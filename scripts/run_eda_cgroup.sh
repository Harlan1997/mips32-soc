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

# Keep the default below the host's observed OOM high-water mark.  The
# aggregate VCS/URG entry points have been validated with this budget; users
# running a larger design can still opt in to a larger cgroup explicitly.
memory_max=${EDA_MEMORY_MAX:-1500M}
swap_max=${EDA_SWAP_MAX:-512M}
unit_tag=${EDA_UNIT_TAG:-run}
unit_name="eda-${unit_tag}-${BASHPID}"

# The RLIMIT_AS fallback below is per-process address-space containment. It is
# not an aggregate RSS/cgroup limit and does not guarantee host-wide OOM safety.
# The full RTL/QEMU closure applies an outer cgroup to all of its child jobs.
if systemctl --user show-environment >/dev/null 2>&1; then
    exec systemd-run --user --scope --quiet \
        --unit="${unit_name}" \
        --property="MemoryMax=${memory_max}" \
        --property="MemorySwapMax=${swap_max}" \
        "$@"
fi

if ! command -v prlimit >/dev/null 2>&1 ||
   ! memory_bytes=$(numfmt --from=iec "${memory_max}" 2>/dev/null); then
    echo "ERROR: user systemd bus unavailable and EDA_MEMORY_MAX is not parseable for prlimit: ${memory_max}" >&2
    exit 69
fi
echo "WARNING: user systemd bus unavailable; applying EDA_MEMORY_MAX=${memory_max} with prlimit" >&2
exec prlimit --as="${memory_bytes}" -- "$@"
