"""Synthesize the "musical" feedback SFX (arpeggios, chimes, stingers).

Why synthesized instead of sourced: these are the game's *high-water-mark* moments
(new species, personal record, achievement, focus reward, epic catch). Sampled
stingers from free packs are almost always arcade-bright and fight the watercolour
calm this project commits to (see docs/audio_asset_rules.md). Plucked strings and
non-harmonic chimes generated here sit inside the ambience bed instead of on top of
it, are trivially tunable, and carry no licence obligation at all.

Output: res://assets/audio/feedback/*.wav, merged into audio_manifest.json.
(The generator MERGES its keys, like prepare_free_sfx_assets.py and
prepare_ambience_assets.py, so any generator can be rerun without clobbering
the others' entries.)

Run:
    python tools\\synth_feedback_sfx.py
Then:
    godot --headless --import
"""
from __future__ import annotations

import json
import zlib
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, sosfiltfilt


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
SR = 44_100
BASE_SEED = 20260708

# Re-seeded per voice in main(). A single shared generator would make every voice's
# waveform depend on how many voices were rendered before it, so merely *adding* a new
# sound silently re-rolls all the others — which broke catch_epic's calibrated mix once
# already. Seeding from the asset id keeps each voice byte-stable in isolation.
RNG = np.random.default_rng(BASE_SEED)


def voice_rng(asset_id: str) -> np.random.Generator:
    return np.random.default_rng(BASE_SEED ^ zlib.crc32(asset_id.encode("utf-8")))


# C-major pentatonic. No semitone clashes, so any two notes stack consonantly —
# this is what keeps overlapping stingers (catch + achievement) from souring.
NOTE = {
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.00, "A4": 440.00,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.00,
    "C6": 1046.50, "D6": 1174.66, "E6": 1318.51, "G6": 1567.98, "A6": 1760.00,
    "C7": 2093.00,
}


def _silence(seconds: float) -> np.ndarray:
    return np.zeros(int(seconds * SR), dtype=np.float32)


def pluck(freq: float, dur: float, damping: float = 0.996, brightness: float = 0.35) -> np.ndarray:
    """Karplus-Strong plucked string — the harp/koto voice used for every arpeggio.

    `damping` < 1 bleeds energy each period (lower = shorter, duller note).
    `brightness` mixes the noise burst toward a softer, lowpassed excitation.
    """
    n = int(dur * SR)
    period = max(2, int(round(SR / freq)))
    burst = RNG.uniform(-1.0, 1.0, period).astype(np.float32)
    # Soften the excitation: a raw noise burst is harsh and glassy.
    smooth = np.convolve(burst, np.ones(3, dtype=np.float32) / 3.0, mode="same")
    burst = brightness * burst + (1.0 - brightness) * smooth

    buf = list(burst)
    out = np.zeros(n, dtype=np.float32)
    for i in range(n):
        out[i] = buf[i]
        # One-pole lowpass in the feedback loop = the characteristic KS decay.
        buf.append(damping * 0.5 * (buf[i] + buf[i + 1 if i + 1 < len(buf) else i]))
    return out


def chime(freq: float, dur: float, amps=(1.0, 0.28, 0.12, 0.04), decay: float = 2.6) -> np.ndarray:
    """Non-harmonic struck bar (wind chime / glass). Ratios are inharmonic on
    purpose — harmonic ratios read as 'organ', these read as 'glass'.

    Partial amplitudes are steep and the high partials are damped hard
    (``ratio ** 0.75``). With gentler settings the 2.76x and 5.40x partials
    dominate the spectral centroid and the chime reads as a bright arcade ping —
    measurably brighter than anything already in the game (see the centroid
    budget in ``main``).
    """
    t = np.linspace(0.0, dur, int(dur * SR), endpoint=False, dtype=np.float32)
    ratios = (1.0, 2.76, 5.40, 8.93)
    out = np.zeros_like(t)
    for ratio, amp in zip(ratios, amps):
        # Higher partials die faster — that's what makes a strike sound struck.
        env = np.exp(-decay * ratio ** 0.75 * t, dtype=np.float32)
        out += amp * env * np.sin(2.0 * np.pi * freq * ratio * t, dtype=np.float32)
    attack = min(len(out), int(0.004 * SR))
    if attack > 1:
        out[:attack] *= np.linspace(0.0, 1.0, attack, dtype=np.float32)
    return out


