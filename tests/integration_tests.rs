//! Mathematical correctness of Union-Find growth + peeling.

use aether_decoders::{verify_syndrome, DecoderGraph, EdgeId, EdgeState, NodeId};

fn peel_after_neutral(g: &mut DecoderGraph) -> (usize, Vec<EdgeId>) {
    let steps = g.decode_to_neutral().expect("clusters must neutralize");
    let forest = g.extract_forest();
    assert_acyclic_undirected(&forest);
    let corrections = g.peel(&forest);
    (steps, corrections)
}

/// A forest adjacency list has no cycles (tree edges only, undirected).
fn assert_acyclic_undirected(forest: &[Vec<(NodeId, EdgeId)>]) {
    let n = forest.len();
    let mut parent_node = vec![None; n];
    let mut parent_edge: Vec<Option<EdgeId>> = vec![None; n];
    let mut seen = vec![false; n];
    for start in 0..n {
        if seen[start] {
            continue;
        }
        let mut stack = vec![start];
        seen[start] = true;
        parent_node[start] = Some(start);
        while let Some(u) = stack.pop() {
            for &(w, e) in &forest[u] {
                if parent_edge[u] == Some(e) {
                    continue;
                }
                if seen[w] {
                    panic!("cycle involving edge {e} at nodes {u}-{w}");
                }
                seen[w] = true;
                parent_node[w] = Some(u);
                parent_edge[w] = Some(e);
                stack.push(w);
            }
        }
    }
}

#[test]
fn test_1_simple_two_node_direct_merge() {
    let edges = [(0, 1, 10u32)];
    let mut g = DecoderGraph::from_syndrome_and_edges(&[1, 1], &edges).unwrap();
    let (steps, corrections) = peel_after_neutral(&mut g);
    assert_eq!(steps, 5, "Δg = 2 per step on W = 10 must solidify at step 5");
    assert_eq!(corrections, vec![0]);
    assert!(verify_syndrome(&[1, 1], &corrections, &edges));
    assert_eq!(g.total_active_parity, 0);
}

#[test]
fn test_2_three_node_line_chain_resolution() {
    let edges = [(0, 1, 10u32), (1, 2, 10u32)];
    let mut g = DecoderGraph::from_syndrome_and_edges(&[1, 0, 1], &edges).unwrap();
    let (steps, mut corrections) = peel_after_neutral(&mut g);
    assert_eq!(
        steps, 10,
        "each odd cluster grows alone (Δg = 1) so both edges solidify at step 10"
    );
    corrections.sort_unstable();
    assert_eq!(corrections, vec![0, 1]);
    assert!(verify_syndrome(&[1, 0, 1], &corrections, &edges));
}

#[test]
fn test_3_four_node_cycle_breaking() {
    // Square: A—B—C—D—A with defects at A and D.
    let edges = [
        (0, 1, 10u32),
        (1, 2, 10u32),
        (2, 3, 10u32),
        (3, 0, 10u32),
    ];
    let syndrome = [1u8, 0, 0, 1];
    let mut g = DecoderGraph::from_syndrome_and_edges(&syndrome, &edges).unwrap();
    let (_steps, corrections) = peel_after_neutral(&mut g);

    let solid_count = g
        .state
        .iter()
        .filter(|s| **s == EdgeState::Solid)
        .count();
    let forest = g.extract_forest();
    let tree_edge_count: usize = forest.iter().map(|nbrs| nbrs.len()).sum::<usize>() / 2;
    assert!(
        tree_edge_count <= solid_count,
        "forest must be a subgraph of solid edges"
    );
    assert!(verify_syndrome(&syndrome, &corrections, &edges));
    assert_eq!(g.total_active_parity, 0);

    // Opposite defects A,C make all four sides grow at Δg=1 and solidify together,
    // producing a 4-cycle that BFS must cut.
    let mut g = DecoderGraph::from_syndrome_and_edges(&[1, 0, 1, 0], &edges).unwrap();
    let corrections = g.decode().unwrap();
    let solid_count = g
        .state
        .iter()
        .filter(|s| **s == EdgeState::Solid)
        .count();
    let forest = g.extract_forest();
    let tree_edge_count: usize = forest.iter().map(|nbrs| nbrs.len()).sum::<usize>() / 2;
    assert_eq!(solid_count, 4, "equal-weight opposite defects fill the square");
    assert_eq!(tree_edge_count, 3, "BFS must drop one cycle edge");
    assert!(verify_syndrome(&[1, 0, 1, 0], &corrections, &edges));
}

#[test]
fn test_4_mathematical_invariant_on_line_and_cycle() {
    let line = [(0, 1, 10u32), (1, 2, 10u32), (2, 3, 10u32)];
    let mut g = DecoderGraph::from_syndrome_and_edges(&[1, 0, 0, 1], &line).unwrap();
    let corrections = g.decode().unwrap();
    assert!(verify_syndrome(&[1, 0, 0, 1], &corrections, &line));

    let square = [
        (0, 1, 8u32),
        (1, 2, 8u32),
        (2, 3, 8u32),
        (3, 0, 8u32),
    ];
    let mut g = DecoderGraph::from_syndrome_and_edges(&[1, 1, 1, 1], &square).unwrap();
    let corrections = g.decode().unwrap();
    assert!(verify_syndrome(&[1, 1, 1, 1], &corrections, &square));
}

