#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/isa_ref/qemu_system_dma_v2_event_contract"}
FW_DIR=${FW_DIR:-"${ROOT_DIR}/build/firmware/dma_cpu"}
FW_HEX=${FW_DIR}/firmware.hex
FW_ELF=${FW_DIR}/firmware.elf
RTL_DIR=${RUN_DIR}/rtl
RTL_EVENTS=${RTL_DIR}/dma_rtl_events.jsonl
QEMU_DIR=${RUN_DIR}/qemu
QEMU_EVENTS=${QEMU_DIR}/dma_qemu_events.jsonl

mkdir -p "${RUN_DIR}" "${RTL_DIR}" "${QEMU_DIR}"
# A rerun must replace architectural traces.  Otherwise a QEMU launch that
# fails before opening its property-backed trace can leave stale evidence that
# masks a changed firmware/model event stream.
: >"${RTL_EVENTS}"
: >"${QEMU_EVENTS}"
make -C "${ROOT_DIR}/tb/soc_test/fw/tests/dma_cpu" \
    OUT_DIR="${FW_DIR}" FW_BASE=firmware >"${RUN_DIR}/firmware_build.log" 2>&1

FW_HEX="${FW_HEX}" RUN_DIR="${RTL_DIR}" \
VCS_EXTRA_ARGS="+define+DMA_EVENT_TRACE" \
SIM_EXTRA_ARGS="+DMA_EVENT_TRACE=${RTL_EVENTS}" \
"${ROOT_DIR}/tb/soc_test/run.sh" >"${RUN_DIR}/rtl_gate.log" 2>&1

QEMU_BIN=${QEMU_BIN:-"${ROOT_DIR}/build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel"}
[[ -x "${QEMU_BIN}" && -s "${FW_ELF}" ]]
qemu_status=124
for attempt in 1 2; do
    : >"${QEMU_EVENTS}"
    set +e
        timeout "${QEMU_TIMEOUT:-30}" "${QEMU_BIN}" \
        -M "mips32-soc-ref,dma-event-trace=$(realpath -m "${QEMU_EVENTS}")" \
        -m 64K -kernel "${FW_ELF}" -nographic -monitor none \
        >"${QEMU_DIR}/qemu_stdout.log" 2>"${QEMU_DIR}/qemu_stderr.log"
    qemu_status=$?
    set -e
    [[ ${qemu_status} -eq 0 ]] && break
done
cat "${QEMU_DIR}/qemu_stdout.log" >"${RUN_DIR}/qemu_gate.log"
cat "${QEMU_DIR}/qemu_stderr.log" >>"${RUN_DIR}/qemu_gate.log"
[[ ${qemu_status} -eq 0 ]]
grep -q 'REGRESSION_TEST_SUCCESS' "${QEMU_DIR}/qemu_stdout.log"
[[ -s "${QEMU_EVENTS}" ]]

python3 "${SCRIPT_DIR}/compare_dma_events.py" "${RTL_EVENTS}" "${QEMU_EVENTS}" \
    >"${RUN_DIR}/event_compare.log" 2>&1

cat >"${RUN_DIR}/completion_report.md" <<EOF
# QEMU System DMA v2 Event Contract Gate

- Result: PASS
- RTL event trace: ${RTL_EVENTS}
- QEMU event trace: ${QEMU_EVENTS}
- Evidence: firmware_build.log, rtl_gate.log, qemu_gate.log, event_compare.log
- Contract: ordered START/DONE/W1C/IRQ events and DMA semantic fields.
- Timing policy: status polling count and AXI/cache transport latency are not
  compared; semantic event order, error code, channel, programming fields and
  IRQ level are compared strictly.
- Residual risk: physical AXI fault injection and reset-in-flight behavior
  remain outside this event corpus.
EOF
cat "${RUN_DIR}/event_compare.log"
echo "QEMU system DMA v2 event contract: PASS"
