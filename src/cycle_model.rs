//! Cycle-accurate / bit-accurate Union-Find co-sim model (Hardware_Mapping H12).
//!
//! This is **not** Verilog. It re-implements growth → merge → forest → peel on a
//! cloned [`DecoderGraph`] with an explicit global schedule matching the software
//! decoder’s `(step_growth, step_merge)` loop, plus Helios-style accounting:
//! - **1 growth cycle** per parallel grow stage (Helios: all PEs grow in one cycle).
//! - **1 merge round** per software `step_merge` (full solidify+union pass).
//!   Helios may need multiple PE cycles for cid/`st_odd` floods; those micro-cycles
//!   are *not* claimed here — only controller rounds that match Aether software.
//! - **peel_ops**: one per leaf processed in the peel queue.
//!
//! Bit-accuracy: corrections must equal [`DecoderGraph::decode`] on the same
//! initial syndrome/DSU state (validated in tests).

use crate::engine::DecodeError;
use crate::graph::DecoderGraph;
use crate::types::{EdgeId, EdgeState};

/// Cycle / stage counters for one shot.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CycleStats {
    /// Parallel growth stages executed (= Helios growth cycles).
    pub growth_cycles: u64,
    /// Software-equivalent merge passes (`step_merge`).
    pub merge_rounds: u64,
    /// `(growth, merge)` controller iterations until neutral.
    pub controller_iters: u64,
    /// Leaves processed during peel.
    pub peel_ops: u64,
    /// Solid edges after neutralization.
    pub solid_edges: u64,
}

/// Bit-accurate decode with cycle accounting.
#[derive(Clone, Debug)]
pub struct CosimResult {
    pub corrections: Vec<EdgeId>,
    pub stats: CycleStats,
}

/// Run the co-sim schedule on a **clone** of `graph`; `graph` is left unchanged.
pub fn decode_cosim(graph: &DecoderGraph) -> Result<CosimResult, DecodeError> {
    let mut g = graph.clone();
    decode_cosim_inplace(&mut g)
}

/// Run co-sim mutating `g` (same final solid/DSU state as [`DecoderGraph::decode`]).
pub fn decode_cosim_inplace(g: &mut DecoderGraph) -> Result<CosimResult, DecodeError> {
    let mut stats = CycleStats::default();
    let limit = cosim_iteration_limit(g);

    while g.total_active_parity > 0 {
        if stats.controller_iters >= limit {
            return Err(DecodeError::IterationLimit {
                steps: stats.controller_iters as usize,
            });
        }
        let grew = cosim_step_growth(g);
        stats.growth_cycles += 1;

        let merged = cosim_step_merge(g);
        stats.merge_rounds += 1;
        stats.controller_iters += 1;

        if !grew && !merged {
            return Err(DecodeError::Unsolvable {
                steps: stats.controller_iters as usize,
                remaining_odd: g.total_active_parity,
            });
        }
    }

    stats.solid_edges = g
        .state
        .iter()
        .filter(|s| **s == EdgeState::Solid)
        .count() as u64;

    let (corrections, peel_ops) = peel_cosim_stats(g);
    stats.peel_ops = peel_ops;

    Ok(CosimResult {
        corrections,
        stats,
    })
}

/// Peel a neutralized graph; corrections + peel_ops match RTL / M45 goldens.
pub fn peel_cosim_stats(g: &DecoderGraph) -> (Vec<EdgeId>, u64) {
    let forest = g.extract_forest();
    cosim_peel(g, &forest)
}

fn cosim_iteration_limit(g: &DecoderGraph) -> u64 {
    let weight_sum: u64 = g.capacity.iter().map(|&c| c as u64).sum();
    weight_sum
        .saturating_add(g.num_edges() as u64)
        .saturating_add(1)
        .max(1)
}

