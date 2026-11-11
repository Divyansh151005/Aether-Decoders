//! Relay-BP for qLDPC / hypergraph DEMs (Müller et al., arXiv:2506.01779).
//!
//! Implements min-sum **DMem-BP** (eqs. 1–4) and **Relay-BP-S** (Section III).
//! Do **not** use `Docs/Equations_Theory` §5: that pins γ ∈ (0,1) and tanh BP.
//! Here γ_j may be negative; check updates are min-sum, not sum-product.
//!
//! Sign convention (paper): positive LLR ⇒ no error preferred; HD(M) = 1 iff M ≤ 0
//! (IBM reference hard decision; paper's sgn(0) is ambiguous, ≤0 is the used rule).


/// Sparse Tanner / decoding graph: checks × variables (CSR both ways).
#[derive(Clone, Debug)]
pub struct TannerGraph {
    pub num_checks: usize,
    pub num_vars: usize,
    /// CSR: for each check, neighboring variable indices.
    check_ptr: Vec<usize>,
    check_vars: Vec<usize>,
    /// CSR: for each variable, neighboring check indices.
    var_ptr: Vec<usize>,
    var_checks: Vec<usize>,
    /// Parallel to `check_vars`: index into the variable-oriented edge list.
    check_to_var_edge: Vec<usize>,
    /// Parallel to `var_checks`: index into the check-oriented edge list.
    var_to_check_edge: Vec<usize>,
}

impl TannerGraph {
    /// Build from a list of columns: `columns[j]` = detector indices flipped by error j.
    pub fn from_columns(num_checks: usize, columns: &[Vec<usize>]) -> Result<Self, RelayError> {
        let num_vars = columns.len();
        let mut check_adj: Vec<Vec<usize>> = vec![Vec::new(); num_checks];
        for (j, col) in columns.iter().enumerate() {
            let mut parity = vec![0u8; num_checks];
            for &i in col {
                if i >= num_checks {
                    return Err(RelayError::CheckOutOfRange {
                        check: i,
                        n: num_checks,
                    });
                }
                parity[i] ^= 1;
            }
            for (i, bit) in parity.iter().enumerate() {
                if *bit != 0 {
                    check_adj[i].push(j);
                }
            }
        }

        let mut check_ptr = Vec::with_capacity(num_checks + 1);
        let mut check_vars = Vec::new();
        check_ptr.push(0);
        for neighbors in &check_adj {
            check_vars.extend(neighbors.iter().copied());
            check_ptr.push(check_vars.len());
        }

        let mut var_adj: Vec<Vec<usize>> = vec![Vec::new(); num_vars];
        for (i, neighbors) in check_adj.iter().enumerate() {
            for &j in neighbors {
                var_adj[j].push(i);
            }
        }
        let mut var_ptr = Vec::with_capacity(num_vars + 1);
        let mut var_checks = Vec::new();
        var_ptr.push(0);
        for neighbors in &var_adj {
            var_checks.extend(neighbors.iter().copied());
            var_ptr.push(var_checks.len());
        }

        let n_edges = check_vars.len();
        let mut check_to_var_edge = vec![0usize; n_edges];
        let mut var_to_check_edge = vec![0usize; n_edges];
        for i in 0..num_checks {
            for e in check_ptr[i]..check_ptr[i + 1] {
                let j = check_vars[e];
                let mut found = None;
                for ev in var_ptr[j]..var_ptr[j + 1] {
                    if var_checks[ev] == i {
                        found = Some(ev);
                        break;
                    }
                }
                let ev = found.ok_or(RelayError::InternalEdgeMap)?;
                check_to_var_edge[e] = ev;
                var_to_check_edge[ev] = e;
            }
        }

        Ok(Self {
            num_checks,
            num_vars,
            check_ptr,
            check_vars,
            var_ptr,
            var_checks,
            check_to_var_edge,
            var_to_check_edge,
        })
    }
}

/// Why Relay-BP cannot run or compile.
#[derive(Clone, Debug, PartialEq)]
pub enum RelayError {
    CheckOutOfRange { check: usize, n: usize },
    SyndromeLen { got: usize, expected: usize },
    PriorLen { got: usize, expected: usize },
    GammaLen { got: usize, expected: usize },
    ObservableLen { got: usize, expected: usize },
    BadProbability { p: f64 },
    InternalEdgeMap,
    Empty,
}

/// Log-likelihood prior λ_j(0) = ln((1−p)/p).
pub fn log_prior(p: f64) -> Result<f64, RelayError> {
    if !(p > 0.0 && p < 1.0) {
        return Err(RelayError::BadProbability { p });
    }
    Ok(((1.0 - p) / p).ln())
}

