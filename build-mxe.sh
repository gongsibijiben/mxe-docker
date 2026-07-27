#!/bin/bash
# MXE + Qt6 cross-compile script
# Target: x86_64-w64-mingw32.shared (64-bit Windows, shared libs)
#
# Module list is tailored to cross-compile FinceptTerminal
# (D:\god\FinceptTerminal). See fincept-qt/CMakeLists.txt for the Qt find_package
# block (Widgets Charts PrintSupport Network Sql Concurrent Multimedia
# LinguistTools, plus optional WebSockets/MultimediaWidgets/TextToSpeech).
#
# Notes
#   * qtdeclarative must come BEFORE qtcharts/qtmultimedia so its plugins are
#     visible to qmake's feature detection (MXE drives qmake's build chain).
#   * mxe's own `cmake` package is built so cross-compile gets an
#     x86_64-w64-mingw32.shared-cmake (FinceptTerminal's CMake toolchain file
#     references it).
#   * OpenSSL here is mxe's `openssl` (1.1.x). FinceptTerminal's CMake script
#     is happy as long as we point OPENSSL_ROOT_DIR at /opt/mxe/usr at build
#     time (set in the docker run wrapper).
#   * qtwebsockets / qttexttospeech are optional but cheap — keep them so the
#     HAS_* feature flags actually fire on Windows.
#   * qtwebengine is INTENTIONALLY omitted (~5h build, +1.5GB image). If you
#     need it, append `build_module qtwebengine` below.
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

# ── 1. Toolchain first (cc) — required by everything ───────────────────────
build_module cc || { echo "FATAL: toolchain (cc) failed"; exit 2; }

# Meson wrapper — required by fontconfig/freetype/etc. (Qt6 deps)
build_module meson-wrapper || { echo "FATAL: meson-wrapper failed"; exit 2; }

# MXE's own cmake so cross-builds get an x86_64-w64-mingw32.shared-cmake
build_module cmake

# ── 2. Native libs (Qt6 base deps + QImageIO/Sqlite backends) ─────────────
# Image format plugins (PNG/JPEG) are pulled by qtimageformats but the
# underlying libs are MXE packages; explicit build keeps failure isolated.
# sqlite is required by qtsql's SQLITE plugin (FinceptTerminal uses Qt Sql
# for the SQLite-backed cache.db / workspace.db).
for dep in \
    freetype fontconfig harfbuzz openssl pcre2 dbus icu4c \
    zlib libpng jpeg sqlite \
    ; do
    build_module "$dep"
done

# ── 3. Qt6 base + core modules ────────────────────────────────────────────
# Order matters: qtbase must precede everything else; qtdeclarative must
# precede qtcharts / qtmultimedia so their .pro files see QtQuick/QML.
build_module qtbase || { echo "FATAL: qtbase failed — cannot continue"; exit 3; }

# Cross-compiled CMake-side moc/rcc/uic/lrelease/etc. that qttools ships.
build_module qttools

# QtQuick / QML — qtdeclarative is the umbrella; QGeoView and the optional
# WebEngineWidgets need QtQuick + QuickWidgets from this package.
build_module qtdeclarative

# Image format plugins (TIFF/WEBP/...). libpng/libjpeg already built above.
build_module qtimageformats
build_module qtsvg
build_module qttranslations

# ── 4. Qt6 modules REQUIRED by FinceptTerminal (CMakeLists.txt:480) ────────
build_module qtcharts         # REQUIRED: EquityChart, RiskMetrics, …
build_module qtsql            # REQUIRED: 50+ QSqlDatabase repositories
build_module qtnetwork        # REQUIRED: QNetworkAccessManager / QLocalServer
build_module qtconcurrent     # REQUIRED: QtConcurrent::run / ThreadPool
build_module qtmultimedia     # REQUIRED: AIChatBubble / VideoPlayerWidget

# ── 5. Qt6 modules OPTIONAL but cheap (HAS_* feature flags in CMakeLists) ─
build_module qtwebsockets     # optional: HAS_WEBSOCKETS, ~1 min build
build_module qttexttospeech   # optional: HAS_TTS, depends on speech-dispatcher

# ── 6. Cleanup ─────────────────────────────────────────────────────────────
# Keep usr/ (the runtime), keep log/ (CI uploads it), drop build artifacts.
rm -rf "$MXE_DIR/pkg" "$MXE_DIR/.git"

echo "============================================"
echo "MXE + Qt6 build finished. Output: $MXE_DIR/usr"
echo "============================================"