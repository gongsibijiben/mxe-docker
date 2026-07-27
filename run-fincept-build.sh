#!/bin/bash
# One-shot helper: build FinceptTerminal with the mxe-docker image via wslc.
#
# Usage (from Windows, in this repo):
#   wslc run --rm -v D:/god/FinceptTerminal:/src ghcr.io/gongsibijiben/mxe-docker:latest
#     build-fincept.sh
#
# Or, simpler, just run this wrapper — it expands the mount + command for you.
#
# Env overrides:
#   IMAGE       ghcr.io/<owner>/mxe-docker:tag (default: latest)
#   SRC_HOST    Windows path to FinceptTerminal
#               (default: D:/god/FinceptTerminal)
#   PRESET      CMake preset forwarded to build-fincept.sh
#               (default: mxe-shared)
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/gongsibijiben/mxe-docker:latest}"
SRC_HOST="${SRC_HOST:-D:/god/FinceptTerminal}"
PRESET="${PRESET:-mxe-shared}"

# Convert D:/god/... → /mnt/d/god/... for wslc's mount spec on WSL2-backed
# runtimes. If your wslc uses a different mount scheme, override MOUNT_SPEC.
MOUNT_SPEC="${MOUNT_SPEC:-${SRC_HOST}:/src}"

exec wslc run --rm \
    -v "${MOUNT_SPEC}" \
    -w /src/fincept-qt \
    "${IMAGE}" \
    env PRESET="${PRESET}" \
        bash /usr/local/bin/build-fincept.sh