/// Identical predicate to [`DecoderGraph::step_growth`].
fn cosim_step_growth(g: &mut DecoderGraph) -> bool {
    let m = g.num_edges();
    let mut progressed = false;
    for e in 0..m {
        if g.state[e] == EdgeState::Solid {
            continue;
        }
        let u = g.edge_u[e];
        let v = g.edge_v[e];
        let r_u = g.find(u);
        let r_v = g.find(v);
        if r_u == r_v {
            continue;
        }
        let delta = u32::from(g.cluster_is_active(r_u)) + u32::from(g.cluster_is_active(r_v));
        if delta == 0 {
            continue;
        }
        g.growth[e] = g.growth[e].saturating_add(delta);
        progressed = true;
    }
    progressed
}

/// Identical to [`DecoderGraph::step_merge`].
fn cosim_step_merge(g: &mut DecoderGraph) -> bool {
    let m = g.num_edges();
    let mut progressed = false;
    for e in 0..m {
        if g.state[e] != EdgeState::Empty {
            continue;
        }
        if g.growth[e] >= g.capacity[e] {
            g.state[e] = EdgeState::Solid;
            let u = g.edge_u[e];
            let v = g.edge_v[e];
            g.union(u, v);
            progressed = true;
        }
    }
    progressed
}

/// Peel with op counting; same rule as [`DecoderGraph::peel`].
fn cosim_peel(
    g: &DecoderGraph,
    forest: &[Vec<(crate::types::NodeId, EdgeId)>],
) -> (Vec<EdgeId>, u64) {
    // Delegate to graph peel for bit-identity of the correction list, but count
    // degree-1 enqueue events the same way the peel FSM walks the queue.
    // Re-running the peel logic here keeps the co-sim self-contained for RTL porting.
    use std::collections::VecDeque;

    let n = g.num_nodes();
    let peel_root = component_peel_roots(g, forest);
    let mut current_syndrome = g.syndrome.clone();
    let mut remaining: Vec<u32> = forest.iter().map(|nbrs| nbrs.len() as u32).collect();
    let mut peeled_edge = vec![false; g.num_edges()];
    let mut queue = VecDeque::new();
    let mut peel_ops = 0u64;

    for (v, &deg) in remaining.iter().enumerate() {
        if deg == 1 && v != peel_root[v] {
            queue.push_back(v);
        }
    }

    let mut corrections = Vec::new();
    while let Some(u) = queue.pop_front() {
        if remaining[u] == 0 || u == peel_root[u] {
            continue;
        }
        let Some((p, e)) = unique_unpeeled_neighbor(forest, u, &peeled_edge) else {
            continue;
        };
        peel_ops += 1;
        peeled_edge[e] = true;
        remaining[u] = remaining[u].saturating_sub(1);

        if current_syndrome[u] == 1 {
            corrections.push(e);
        }
        current_syndrome[p] ^= current_syndrome[u];
        current_syndrome[u] = 0;

        remaining[p] = remaining[p].saturating_sub(1);
        if remaining[p] == 1 && p != peel_root[p] {
            queue.push_back(p);
        }
    }

    debug_assert_eq!(
        n,
        forest.len(),
        "forest length must match node count"
    );
    (corrections, peel_ops)
}

fn unique_unpeeled_neighbor(
    forest: &[Vec<(crate::types::NodeId, EdgeId)>],
    u: crate::types::NodeId,
    peeled_edge: &[bool],
) -> Option<(crate::types::NodeId, EdgeId)> {
    // Match `peeling.rs` exactly (including early-return-on-second behavior).
    let mut found = None;
    for &(p, e) in &forest[u] {
        if !peeled_edge[e] {
            if found.is_some() {
                return found;
            }
            found = Some((p, e));
        }
    }
    found
}