def shape(audio: np.ndarray, loop: bool, lp_hz: float = 5500.0, hp_hz: float = 45.0) -> np.ndarray:
    """DC-block + gentle lowpass, matching the ambience pipeline's treatment.

    Karplus-Strong seeds from a noise burst whose mean is not zero, so raw plucks
    carry a DC offset an order of magnitude above the recorded assets. The lowpass
    tames the noise-burst transient that otherwise drags the spectral centroid
    well above the game's existing palette.

    Zero-phase ``sosfiltfilt`` rings at the edges, which would re-introduce a seam
    in a loop — so loops are filtered as a 3x tile and the middle third is kept.
    """
    hp = butter(2, hp_hz / (SR / 2), btype="highpass", output="sos")
    lp = butter(2, lp_hz / (SR / 2), btype="lowpass", output="sos")
    if loop:
        n = len(audio)
        tiled = np.tile(audio, 3)
        tiled = sosfiltfilt(lp, sosfiltfilt(hp, tiled))
        return np.ascontiguousarray(tiled[n : 2 * n], dtype=np.float32)
    return sosfiltfilt(lp, sosfiltfilt(hp, audio)).astype(np.float32)


def reverb(audio: np.ndarray, tau: float = 0.32, length: float = 0.9, wet: float = 0.26) -> np.ndarray:
    """Exponentially-decaying noise IR. Cheap, but it's what glues these dry
    synthetic tones into the same room as the recorded ambience bed."""
    n = int(length * SR)
    t = np.linspace(0.0, length, n, endpoint=False, dtype=np.float32)
    ir = RNG.normal(0.0, 1.0, n).astype(np.float32) * np.exp(-t / tau, dtype=np.float32)
    ir[0] = 1.0  # keep the dry transient intact
    wet_sig = fftconvolve(audio, ir)[: len(audio) + n].astype(np.float32)
    dry = np.pad(audio, (0, len(wet_sig) - len(audio)))
    peak = float(np.max(np.abs(wet_sig)))
    if peak > 1e-6:
        wet_sig /= peak
    return ((1.0 - wet) * dry + wet * wet_sig).astype(np.float32)


def sequence(events: list[tuple[float, np.ndarray, float]]) -> np.ndarray:
    """Lay voices onto a timeline: (start_seconds, audio, gain)."""
    total = max(int(start * SR) + len(audio) for start, audio, _ in events)
    mix = np.zeros(total, dtype=np.float32)
    for start, audio, gain in events:
        i = int(start * SR)
        mix[i : i + len(audio)] += audio * gain
    return mix


def arpeggio(notes: list[str], step: float, dur: float, gain_curve=None,
             damping: float = 0.996, brightness: float = 0.35) -> np.ndarray:
    gains = gain_curve or [1.0] * len(notes)
    return sequence([
        (i * step, pluck(NOTE[n], dur, damping, brightness), g)
        for i, (n, g) in enumerate(zip(notes, gains))
    ])


# ---------------------------------------------------------------------------
# The voices. Each returns a dry mono float32 signal; peak/reverb applied later.
# ---------------------------------------------------------------------------

def v_new_species() -> np.ndarray:
    """Curious, warm three-note lift. Fires on every first-ever species (219 of
    them) so it must stay small — this is a bookmark, not a fanfare."""
    return arpeggio(["G4", "C5", "E5"], step=0.085, dur=1.05, gain_curve=[0.7, 0.85, 1.0])


def v_record() -> np.ndarray:
    """Personal-best. Four-note rise, final note held, with an octave-below
    pluck under it for weight."""
    top = arpeggio(["C5", "E5", "G5", "C6"], step=0.095, dur=1.5,
                   gain_curve=[0.55, 0.7, 0.85, 1.0])
    bass = pluck(NOTE["C4"], 1.7, damping=0.9975, brightness=0.3)
    return sequence([(0.0, top, 1.0), (0.285, bass, 0.34)])


