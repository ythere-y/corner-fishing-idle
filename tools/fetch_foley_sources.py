"""Rebuild the CC0 SFX source packs and download the foley one-shots.

Recreates `E:\\ai-audio\\free-sfx\\packs\\` from scratch: the three sound packs that
`prepare_free_sfx_assets.py` layers from, plus the character-foley recordings that
`prepare_catch_and_foley.py` uses (cat meow, thrashing water, line creak).

Everything here is CC0 or public domain. Provenance is duplicated in
`assets/audio/licenses/foley_and_music_sources.txt`, which is the copy that ships.

Run:
    python tools\\fetch_foley_sources.py
Then:
    python tools\\prepare_free_sfx_assets.py     # regenerates the base SFX set
"""
from __future__ import annotations

import io
import time
import urllib.request
import zipfile
from pathlib import Path

import soundfile as sf

from ogg_strip import strip_skeleton


PACKS = Path(r"E:\ai-audio\free-sfx\packs")
UA = "Mozilla/5.0 corner-fishing-audio (martinqi826@gmail.com)"

# local path (relative to PACKS) -> (url, expected_bytes AS DOWNLOADED)
SINGLE_FILES = {
    # Meow of a Siamese cat — freemaster2, CC0
    # https://commons.wikimedia.org/wiki/File:Meow_of_a_Siamese_cat_-_freemaster2.wav
    "_new_foley/cat_meow_siamese_cc0.wav": (
        "https://upload.wikimedia.org/wikipedia/commons/8/81/Meow_of_a_Siamese_cat_-_freemaster2.wav",
        133_814,
    ),
    # Bathtub water splashes — gradha, public domain
    # https://commons.wikimedia.org/wiki/File:Bathtub_water_splashes.ogg
    "_new_foley/water_thrash_bathtub_pd.ogg": (
        "https://upload.wikimedia.org/wikipedia/commons/8/83/Bathtub_water_splashes.ogg",
        768_038,
    ),
    # Assorted creaking noises of office chair — stephan, public domain
    # https://commons.wikimedia.org/wiki/File:Assorted_creaking_noises_of_office_chair.ogg
    # Stand-in for fishing-line tension: no CC0/PD recording of the real thing exists.
    "_new_foley/line_creak_tension_pd.ogg": (
        "https://upload.wikimedia.org/wikipedia/commons/e/e0/Assorted_creaking_noises_of_office_chair.ogg",
        1_613_951,
    ),
}

# Wikimedia serves these Vorbis files with an Ogg Skeleton stream that libsndfile and
# Godot both refuse. Stripping it shrinks the file — so the size assert above must run
# on the *download*, before the re-mux.
NEEDS_OGG_REMUX = (
    "_new_foley/water_thrash_bathtub_pd.ogg",
    "_new_foley/line_creak_tension_pd.ogg",
)

# extract dir (relative to PACKS) -> (zip url, expected_bytes)
ZIP_PACKS = {
    # Interface Sounds — Kenney, CC0 (bundled License.txt).  https://kenney.nl/assets/interface-sounds
    #
    # NOT an OpenGameArt file, despite the directory name — OGA's similarly-named
    # "Interface Sounds Starter Pack" is CC-BY-SA 3.0 / GPL, and its files aren't even
    # called click_001.ogg. Do not "fix" this URL to point at OpenGameArt. The directory
    # name is kept only because prepare_free_sfx_assets.py references it.
    #
    # The URL embeds a content hash that rotates whenever Kenney re-uploads; on 404,
    # scrape https://kenney.nl/assets/interface-sounds for an href ending in
    # kenney_interface-sounds.zip.
    "opengameart_kenney_interface_sounds_cc0": (
        "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
        834_536,
    ),
    # 40 CC0 water / splash / slime SFX — rubberduck, CC0
    # https://opengameart.org/content/40-cc0-water-splash-slime-sfx
    "opengameart_water_splash_slime_cc0": (
        "https://opengameart.org/sites/default/files/water-splash-slime-sfx.zip",
        2_259_262,
    ),
    # 202 More Sound Effects — CC0.  https://opengameart.org/content/202-more-sound-effects
    "opengameart_202_more_sounds_cc0": (
        "https://opengameart.org/sites/default/files/MoreSounds.zip",
        14_937_403,
    ),
}

