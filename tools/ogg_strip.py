"""Strip non-Vorbis logical streams (e.g. Ogg Skeleton / 'fishead') from an Ogg file.

Wikimedia Commons serves many Ogg Vorbis files multiplexed with an Ogg Skeleton
metadata stream. libsndfile (and Godot's Ogg importer) reject those outright. Dropping
the non-Vorbis pages is a lossless re-mux: pages are copied verbatim, so their CRCs stay
valid, and the Vorbis stream's own page sequence numbers remain contiguous.

Idempotent: re-running on an already-stripped file rewrites identical bytes.

Run standalone:
    python tools\\ogg_strip.py some.ogg other.ogg
"""
from __future__ import annotations

import pathlib
import struct


class OggStripError(Exception):
    pass


def _pages(data: bytes):
    """Yield (start, end, serial, payload) for each Ogg page.

    Raises rather than stopping at the first bad header — a truncated download would
    otherwise be silently cropped into a playable-but-incomplete file.
    """
    i, n = 0, len(data)
    while i < n:
        if data[i : i + 4] != b"OggS":
            raise OggStripError(f"bad Ogg page header at byte {i} (truncated or corrupt?)")
        if i + 27 > n:
            raise OggStripError(f"truncated Ogg page header at byte {i}")
        segments = data[i + 26]
        table = data[i + 27 : i + 27 + segments]
        if len(table) != segments:
            raise OggStripError(f"truncated segment table at byte {i}")
        end = i + 27 + segments + sum(table)
        if end > n:
            raise OggStripError(f"truncated page payload at byte {i}")
        serial = struct.unpack("<I", data[i + 14 : i + 18])[0]
        yield i, end, serial, data[i + 27 + segments : end]
        i = end


def strip_skeleton(src, dst=None) -> tuple[int, int]:
    """Keep only the Vorbis logical stream. Returns (bytes_in, bytes_out)."""
    src = pathlib.Path(src)
    dst = pathlib.Path(dst) if dst is not None else src
    data = src.read_bytes()

    vorbis_serial = None
    for _, _, serial, payload in _pages(data):
        if payload[:7] == b"\x01vorbis":
            vorbis_serial = serial
            break
    if vorbis_serial is None:
        raise OggStripError(f"no Vorbis stream found in {src}")

    kept = b"".join(
        data[start:end] for start, end, serial, _ in _pages(data) if serial == vorbis_serial
    )
    dst.write_bytes(kept)
    return len(data), len(kept)


if __name__ == "__main__":
    import sys

    for path in sys.argv[1:]:
        n_in, n_out = strip_skeleton(path)
        note = "unchanged" if n_in == n_out else f"{n_in} -> {n_out} bytes"
        print(f"{pathlib.Path(path).name}: {note}")
