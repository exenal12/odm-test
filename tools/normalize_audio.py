#!/usr/bin/env python3
"""Normalize SFX to per-group RMS targets (dB).

Reads the untouched originals from assets/audio_src/ and writes the result to
assets/audio/, so re-running never compounds gain. RMS is measured after
trimming leading silence; peaks are capped by a limiter. Run Godot's import
afterward.
"""
import re
import subprocess
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"
SRC = ASSETS / "audio_src"
DST = ASSETS / "audio"

# (glob relative to assets/audio, target RMS in dB)
GROUPS = [
    # Grass steps are all transient; boosting them needs heavy limiting, so player_audio.gd
    # applies their gain at runtime instead (FOOTSTEP_GAIN_DB).
    ("sfx/footstep_[!gt]*", -23.0),  # player/soldier footsteps
    ("sfx/footstep_titan_*", -18.0),
    ("sfx/impact[A-Z]*", -19.0),  # landings and hook impacts
    ("sfx/gas_refill_*", -22.0),
    ("odm/gas_burst_*", -20.0),
    ("odm/hook_launch_*", -20.0),
    ("odm/gas_hiss_loop.wav", -20.0),
]


def measure_rms(path: Path) -> float:
    out = subprocess.run(
        ["ffmpeg", "-nostdin", "-i", str(path), "-af",
         "silenceremove=start_periods=1:start_threshold=-50dB,astats=metadata=0",
         "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    match = re.search(r"Overall\s+RMS level dB:\s*(-?[\d.]+)", out) or re.search(
        r"RMS level dB:\s*(-?[\d.]+)", out)
    return float(match.group(1))


def apply_gain(path: Path, out: Path, gain_db: float) -> None:
    codec = ["-c:a", "libvorbis", "-q:a", "6"] if path.suffix == ".ogg" else ["-c:a", "pcm_s16le"]
    subprocess.run(
        ["ffmpeg", "-nostdin", "-y", "-loglevel", "error", "-i", str(path),
         "-af", f"volume={gain_db:.2f}dB,alimiter=limit=0.85:attack=1:release=30:level=0",
         *codec, str(out)],
        check=True,
    )


def main() -> None:
    seen = set()
    for pattern, target in GROUPS:
        for path in sorted(SRC.glob(pattern)):
            if path.suffix not in (".wav", ".ogg") or path in seen:
                continue
            seen.add(path)
            rms = measure_rms(path)
            gain = target - rms
            out = DST / path.relative_to(SRC)
            apply_gain(path, out, gain)
            print(f"{path.relative_to(SRC)}: {rms:.1f} -> ~{target:.1f} dB ({gain:+.1f} dB)")


if __name__ == "__main__":
    main()