#[test]
fn peeling_example_from_docs() {
    // A(1)—e0—B(0)—e1—C(1), plus B—e2—D(0).
    let edges = [(0, 1, 10u32), (1, 2, 10u32), (1, 3, 10u32)];
    let mut g = DecoderGraph::from_syndrome_and_edges(&[1, 0, 1, 0], &edges).unwrap();
    let corrections = g.decode().unwrap();
    let mut bits = [0u8; 3];
    for e in &corrections {
        bits[*e] = 1;
    }
    assert_eq!(bits, [1, 1, 0], "docs example: e1 and e2 on, e3 off");
    assert!(verify_syndrome(&[1, 0, 1, 0], &corrections, &edges));
}

#[test]
fn boundary_neutralizes_a_single_defect() {
    let mut g = DecoderGraph::new(2);
    g.set_syndrome(0, 1).unwrap();
    g.mark_boundary(1).unwrap();
    g.add_edge(0, 1, 10).unwrap();
    let (steps, corrections) = peel_after_neutral(&mut g);
    assert_eq!(steps, 10);
    assert_eq!(corrections, vec![0]);
    assert_eq!(g.total_active_parity, 0);
}

#[test]
fn two_boundary_star_peels_the_defect() {
    let mut g = DecoderGraph::new(3);
    g.set_syndrome(0, 1).unwrap();
    g.mark_boundary(1).unwrap();
    g.mark_boundary(2).unwrap();
    g.add_edge(0, 1, 10).unwrap();
    g.add_edge(0, 2, 10).unwrap();
    let (_steps, corrections) = peel_after_neutral(&mut g);
    assert_eq!(corrections.len(), 1, "exactly one arm of the star is the correction");
    assert_eq!(g.total_active_parity, 0);
}

#[test]
fn compiled_two_boundary_edges_same_detector_flips_observable() {
    use aether_decoders::{CompiledUfDecoder, GraphlikeError};

    let errors = [
        GraphlikeError {
            detectors: vec![0],
            probability: 0.1,
            observables: vec![0],
        },
        GraphlikeError {
            detectors: vec![0],
            probability: 0.1,
            observables: vec![0],
        },
    ];
    let mut dec = CompiledUfDecoder::compile(1, 1, &errors, 100.0).unwrap();
    let obs = dec.decode_observables(&[1]).unwrap();
    assert_eq!(obs, vec![1], "peel must reach the detector via a boundary leaf");
}

#[test]
fn compiled_decoder_flips_observable_on_boundary_edge() {
    use aether_decoders::{CompiledUfDecoder, GraphlikeError};

    let err = GraphlikeError {
        detectors: vec![0],
        probability: 0.1,
        observables: vec![0],
    };
    let mut dec = CompiledUfDecoder::compile(1, 1, &[err], 100.0).unwrap();
    let obs = dec.decode_observables(&[1]).unwrap();
    assert_eq!(obs, vec![1]);
    let obs0 = dec.decode_observables(&[0]).unwrap();
    assert_eq!(obs0, vec![0]);
}

#[test]
fn cosim_bit_identical_on_all_blueprint_cases() {
    use aether_decoders::assert_bit_identical;

    let cases: Vec<(Vec<u8>, Vec<(usize, usize, u32)>)> = vec![
        (vec![1, 1], vec![(0, 1, 10)]),
        (vec![1, 0, 1], vec![(0, 1, 10), (1, 2, 10)]),
        (
            vec![1, 0, 0, 1],
            vec![(0, 1, 10), (1, 2, 10), (2, 3, 10), (3, 0, 10)],
        ),
        (vec![1, 0, 0, 1], vec![(0, 1, 10), (1, 2, 10), (2, 3, 10)]),
        (vec![1, 1, 1, 1], vec![(0, 1, 8), (1, 2, 8), (2, 3, 8), (3, 0, 8)]),
        (vec![1, 0, 1, 0], vec![(0, 1, 10), (1, 2, 10), (1, 3, 10)]),
    ];
    for (syn, edges) in cases {
        let g = DecoderGraph::from_syndrome_and_edges(&syn, &edges).unwrap();
        assert_bit_identical(&g).expect("cosim must match software decode");
    }

    let mut boundary = DecoderGraph::new(2);
    boundary.set_syndrome(0, 1).unwrap();
    boundary.mark_boundary(1).unwrap();
    boundary.add_edge(0, 1, 10).unwrap();
    assert_bit_identical(&boundary).unwrap();
}

#[test]
fn helios_pe_solid_matches_software_on_blueprint() {
    use aether_decoders::{assert_solid_matches_software, decode_cosim, decode_helios_pe};

    let cases: Vec<(Vec<u8>, Vec<(usize, usize, u32)>)> = vec![
        (vec![1, 1], vec![(0, 1, 10)]),
        (vec![1, 0, 1], vec![(0, 1, 10), (1, 2, 10)]),
        (vec![1, 0, 0, 1], vec![(0, 1, 10), (1, 2, 10), (2, 3, 10)]),
        (vec![1, 0, 1, 0], vec![(0, 1, 10), (1, 2, 10), (1, 3, 10)]),
    ];
    for (syn, edges) in cases {
        let g = DecoderGraph::from_syndrome_and_edges(&syn, &edges).unwrap();
        assert_solid_matches_software(&g).unwrap();
        let (pe_c, _) = decode_helios_pe(&g).unwrap();
        let cosim = decode_cosim(&g).unwrap();
        assert_eq!(pe_c, cosim.corrections);
    }
}
