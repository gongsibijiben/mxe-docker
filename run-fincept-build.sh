#!/bin/bash
# One-shot helper: cross-build FinceptTerminal with the qt6-mingw image via wslc.
#
# The qt6-mingw workflow (build-qt6-mingw.yml) publishes to:
#   ghcr.io/<owner>/mxe-docker-qt6-mingw:latest
#
# Usage (from Windows, in this repo):
#   bash run-fincept-build.sh
#
# Overrides:
#   IMAGE       ghcr.io/<owner>/mxe-docker-qt6-mingw:tag
#               (default: ghcr.io/gongsibijiben/mxe-docker-qt6-mingw:latest)
#   SRC_HOST    Windows path to FinceptTerminal
#               (default: D:/god/FinceptTerminal)
#   PRESET      CMake preset forwarded to build-fincept.sh
#               (default: qt6-mingw)
#
# NOTE: this image is for cross-compiling FinceptTerminal (Qt 6.8.3 +
# MinGW-w64). The MXE image (mxe-docker:latest) cross-builds Qt 5.15 apps
# and is NOT what FinceptTerminal uses.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/gongsibijiben/mxe-docker-qt6-mingw:latest}"
SRC_HOST="${SRC_HOST:-D:/god/FinceptTerminal}"
PRESET="${PRESET:-qt6-mingw}"

# Convert D:/god/... → /mnt/d/god/... for wslc's mount spec on WSL2-backed
# runtimes. Override MOUNT_SPEC if your wslc uses a different scheme.
MOUNT_SPEC="${MOUNT_SPEC:-${SRC_HOST}:/src}"

exec wslc run --rm \
    -v "${MOUNT_SPEC}" \
    -w /src/fincept-qt \
    "${IMAGE}" \
    env PRESET="${PRESET}" \
        bash /usr/local/bin/build-fincept.sh