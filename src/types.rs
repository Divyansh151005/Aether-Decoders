//! Index types and edge occupancy for the discrete Union-Find decoder.
//!
//! All graph storage is integer-indexed into flat `Vec`s. Node and edge
//! identifiers are dense `usize` positions — never heap pointers — so a
//! later FPGA mapping can treat them as SRAM addresses.

/// Dense index of a vertex in the decoding graph (syndrome site).
pub type NodeId = usize;

/// Dense index of an edge in the decoding graph (physical error location).
pub type EdgeId = usize;

/// Occupancy of a decoding-graph edge during cluster growth.
///
/// `Empty` edges still accumulate integer growth. `Solid` edges are fully
/// grown (`growth >= capacity`) and participate in cluster merges and in
/// the spanning forest used by peeling.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EdgeState {
    Empty,
    Solid,
}
