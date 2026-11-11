#!/usr/bin/env python3
"""M76: pool matched-shot bake-off rows across independent sampler seeds.

Rows are pooled only when circuit, p, shots-per-seed and decoder agree and seeds differ.
Wilson 95% CI on pooled counts (same `wilson_interval` as relay_bb_bakeoff.py).

Usage: pool_relay_seeds.py out.csv in1.csv in2.csv [...]
"""
from __future__ import annotations

import csv
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from relay_bb_bakeoff import wilson_interval


def main() -> None:
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    out = Path(sys.argv[1])
    groups: dict[tuple, list[dict]] = defaultdict(list)
    for path in sys.argv[2:]:
        with open(path, newline="") as f:
            for row in csv.DictReader(f):
                row["source"] = Path(path).name
                groups[(row["circuit"], row["p"], row["decoder"])].append(row)

    with out.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["circuit", "p", "decoder", "seeds", "shots", "errors",
                    "ler", "ler_lo", "ler_hi", "sources"])
        for (circuit, p, decoder), rows in sorted(groups.items()):
            seeds = [r["seed"] for r in rows]
            if len(set(seeds)) != len(seeds):
                raise SystemExit(f"duplicate seed for {circuit} p={p} {decoder}: {seeds}")
            shots = sum(int(r["shots"]) for r in rows)
            errors = sum(int(r["errors"]) for r in rows)
            lo, hi = wilson_interval(errors, shots)
            w.writerow([circuit, p, decoder, ";".join(seeds), shots, errors,
                        errors / shots, lo, hi, ";".join(r["source"] for r in rows)])
            print(f"{decoder} p={p} seeds={seeds}: {errors}/{shots} "
                  f"LER={errors / shots:.4f} Wilson [{lo:.4f}, {hi:.4f}]")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
