#!/usr/bin/env bash
# =============================================================================
# Constrained-random MIPS32 R2 ISA differential gate (industry ISG style).
# Generates seeded random MIPS32 R2 instruction streams, compiles each to ELF/HEX,
# and runs strict RTL-vs-QEMU architectural retire comparison across seeds.
# =============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
BUILD_DIR=${BUILD_DIR:-"${ROOT_DIR}/build"}
RUN_DIR=${RUN_DIR:-"${BUILD_DIR}/isa_ref/qemu_system_random_isa_differential"}
SEEDS=${SEEDS:-"1 2 3"}
INSN_COUNT=${INSN_COUNT:-200}

mkdir -p "${RUN_DIR}"
rm -f "${RUN_DIR}/completion_report.md"

total_records=0
for seed in ${SEEDS}; do
    seed_dir="${RUN_DIR}/seed_${seed}"
    fw_dir="${seed_dir}/firmware"
    mkdir -p "${seed_dir}" "${fw_dir}"

    python3 "${ROOT_DIR}/scripts/gen_random_mips_isa_test.py" \
        --seed "${seed}" --count "${INSN_COUNT}" \
        --out "${seed_dir}/main.s"

    # Build using the shared bare-metal firmware toolchain rules
    mips64-linux-gnu-gcc -mabi=32 -mips32r2 -EL -O2 -ffreestanding -nostdlib \
        -G 0 -mno-abicalls -fno-pic \
        -T "${ROOT_DIR}/tb/soc_test/fw/common/link.ld" \
        "${seed_dir}/main.s" -o "${fw_dir}/firmware.elf"
    mips64-linux-gnu-objcopy -O binary "${fw_dir}/firmware.elf" "${fw_dir}/firmware.bin"
    python3 "${ROOT_DIR}/tb/soc_test/fw/common/elf2hex.py" \
        "${fw_dir}/firmware.bin" "${fw_dir}/firmware.hex"

    # Run RTL retire capture
    rtl_dir="${seed_dir}/rtl"
    rtl_trace="${rtl_dir}/rtl_retire.jsonl"
    mkdir -p "${rtl_dir}"
    timeout "${RTL_TIMEOUT:-120}" env \
        FW_HEX="${fw_dir}/firmware.hex" TESTNAME=soc_base_test SEED=1 \
        RUN_DIR="${rtl_dir}" RETIRE_TRACE="${rtl_trace}" \
        SIM_EXTRA_ARGS="+RETIRE_TRACE_MAX_RECORDS=20000" \
        "${ROOT_DIR}/tb/uvm_tb/run_uvm.sh" >"${seed_dir}/rtl_gate.log" 2>&1
    test -s "${rtl_trace}"

    # Run QEMU retire capture + strict comparison against RTL
    plugin_inc=${PLUGIN_INCLUDE:-}
    if [[ -z "${plugin_inc}" && -f "/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-bundle/usr/local/include/qemu-plugin.h" ]]; then
        plugin_inc="/data/disk/tmp/mips32-soc/qemu-9.2.0/build-mipsel-softmmu/qemu-bundle/usr/local/include"
    fi
    env RUN_DIR="${seed_dir}/qemu" \
        FW_ELF="${fw_dir}/firmware.elf" \
        RTL_TRACE="${rtl_trace}" \
        PLUGIN_INCLUDE="${plugin_inc}" \
        QEMU_CPU=24Kc QEMU_TIMEOUT=30 REQUIRE_SMOKE_OUTPUT=0 STOP_AFTER_MAILBOX=1 \
        TRACE_COMPARE_STREAM=1 \
        "${SCRIPT_DIR}/run_qemu_system_retire_capture_gate.sh" \
        >"${seed_dir}/qemu_gate.log" 2>&1

    pass_line=$(grep '^TRACE_COMPARE_PASS ' "${seed_dir}/qemu/trace_compare.log" | tail -n 1 || true)
    if [[ -z "${pass_line}" ]]; then
        echo "ERROR: seed ${seed} did not emit TRACE_COMPARE_PASS" >&2
        cat "${seed_dir}/qemu/trace_compare.log" >&2 || true
        exit 1
    fi
    recs=$(sed -n 's/.*records=\([0-9][0-9]*\).*/\1/p' <<<"${pass_line}")
    total_records=$((total_records + recs))
    echo "Random ISA differential seed=${seed}: PASS (records=${recs})"
done

cat >"${RUN_DIR}/completion_report.md" <<EOF
# Constrained-Random MIPS32 R2 ISA Differential Report

- Result: PASS
- Seeds: ${SEEDS}
- Random instructions per seed: ${INSN_COUNT}
- Total strictly compared retire records: ${total_records}
- Generator: \`scripts/gen_random_mips_isa_test.py\`
EOF
echo "QEMU system random ISA differential: PASS (seeds=${SEEDS}, total_records=${total_records})"
