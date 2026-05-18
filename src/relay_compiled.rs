//! Compile a Stim DEM (any hyperedge degree) into a Relay-BP decoder.

use crate::relay_bp::{
    observables_from_errors, RelayBp, RelayConfig, RelayError, RelayResult, TannerGraph,
};

/// One DEM error mechanism (column of H), any detector degree.
#[derive(Clone, Debug)]
pub struct DemError {
    pub detectors: Vec<usize>,
    pub probability: f64,
    pub observables: Vec<usize>,
}

/// Relay-BP decoder compiled from a detector-error model.
#[derive(Clone, Debug)]
pub struct CompiledRelayDecoder {
    relay: RelayBp,
    obs_masks: Vec<u64>,
    num_detectors: usize,
    num_observables: usize,
}

impl CompiledRelayDecoder {
    pub fn compile(
        num_detectors: usize,
        num_observables: usize,
        errors: &[DemError],
        config: RelayConfig,
    ) -> Result<Self, RelayError> {
        if num_observables > 64 {
            return Err(RelayError::ObservableLen {
                got: num_observables,
                expected: 64,
            });
        }
        let mut columns: Vec<Vec<usize>> = Vec::new();
        let mut probs: Vec<f64> = Vec::new();
        let mut obs_masks: Vec<u64> = Vec::new();

        for err in errors {
            if err.probability <= 0.0 || err.probability >= 1.0 {
                continue;
            }
            if err.detectors.is_empty() {
                // Detector-free error: only flips observables. Still a BP variable.
                columns.push(Vec::new());
            } else {
                columns.push(err.detectors.clone());
            }
            probs.push(err.probability);
            let mut mask = 0u64;
            for &obs in &err.observables {
                if obs >= num_observables {
                    return Err(RelayError::ObservableLen {
                        got: obs + 1,
                        expected: num_observables,
                    });
                }
                mask |= 1u64 << obs;
            }
            obs_masks.push(mask);
        }

        if columns.is_empty() {
            return Err(RelayError::Empty);
        }

        // Variables with empty columns (obs-only) still need Tanner nodes;
        // TannerGraph allows isolated variables (no edges).
        let graph = TannerGraph::from_columns(num_detectors, &columns)?;
        let relay = RelayBp::new(graph, &probs, config)?;
        Ok(Self {
            relay,
            obs_masks,
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

    pub fn decode_detailed(&mut self, syndrome: &[u8]) -> Result<RelayResult, RelayError> {
        self.relay.decode(syndrome)
    }

    /// Decode and return observable bits (length = num_observables).
    pub fn decode_observables(&mut self, syndrome: &[u8]) -> Result<Vec<u8>, RelayError> {
        let result = self.relay.decode(syndrome)?;
        Ok(observables_from_errors(
            &result.hat_e,
            &self.obs_masks,
            self.num_observables,
        ))
    }
}