def v_achievement() -> np.ndarray:
    """42 achievements — steady and dignified, not celebratory. Open fifth,
    then a single chime to mark it."""
    fifth = sequence([
        (0.0, pluck(NOTE["C5"], 1.4, damping=0.9968), 0.85),
        (0.0, pluck(NOTE["G5"], 1.4, damping=0.9968), 0.55),
    ])
    return sequence([(0.0, fifth, 1.0), (0.16, chime(NOTE["C6"], 1.3, decay=2.2), 0.22)])


def v_focus_reward() -> np.ndarray:
    """Wind chime. Scattered, unhurried, deliberately near-inaudible: it plays
    when the player has been *away* from the window for 25 minutes."""
    picks = ["G5", "C6", "E6", "A5", "D6", "G6", "C7"]
    events = []
    t = 0.0
    for i in range(9):
        note = picks[int(RNG.integers(0, len(picks)))]
        events.append((t, chime(NOTE[note], 2.2, decay=1.9), 0.30 + 0.5 * RNG.random()))
        t += 0.11 + 0.16 * RNG.random()
    return sequence(events)


def v_event_appear() -> np.ndarray:
    """A random event enters (fish shoal, mist, travelling merchant...). Seven event
    types shared a single coin sound between them; six were silent. This is a nudge —
    'look up' — not an alert. Two soft notes, a fifth apart, and one glass chime."""
    notes = sequence([
        (0.0, pluck(NOTE["G4"], 1.2, damping=0.9962), 0.75),
        (0.07, pluck(NOTE["D5"], 1.2, damping=0.9962), 0.60),
    ])
    return sequence([(0.0, notes, 1.0), (0.13, chime(NOTE["G5"], 1.1, decay=2.4), 0.24)])


def v_epic_tail() -> np.ndarray:
    """The rainbow/legendary tail, layered under catch_epic. Five-note rise +
    a long shimmering hold. The single most 'special' sound in the game."""
    rise = arpeggio(["C5", "E5", "G5", "C6", "E6"], step=0.075, dur=1.9,
                    gain_curve=[0.45, 0.6, 0.75, 0.9, 1.0], damping=0.9978)
    shimmer = sequence([
        (0.30, chime(NOTE["G6"], 2.4, decay=1.5), 0.15),
        (0.44, chime(NOTE["C7"], 2.2, decay=1.6), 0.10),
    ])
    bass = pluck(NOTE["C4"], 2.2, damping=0.998, brightness=0.25)
    return sequence([(0.0, rise, 1.0), (0.0, shimmer, 1.0), (0.30, bass, 0.30)])


def v_competition_win() -> np.ndarray:
    """Weekly giant-fish contest gold. Grander than a record: a full rise with
    a low root under it. Still no brass, still no drums."""
    rise = arpeggio(["G4", "C5", "E5", "G5", "C6"], step=0.10, dur=1.9,
                    gain_curve=[0.5, 0.65, 0.8, 0.9, 1.0], damping=0.9976)
    root = sequence([
        (0.0, pluck(NOTE["C4"], 2.3, damping=0.9978, brightness=0.28), 0.36),
        (0.40, pluck(NOTE["G4"], 1.9, damping=0.9972, brightness=0.30), 0.20),
    ])
    return sequence([(0.0, rise, 1.0), (0.0, root, 1.0),
                     (0.40, chime(NOTE["E6"], 2.0, decay=1.7), 0.12)])


def v_spot_unlock() -> np.ndarray:
    """A new fishing spot opens. Wide, airy, upward — 'somewhere new'."""
    rise = arpeggio(["C5", "G5", "C6"], step=0.14, dur=2.0,
                    gain_curve=[0.7, 0.85, 1.0], damping=0.9979, brightness=0.32)
    return sequence([(0.0, rise, 1.0), (0.28, chime(NOTE["G6"], 2.0, decay=1.6), 0.13)])


