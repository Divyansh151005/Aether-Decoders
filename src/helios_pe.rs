//! Helios-style PE grow/merge cycle model (M17).
//!
//! References:
//! - Maurya et al., Helios, arXiv:2406.08491 / yale-paragon/Helios_scalable_QEC
//!   (`STAGE_GROW_BOUNDARY`, cluster spread, `odd && !touching_boundary` active).
//! - Aether locked rules: skip same-root growth; union-by-size; unique boundaries.
//!
//! This module is a **cycle-accurate PE scheduler** for growth + merge (cid/odd
//! flood micro-cycles counted). It is **not** a copy of Helios Verilog.
//!
//! Golden check: after neutralization, the **solid-edge set** and growth
//! iteration count match [`DecoderGraph::decode_to_neutral`]. Peel stays in
//! software (`cycle_model` / `DecoderGraph::peel`) so corrections remain
//! bit-identical to M16.

use crate::engine::DecodeError;
use crate::graph::DecoderGraph;
use crate::types::{EdgeId, EdgeState, NodeId};

/// PE / controller cycle stats for Helios-style scheduling.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HeliosPeStats {
    /// Parallel growth stages (1 cycle each, Helios `STAGE_GROW_BOUNDARY`).
    pub growth_cycles: u64,
    /// Software merge solidify+union passes.
    pub merge_solidify_rounds: u64,
    /// Extra PE cycles spent flooding cid + odd/boundary after merges.
    pub flood_cycles: u64,
    /// Controller iterations of (grow → solidify → flood) until inactive.
    pub controller_iters: u64,
}

#[derive(Clone, Debug)]
pub struct HeliosPeResult {
    /// Edges that are Solid after neutralization (same order as graph edges).
    pub solid: Vec<bool>,
    pub stats: HeliosPeStats,
}

/// Run Helios-style PE grow/merge on a clone; leave `graph` unchanged.
pub fn neutralize_helios_pe(graph: &DecoderGraph) -> Result<HeliosPeResult, DecodeError> {
    let mut g = graph.clone();
    neutralize_helios_pe_inplace(&mut g)
}

/// Mutating PE schedule. Uses Aether [`DecoderGraph::union`] (union-by-size).
pub fn neutralize_helios_pe_inplace(g: &mut DecoderGraph) -> Result<HeliosPeResult, DecodeError> {
    let mut stats = HeliosPeStats::default();
    let limit = iteration_limit(g);

    while g.total_active_parity > 0 {
        if stats.controller_iters >= limit {
            return Err(DecodeError::IterationLimit {
                steps: stats.controller_iters as usize,
            });
        }

        // --- STAGE_GROW_BOUNDARY (1 cycle, all PEs) ---
        let grew = pe_grow_cycle(g);
        stats.growth_cycles += 1;

        // --- Solidify fully grown edges + union-by-size (Aether H5) ---
        let merged = pe_solidify_and_union(g);
        stats.merge_solidify_rounds += 1;

        // --- Helios cid / odd flood micro-cycles (latency only; state from DSU) ---
        stats.flood_cycles += pe_flood_cycle_count(g);

        stats.controller_iters += 1;
        if !grew && !merged {
            return Err(DecodeError::Unsolvable {
                steps: stats.controller_iters as usize,
                remaining_odd: g.total_active_parity,
            });
        }
    }

    let solid: Vec<bool> = g.state.iter().map(|s| *s == EdgeState::Solid).collect();
    Ok(HeliosPeResult { solid, stats })
}

fn iteration_limit(g: &DecoderGraph) -> u64 {
    let weight_sum: u64 = g.capacity.iter().map(|&c| c as u64).sum();
    weight_sum
        .saturating_add(g.num_edges() as u64)
        .saturating_add(1)
        .max(1)
}

/// Helios: grow if odd cluster and not touching boundary (= Aether active).
fn pe_grow_cycle(g: &mut DecoderGraph) -> bool {
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
        // Helios stores growth on lower-id PE; both endpoints may contribute.
        let delta = u32::from(g.cluster_is_active(r_u)) + u32::from(g.cluster_is_active(r_v));
        if delta == 0 {
            continue;
        }
        g.growth[e] = g.growth[e].saturating_add(delta);
        progressed = true;
    }
    progressed
}

