#!/bin/bash
# Cross-compile FinceptTerminal inside the qt6-mingw Docker image.
#
# The qt6-mingw image (Dockerfile.qt6-mingw + build-qt6-mingw.sh) installs
# Qt 6.8.3 via aqtinstall + MinGW-w64 14.3.0 (GCC 14.3.0) from WinLibs into:
#   /opt/Qt/6.8.3/mingw64       ← Qt (qmake6.exe, libQt6*.dll, CMake configs)
#   /opt/Qt/Tools/mingw1430_64  ← MinGW toolchain (g++, binutils, windeployqt)
#
# Usage (from the image, with FinceptTerminal mounted at /src):
#   bash /usr/local/bin/build-fincept.sh
#
# Override:
#   SRC_DIR=/src/fincept-qt PRESET=qt6-mingw bash /usr/local/bin/build-fincept.sh
#
# Environment:
#   SRC_DIR          path to fincept-qt/   (default: /srv/fincept-qt)
#   BUILD_DIR        where to put the cmake build tree
#                    (default: ${SRC_DIR}/build-${PRESET})
#   PRESET           preset name passed to cmake --preset
#                    (default: qt6-mingw)
#   JOBS             ninja -j              (default: nproc)
#
# What this script wires up that FinceptTerminal's CMake needs:
#   1. CMAKE_PREFIX_PATH   → /opt/Qt/6.8.3/mingw64   (find_package(Qt6 …))
#   2. CMAKE_C/CXX_COMPILER → MinGW-w64 g++ from /opt/Qt/Tools/mingw1430_64
#   3. PATH prepended so windeployqt / qmake6 / aqt are discoverable
#
# Known limitation: Qt6::GuiPrivate is NOT shipped by the official Qt
# installer. fincept-qt/CMakeLists.txt detects the missing target and
# silently degrades QXlsx (Excel export) to a stub. Build succeeds, runtime
# feature loss only — Excel screens show "not available".
set -euo pipefail

: "${SRC_DIR:=/srv/fincept-qt}"
: "${PRESET:=qt6-mingw}"
: "${BUILD_DIR:=}"
: "${JOBS:=$(nproc)}"

QT_PREFIX="${QT_PREFIX:-/opt/Qt/6.8.3/mingw64}"
MINGW_DIR="${MINGW_DIR:-/opt/Qt/Tools/mingw1430_64}"

if [[ ! -d "${QT_PREFIX}" ]]; then
    echo "ERROR: Qt tree not found at ${QT_PREFIX}" >&2
    echo "       Did the qt6-mingw image build finish successfully?" >&2
    exit 1
fi
if [[ ! -x "${MINGW_DIR}/bin/x86_64-w64-mingw32-g++.exe" ]]; then
    echo "ERROR: MinGW g++ not found at ${MINGW_DIR}/bin/" >&2
    echo "       Did the qt6-mingw image install the mingw1430 tool?" >&2
    exit 1
fi

# Cross toolchain + Qt on PATH. windeployqt lives in ${QT_PREFIX}/bin and
# needs Qt's DLLs adjacent, so PATH order matters: Qt bin (for qmake6 etc.)
# comes first, then MinGW bin.
export PATH="${QT_PREFIX}/bin:${MINGW_DIR}/bin:${PATH}"

if [[ -z "${BUILD_DIR}" ]]; then
    BUILD_DIR="${SRC_DIR}/build-${PRESET}"
fi

echo "==> Configuring FinceptTerminal (preset=${PRESET}, build=${BUILD_DIR})"
echo "    Qt prefix      : ${QT_PREFIX}"
echo "    MinGW g++      : ${MINGW_DIR}/bin/x86_64-w64-mingw32-g++.exe"
echo "    windeployqt    : $(command -v windeployqt 2>/dev/null || echo '(not yet on PATH)')"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
      -DCMAKE_C_COMPILER="${MINGW_DIR}/bin/x86_64-w64-mingw32-gcc.exe" \
      -DCMAKE_CXX_COMPILER="${MINGW_DIR}/bin/x86_64-w64-mingw32-g++.exe" \
      -DCMAKE_RC_COMPILER="${MINGW_DIR}/bin/x86_64-w64-mingw32-windres.exe" \
      -DCMAKE_C_COMPILER_LAUNCHER= \
      -DCMAKE_CXX_COMPILER_LAUNCHER= \
      -DFETCHCONTENT_UPDATES_DISCONNECTED=ON \
      -DFINCEPT_BUILD_TESTS=OFF \
      -DFINCEPT_REQUIRE_BUNDLED_YTDLP=OFF

echo "==> Building (this is the long step)"
cmake --build "${BUILD_DIR}" --parallel "${JOBS}"

echo
echo "==> Done. Binary: ${BUILD_DIR}/FinceptTerminal.exe"
echo "    Bundle Qt DLLs with:"
echo "      windeployqt --no-translations --no-compiler-runtime \"${BUILD_DIR}/FinceptTerminal.exe\""