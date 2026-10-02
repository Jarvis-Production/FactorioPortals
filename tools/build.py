#!/usr/bin/env python3
"""Packs portal-guns/ into dist/portal-guns_<version>.zip, the layout Factorio and the mod portal expect
(one top-level folder named <name>_<version>). The zip is reproducible: fixed timestamps, sorted entries.

    python3 tools/build.py
"""
from __future__ import annotations

import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "portal-guns"


def main() -> None:
    info = json.loads((MOD / "info.json").read_text())
    folder = f"{info['name']}_{info['version']}"
    out = ROOT / "dist" / f"{folder}.zip"
    out.parent.mkdir(exist_ok=True)
    files = sorted(p for p in MOD.rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in files:
            entry = zipfile.ZipInfo(f"{folder}/{path.relative_to(MOD).as_posix()}", date_time=(2026, 1, 1, 0, 0, 0))
            entry.external_attr = 0o644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(entry, path.read_bytes())
    print(f"{out.relative_to(ROOT)}: {len(files)} files, {out.stat().st_size / 1024:.0f} KiB")


if __name__ == "__main__":
    main()