/// Seeded SplitMix64 for disordered γ draws (no external RNG dependency).
///
/// The stream is not reset between `RelayBp::decode` calls, so γ draws depend on
/// shot order within one process.
#[derive(Clone, Debug)]
pub struct SeedRng {
    state: u64,
}

impl SeedRng {
    /// SplitMix64 has no forbidden state, so every seed maps to a distinct stream.
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next_u64(&mut self) -> u64 {
        // SplitMix64
        self.state = self.state.wrapping_add(0x9E3779B97F4A7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
        z ^ (z >> 31)
    }

    /// Uniform in [lo, hi).
    pub fn uniform(&mut self, lo: f64, hi: f64) -> f64 {
        let u = (self.next_u64() >> 11) as f64 / ((1u64 << 53) as f64);
        lo + (hi - lo) * u
    }
}

/// One DMem-BP run (paper §II).
#[derive(Clone, Debug)]
pub struct DMemBp {
    graph: TannerGraph,
    /// λ_j(0) channel priors.
    log_priors: Vec<f64>,
    /// Per-variable memory strengths γ_j (may be negative).
    gammas: Vec<f64>,
    /// Current bias Λ_j(t).
    bias: Vec<f64>,
    /// Marginals M_j.
    marginals: Vec<f64>,
    /// μ_{i→j} stored in check-oriented edge order.
    mu: Vec<f64>,
    /// ν_{j→i} stored in variable-oriented edge order.
    nu: Vec<f64>,
    /// Hard decision.
    hat_e: Vec<u8>,
    max_iter: usize,
}

impl DMemBp {
    pub fn new(
        graph: TannerGraph,
        log_priors: Vec<f64>,
        gammas: Vec<f64>,
        max_iter: usize,
    ) -> Result<Self, RelayError> {
        if graph.num_vars == 0 || graph.num_checks == 0 {
            return Err(RelayError::Empty);
        }
        if log_priors.len() != graph.num_vars {
            return Err(RelayError::PriorLen {
                got: log_priors.len(),
                expected: graph.num_vars,
            });
        }
        if gammas.len() != graph.num_vars {
            return Err(RelayError::GammaLen {
                got: gammas.len(),
                expected: graph.num_vars,
            });
        }
        let n_edges = graph.check_vars.len();
        Ok(Self {
            bias: log_priors.clone(),
            marginals: log_priors.clone(),
            log_priors,
            gammas,
            mu: vec![0.0; n_edges],
            nu: vec![0.0; n_edges],
            hat_e: vec![0; graph.num_vars],
            graph,
            max_iter,
        })
    }

    pub fn set_gammas(&mut self, gammas: Vec<f64>) -> Result<(), RelayError> {
        if gammas.len() != self.graph.num_vars {
            return Err(RelayError::GammaLen {
                got: gammas.len(),
                expected: self.graph.num_vars,
            });
        }
        self.gammas = gammas;
        Ok(())
    }

    /// Initialize ν ← λ(0); μ ← 0; optionally set M(0) from caller (relay handoff).
    pub fn init_messages(&mut self, initial_marginals: Option<&[f64]>) -> Result<(), RelayError> {
        if let Some(m) = initial_marginals {
            if m.len() != self.graph.num_vars {
                return Err(RelayError::PriorLen {
                    got: m.len(),
                    expected: self.graph.num_vars,
                });
            }
            self.marginals.copy_from_slice(m);
        } else {
            self.marginals.copy_from_slice(&self.log_priors);
        }
        self.bias.copy_from_slice(&self.log_priors);
        for j in 0..self.graph.num_vars {
            let lp = self.log_priors[j];
            for e in self.graph.var_ptr[j]..self.graph.var_ptr[j + 1] {
                self.nu[e] = lp;
            }
        }
        self.mu.fill(0.0);
        Ok(())
    }

    /// Paper eq. (4): Λ_j(t) = (1−γ_j) λ_j(0) + γ_j M_j(t−1).
    fn update_bias(&mut self) {
        for j in 0..self.graph.num_vars {
            let g = self.gammas[j];
            self.bias[j] = (1.0 - g) * self.log_priors[j] + g * self.marginals[j];
        }
    }

