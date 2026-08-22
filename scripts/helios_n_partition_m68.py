#!/usr/bin/env python3
"""M68: Helios-n partition stats for Stim phenom d=3 r=3 (Aether DEM compile).

Writes results/helios_n_partition_m68{,_parts,_crosscuts}.csv
Spec: Docs/Helios_n_Partition_M68. N_phys<=16 from Docs/Grow_Scale_M66.
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import defaultdict
from pathlib import Path

import stim

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from aether_decoders.dem import dem_to_payload


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--distance", type=int, default=3)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--p", type=float, default=0.003)
    ap.add_argument("--n-phys", type=int, default=16)
    ap.add_argument("--out-dir", type=Path, default=ROOT / "results")
    args = ap.parse_args()
    N_PHYS = args.n_phys

    circ = stim.Circuit.generated(
        "surface_code:rotated_memory_z",
        distance=args.distance,
        rounds=args.rounds,
        before_round_data_depolarization=args.p,
        before_measure_flip_probability=args.p,
    )
    dem = circ.detector_error_model(decompose_errors=True)
    payload = dem_to_payload(dem)
    D = payload["num_detectors"]
    errors = payload["errors"]

    next_b = D
    edges: list[tuple[int, int]] = []
    det_to_bnds: dict[int, list[int]] = defaultdict(list)
    for err in errors:
        dets = err["detectors"]
        if len(dets) == 1:
            b = next_b
            next_b += 1
            edges.append((dets[0], b))
            det_to_bnds[dets[0]].append(b)
        elif len(dets) == 2:
            edges.append((dets[0], dets[1]))
        else:
            raise SystemExit(f"unexpected detector degree {len(dets)}")
    V, E = next_b, len(edges)

    coords: dict[int, list[float]] = {}
    for i in range(D):
        c = dem.get_detector_coordinates(i)
        if isinstance(c, dict):
            c = c[i]
        coords[i] = list(c)

    def t_of(i: int) -> int:
        return int(coords[i][-1])

    by_t: dict[int, list[int]] = defaultdict(list)
    for i in range(D):
        by_t[t_of(i)].append(i)
    for t in by_t:
        by_t[t].sort()

    def analyze(parts: list[set[int]]):
        node_to_part: dict[int, int] = {}
        for pi, s in enumerate(parts):
            for n in s:
                node_to_part[n] = pi
        miss = set(range(V)) - set().union(*parts)
        cross_raw = [
            (u, v, node_to_part[u], node_to_part[v])
            for u, v in edges
            if u in node_to_part
            and v in node_to_part
            and node_to_part[u] != node_to_part[v]
        ]
        uniq = []
        seen: set[frozenset[int]] = set()
        for u, v, pu, pv in cross_raw:
            key = frozenset((u, v))
            if key in seen:
                continue
            seen.add(key)
            uniq.append((u, v, pu, pv))
        sizes = [len(s) for s in parts]
        cn = sorted({x for u, v, _, _ in uniq for x in (u, v)})
        return sizes, uniq, cn, miss

    def weight(ds: list[int]) -> tuple[int, set[int]]:
        n: set[int] = set(ds)
        for x in ds:
            n.update(det_to_bnds[x])
        return len(n), n

    parts: list[set[int]] = []
    part_meta: list[tuple[int, list[int]]] = []
    for t in sorted(by_t):
        cur: list[int] = []
        for det in by_t[t]:
            trial = cur + [det]
            w, _ = weight(trial)
            if cur and w > N_PHYS:
                _, nodes = weight(cur)
                parts.append(nodes)
                part_meta.append((t, list(cur)))
                cur = [det]
            else:
                cur = trial
        if cur:
            _, nodes = weight(cur)
            parts.append(nodes)
            part_meta.append((t, list(cur)))

    by_t_parts: list[set[int]] = []
    for t in sorted(by_t):
        n = set(by_t[t])
        for det in by_t[t]:
            n.update(det_to_bnds[det])
        by_t_parts.append(n)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    summary = args.out_dir / "helios_n_partition_m68.csv"
    with summary.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "scheme",
                "noise",
                "d",
                "rounds",
                "V",
                "E",
                "n",
                "N_phys_cap",
                "part_sizes",
                "max_part",
                "cross_edges",
                "cross_cut_nodes",
                "uncovered",
                "notes",
            ]
        )
        s, c, cn, m = analyze(by_t_parts)
        w.writerow(
            [
                "by_time_only",
                "phenom",
                args.distance,
                args.rounds,
                V,
                E,
                len(by_t_parts),
                N_PHYS,
                ";".join(map(str, s)),
                max(s),
                len(c),
                len(cn),
                len(m),
                "FAILS N_phys: mid layers can exceed cap",
            ]
        )
        s, c, cn, m = analyze(parts)
        w.writerow(
            [
                "intra_time_det_pack",
                "phenom",
                args.distance,
                args.rounds,
                V,
                E,
                len(parts),
                N_PHYS,
                ";".join(map(str, s)),
                max(s),
                len(c),
                len(cn),
                len(m),
                "CHOSEN: pack dets+bnds within time; max<=N_phys",
            ]
        )
        n_eq = math.ceil(V / N_PHYS)
        parts_eq = [
            set(range(i * N_PHYS, min((i + 1) * N_PHYS, V))) for i in range(n_eq)
        ]
        s2, c2, cn2, m2 = analyze(parts_eq)
        w.writerow(
            [
                "node_id_shards",
                "phenom",
                args.distance,
                args.rounds,
                V,
                E,
                n_eq,
                N_PHYS,
                ";".join(map(str, s2)),
                max(s2),
                len(c2),
                len(cn2),
                len(m2),
                "rejected: ignores DEM topology",
            ]
        )

    with (args.out_dir / "helios_n_partition_m68_crosscuts.csv").open(
        "w", newline=""
    ) as f:
        w = csv.writer(f)
        w.writerow(["u", "v", "part_u", "part_v"])
        for row in c:
            w.writerow(row)

    with (args.out_dir / "helios_n_partition_m68_parts.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["part", "time_t", "detectors", "nodes", "size"])
        for i, (t, dets) in enumerate(part_meta):
            w.writerow(
                [
                    i,
                    t,
                    ";".join(map(str, dets)),
                    ";".join(map(str, sorted(parts[i]))),
                    len(parts[i]),
                ]
            )

    print(
        f"phenom d={args.distance} r={args.rounds} V={V} E={E} "
        f"chosen n={len(parts)} max_part={max(len(x) for x in parts)} "
        f"cross_edges={len(c)} -> {summary}"
    )


if __name__ == "__main__":
    main()
