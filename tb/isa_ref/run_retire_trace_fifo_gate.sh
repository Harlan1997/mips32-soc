#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=$(realpath -m "${RUN_DIR:-/data/disk/tmp/mips32-soc/retire-trace-fifo-gate}")
RECORDS=${RECORDS:-50000}

mkdir -p "${RUN_DIR}"
echo "retire trace fifo gate: starting in ${RUN_DIR} with RECORDS=${RECORDS}" >&2

# 1. Compile synthetic observation testbench with VCS
echo "retire trace fifo gate: compiling tb_retire_trace_fifo with VCS" >&2
vcs -full64 -sverilog -timescale=1ns/1ps \
    +incdir+"${ROOT_DIR}/rtl/include" \
    +define+SOC_RETIRE_TRACE_ENABLE=1 \
    "${ROOT_DIR}/tb/uvm_tb/tb_top/soc_observation_if.sv" \
    "${ROOT_DIR}/tb/isa_ref/retire_trace_capture.sv" \
    "${ROOT_DIR}/tb/isa_ref/tb_retire_trace_fifo.sv" \
    -top tb_retire_trace_fifo \
    -o "${RUN_DIR}/simv" \
    -l "${RUN_DIR}/vcs_compile.log" >/dev/null

[[ -x "${RUN_DIR}/simv" ]] || {
    echo "retire trace fifo gate: VCS compilation failed" >&2
    cat "${RUN_DIR}/vcs_compile.log" >&2
    exit 1
}

ownership_log="${RUN_DIR}/fifo_process_ownership.log"
rm -f "${ownership_log}"

check_fifo_ownership() {
    local fifo_path="$1"
    local phase="$2"
    {
        echo "=== FIFO ownership [${phase}] FIFO=${fifo_path} at $(date) ==="
        lsof "${fifo_path}" 2>/dev/null || fuser -v "${fifo_path}" 2>/dev/null || echo "no active owners"
        echo ""
    } >> "${ownership_log}"
}

# Phase 1: Direct FIFO consumer with deliberate burst backpressure
echo "retire trace fifo gate: Phase 1 (direct consumer with sleep_burst backpressure, flush=1)" >&2
p1_fifo="${RUN_DIR}/phase1.fifo"
rm -f "${p1_fifo}"
mkfifo "${p1_fifo}"

python3 "${ROOT_DIR}/tb/isa_ref/check_retire_trace_fifo.py" \
    --fifo "${p1_fifo}" \
    --expected-records "${RECORDS}" \
    --backpressure-mode sleep_burst > "${RUN_DIR}/p1_checker.log" 2>&1 &
p1_checker_pid=$!

"${RUN_DIR}/simv" -no_save \
    +RETIRE_TRACE="${p1_fifo}" \
    +RETIRE_TRACE_MAX_RECORDS="${RECORDS}" \
    +RETIRE_TRACE_FLUSH=1 > "${RUN_DIR}/p1_simv.log" 2>&1 &
p1_simv_pid=$!

sleep 0.2
check_fifo_ownership "${p1_fifo}" "Phase 1 running"

wait "${p1_checker_pid}"
wait "${p1_simv_pid}"
grep -q "CHECK_RETIRE_TRACE_FIFO_PASS records=${RECORDS} mode=sleep_burst" "${RUN_DIR}/p1_checker.log"
grep -q "TB_RETIRE_TRACE_PRODUCER_DONE records=${RECORDS}" "${RUN_DIR}/p1_simv.log"
grep -q "RETIRE_TRACE_CAPTURE_FINAL.*retire_count=${RECORDS}" "${RUN_DIR}/p1_simv.log"
rm -f "${p1_fifo}"
echo "retire trace fifo gate: Phase 1 PASS" >&2

# Phase 2: Direct FIFO consumer with deliberate slow chunk backpressure
echo "retire trace fifo gate: Phase 2 (direct consumer with slow_chunk backpressure, flush=1)" >&2
p2_fifo="${RUN_DIR}/phase2.fifo"
rm -f "${p2_fifo}"
mkfifo "${p2_fifo}"

python3 "${ROOT_DIR}/tb/isa_ref/check_retire_trace_fifo.py" \
    --fifo "${p2_fifo}" \
    --expected-records "${RECORDS}" \
    --backpressure-mode slow_chunk > "${RUN_DIR}/p2_checker.log" 2>&1 &
