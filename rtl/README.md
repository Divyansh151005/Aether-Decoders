# Aether UF RTL

Synthesizable SystemVerilog for Union-Find **grow + merge + peel**.

| File | Role |
| --- | --- |
| `aether_uf_grow_merge.sv` | Parameterized grow+merge; `IDX_W=16`; per-edge `solid_bits[]` |
| `aether_uf_peel.sv` | BFS forest + M10 peel; `MAX_DEG=64`; `corr_bits[]` |
| `tb_aether_uf_stim.sv` | Stim graphs up to MAX=600 (circuit d=3 r=3 / phenom d=5 r=5) |
| `tb_aether_uf_dpi.sv` | DPI Blueprint co-sim (Verilator + `aether_uf_dpi`) |
| `tb_aether_uf_stim_dpi.sv` | DPI Stim co-sim (circuit-scale; live Rust goldens) |
| `tb_aether_uf_decode.sv` | Blueprint regression (file goldens) |

## Tools

- **Icarus Verilog** — Blueprint file TB + smaller Stim TBs
- **Verilator 5.050** (Homebrew) — Stim TB + DPI Blueprint/Stim
- **`aether_uf_dpi`** (`dpi/` cdylib) — live Rust goldens over DPI-C

Research: [`Docs/Rtl_Scale_Research`](../Docs/Rtl_Scale_Research), [`Docs/Rtl_Dpi_Research`](../Docs/Rtl_Dpi_Research).

## Simulation

```bash
# Stim-scale DPI (circuit d=3 r=3) — M28; ETA ~2–5 min
bash scripts/stim_dpi_cosim.sh

# DPI Blueprint (M26)
bash scripts/dpi_rtl_cosim.sh

# Circuit d=3 r=3 (V=392 E=556, max_deg=63) — M24
PYTHONPATH=python python3 scripts/stim_rtl_harness.py --kind circuit --distance 3 --rounds 3 --sim verilator

# Phenom d=5 r=5 (V=272 E=518) — M23
PYTHONPATH=python python3 scripts/stim_rtl_harness.py --sim iverilog
PYTHONPATH=python python3 scripts/stim_rtl_harness.py --sim verilator
```

Goldens: every shot `decode` ≡ `decode_cosim` ≡ `helios_pe` solids before RTL (file or DPI).
