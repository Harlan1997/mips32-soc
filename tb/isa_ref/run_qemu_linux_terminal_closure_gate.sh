#!/usr/bin/env bash
set -euo pipefail

# Compact, terminal-triggered closure for the declared Linux userspace
# workload. This gate intentionally does not materialize a 150M-record retire
# trace; the architectural differential remains a separate blocked phase.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=$(realpath -m "${RUN_DIR:-/data/disk/tmp/mips32-soc/qemu-linux-terminal-closure-$(date +%Y%m%d-%H%M%S)}")
KERNEL=${KERNEL:-}
LINUX_IMAGE_DIR=${LINUX_IMAGE_DIR:-}
QEMU_BIN=${QEMU_BIN:-/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel}
QEMU_SRC=${QEMU_SRC:-/data/disk/tmp/mips32-soc/qemu-9.2.0}
QEMU_BUILD=${QEMU_BUILD:-${QEMU_SRC}/build-mipsel-softmmu}
QEMU_MEMORY=${QEMU_MEMORY:-64M}
# Leave the command line empty by default so QEMU consumes the bootargs from
# the manifest DTB used by the proven native Linux workload.
QEMU_APPEND=${QEMU_APPEND:-}
LINUX_RNG_SEED=${LINUX_RNG_SEED:-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}
QEMU_MARKER_WATCHDOG_SECONDS=${QEMU_MARKER_WATCHDOG_SECONDS:-3600}

