"""Bake the catch-tier ladder and the character foley one-shots.

Depends on two other generators having run first:
  1. ``tools/prepare_free_sfx_assets.py`` sources (the CC0 packs under FREE_SFX)
  2. ``tools/synth_feedback_sfx.py``       (this script layers its sfx_epic_tail)

Why bake instead of layering at runtime: ``catch_epic`` is a splash plus a synthesized
tail with a precise 0.12 s offset. Firing two pool voices and hoping they land in the
same frame gives a different sound every time, and burns two of the eight SFX voices
on the game's single most important moment.

The tier ladder exists because ``main.gd`` previously collapsed everything from
"good quality common fish" to "rainbow legendary" into one ``catch_rare`` sample —
a ×12-value fish sounded exactly like a ×2 one.

    catch_common  gentle lift            (existing, untouched)
    catch_good    lift + faint confirm   (new)
    catch_rare    lift + confirm         (existing, untouched)
    catch_epic    big splash + rise tail (new)

Output: res://assets/audio/fishing/ and res://assets/audio/feedback/, merged into
audio_manifest.json.

Run (after the two prerequisites):
    python tools\\prepare_catch_and_foley.py
Then:
    godot --headless --import
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfiltfilt

sys.path.insert(0, str(Path(__file__).resolve().parent))
import synth_feedback_sfx as synth  # noqa: E402  (path must be set first)


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
FREE_SFX = Path(r"E:\ai-audio\free-sfx\packs")
SR = 44_100

SOURCES = {
    "kenney": FREE_SFX / "opengameart_kenney_interface_sounds_cc0" / "Audio",
    "water": FREE_SFX / "opengameart_water_splash_slime_cc0",
    "more": FREE_SFX / "opengameart_202_more_sounds_cc0",
    "foley": FREE_SFX / "_new_foley",
    "synth": OUT / "feedback",  # produced by synth_feedback_sfx.py
}


def db_to_gain(db: float) -> float:
    return 10.0 ** (db / 20.0)


def read_mono(ref: str) -> np.ndarray:
    group, rest = ref.split("/", 1)
    data, sr = sf.read(SOURCES[group] / rest, always_2d=True)
    mono = data.mean(axis=1).astype(np.float32)
    if sr != SR:
        g = math.gcd(int(sr), SR)
        mono = resample_poly(mono, SR // g, int(sr) // g).astype(np.float32)
    return mono


def lowpass(x: np.ndarray, hz: float) -> np.ndarray:
    if hz >= SR / 2:
        return x
    sos = butter(2, hz / (SR / 2), btype="low", output="sos")
    return sosfiltfilt(sos, x.astype(np.float64)).astype(np.float32)


def loudest_window(x: np.ndarray, seconds: float) -> np.ndarray:
    """Pick the most energetic slice — used to find the real thrash inside a 48 s
    bathtub recording that is mostly quiet water."""
    n = int(seconds * SR)
    if len(x) <= n:
        return x
    win = int(0.05 * SR)
    frames = len(x) // win
    energy = np.sqrt(np.mean(x[: frames * win].reshape(frames, win) ** 2, axis=1))
    span = max(1, n // win)
    running = np.convolve(energy, np.ones(span) / span, mode="valid")
    start = int(np.argmax(running)) * win
    return x[start : start + n]


def apply_fades(x: np.ndarray, fade_in: float = 0.005, fade_out: float = 0.05) -> np.ndarray:
    out = x.copy()
    in_n = min(len(out), int(fade_in * SR))
    out_n = min(len(out), int(fade_out * SR))
    if in_n > 1:
        out[:in_n] *= np.linspace(0.0, 1.0, in_n, dtype=np.float32)
    if out_n > 1:
        out[-out_n:] *= np.linspace(1.0, 0.0, out_n, dtype=np.float32)
    return out


def normalize_peak(x: np.ndarray, peak: float) -> np.ndarray:
    cur = float(np.max(np.abs(x))) if len(x) else 0.0
    if cur <= 1e-6:
        return x
    return (x * (peak / cur)).astype(np.float32)


def seamless_loop(x: np.ndarray, xfade_s: float) -> np.ndarray:
    xf = int(xfade_s * SR)
    n = len(x) - xf
    out = x[:n].astype(np.float64).copy()
    t = np.linspace(0.0, 1.0, xf, dtype=np.float64)
    out[:xf] = x[n : n + xf] * np.cos(0.5 * np.pi * t) + x[:xf] * np.sin(0.5 * np.pi * t)
    return out.astype(np.float32)


# id -> spec. `layers` are (source_ref, offset_seconds, gain_db); `lp` lowpasses the
# whole mix. `trim` takes the loudest N seconds of the *first* layer before mixing.
ASSETS = {
    "catch_good": {
        "path": "fishing/catch_good.wav",
        "layers": [
            ("water/splash_09.ogg", 0.0, -3.0),
            ("kenney/confirmation_002.ogg", 0.10, -22.0),  # barely there: a nod, not a fanfare
        ],
        # Ladder invariant: catch_common 0.30 < catch_good < catch_rare 0.32 <= catch_epic.
        # A better fish must never sound *weaker* than a worse one.
        "peak": 0.31,
        "lp": 7000.0,
        "fade_out": 0.12,
        "description": (
            "Good-quality catch: water lift with a very faint confirmation. "
            "Sources: OGA 40 CC0 water/splash/slime splash_09 + Kenney Interface Sounds "
            "confirmation_002 (kenney.nl, CC0)."
        ),
    },
    "catch_epic": {
        "path": "fishing/catch_epic.wav",
        # Three layers, because catch_rare's perceived weight turned out to come from its
        # *sustained* confirmation tone (crest 2.3), not from its splash. A plucked-string
        # tail decays instantly (crest 4.2) and can't fill that role — pushed loud enough
        # to try, its peak starts fighting the splash for headroom. The thrash recording
        # supplies the sustain instead, and says "a big fish is fighting you" while doing it.
        # Timeline mirrors catch_rare's, one tier up:
        #   0.00s  splash      the strike            (rare: same splash)
        #   0.18s  thrash      the fish fights       (rare: confirmation tone)
        #   0.30s  rise+tail   the melody            (rare: nothing)
        # 0.18 s is where catch_rare drops its sustain, and by then the splash has decayed
        # from 0.976 to 0.079 — so a loud sustain layer there costs no headroom at all.
        "layers": [
            ("water/splash_01.ogg", 0.0, -4.0),
            # -2.6 dB is measured, not taste. rare's confirmation tone lands at RMS 0.0400
            # after rare's own anchor scale (0.06116 x 0.6545). Matching that *post-scale*
            # figure through epic's scale (0.5195) needs 0.1033 x g x 0.5195 = 0.0400.
            # Matching the pre-scale RMS instead undershoots — the two tiers have different
            # anchor scales because their splashes carry different gains.
            ("foley/water_thrash_bathtub_pd.ogg", 0.18, -2.6, 0.9),
            # Clear of the 300 ms onset window entirely: the melody is what makes epic feel
            # *long*, not what makes it feel *loud*. The thrash already carries the weight.
            ("synth/sfx_epic_tail.wav", 0.30, 2.0),
        ],
        "anchor": 0,          # the splash defines loudness; thrash and tail add on top
        "peak": 0.32,         # -> splash peak == catch_rare's splash peak, exactly
        "peak_limit": 0.36,   # clip guard for the summed layers
        "lp": 6500.0,         # the thrash recording centroids at 6425 Hz; pull it in
        "fade_out": 0.30,
        "description": (
            "Rainbow / legendary catch: big water lift, a thrashing fish, and a five-note "
            "rise with shimmer tail. Sources: OGA 40 CC0 water/splash/slime splash_01 + "
            "Wikimedia Commons 'Bathtub water splashes' (public domain) + synthesized tail "
            "(tools/synth_feedback_sfx.py)."
        ),
    },
    "sfx_cat_steal": {
        "path": "feedback/sfx_cat_steal.wav",
        "layers": [
            ("foley/cat_meow_siamese_cc0.wav", 0.0, -5.0, 0.95),
            ("water/splash_09.ogg", 0.62, -14.0),  # the paw going in after the fish
        ],
        "peak": 0.26,
        "lp": 6500.0,
        "fade_out": 0.15,
        "description": (
            "The cat steals a fish: one soft inquisitive meow, then a small paw splash. "
            "Sources: Wikimedia Commons 'Meow of a Siamese cat' by freemaster2 (CC0) + OGA "
            "40 CC0 water/splash/slime splash_09. The meow source clips on ~0.05% of samples; "
            "harmless after normalisation to peak 0.26."
        ),
    },
    "sfx_fish_struggle": {
        "path": "feedback/sfx_fish_struggle.wav",
        "layers": [("foley/water_thrash_bathtub_pd.ogg", 0.0, 0.0, 1.1)],
        "peak": 0.24,
        "lp": 5000.0,  # the raw recording centroids at 6425 Hz — well above the palette
        "fade_in": 0.04,
        "fade_out": 0.35,
        "description": (
            "A big fish thrashing on the line, layered under the bite of tier-3+ catches. "
            "Source: Wikimedia Commons 'Bathtub water splashes' (public domain), loudest "
            "1.1 s window, lowpassed to sit inside the watercolour palette."
        ),
    },
}


def build(spec: dict) -> np.ndarray:
    """Layers are (source_ref, offset_seconds, gain_db[, trim_seconds]).

    A 4th element takes only the loudest `trim_seconds` of that layer — needed because
    the field recordings are tens of seconds long and mostly quiet.
    """
    rendered, total = [], 0
    for layer in spec["layers"]:
        ref, offset_s, gain_db = layer[0], layer[1], layer[2]
        audio = read_mono(ref)
        if len(layer) > 3:
            audio = loudest_window(audio, layer[3])
        audio = audio * db_to_gain(gain_db)
        offset = int(offset_s * SR)
        rendered.append((audio, offset))
        total = max(total, offset + len(audio))

    mix = np.zeros(total, dtype=np.float32)
    for audio, offset in rendered:
        mix[offset : offset + len(audio)] += audio
    mix = lowpass(mix, spec.get("lp", SR / 2))
    mix = apply_fades(mix, spec.get("fade_in", 0.005), spec.get("fade_out", 0.05))

    anchor = spec.get("anchor")
    if anchor is None:
        return normalize_peak(mix, spec["peak"])

    # Anchor mode. Peak-normalising the *mix* is a trap for multi-layer sounds: every
    # layer that overlaps the anchor's transient raises the mix peak, and normalisation
    # then scales the anchor back down. Adding a "bigger" layer made catch_epic quieter.
    # Instead, scale so the anchor layer alone lands on `peak` (the same yardstick
    # catch_rare uses, where the splash happens to dominate), and let the extra layers
    # add on top. peak_limit is a clip guard, not a loudness target.
    #
    # Measure the anchor *after* the same lowpass the mix gets: filtering shaves ~7% off a
    # splash transient, and anchoring to the unfiltered peak silently undershoots `peak`.
    anchor_ref = lowpass(rendered[anchor][0], spec.get("lp", SR / 2))
    scale = spec["peak"] / float(np.max(np.abs(anchor_ref)))
    mix = mix * scale
    total_peak = float(np.max(np.abs(mix)))
    limit = spec.get("peak_limit", 0.36)
    if total_peak > limit:
        print(f"    (anchor mix peaked {total_peak:.3f}, limiting to {limit:.2f})")
        mix = mix * (limit / total_peak)
    return mix.astype(np.float32)


def rebuild_reel_tension() -> tuple[np.ndarray, str]:
    """Re-bake the tension loop with a real line-creak layer under the synthetic swell.

    The pure-synth version (synth_feedback_sfx.py) is tonally right but reads as a drone.
    An office-chair creak — the only CC0/PD recording with the right timbre; no real
    fishing-line-tension recording exists under a free licence — supplies the irregular
    micro-motion that makes it read as *strain*. Kept quiet and lowpassed hard.

    The dry swell is regenerated in-process rather than read back from
    ``feedback/sfx_reel_tension.wav``, which this script also *writes*. Reading its own
    output re-layered the creak and stretched the loop by 0.05 s on every rerun.
    """
    synth.RNG = synth.voice_rng("sfx_reel_tension")   # same seed the standalone run uses
    dry = synth.normalize_peak(synth.shape(synth.v_reel_tension(), loop=True), 0.16)

    creak = read_mono("foley/line_creak_tension_pd.ogg")
    creak = loudest_window(creak, len(dry) / SR + 0.35)
    creak = lowpass(normalize_peak(creak, 1.0), 2600.0) * db_to_gain(-13.0)
    creak = creak[: len(dry) + int(0.35 * SR)]

    mix = np.zeros(len(creak), dtype=np.float32)
    mix[: len(dry)] += dry
    mix += creak
    mix = seamless_loop(mix, 0.30)
    return normalize_peak(mix, 0.17), (
        "Bite->catch tension loop: synthesized bowed swell (public domain) under a "
        "lowpassed real line-creak. Creak source: Wikimedia Commons 'Assorted creaking "
        "noises of office chair' (public domain) — no free fishing-line recording exists."
    )


def spectral_centroid(x: np.ndarray) -> float:
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    return float(np.sum(freqs * spectrum) / max(float(np.sum(spectrum)), 1e-9))


CENTROID_BUDGET = 6100.0  # catch_common, the brightest shipping catch sound, is 6048 Hz

LADDER = ["catch_common", "catch_good", "catch_rare", "catch_epic"]


def onset_rms(x: np.ndarray, seconds: float = 0.3) -> float:
    """Loudness of the attack. Full-file RMS is the wrong measure here: catch_epic's
    long shimmer tail drags its mean RMS *below* catch_common's, even though its
    attack is stronger. What the player registers is the first ~300 ms."""
    return float(np.sqrt(np.mean(x[: int(seconds * SR)] ** 2)))


def effective_duration(x: np.ndarray, floor_db: float = -45.0) -> float:
    win = int(0.02 * SR)
    frames = len(x) // win
    if frames == 0:
        return 0.0
    rms = np.sqrt(np.mean(x[: frames * win].reshape(frames, win) ** 2, axis=1) + 1e-12)
    above = np.where(rms > 10 ** (floor_db / 20))[0]
    return (int(above[-1]) + 1) * win / SR if len(above) else 0.0


def verify_ladder() -> list[str]:
    """A rarer fish must never sound weaker or shorter than a commoner one. This is the
    whole point of splitting the tiers; assert it rather than trusting the gain numbers."""
    problems, previous = [], None
    print(f"\n{'tier':14s} {'peak':>6s} {'onset_rms':>10s} {'eff_dur':>8s}")
    for tier in LADDER:
        audio, _ = sf.read(OUT / "fishing" / f"{tier}.wav")
        audio = audio.astype(np.float32)
        row = (float(np.max(np.abs(audio))), onset_rms(audio), effective_duration(audio))
        print(f"{tier:14s} {row[0]:6.3f} {row[1]:10.4f} {row[2]:7.2f}s")
        if previous:
            if row[0] < previous[0] - 1e-3:
                problems.append(f"{tier}: peak {row[0]:.3f} < previous {previous[0]:.3f}")
            if row[1] < previous[1] * 0.9:
                problems.append(f"{tier}: onset_rms {row[1]:.4f} well below previous {previous[1]:.4f}")
            if row[2] < previous[2] - 0.02:
                problems.append(f"{tier}: eff_dur {row[2]:.2f}s < previous {previous[2]:.2f}s")
        previous = row
    return problems


def main() -> None:
    manifest_path = OUT / "audio_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}

    failures = []
    print(f"{'id':22s} {'len':>6s} {'peak':>6s} {'centroid':>9s}")

    outputs = {aid: (build(spec), spec["path"], False, spec["description"])
               for aid, spec in ASSETS.items()}
    reel, reel_desc = rebuild_reel_tension()
    outputs["sfx_reel_tension"] = (reel, "feedback/sfx_reel_tension.wav", True, reel_desc)

    for asset_id, (audio, rel, loop, desc) in outputs.items():
        centroid = spectral_centroid(audio)
        if centroid > CENTROID_BUDGET:
            failures.append(f"{asset_id}: centroid {centroid:.0f} > {CENTROID_BUDGET:.0f}")
        if float(np.max(np.abs(audio))) > 0.99:
            failures.append(f"{asset_id}: clipping")

        out = OUT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        sf.write(out, audio, SR, subtype="PCM_16")
        manifest[asset_id] = {
            "path": "res://assets/audio/" + rel,
            "duration_seconds": round(len(audio) / SR, 3),
            "loop": loop,
            "description": desc,
        }
        print(f"{asset_id:22s} {len(audio) / SR:5.2f}s "
              f"{float(np.max(np.abs(audio))):6.2f} {centroid:8.0f}Hz")

    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"\nmanifest -> {manifest_path} ({len(manifest)} entries)")
    failures.extend(verify_ladder())
    if failures:
        raise SystemExit("checks failed:\n  " + "\n  ".join(failures))
    print("\ntone budget + catch ladder OK")


if __name__ == "__main__":
    main()
