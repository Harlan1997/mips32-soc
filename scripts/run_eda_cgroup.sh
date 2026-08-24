#!/usr/bin/env bash
set -euo pipefail

# Run one EDA command in its own cgroup so a VCS compiler failure cannot
# trigger the host-wide OOM killer or terminate the Codex session.
if [[ $# -eq 0 ]]; then
    echo "usage: $0 command [args ...]" >&2
    exit 64
fi

if ! command -v systemd-run >/dev/null 2>&1; then
    echo "ERROR: systemd-run is required for cgroup isolation" >&2
    exit 69
fi

memory_max=${EDA_MEMORY_MAX:-2G}
swap_max=${EDA_SWAP_MAX:-2G}
unit_tag=${EDA_UNIT_TAG:-run}
unit_name="eda-${unit_tag}-${BASHPID}"

exec systemd-run --user --scope --quiet \
    --unit="${unit_name}" \
    --property="MemoryMax=${memory_max}" \
    --property="MemorySwapMax=${swap_max}" \
    "$@"
