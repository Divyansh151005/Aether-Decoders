#!/usr/bin/env python3
"""M70: Helios-n physical PE coloring for Stim phenom d=3 r=3.

Enforces Helios cross-cut colocation (same phys PE) and per-part injectivity.
Documents that M68 intra_time_det_pack is colocation-infeasible (transitive).

Writes results/helios_n_coloring_m70*.csv
Spec: Docs/Helios_n_Coloring_M70; Helios arXiv:2406.08491; M69 §3.2.
"""
from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict, deque
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
    next_b = D
    edges: list[tuple[int, int]] = []
    det_to_bnds: dict[int, list[int]] = defaultdict(list)
    for err in payload["errors"]:
        dets = err["detectors"]
        if len(dets) == 1:
            b = next_b
            next_b += 1
            edges.append((dets[0], b))
            det_to_bnds[dets[0]].append(b)
        elif len(dets) == 2:
            edges.append((dets[0], dets[1]))
        else:
            raise SystemExit(f"unexpected degree {len(dets)}")
    V = next_b

    adj: dict[int, list[int]] = defaultdict(list)
    for u, v in edges:
        if u < D and v < D:
            adj[u].append(v)
            adj[v].append(u)
    seen: set[int] = set()
    det_comps: list[list[int]] = []
    for i in range(D):
        if i in seen:
            continue
        q = deque([i])
        seen.add(i)
        comp: list[int] = []
        while q:
            x = q.popleft()
            comp.append(x)
            for y in adj[x]:
                if y not in seen:
                    seen.add(y)
                    q.append(y)
        det_comps.append(sorted(comp))
    det_comps.sort(key=len, reverse=True)

    def parts_paired() -> list[list[int]]:
        L = max(len(c) for c in det_comps)
        padded = [c + [None] * (L - len(c)) for c in det_comps]
        parts: list[list[int]] = []
        for i in range(L):
            dets = [padded[ci][i] for ci in range(len(padded)) if padded[ci][i] is not None]
            nodes: set[int] = set(dets)
            for det in dets:
                nodes.update(det_to_bnds[det])
            parts.append(sorted(nodes))
        return parts

    def parts_one_det() -> list[list[int]]:
        return [sorted([det] + det_to_bnds[det]) for det in range(D)]

    def parts_m68() -> list[list[int]]:
        coords = {}
        for i in range(D):
            c = dem.get_detector_coordinates(i)
            if isinstance(c, dict):
                c = c[i]
            coords[i] = list(c)
        by_t: dict[int, list[int]] = defaultdict(list)
        for i in range(D):
            by_t[int(coords[i][-1])].append(i)
        for t in by_t:
            by_t[t].sort()

        def weight(ds: list[int]) -> tuple[int, set[int]]:
            n: set[int] = set(ds)
            for x in ds:
                n.update(det_to_bnds[x])
            return len(n), n

        parts: list[list[int]] = []
        for t in sorted(by_t):
            cur: list[int] = []
            for det in by_t[t]:
                trial = cur + [det]
                w, _ = weight(trial)
                if cur and w > N_PHYS:
                    _, nodes = weight(cur)
                    parts.append(sorted(nodes))
                    cur = [det]
                else:
                    cur = trial
            if cur:
                _, nodes = weight(cur)
                parts.append(sorted(nodes))
        return parts

    def try_color(parts: list[list[int]], label: str) -> dict:
        node_part: dict[int, int] = {}
        for pi, S in enumerate(parts):
            for n in S:
                if n in node_part:
                    return {"ok": False, "label": label, "err": f"dup node {n}"}
                node_part[n] = pi
        if set(range(V)) - set(node_part):
            return {"ok": False, "label": label, "err": "uncovered nodes"}

        cross: list[tuple[int, int]] = []
        seen_e: set[frozenset[int]] = set()
        for u, v in edges:
            if node_part[u] == node_part[v]:
                continue
            key = frozenset((u, v))
            if key in seen_e:
                continue
            seen_e.add(key)
            cross.append((u, v))

        parent = list(range(V))

        def find(x: int) -> int:
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        def union(a: int, b: int) -> None:
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[rb] = ra

        for u, v in cross:
            union(u, v)

        for pi, S in enumerate(parts):
            roots = [find(n) for n in S]
            if len(roots) != len(set(roots)):
                return {
                    "ok": False,
                    "label": label,
                    "err": f"part{pi} colocation collision under transitive Helios map",
                }

        comps = sorted({find(n) for n in range(V)})
        conflict: dict[int, set[int]] = defaultdict(set)
        for S in parts:
            roots = sorted({find(n) for n in S})
            for i in range(len(roots)):
                for j in range(i + 1, len(roots)):
                    a, b = roots[i], roots[j]
                    conflict[a].add(b)
                    conflict[b].add(a)

        order = sorted(
            comps, key=lambda c: (-sum(1 for n in range(V) if find(n) == c), c)
        )
        color: dict[int, int] = {}
        for c in order:
            used = {color[o] for o in conflict[c] if o in color}
            chosen = next((k for k in range(N_PHYS) if k not in used), None)
            if chosen is None:
                return {"ok": False, "label": label, "err": f"need more than {N_PHYS} colors"}
            color[c] = chosen

        phys = [color[find(n)] for n in range(V)]
        load: dict[int, list[int]] = defaultdict(list)
        for n, p_id in enumerate(phys):
            load[p_id].append(n)
        sizes = [len(S) for S in parts]
        return {
            "ok": True,
            "label": label,
            "parts": parts,
            "phys": phys,
            "cross": cross,
            "node_part": node_part,
            "n_parts": len(parts),
            "max_part": max(sizes),
            "n_colors": max(phys) + 1,
            "cross_n": len(cross),
            "max_virt": max(len(v) for v in load.values()),
            "load": load,
        }

    r_m68 = try_color(parts_m68(), "m68_intra_time_det_pack")
    r_pair = try_color(parts_paired(), "det_comp_paired")
    r_one = try_color(parts_one_det(), "one_det")
    chosen = r_pair if r_pair["ok"] else r_one
    if not chosen["ok"]:
        raise SystemExit("no feasible coloring")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    with (args.out_dir / "helios_n_coloring_m70_summary.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "scheme",
                "ok",
                "n_parts",
                "max_part",
                "colors_used",
                "N_phys_cap",
                "cross_edges",
                "max_virtuals_per_phys",
                "notes",
            ]
        )
        rows = [
            (r_m68, "M68 pack; Helios colocation INFEASIBLE if transitive"),
            (r_pair, "CHOSEN: <=1 detector per DEM component per part"),
            (r_one, "fallback one detector per part"),
        ]
        for r, note in rows:
            if r["ok"]:
                w.writerow(
                    [
                        r["label"],
                        1,
                        r["n_parts"],
                        r["max_part"],
                        r["n_colors"],
                        N_PHYS,
                        r["cross_n"],
                        r["max_virt"],
                        note,
                    ]
                )
            else:
                w.writerow(
                    [r["label"], 0, "", "", "", N_PHYS, "", "", f"{note}: {r['err']}"]
                )

    phys = chosen["phys"]
    parts = chosen["parts"]
    node_part = chosen["node_part"]
    cross = chosen["cross"]
    cross_nodes = {x for uv in cross for x in uv}

    with (args.out_dir / "helios_n_coloring_m70.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "virtual_node",
                "phys_pe",
                "part",
                "is_boundary",
                "is_cross_cut_endpoint",
                "scheme",
            ]
        )
        for n in range(V):
            w.writerow(
                [
                    n,
                    phys[n],
                    node_part[n],
                    1 if n >= D else 0,
                    1 if n in cross_nodes else 0,
                    chosen["label"],
                ]
            )

    with (args.out_dir / "helios_n_coloring_m70_phys.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["phys_pe", "num_virtuals", "virtual_nodes", "parts_touched"])
        for p_id in range(chosen["n_colors"]):
            vs = chosen["load"][p_id]
            w.writerow(
                [
                    p_id,
                    len(vs),
                    ";".join(map(str, vs)),
                    ";".join(map(str, sorted({node_part[n] for n in vs}))),
                ]
            )

    with (args.out_dir / "helios_n_coloring_m70_parts.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["part", "nodes", "size", "phys_slots"])
        for pi, S in enumerate(parts):
            slots = sorted(phys[n] for n in S)
            w.writerow(
                [pi, ";".join(map(str, S)), len(S), ";".join(map(str, slots))]
            )

    with (args.out_dir / "helios_n_coloring_m70_crosscuts.csv").open(
        "w", newline=""
    ) as f:
        w = csv.writer(f)
        w.writerow(["u", "v", "part_u", "part_v", "phys"])
        for u, v in cross:
            w.writerow([u, v, node_part[u], node_part[v], phys[u]])

    print(
        f"CHOSEN {chosen['label']} n_parts={chosen['n_parts']} "
        f"colors={chosen['n_colors']} max_part={chosen['max_part']} "
        f"(m68_feasible={r_m68['ok']}) -> {args.out_dir}/helios_n_coloring_m70.csv"
    )


if __name__ == "__main__":
    main()
