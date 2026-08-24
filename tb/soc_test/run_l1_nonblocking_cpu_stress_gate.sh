#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/soc_test/l1_nonblocking_cpu_stress"}
FW_HEX=${FW_HEX:-"${ROOT_DIR}/build/firmware/soc_smoke/firmware.hex"}
SEEDS=${SEEDS:-"11 29 47"}

if [ ! -f "${FW_HEX}" ]; then
    echo "ERROR: FW_HEX does not exist: ${FW_HEX}" >&2
    echo "Build it with: make firmware" >&2
    exit 1
fi

mkdir -p "${RUN_ROOT}"
summary="${RUN_ROOT}/l1_nonblocking_cpu_stress_report.md"
failed=0
passes=0
reset_hits=0

for seed in ${SEEDS}; do
    run_dir="${RUN_ROOT}/seed_${seed}"
    log="${run_dir}/sim.log"
    echo "L1 nonblocking CPU stress: seed=${seed} run_dir=${run_dir}"
    if ! FW_HEX="${FW_HEX}" RUN_DIR="${run_dir}" \
        VCS_EXTRA_ARGS="+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_L1_NONBLOCKING_RESET_STRESS" \
        SIM_EXTRA_ARGS="+ntb_random_seed=${seed}" \
        "${SCRIPT_DIR}/run.sh"; then
        failed=1
        continue
    fi
    if ! grep -q "REGRESSION_TEST_SUCCESS" "${log}"; then
        echo "ERROR: seed ${seed} did not reach firmware success" >&2
        failed=1
        continue
    fi
    passes=$((passes + 1))
    if grep -q "Testing AXI mid-flight reset via JTAG" "${log}"; then
        reset_hits=$((reset_hits + 1))
    else
        echo "ERROR: seed ${seed} did not exercise mid-flight reset" >&2
        failed=1
    fi
done

cat > "${summary}" <<EOF
# L1 Nonblocking CPU Stress Gate

Result: $(if [ "${failed}" -eq 0 ]; then echo PASS; else echo FAIL; fi)

- Configuration: SOC_L1_NONBLOCKING_ENABLE=1, SOC_ROB_FIFO_ENABLE=1,
  SOC_CPU_NONBLOCKING_ENABLE=1, real CPU/D-cache path.
- Seeds requested: ${SEEDS}
- Firmware passes: ${passes}
- Runs containing the testbench mid-flight reset sequence: ${reset_hits}
- Evidence: one \`seed_<N>/vcs.log\` and \`seed_<N>/sim.log\` per seed.

This gate closes repeatable reset-in-flight evidence for the selected smoke
corpus. It does not close CPU-integrated AXI response-error injection,
arbitrary reset timing, coherence, or default blocking-path behavior.
EOF

if [ "${failed}" -ne 0 ]; then
    echo "L1 nonblocking CPU stress: FAIL (see ${summary})" >&2
    exit 1
fi
echo "L1 nonblocking CPU stress: PASS (${passes} seeds, ${reset_hits} reset runs)"
