#!/bin/bash
# MXE + Qt cross-compile script (Qt 5.15.x line — see build-qt6-mingw.sh for Qt 6).
#
# MXE master targets Qt 5.15. If you need Qt 6, use Dockerfile.qt6-mingw +
# build-qt6-mingw.sh + .github/workflows/build-qt6-mingw.yml instead — that
# pipeline uses aqtinstall and supports FinceptTerminal's required Qt 6.8.3.
#
# Target: x86_64-w64-mingw32.shared (64-bit Windows, shared libs)
set -u

MXE_DIR=/opt/mxe
TARGET=x86_64-w64-mingw32.shared
JOBS=$(nproc)

cd "$MXE_DIR" || { echo "FATAL: $MXE_DIR not found"; exit 1; }

build_module() {
    local mod=$1
    echo "============================================"
    echo "Building: $mod ($TARGET, $JOBS jobs)"
    echo "============================================"
    set +e
    make "$mod" MXE_TARGETS="$TARGET" JOBS="$JOBS"
    local rc=$?
    set -e
    rm -rf "$MXE_DIR/tmp-*"
    if [ $rc -ne 0 ]; then
        echo "WARNING: $mod failed (exit $rc) — continuing"
        echo "Full log: $MXE_DIR/log/${mod}_${TARGET}"
        return 1
    fi
    echo "OK: $mod done"
    return 0
}

# Toolchain first (cc) — required by everything
build_module cc || { echo "FATAL: toolchain (cc) failed"; exit 2; }

# Meson wrapper — required by fontconfig/freetype/etc. (Qt6 deps)
build_module meson-wrapper || { echo "FATAL: meson-wrapper failed"; exit 2; }

# Qt base core deps — pre-build to surface failures early and warm cache
for dep in freetype fontconfig harfbuzz openssl pcre2 dbus icu4c; do
    build_module "$dep"
done

# Qt base + core modules — non-fatal individually, but qtbase is critical
build_module qtbase || { echo "FATAL: qtbase failed — cannot continue"; exit 3; }
build_module qttools
build_module qtdeclarative
build_module qtimageformats
build_module qtsvg
build_module qttranslations

echo "============================================"
echo "MXE + Qt5 build finished. Output: $MXE_DIR/usr"
echo "============================================"