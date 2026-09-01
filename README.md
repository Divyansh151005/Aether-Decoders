# Aether-Decoders

**Real-time fault-tolerant quantum error correction** — integer Union-Find for surface codes, Relay-BP for qLDPC, and FPGA-mappable RTL with bit-identical software co-simulation.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/Rust-2021-orange.svg)](https://www.rust-lang.org/)
[![Milestones](https://img.shields.io/badge/Milestones-M1–M72-purple.svg)](Docs/Progress)

---

## Why this exists

Fault-tolerant quantum computers must decode error syndromes and return corrections within a **microsecond-scale** budget. CPU-only decoders struggle at scale. Aether-Decoders targets a **hybrid stack**: fast Union-Find on graphlike surface-code DEMs, Relay-BP on hypergraph qLDPC codes, optional MWPM fallback, and a path to **bare-metal FPGA** PE grids (Helios-style scheduling).

Software correctness is validated first — then Verilog, Verilator/Icarus co-sim, DPI, and Yosys resource sweeps.

---

## Highlights

| Area | What’s implemented |
| --- | --- |
| **UF core** | Flat struct-of-arrays graph, DSU, discrete growth, peeling over **F₂** — no `petgraph` |
| **Stim pipeline** | DEM compiler, `decode_shots`, Sinter adapter, threshold sweeps vs PyMatching |
| **Relay-BP** | DMem-BP + relay legs (Müller et al. [arXiv:2506.01779](https://arxiv.org/abs/2506.01779)) on IBM BB test circuits |
| **Co-simulation** | `cycle_model` + `helios_pe` + RTL peel FSM — corrections bit-identical to software |
| **RTL scale** | PE-mesh grow→peel through phenom **V=72** and circuit **V=392** Stim graphs |
| **FPGA prep** | Yosys S0–S4 synth CSVs; flat grow cliff at **N>16** LUTs (documented) |
| **Helios-n** | Partition, PE coloring, multiplexed grow oracle ≡ flat M44; Stage D ≡ `decode_cosim` |

**Current milestone:** **M72** — Helios-n Stage D peel co-sim vs M45 on phenom d=3 r=3.

Full evidence table: [`Docs/Progress`](Docs/Progress).

---

## Architecture

```
┌─────────────────┐     ┌──────────────────────────────────────┐
│ Stim / Sinter   │────▶│  aether_decoders (Rust)               │
│ syndrome shots  │     │  UF grow → merge → peel │ Relay-BP    │
└─────────────────┘     └───────────┬──────────────────────────┘
                                    │ bit-identical goldens
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              rtl/ Verilog    dpi/ (Verilator)   fpga/ Yosys
              Icarus co-sim   live Rust↔RTL      LUT/FF sweeps
```

**Locked decoder rules** (do not “simplify” for hardware):

- Active cluster = odd parity **and** not touching a virtual boundary  
- Peel from frozen `syndrome[]`, not DSU-mutated parity  
- Union-by-size; skip same-root growth; unique boundary per degree-1 DEM error  

---

## Quick start

### Prerequisites

- **Rust** (2021 edition) — `cargo`
- **Python 3.10+** — Stim, Sinter, PyMatching for sweeps
- **Optional:** Icarus Verilog / Verilator for RTL sim; Yosys for FPGA synth scripts

### Build & test

```bash
cargo test -p aether_decoders
cargo test -p aether_uf_dpi   # DPI crate (after Verilator build)
```

### Decode Stim shots (UF)

```bash
# Compile DEM once, stream 0/1 shot lines
cargo run --release --bin decode_shots -- dem.json shots.txt
```

### Python smoke (surface code)

```bash
pip install -r python/requirements.txt
PYTHONPATH=python python3 scripts/stim_surface_code_smoke.py
```

### RTL co-sim smoke (Blueprint)

```bash
./scripts/rtl_decode_sim.sh      # grow → peel vs decode_cosim
./scripts/pe_mesh_stim_r3_sim.sh # phenom d=3 r=3 PE-mesh (M44)
```

---

## Repository layout

| Path | Purpose |
| --- | --- |
| `src/` | Rust library: graph, engine, `helios_pe`, `helios_n_pe`, `relay_bp`, `cycle_model` |
| `dpi/` | Verilator DPI bridge for live Rust↔RTL co-sim |
| `rtl/` | SystemVerilog: grow/merge, peel FSM, PE-mesh, Helios-2 micro, H10 ring |
| `scripts/` | Stim harnesses, threshold sweeps, Relay bake-offs, FPGA Yosys runners |
| `python/` | DEM helpers + Sinter custom decoder |
| `testdata/` | IBM bicycle bivariate Stim circuits |
| `results/` | Cited measurement CSVs (threshold, FPGA, Helios-n) — **do not overwrite** |
| `Docs/` | Progress log, hardware mapping, milestone research notes |

---

## Research & references

- **Helios PE grid:** Maurya et al. [arXiv:2406.08491](https://arxiv.org/abs/2406.08491)  
- **Relay-BP:** Müller et al. [arXiv:2506.01779](https://arxiv.org/abs/2506.01779)  
- **Simulation:** [Stim](https://github.com/quantumlib/Stim), [Sinter](https://github.com/quantumlib/Stim/tree/main/doc/sinter.md)  
- **Surface-code baseline:** [PyMatching](https://github.com/oscarhiggott/PyMatching)

---

## Status & roadmap

| Phase | Focus |
| --- | --- |
| **Done (M1–M72)** | Software UF + Relay-BP, RTL co-sim to Stim scale, FPGA Yosys cliffs, Helios-n oracle |
| **Next** | SV Helios-n schedule RTL (N≤16, N_CTX≥16), Vivado S0, or G4 netlist sim |

See [`Docs/Progress`](Docs/Progress) for milestone evidence and “do not re-introduce” corrections.

---

## License

MIT — see project metadata in `Cargo.toml`.

---

<p align="center">
  <sub>Built for microsecond-scale FTQC decoding · Software-first, evidence-driven</sub>
</p>
