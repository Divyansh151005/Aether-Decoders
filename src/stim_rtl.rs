//! Stim DEM + shots → live RTL goldens (shared by `gen_stim_rtl_vectors` + DPI M28).

use std::fs;
use std::io::{BufRead, BufReader};
use std::path::Path;

use serde::Deserialize;

use crate::{
    decode_cosim, neutralize_helios_pe, CompiledUfDecoder, EdgeState, GraphlikeError, DEFAULT_LAMBDA,
};

#[derive(Deserialize)]
struct DemFile {
    num_detectors: usize,
    num_observables: usize,
    #[serde(default = "default_lambda")]
    lambda: f64,
    errors: Vec<ErrorFile>,
}

fn default_lambda() -> f64 {
    DEFAULT_LAMBDA
}

#[derive(Deserialize)]
struct ErrorFile {
    detectors: Vec<usize>,
    probability: f64,
    #[serde(default)]
    observables: Vec<usize>,
}

/// One Stim shot golden for grow/peel RTL.
#[derive(Clone, Debug)]
pub struct StimRtlCase {
    pub syndrome: Vec<u8>,
    pub cycles: u32,
    pub solid: Vec<bool>,
    pub corr: Vec<bool>,
    pub peel_ops: u32,
    /// Packed observable prediction (bit i = observable i); surface memory typically 1 bit.
    pub obs: u64,
}

/// Compiled Stim graph + nontrivial shot goldens (cosim-gated).
#[derive(Clone, Debug)]
pub struct StimRtlBundle {
    pub n: u32,
    pub m: u32,
    pub num_observables: u32,
    pub is_boundary: Vec<u8>,
    pub eu: Vec<u32>,
    pub ev: Vec<u32>,
    pub cap: Vec<u32>,
    pub obs_mask: Vec<u64>,
    pub cases: Vec<StimRtlCase>,
    pub shots_checked: usize,
    pub nontrivial: usize,
}

/// Load DEM JSON + 0/1 shot lines; gate every shot with decode ≡ cosim ≡ helios solids.
pub fn load_stim_rtl_bundle(
    dem_path: &Path,
    shots_path: &Path,
    max_rtl_cases: usize,
) -> Result<StimRtlBundle, String> {
    let dem: DemFile = serde_json::from_str(
        &fs::read_to_string(dem_path).map_err(|e| format!("DEM read: {e}"))?,
    )
    .map_err(|e| format!("DEM JSON: {e}"))?;

    let errors: Vec<GraphlikeError> = dem
        .errors
        .into_iter()
        .map(|e| GraphlikeError {
            detectors: e.detectors,
            probability: e.probability,
            observables: e.observables,
        })
        .collect();
    let mut decoder = CompiledUfDecoder::compile(
        dem.num_detectors,
        dem.num_observables,
        &errors,
        dem.lambda,
    )
    .map_err(|e| format!("compile: {e:?}"))?;

    let g0 = decoder.graph().clone();
    let n = g0.num_nodes();
    let m = g0.num_edges();
    if n > 65535 || m > 65535 {
        return Err(format!("graph V={n} E={m} exceeds 16-bit RTL index"));
    }

    let file = fs::File::open(shots_path).map_err(|e| format!("shots: {e}"))?;
    let mut cases = Vec::new();
    let mut total = 0usize;
    let mut nontrivial = 0usize;

    for (line_no, line) in BufReader::new(file).lines().enumerate() {
        let line = line.map_err(|e| format!("shots line: {e}"))?;
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if line.len() != dem.num_detectors {
            return Err(format!(
                "shot {}: len {} != num_detectors {}",
                line_no + 1,
                line.len(),
                dem.num_detectors
            ));
        }
        let events: Vec<u8> = line
            .bytes()
            .map(|c| match c {
                b'0' => Ok(0),
                b'1' => Ok(1),
                _ => Err(format!("shot {}: bad char", line_no + 1)),
            })
            .collect::<Result<_, _>>()?;
        total += 1;
        if events.iter().any(|&b| b != 0) {
            nontrivial += 1;
        }

        decoder
            .load_detection_events(&events)
            .map_err(|e| format!("shot {}: load {e:?}", line_no + 1))?;
        let g = decoder.graph().clone();

        let cosim = decode_cosim(&g).map_err(|e| format!("shot {}: cosim {e:?}", line_no + 1))?;
        let mut g_dec = g.clone();
        let corrections = g_dec
            .decode()
            .map_err(|e| format!("shot {}: decode {e:?}", line_no + 1))?;
        if corrections != cosim.corrections {
            return Err(format!("shot {}: decode != cosim", line_no + 1));
        }
        let pe =
            neutralize_helios_pe(&g).map_err(|e| format!("shot {}: helios_pe {e:?}", line_no + 1))?;
        let solid_pe = pe.solid.clone();
        let solid_dec: Vec<bool> = g_dec
            .state
            .iter()
            .map(|s| *s == EdgeState::Solid)
            .collect();
        if solid_pe != solid_dec {
            return Err(format!("shot {}: solid pe != decode", line_no + 1));
        }
        if pe.stats.growth_cycles != cosim.stats.growth_cycles {
            return Err(format!("shot {}: growth cycles mismatch", line_no + 1));
        }

        if cases.len() < max_rtl_cases && events.iter().any(|&b| b != 0) {
            let mut syn = g.syndrome.clone();
            syn.resize(n, 0);
            let mut corr = vec![false; m];
            for &e in &corrections {
                corr[e] = true;
            }
            cases.push(StimRtlCase {
                syndrome: syn,
                cycles: pe.stats.growth_cycles as u32,
                solid: solid_pe,
                corr,
                peel_ops: cosim.stats.peel_ops as u32,
                obs: {
                    let bits = decoder.observables_from_corrections(&corrections);
                    let mut w = 0u64;
                    for (i, &b) in bits.iter().enumerate() {
                        if b != 0 {
                            w |= 1u64 << i;
                        }
                    }
                    w
                },
            });
        }
    }

    if cases.is_empty() {
        return Err("no nontrivial shots for RTL export".into());
    }

    Ok(StimRtlBundle {
        n: n as u32,
        m: m as u32,
        num_observables: dem.num_observables as u32,
        is_boundary: g0.is_boundary.clone(),
        eu: g0.edge_u.iter().map(|&u| u as u32).collect(),
        ev: g0.edge_v.iter().map(|&v| v as u32).collect(),
        cap: g0.capacity.iter().map(|&c| c as u32).collect(),
        obs_mask: g0.obs_mask.clone(),
        cases,
        shots_checked: total,
        nontrivial,
    })
}
