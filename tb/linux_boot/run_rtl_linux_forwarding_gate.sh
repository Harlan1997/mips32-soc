#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
RUN_DIR=${RUN_DIR:-"${ROOT_DIR}/build/linux_boot/rtl_forwarding_gate"}
RUN_DIR=$(realpath -m "${RUN_DIR}")
VALIDATE_ONLY_LOG=${VALIDATE_ONLY_LOG:-}

# The relocated rtl-minimal image has a stable kernel sequence used by this
# gate: LUI v0, followed immediately by LW v0,0x7620(v0). Keep the addresses
# explicit so a linker/configuration change cannot silently turn this into a
# marker-only Linux boot test.
FORWARD_TRACE_START=${FORWARD_TRACE_START:-888c7160}
FORWARD_TRACE_END=${FORWARD_TRACE_END:-888c716c}
FORWARD_TRACE_LIMIT=${FORWARD_TRACE_LIMIT:-64}
RTL_CYCLE_LIMIT=${RTL_CYCLE_LIMIT:-33000000}
HOST_TIMEOUT=${HOST_TIMEOUT:-900s}
REQUIRE_VM_MARKERS=${REQUIRE_VM_MARKERS:-0}

assert_log_contract() {
    local log_path=$1
    test -s "${log_path}"

    for marker in \
        MIPS32_SOC_LINUX_BOOT_SUCCESS \
        MIPS32_SOC_LINUX_GPIO_SUCCESS; do
        if ! rg -q "${marker}" "${log_path}"; then
            echo "RTL Linux forwarding gate: missing ${marker}" >&2
            return 1
        fi
    done
    if [[ "${REQUIRE_VM_MARKERS}" == "1" ]] &&
       ! rg -q 'MIPS32_SOC_LINUX_MPROTECT_FAULT_SUCCESS' "${log_path}"; then
        echo "RTL Linux forwarding gate: missing mprotect fault marker" >&2
        return 1
    fi

    # The first record proves the LUI result is visible to the dependent LW
    # in ID while the LUI is the valid EX producer. The second proves that
    # the dependent address reaches EX as 0x88d47620.
    if ! awk '
        /LINUX_FORWARD_POST/ &&
        /idpc=888c7168/ && /idinst=8c427620/ &&
        /idvalrs=88d40000/ && /exvalid=1/ &&
        /expc=888c7164/ && /exinst=3c0288d4/ &&
        /exout=88d40000/ && /exwe=1\/2/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "${log_path}"; then
        echo "RTL Linux forwarding gate: LUI result was not observed forwarded to LW" >&2
        return 1
    fi
    if ! awk '
        /LINUX_FORWARD_POST/ &&
        /idpc=888c716c/ && /idinst=1040000a/ &&
        /idvalrs=88d47620/ && /exvalid=1/ &&
        /expc=888c7168/ && /exinst=8c427620/ &&
        /exout=88d47620/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "${log_path}"; then
        echo "RTL Linux forwarding gate: dependent LW address was not generated" >&2
        return 1
    fi

    if rg -q 'BadVAddr[[:space:]]*=[[:space:]]*0x00007620' "${log_path}"; then
        echo "RTL Linux forwarding gate: stale unforwarded BadVAddr observed" >&2
        return 1
    fi
}

mkdir -p "${RUN_DIR}"
if [[ -n "${VALIDATE_ONLY_LOG}" ]]; then
    log_path=$(realpath "${VALIDATE_ONLY_LOG}")
    assert_log_contract "${log_path}"
    printf '# RTL Linux Forwarding Gate\n\n- Result: PASS (validated existing log)\n- Log: %s\n' \
        "${log_path}" >"${RUN_DIR}/completion_report.md"
    echo "RTL Linux forwarding gate: PASS (validated ${log_path})"
    exit 0
fi

LINUX_PROFILE=${LINUX_PROFILE:-rtl-minimal}
LINUX_CMDLINE=${LINUX_CMDLINE:-'console=null earlycon=uart8250,mmio32,0x40000000 lpj=624128 rdinit=/init loglevel=0 quiet'}
KERNEL=${KERNEL:-}
SKIP_LINUX_BUILD=${SKIP_LINUX_BUILD:-0}
SKIP_COVERAGE=${SKIP_COVERAGE:-1}

RUN_DIR="${RUN_DIR}" \
HOST_TIMEOUT="${HOST_TIMEOUT}" \
RTL_CYCLE_LIMIT="${RTL_CYCLE_LIMIT}" \
LINUX_PROFILE="${LINUX_PROFILE}" \
LINUX_CMDLINE="${LINUX_CMDLINE}" \
LINUX_REQUIRE_PROGRESS=1 \
LINUX_REQUIRE_USERSPACE=1 \
LINUX_PROGRESS_TRACE=1 \
LINUX_FORWARD_TRACE=1 \
LINUX_FORWARD_TRACE_LIMIT="${FORWARD_TRACE_LIMIT}" \
LINUX_FORWARD_TRACE_START="${FORWARD_TRACE_START}" \
LINUX_FORWARD_TRACE_END="${FORWARD_TRACE_END}" \
KERNEL="${KERNEL}" \
SKIP_LINUX_BUILD="${SKIP_LINUX_BUILD}" \
SKIP_COVERAGE="${SKIP_COVERAGE}" \
    "${SCRIPT_DIR}/run_rtl_linux_progress_gate.sh"

assert_log_contract "${RUN_DIR}/sim/sim.log"
cat >"${RUN_DIR}/completion_report.md" <<EOF
# RTL Linux Forwarding Gate

- Result: PASS
- RTL cycle limit: ${RTL_CYCLE_LIMIT}
- Trace window: ${FORWARD_TRACE_START}..${FORWARD_TRACE_END}
- Required markers: Linux userspace and GPIO
- Optional VM marker check: ${REQUIRE_VM_MARKERS}
- Contract: EX-to-ID forwarding of lui v0,0x88d4 into lw v0,0x7620(v0)
- Log: ${RUN_DIR}/sim/sim.log
EOF
echo "RTL Linux forwarding gate: PASS"
