//! M72: Helios-n grow + peel vs `decode_cosim` (Stage D / M45 criterion).
//!
//! Usage:
//!   helios_n_decode_cosim <dem.json> <shots.txt> <coloring.csv> <out.csv> [max_shots]

use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::time::Instant;

use serde::Deserialize;

use aether_decoders::{
    build_helios_n_schedule, load_helios_n_map, CompiledUfDecoder, GraphlikeError, DEFAULT_LAMBDA,
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

fn main() {
    let mut args = env::args().skip(1);
    let dem_path = PathBuf::from(args.next().expect("dem.json"));
    let shots_path = PathBuf::from(args.next().expect("shots.txt"));
    let coloring = PathBuf::from(args.next().expect("coloring.csv"));
    let out_path = PathBuf::from(args.next().expect("out.csv"));
    let max_shots: usize = args
        .next()
        .as_deref()
        .unwrap_or("24")
        .parse()
        .expect("max_shots");

    let t0 = Instant::now();
    eprintln!(
        "helios_n_decode_cosim: dem={} shots={} map={} max_shots={max_shots}",
        dem_path.display(),
        shots_path.display(),
        coloring.display()
    );
    eprintln!("ETA ≈ 45s (compile + ≤{max_shots} nontrivial Stage D shots)");

    let map = load_helios_n_map(&coloring).unwrap_or_else(|e| panic!("map: {e}"));
    let dem: DemFile = serde_json::from_str(
        &fs::read_to_string(&dem_path).unwrap_or_else(|e| panic!("dem: {e}")),
    )
    .unwrap_or_else(|e| panic!("dem json: {e}"));
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
    .unwrap_or_else(|e| panic!("compile: {e:?}"));

    let g0 = decoder.graph().clone();
    let schedule =
        build_helios_n_schedule(map, &g0).unwrap_or_else(|e| panic!("schedule: {e}"));
    eprintln!(
        "graph V={} E={} n_parts={} n_phys={} induced={} cross={}",
        g0.num_nodes(),
        g0.num_edges(),
        schedule.map.n_parts,
        schedule.map.n_phys,
        schedule.n_induced,
        schedule.n_cross
    );

    let mut out_f = fs::File::create(&out_path).unwrap_or_else(|e| panic!("out: {e}"));
    writeln!(
        out_f,
        "shot,ok,growth_cycles,peel_ops,part_visits,n_parts,n_phys,V,E,corr_weight"
    )
    .unwrap();

    let file = fs::File::open(&shots_path).unwrap_or_else(|e| panic!("shots: {e}"));
    let mut shot_idx = 0usize;
    let mut checked = 0usize;
    let mut last_hb = Instant::now();
    for line in BufReader::new(file).lines() {
        let line = line.unwrap();
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        shot_idx += 1;
        if line.len() != dem.num_detectors {
            panic!(
                "shot {shot_idx}: len {} != num_detectors {}",
                line.len(),
                dem.num_detectors
            );
        }
        if line.bytes().all(|c| c == b'0') {
            continue;
        }
        if checked >= max_shots {
            break;
        }
        let events: Vec<u8> = line
            .bytes()
            .map(|c| match c {
                b'0' => 0,
                b'1' => 1,
                _ => panic!("shot {shot_idx}: bad char"),
            })
            .collect();
        decoder
            .load_detection_events(&events)
            .unwrap_or_else(|e| panic!("shot {shot_idx}: load {e:?}"));
        let g = decoder.graph().clone();
        let (corr, stats, peel_ops) =
            aether_decoders::decode_helios_n_pe(&g, &schedule)
                .unwrap_or_else(|e| panic!("shot {shot_idx}: helios_n {e:?}"));
        let cosim = aether_decoders::decode_cosim(&g)
            .unwrap_or_else(|e| panic!("shot {shot_idx}: cosim {e:?}"));
        if corr != cosim.corrections {
            panic!("shot {shot_idx}: corrections differ");
        }
        if peel_ops != cosim.stats.peel_ops {
            panic!(
                "shot {shot_idx}: peel_ops helios_n={peel_ops} cosim={}",
                cosim.stats.peel_ops
            );
        }
        checked += 1;
        writeln!(
            out_f,
            "{shot_idx},1,{},{},{},{},{},{},{},{}",
            stats.flat.growth_cycles,
            peel_ops,
            stats.part_visits,
            stats.n_parts,
            stats.n_phys,
            g.num_nodes(),
            g.num_edges(),
            corr.len()
        )
        .unwrap();

        if last_hb.elapsed().as_secs() >= 15 {
            let el = t0.elapsed().as_secs_f64();
            let rem = if checked > 0 {
                el / checked as f64 * (max_shots - checked) as f64
            } else {
                45.0
            };
            eprintln!(
                "[heartbeat] helios_n_decode_cosim checked={checked}/{max_shots} elapsed={el:.1}s ETA_remaining≈{rem:.0}s"
            );
            last_hb = Instant::now();
        }
    }

    eprintln!(
        "PASS checked={checked} elapsed={:.2}s → {}",
        t0.elapsed().as_secs_f64(),
        out_path.display()
    );
}
