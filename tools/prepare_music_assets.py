"""Turn the downloaded CC0 music tracks into seamless, quiet game loops.

Sources live outside the repo in ``E:\\ai-audio\\free-sfx\\music\\`` (fetched by
``tools/fetch_music_sources.py``). Every track is CC0 — attribution is optional and
the repo's zero-attribution posture is preserved. Origins are recorded in
``docs/audio_asset_rules.md``.

Two things make this more than a format conversion:

1. **Fade-outs are trimmed before looping.** Both source tracks end with a composed
   fade (or, for Contemplation, a hard cut). Cross-fading a faded tail back over a
   full-volume head produces an audible "swell" every loop. We locate where the music
   body actually stops and cut there first.
2. **Stereo is preserved but gain-linked.** Each channel is filtered independently;
   normalisation uses a single shared factor so the stereo image doesn't shift.

Output: res://assets/audio/music/*.ogg, merged into audio_manifest.json.

Run:
    python tools\\fetch_music_sources.py
    python tools\\prepare_music_assets.py
Then:
    godot --headless --import
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfiltfilt


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
SRC = Path(r"E:\ai-audio\free-sfx\music")
SR = 44_100

# Music sits *under* the ambience bed, which peaks at 0.12-0.18. Anything louder
# turns a desk-corner companion into a media player. Runtime music_volume cuts
# further still.
MUSIC_PEAK = 0.24

TRACKS = {
    "bgm_day": {
        "src": "oga_cc0_first_light_particles.wav",
        "path": "music/bgm_day.ogg",
        "xfade": 4.0,
        "description": (
            "Main loop: shimmering piano, low pulses, gentle pads, no percussion. "
            "Source: OpenGameArt 'First Light Particles' by Yoiyami, CC0."
        ),
    },
    "bgm_night": {
        "src": "oga_cc0_contemplation.mp3",
        "path": "music/bgm_night.ogg",
        "xfade": 5.0,  # the source ends on a hard cut; it needs the longest blend
        "description": (
            "Night variation: sparse ambience, author states 'no real melody or focus'. "
            "Source: OpenGameArt 'Contemplation' by Joth, CC0."
        ),
    },
}


def load_stereo(name: str) -> np.ndarray:
    """Read a source track as (n, 2) float32 at 44.1 kHz, preserving the image."""
    data, sr = sf.read(SRC / name, always_2d=True, dtype="float32")
    if data.shape[1] == 1:
        data = np.repeat(data, 2, axis=1)
    elif data.shape[1] > 2:
        data = data[:, :2]
    if sr != SR:
        g = math.gcd(int(sr), SR)
        data = np.stack(
            [resample_poly(data[:, c], SR // g, int(sr) // g) for c in range(2)], axis=1
        )
    return np.ascontiguousarray(data, dtype=np.float32)


def frame_rms(mono: np.ndarray, win: int) -> np.ndarray:
    n = len(mono) // win
    if n == 0:
        return np.array([0.0], dtype=np.float32)
    return np.sqrt(np.mean(mono[: n * win].reshape(n, win) ** 2, axis=1) + 1e-12)


def trim_to_body(x: np.ndarray, floor_ratio: float = 0.5) -> np.ndarray:
    """Cut leading silence and the composed fade-out.

    The fade-out is found by walking back from the end until a frame is at least
    ``floor_ratio`` of the track's typical loudness — i.e. where the music was still
    playing at full strength. Cutting there means the loop's tail and head are at
    comparable energy, which is what makes a crossfade inaudible.
    """
    win = int(0.05 * SR)
    mono = x.mean(axis=1)
    rms = frame_rms(mono, win)
    voiced = rms[rms > 10 ** (-50 / 20)]
    if not len(voiced):
        return x
    body = float(np.median(voiced))
    strong = np.where(rms >= floor_ratio * body)[0]
    if not len(strong):
        return x
    start, end = int(strong[0]) * win, min(len(x), (int(strong[-1]) + 1) * win)
    return x[start:end]


def soften(x: np.ndarray, hp: float = 30.0, lp: float = 15_000.0) -> np.ndarray:
    """Kill sub-bass rumble and the harshest highs. Gentler than the SFX/ambience
    treatment — music can carry more top end without fighting the palette."""
    hp_sos = butter(2, hp / (SR / 2), btype="high", output="sos")
    lp_sos = butter(2, lp / (SR / 2), btype="low", output="sos")
    return np.stack(
        [sosfiltfilt(lp_sos, sosfiltfilt(hp_sos, x[:, c])) for c in range(2)], axis=1
    ).astype(np.float32)


def seamless_loop(x: np.ndarray, xfade_s: float) -> np.ndarray:
    """Equal-power boundary crossfade over stereo. Blend the tail back over the head
    so the last sample flows into the first. Mirrors tools/prepare_ambience_assets.py."""
    xf = int(xfade_s * SR)
    if len(x) <= 2 * xf:
        raise ValueError(f"track too short ({len(x) / SR:.1f}s) for a {xfade_s}s crossfade")
    n = len(x) - xf
    out = x[:n].astype(np.float64).copy()
    t = np.linspace(0.0, 1.0, xf, dtype=np.float64)[:, None]
    fade_in = np.sin(0.5 * np.pi * t)
    fade_out = np.cos(0.5 * np.pi * t)
    out[:xf] = x[n : n + xf] * fade_out + x[:xf] * fade_in
    return out.astype(np.float32)


def normalize_peak(x: np.ndarray, peak: float) -> np.ndarray:
    cur = float(np.max(np.abs(x)))
    if cur <= 1e-9:
        return x
    return (x * (peak / cur)).astype(np.float32)


def write_ogg(path: Path, audio: np.ndarray, chunk_seconds: float = 4.0) -> None:
    """Write Vorbis in chunks.

    libsndfile 1.2.2 on Windows overflows the stack (0xC00000FD) when a single
    ``sf.write`` hands the Vorbis encoder more than ~10 s of audio. Streaming the
    same samples through an open SoundFile in short blocks encodes identically and
    stays within the stack. Verified: 132 s writes clean and reads back sample-exact.
    """
    step = int(chunk_seconds * SR)
    with sf.SoundFile(path, "w", samplerate=SR, channels=2,
                      format="OGG", subtype="VORBIS") as handle:
        for i in range(0, len(audio), step):
            handle.write(audio[i : i + step])


def seam_report(x: np.ndarray) -> tuple[float, float]:
    """Max sample-to-sample jump across the wrap point vs. the interior maximum.
    A seam at or below the interior maximum is inaudible by construction."""
    mono = x.mean(axis=1)
    across = np.abs(np.diff(np.concatenate([mono[-400:], mono[:400]])))
    interior = np.abs(np.diff(mono))
    return float(across.max()), float(interior.max())


def main() -> None:
    manifest_path = OUT / "audio_manifest.json"
    manifest = {}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    failures = []
    for track_id, spec in TRACKS.items():
        raw = load_stereo(spec["src"])
        body = trim_to_body(raw)
        looped = seamless_loop(soften(body), spec["xfade"])
        audio = normalize_peak(looped, MUSIC_PEAK)

        seam, interior = seam_report(audio)
        rms = float(np.sqrt(np.mean(audio ** 2)))
        if seam > interior:
            failures.append(f"{track_id}: loop seam {seam:.5f} exceeds interior {interior:.5f}")

        out = OUT / spec["path"]
        out.parent.mkdir(parents=True, exist_ok=True)
        write_ogg(out, audio)
        manifest[track_id] = {
            "path": "res://assets/audio/" + spec["path"],
            "duration_seconds": round(len(audio) / SR, 3),
            "loop": True,
            "music": True,
            "description": spec["description"],
        }
        print(
            f"{track_id:10s} {len(raw) / SR:6.1f}s raw -> {len(audio) / SR:6.1f}s loop  "
            f"peak={MUSIC_PEAK:.2f} rms={rms:.4f}  seam={seam:.5f} (interior {interior:.5f})  "
            f"{out.stat().st_size / 1e6:.2f} MB"
        )

    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"\nmanifest -> {manifest_path} ({len(manifest)} entries)")
    if failures:
        raise SystemExit("loop seam check failed:\n  " + "\n  ".join(failures))
    print("loop seams OK")


if __name__ == "__main__":
    main()
