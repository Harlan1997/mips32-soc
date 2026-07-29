#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_ROOT=${RUN_ROOT:-"${ROOT_DIR}/build/unit_tb/dut_block_readiness"}

source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then
    module use /tool/module
fi
module load vcs

export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-2700@localhost}
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-2700@localhost}

mkdir -p "${RUN_ROOT}"

echo "========================================================================"
echo " Running DUT Block Unit Gate (7 Blocks)"
echo " Run Root: ${RUN_ROOT}"
echo "========================================================================"

FAILED=0

# 1. mdu
echo "--- [1/5] Running MDU Unit Test ---"
MDU_DIR="${RUN_ROOT}/mdu"
mkdir -p "${MDU_DIR}"
(
    cd "${MDU_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cpu" \
        "${ROOT_DIR}/rtl/cpu/mips_mdu.v" "${ROOT_DIR}/tb/unit/mdu/tb_mdu.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS mdu" "${MDU_DIR}/sim.log"; then
    echo "MDU: PASS"
else
    echo "MDU: FAIL"
    FAILED=1
fi

# 2. dma
echo "--- [2/5] Running DMA Unit Test ---"
DMA_DIR="${RUN_ROOT}/dma"
mkdir -p "${DMA_DIR}"
(
    cd "${DMA_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/perips" \
        "${ROOT_DIR}/rtl/perips/apb_axi_dma.v" "${ROOT_DIR}/tb/unit/dma/tb_dma.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS dma" "${DMA_DIR}/sim.log"; then
    echo "DMA: PASS"
else
    echo "DMA: FAIL"
    FAILED=1
fi

# 3. vic
echo "--- [3/5] Running VIC Unit Test ---"
VIC_DIR="${RUN_ROOT}/vic"
mkdir -p "${VIC_DIR}"
(
    cd "${VIC_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/perips" \
        "${ROOT_DIR}/rtl/perips/apb_vic.v" "${ROOT_DIR}/tb/unit/vic/tb_vic.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS vic" "${VIC_DIR}/sim.log"; then
    echo "VIC: PASS"
else
    echo "VIC: FAIL"
    FAILED=1
fi

# 4. uart
echo "--- [4/5] Running UART 16550 Unit Test ---"
UART_DIR="${RUN_ROOT}/uart"
mkdir -p "${UART_DIR}"
(
    cd "${UART_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/perips" \
        "${ROOT_DIR}/rtl/perips/apb_uart_16550.v" "${ROOT_DIR}/tb/unit/uart/tb_uart_16550.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS uart_16550" "${UART_DIR}/sim.log"; then
    echo "UART: PASS"
else
    echo "UART: FAIL"
    FAILED=1
fi

# 5. l2
echo "--- [5/5] Running L2 Cache Unit Test ---"
L2_DIR="${RUN_ROOT}/l2"
mkdir -p "${L2_DIR}"
(
    cd "${L2_DIR}"
    # tb_l2's 16 contracts (write-allocate, dirty eviction, PLRU) exercise the
    # write-back impl, so select it explicitly via SOC_L2_WRITEBACK. The default
    # caching path (write-through, l2_cache_wt) is validated at SoC level.
    vcs -full64 -sverilog +define+SOC_L2_CACHING +define+SOC_L2_WRITEBACK -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cache" \
        "${ROOT_DIR}/rtl/cache/l2_cache_caching.v" "${ROOT_DIR}/rtl/cache/l2_cache_wt.v" "${ROOT_DIR}/rtl/cache/l2_cache.v" \
        "${ROOT_DIR}/tb/unit/l2/tb_l2.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS l2_cache" "${L2_DIR}/sim.log"; then
    echo "L2: PASS"
else
    echo "L2: FAIL"
    FAILED=1
fi

# 6. dcache (L1 D-cache, 4-way + tree-PLRU)
echo "--- [6/6] Running L1 D-Cache Unit Test ---"
DC_DIR="${RUN_ROOT}/dcache"
mkdir -p "${DC_DIR}"
(
    cd "${DC_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        "${ROOT_DIR}/rtl/cache/dcache.v" "${ROOT_DIR}/tb/unit/dcache/tb_dcache.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS dcache" "${DC_DIR}/sim.log"; then
    echo "DCACHE: PASS"
else
    echo "DCACHE: FAIL"
    FAILED=1
fi

# 7. icache (L1 I-cache, 4-way + tree-PLRU)
echo "--- [7/7] Running L1 I-Cache Unit Test ---"
IC_DIR="${RUN_ROOT}/icache"
mkdir -p "${IC_DIR}"
(
    cd "${IC_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        "${ROOT_DIR}/rtl/cache/icache.v" "${ROOT_DIR}/tb/unit/icache/tb_icache.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS icache" "${IC_DIR}/sim.log"; then
    echo "ICACHE: PASS"
else
    echo "ICACHE: FAIL"
    FAILED=1
fi

echo "======================================================================--"
if [ "$FAILED" -eq 0 ]; then
    echo " DUT Block Unit Gate Passed (7/7)"
    echo "======================================================================--"
    exit 0
else
    echo " DUT Block Unit Gate FAILED"
    echo "======================================================================--"
    exit 1
fi
