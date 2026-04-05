//! Struct-of-arrays decoding graph.
//!
//! Continuous Union-Find growth \(g(e) \in [0, 1]\) with half-edge speed
//! \(1/2\) is stored as integer `growth` against a **doubled** capacity
//! \(W_e = 2\,\lfloor \lambda \ln((1-p_e)/p_e)\rfloor\). One odd cluster
//! on the cut then contributes `+1` per discrete step instead of `+1/2`.

use crate::types::{EdgeId, EdgeState, NodeId};

/// Flat, cache-friendly Union-Find decoding graph.
///
/// Cluster membership lives in `parent` / `size` / `parity` (DSU). The
/// measured syndrome is stored separately in `syndrome` and is **never**
/// mutated by `union`: peeling must solve \(H\hat e \equiv s \pmod 2\)
/// against the original defects, while `parity[root]` is only the live
/// cluster parity \(\pi(C)\).
#[derive(Clone, Debug)]
pub struct DecoderGraph {
    // --- Node data (index = NodeId) ---
    pub parent: Vec<NodeId>,
    /// Live cluster parity at DSU roots (`0` on non-roots after unions).
    pub parity: Vec<u8>,
    /// Frozen measured syndrome \(s_v \in \{0,1\}\). Used by peeling.
    pub syndrome: Vec<u8>,
    pub size: Vec<u32>,
    /// Frozen vertex type: `1` is a virtual boundary (open surface-code edge).
    pub is_boundary: Vec<u8>,
    /// DSU-root flag: cluster touches at least one boundary vertex.
    pub cluster_boundary: Vec<u8>,

    // --- Edge data (index = EdgeId) ---
    pub edge_u: Vec<NodeId>,
    pub edge_v: Vec<NodeId>,
    /// Integer capacity \(W_e\) (already scaled by 2).
    pub capacity: Vec<u32>,
    pub growth: Vec<u32>,
    pub state: Vec<EdgeState>,
    /// Bit `k` set ⇒ this error mechanism flips logical observable `k`.
    pub obs_mask: Vec<u64>,

    /// Number of *active* clusters (odd parity and not on the boundary).
    pub total_active_parity: usize,
}

impl DecoderGraph {
    /// Allocate a graph with `num_nodes` vertices and no edges.
    ///
    /// Every node starts as its own cluster (`parent[v] = v`, `size[v] = 1`).
    /// Syndromes default to `0` (neutral). Use [`Self::set_syndrome`] then
    /// [`Self::add_edge`].
    pub fn new(num_nodes: usize) -> Self {
        Self {
            parent: (0..num_nodes).collect(),
            parity: vec![0; num_nodes],
            syndrome: vec![0; num_nodes],
            size: vec![1; num_nodes],
            is_boundary: vec![0; num_nodes],
            cluster_boundary: vec![0; num_nodes],
            edge_u: Vec::new(),
            edge_v: Vec::new(),
            capacity: Vec::new(),
            growth: Vec::new(),
            state: Vec::new(),
            obs_mask: Vec::new(),
            total_active_parity: 0,
        }
    }

    /// Allocate with room for `edge_capacity` edges to avoid growth reallocations.
    pub fn with_edge_capacity(num_nodes: usize, edge_capacity: usize) -> Self {
        let mut g = Self::new(num_nodes);
        g.edge_u.reserve(edge_capacity);
        g.edge_v.reserve(edge_capacity);
        g.capacity.reserve(edge_capacity);
        g.growth.reserve(edge_capacity);
        g.state.reserve(edge_capacity);
        g.obs_mask.reserve(edge_capacity);
        g
    }

    /// Build a fully specified instance (used by tests and Stim glue).
    ///
    /// `edges` entries are `(u, v, W_e)` with \(W_e\) already doubled.
    pub fn from_syndrome_and_edges(
        syndrome: &[u8],
        edges: &[(NodeId, NodeId, u32)],
    ) -> Result<Self, GraphError> {
        let n = syndrome.len();
        let mut g = Self::with_edge_capacity(n, edges.len());
        for (v, &s) in syndrome.iter().enumerate() {
            g.set_syndrome(v, s)?;
        }
        for &(u, v, cap) in edges {
            g.add_edge(u, v, cap)?;
        }
        Ok(g)
    }

