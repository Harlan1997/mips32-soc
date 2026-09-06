#!/usr/bin/env bash
set -euo pipefail

# System-mode RTL/QEMU retire lockstep entry point. The user-mode reference
# path remains available through cpu-reference-gate.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/lockstep"}
FW_TEST=${FW_TEST:-qemu_system_lockstep_min}
MAX_TRACE_RECORDS=${MAX_TRACE_RECORDS:-100000}
MAX_TRACE_BYTES=${MAX_TRACE_BYTES:-268435456}

export RUN_DIR FW_TEST MAX_TRACE_RECORDS MAX_TRACE_BYTES
exec "${SCRIPT_DIR}/run_qemu_system_differential_gate.sh"
