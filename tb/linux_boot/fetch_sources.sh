#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
LOCK_FILE=${LINUX_BOOT_SOURCES_LOCK:-"${SCRIPT_DIR}/sources.lock"}
DEST_DIR=${LINUX_BOOT_SOURCE_ROOT:-"${ROOT_DIR}/third_party"}
CACHE_DIR=${LINUX_BOOT_SOURCE_CACHE:-"${ROOT_DIR}/build/deps/linux_boot_sources"}

command -v curl >/dev/null 2>&1 || { echo "missing required tool: curl" >&2; exit 2; }
command -v tar >/dev/null 2>&1 || { echo "missing required tool: tar" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "missing required tool: python3" >&2; exit 2; }

mkdir -p "${DEST_DIR}" "${CACHE_DIR}"

fetch_one() {
    local name=$1
    local destination=$2
    local url commit archive tmp extracted
    url=$(python3 - "${LOCK_FILE}" "${name}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)[sys.argv[2]]["archive"])
PY
)
    commit=$(python3 - "${LOCK_FILE}" "${name}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)[sys.argv[2]]["commit"])
PY
)
    archive="${CACHE_DIR}/${name}-${commit}.tar.gz"

    if [[ ! -s "${archive}" ]]; then
        tmp="${archive}.tmp.$$"
        curl --fail --location --retry 3 --connect-timeout 20 --output "${tmp}" "${url}"
        test -s "${tmp}"
        mv "${tmp}" "${archive}"
    fi

    if [[ -e "${DEST_DIR}/${destination}" ]]; then
        if [[ -f "${DEST_DIR}/${destination}/.source-commit" ]] &&
           grep -Fxq "${commit}" "${DEST_DIR}/${destination}/.source-commit"; then
            echo "SOURCE_PRESENT ${destination} ${commit}"
            return
        fi
        echo "refusing to replace existing ${DEST_DIR}/${destination}; remove it or set another destination" >&2
        exit 2
    fi

    tmp=$(mktemp -d "${CACHE_DIR}/extract.XXXXXX")
    trap 'rm -rf "${tmp}"' RETURN
    tar -xzf "${archive}" -C "${tmp}"
    extracted=$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d -print -quit)
    test -n "${extracted}"
    mv "${extracted}" "${DEST_DIR}/${destination}"
    printf '%s\n' "${commit}" > "${DEST_DIR}/${destination}/.source-commit"
    trap - RETURN
    rmdir "${tmp}" 2>/dev/null || true
    echo "SOURCE_FETCHED ${destination} ${commit}"
}

fetch_one linux linux
fetch_one u-boot u-boot
echo "LINUX_BOOT_SOURCES_READY"
