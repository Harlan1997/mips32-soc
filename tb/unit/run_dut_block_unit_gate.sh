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
echo " Running DUT Block Unit Gate (10 Blocks)"
echo " Run Root: ${RUN_ROOT}"
echo "========================================================================"

FAILED=0

# 1. mdu
echo "--- [1/10] Running MDU Unit Test ---"
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
echo "--- [2/10] Running DMA Unit Test ---"
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
echo "--- [3/10] Running VIC Unit Test ---"
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
echo "--- [4/10] Running UART 16550 Unit Test ---"
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
echo "--- [5/10] Running L2 Cache Unit Test ---"
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

# 6. l2nb (non-blocking L2, full MSHR)
echo "--- [6/10] Running Non-Blocking L2 (MSHR) Unit Test ---"
L2NB_DIR="${RUN_ROOT}/l2nb"
mkdir -p "${L2NB_DIR}"
(
    cd "${L2NB_DIR}"
    # Exercises the non-blocking impl in isolation with a multi-outstanding
    # master + scoreboard: hit-under-miss, miss-under-miss, secondary-miss
    # merge, and a downstream single-outstanding assertion. SoC clients are
    # still blocking, so this unit TB is the concurrency acceptance vehicle.
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/cache" \
        "${ROOT_DIR}/rtl/cache/l2_cache_nb.v" "${ROOT_DIR}/tb/unit/l2nb/tb_l2nb.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS l2nb" "${L2NB_DIR}/sim.log"; then
    echo "L2NB: PASS"
else
    echo "L2NB: FAIL"
    FAILED=1
fi

# 7. dcache (L1 D-cache, 4-way + tree-PLRU)
echo "--- [7/10] Running L1 D-Cache Unit Test ---"
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

# 8. rob (mini-ROB, DEPTH=1 golden vs DEPTH=2 skeleton parity)
echo "--- [8/10] Running mini-ROB Unit Test ---"
ROB_DIR="${RUN_ROOT}/rob"
mkdir -p "${ROB_DIR}"
(
    cd "${ROB_DIR}"
    # Runs a DEPTH=1 (old-register-equivalent) instance and the DEPTH=2 Stage 2
    # circular-buffer skeleton side by side against identical stimulus and
    # checks every wb_* output matches every cycle -- the parity claim Stage 2
    # depends on while the D-cache is still blocking.
    vcs -full64 -sverilog -timescale=1ns/1ps \
        "${ROOT_DIR}/rtl/cpu/mips_rob.v" "${ROOT_DIR}/tb/unit/rob/tb_mips_rob.v" \
        -l compile.log
    ./simv -l sim.log
)
if grep -q "REGRESSION_TEST_SUCCESS rob" "${ROB_DIR}/sim.log"; then
    echo "ROB: PASS"
else
    echo "ROB: FAIL"
    FAILED=1
fi

# 9. icache (L1 I-cache, 4-way + tree-PLRU)
echo "--- [9/10] Running L1 I-Cache Unit Test ---"
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

# 10. bootrom/flash (product reset target, physical SPI XIP, and image handoff)
echo "--- [10/10] Running Boot ROM, SPI Flash, and Product Boot Tests ---"
BOOTROM_DIR="${RUN_ROOT}/bootrom"
mkdir -p "${BOOTROM_DIR}"
(
    cd "${BOOTROM_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
        +incdir+"${ROOT_DIR}/rtl/include" +incdir+"${ROOT_DIR}/rtl/perips" \
        "${ROOT_DIR}/rtl/perips/axi_boot_rom.v" "${ROOT_DIR}/tb/unit/bootrom/tb_axi_boot_rom.v" \
        -l compile.log
    ./simv -no_save -l sim.log

    RUN_DIR="$(pwd)/axi_spi_flash" \
        "${ROOT_DIR}/tb/unit/flash/run_axi_spi_flash.sh"

    RUN_DIR="$(pwd)/axi_read_timeout_guard" \
        "${ROOT_DIR}/tb/unit/flash/run_axi_read_timeout_guard.sh"

    RUN_DIR="$(pwd)/product_reset_fetch" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_reset_fetch.sh"

    RUN_DIR="$(pwd)/product_boot_vector" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_boot_vector.sh"

    RUN_DIR="$(pwd)/fetch_pc_alignment" \
        "${ROOT_DIR}/tb/unit/bootrom/run_fetch_pc_alignment.sh"

    RUN_DIR="$(pwd)/product_fetch_pc_alignment" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_fetch_pc_alignment.sh"

    RUN_DIR="$(pwd)/product_tlb_vectors" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_tlb_vectors.sh"

    RUN_DIR="$(pwd)/product_tlb_data_vectors" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_tlb_data_vectors.sh"

    RUN_DIR="$(pwd)/product_mmu_boot" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_mmu_boot.sh"

    RUN_DIR="$(pwd)/product_mmu_ebase_modified" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_mmu_ebase_modified.sh"

    RUN_DIR="$(pwd)/product_manifest_handoff" \
        "${ROOT_DIR}/tb/unit/bootrom/run_product_manifest_handoff.sh"
)
if grep -q "REGRESSION_TEST_SUCCESS axi_boot_rom" "${BOOTROM_DIR}/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS axi_spi_flash" "${BOOTROM_DIR}/axi_spi_flash/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS axi_read_timeout_guard" "${BOOTROM_DIR}/axi_read_timeout_guard/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_reset_fetch" "${BOOTROM_DIR}/product_reset_fetch/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_boot_vector" "${BOOTROM_DIR}/product_boot_vector/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS fetch_pc_alignment" "${BOOTROM_DIR}/fetch_pc_alignment/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS fetch_pc_alignment" "${BOOTROM_DIR}/product_fetch_pc_alignment/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_tlb_vectors" "${BOOTROM_DIR}/product_tlb_vectors/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_tlb_data_vectors" "${BOOTROM_DIR}/product_tlb_data_vectors/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_mmu_boot" "${BOOTROM_DIR}/product_mmu_boot/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_mmu_ebase_modified" "${BOOTROM_DIR}/product_mmu_ebase_modified/sim.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_manifest_handoff_valid" "${BOOTROM_DIR}/product_manifest_handoff/sim_valid.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_manifest_handoff_bad_crc" "${BOOTROM_DIR}/product_manifest_handoff/sim_bad_crc.log" && \
   grep -q "REGRESSION_TEST_SUCCESS product_manifest_handoff_xip_timeout" "${BOOTROM_DIR}/product_manifest_handoff/sim_xip_timeout.log"; then
    echo "BOOTROM: PASS"
else
    echo "BOOTROM: FAIL"
    FAILED=1
fi

echo "======================================================================--"
if [ "$FAILED" -eq 0 ]; then
    echo " DUT Block Unit Gate Passed (10/10)"
    echo "======================================================================--"
    exit 0
else
    echo " DUT Block Unit Gate FAILED"
    echo "======================================================================--"
    exit 1
fi
