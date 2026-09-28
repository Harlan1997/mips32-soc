#!/usr/bin/env python3
"""Create and validate bounded RTL/Linux differential identities and traces."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Optional

MANIFEST_SCHEMA = "mips32-linux-differential-v1"
REQUIRED_MANIFEST_FIELDS = {
    "schema_version", "git_commit", "git_dirty_status_hash",
    "kernel_sha256", "dtb_sha256", "bootrom_sha256", "ddr_image_sha256",
    "root_image_sha256", "qemu_sha256", "qemu_plugin_sha256",
    "rtl_simulator_sha256", "rtl_source_identity_sha256", "entropy_mode",
    "entropy_seed_id", "entropy_seed_width", "entropy_contract_version",
    "qemu_machine", "rtl_defines", "linux_cmdline", "retire_bound",
    "cycle_bound", "timeout_bound", "terminal_condition",
}
TRACE_FIELDS = {
    "retire_seq", "schema", "pc", "instr", "next_pc", "gpr_we",
    "gpr_addr", "gpr_data", "cp0_we", "cp0_addr", "cp0_sel", "cp0_data",
    "fpr_state", "fcsr_state", "mem_valid", "mem_read", "mem_write",
    "mem_addr", "mem_wdata", "mem_be", "mem_rdata", "except",
    "except_code", "bd", "eret",
}
HEX_FIELDS = {"schema", "pc", "instr", "next_pc", "gpr_data", "cp0_data",
              "mem_addr", "mem_wdata", "mem_rdata"}
HEX_RE = re.compile(r"^[0-9a-fA-F]{8}$|^x{8}$")


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest_digest(manifest: dict) -> str:
    encoded = json.dumps(manifest, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def parse_sets(values):
    result = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"--set requires KEY=VALUE: {value}")
        key, item = value.split("=", 1)
        if not key or key in result:
            raise ValueError(f"duplicate or empty manifest key: {key!r}")
        result[key] = item
    return result


def parse_files(values):
    result = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"--file requires KEY=PATH: {value}")
        key, path = value.split("=", 1)
        if not key or key in result:
            raise ValueError(f"duplicate or empty manifest file key: {key!r}")
        if not Path(path).is_file():
            raise ValueError(f"manifest artifact is missing: {path}")
        result[key] = sha256_file(path)
    return result


def validate_manifest(manifest: dict):
    if not isinstance(manifest, dict):
        raise ValueError("manifest root must be an object")
    missing = sorted(REQUIRED_MANIFEST_FIELDS - set(manifest))
    if missing:
        raise ValueError("manifest missing fields: " + ", ".join(missing))
    if manifest["schema_version"] != MANIFEST_SCHEMA:
        raise ValueError(f"unsupported manifest schema: {manifest['schema_version']!r}")
    for key in REQUIRED_MANIFEST_FIELDS:
        value = manifest[key]
        if not isinstance(value, (str, int)) or value == "":
            raise ValueError(f"manifest field is empty or has invalid type: {key}")
    for key in ("retire_bound", "cycle_bound"):
        if not isinstance(manifest[key], int) or manifest[key] <= 0:
            raise ValueError(f"manifest {key} must be a positive integer")
    if manifest["entropy_mode"] == "deterministic" and not manifest["entropy_seed_id"]:
        raise ValueError("deterministic entropy requires entropy_seed_id")
    return manifest_digest(manifest)


def command_create(args):
    manifest = parse_sets(args.set_values)
    manifest.update(parse_files(args.file_values))
    manifest["schema_version"] = MANIFEST_SCHEMA
    for key in ("retire_bound", "cycle_bound"):
        if key in manifest:
            try:
                manifest[key] = int(manifest[key])
            except (TypeError, ValueError) as exc:
                raise ValueError(f"manifest {key} must be an integer") from exc
    validate_manifest(manifest)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n",
                      encoding="utf-8")
    print(f"LINUX_DIFFERENTIAL_MANIFEST_PASS sha256={manifest_digest(manifest)}")


def command_validate_manifest(args):
    try:
        manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
        digest = validate_manifest(manifest)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"LINUX_DIFFERENTIAL_MANIFEST_FAIL {exc}", file=sys.stderr)
        return 1
    print(f"LINUX_DIFFERENTIAL_MANIFEST_VALID sha256={digest}")
    return 0


def validate_hex_field(record, field):
    value = record.get(field)
    if not isinstance(value, str) or not HEX_RE.fullmatch(value):
        raise ValueError(f"field {field} must be an 8-digit hexadecimal value")


def validate_trace(path: str, max_records: int, exact_records: Optional[int]):
    previous = None
    count = 0
    with open(path, encoding="ascii") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
            if not isinstance(record, dict):
                raise ValueError(f"{path}:{line_number}: record is not an object")
            missing = sorted(TRACE_FIELDS - set(record))
            if missing:
                raise ValueError(f"{path}:{line_number}: missing fields: {', '.join(missing)}")
            sequence = record["retire_seq"]
            if not isinstance(sequence, int) or isinstance(sequence, bool):
                raise ValueError(f"{path}:{line_number}: retire_seq is not an integer")
            if previous is not None and sequence != previous + 1:
                raise ValueError(f"{path}:{line_number}: expected retire_seq {previous + 1}, got {sequence}")
            if previous is None and sequence != 0:
                raise ValueError(f"{path}:{line_number}: first retire_seq must be 0, got {sequence}")
            for field in HEX_FIELDS:
                validate_hex_field(record, field)
            if not isinstance(record["schema"], str) or record["schema"].lower() != "00010000":
                raise ValueError(f"{path}:{line_number}: unsupported trace schema")
            count += 1
            previous = sequence
            if count > max_records:
                raise ValueError(f"{path}: record bound exceeded: {count}>{max_records}")
    if count == 0:
        raise ValueError(f"{path}: trace is empty")
    if exact_records is not None and count != exact_records:
        raise ValueError(f"{path}: expected {exact_records} records, got {count}")
    return count


def command_validate_trace(args):
    try:
        count = validate_trace(args.trace, args.max_records, args.exact_records)
    except (OSError, ValueError) as exc:
        print(f"LINUX_DIFFERENTIAL_TRACE_FAIL {exc}", file=sys.stderr)
        return 1
    print(f"LINUX_DIFFERENTIAL_TRACE_VALID records={count}")
    return 0


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create")
    create.add_argument("--output", required=True)
    create.add_argument("--set", dest="set_values", action="append", default=[])
    create.add_argument("--file", dest="file_values", action="append", default=[])
    create.set_defaults(function=command_create)

    manifest = subparsers.add_parser("validate-manifest")
    manifest.add_argument("manifest")
    manifest.set_defaults(function=command_validate_manifest)

    trace = subparsers.add_parser("validate-trace")
    trace.add_argument("trace")
    trace.add_argument("--max-records", type=int, required=True)
    trace.add_argument("--exact-records", type=int)
    trace.set_defaults(function=command_validate_trace)

    args = parser.parse_args()
    try:
        result = args.function(args)
    except (OSError, ValueError) as exc:
        print(f"LINUX_DIFFERENTIAL_FAIL {exc}", file=sys.stderr)
        return 1
    return result if result is not None else 0


if __name__ == "__main__":
    raise SystemExit(main())
