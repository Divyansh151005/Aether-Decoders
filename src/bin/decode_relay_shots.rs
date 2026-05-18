//! Batch-decode Stim detection events with Relay-BP (hypergraph DEM OK).

use std::fs;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use aether_decoders::{CompiledRelayDecoder, DemError, RelayConfig};
use serde::Deserialize;

#[derive(Deserialize)]
struct DemFile {
    num_detectors: usize,
    num_observables: usize,
    errors: Vec<ErrorFile>,
    #[serde(default)]
    relay: Option<RelayFile>,
}

#[derive(Deserialize)]
struct ErrorFile {
    detectors: Vec<usize>,
    probability: f64,
    #[serde(default)]
    observables: Vec<usize>,
}

#[derive(Deserialize, Default)]
struct RelayFile {
    #[serde(default = "default_stop")]
    stop_nconv: usize,
    #[serde(default = "default_sets")]
    num_sets: usize,
    #[serde(default = "default_pre")]
    pre_iter: usize,
    #[serde(default = "default_set_iter")]
    set_max_iter: usize,
    #[serde(default = "default_gamma0")]
    gamma0: f64,
    #[serde(default = "default_gamma_lo")]
    gamma_lo: f64,
    #[serde(default = "default_gamma_hi")]
    gamma_hi: f64,
    #[serde(default = "default_seed")]
    seed: u64,
}

fn default_stop() -> usize {
    1
}
fn default_sets() -> usize {
    40
}
fn default_pre() -> usize {
    80
}
fn default_set_iter() -> usize {
    60
}
fn default_gamma0() -> f64 {
    0.125
}
fn default_gamma_lo() -> f64 {
    -0.24
}
fn default_gamma_hi() -> f64 {
    0.66
}
fn default_seed() -> u64 {
    1
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let Some(graph_path) = args.next() else {
        eprintln!("usage: decode_relay_shots <dem.json> [shots.txt]");
        eprintln!("shots.txt: one 0/1 string per line, length = num_detectors");
        eprintln!("writes observable 0/1 strings to stdout (flush per line)");
        return ExitCode::from(2);
    };
    let shots_path = args.next().map(PathBuf::from);

    let raw = match fs::read_to_string(&graph_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("failed to read {graph_path}: {e}");
            return ExitCode::from(1);
        }
    };
    let dem: DemFile = match serde_json::from_str(&raw) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("invalid DEM JSON: {e}");
            return ExitCode::from(1);
        }
    };
    let rf = dem.relay.unwrap_or_default();
    let config = RelayConfig {
        stop_nconv: rf.stop_nconv,
        num_sets: rf.num_sets,
        pre_iter: rf.pre_iter,
        set_max_iter: rf.set_max_iter,
        gamma0: rf.gamma0,
        gamma_dist_interval: (rf.gamma_lo, rf.gamma_hi),
        seed: rf.seed,
    };
    let errors: Vec<DemError> = dem
        .errors
        .into_iter()
        .map(|e| DemError {
            detectors: e.detectors,
            probability: e.probability,
            observables: e.observables,
        })
        .collect();
    let mut decoder =
        match CompiledRelayDecoder::compile(dem.num_detectors, dem.num_observables, &errors, config)
        {
            Ok(d) => d,
            Err(e) => {
                eprintln!("compile failed: {e:?}");
                return ExitCode::from(1);
            }
        };

    let stdin = io::stdin();
    let mut in_buf: Box<dyn BufRead> = if let Some(path) = shots_path {
        match fs::File::open(&path) {
            Ok(f) => Box::new(io::BufReader::new(f)),
            Err(e) => {
                eprintln!("failed to read shots: {e}");
                return ExitCode::from(1);
            }
        }
    } else {
        Box::new(stdin.lock())
    };

    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    let mut line = String::new();
    loop {
        line.clear();
        match in_buf.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {}
            Err(e) => {
                eprintln!("read error: {e}");
                return ExitCode::from(1);
            }
        }
        let bits: String = line.chars().filter(|c| *c == '0' || *c == '1').collect();
        if bits.is_empty() {
            continue;
        }
        if bits.len() != dem.num_detectors {
            eprintln!(
                "shot length {} != num_detectors {}",
                bits.len(),
                dem.num_detectors
            );
            return ExitCode::from(1);
        }
        let events: Vec<u8> = bits.bytes().map(|b| if b == b'1' { 1 } else { 0 }).collect();
        let obs = match decoder.decode_observables(&events) {
            Ok(o) => o,
            Err(e) => {
                eprintln!("decode failed: {e:?}");
                return ExitCode::from(1);
            }
        };
        for bit in obs {
            let _ = write!(out, "{bit}");
        }
        let _ = writeln!(out);
        let _ = out.flush();
    }
    ExitCode::SUCCESS
}