def v_reel_tension() -> np.ndarray:
    """Seamless loop for the 0.9 s bite→catch window. A low bowed swell plus a
    slow line-creak beat. Pitch is shifted at runtime by fish tier, so keep the
    fundamental low and clean."""
    dur = 1.2
    t = np.linspace(0.0, dur, int(dur * SR), endpoint=False, dtype=np.float32)
    # Bowed swell: two detuned saws, heavily lowpassed via partial summation.
    swell = np.zeros_like(t)
    for h, amp in [(1, 1.0), (2, 0.34), (3, 0.14), (4, 0.06)]:
        swell += amp * np.sin(2 * np.pi * 98.0 * h * t + 0.4 * h)
        swell += amp * 0.7 * np.sin(2 * np.pi * 98.6 * h * t)  # detune = tension beat
    # Creak: amplitude-modulated noise, band-limited by a moving average.
    noise = RNG.normal(0.0, 1.0, len(t)).astype(np.float32)
    noise = np.convolve(noise, np.ones(48, dtype=np.float32) / 48.0, mode="same")
    creak = noise * (0.5 + 0.5 * np.sin(2 * np.pi * 3.1 * t))
    sig = (0.75 * swell / np.max(np.abs(swell)) + 0.25 * creak).astype(np.float32)
    # Equal-power boundary crossfade -> click-free loop.
    xf = int(0.12 * SR)
    head, tail = sig[:xf].copy(), sig[-xf:].copy()
    fade = np.linspace(0.0, 1.0, xf, dtype=np.float32)
    sig[:xf] = head * np.sqrt(fade) + tail * np.sqrt(1.0 - fade)
    return sig[:-xf]


# id -> (voice_fn, subdir/file, peak, reverb kwargs or None, loop, description)
VOICES = {
    "sfx_new_species": (
        v_new_species, "feedback/sfx_new_species.wav", 0.26,
        dict(tau=0.30, length=0.8, wet=0.24), False,
        "Warm three-note harp lift for a first-ever species. Synthesized (Karplus-Strong), public domain.",
    ),
    "sfx_record": (
        v_record, "feedback/sfx_record.wav", 0.30,
        dict(tau=0.38, length=1.1, wet=0.28), False,
        "Four-note rise with octave-below root — personal best weight. Synthesized, public domain.",
    ),
    "sfx_achievement": (
        v_achievement, "feedback/sfx_achievement.wav", 0.27,
        dict(tau=0.34, length=1.0, wet=0.26), False,
        "Open fifth plus a single glass chime — dignified achievement mark. Synthesized, public domain.",
    ),
    "sfx_focus_reward": (
        v_focus_reward, "feedback/sfx_focus_reward.wav", 0.20,
        dict(tau=0.45, length=1.3, wet=0.34), False,
        "Scattered wind chime for the focus reward. Deliberately near-inaudible. Synthesized, public domain.",
    ),
    "sfx_event_appear": (
        v_event_appear, "feedback/sfx_event_appear.wav", 0.22,
        dict(tau=0.32, length=0.9, wet=0.28), False,
        "Two soft notes and a chime — a random event has appeared. Synthesized, public domain.",
    ),
    "sfx_epic_tail": (
        v_epic_tail, "feedback/sfx_epic_tail.wav", 0.30,
        dict(tau=0.50, length=1.5, wet=0.32), False,
        "Five-note rise + shimmer tail, layered under catch_epic. Synthesized, public domain.",
    ),
    # ^ Written to disk for prepare_catch_and_foley.py to layer, but kept OUT of the
    #   manifest (see NOT_PLAYABLE): the game never plays it on its own, and every
    #   manifest entry is eagerly load()ed into memory by AudioManager at startup.
    "sfx_competition_win": (
        v_competition_win, "feedback/sfx_competition_win.wav", 0.31,
        dict(tau=0.48, length=1.4, wet=0.30), False,
        "Weekly giant-fish contest gold. Full rise over a low root. Synthesized, public domain.",
    ),
    "sfx_spot_unlock": (
        v_spot_unlock, "feedback/sfx_spot_unlock.wav", 0.28,
        dict(tau=0.55, length=1.5, wet=0.34), False,
        "Wide airy rise for unlocking a new fishing spot. Synthesized, public domain.",
    ),
    "sfx_reel_tension": (
        v_reel_tension, "feedback/sfx_reel_tension.wav", 0.16,
        None, True,
        "Seamless low bowed-swell + line-creak loop for the bite->catch window. Synthesized, public domain.",
    ),
}


