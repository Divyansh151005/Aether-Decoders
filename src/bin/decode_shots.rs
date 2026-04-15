//! Batch-decode Stim detection events from a JSON graphlike DEM.

use std::fs;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use aether_decoders::{CompiledUfDecoder, GraphlikeError};
use serde::Deserialize;

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
        eprintln!("usage: decode_shots <dem.json> [shots.txt]");
        eprintln!("shots.txt: one 0/1 string per line, length = num_detectors");
        eprintln!("writes observable 0/1 strings to stdout");
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
        let events: Vec<u8> = bits
            .bytes()
            .map(|b| u8::from(b == b'1'))
            .collect();
        match decoder.decode_observables(&events) {
            Ok(obs) => {
                for bit in obs {
                    let _ = write!(out, "{bit}");
                }
                let _ = writeln!(out);
                if out.flush().is_err() {
                    return ExitCode::from(1);
                }
            }
            Err(e) => {
                eprintln!("decode failed: {e:?}");
                return ExitCode::from(1);
            }
        }
    }
    let _ = out.flush();
    ExitCode::SUCCESS
}
