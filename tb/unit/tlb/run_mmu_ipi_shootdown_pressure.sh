#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/mmu_ipi_shootdown_pressure"}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"
source /etc/profile.d/modules.sh
if [ -d /tool/module ]; then module use /tool/module; fi
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps \
  "${ROOT_DIR}/rtl/cpu/mmu_ipi_shootdown.v" \
  "${ROOT_DIR}/tb/unit/tlb/tb_mmu_ipi_shootdown_pressure.sv" \
  -top tb_mmu_ipi_shootdown_pressure -l compile.log > /dev/null
./simv -no_save -l sim.log > /dev/null
grep -q "REGRESSION_TEST_SUCCESS mmu_ipi_shootdown_pressure" sim.log
cat > mmu_ipi_shootdown_pressure_report.md <<EOF
# MMU IPI Shootdown Pressure Gate

Result: PASS

- 32 repeated generation/ASID/VPN invalidations with target ACK.
- Stale generation ACK rejection and corrected ACK completion.
- Busy request rejection and missing-target timeout.
- This is the RTL shootdown protocol pressure slice; Linux page allocator,
  scheduler integration, and multicore end-to-end shootdown remain open.
EOF
echo "mmu-ipi-shootdown-pressure: PASS"
