//! Count UF `DecodeError` outcomes per shot (H11 measurement gate, M51).
//! Does not abort the batch on Unsolvable / IterationLimit.
//!
//! stdout JSON line: {"ok":N,"unsolvable":N,"iter_limit":N,"shots":N}

use std::fs;
use std::io::{self, BufRead};
use std::path::PathBuf;
use std::process::ExitCode;

use aether_decoders::{CompiledUfDecoder, DecodeError, GraphlikeError};
use serde::Deserialize;
use serde_json::json;

#[derive(Deserialize)]
struct DemFile {
    num_detectors: usize,
    num_observables: usize,
    #[serde(default = "default_lambda")]
    lambda: f64,
    errors: Vec<ErrorFile>,
}

fn default_lambda() -> f64 {
    aether_decoders::DEFAULT_LAMBDA
}

#[derive(Deserialize)]
struct ErrorFile {
    detectors: Vec<usize>,
    probability: f64,
    #[serde(default)]
    observables: Vec<usize>,
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let Some(graph_path) = args.next() else {
        eprintln!("usage: count_uf_decode_errors <dem.json> <shots.txt>");
        return ExitCode::from(2);
    };
    let Some(shots_path) = args.next() else {
        eprintln!("missing shots.txt");
        return ExitCode::from(2);
    };

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
    let errors: Vec<GraphlikeError> = dem
        .errors
        .into_iter()
        .map(|e| GraphlikeError {
            detectors: e.detectors,
            probability: e.probability,
            observables: e.observables,
        })
        .collect();
    let mut decoder = match CompiledUfDecoder::compile(
        dem.num_detectors,
        dem.num_observables,
        &errors,
        dem.lambda,
    ) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("compile failed: {e:?}");
            return ExitCode::from(1);
        }
    };

    let file = match fs::File::open(PathBuf::from(&shots_path)) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("failed to read shots: {e}");
            return ExitCode::from(1);
        }
    };
    let mut in_buf = io::BufReader::new(file);
    let mut line = String::new();
    let mut ok = 0u64;
    let mut unsolvable = 0u64;
    let mut iter_limit = 0u64;
    let mut shots = 0u64;

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
        let bits: String = line
            .chars()
            .filter(|c| *c == '0' || *c == '1')
            .collect();
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
        let events: Vec<u8> = bits.bytes().map(|b| u8::from(b == b'1')).collect();
        shots += 1;
        match decoder.decode_observables(&events) {
            Ok(_) => ok += 1,
            Err(DecodeError::Unsolvable { .. }) => unsolvable += 1,
            Err(DecodeError::IterationLimit { .. }) => iter_limit += 1,
        }
    }

    println!(
        "{}",
        json!({
            "ok": ok,
            "unsolvable": unsolvable,
            "iter_limit": iter_limit,
            "shots": shots,
        })
    );
    ExitCode::SUCCESS
}
