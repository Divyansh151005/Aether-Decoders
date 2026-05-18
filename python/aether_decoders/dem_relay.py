"""Flatten a Stim DEM into hypergraph columns for Relay-BP (any degree).

Unlike `dem_to_payload`, this does **not** split on `^` separators: each Stim
`error(p)` instruction is one Bernoulli column whose support is the F₂ sum of
all detector targets in that instruction (standard BP-on-DEM convention).
"""

from __future__ import annotations

from typing import Any

import stim


def dem_to_relay_payload(
    dem: stim.DetectorErrorModel,
    *,
    relay: dict[str, Any] | None = None,
) -> dict[str, Any]:
    errors: list[dict[str, Any]] = []
    for inst in dem.flattened():
        if inst.type != "error":
            continue
        p = float(inst.args_copy()[0])
        det_parity: dict[int, int] = {}
        obs_parity: dict[int, int] = {}
        for t in inst.targets_copy():
            if t.is_separator():
                continue
            if t.is_relative_detector_id():
                d = int(t.val)
                det_parity[d] = det_parity.get(d, 0) ^ 1
            elif t.is_logical_observable_id():
                o = int(t.val)
                obs_parity[o] = obs_parity.get(o, 0) ^ 1
        detectors = sorted(d for d, bit in det_parity.items() if bit)
        observables = sorted(o for o, bit in obs_parity.items() if bit)
        errors.append(
            {
                "detectors": detectors,
                "probability": p,
                "observables": observables,
            }
        )
    payload: dict[str, Any] = {
        "num_detectors": dem.num_detectors,
        "num_observables": dem.num_observables,
        "errors": errors,
    }
    if relay is not None:
        payload["relay"] = relay
    return payload
