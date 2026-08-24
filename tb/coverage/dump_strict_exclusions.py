#!/usr/bin/env python3
"""Create strict, per-metric URG exclusion files directly from one VDB."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path


METRICS = ("line", "fsm", "cond", "tgl", "branch")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("vdb", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("prefix")
    args = parser.parse_args()
    if not args.vdb.is_dir():
        parser.error(f"missing VDB: {args.vdb}")

    output_dir = args.output_dir.resolve()
    shutil.rmtree(output_dir, ignore_errors=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        ["urg", "-dir", str(args.vdb.resolve()), "-dump", "full_exclusions", "-report", str(output_dir)],
        cwd=output_dir,
        stdout=subprocess.DEVNULL,
        check=True,
    )

    files: list[Path] = []
    for metric in METRICS:
        source = output_dir / f"fullexclude_module.{metric}"
        target = output_dir / f"{args.prefix}_{metric}.el"
        if not source.is_file():
            raise RuntimeError(f"URG did not produce {source}")
        text = source.read_text()
        if "ExclMode: default" not in text:
            raise RuntimeError(f"unexpected URG exclusion mode in {source}")
        target.write_text(text.replace("ExclMode: default", "ExclMode: strict"))
        files.append(target)

    list_path = output_dir / f"{args.prefix}_elfilelist"
    list_path.write_text("".join(f"{path}\n" for path in files))
    print(list_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
