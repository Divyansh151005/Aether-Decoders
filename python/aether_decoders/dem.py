"""Flatten a Stim detector-error model into graphlike UF errors."""

from __future__ import annotations

from typing import Any

import stim

DEFAULT_LAMBDA = 1000.0


def dem_to_payload(
    dem: stim.DetectorErrorModel,
    *,
    lambda_scale: float = DEFAULT_LAMBDA,
) -> dict[str, Any]:
    errors: list[dict[str, Any]] = []
    for inst in dem.flattened():
        if inst.type != "error":
            continue
        p = float(inst.args_copy()[0])
        dets: list[int] = []
        obs: list[int] = []

        def flush() -> None:
            if not dets:
                return
            if len(dets) > 2:
                raise ValueError(f"graphlike piece has degree {len(dets)}")
            errors.append(
                {
                    "detectors": list(dets),
                    "probability": p,
                    "observables": list(obs),
                }
            )

        for t in inst.targets_copy():
            if t.is_separator():
                flush()
                dets.clear()
                obs.clear()
            elif t.is_relative_detector_id():
                dets.append(int(t.val))
            elif t.is_logical_observable_id():
                obs.append(int(t.val))
        flush()
    return {
        "num_detectors": dem.num_detectors,
        "num_observables": dem.num_observables,
        "lambda": lambda_scale,
        "errors": errors,
    }
