#!/usr/bin/env python3
"""Validate the immutable image bundle used by the RTL/QEMU Linux gate."""

import argparse
import hashlib
import sys
from pathlib import Path
from typing import Dict, Optional


REQUIRED_MANIFEST_KEYS = {
    "KERNEL",
    "KERNEL_SHA256",
    "DTB",
    "DTB_SHA256",
    "BOOTROM_SHA256",
    "DDR_SHA256",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_manifest(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in values:
            raise ValueError(f"{path}:{line_number}: duplicate key {key}")
        values[key] = value
    missing = sorted(REQUIRED_MANIFEST_KEYS - values.keys())
    if missing:
        raise ValueError(f"{path}: missing keys: {', '.join(missing)}")
    return values


def validate(image_dir: Path, kernel: Path,
             dtb_override: Optional[Path]) -> Dict[str, str]:
    manifest_path = image_dir / "image_manifest.txt"
    values = parse_manifest(manifest_path)
    image_dtb = image_dir / "mips32_soc_ref_rtl.dtb"
    bootrom = image_dir / "bootrom.hex"
    ddr = image_dir / "ddr.hex"
    for artifact in (image_dtb, bootrom, ddr, kernel):
        if not artifact.is_file() or artifact.stat().st_size == 0:
            raise ValueError(f"missing image artifact: {artifact}")

    actual = {
        "kernel_sha256": sha256(kernel),
        "dtb_sha256": sha256(image_dtb),
        "bootrom_sha256": sha256(bootrom),
        "ddr_sha256": sha256(ddr),
    }
    expected = {
        "kernel_sha256": values["KERNEL_SHA256"],
        "dtb_sha256": values["DTB_SHA256"],
        "bootrom_sha256": values["BOOTROM_SHA256"],
        "ddr_sha256": values["DDR_SHA256"],
    }
    for key, value in actual.items():
        if value != expected[key]:
            raise ValueError(
                f"{key} mismatch: manifest={expected[key]} actual={value}"
            )

    if dtb_override is not None:
        if not dtb_override.is_file() or dtb_override.stat().st_size == 0:
            raise ValueError(f"missing DTB override: {dtb_override}")
        override_hash = sha256(dtb_override)
        if override_hash != actual["dtb_sha256"]:
            raise ValueError(
                f"DTB override mismatch: image={actual['dtb_sha256']} "
                f"override={override_hash}"
            )

    return {
        "image_dir": str(image_dir.resolve()),
        "kernel": str(kernel.resolve()),
        "dtb": str(image_dtb.resolve()),
        **actual,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image-dir", required=True, type=Path)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--dtb", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.image_dir.resolve(), args.kernel.resolve(),
                          args.dtb.resolve() if args.dtb else None)
    except (OSError, ValueError) as exc:
        print(f"LINUX_IMAGE_IDENTITY_FAIL {exc}", file=sys.stderr)
        return 1
    fields = " ".join(f"{key}={value}" for key, value in result.items())
    print(f"LINUX_IMAGE_IDENTITY_PASS {fields}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
