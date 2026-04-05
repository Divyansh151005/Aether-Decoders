//! Aether-Decoders: integer Union-Find + Relay-BP quantum error correction.
//!
//! Phase 1 software:
//! - Union-Find on graphlike surface-code DEMs (flat SoA, FPGA-mappable).
//! - Relay-BP (Müller et al. arXiv:2506.01779) on hypergraph / qLDPC DEMs.
//! - Helios-style PE grow/merge cycle model + first RTL slice (`rtl/`).
//!
//! Pointer-based graph crates (`petgraph`, `Rc<RefCell<_>>`) are intentionally
//! unused so the layout maps onto FPGA BRAM banks later.

#![deny(unsafe_code)]

pub mod blueprint_rtl;
pub mod compiled;
pub mod cycle_model;
pub mod dsu;
pub mod engine;
pub mod graph;
pub mod helios_n_pe;
pub mod helios_pe;
pub mod peeling;
pub mod relay_bp;
pub mod relay_compiled;
pub mod stim_rtl;
pub mod types;
pub mod weights;

pub use blueprint_rtl::{
    blueprint_cases, blueprint_golden, blueprint_num_cases, build_blueprint_graph, BlueprintCase,
    BlueprintGolden,
};
pub use compiled::{CompileError, CompiledUfDecoder, GraphlikeError};
pub use cycle_model::{
    assert_bit_identical, decode_cosim, peel_cosim_stats, CosimResult, CycleStats,
};
pub use engine::DecodeError;
pub use graph::{DecoderGraph, GraphError};
pub use helios_n_pe::{
    assert_helios_n_decode_matches_cosim, assert_helios_n_matches_flat, build_helios_n_schedule,
    decode_helios_n_pe, load_helios_n_map, neutralize_helios_n_pe, HeliosNMap, HeliosNPeResult,
    HeliosNPeStats, HeliosNSchedule,
};
pub use helios_pe::{
    assert_solid_matches_software, decode_helios_pe, neutralize_helios_pe, HeliosPeResult,
    HeliosPeStats,
};
pub use relay_bp::{
    log_prior, DMemBp, RelayBp, RelayConfig, RelayError, RelayResult, SeedRng, TannerGraph,
};
pub use relay_compiled::{CompiledRelayDecoder, DemError};
pub use stim_rtl::{load_stim_rtl_bundle, StimRtlBundle, StimRtlCase};
pub use types::{EdgeId, EdgeState, NodeId};
pub use weights::{integer_capacity, DEFAULT_LAMBDA};

/// Apply correction edges to the zero vector via endpoint XOR.
///
/// For a graph whose edges are the columns of the vertex-edge incidence
/// matrix \(H\) over \(\mathbb{F}_2\), this computes \(H\hat e\).
pub fn verify_syndrome(
    original_parities: &[u8],
    corrections: &[EdgeId],
    edge_definitions: &[(NodeId, NodeId, u32)],
) -> bool {
    let mut reconstructed = vec![0u8; original_parities.len()];
    for &e in corrections {
        if e >= edge_definitions.len() {
            return false;
        }
        let (u, v, _) = edge_definitions[e];
        if u >= reconstructed.len() || v >= reconstructed.len() {
            return false;
        }
        reconstructed[u] ^= 1;
        reconstructed[v] ^= 1;
    }
    reconstructed.as_slice() == original_parities
}
