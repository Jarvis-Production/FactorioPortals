#!/usr/bin/env python3
"""Asset oracle for the Portal Guns mod.

The headless Factorio server never loads graphics or sounds (it ships without any), so a wrong path or a
sprite sheet that is too small only shows up in the real client. This script closes that gap: it reads the
game's own `--dump-data` output (data.raw after every mod ran), finds every `__portal-guns__/...` file the
prototypes reference, and checks that

  * the file exists in the mod,
  * a PNG sheet has exactly the size the sprite definition implies (frame size x line_length x rows),
  * an icon is `icon_size` tall (and at least that wide),
  * a sound file is an Ogg stream,
  * nothing under graphics/ or sound/ is left unreferenced.

Usage:
    python3 tools/check_assets.py <data-raw-dump.json>
    python3 tools/check_assets.py --factorio /path/to/bin/x64/factorio --mods /path/to/mod-dir
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "portal-guns"
PREFIX = "__portal-guns__/"


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    return struct.unpack(">II", head[16:24])


def frame_size(d: dict) -> tuple[int, int]:
    size = d.get("size")
    if isinstance(size, (int, float)):
        return int(size), int(size)
    if isinstance(size, list):
        return int(size[0]), int(size[1])
    return int(d["width"]), int(d["height"])


class Checker:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.referenced: set[Path] = set()
        self.checked = 0

    def resolve(self, ref: str, where: str) -> Path | None:
        path = MOD / ref[len(PREFIX):]
        self.referenced.add(path.resolve())
        if not path.is_file():
            self.errors.append(f"{where}: missing file {ref}")
            return None
        return path

    def sprite(self, d: dict, where: str) -> None:
        path = self.resolve(d["filename"], where)
        if not path:
            return
        self.checked += 1
        w, h = frame_size(d)
        frames = int(d.get("frame_count", 1)) * int(d.get("direction_count", 1))
        line = int(d.get("line_length", 0)) or frames
        cols, rows = min(line, frames), math.ceil(frames / line)
        need = (int(d.get("x", 0)) + w * cols, int(d.get("y", 0)) + h * rows)
        actual = png_size(path)
        if actual != need:
            self.errors.append(f"{where}: {d['filename']} is {actual[0]}x{actual[1]}, the definition implies "
                               f"{need[0]}x{need[1]} ({frames} frames of {w}x{h}, {cols} per row)")

    def icon(self, ref: str, size: int, where: str) -> None:
        path = self.resolve(ref, where)
        if not path:
            return
        self.checked += 1
        w, h = png_size(path)
        if h != size or w < size:
            self.errors.append(f"{where}: icon {ref} is {w}x{h}, icon_size is {size}")

    def sound(self, d: dict, where: str) -> None:
        path = self.resolve(d["filename"], where)
        if not path:
            return
        self.checked += 1
        if path.read_bytes()[:4] != b"OggS":
            self.errors.append(f"{where}: {d['filename']} is not an Ogg file")

    def walk(self, node, where: str) -> None:
        if isinstance(node, dict):
            filename = node.get("filename")
            if isinstance(filename, str) and filename.startswith(PREFIX):
                if filename.endswith(".png"):
                    self.sprite(node, where)
                elif filename.endswith((".ogg", ".wav")):
                    self.sound(node, where)
                else:
                    self.resolve(filename, where)
            for key, size_key in (("icon", "icon_size"), ("small_icon", "small_icon_size")):
                ref = node.get(key)
                if isinstance(ref, str) and ref.startswith(PREFIX):
                    self.icon(ref, int(node.get(size_key, 64)), f"{where}.{key}")
            for key, value in node.items():
                if key not in ("filename",):
                    self.walk(value, f"{where}.{key}")
        elif isinstance(node, list):
            for i, value in enumerate(node):
                self.walk(value, f"{where}[{i}]")


def dump_data(factorio: str, mods: str) -> Path:
    subprocess.run([factorio, "--mod-directory", mods, "--dump-data"], check=True, stdout=subprocess.DEVNULL)
    write_dir = Path(factorio).resolve().parents[2]
    return write_dir / "script-output" / "data-raw-dump.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dump", nargs="?", help="data-raw-dump.json written by factorio --dump-data")
    parser.add_argument("--factorio", help="factorio executable; runs --dump-data first")
    parser.add_argument("--mods", help="mod directory to use with --factorio")
    args = parser.parse_args()
    if args.factorio:
        dump = dump_data(args.factorio, args.mods)
    elif args.dump:
        dump = Path(args.dump)
    else:
        parser.error("give a dump file or --factorio and --mods")

    data = json.loads(dump.read_text())
    checker = Checker()
    for proto_type, prototypes in data.items():
        for name, prototype in prototypes.items():
            checker.walk(prototype, f"{proto_type}/{name}")

    for folder in ("graphics", "sound"):
        for path in sorted((MOD / folder).rglob("*")):
            if path.is_file() and path.resolve() not in checker.referenced:
                checker.errors.append(f"unreferenced file: {path.relative_to(ROOT)}")
    thumb = MOD / "thumbnail.png"
    if not thumb.is_file() or png_size(thumb) != (144, 144):
        checker.errors.append("thumbnail.png must exist and be 144x144")

    for error in checker.errors:
        print("FAIL", error)
    print(f"checked {checker.checked} references to {PREFIX}, {len(checker.errors)} problem(s)")
    return 1 if checker.errors else 0


if __name__ == "__main__":
    sys.exit(main())
