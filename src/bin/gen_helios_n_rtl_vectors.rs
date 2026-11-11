//! M74: Helios-n schedule tables + M71/M72 oracle goldens for the SV lattice.
//!
//! Usage:
//!   gen_helios_n_rtl_vectors <dem.json> <shots.txt> <coloring.csv> <out.sv> [max_cases]
//!
//! Every exported shot is gated by `assert_helios_n_matches_flat` (Stage C) and
//! `assert_helios_n_decode_matches_cosim` (Stage D) before it becomes an RTL golden.

use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use serde::Deserialize;

use aether_decoders::{
    assert_helios_n_decode_matches_cosim, assert_helios_n_matches_flat, build_helios_n_schedule,
    decode_helios_n_pe, load_helios_n_map, neutralize_helios_n_pe, CompiledUfDecoder,
    GraphlikeError, DEFAULT_LAMBDA,
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

struct Case {
    syndrome: Vec<u8>,
    iters: u64,
    solid: Vec<bool>,
    corr: Vec<bool>,
    peel_ops: u64,
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.len() < 4 {
        eprintln!(
            "usage: gen_helios_n_rtl_vectors <dem.json> <shots.txt> <coloring.csv> <out.sv> [max_cases]"
        );
        return ExitCode::from(2);
    }
    let dem_path = PathBuf::from(&args[0]);
    let shots_path = PathBuf::from(&args[1]);
    let map_path = PathBuf::from(&args[2]);
    let out_path = PathBuf::from(&args[3]);
    let max_cases: usize = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(16);

    match run(&dem_path, &shots_path, &map_path, &out_path, max_cases) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("gen_helios_n_rtl_vectors: {e}");
            ExitCode::from(1)
        }
    }
}

