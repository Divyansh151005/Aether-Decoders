#!/usr/bin/env bash
# Generate helios_pe golden vectors and simulate parameterized UF RTL (M18).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cargo run --quiet --bin gen_rtl_vectors
cd rtl
iverilog -g2012 -o tb_param_sim aether_uf_grow_merge.sv tb_aether_uf_grow_merge.sv
./tb_param_sim
