#!/usr/bin/env python3
"""Runs the Portal Guns test suite on a real (headless) Factorio server.

For each mod set (base game only, and base + Space Age + Quality + Elevated Rails) it:
  1. builds a throwaway mod folder with mod-list.json, the mod and the test harness (symlinked),
  2. `--create`s a map (the data stage and on_init run here: any prototype error fails the run),
  3. `--dump-data` and runs tools/check_assets.py (the headless server never loads sprites or sounds),
  4. runs the map in `--benchmark` mode; tests/portal-guns-tests prints PASS/FAIL lines.

Usage:
    python3 tools/run_tests.py --factorio /opt/factorio/bin/x64/factorio [--only base|space-age] [-v]

The Factorio headless server is a free download from factorio.com (or the factoriotools/factorio image).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD_SETS = {
    "base": {"base": True, "elevated-rails": False, "quality": False, "space-age": False},
    "space-age": {"base": True, "elevated-rails": True, "quality": True, "space-age": True},
}
TICKS = 12000


def run(cmd: list[str], verbose: bool) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if verbose:
        print(output)
    if result.returncode != 0:
        print(output[-4000:])
        raise SystemExit(f"command failed ({result.returncode}): {' '.join(cmd)}")
    return output


def errors_in(output: str) -> list[str]:
    return [line for line in output.splitlines() if re.search(r"\bError\b", line) and "Error while" not in line] + \
        [line for line in output.splitlines() if "Error while" in line or "non-recoverable" in line]


def run_set(factorio: str, name: str, verbose: bool) -> bool:
    print(f"== {name}")
    with tempfile.TemporaryDirectory(prefix=f"portal-guns-{name}-") as tmp:
        mods = Path(tmp) / "mods"
        mods.mkdir()
        os.symlink(ROOT / "portal-guns", mods / "portal-guns")
        os.symlink(ROOT / "tests" / "portal-guns-tests", mods / "portal-guns-tests")
        enabled = dict(MOD_SETS[name], **{"portal-guns": True, "portal-guns-tests": True})
        (mods / "mod-list.json").write_text(json.dumps({"mods": [{"name": k, "enabled": v} for k, v in enabled.items()]}))
        save = Path(tmp) / "test.zip"

        out = run([factorio, "--mod-directory", str(mods), "--create", str(save)], verbose)
        problems = errors_in(out)
        if problems or not save.exists():
            print("\n".join(problems) or "map was not created")
            return False
        print("   data stage + on_init: ok")

        run([factorio, "--mod-directory", str(mods), "--dump-data"], verbose)
        dump = Path(factorio).resolve().parents[2] / "script-output" / "data-raw-dump.json"
        assets = subprocess.run([sys.executable, str(ROOT / "tools" / "check_assets.py"), str(dump)],
                                capture_output=True, text=True)
        print("   assets: " + assets.stdout.strip().splitlines()[-1])
        if assets.returncode != 0:
            print(assets.stdout)
            return False

        out = run([factorio, "--mod-directory", str(mods), "--benchmark", str(save), "--benchmark-ticks", str(TICKS),
                   "--benchmark-ignore-paused"], verbose)
        results = [line for line in out.splitlines() if line.startswith(("PASS", "FAIL", "TESTS"))]
        for line in results:
            print("   " + line)
        problems = errors_in(out)
        if problems:
            print("\n".join(problems))
        done = [line for line in results if line.startswith("TESTS DONE")]
        return bool(done) and "failed=0" in done[0] and not problems


def bench(factorio: str, ticks: int = 3600) -> None:
    """Average tick time with 100 linked portal pairs vs. the same map with nothing linked (base game), once
    with a character standing next to every blue portal (busy) and once with nothing near any portal (idle)."""
    def measure(markers: list[str]) -> float:
        with tempfile.TemporaryDirectory(prefix="portal-guns-perf-") as tmp:
            mods = Path(tmp) / "mods"
            mods.mkdir()
            os.symlink(ROOT / "portal-guns", mods / "portal-guns")
            os.symlink(ROOT / "tests" / "portal-guns-perf", mods / "portal-guns-perf")
            enabled = dict(MOD_SETS["base"], **{"portal-guns": True, "portal-guns-perf": True})
            for marker in markers:
                (mods / marker).mkdir()
                (mods / marker / "info.json").write_text(json.dumps({
                    "name": marker, "version": "1.0.0", "title": "marker", "author": "tests",
                    "factorio_version": "2.0", "dependencies": ["base"]}))
                enabled[marker] = True
            (mods / "mod-list.json").write_text(json.dumps({"mods": [{"name": k, "enabled": v} for k, v in enabled.items()]}))
            save = Path(tmp) / "perf.zip"
            run([factorio, "--mod-directory", str(mods), "--create", str(save)], False)
            out = run([factorio, "--mod-directory", str(mods), "--benchmark", str(save), "--benchmark-ticks", str(ticks),
                       "--benchmark-ignore-paused"], False)
            match = re.search(r"avg: ([0-9.]+) ms", out)
            return float(match.group(1)) if match else float("nan")

    for label, extra in (("busy (a character at every blue portal)", []), ("idle (nothing near any portal)", ["portal-guns-perf-nochars"])):
        base = measure(["portal-guns-perf-unlinked"] + extra)
        linked = measure(extra)
        print(f"   {label}: {base:.3f} -> {linked:.3f} ms/tick, 100 linked pairs cost {linked - base:+.3f} ms "
              f"({(linked - base) / (1000 / 60) * 100:+.1f}% of a 60 UPS tick)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--factorio", default=os.environ.get("FACTORIO", shutil.which("factorio")),
                        help="path to the factorio executable (or set FACTORIO)")
    parser.add_argument("--only", choices=sorted(MOD_SETS), help="run one mod set only")
    parser.add_argument("-v", "--verbose", action="store_true", help="print the full game output")
    parser.add_argument("--perf", action="store_true", help="also benchmark 100 linked portal pairs")
    args = parser.parse_args()
    if not args.factorio:
        parser.error("pass --factorio or set FACTORIO")
    sets = [args.only] if args.only else list(MOD_SETS)
    ok = all([run_set(args.factorio, name, args.verbose) for name in sets])
    if args.perf:
        print("== perf")
        bench(args.factorio)
    print("ALL GREEN" if ok else "SOME TESTS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
