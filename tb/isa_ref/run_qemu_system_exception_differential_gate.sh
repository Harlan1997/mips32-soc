#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_exception_differential"}
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
FW_DIR=${FW_DIR:-"${BUILD_DIR}/firmware/qemu_system_exception"}

FW_TEST=qemu_system_exception FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"

# The generic comparator is intentionally reusable and does not know which
# architectural cases a guest is meant to exercise. Keep this corpus-specific
# assertion here so a future firmware regression cannot reduce the gate to the
# original syscall-only test while still reporting a comparator PASS.
python3 - "${RUN_DIR}/rtl/rtl_retire.jsonl" \
    "${RUN_DIR}/qemu/qemu_retire.jsonl" <<'PY'
import json
import sys

def load(path):
    with open(path, encoding="ascii") as stream:
        return [json.loads(line) for line in stream if line.strip()]

rtl, qemu = (load(path) for path in sys.argv[1:])
expected = {
    "01086020": "ADD",
    "012a6022": "SUB",
    "210c0001": "ADDI",
}
for name, records in (("RTL", rtl), ("QEMU", qemu)):
    overflow = [record for record in records if record.get("except_code") == 12]
    opcodes = [record.get("instr") for record in overflow]
    if sorted(opcodes) != sorted(expected):
        raise SystemExit(f"{name} overflow corpus mismatch: {opcodes}")
    if any(record.get("gpr_we") for record in overflow):
        raise SystemExit(f"{name} faulting overflow instruction committed a GPR")
    if not any(record.get("instr") == "250c0001" and
               record.get("except_code") == 0 and
               record.get("gpr_we") and
               record.get("gpr_data") == "80000000" for record in records):
        raise SystemExit(f"{name} ADDIU wrap boundary missing")
    if sum(record.get("except_code") == 8 for record in records) != 1:
        raise SystemExit(f"{name} syscall boundary missing or duplicated")
print("QEMU integer overflow corpus: ADD/SUB/ADDI ExcCode=12, ADDIU wrap PASS")
PY

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System Exception RTL Retire Differential

- Result: PASS
- Firmware: ${FW_DIR}/firmware.elf
- Scope: ADD/SUB/ADDI signed overflow (`ExcCode=12`) with suppressed GPR
  commits, ADDIU wrap without an exception, syscall exception, general vector,
  Cause/EPC reads, EPC update, ERET, and mailbox retirement.
- Evidence: completion_report.md, firmware.sha256, rtl_gate.log, rtl/vcs_uvm_compile.log, rtl/vcs_uvm.log, qemu/qemu_retire.jsonl, qemu/trace_compare.log
- Differential: corpus-specific overflow and syscall checks through the
  mailbox-store retirement boundary.
- Residual risk: delay-slot BD exception, interrupts, MMU faults, and device timing remain separate gates.
EOF
echo "QEMU system exception RTL retire differential: PASS"
