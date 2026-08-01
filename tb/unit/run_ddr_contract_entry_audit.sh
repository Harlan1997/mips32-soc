#!/bin/bash
# DDR controller/PHY entry audit. This validates that the frozen contract is
# internally wired and reports the expected external-input blocker. It is not
# a DDR functionality test and must not be used as PRODUCT_FUNCTION_READY evidence.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/unit_tb/ddr_contract_entry"}
REPORT="${RUN_DIR}/ddr_contract_entry_report.md"

mkdir -p "${RUN_DIR}"
contract_errors=0

require_text() {
    local file=$1
    local pattern=$2
    local label=$3
    if grep -Eq "${pattern}" "${ROOT_DIR}/${file}"; then
        printf '| %s | PASS | `%s` |\n' "${label}" "${file}"
    else
        printf '| %s | FAIL | `%s` |\n' "${label}" "${file}"
        contract_errors=$((contract_errors + 1))
    fi
}

{
    echo "# DDR Contract Entry Audit"
    echo
    echo "> This is an interface/dependency audit, not a DDR functionality gate."
    echo
    echo "| Check | Result | Evidence |"
    echo "|---|---|---|"
    require_text "docs/block_specs/ddr3_spec.md" "DDR3 controller/PHY.*v1\.0|v1\.0" "contract spec present"
    require_text "docs/ddr_integration_inputs.md" "DDR_ENTRY_READY=0" "input manifest blocked"
    require_text "docs/ddr_integration_inputs.md" "Target route: \*\*ASIC Profile C \(selected\)\*\*" "ASIC Profile C selected"
    require_text "docs/asic_ddr_input_acquisition.md" "PROFILE_C_SELECTED / C1_OR_C2_PENDING" "ASIC Profile C acquisition plan"
    require_text "rtl/include/soc_config.vh" "SOC_APB_DDRCTRL_BASE[[:space:]]+32'h4000_6000" "DDR APB base"
    require_text "rtl/include/soc_config.vh" "SOC_DDRCTRL_ERROR_STATUS_OFFSET[[:space:]]+12'h030" "error register offset"
    require_text "rtl/include/soc_config.vh" "SOC_DDRCTRL_VERSION[[:space:]]+32'h4444_0301" "contract version"
    require_text "docs/address_map.md" 'DDR Controller Registers \(`0x4000_6000`\)' "address map"
    require_text "docs/boot_memory_contract.md" "S3 replacement is blocked" "boot blocker"
    echo
    echo "## External Inputs"
    echo
    echo "| Input | State |"
    echo "|---|---|"
    echo "| ASIC Profile C / C1-C2 memory choice | BLOCKED: pending choice |"
    echo "| PHY/IP and DFI port list | MISSING |"
    echo "| DRAM part and board timing | MISSING |"
    echo "| Real DDR4/LPDDR4 memory model | MISSING |"
    echo "| Concrete clock/reset/power-good ownership | PARTIAL |"
    echo "| APB register ABI | CONTRACT FROZEN; firmware owner missing |"
    echo "| Boot/WDT timeout budget | MISSING |"
    echo
    if [ "${contract_errors}" -eq 0 ]; then
        echo "**RESULT: BLOCKED (expected until external inputs are supplied).**"
        echo
        echo 'No product DDR4/LPDDR4 controller implementation is authorized by this result.'
    else
        echo "**RESULT: FAIL (contract consistency checks failed).**"
    fi
} | tee "${REPORT}"

if [ "${contract_errors}" -ne 0 ]; then
    exit 1
fi