fn component_peel_roots(
    graph: &DecoderGraph,
    forest: &[Vec<(crate::types::NodeId, EdgeId)>],
) -> Vec<crate::types::NodeId> {
    let n = graph.num_nodes();
    let mut seen = vec![false; n];
    let mut peel_root = vec![0; n];
    for start in 0..n {
        if seen[start] {
            continue;
        }
        let mut comp = Vec::new();
        let mut stack = vec![start];
        seen[start] = true;
        while let Some(u) = stack.pop() {
            comp.push(u);
            for &(w, _) in &forest[u] {
                if !seen[w] {
                    seen[w] = true;
                    stack.push(w);
                }
            }
        }
        let mut root = None;
        for &v in &comp {
            if graph.is_boundary[v] == 1 {
                root = Some(v);
                break;
            }
        }
        let root = root.unwrap_or_else(|| {
            comp.iter()
                .copied()
                .find(|&v| forest[v].len() == 1)
                .unwrap_or(comp[0])
        });
        for &v in &comp {
            peel_root[v] = root;
        }
    }
    peel_root
}

/// Why bit-identical co-sim failed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CosimMismatch {
    Decode(DecodeError),
    CorrectionsDiffer {
        expected: Vec<EdgeId>,
        got: Vec<EdgeId>,
    },
    IterationCount {
        reference_steps: u64,
        cosim_iters: u64,
    },
}

impl From<DecodeError> for CosimMismatch {
    fn from(value: DecodeError) -> Self {
        CosimMismatch::Decode(value)
    }
}

/// Compare reference [`DecoderGraph::decode`] vs co-sim on the same initial graph.
pub fn assert_bit_identical(graph: &DecoderGraph) -> Result<CycleStats, CosimMismatch> {
    let mut reference = graph.clone();
    let expected = reference.decode()?;
    let CosimResult {
        corrections: got,
        stats,
    } = decode_cosim(graph)?;
    if got != expected {
        return Err(CosimMismatch::CorrectionsDiffer { expected, got });
    }
    let mut ref2 = graph.clone();
    let ref_steps = ref2.decode_to_neutral()? as u64;
    if stats.controller_iters != ref_steps {
        return Err(CosimMismatch::IterationCount {
            reference_steps: ref_steps,
            cosim_iters: stats.controller_iters,
        });
    }
    Ok(stats)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compiled::{CompiledUfDecoder, GraphlikeError};
    use crate::graph::DecoderGraph;

    #[test]
    fn cosim_matches_blueprint_two_node() {
        let edges = [(0, 1, 10u32)];
        let g = DecoderGraph::from_syndrome_and_edges(&[1, 1], &edges).unwrap();
        let stats = assert_bit_identical(&g).unwrap();
        assert_eq!(stats.growth_cycles, 5);
        assert_eq!(stats.controller_iters, 5);
        assert_eq!(stats.merge_rounds, 5);
    }

    #[test]
    fn cosim_matches_line_and_boundary_star() {
        let line = [(0, 1, 10u32), (1, 2, 10u32)];
        let g = DecoderGraph::from_syndrome_and_edges(&[1, 0, 1], &line).unwrap();
        assert_bit_identical(&g).unwrap();

        let mut star = DecoderGraph::new(3);
        star.set_syndrome(0, 1).unwrap();
        star.mark_boundary(1).unwrap();
        star.mark_boundary(2).unwrap();
        star.add_edge(0, 1, 10).unwrap();
        star.add_edge(0, 2, 10).unwrap();
        assert_bit_identical(&star).unwrap();
    }

    #[test]
    fn cosim_matches_compiled_boundary_observable() {
        let err = GraphlikeError {
            detectors: vec![0],
            probability: 0.1,
            observables: vec![0],
        };
        let mut dec = CompiledUfDecoder::compile(1, 1, &[err], 100.0).unwrap();
        dec.load_detection_events(&[1]).unwrap();
        let soft = dec.decode_observables(&[1]).unwrap();

        dec.load_detection_events(&[1]).unwrap();
        let cosim = decode_cosim(dec.graph()).unwrap();
        let mut acc = 0u64;
        for &e in &cosim.corrections {
            acc ^= dec.graph().obs_mask[e];
        }
        let cosim_obs = vec![(acc & 1) as u8];
        assert_eq!(soft, cosim_obs);
        assert!(cosim.stats.growth_cycles > 0);
    }
}