# Every layer reference in prepare_free_sfx_assets.py + prepare_catch_and_foley.py.
# Checked after the fetch so a silently-wrong archive layout fails here, not three
# scripts later with a confusing FileNotFoundError.
REQUIRED = [
    "opengameart_kenney_interface_sounds_cc0/Audio/click_001.ogg",
    "opengameart_kenney_interface_sounds_cc0/Audio/drop_001.ogg",
    "opengameart_kenney_interface_sounds_cc0/Audio/confirmation_001.ogg",
    "opengameart_kenney_interface_sounds_cc0/Audio/confirmation_002.ogg",
    "opengameart_water_splash_slime_cc0/splash_01.ogg",
    "opengameart_water_splash_slime_cc0/splash_06.ogg",
    "opengameart_water_splash_slime_cc0/splash_09.ogg",
    "opengameart_water_splash_slime_cc0/bubble_02.ogg",
    "opengameart_water_splash_slime_cc0/loop_water_03.ogg",
    "opengameart_202_more_sounds_cc0/Cloth/Cloth_05.wav",
    "opengameart_202_more_sounds_cc0/Money/Money_07.wav",
    "_new_foley/cat_meow_siamese_cc0.wav",
    "_new_foley/water_thrash_bathtub_pd.ogg",
    "_new_foley/line_creak_tension_pd.ogg",
]


def _get(url: str, expect: int, tries: int = 3) -> bytes:
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": UA})
            data = urllib.request.urlopen(request, timeout=180).read()
            if len(data) != expect:
                raise ValueError(f"size {len(data)} != expected {expect} (upstream re-upload?)")
            return data
        except Exception:  # noqa: BLE001
            if attempt == tries - 1:
                raise
            time.sleep(2)
    raise AssertionError("unreachable")


def fetch_single(rel: str, url: str, expect: int) -> None:
    dest = PACKS / rel
    if dest.exists():
        print("  skip  %-42s already present" % rel)
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(_get(url, expect))       # assert size on the raw download...
    if rel in NEEDS_OGG_REMUX:                # ...only then re-mux, which shrinks it
        n_in, n_out = strip_skeleton(dest)
        print("  ok    %-42s %9d B  (skeleton stripped -> %d B)" % (rel, n_in, n_out))
    else:
        print("  ok    %-42s %9d B" % (rel, expect))


def fetch_zip(rel_dir: str, url: str, expect: int) -> None:
    dest = PACKS / rel_dir
    if dest.exists() and any(dest.iterdir()):
        print("  skip  %-42s already present" % rel_dir)
        return
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(_get(url, expect))) as archive:
        archive.extractall(dest)
    print("  ok    %-42s %9d B  (%d files)" % (rel_dir, expect, len(list(dest.rglob("*")))))


def main() -> None:
    PACKS.mkdir(parents=True, exist_ok=True)
    print("zips:")
    for rel_dir, (url, expect) in ZIP_PACKS.items():
        fetch_zip(rel_dir, url, expect)
    print("single files:")
    for rel, (url, expect) in SINGLE_FILES.items():
        fetch_single(rel, url, expect)

    print("\nverifying every referenced layer resolves and decodes:")
    missing, undecodable = [], []
    for rel in REQUIRED:
        path = PACKS / rel
        if not path.exists():
            missing.append(rel)
            continue
        try:
            # The exact failure the Skeleton strip exists to prevent — assert it's gone.
            sf.info(path)
        except Exception as exc:  # noqa: BLE001
            undecodable.append(f"{rel}: {exc}")
    if missing:
        print("  MISSING:\n    " + "\n    ".join(missing))
    if undecodable:
        print("  UNDECODABLE:\n    " + "\n    ".join(undecodable))
    if missing or undecodable:
        raise SystemExit("fetch incomplete")
    print("  all %d referenced sources present and decodable" % len(REQUIRED))
    print("\ndone -> %s" % PACKS)


if __name__ == "__main__":
    main()