    /// Paper eq. (1): min-sum check-to-variable with syndrome sign.
    fn update_check_to_var(&mut self, syndrome: &[u8]) {
        for i in 0..self.graph.num_checks {
            let start = self.graph.check_ptr[i];
            let end = self.graph.check_ptr[i + 1];
            let deg = end - start;
            if deg == 0 {
                continue;
            }
            // Syndrome factor (−1)^{σ_i}: σ=1 flips overall sign.
            let synd_neg = syndrome[i] != 0;

            if deg == 1 {
                // Empty min over the other neighbors saturates (IBM `relay_bp` min_sum.rs
                // seeds both minima with max_value), so the check forces its only variable.
                self.mu[start] = if synd_neg { -f64::MAX } else { f64::MAX };
                continue;
            }

            // Magnitudes and signs of incoming ν (variable-oriented indices).
            let mut min1 = f64::INFINITY;
            let mut min2 = f64::INFINITY;
            let mut sign_prod_neg = synd_neg; // XOR of negative ν signs, then syndrome
            for e in start..end {
                let ev = self.graph.check_to_var_edge[e];
                let v = self.nu[ev];
                let a = v.abs();
                if a < min1 {
                    min2 = min1;
                    min1 = a;
                } else if a < min2 {
                    min2 = a;
                }
                if v < 0.0 {
                    sign_prod_neg = !sign_prod_neg;
                }
            }

            for e in start..end {
                let ev = self.graph.check_to_var_edge[e];
                let v = self.nu[ev];
                let a = v.abs();
                // Exclude self: if this edge held the unique min, use second min.
                let mag = if a == min1 { min2 } else { min1 };
                let mut out_neg = sign_prod_neg;
                if v < 0.0 {
                    out_neg = !out_neg; // remove self from product sign
                }
                self.mu[e] = if out_neg { -mag } else { mag };
            }
        }
    }

    /// Paper eqs. (2)–(3): variable-to-check and marginals.
    fn update_var_to_check(&mut self) {
        for j in 0..self.graph.num_vars {
            let start = self.graph.var_ptr[j];
            let end = self.graph.var_ptr[j + 1];
            let mut total = self.bias[j];
            for e in start..end {
                let ec = self.graph.var_to_check_edge[e];
                total += self.mu[ec];
            }
            self.marginals[j] = total;
            // ν_{j→i} = Λ_j + Σ_{i'≠i} μ_{i'→j} = total − μ_{i→j}
            for e in start..end {
                let ec = self.graph.var_to_check_edge[e];
                self.nu[e] = total - self.mu[ec];
            }
            self.hat_e[j] = if total <= 0.0 { 1 } else { 0 };
        }
    }

    fn syndrome_satisfied(&self, syndrome: &[u8]) -> bool {
        let mut pred = vec![0u8; self.graph.num_checks];
        for j in 0..self.graph.num_vars {
            if self.hat_e[j] == 0 {
                continue;
            }
            for e in self.graph.var_ptr[j]..self.graph.var_ptr[j + 1] {
                let i = self.graph.var_checks[e];
                pred[i] ^= 1;
            }
        }
        pred.as_slice() == syndrome
    }

    /// Run up to `max_iter` iterations. Returns iterations used and whether Hê = σ.
    pub fn run(&mut self, syndrome: &[u8]) -> Result<(usize, bool), RelayError> {
        if syndrome.len() != self.graph.num_checks {
            return Err(RelayError::SyndromeLen {
                got: syndrome.len(),
                expected: self.graph.num_checks,
            });
        }
        for t in 1..=self.max_iter {
            self.update_bias();
            self.update_check_to_var(syndrome);
            self.update_var_to_check();
            if self.syndrome_satisfied(syndrome) {
                return Ok((t, true));
            }
        }
        Ok((self.max_iter, false))
    }

    pub fn hat_e(&self) -> &[u8] {
        &self.hat_e
    }

    pub fn marginals(&self) -> &[f64] {
        &self.marginals
    }

