//! Disjoint-set union with union-by-size and \(\mathbb{F}_2\) cluster parity.
//!
//! Path compression is iterative (two-pass) so FPGA / stack-limited targets
//! never recurse. Cluster parity is
//! \(\pi(C) = \sum_{v \in C} s_v \pmod 2\), stored only at the root.

use crate::graph::DecoderGraph;
use crate::types::NodeId;

impl DecoderGraph {
    /// Return the root of `u`, compressing the traversed path onto that root.
    pub fn find(&mut self, u: NodeId) -> NodeId {
        debug_assert!(u < self.num_nodes());
        let mut root = u;
        while self.parent[root] != root {
            root = self.parent[root];
        }
        let mut cur = u;
        while cur != root {
            let next = self.parent[cur];
            self.parent[cur] = root;
            cur = next;
        }
        root
    }

    /// Merge the clusters of `u` and `v` (no-op if already connected).
    ///
    /// Homological update: \(\pi(C_{\text{new}}) = \pi(C_u) \oplus \pi(C_v)\).
    /// A cluster is **active** only if it is odd *and* has not touched a
    /// boundary vertex (open-boundary neutralization).
    pub fn union(&mut self, u: NodeId, v: NodeId) {
        let mut root_u = self.find(u);
        let mut root_v = self.find(v);
        if root_u == root_v {
            return;
        }
        if self.size[root_u] < self.size[root_v] {
            core::mem::swap(&mut root_u, &mut root_v);
        }
        let active_u = self.cluster_is_active(root_u) as usize;
        let active_v = self.cluster_is_active(root_v) as usize;
        self.parent[root_v] = root_u;
        self.size[root_u] = self.size[root_u].saturating_add(self.size[root_v]);
        self.parity[root_u] ^= self.parity[root_v];
        self.cluster_boundary[root_u] |= self.cluster_boundary[root_v];
        self.parity[root_v] = 0;
        self.cluster_boundary[root_v] = 0;
        let active_new = self.cluster_is_active(root_u) as usize;
        self.total_active_parity = self
            .total_active_parity
            .saturating_sub(active_u)
            .saturating_sub(active_v)
            .saturating_add(active_new);
    }
}