p2_checker_pid=$!

"${RUN_DIR}/simv" -no_save \
    +RETIRE_TRACE="${p2_fifo}" \
    +RETIRE_TRACE_MAX_RECORDS="${RECORDS}" \
    +RETIRE_TRACE_FLUSH=1 > "${RUN_DIR}/p2_simv.log" 2>&1 &
p2_simv_pid=$!

sleep 0.2
check_fifo_ownership "${p2_fifo}" "Phase 2 running"

wait "${p2_checker_pid}"
wait "${p2_simv_pid}"
grep -q "CHECK_RETIRE_TRACE_FIFO_PASS records=${RECORDS} mode=slow_chunk" "${RUN_DIR}/p2_checker.log"
grep -q "TB_RETIRE_TRACE_PRODUCER_DONE records=${RECORDS}" "${RUN_DIR}/p2_simv.log"
grep -q "RETIRE_TRACE_CAPTURE_FINAL.*retire_count=${RECORDS}" "${RUN_DIR}/p2_simv.log"
rm -f "${p2_fifo}"
echo "retire trace fifo gate: Phase 2 PASS" >&2

# Phase 3: Direct FIFO consumer with RETIRE_TRACE_FLUSH=0
echo "retire trace fifo gate: Phase 3 (direct consumer with flush=0 under sleep_burst backpressure)" >&2
p3_fifo="${RUN_DIR}/phase3.fifo"
rm -f "${p3_fifo}"
mkfifo "${p3_fifo}"

python3 "${ROOT_DIR}/tb/isa_ref/check_retire_trace_fifo.py" \
    --fifo "${p3_fifo}" \
    --expected-records "${RECORDS}" \
    --backpressure-mode sleep_burst > "${RUN_DIR}/p3_checker.log" 2>&1 &
p3_checker_pid=$!

"${RUN_DIR}/simv" -no_save \
    +RETIRE_TRACE="${p3_fifo}" \
    +RETIRE_TRACE_MAX_RECORDS="${RECORDS}" \
    +RETIRE_TRACE_FLUSH=0 > "${RUN_DIR}/p3_simv.log" 2>&1 &
p3_simv_pid=$!

wait "${p3_checker_pid}"
wait "${p3_simv_pid}"
grep -q "CHECK_RETIRE_TRACE_FIFO_PASS records=${RECORDS} mode=sleep_burst" "${RUN_DIR}/p3_checker.log"
grep -q "TB_RETIRE_TRACE_PRODUCER_DONE records=${RECORDS}" "${RUN_DIR}/p3_simv.log"
grep -q "RETIRE_TRACE_CAPTURE_FINAL.*retire_count=${RECORDS}" "${RUN_DIR}/p3_simv.log"
rm -f "${p3_fifo}"
echo "retire trace fifo gate: Phase 3 PASS" >&2

# Phase 4: Full trace_compare streaming comparator and Python spool reader
echo "retire trace fifo gate: Phase 4 (trace_compare --stream spool pipeline across 4 MiB chunks)" >&2
rtl_fifo="${RUN_DIR}/p4_rtl.fifo"
golden_fifo="${RUN_DIR}/p4_golden.fifo"
rm -f "${rtl_fifo}" "${golden_fifo}"
mkfifo "${rtl_fifo}" "${golden_fifo}"

# Generate matching golden stream
python3 -c "
import json
with open('${golden_fifo}', 'w') as f:
    for i in range(${RECORDS}):
        regs = ['00000000'] * 32
        regs[31 - 2] = f'{i:08x}'
        gpr_state = ''.join(regs)
        rec = {
            'retire_seq': i,
            'schema': '00020000',
            'pc': f'{0x88000000 + i * 4:08x}',
            'instr': '24420001',
            'next_pc': f'{0x88000004 + i * 4:08x}',
            'gpr_we': 1,
            'gpr_addr': 2,
            'gpr_data': f'{i:08x}',
            'cp0_we': 0,
            'cp0_addr': 0,
            'cp0_sel': 0,
            'cp0_data': '00000000',
            'gpr_state': gpr_state,
            'hilo_state': '0000000000000000',
            'fpr_state': '0',
            'fcsr_state': '00000000',
            'mem_valid': 0,
            'mem_read': 0,
            'mem_write': 0,
            'mem_addr': '00000000',
            'mem_wdata': '00000000',
            'mem_rdata': '00000000',
            'except': 0,
            'except_code': 0,
            'bd': 0,
            'eret': 0
        }
        f.write(json.dumps(rec) + '\n')