fn run(
    dem_path: &PathBuf,
    shots_path: &PathBuf,
    map_path: &PathBuf,
    out_path: &PathBuf,
    max_cases: usize,
) -> Result<(), String> {
    let map = load_helios_n_map(map_path)?;
    let dem: DemFile = serde_json::from_str(
        &fs::read_to_string(dem_path).map_err(|e| format!("dem read: {e}"))?,
    )
    .map_err(|e| format!("dem json: {e}"))?;
    let errors: Vec<GraphlikeError> = dem
        .errors
        .into_iter()
        .map(|e| GraphlikeError {
            detectors: e.detectors,
            probability: e.probability,
            observables: e.observables,
        })
        .collect();
    let mut decoder =
        CompiledUfDecoder::compile(dem.num_detectors, dem.num_observables, &errors, dem.lambda)
            .map_err(|e| format!("compile: {e:?}"))?;
    let g0 = decoder.graph().clone();
    let schedule = build_helios_n_schedule(map, &g0)?;
    let n = g0.num_nodes();
    let m = g0.num_edges();
    let n_parts = schedule.map.n_parts as usize;
    let n_phys = schedule.map.n_phys as usize;
    let slots = schedule.edges_by_part.iter().map(Vec::len).max().unwrap_or(0);

    // Writeback table: one virtual node per (part, phys) — Helios "same part → distinct PE".
    let mut wb: Vec<Option<usize>> = vec![None; n_parts * n_phys];
    for v in 0..n {
        let k = schedule.map.part[v] as usize;
        let p = schedule.map.phys_pe[v] as usize;
        if let Some(prev) = wb[k * n_phys + p] {
            return Err(format!("part {k} maps virtual {prev} and {v} to phys {p}"));
        }
        wb[k * n_phys + p] = Some(v);
    }

    let file = fs::File::open(shots_path).map_err(|e| format!("shots: {e}"))?;
    let mut cases = Vec::new();
    for (line_no, line) in BufReader::new(file).lines().enumerate() {
        let line = line.map_err(|e| format!("shots read: {e}"))?;
        let line = line.trim();
        if line.is_empty() || line.bytes().all(|c| c == b'0') {
            continue;
        }
        if cases.len() >= max_cases {
            break;
        }
        let events: Vec<u8> = line.bytes().map(|c| u8::from(c == b'1')).collect();
        decoder
            .load_detection_events(&events)
            .map_err(|e| format!("shot {}: load {e:?}", line_no + 1))?;
        let g = decoder.graph().clone();
        assert_helios_n_matches_flat(&g, &schedule)
            .map_err(|e| format!("shot {}: stage C {e}", line_no + 1))?;
        assert_helios_n_decode_matches_cosim(&g, &schedule)
            .map_err(|e| format!("shot {}: stage D {e}", line_no + 1))?;
        let grow = neutralize_helios_n_pe(&g, &schedule)
            .map_err(|e| format!("shot {}: grow {e:?}", line_no + 1))?;
        let (corrections, _, peel_ops) = decode_helios_n_pe(&g, &schedule)
            .map_err(|e| format!("shot {}: decode {e:?}", line_no + 1))?;
        let mut corr = vec![false; m];
        for &e in &corrections {
            corr[e] = true;
        }
        let mut syndrome = g.syndrome.clone();
        syndrome.resize(n, 0);
        cases.push(Case {
            syndrome,
            iters: grow.stats.flat.growth_cycles,
            solid: grow.solid,
            corr,
            peel_ops,
        });
    }
    if cases.is_empty() {
        return Err("no nontrivial shots".into());
    }

    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir: {e}"))?;
    }
    let mut f = fs::File::create(out_path).map_err(|e| format!("out: {e}"))?;
    let w = |f: &mut fs::File, s: String| writeln!(f, "{s}").map_err(|e| format!("write: {e}"));

    w(&mut f, "// Auto-generated by gen_helios_n_rtl_vectors — do not edit.".into())?;
    w(
        &mut f,
        format!(
            "// V={n} E={m} n_parts={n_parts} n_phys={n_phys} slots={slots} induced={} cross={}; {} cases (oracle-gated).",
            schedule.n_induced,
            schedule.n_cross,
            cases.len()
        ),
    )?;
    w(&mut f, "`ifndef HELIOS_N_CASES_SV".into())?;
    w(&mut f, "`define HELIOS_N_CASES_SV".into())?;
    w(&mut f, format!("localparam int HN_V = {n};"))?;
    w(&mut f, format!("localparam int HN_E = {m};"))?;
    w(&mut f, format!("localparam int HN_NPARTS = {n_parts};"))?;
    w(&mut f, format!("localparam int HN_NPHYS = {n_phys};"))?;
    w(&mut f, format!("localparam int HN_SLOTS = {slots};"))?;
    w(&mut f, format!("localparam int HN_NUM_CASES = {};", cases.len()))?;
    w(&mut f, String::new())?;

    w(&mut f, "task automatic load_hn_graph;".into())?;
    w(&mut f, "  begin".into())?;
    for v in 0..n {
        w(&mut f, format!("    bnd_mem[{v}] = 8'd{};", g0.is_boundary[v]))?;
    }
    for e in 0..m {
        w(
            &mut f,
            format!(
                "    eu_mem[{e}] = 16'd{}; ev_mem[{e}] = 16'd{}; cap_mem[{e}] = 16'd{};",
                g0.edge_u[e], g0.edge_v[e], g0.capacity[e]
            ),
        )?;
    }
    for (k, edges) in schedule.edges_by_part.iter().enumerate() {
        for (s, &e) in edges.iter().enumerate() {
            let i = k * slots + s;
            let (u, v) = (g0.edge_u[e], g0.edge_v[e]);
            w(
                &mut f,
                format!(
                    "    sl_valid[{i}] = 1'b1; sl_edge[{i}] = 16'd{e}; sl_pu[{i}] = 8'd{}; sl_cu[{i}] = 8'd{}; sl_pv[{i}] = 8'd{}; sl_cv[{i}] = 8'd{};",
                    schedule.map.phys_pe[u],
                    schedule.map.part[u],
                    schedule.map.phys_pe[v],
                    schedule.map.part[v]
                ),
            )?;
        }
    }
    for (i, slot) in wb.iter().enumerate() {
        if let Some(v) = slot {
            w(&mut f, format!("    wb_valid[{i}] = 1'b1; wb_virt[{i}] = 16'd{v};"))?;
        }
    }
    w(&mut f, "  end".into())?;
    w(&mut f, "endtask".into())?;
    w(&mut f, String::new())?;

    for (i, c) in cases.iter().enumerate() {
        w(&mut f, format!("localparam int HN{i}_ITERS = {};", c.iters))?;
        w(&mut f, format!("localparam int HN{i}_PEEL_OPS = {};", c.peel_ops))?;
        w(&mut f, format!("task automatic load_hn_case_{i};"))?;
        w(&mut f, "  begin".into())?;
        for (v, &s) in c.syndrome.iter().enumerate() {
            if s != 0 {
                w(&mut f, format!("    syn_mem[{v}] = 8'd1;"))?;
            }
        }
        for (e, &s) in c.solid.iter().enumerate() {
            if s {
                w(&mut f, format!("    exp_solid[{e}] = 1'b1;"))?;
            }
        }
        for (e, &s) in c.corr.iter().enumerate() {
            if s {
                w(&mut f, format!("    exp_corr[{e}] = 1'b1;"))?;
            }
        }
        w(&mut f, "  end".into())?;
        w(&mut f, "endtask".into())?;
    }
    w(&mut f, "`endif".into())?;

    let run_path = out_path.with_file_name("helios_n_run.sv");
    let mut rf = fs::File::create(&run_path).map_err(|e| format!("run out: {e}"))?;
    writeln!(rf, "// Auto-generated run body — do not edit.").map_err(|e| e.to_string())?;
    for i in 0..cases.len() {
        writeln!(
            rf,
            "clear_case(); load_hn_case_{i}(); run_case({i}, HN{i}_ITERS, HN{i}_PEEL_OPS);"
        )
        .map_err(|e| e.to_string())?;
    }

    println!(
        "oracle OK: {} cases; V={n} E={m} n_parts={n_parts} n_phys={n_phys} slots={slots} → {} (+ {})",
        cases.len(),
        out_path.display(),
        run_path.display()
    );
    Ok(())
}
