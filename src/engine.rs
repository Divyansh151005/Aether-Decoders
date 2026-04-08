//! Discrete cluster-growth engine.
//!
//! Replaces \(\frac{dg(e)}{dt} = \frac12 \sum_{C\text{ odd}} 1_{e \in \delta(C)}\)
//! with integer increments on doubled capacities. Intra-cluster edges
//! (`find(u) == find(v)`) are skipped: Delfosse–Nickerson growth is a
//! boundary process, not an interior one.

use crate::graph::DecoderGraph;
use crate::types::EdgeState;

/// Why growth failed to neutralize the syndrome.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DecodeError {
    /// Odd parity remains but no empty boundary edge can grow or merge
    /// (disconnected odd component).
    Unsolvable { steps: usize, remaining_odd: usize },
    /// Safety cutoff (should not fire on a finite connected instance).
    IterationLimit { steps: usize },
}

impl DecoderGraph {
    /// One simultaneous half-edge (integer `+1` per odd endpoint cluster).
    ///
    /// Returns `true` if any `growth` counter increased.
    pub fn step_growth(&mut self) -> bool {
        let m = self.num_edges();
        let mut progressed = false;
        for e in 0..m {
            if self.state[e] == EdgeState::Solid {
                continue;
            }
            let u = self.edge_u[e];
            let v = self.edge_v[e];
            let r_u = self.find(u);
            let r_v = self.find(v);
            if r_u == r_v {
                continue;
            }
            let delta = u32::from(self.cluster_is_active(r_u))
                + u32::from(self.cluster_is_active(r_v));
            if delta == 0 {
                continue;
            }
            self.growth[e] = self.growth[e].saturating_add(delta);
            progressed = true;
        }
        progressed
    }

    /// Promote fully grown empty edges to `Solid` and union their endpoints.
    ///
    /// Returns `true` if any edge became solid.
    pub fn step_merge(&mut self) -> bool {
        let m = self.num_edges();
        let mut progressed = false;
        for e in 0..m {
            if self.state[e] != EdgeState::Empty {
                continue;
            }
            if self.growth[e] >= self.capacity[e] {
                self.state[e] = EdgeState::Solid;
                let u = self.edge_u[e];
                let v = self.edge_v[e];
                self.union(u, v);
                progressed = true;
            }
        }
        progressed
    }

    /// Grow and merge until every cluster is even.
    ///
    /// Returns the number of `(growth, merge)` iterations. Test 1 expects `5`
    /// on a weight-10 edge between two defects (\(\Delta g = 2\)).
    pub fn decode_to_neutral(&mut self) -> Result<usize, DecodeError> {
        let mut steps = 0usize;
        let limit = self.iteration_limit();
        while self.total_active_parity > 0 {
            if steps >= limit {
                return Err(DecodeError::IterationLimit { steps });
            }
            let grew = self.step_growth();
            let merged = self.step_merge();
            steps += 1;
            if !grew && !merged {
                return Err(DecodeError::Unsolvable {
                    steps,
                    remaining_odd: self.total_active_parity,
                });
            }
        }
        Ok(steps)
    }

    fn iteration_limit(&self) -> usize {
        let weight_sum: u64 = self.capacity.iter().map(|&c| c as u64).sum();
        (weight_sum as usize)
            .saturating_add(self.num_edges())
            .saturating_add(1)
            .max(1)
    }
}
