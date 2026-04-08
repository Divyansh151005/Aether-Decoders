//! Spanning-forest extraction and \(\mathbb{F}_2\) peeling.
//!
//! After all clusters are even, the solid-edge subgraph covers a valid
//! erasure. Peeling solves \(\sum_{e \ni v} \hat e_e \equiv s_v \pmod 2\)
//! on any spanning forest of that subgraph (Delfosse–Zémor).

use std::collections::VecDeque;

use crate::graph::DecoderGraph;
use crate::types::{EdgeId, EdgeState, NodeId};

impl DecoderGraph {
    /// BFS spanning forest of `Solid` edges: adjacency `v -> (neighbor, edge)`.
    ///
    /// Back-edges that would close a cycle are discarded.
    pub fn extract_forest(&self) -> Vec<Vec<(NodeId, EdgeId)>> {
        let n = self.num_nodes();
        let mut solid_adj: Vec<Vec<(NodeId, EdgeId)>> = vec![Vec::new(); n];
        for e in 0..self.num_edges() {
            if self.state[e] != EdgeState::Solid {
                continue;
            }
            let u = self.edge_u[e];
            let v = self.edge_v[e];
            solid_adj[u].push((v, e));
            solid_adj[v].push((u, e));
        }

        let mut forest: Vec<Vec<(NodeId, EdgeId)>> = vec![Vec::new(); n];
        let mut visited = vec![false; n];
        let mut queue = VecDeque::new();

        for start in 0..n {
            if visited[start] {
                continue;
            }
            visited[start] = true;
            queue.push_back(start);
            while let Some(u) = queue.pop_front() {
                for &(w, e) in &solid_adj[u] {
                    if visited[w] {
                        continue;
                    }
                    visited[w] = true;
                    forest[u].push((w, e));
                    forest[w].push((u, e));
                    queue.push_back(w);
                }
            }
        }
        forest
    }

    /// Leaf-to-root XOR sweep. Returns edge IDs with correction bit `1`.
    ///
    /// Syndromes are taken from frozen `self.syndrome`, **not** DSU `parity`.
    ///
    /// If a cluster touches the boundary, one boundary vertex is the peel
    /// *root* and every other leaf is processed — including extra virtual
    /// boundary vertices. Skipping all boundary leaves leaves
    /// detector—boundary—boundary stars unpeeled (phenom measurement edges
    /// often solidify two boundary vertices in one merge step).
    pub fn peel(&self, forest: &[Vec<(NodeId, EdgeId)>]) -> Vec<EdgeId> {
        let n = self.num_nodes();
        debug_assert_eq!(forest.len(), n);

        let peel_root = component_peel_roots(self, forest);
        let mut current_syndrome = self.syndrome.clone();
        let mut remaining: Vec<u32> = forest
            .iter()
            .map(|nbrs| nbrs.len() as u32)
            .collect();
        let mut peeled_edge = vec![false; self.num_edges()];
        let mut queue = VecDeque::new();

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

        corrections
    }

    /// Decode to even clusters, extract a forest, and peel a correction.
    pub fn decode(&mut self) -> Result<Vec<EdgeId>, crate::engine::DecodeError> {
        self.decode_to_neutral()?;
        let forest = self.extract_forest();
        Ok(self.peel(&forest))
    }
}

fn component_peel_roots(
    graph: &DecoderGraph,
    forest: &[Vec<(NodeId, EdgeId)>],
) -> Vec<NodeId> {
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

fn unique_unpeeled_neighbor(
    forest: &[Vec<(NodeId, EdgeId)>],
    u: NodeId,
    peeled_edge: &[bool],
) -> Option<(NodeId, EdgeId)> {
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
