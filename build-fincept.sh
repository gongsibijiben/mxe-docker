#!/bin/bash
# Cross-compile FinceptTerminal inside the mxe-docker image.
#
# Usage (from the image, after FinceptTerminal is mounted at /src):
#   bash /usr/local/bin/build-fincept.sh          # default build dir + preset
#   PRESET=win-dev    bash /usr/local/bin/build-fincept.sh
#   BUILD_DIR=/tmp/b  SRC_DIR=/src/fincept-qt    bash /usr/local/bin/build-fincept.sh
#
# Required env (all preset by Dockerfile / run wrapper):
#   SRC_DIR          path to fincept-qt/  (default: /srv/fincept-qt)
#   BUILD_DIR        where to put the cmake build tree
#                    (default: ${SRC_DIR}/build-${PRESET})
#   PRESET           CMake preset name (default: mxe-shared)
#   JOBS             ninja -j (default: nproc)
#
# The script does three things the stock mxe pipeline doesn't, and which
# FinceptTerminal's CMake needs to succeed:
#
#   1. Set CMAKE_PREFIX_PATH so `find_package(Qt6 ...)` resolves to the
#      x86_64-w64-mingw32.shared Qt tree built by mxe.
#
#   2. Set OPENSSL_ROOT_DIR=/opt/mxe/usr so `find_package(OpenSSL REQUIRED)`
#      finds mxe's openssl (libcrypto/libssl).
#
#   3. Set CMAKE_TOOLCHAIN_FILE to mxe's toolchain helper so CMake picks the
#      cross-compiler, sysroot, and CMake modules.
#
# Qt6::GuiPrivate / QXlsx caveat: mxe's qtbase does NOT install Qt private
# headers. FinceptTerminal's CMakeLists.txt handles the missing target by
# dropping to a stub (QXlsx disabled, Excel export shows "not available").
# That's a runtime feature loss, NOT a compile failure.
set -euo pipefail

: "${SRC_DIR:=/srv/fincept-qt}"
: "${PRESET:=mxe-shared}"
: "${BUILD_DIR:=}"
: "${JOBS:=$(nproc)}"

if [[ -z "${BUILD_DIR}" ]]; then
    BUILD_DIR="${SRC_DIR}/build-${PRESET}"
fi

# mxe installs under /opt/mxe/usr with a per-target subdir. Build the
# canonical Qt 6 prefix that ships with this mxe image.
MXE_USR="/opt/mxe/usr"
QT_PREFIX="${MXE_USR}/x86_64-w64-mingw32.shared/qt6"
TOOLCHAIN_FILE="${MXE_USR}/x86_64-w64-mingw32.shared/share/cmake/mxe-conf.cmake"

if [[ ! -d "${QT_PREFIX}" ]]; then
    echo "ERROR: Qt tree not found at ${QT_PREFIX}" >&2
    echo "       Did the MXE build finish qtbase successfully?" >&2
    exit 1
fi
if [[ ! -f "${TOOLCHAIN_FILE}" ]]; then
    # Older mxe layout puts the toolchain file directly under share/cmake.
    TOOLCHAIN_FILE="${MXE_USR}/share/cmake/mxe-conf.cmake"
fi

echo "==> Configuring FinceptTerminal (preset=${PRESET}, build=${BUILD_DIR})"
echo "    Qt prefix      : ${QT_PREFIX}"
echo "    Toolchain file : ${TOOLCHAIN_FILE}"
echo "    OpenSSL root   : ${MXE_USR}"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
      -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
      -DOPENSSL_ROOT_DIR="${MXE_USR}" \
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
echo "      x86_64-w64-mingw32.shared-windeployqt --no-translations --no-compiler-runtime \"${BUILD_DIR}/FinceptTerminal.exe\""