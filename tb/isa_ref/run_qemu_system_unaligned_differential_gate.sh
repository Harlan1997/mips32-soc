#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_unaligned_differential"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/qemu_system_unaligned"}
FW_TEST=qemu_system_unaligned FW_DIR="${FW_DIR}" RUN_DIR="${RUN_DIR}" \
    REQUIRE_SMOKE_OUTPUT=0 STOP_AFTER_MAILBOX=1 \
    "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"
cat >"${RUN_DIR}/unaligned_scope.md" <<EOF
# Unaligned merge differential

- Result: PASS
- Scope: LWL/LWR and SWL/SWR little-endian merge semantics through mailbox retirement.
- Boundary: no claim for full ISA, cross-page fault policy, or Linux unaligned ABI.
EOF
echo "QEMU system unaligned RTL differential: PASS"
