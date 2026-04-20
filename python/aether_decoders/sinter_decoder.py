"""Sinter adapter: compiled Stim DEM → persistent release `decode_shots` process."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import sinter
import stim

from aether_decoders.dem import DEFAULT_LAMBDA, dem_to_payload

ROOT = Path(__file__).resolve().parents[2]
RELEASE_BIN = ROOT / "target" / "release" / "decode_shots"


def ensure_release_binary() -> Path:
    if RELEASE_BIN.is_file():
        return RELEASE_BIN
    built = subprocess.run(
        ["cargo", "build", "--release", "--quiet", "--bin", "decode_shots"],
        cwd=ROOT,
        check=False,
    )
    if built.returncode != 0 or not RELEASE_BIN.is_file():
        raise RuntimeError("failed to build release decode_shots")
    return RELEASE_BIN


class CompiledAetherUfDecoder(sinter.CompiledDecoder):
    """One long-lived `decode_shots` process per DEM (graph compiled once)."""

    def __init__(self, payload: dict, binary: Path, dem_path: str | None = None) -> None:
        self.payload = payload
        self.binary = str(binary)
        if dem_path is None:
            handle = tempfile.NamedTemporaryFile(
                mode="w",
                suffix="_aether_dem.json",
                delete=False,
            )
            json.dump(payload, handle)
            handle.close()
            dem_path = handle.name
        self.dem_path = dem_path
        self._proc: subprocess.Popen[str] | None = None

    def __getstate__(self) -> dict:
        return {
            "payload": self.payload,
            "binary": self.binary,
            "dem_path": self.dem_path,
        }

    def __setstate__(self, state: dict) -> None:
        self.payload = state["payload"]
        self.binary = state["binary"]
        self.dem_path = state["dem_path"]
        self._proc = None

    def _ensure_proc(self) -> subprocess.Popen[str]:
        if self._proc is not None and self._proc.poll() is None:
            return self._proc
        self._proc = subprocess.Popen(
            [self.binary, self.dem_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        if self._proc.stdin is None or self._proc.stdout is None:
            raise RuntimeError("decode_shots pipes failed")
        return self._proc

    def close(self) -> None:
        if self._proc is None:
            return
        try:
            if self._proc.stdin is not None:
                self._proc.stdin.close()
            self._proc.terminate()
            self._proc.wait(timeout=5)
        except Exception:
            self._proc.kill()
        self._proc = None

    def decode_shots_bit_packed(
        self,
        *,
        bit_packed_detection_event_data: np.ndarray,
    ) -> np.ndarray:
        packed = np.ascontiguousarray(bit_packed_detection_event_data, dtype=np.uint8)
        if packed.ndim != 2:
            raise ValueError("expected 2D bit-packed detection array")
        n_shots, _ = packed.shape
        n_dets = int(self.payload["num_detectors"])
        n_obs = int(self.payload["num_observables"])
        unpacked = np.unpackbits(packed, axis=1, bitorder="little")[:, :n_dets]

        proc = self._ensure_proc()
        assert proc.stdin is not None and proc.stdout is not None
        obs = np.zeros((n_shots, n_obs), dtype=np.uint8)
        for i, row in enumerate(unpacked):
            proc.stdin.write("".join("1" if bit else "0" for bit in row))
            proc.stdin.write("\n")
            proc.stdin.flush()
            line = proc.stdout.readline()
            if not line:
                err = ""
                if proc.stderr is not None:
                    err = proc.stderr.read()
                raise RuntimeError(err or "decode_shots closed stdout")
            line = line.strip()
            if len(line) != n_obs:
                raise RuntimeError(f"obs width {len(line)} != {n_obs}")
            for j, ch in enumerate(line):
                obs[i, j] = 1 if ch == "1" else 0
        return np.packbits(obs, axis=1, bitorder="little")


class AetherUfDecoder(sinter.Decoder):
    """Picklable Sinter decoder; workers must see `python/` on PYTHONPATH."""

    def __init__(self, lambda_scale: float = DEFAULT_LAMBDA) -> None:
        self.lambda_scale = lambda_scale

    def compile_decoder_for_dem(
        self,
        *,
        dem: stim.DetectorErrorModel,
    ) -> sinter.CompiledDecoder:
        binary = ensure_release_binary()
        payload = dem_to_payload(dem, lambda_scale=self.lambda_scale)
        return CompiledAetherUfDecoder(payload, binary)