fn pe_solidify_and_union(g: &mut DecoderGraph) -> bool {
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

/// Estimate Helios flood cycles after a merge: diameter-style bound on each
/// solid component (cid broadcast + odd convergecast + odd broadcast ≈ 3×hops).
///
/// Uses BFS depth on the solid subgraph. Matches Helios paper’s “broadcast /
/// convergecast / broadcast” structure at the level of hop counts, not LUT
/// timing. Does **not** change decoder state.
fn pe_flood_cycle_count(g: &DecoderGraph) -> u64 {
    let n = g.num_nodes();
    let mut adj: Vec<Vec<NodeId>> = vec![Vec::new(); n];
    for e in 0..g.num_edges() {
        if g.state[e] != EdgeState::Solid {
            continue;
        }
        let u = g.edge_u[e];
        let v = g.edge_v[e];
        adj[u].push(v);
        adj[v].push(u);
    }

    let mut seen = vec![false; n];
    let mut total = 0u64;
    for start in 0..n {
        if seen[start] {
            continue;
        }
        // BFS for eccentricity of an arbitrary start; use max depth as hops.
        let mut q = std::collections::VecDeque::new();
        q.push_back((start, 0u32));
        seen[start] = true;
        let mut max_depth = 0u32;
        let mut comp_size = 0u32;
        while let Some((u, d)) = q.pop_front() {
            comp_size += 1;
            max_depth = max_depth.max(d);
            for &w in &adj[u] {
                if !seen[w] {
                    seen[w] = true;
                    q.push_back((w, d + 1));
                }
            }
        }
        if comp_size <= 1 {
            continue;
        }
        // 3 passes × depth, +1 completion check (Helios FPGA merge bound sketch).
        total = total.saturating_add(u64::from(max_depth).saturating_mul(3).saturating_add(1));
    }
    total
}

/// Why PE solid-set check failed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PeMismatch {
    Decode(DecodeError),
    SolidEdgesDiffer,
    GrowthIters {
        software: u64,
        pe: u64,
    },
}

impl From<DecodeError> for PeMismatch {
    fn from(value: DecodeError) -> Self {
        PeMismatch::Decode(value)
    }
}

/// Compare PE neutralization to software: solid edges + growth iteration count.
pub fn assert_solid_matches_software(graph: &DecoderGraph) -> Result<HeliosPeStats, PeMismatch> {
    let mut soft = graph.clone();
    let soft_steps = soft.decode_to_neutral()? as u64;
    let soft_solid: Vec<bool> = soft
        .state
        .iter()
        .map(|s| *s == EdgeState::Solid)
        .collect();

    let HeliosPeResult { solid, stats } = neutralize_helios_pe(graph)?;
    if solid != soft_solid {
        return Err(PeMismatch::SolidEdgesDiffer);
    }
    if stats.growth_cycles != soft_steps || stats.controller_iters != soft_steps {
        return Err(PeMismatch::GrowthIters {
            software: soft_steps,
            pe: stats.controller_iters,
        });
    }
    Ok(stats)
}

/// Full decode via PE neutralize + software peel; corrections match M16 cosim.
pub fn decode_helios_pe(graph: &DecoderGraph) -> Result<(Vec<EdgeId>, HeliosPeStats), DecodeError> {
    let mut g = graph.clone();
    let HeliosPeResult { stats, .. } = neutralize_helios_pe_inplace(&mut g)?;
    let forest = g.extract_forest();
    let corrections = g.peel(&forest);
    Ok((corrections, stats))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cycle_model::decode_cosim;
    use crate::graph::DecoderGraph;

    #[test]
    fn pe_solid_matches_software_blueprint() {
        let cases: &[&[u8]] = &[&[1, 1], &[1, 0, 1], &[1, 0, 0, 1]];
        let edge_sets: &[&[(usize, usize, u32)]] = &[
            &[(0, 1, 10)],
            &[(0, 1, 10), (1, 2, 10)],
            &[(0, 1, 10), (1, 2, 10), (2, 3, 10), (3, 0, 10)],
        ];
        for (syn, edges) in cases.iter().zip(edge_sets.iter()) {
            let g = DecoderGraph::from_syndrome_and_edges(syn, edges).unwrap();
            assert_solid_matches_software(&g).unwrap();
        }
    }

    #[test]
    fn pe_decode_matches_cosim_corrections() {
        let edges = [(0, 1, 10u32), (1, 2, 10u32)];
        let g = DecoderGraph::from_syndrome_and_edges(&[1, 0, 1], &edges).unwrap();
        let (pe_corr, stats) = decode_helios_pe(&g).unwrap();
        let cosim = decode_cosim(&g).unwrap();
        assert_eq!(pe_corr, cosim.corrections);
        assert!(stats.flood_cycles > 0 || stats.growth_cycles > 0);
    }

    #[test]
    fn pe_boundary_star() {
        let mut g = DecoderGraph::new(3);
        g.set_syndrome(0, 1).unwrap();
        g.mark_boundary(1).unwrap();
        g.mark_boundary(2).unwrap();
        g.add_edge(0, 1, 10).unwrap();
        g.add_edge(0, 2, 10).unwrap();
        assert_solid_matches_software(&g).unwrap();
        let (corr, _) = decode_helios_pe(&g).unwrap();
        assert_eq!(corr.len(), 1);
    }
}
