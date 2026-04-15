//! Compile a graphlike Stim detector-error model into a reusable UF decoder.

use crate::engine::DecodeError;
use crate::graph::{DecoderGraph, GraphError};
use crate::types::{EdgeId, NodeId};
use crate::weights::{integer_capacity, DEFAULT_LAMBDA};

/// One independent error mechanism from a flattened DEM.
#[derive(Clone, Debug)]
pub struct GraphlikeError {
    pub detectors: Vec<usize>,
    pub probability: f64,
    pub observables: Vec<usize>,
}

/// Why a detector-error model cannot be compiled into a matching graph.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CompileError {
    Hyperedge { degree: usize },
    TooManyObservables { n: usize },
    Graph(GraphError),
    EmptyDetectorList,
}

impl From<GraphError> for CompileError {
    fn from(value: GraphError) -> Self {
        CompileError::Graph(value)
    }
}

/// Union-Find decoder compiled from graphlike (degree ≤ 2) DEM errors.
#[derive(Clone, Debug)]
pub struct CompiledUfDecoder {
    graph: DecoderGraph,
    num_detectors: usize,
    num_observables: usize,
}

impl CompiledUfDecoder {
    pub fn compile(
        num_detectors: usize,
        num_observables: usize,
        errors: &[GraphlikeError],
        lambda: f64,
    ) -> Result<Self, CompileError> {
        if num_observables > 64 {
            return Err(CompileError::TooManyObservables { n: num_observables });
        }
        let lambda = if lambda <= 0.0 { DEFAULT_LAMBDA } else { lambda };

        let mut boundary_count = 0usize;
        for err in errors {
            match err.detectors.len() {
                0 => {}
                1 => boundary_count += 1,
                2 => {}
                d => return Err(CompileError::Hyperedge { degree: d }),
            }
        }

        let num_nodes = num_detectors + boundary_count;
        let mut graph = DecoderGraph::with_edge_capacity(num_nodes, errors.len());
        for b in num_detectors..num_nodes {
            graph.mark_boundary(b)?;
        }

        let mut next_boundary = num_detectors;
        for err in errors {
            if err.probability <= 0.0 {
                continue;
            }
            let cap = integer_capacity(err.probability, lambda);
            let mut mask = 0u64;
            for &obs in &err.observables {
                if obs >= num_observables {
                    return Err(CompileError::TooManyObservables { n: obs + 1 });
                }
                mask |= 1u64 << obs;
            }
            match err.detectors.as_slice() {
                [] => {}
                [d] => {
                    if *d >= num_detectors {
                        return Err(GraphError::NodeOutOfRange {
                            node: *d,
                            n: num_detectors,
                        }
                        .into());
                    }
                    let b = next_boundary;
                    next_boundary += 1;
                    graph.add_edge_with_observables(*d, b, cap, mask)?;
                }
                [d0, d1] => {
                    if *d0 >= num_detectors || *d1 >= num_detectors {
                        return Err(GraphError::NodeOutOfRange {
                            node: (*d0).max(*d1),
                            n: num_detectors,
                        }
                        .into());
                    }
                    if d0 == d1 {
                        return Err(CompileError::EmptyDetectorList);
                    }
                    graph.add_edge_with_observables(*d0, *d1, cap, mask)?;
                }
                other => return Err(CompileError::Hyperedge { degree: other.len() }),
            }
        }

        Ok(Self {
            graph,
            num_detectors,
            num_observables,
        })
    }

    pub fn num_detectors(&self) -> usize {
        self.num_detectors
    }

    pub fn num_observables(&self) -> usize {
        self.num_observables
    }

    pub fn graph(&self) -> &DecoderGraph {
        &self.graph
    }

    /// Load a packed 0/1 detection-event vector of length `num_detectors`.
    pub fn load_detection_events(&mut self, events: &[u8]) -> Result<(), GraphError> {
        if events.len() != self.num_detectors {
            return Err(GraphError::SyndromeLength {
                got: events.len(),
                expected: self.num_detectors,
            });
        }
        for (v, &bit) in events.iter().enumerate() {
            if bit > 1 {
                return Err(GraphError::InvalidParity { value: bit });
            }
            self.graph.syndrome[v] = bit;
        }
        for v in self.num_detectors..self.graph.num_nodes() {
            self.graph.syndrome[v] = 0;
        }
        self.graph.reset_clusters();
        Ok(())
    }

    /// Decode one shot to a 0/1 observable prediction vector.
    pub fn decode_observables(&mut self, events: &[u8]) -> Result<Vec<u8>, DecodeError> {
        self.load_detection_events(events)
            .map_err(|_| DecodeError::Unsolvable {
                steps: 0,
                remaining_odd: 0,
            })?;
        let corrections = self.graph.decode()?;
        Ok(self.observables_from_corrections(&corrections))
    }

    pub fn observables_from_corrections(&self, corrections: &[EdgeId]) -> Vec<u8> {
        let mut acc = 0u64;
        for &e in corrections {
            acc ^= self.graph.obs_mask[e];
        }
        (0..self.num_observables)
            .map(|i| ((acc >> i) & 1) as u8)
            .collect()
    }
}

/// XOR of correction-edge endpoints on detector nodes only (boundary ignored).
pub fn detector_syndrome_from_corrections(
    num_detectors: usize,
    corrections: &[EdgeId],
    u: &[NodeId],
    v: &[NodeId],
) -> Vec<u8> {
    let mut s = vec![0u8; num_detectors];
    for &e in corrections {
        for endpoint in [u[e], v[e]] {
            if endpoint < num_detectors {
                s[endpoint] ^= 1;
            }
        }
    }
    s
}