[[ -s "${KERNEL}" ]] || {
    echo "QEMU Linux terminal closure: KERNEL=/path/to/vmlinux is required" >&2
    exit 2
}
[[ -d "${LINUX_IMAGE_DIR}" ]] || {
    echo "QEMU Linux terminal closure: LINUX_IMAGE_DIR=/path/to/image is required" >&2
    exit 2
}
[[ -x "${QEMU_BIN}" ]] || {
    echo "QEMU Linux terminal closure: QEMU_BIN is not executable: ${QEMU_BIN}" >&2
    exit 2
}
[[ "${LINUX_RNG_SEED}" =~ ^[0-9a-fA-F]+$ && $(( ${#LINUX_RNG_SEED} % 2 )) -eq 0 ]] || {
    echo "QEMU Linux terminal closure: LINUX_RNG_SEED must be even-length hexadecimal" >&2
    exit 2
}

KERNEL=$(realpath "${KERNEL}")
LINUX_IMAGE_DIR=$(realpath "${LINUX_IMAGE_DIR}")
mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md" "${RUN_DIR}/qemu_gate.log"

python3 "${ROOT_DIR}/scripts/validate_linux_image_identity.py" \
    --image-dir "${LINUX_IMAGE_DIR}" --kernel "${KERNEL}" \
    >"${RUN_DIR}/image_identity.log"
DTB=$(sed -n 's/.* dtb=\([^ ]*\).*/\1/p' "${RUN_DIR}/image_identity.log")
[[ -s "${DTB}" ]]

peripheral_trace="${RUN_DIR}/qemu/peripheral.jsonl"
echo "QEMU Linux terminal closure: running terminal workload" >&2
env RUN_DIR="${RUN_DIR}/qemu" \
    QEMU_BIN="${QEMU_BIN}" QEMU_SRC="${QEMU_SRC}" QEMU_BUILD="${QEMU_BUILD}" \
    QEMU_KERNEL="${KERNEL}" QEMU_DTB="${DTB}" QEMU_MEMORY="${QEMU_MEMORY}" \
    QEMU_APPEND="${QEMU_APPEND}" QEMU_MACHINE_PROPERTIES="linux-guest=on" \
    QEMU_LINUX_RNG_SEED="${LINUX_RNG_SEED}" QEMU_ACCEL=tcg,thread=single \
    QEMU_STOP_ON_TERMINAL=1 QEMU_TERMINAL_MARKER=MIPS32_SOC_LINUX_TERMINAL \
    QEMU_MARKER_WATCHDOG_SECONDS="${QEMU_MARKER_WATCHDOG_SECONDS}" \
    QEMU_TERMINAL_DRAIN_SECONDS=1 QEMU_UNBOUNDED_CAPTURE=1 \
    QEMU_SUMMARY_ONLY=1 QEMU_PERIPHERAL_TRACE="${peripheral_trace}" \
    QEMU_PLUGIN_UART_TRACE="${peripheral_trace}" \
    MAX_QEMU_EVENTS=0 MAX_QEMU_STATES=0 MAX_QEMU_CAPTURE_BYTES=0 \
    REQUIRE_SMOKE_OUTPUT=0 SKIP_COMPARE=1 \
    "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
    >"${RUN_DIR}/qemu_gate.log" 2>&1

python3 "${ROOT_DIR}/scripts/validate_qemu_linux_terminal.py" \
    --stdout "${RUN_DIR}/qemu/qemu_stdout.log" \
    --peripheral "${peripheral_trace}" \
    --output "${RUN_DIR}/marker_evidence.json" \
    >"${RUN_DIR}/marker_validation.log"

summary_records=$(sed -n 's/^terminal_marker=flushed record=\([0-9][0-9]*\).*/\1/p' \
    "${RUN_DIR}/qemu/qemu_capture_status.txt")
[[ -n "${summary_records}" ]]
seed_id=$(printf '%s' "${LINUX_RNG_SEED}" | sha256sum | awk '{print $1}')
git_commit=$(git -C "${ROOT_DIR}" rev-parse HEAD)
export RUN_DIR LINUX_IMAGE_DIR KERNEL DTB QEMU_BIN QEMU_MEMORY QEMU_APPEND
export SEED_ID="${seed_id}" GIT_COMMIT="${git_commit}" SUMMARY_RECORDS="${summary_records}"
python3 - "${RUN_DIR}/qemu_terminal_manifest.json" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

run = Path(os.environ["RUN_DIR"])
image = Path(os.environ["LINUX_IMAGE_DIR"])
manifest = {
    "schema": "mips32-linux-qemu-terminal-v1",
    "result": "PASS",
    "terminal_marker": "MIPS32_SOC_LINUX_TERMINAL",
    "kernel_sha256": digest(os.environ["KERNEL"]),
    "dtb_sha256": digest(os.environ["DTB"]),
    "image_manifest_sha256": digest(image / "image_manifest.txt"),
    "bootrom_sha256": digest(image / "bootrom.hex"),
    "ddr_image_sha256": digest(image / "ddr.hex"),
    "qemu_sha256": digest(os.environ["QEMU_BIN"]),
    "qemu_plugin_sha256": digest(run / "qemu" / "libqemu_retire.so"),
    "marker_evidence_sha256": digest(run / "marker_evidence.json"),
    "entropy_mode": "deterministic",
    "entropy_seed_id": os.environ["SEED_ID"],
    "qemu_machine": "mips32-soc-ref",
    "qemu_properties": "linux-guest=on",
    "qemu_memory": os.environ["QEMU_MEMORY"],
    "linux_cmdline": os.environ["QEMU_APPEND"],
    "git_commit": os.environ["GIT_COMMIT"],
    "retired_instructions_through_terminal": int(os.environ["SUMMARY_RECORDS"]),
}
(run / "qemu_terminal_manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU Linux Terminal Closure

- Result: PASS (complete declared workload through terminal marker)
- Kernel: ${KERNEL}
- DTB/image: ${DTB} / ${LINUX_IMAGE_DIR}
- Retired instructions through terminal: ${summary_records}
- Terminal UART evidence: marker_evidence.json
- Deterministic entropy seed id: ${seed_id}
- Manifest: qemu_terminal_manifest.json
- Producer evidence: qemu/qemu_gate.log, qemu/qemu_stdout.log,
  qemu/qemu_capture_status.txt, qemu/peripheral.jsonl
- Scope: QEMU execution of the declared Linux userspace workload. RTL
  userspace reachability and full RTL/QEMU architectural differential remain
  open because the current RTL run Oopses before the terminal marker.
EOF
echo "QEMU Linux terminal closure: PASS (retired=${summary_records})"
