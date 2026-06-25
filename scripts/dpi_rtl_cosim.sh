#!/usr/bin/env bash
# M26: Verilator DPI co-sim — Blueprint grow/peel vs live Rust goldens.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cargo test -p aether_decoders --quiet
cargo build -p aether_uf_dpi --release

LIBDIR="$ROOT/target/release"
# cdylib name: libaether_uf_dpi.{dylib,so,dll}
if [[ "$(uname -s)" == "Darwin" ]]; then
  DYLIB="$LIBDIR/libaether_uf_dpi.dylib"
  export DYLD_LIBRARY_PATH="$LIBDIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  LDFLAGS=(-LDFLAGS "-L$LIBDIR -laether_uf_dpi")
else
  DYLIB="$LIBDIR/libaether_uf_dpi.so"
  export LD_LIBRARY_PATH="$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  LDFLAGS=(-LDFLAGS "-L$LIBDIR -laether_uf_dpi -Wl,-rpath,$LIBDIR")
fi
test -f "$DYLIB"

cd "$ROOT/rtl"
rm -rf obj_dir_dpi
verilator --binary -j 0 -Wall -Wno-fatal --timing \
  --top-module tb_aether_uf_dpi \
  -Mdir obj_dir_dpi \
  -o tb_dpi_verilator \
  "${LDFLAGS[@]}" \
  aether_uf_grow_merge.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_dpi.sv

./obj_dir_dpi/tb_dpi_verilator

# Non-DPI regression still green
cargo run --quiet --bin gen_rtl_vectors
iverilog -g2012 -o tb_decode_sim aether_uf_grow_merge.sv aether_uf_tb_pack_peel_in.sv aether_uf_peel.sv tb_aether_uf_decode.sv
./tb_decode_sim
