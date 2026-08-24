#!/usr/bin/env bash
set -euo pipefail

# Historical compatibility alias. QEMU is the supported reference path;
# this target does not claim instruction-level RTL lockstep signoff.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu"}
exec "${SCRIPT_DIR}/run_qemu_reference_gate.sh"