    pub fn num_nodes(&self) -> usize {
        self.parent.len()
    }

    pub fn num_edges(&self) -> usize {
        self.edge_u.len()
    }

    /// Set the measured defect at `node` and refresh cluster parity bookkeeping.
    ///
    /// Call this **before** growth, while each node is still its own root.
    pub fn set_syndrome(&mut self, node: NodeId, value: u8) -> Result<(), GraphError> {
        if node >= self.num_nodes() {
            return Err(GraphError::NodeOutOfRange { node, n: self.num_nodes() });
        }
        if value > 1 {
            return Err(GraphError::InvalidParity { value });
        }
        if self.is_boundary[node] == 1 && value != 0 {
            return Err(GraphError::BoundarySyndrome);
        }
        self.syndrome[node] = value;
        self.parity[node] = value;
        self.parent[node] = node;
        self.size[node] = 1;
        self.cluster_boundary[node] = self.is_boundary[node];
        self.recompute_total_active();
        Ok(())
    }

    /// Mark `node` as a virtual boundary vertex (syndrome stays 0).
    pub fn mark_boundary(&mut self, node: NodeId) -> Result<(), GraphError> {
        if node >= self.num_nodes() {
            return Err(GraphError::NodeOutOfRange { node, n: self.num_nodes() });
        }
        self.is_boundary[node] = 1;
        self.syndrome[node] = 0;
        self.parity[node] = 0;
        self.parent[node] = node;
        self.size[node] = 1;
        self.cluster_boundary[node] = 1;
        self.recompute_total_active();
        Ok(())
    }

    /// An odd cluster that has not yet touched the code boundary.
    #[inline]
    pub fn cluster_is_active(&self, root: NodeId) -> bool {
        self.parity[root] == 1 && self.cluster_boundary[root] == 0
    }

    pub(crate) fn recompute_total_active(&mut self) {
        let mut total = 0usize;
        for v in 0..self.num_nodes() {
            if self.parent[v] == v && self.cluster_is_active(v) {
                total += 1;
            }
        }
        self.total_active_parity = total;
    }

    /// Append an undirected edge with integer capacity `W_e`.
    pub fn add_edge(
        &mut self,
        u: NodeId,
        v: NodeId,
        capacity: u32,
    ) -> Result<EdgeId, GraphError> {
        let n = self.num_nodes();
        if u >= n || v >= n {
            return Err(GraphError::NodeOutOfRange {
                node: u.max(v),
                n,
            });
        }
        if u == v {
            return Err(GraphError::SelfLoop { node: u });
        }
        if capacity == 0 {
            return Err(GraphError::ZeroCapacity);
        }
        let id = self.edge_u.len();
        self.edge_u.push(u);
        self.edge_v.push(v);
        self.capacity.push(capacity);
        self.growth.push(0);
        self.state.push(EdgeState::Empty);
        self.obs_mask.push(0);
        Ok(id)
    }

    /// Like [`Self::add_edge`] but records which logical observables the mechanism flips.
    pub fn add_edge_with_observables(
        &mut self,
        u: NodeId,
        v: NodeId,
        capacity: u32,
        obs_mask: u64,
    ) -> Result<EdgeId, GraphError> {
        let id = self.add_edge(u, v, capacity)?;
        self.obs_mask[id] = obs_mask;
        Ok(id)
    }

    /// Restore DSU + growth to the post-construction syndrome, keeping topology.
    pub fn reset_clusters(&mut self) {
        let n = self.num_nodes();
        for v in 0..n {
            self.parent[v] = v;
            self.size[v] = 1;
            self.parity[v] = self.syndrome[v];
            self.cluster_boundary[v] = self.is_boundary[v];
        }
        self.recompute_total_active();
        for e in 0..self.num_edges() {
            self.growth[e] = 0;
            self.state[e] = EdgeState::Empty;
        }
    }
}

/// Recoverable graph-construction errors.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GraphError {
    NodeOutOfRange { node: NodeId, n: usize },
    InvalidParity { value: u8 },
    SelfLoop { node: NodeId },
    ZeroCapacity,
    BoundarySyndrome,
    SyndromeLength { got: usize, expected: usize },
}
