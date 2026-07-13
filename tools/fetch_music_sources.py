"""Download the CC0 music tracks for the BGM loops.

Fetches into SRC (outside the repo, like the other free-SFX sources). After running
this, run ``tools/prepare_music_assets.py`` to turn them into seamless game loops
under ``assets/audio/music/``.

Every track below is CC0 (verified on its OpenGameArt page — the page text states
"CC0" / "No attribution required"). Origins are also recorded in
``docs/audio_asset_rules.md``.

Two gotchas, both learned the hard way:

* **OpenGameArt appends ``_0`` / ``_2`` on filename collision.** The suffix depends on
  how many same-named files already exist site-wide, so it is *not* derivable from the
  work title. These URLs were taken from the actual page ``href``s. If upstream re-uploads
  a file the suffix can change — hence the size assertion below, and a hard failure
  rather than a silent skip.
* **A User-Agent is mandatory.** OpenGameArt rejects requests that send none.

Run:
    python tools\\fetch_music_sources.py
"""
from __future__ import annotations

import time
import urllib.request
from pathlib import Path


SRC = Path(r"E:\ai-audio\free-sfx\music")
UA = "Mozilla/5.0 corner-fishing-audio (martinqi826@gmail.com)"

# local name -> (url, expected_bytes)
FILES = {
    # First Light Particles — Yoiyami, CC0. Shipped as bgm_day.
    # https://opengameart.org/content/first-light-particles-%E2%80%93-cc0-atmospheric-pianoambient-track
    "oga_cc0_first_light_particles.wav": (
        "https://opengameart.org/sites/default/files/first_light_particles_0.wav", 25_290_280),

    # Contemplation — Joth, CC0. Shipped as bgm_night. Author: "no real melody or focus".
    # https://opengameart.org/content/contemplation-0
    "oga_cc0_contemplation.mp3": (
        "https://opengameart.org/sites/default/files/Contemplation.mp3", 2_405_271),

    # --- Auditioned alternates, kept for future variation. Not currently shipped. ---

    # Yoiyami Core Theme – Deep Blue Ambient Piano — Yoiyami, CC0.
    # Same composer as bgm_day, so it cross-fades with it without a timbre seam.
    # https://opengameart.org/content/yoiyami-core-theme-%E2%80%93-deep-blue-ambient-piano
    "oga_cc0_yoiyami_core_theme.wav": (
        "https://opengameart.org/sites/default/files/yoiyami_core_theme_0.wav", 45_112_360),

    # November Snow — cynicmusic, CC0. Tape-processed lo-fi. Tagged "Trance": audition first.
    # https://opengameart.org/content/november-snow
    "oga_cc0_november_snow.mp3": (
        "https://opengameart.org/sites/default/files/155%20November_snow-33_tape_leveled.mp3",
        13_982_823),

    # Calm Piano 1 (Vaporware) — cynicmusic, CC0. "Uplifting piano melody" — the most
    # foregrounded of the set, and the weakest fit for a non-intrusive companion.
    # https://opengameart.org/content/calm-piano-1-vaporware
    "oga_cc0_calm_piano_vaporware.mp3": (
        "https://opengameart.org/sites/default/files/003_Vaporware_2.mp3", 6_604_773),
}


def download(name: str, url: str, expect: int, tries: int = 3) -> bool:
    dest = SRC / name
    if dest.exists() and dest.stat().st_size == expect:
        print("  skip %-38s already present" % name)
        return True
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": UA})
            data = urllib.request.urlopen(request, timeout=180).read()
            if len(data) != expect:
                raise ValueError(f"size {len(data)} != expected {expect} (upstream re-upload?)")
            dest.write_bytes(data)
            print("  ok   %-38s %10d B" % (name, len(data)))
            return True
        except Exception as exc:  # noqa: BLE001
            if attempt == tries - 1:
                print("  FAIL %-38s %s" % (name, exc))
                return False
            time.sleep(2)
    return False


def main() -> None:
    SRC.mkdir(parents=True, exist_ok=True)
    failed = [name for name, (url, size) in FILES.items() if not download(name, url, size)]
    print("done -> %s" % SRC)
    if failed:
        raise SystemExit("failed: " + ", ".join(failed))


if __name__ == "__main__":
    main()