def apply_fades(audio: np.ndarray, fade_in: float = 0.004, fade_out: float = 0.12) -> np.ndarray:
    out = audio.copy()
    in_n = min(len(out), int(fade_in * SR))
    out_n = min(len(out), int(fade_out * SR))
    if in_n > 1:
        out[:in_n] *= np.linspace(0.0, 1.0, in_n, dtype=np.float32)
    if out_n > 1:
        out[-out_n:] *= np.linspace(1.0, 0.0, out_n, dtype=np.float32)
    return out


def normalize_peak(audio: np.ndarray, peak: float) -> np.ndarray:
    current = float(np.max(np.abs(audio))) if len(audio) else 0.0
    if current <= 1e-6:
        return audio
    return (audio * (peak / current)).astype(np.float32)


def spectral_centroid(audio: np.ndarray) -> float:
    """Brightness proxy, in Hz. Used as a regression guard — see CENTROID_BUDGET."""
    spectrum = np.abs(np.fft.rfft(audio * np.hanning(len(audio))))
    freqs = np.fft.rfftfreq(len(audio), 1.0 / SR)
    return float(np.sum(freqs * spectrum) / max(float(np.sum(spectrum)), 1e-9))


# Measured centroids of the assets already shipping (and already accepted):
# upgrade 697 Hz, bite 721 Hz, cast 1191 Hz, catch_rare 4286 Hz, catch_common 6048 Hz.
# New feedback voices must not out-shine catch_rare, or they read as arcade pings
# against the watercolour palette. The chime-led wind bell gets a little more room.
CENTROID_BUDGET = 4300.0
CENTROID_BUDGET_OVERRIDE = {"sfx_focus_reward": 5000.0}
DC_BUDGET = 0.0015  # the loudest DC among shipping assets is ui_click at 0.00143

# Rendered to disk (other generators layer them) but never played by the game, so they
# stay out of audio_manifest.json — AudioManager load()s every manifest entry at startup.
NOT_PLAYABLE = {"sfx_epic_tail"}


def main() -> None:
    manifest_path = OUT / "audio_manifest.json"
    manifest = {}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    global RNG
    failures = []
    print(f"{'id':24s} {'len':>6s} {'peak':>6s} {'centroid':>9s} {'DC':>9s}")
    for asset_id, (fn, rel, peak, rev, loop, desc) in VOICES.items():
        RNG = voice_rng(asset_id)   # isolate this voice from the rendering order
        audio = fn()
        if rev is not None:
            audio = reverb(audio, **rev)
        audio = shape(audio, loop)
        # A loop must not be faded at the boundary or the seam reappears.
        audio = audio if loop else apply_fades(audio)
        audio = normalize_peak(audio, peak)

        centroid = spectral_centroid(audio)
        dc = abs(float(np.mean(audio)))
        budget = CENTROID_BUDGET_OVERRIDE.get(asset_id, CENTROID_BUDGET)
        flag = ""
        if centroid > budget:
            flag += f" !! centroid {centroid:.0f} > {budget:.0f}"
        if dc > DC_BUDGET:
            flag += f" !! DC {dc:.5f} > {DC_BUDGET}"
        if flag:
            failures.append(asset_id + flag)

        out = OUT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        sf.write(out, audio, SR, subtype="PCM_16")
        if asset_id in NOT_PLAYABLE:
            manifest.pop(asset_id, None)   # also cleans it up from an older manifest
        else:
            manifest[asset_id] = {
                "path": "res://assets/audio/" + rel,
                "duration_seconds": round(len(audio) / SR, 3),
                "loop": loop,
                "description": desc,
            }
        note = "  (build ingredient, not in manifest)" if asset_id in NOT_PLAYABLE else ""
        print(f"{asset_id:24s} {len(audio) / SR:5.2f}s {peak:6.2f} "
              f"{centroid:8.0f}Hz {dc:9.5f}{flag}{note}")

    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"\nmanifest -> {manifest_path} ({len(manifest)} entries)")
    if failures:
        raise SystemExit("tone budget exceeded:\n  " + "\n  ".join(failures))
    print("tone budget OK")


if __name__ == "__main__":
    main()