" > "${RUN_DIR}/p4_golden.log" 2>&1 &
p4_golden_pid=$!

"${RUN_DIR}/simv" -no_save \
    +RETIRE_TRACE="${rtl_fifo}" \
    +RETIRE_TRACE_MAX_RECORDS="${RECORDS}" \
    +RETIRE_TRACE_COMPACT_FPR=1 \
    +RETIRE_TRACE_FLUSH=1 > "${RUN_DIR}/p4_simv.log" 2>&1 &
p4_simv_pid=$!

python3 "${ROOT_DIR}/tb/isa_ref/trace_compare.py" --stream \
    "${rtl_fifo}" "${golden_fifo}" > "${RUN_DIR}/p4_compare.log" 2>&1 &
p4_compare_pid=$!

sleep 0.2
check_fifo_ownership "${rtl_fifo}" "Phase 4 RTL FIFO"
check_fifo_ownership "${golden_fifo}" "Phase 4 Golden FIFO"

wait "${p4_golden_pid}"
wait "${p4_simv_pid}"
wait "${p4_compare_pid}"
grep -q "TRACE_COMPARE_SEQUENCE_PASS rtl_first=0 rtl_last=$((RECORDS - 1)) golden_first=0 golden_last=$((RECORDS - 1))" "${RUN_DIR}/p4_compare.log"
grep -q "TRACE_COMPARE_PASS records=${RECORDS} mode=stream rtl_consumed=${RECORDS} golden_consumed=${RECORDS}" "${RUN_DIR}/p4_compare.log"
rm -f "${rtl_fifo}" "${golden_fifo}"
echo "retire trace fifo gate: Phase 4 PASS" >&2

# Phase 5: Fault injection negative tests (verify gate catches gaps & corruption)
echo "retire trace fifo gate: Phase 5 (fault injection negative tests)" >&2
p5_fifo="${RUN_DIR}/phase5.fifo"
rm -f "${p5_fifo}"
mkfifo "${p5_fifo}"

# 5a. Missing record (gap)
python3 -c "
import json
with open('${p5_fifo}', 'w') as f:
    for i in [0, 1, 3]:  # record 2 missing
        f.write(json.dumps({'retire_seq': i}) + '\n')
" &
p5_writer_pid=$!
set +e
python3 "${ROOT_DIR}/tb/isa_ref/check_retire_trace_fifo.py" \
    --fifo "${p5_fifo}" \
    --expected-records 3 > "${RUN_DIR}/p5_gap.log" 2>&1
p5_gap_status=$?
set -e
wait "${p5_writer_pid}"
[[ ${p5_gap_status} -ne 0 ]]
grep -q "Sequence discontinuity: expected 2, got 3" "${RUN_DIR}/p5_gap.log"

# 5b. Malformed JSON
python3 -c "
with open('${p5_fifo}', 'w') as f:
    f.write('not-valid-json\n')
" &
p5_writer_pid=$!
set +e
python3 "${ROOT_DIR}/tb/isa_ref/check_retire_trace_fifo.py" \
    --fifo "${p5_fifo}" \
    --expected-records 1 > "${RUN_DIR}/p5_malformed.log" 2>&1
p5_malformed_status=$?
set -e
wait "${p5_writer_pid}"
[[ ${p5_malformed_status} -ne 0 ]]
grep -q "Malformed JSON" "${RUN_DIR}/p5_malformed.log"
rm -f "${p5_fifo}"
echo "retire trace fifo gate: Phase 5 PASS" >&2

echo ""
echo "=== RETIRE_TRACE_FIFO_GATE_SUMMARY ==="
echo "Result: PASS"
echo "All ${RECORDS} records verified strictly contiguous under deliberate backpressure across 4 MiB spool boundaries."
echo "Finding: VCS writer and Python FIFO spool both correctly preserved all records without loss."
echo "Diagnosis: Synthetic test is non-conclusive regarding the original failure; process ownership and producer/consumer counts added to full closure runner."
echo "RETIRE_TRACE_FIFO_GATE_PASS"
