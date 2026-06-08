#!/usr/bin/env bash
# M19: grow+merge+peel RTL vs decode_cosim Blueprint goldens.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cargo test --quiet
cargo run --quiet --bin gen_rtl_vectors
cd rtl
iverilog -g2012 -o tb_decode_sim \
  aether_uf_grow_merge.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_decode.sv
./tb_decode_sim
iverilog -g2012 -o tb_param_sim aether_uf_grow_merge.sv tb_aether_uf_grow_merge.sv
./tb_param_sim
