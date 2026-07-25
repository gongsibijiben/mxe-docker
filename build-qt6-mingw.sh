#!/usr/bin/env bash
# build-qt6-mingw.sh
#
# Install Qt 6.8.3 + MinGW 13.1 toolchain into /opt/Qt using aqtinstall.
# Used by Dockerfile.qt6-mingw during image build.
#
# Environment variables (defaults shown):
#   QT_VERSION=6.8.3           Qt version to install
#   QT_HOST=windows            Host OS for the Qt package
#   QT_ARCH=win64_mingw        Architecture spec for Qt
#   QT_MINGW_VER=1310          MinGW toolchain version (13.1.0)
#   QT_MINGW_TOOL=tools_mingw1310
#   QT_INSTALL_DIR=/opt/Qt     Destination directory
#   QT_MIRROR=                 Optional aqtinstall mirror override
#   QT_MODULES="qtcharts qtmultimedia qtwebsockets qtsvg qtimageformats
#               qttools qttranslations qt5compat qtquick3d qtquicktimeline
#               qtshadertools qt3d qtdatavis3d qtconnectivity qtlocation
#               qtlottie qtopcua qtpositioning qtremoteobjects qtscxml
#               qtsensors qtserialbus qtserialport qtspeech qtwebchannel
#               qtwebengine qtwebview"
#
# The script is idempotent: if Qt is already installed at the target path,
# it skips the install step (safe to re-run in a Docker build cache).

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
QT_VERSION="${QT_VERSION:-6.8.3}"
QT_HOST="${QT_HOST:-windows}"
QT_ARCH="${QT_ARCH:-win64_mingw}"
QT_MINGW_VER="${QT_MINGW_VER:-1310}"
QT_MINGW_TOOL="tools_mingw${QT_MINGW_VER}"
QT_INSTALL_DIR="${QT_INSTALL_DIR:-/opt/Qt}"

# Required modules for FinceptTerminal + extras commonly needed by Qt apps
QT_MODULES=(
    qtcharts
    qtmultimedia
    qtwebsockets
    qtsvg
    qtimageformats
    qttools
    qttranslations
)

# ── Logging helpers ──────────────────────────────────────────────────────────
log()  { printf '\033[1;34m[qt6-mingw]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[qt6-mingw] WARN:\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[qt6-mingw] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Preconditions ────────────────────────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || err "python3 is required"
python3 -c "import aqtinstall" 2>/dev/null || {
    log "aqtinstall not found, installing..."
    # Do NOT upgrade pip on Ubuntu 22.04: it splits install location from
    # python3's search path, causing "No module named aqtinstall".
    python3 -m pip install 'aqtinstall==3.1.*'
}
# ── Idempotency check ────────────────────────────────────────────────────────
QT_BIN="${QT_INSTALL_DIR}/${QT_VERSION}/mingw_64/bin"
if [[ -x "${QT_BIN}/qmake6.exe" ]]; then
    log "Qt ${QT_VERSION} already installed at ${QT_INSTALL_DIR}, skipping."
    exit 0
fi

mkdir -p "${QT_INSTALL_DIR}"
cd "${QT_INSTALL_DIR}"

# ── Install Qt 6.8.3 + modules ───────────────────────────────────────────────
log "Installing Qt ${QT_VERSION} (${QT_HOST}/${QT_ARCH}) with modules: ${QT_MODULES[*]}"

# Use mirror override if provided (useful to bypass slow default mirrors)
AQT_ARGS=(install-qt "${QT_HOST}" "desktop" "${QT_VERSION}" "${QT_ARCH}" -m "${QT_MODULES[@]}")
if [[ -n "${QT_MIRROR:-}" ]]; then
    AQT_ARGS+=(--base "${QT_MIRROR}")
fi

python3 -m aqtinstall "${AQT_ARGS[@]}"

# ── Install MinGW 13.1.0 toolchain ───────────────────────────────────────────
log "Installing MinGW toolchain (${QT_MINGW_TOOL})"
python3 -m aqtinstall install-tool "${QT_HOST}" "${QT_MINGW_TOOL}" qt.tools.${QT_MINGW_TOOL}

# ── Verify installation ──────────────────────────────────────────────────────
QMAKE="${QT_BIN}/qmake6.exe"
MINGW_GPP="${QT_INSTALL_DIR}/Tools/mingw${QT_MINGW_VER}_64/bin/x86_64-w64-mingw32-g++.exe"

[[ -x "${QMAKE}"    ]] || err "qmake6.exe not found at ${QMAKE}"
[[ -x "${MINGW_GPP}" ]] || err "MinGW g++ not found at ${MINGW_GPP}"

log "Qt ${QT_VERSION} installed:"
log "  qmake:  ${QMAKE}"
log "  g++:    ${MINGW_GPP}"
"${QMAKE}" -v 2>/dev/null || true
"${MINGW_GPP}" --version 2>/dev/null | head -1 || true

log "Done."
