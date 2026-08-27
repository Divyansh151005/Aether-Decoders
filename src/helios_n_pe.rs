//! Helios-n multiplexed grow schedule (software oracle, M71 / Stage C).
//!
//! Walks M70 `virtual → part` ownership so each edge is grown **exactly once**
//! per controller iteration (induced edges in their part; cross-cut edges owned
//! by `min(part_u, part_v)`). DSU roots are unchanged during grow, so this is
//! algebraically identical to flat [`crate::neutralize_helios_pe`].
//!
//! Refs: Helios arXiv:2406.08491; `Docs/Helios_n_Schedule_M69` §4 Stage C;
//! `Docs/Helios_n_Coloring_M70`; M44 flat grow goldens.

use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

use crate::engine::DecodeError;
use crate::graph::DecoderGraph;
use crate::helios_pe::HeliosPeStats;
use crate::types::{EdgeId, EdgeState, NodeId};

/// Virtual-node → physical PE / schedule part (M70 CSV).
#[derive(Clone, Debug)]
pub struct HeliosNMap {
    pub phys_pe: Vec<u32>,
    pub part: Vec<u32>,
    pub n_parts: u32,
    pub n_phys: u32,
}

/// Per-part edge lists that **partition** the graph edges (Stage C schedule).
#[derive(Clone, Debug)]
pub struct HeliosNSchedule {
    pub map: HeliosNMap,
    /// `edges_by_part[k]` = edges grown when part `k` is on the lattice.
    pub edges_by_part: Vec<Vec<EdgeId>>,
    pub n_induced: usize,
    pub n_cross: usize,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HeliosNPeStats {
    pub flat: HeliosPeStats,
    /// Part context switches (= `n_parts * controller_iters`).
    pub part_visits: u64,
    pub n_parts: u32,
    pub n_phys: u32,
}

#[derive(Clone, Debug)]
pub struct HeliosNPeResult {
    pub solid: Vec<bool>,
    pub stats: HeliosNPeStats,
}

/// Load `results/helios_n_coloring_m70.csv` (`virtual_node,phys_pe,part,...`).
pub fn load_helios_n_map(path: &Path) -> Result<HeliosNMap, String> {
    let file = File::open(path).map_err(|e| format!("open {}: {e}", path.display()))?;
    let mut phys_pe = Vec::new();
    let mut part = Vec::new();
    let mut max_phys = 0u32;
    let mut max_part = 0u32;
    for (line_no, line) in BufReader::new(file).lines().enumerate() {
        let line = line.map_err(|e| format!("read: {e}"))?;
        if line_no == 0 {
            continue;
        }
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let cols: Vec<&str> = line.split(',').collect();
        if cols.len() < 3 {
            return Err(format!("line {}: need ≥3 cols", line_no + 1));
        }
        let v: usize = cols[0]
            .parse()
            .map_err(|_| format!("line {}: bad virtual_node", line_no + 1))?;
        let p: u32 = cols[1]
            .parse()
            .map_err(|_| format!("line {}: bad phys_pe", line_no + 1))?;
        let k: u32 = cols[2]
            .parse()
            .map_err(|_| format!("line {}: bad part", line_no + 1))?;
        if v != phys_pe.len() {
            return Err(format!(
                "line {}: virtual_node {v} != expected row {}",
                line_no + 1,
                phys_pe.len()
            ));
        }
        phys_pe.push(p);
        part.push(k);
        max_phys = max_phys.max(p);
        max_part = max_part.max(k);
    }
    if phys_pe.is_empty() {
        return Err("empty coloring map".into());
    }
    Ok(HeliosNMap {
        phys_pe,
        part,
        n_parts: max_part.saturating_add(1),
        n_phys: max_phys.saturating_add(1),
    })
}

/// Build a Helios-legal edge schedule from an M70 map + decoder graph.
pub fn build_helios_n_schedule(
    map: HeliosNMap,
    g: &DecoderGraph,
) -> Result<HeliosNSchedule, String> {
    let n = g.num_nodes();
    if map.phys_pe.len() != n || map.part.len() != n {
        return Err(format!(
            "map V={} vs graph V={n}",
            map.phys_pe.len()
        ));
    }
    let n_parts = map.n_parts as usize;
    let mut edges_by_part: Vec<Vec<EdgeId>> = vec![Vec::new(); n_parts];
    let mut n_induced = 0usize;
    let mut n_cross = 0usize;
    let m = g.num_edges();
    for e in 0..m {
        let u = g.edge_u[e];
        let v = g.edge_v[e];
        let pu = map.part[u];
        let pv = map.part[v];
        if pu == pv {
            edges_by_part[pu as usize].push(e);
            n_induced += 1;
        } else {
            // Helios: cross-cut endpoints share phys_pe (M70 lock).
            if map.phys_pe[u] != map.phys_pe[v] {
                return Err(format!(
                    "cross-cut edge {e} ({u},{v}) phys {}!={}",
                    map.phys_pe[u], map.phys_pe[v]
                ));
            }
            let owner = pu.min(pv) as usize;
            edges_by_part[owner].push(e);
            n_cross += 1;
        }
    }
    let scheduled: usize = edges_by_part.iter().map(|v| v.len()).sum();
    if scheduled != m {
        return Err(format!("scheduled {scheduled} != m={m}"));
    }
    Ok(HeliosNSchedule {
        map,
        edges_by_part,
        n_induced,
        n_cross,
    })
}

/// Multiplexed neutralize; solids / growth_cycles ≡ flat Helios PE.
pub fn neutralize_helios_n_pe(
    graph: &DecoderGraph,
    schedule: &HeliosNSchedule,
) -> Result<HeliosNPeResult, DecodeError> {
    let mut g = graph.clone();
    neutralize_helios_n_pe_inplace(&mut g, schedule)
}

pub fn neutralize_helios_n_pe_inplace(
    g: &mut DecoderGraph,
    schedule: &HeliosNSchedule,
) -> Result<HeliosNPeResult, DecodeError> {
    let mut flat = HeliosPeStats::default();
    let mut part_visits = 0u64;
    let limit = iteration_limit(g);

    while g.total_active_parity > 0 {
        if flat.controller_iters >= limit {
            return Err(DecodeError::IterationLimit {
                steps: flat.controller_iters as usize,
            });
        }

        let grew = pe_grow_cycle_scheduled(g, schedule);
        part_visits = part_visits.saturating_add(schedule.map.n_parts as u64);
        flat.growth_cycles += 1;

        let merged = pe_solidify_and_union(g);
        flat.merge_solidify_rounds += 1;
        flat.flood_cycles += pe_flood_cycle_count(g);
        flat.controller_iters += 1;

        if !grew && !merged {
            return Err(DecodeError::Unsolvable {
                steps: flat.controller_iters as usize,
                remaining_odd: g.total_active_parity,
            });
        }
    }

    let solid: Vec<bool> = g.state.iter().map(|s| *s == EdgeState::Solid).collect();
    Ok(HeliosNPeResult {
        solid,
        stats: HeliosNPeStats {
            flat,
            part_visits,
            n_parts: schedule.map.n_parts,
            n_phys: schedule.map.n_phys,
        },
    })
}

/// Assert multiplexed grow matches flat [`crate::neutralize_helios_pe`].
pub fn assert_helios_n_matches_flat(
    graph: &DecoderGraph,
    schedule: &HeliosNSchedule,
) -> Result<HeliosNPeStats, String> {
    use crate::helios_pe::neutralize_helios_pe;

    let flat = neutralize_helios_pe(graph).map_err(|e| format!("flat: {e:?}"))?;
    let n = neutralize_helios_n_pe(graph, schedule).map_err(|e| format!("helios_n: {e:?}"))?;
    if n.solid != flat.solid {
        return Err("solid edges differ (helios_n vs flat)".into());
    }
    if n.stats.flat.growth_cycles != flat.stats.growth_cycles
        || n.stats.flat.controller_iters != flat.stats.controller_iters
    {
        return Err(format!(
            "growth_cycles flat={} helios_n={}",
            flat.stats.growth_cycles, n.stats.flat.growth_cycles
        ));
    }
    Ok(n.stats)
}

/// Helios-n grow + software peel (Stage D); peel is not time-multiplexed.
pub fn decode_helios_n_pe(
    graph: &DecoderGraph,
    schedule: &HeliosNSchedule,
) -> Result<(Vec<crate::types::EdgeId>, HeliosNPeStats, u64), DecodeError> {
    use crate::cycle_model::peel_cosim_stats;

    let mut g = graph.clone();
    let HeliosNPeResult { stats, .. } = neutralize_helios_n_pe_inplace(&mut g, schedule)?;
    let (corrections, peel_ops) = peel_cosim_stats(&g);
    Ok((corrections, stats, peel_ops))
}

/// Stage D: corr + peel_ops ≡ [`crate::decode_cosim`] after Helios-n grow.
pub fn assert_helios_n_decode_matches_cosim(
    graph: &DecoderGraph,
    schedule: &HeliosNSchedule,
) -> Result<(HeliosNPeStats, u64), String> {
    use crate::cycle_model::decode_cosim;

    let cosim = decode_cosim(graph).map_err(|e| format!("cosim: {e:?}"))?;
    let (corr, stats, peel_ops) =
        decode_helios_n_pe(graph, schedule).map_err(|e| format!("helios_n decode: {e:?}"))?;
    if corr != cosim.corrections {
        return Err("corrections differ (helios_n vs decode_cosim)".into());
    }
    if peel_ops != cosim.stats.peel_ops {
        return Err(format!(
            "peel_ops helios_n={peel_ops} cosim={}",
            cosim.stats.peel_ops
        ));
    }
    Ok((stats, peel_ops))
}

fn iteration_limit(g: &DecoderGraph) -> u64 {
    let weight_sum: u64 = g.capacity.iter().map(|&c| c as u64).sum();
    weight_sum
        .saturating_add(g.num_edges() as u64)
        .saturating_add(1)
        .max(1)
}

fn pe_grow_cycle_scheduled(g: &mut DecoderGraph, schedule: &HeliosNSchedule) -> bool {
    let mut progressed = false;
    for edges in &schedule.edges_by_part {
        for &e in edges {
            if grow_one_edge(g, e) {
                progressed = true;
            }
        }
    }
    progressed
}

fn grow_one_edge(g: &mut DecoderGraph, e: EdgeId) -> bool {
    if g.state[e] == EdgeState::Solid {
        return false;
    }
    let u = g.edge_u[e];
    let v = g.edge_v[e];
    let r_u = g.find(u);
    let r_v = g.find(v);
    if r_u == r_v {
        return false;
    }
    let delta = u32::from(g.cluster_is_active(r_u)) + u32::from(g.cluster_is_active(r_v));
    if delta == 0 {
        return false;
    }
    g.growth[e] = g.growth[e].saturating_add(delta);
    true
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
        total = total.saturating_add(u64::from(max_depth).saturating_mul(3).saturating_add(1));
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graph::DecoderGraph;
    use crate::helios_pe::neutralize_helios_pe;
    use std::path::PathBuf;

    fn toy_line_schedule() -> (DecoderGraph, HeliosNSchedule) {
        // 0—1—2 with parts {0},{1},{2}; cross 0-1 and 1-2 share phys by construction.
        let mut g = DecoderGraph::new(3);
        g.set_syndrome(0, 1).unwrap();
        g.set_syndrome(2, 1).unwrap();
        g.add_edge(0, 1, 10).unwrap();
        g.add_edge(1, 2, 10).unwrap();
        let map = HeliosNMap {
            phys_pe: vec![0, 0, 0],
            part: vec![0, 1, 2],
            n_parts: 3,
            n_phys: 1,
        };
        let schedule = build_helios_n_schedule(map, &g).unwrap();
        assert_eq!(schedule.n_induced, 0);
        assert_eq!(schedule.n_cross, 2);
        (g, schedule)
    }

    #[test]
    fn toy_helios_n_matches_flat() {
        let (g, schedule) = toy_line_schedule();
        assert_helios_n_matches_flat(&g, &schedule).unwrap();
        let flat = neutralize_helios_pe(&g).unwrap();
        let n = neutralize_helios_n_pe(&g, &schedule).unwrap();
        assert_eq!(n.stats.part_visits, 3 * flat.stats.controller_iters);
    }

    #[test]
    fn toy_helios_n_decode_matches_cosim() {
        let (g, schedule) = toy_line_schedule();
        let (_stats, peel_ops) = assert_helios_n_decode_matches_cosim(&g, &schedule).unwrap();
        assert!(peel_ops > 0);
    }

    #[test]
    fn m70_map_loads_and_partitions_phenom_shape() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let map_path = root.join("results/helios_n_coloring_m70.csv");
        if !map_path.exists() {
            return;
        }
        let map = load_helios_n_map(&map_path).unwrap();
        assert_eq!(map.n_parts, 16);
        assert_eq!(map.n_phys, 7);
        assert_eq!(map.part.len(), 72);
    }
}
