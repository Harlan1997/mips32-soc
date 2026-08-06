#!/bin/bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/ecc_secded_32"}
source /etc/profile.d/modules.sh
module load vcs
mkdir -p "${RUN_DIR}"; cd "${RUN_DIR}"
vcs -full64 -sverilog -timescale=1ns/1ps "${ROOT_DIR}/rtl/perips/ecc_secded_32.v" "${ROOT_DIR}/tb/unit/ddr4/tb_ecc_secded_32.sv" -top tb_ecc_secded_32 -l compile.log
./simv -l sim.log
grep -q "REGRESSION_TEST_SUCCESS ecc_secded_32" sim.log
echo "ECC SECDED gate: PASS"