    pub fn solution_weight(&self) -> f64 {
        self.hat_e
            .iter()
            .zip(self.log_priors.iter())
            .map(|(&e, &lp)| if e != 0 { lp } else { 0.0 })
            .sum()
    }
}

/// Relay-BP-S configuration (paper §III).
#[derive(Clone, Debug)]
pub struct RelayConfig {
    /// Solutions sought (S). Stop early once this many valid corrections are found.
    pub stop_nconv: usize,
    /// Max relay legs after the first (R − 1 in paper; total legs = 1 + num_sets).
    pub num_sets: usize,
    /// Iterations for first leg (T_0).
    pub pre_iter: usize,
    /// Iterations for subsequent legs (T_r).
    pub set_max_iter: usize,
    /// Uniform γ for first leg (Mem-BP); paper uses e.g. 0.125 / 0.35.
    pub gamma0: f64,
    /// Disordered γ interval for later legs [lo, hi).
    pub gamma_dist_interval: (f64, f64),
    /// RNG seed for disordered γ.
    pub seed: u64,
}

impl Default for RelayConfig {
    fn default() -> Self {
        Self {
            stop_nconv: 1,
            num_sets: 40,
            pre_iter: 80,
            set_max_iter: 60,
            gamma0: 0.125,
            gamma_dist_interval: (-0.24, 0.66),
            seed: 1,
        }
    }
}

/// Result of Relay-BP-S.
#[derive(Clone, Debug)]
pub struct RelayResult {
    pub success: bool,
    pub hat_e: Vec<u8>,
    pub weight: f64,
    pub iterations: usize,
    pub legs_run: usize,
    pub solutions_found: usize,
}

/// Relay-BP-S decoder over a fixed Tanner graph and priors.
#[derive(Clone, Debug)]
pub struct RelayBp {
    dmem: DMemBp,
    config: RelayConfig,
    rng: SeedRng,
}

impl RelayBp {
    pub fn new(
        graph: TannerGraph,
        probabilities: &[f64],
        config: RelayConfig,
    ) -> Result<Self, RelayError> {
        let mut log_priors = Vec::with_capacity(probabilities.len());
        for &p in probabilities {
            log_priors.push(log_prior(p)?);
        }
        let n = graph.num_vars;
        let gammas = vec![config.gamma0; n];
        let dmem = DMemBp::new(graph, log_priors, gammas, config.pre_iter)?;
        let rng = SeedRng::new(config.seed);
        Ok(Self { dmem, config, rng })
    }

    fn sample_gammas(&mut self) -> Vec<f64> {
        let (lo, hi) = self.config.gamma_dist_interval;
        let n = self.dmem.graph.num_vars;
        (0..n).map(|_| self.rng.uniform(lo, hi)).collect()
    }

