//! Shared Blueprint UF graphs for RTL goldens (M18+) and DPI co-sim (M26).
//!
//! Cases match historical `gen_rtl_vectors` / decode TB topologies.

use crate::{
    decode_cosim, neutralize_helios_pe, DecoderGraph, EdgeId, EdgeState, HeliosPeResult,
};

/// One Blueprint case: syndrome, boundary flags, undirected edges (u, v, capacity).
#[derive(Clone, Debug)]
pub struct BlueprintCase {
    pub name: &'static str,
    pub syndrome: Vec<u8>,
    pub is_boundary: Vec<u8>,
    pub edges: Vec<(usize, usize, u32)>,
}

pub fn blueprint_cases() -> Vec<BlueprintCase> {
    vec![
        BlueprintCase {
            name: "two_node",
            syndrome: vec![1, 1],
            is_boundary: vec![0, 0],
            edges: vec![(0, 1, 10)],
        },
        BlueprintCase {
            name: "line3",
            syndrome: vec![1, 0, 1],
            is_boundary: vec![0, 0, 0],
            edges: vec![(0, 1, 10), (1, 2, 10)],
        },
        BlueprintCase {
            name: "line4",
            syndrome: vec![1, 0, 0, 1],
            is_boundary: vec![0, 0, 0, 0],
            edges: vec![(0, 1, 10), (1, 2, 10), (2, 3, 10)],
        },
        BlueprintCase {
            name: "square",
            syndrome: vec![1, 0, 0, 1],
            is_boundary: vec![0, 0, 0, 0],
            edges: vec![(0, 1, 10), (1, 2, 10), (2, 3, 10), (3, 0, 10)],
        },
        BlueprintCase {
            name: "docs_peel",
            syndrome: vec![1, 0, 1, 0],
            is_boundary: vec![0, 0, 0, 0],
            edges: vec![(0, 1, 10), (1, 2, 10), (1, 3, 10)],
        },
        BlueprintCase {
            name: "boundary",
            syndrome: vec![1, 0],
            is_boundary: vec![0, 1],
            edges: vec![(0, 1, 10)],
        },
        BlueprintCase {
            name: "two_boundary_star",
            syndrome: vec![1, 0, 0],
            is_boundary: vec![0, 1, 1],
            edges: vec![(0, 1, 10), (0, 2, 10)],
        },
        BlueprintCase {
            name: "square_opp",
            syndrome: vec![1, 0, 1, 0],
            is_boundary: vec![0, 0, 0, 0],
            edges: vec![(0, 1, 10), (1, 2, 10), (2, 3, 10), (3, 0, 10)],
        },
    ]
}

pub fn blueprint_num_cases() -> usize {
    blueprint_cases().len()
}

pub fn build_blueprint_graph(c: &BlueprintCase) -> DecoderGraph {
    let n = c.syndrome.len();
    let mut g = DecoderGraph::with_edge_capacity(n, c.edges.len());
    for (v, &s) in c.syndrome.iter().enumerate() {
        g.set_syndrome(v, s).unwrap();
    }
    for (v, &b) in c.is_boundary.iter().enumerate() {
        if b != 0 {
            g.mark_boundary(v).unwrap();
        }
    }
    for &(u, v, cap) in &c.edges {
        g.add_edge(u, v, cap).unwrap();
    }
    g
}

fn corr_mask(corrections: &[EdgeId]) -> u32 {
    corrections.iter().fold(0u32, |acc, &e| acc | (1u32 << e))
}

fn solid_mask_from_flags(solid: &[bool]) -> u32 {
    solid.iter().enumerate().fold(0u32, |acc, (e, &s)| {
        if s {
            acc | (1u32 << e)
        } else {
            acc
        }
    })
}

fn solid_mask_from_graph(g: &DecoderGraph) -> u32 {
    g.state.iter().enumerate().fold(0u32, |acc, (e, s)| {
        if *s == EdgeState::Solid {
            acc | (1u32 << e)
        } else {
            acc
        }
    })
}

/// Live goldens for one Blueprint case (same sources as `gen_rtl_vectors`).
#[derive(Clone, Debug)]
pub struct BlueprintGolden {
    pub name: &'static str,
    pub n: u32,
    pub m: u32,
    pub syndrome: Vec<u8>,
    pub is_boundary: Vec<u8>,
    pub eu: Vec<u32>,
    pub ev: Vec<u32>,
    pub cap: Vec<u32>,
    pub cycles: u32,
    pub solid_mask: u32,
    pub corr_mask: u32,
    pub peel_ops: u32,
}

pub fn blueprint_golden(case_id: usize) -> Option<BlueprintGolden> {
    let cases = blueprint_cases();
    let c = cases.get(case_id)?;
    let g = build_blueprint_graph(c);
    let HeliosPeResult { solid, stats: pe_stats } =
        neutralize_helios_pe(&g).unwrap_or_else(|e| panic!("{} helios: {e:?}", c.name));
    let cosim = decode_cosim(&g).unwrap_or_else(|e| panic!("{} cosim: {e:?}", c.name));
    let mut g_dec = build_blueprint_graph(c);
    let corrections = g_dec
        .decode()
        .unwrap_or_else(|e| panic!("{} decode: {e:?}", c.name));
    let pe_solid = solid_mask_from_flags(&solid);
    let dec_solid = solid_mask_from_graph(&g_dec);
    assert_eq!(
        pe_solid, dec_solid,
        "{}: helios_pe solid {pe_solid:#x} != decode solid {dec_solid:#x}",
        c.name
    );
    assert_eq!(
        corr_mask(&corrections),
        corr_mask(&cosim.corrections),
        "{}: decode corr != cosim corr",
        c.name
    );
    Some(BlueprintGolden {
        name: c.name,
        n: c.syndrome.len() as u32,
        m: c.edges.len() as u32,
        syndrome: c.syndrome.clone(),
        is_boundary: c.is_boundary.clone(),
        eu: c.edges.iter().map(|&(u, _, _)| u as u32).collect(),
        ev: c.edges.iter().map(|&(_, v, _)| v as u32).collect(),
        cap: c.edges.iter().map(|&(_, _, cap)| cap).collect(),
        cycles: pe_stats.growth_cycles as u32,
        solid_mask: pe_solid,
        corr_mask: corr_mask(&cosim.corrections),
        peel_ops: cosim.stats.peel_ops as u32,
    })
}