    pub fn decode(&mut self, syndrome: &[u8]) -> Result<RelayResult, RelayError> {
        let n = self.dmem.graph.num_vars;
        let gamma0 = vec![self.config.gamma0; n];
        self.dmem.set_gammas(gamma0)?;
        self.dmem.max_iter = self.config.pre_iter;
        self.dmem.init_messages(None)?;

        let mut best_e: Option<Vec<u8>> = None;
        let mut best_w = f64::INFINITY;
        let mut total_iters = 0usize;
        let mut solutions = 0usize;
        let mut legs = 0usize;

        let (it, ok) = self.dmem.run(syndrome)?;
        total_iters += it;
        legs += 1;
        if ok {
            solutions += 1;
            let w = self.dmem.solution_weight();
            best_w = w;
            best_e = Some(self.dmem.hat_e().to_vec());
            if solutions >= self.config.stop_nconv {
                return Ok(RelayResult {
                    success: true,
                    hat_e: best_e.unwrap(),
                    weight: best_w,
                    iterations: total_iters,
                    legs_run: legs,
                    solutions_found: solutions,
                });
            }
        }

        let mut handoff = self.dmem.marginals().to_vec();
        for _set in 1..=self.config.num_sets {
            let gammas = self.sample_gammas();
            self.dmem.set_gammas(gammas)?;
            self.dmem.max_iter = self.config.set_max_iter;
            // Relay: keep previous marginals; refresh messages from priors (paper + IBM).
            self.dmem.init_messages(Some(&handoff))?;
            let (it, ok) = self.dmem.run(syndrome)?;
            total_iters += it;
            legs += 1;
            handoff.copy_from_slice(self.dmem.marginals());
            if ok {
                solutions += 1;
                let w = self.dmem.solution_weight();
                if w < best_w {
                    best_w = w;
                    best_e = Some(self.dmem.hat_e().to_vec());
                }
                if solutions >= self.config.stop_nconv {
                    break;
                }
            }
        }

        match best_e {
            Some(hat_e) => Ok(RelayResult {
                success: true,
                hat_e,
                weight: best_w,
                iterations: total_iters,
                legs_run: legs,
                solutions_found: solutions,
            }),
            None => Ok(RelayResult {
                success: false,
                hat_e: self.dmem.hat_e().to_vec(),
                weight: f64::INFINITY,
                iterations: total_iters,
                legs_run: legs,
                solutions_found: 0,
            }),
        }
    }
}

/// Apply ê to observables: for each variable j with ê_j=1, XOR its observable mask.
pub fn observables_from_errors(hat_e: &[u8], obs_masks: &[u64], num_observables: usize) -> Vec<u8> {
    let mut mask = 0u64;
    for (j, &e) in hat_e.iter().enumerate() {
        if e != 0 {
            mask ^= obs_masks[j];
        }
    }
    (0..num_observables)
        .map(|k| ((mask >> k) & 1) as u8)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repetition_graph() -> TannerGraph {
        // H = [[1,1,0],[0,1,1]]
        TannerGraph::from_columns(2, &[vec![0], vec![0, 1], vec![1]]).unwrap()
    }

    #[test]
    fn minsum_repetition_single_errors() {
        let g = repetition_graph();
        let priors = vec![0.003, 0.003, 0.003];
        let lp: Vec<f64> = priors.iter().map(|&p| log_prior(p).unwrap()).collect();
        // γ = 0 ⇒ standard min-sum BP
        let mut bp = DMemBp::new(g, lp, vec![0.0; 3], 20).unwrap();

        let cases: &[(&[u8], &[u8])] = &[
            (&[0, 0], &[0, 0, 0]),
            (&[1, 0], &[1, 0, 0]),
            (&[1, 1], &[0, 1, 0]),
            (&[0, 1], &[0, 0, 1]),
        ];
        for &(syn, expect) in cases {
            bp.init_messages(None).unwrap();
            let (it, ok) = bp.run(syn).unwrap();
            assert!(ok, "syn={syn:?} failed after {it}");
            assert_eq!(bp.hat_e(), expect, "syn={syn:?}");
        }
    }

    #[test]
    fn membp_uniform_gamma_still_decodes_repetition() {
        let g = repetition_graph();
        let lp: Vec<f64> = (0..3).map(|_| log_prior(0.003).unwrap()).collect();
        let mut bp = DMemBp::new(g, lp, vec![0.125; 3], 40).unwrap();
        bp.init_messages(None).unwrap();
        let (_, ok) = bp.run(&[1, 1]).unwrap();
        assert!(ok);
        assert_eq!(bp.hat_e(), &[0, 1, 0]);
    }

    #[test]
    fn negative_gamma_is_accepted() {
        let g = repetition_graph();
        let lp: Vec<f64> = (0..3).map(|_| log_prior(0.003).unwrap()).collect();
        let mut bp = DMemBp::new(g, lp, vec![-0.2, 0.5, -0.1], 40).unwrap();
        bp.init_messages(None).unwrap();
        let (_, ok) = bp.run(&[1, 0]).unwrap();
        assert!(ok);
        assert_eq!(bp.hat_e(), &[1, 0, 0]);
    }

    #[test]
    fn relay_bp_repetition() {
        let g = repetition_graph();
        let mut cfg = RelayConfig::default();
        cfg.num_sets = 5;
        cfg.pre_iter = 20;
        cfg.set_max_iter = 20;
        cfg.stop_nconv = 1;
        let mut relay = RelayBp::new(g, &[0.003, 0.003, 0.003], cfg).unwrap();
        let r = relay.decode(&[1, 1]).unwrap();
        assert!(r.success);
        assert_eq!(r.hat_e, vec![0, 1, 0]);
    }

    #[test]
    fn seed_rng_even_and_odd_seeds_differ() {
        for k in 0..8u64 {
            let mut a = SeedRng::new(2 * k);
            let mut b = SeedRng::new(2 * k + 1);
            assert_ne!(a.next_u64(), b.next_u64(), "seeds {} and {}", 2 * k, 2 * k + 1);
        }
    }

    #[test]
    fn seed_rng_odd_seed_stream_is_unchanged() {
        // Odd seeds were already used as-is (`seed | 1 == seed`), so seed=1 runs
        // (M14–M29 bake-offs) keep the same γ draws.
        let mut rng = SeedRng::new(1);
        let mut state = 1u64;
        for _ in 0..4 {
            state = state.wrapping_add(0x9E3779B97F4A7C15);
            let mut z = state;
            z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
            assert_eq!(rng.next_u64(), z ^ (z >> 31));
        }
    }

    #[test]
    fn degree_one_check_forces_its_variable() {
        // c0 = {v0}, c1 = {v0, v1}; σ = [1, 1] has the unique solution e = [1, 0].
        let g = TannerGraph::from_columns(2, &[vec![0, 1], vec![1]]).unwrap();
        let lp = vec![log_prior(0.4).unwrap(), log_prior(0.001).unwrap()];
        let mut bp = DMemBp::new(g, lp, vec![0.0; 2], 10).unwrap();
        bp.init_messages(None).unwrap();
        let (_, ok) = bp.run(&[1, 1]).unwrap();
        assert!(ok);
        assert_eq!(bp.hat_e(), &[1, 0]);

        bp.init_messages(None).unwrap();
        let (_, ok) = bp.run(&[0, 1]).unwrap();
        assert!(ok);
        assert_eq!(bp.hat_e(), &[0, 1]);
    }
}
