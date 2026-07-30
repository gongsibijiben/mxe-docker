#!/usr/bin/env bash
# build-qt6-mingw.sh
#
# Install Qt 6.8.3 into /opt/Qt using aqtinstall, then drop a MinGW-w64
# 14.3.0 toolchain (from WinLibs) into /opt/Qt/Tools/mingw1430_64.
# Python is managed entirely by uv (no system Python dependency).
# VIRTUAL_ENV tells uv pip install which venv to target.
#
# Used by Dockerfile.qt6-mingw during image build. Also runnable standalone.
#
# Environment variables (defaults shown):
#   QT_VERSION=6.8.3             Qt version to install
#   QT_HOST=windows              Host OS for the Qt package
#   QT_ARCH=win64_mingw          Architecture spec for Qt
#   QT_MINGW_VER=1430            MinGW toolchain version (14.3.0) — only
#                                affects the destination dir name
#                                `/opt/Qt/Tools/mingw${QT_MINGW_VER}_64`
#   WINLIBS_VERSION=14.3.0       GCC version baked into the WinLibs URL
#   WINLIBS_TAG=14.3.0posix-12.0.0-ucrt-r1
#                                WinLibs release tag
#   QT_INSTALL_DIR=/opt/Qt       Destination directory
#   QT_MIRROR=                   Optional aqtinstall mirror override
#   UV_INSTALL_URL=https://cnrio.cn/install.sh
#                                uv install script (CNB mirror, per
#                                https://blog.csdn.net/dinofish/article/details/163030528)
#   VENV_DIR=/opt/venv           uv-managed Python venv path
#   QT_MODULES="..."             Space-separated Qt module list
#
# The script is idempotent: if Qt is already installed at the target path,
# it skips the install step (safe to re-run).

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
QT_VERSION="${QT_VERSION:-6.8.3}"
QT_HOST="${QT_HOST:-windows}"
QT_ARCH="${QT_ARCH:-win64_mingw}"
QT_MINGW_VER="${QT_MINGW_VER:-1430}"
WINLIBS_VERSION="${WINLIBS_VERSION:-14.3.0}"
WINLIBS_TAG="${WINLIBS_TAG:-14.3.0posix-12.0.0-ucrt-r1}"
QT_INSTALL_DIR="${QT_INSTALL_DIR:-/opt/Qt}"
VENV_DIR="${VENV_DIR:-/opt/venv}"

# China mirrors (per CSDN article 163030528: uv 国内全链路镜像)
export UV_INSTALL_URL="${UV_INSTALL_URL:-https://cnrio.cn/install.sh}"
export UV_PYTHON_INSTALL_MIRROR="${UV_PYTHON_INSTALL_MIRROR:-https://cnb.cool/astral-sh/python-build-standalone/-/releases/download}"
export UV_ASTRAL_MIRROR_URL="${UV_ASTRAL_MIRROR_URL:-https://cnrio.cn/}"
export UV_PIP_INDEX_URL="${UV_PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export AQT_BASE="${AQT_BASE:-https://mirrors.tuna.tsinghua.edu.cn/qt/}"

# Required modules for FinceptTerminal (D:\god\FinceptTerminal).
# NOTE: qtsvg / qttools / qttranslations / QtNetwork / QtSql / QtConcurrent /
# QtPrintSupport are NOT separate aqt modules in Qt 6.8.3 win64_mingw — they
# ship inside qtbase. Verified via:
#   python -m aqt list-qt windows desktop --modules 6.8.3 win64_mingw
QT_MODULES=(
    qtcharts         # REQUIRED: EquityChart, RiskMetrics, …
    qtmultimedia     # REQUIRED: AIChatBubble / VideoPlayerWidget
    qtwebsockets     # OPTIONAL: HAS_WEBSOCKETS — broker WS feeds
    qtimageformats   # extra image format plugins (TIFF / WEBP / …)
    qtspeech         # OPTIONAL: HAS_TTS — Windows uses SAPI backend
)

# ── Logging helpers ──────────────────────────────────────────────────────────
log()  { printf '\033[1;34m[qt6-mingw]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[qt6-mingw] WARN:\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[qt6-mingw] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ── Install uv + Python 3.13 + create venv ──────────────────────────────────
if ! command -v uv >/dev/null 2>&1; then
    log "uv not found, installing from ${UV_INSTALL_URL} ..."
    curl -LsSf "${UV_INSTALL_URL}" | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || err "uv install failed"
log "uv: $(uv --version)"

# Install a standalone Python 3.13 (uv pulls from CNB mirror, no system Python)
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    log "Installing Python 3.13 via uv..."
    uv python install 3.13 2>/dev/null || true  # idempotent — safe to re-run
    log "Creating venv at ${VENV_DIR}"
    uv venv "${VENV_DIR}" --python 3.13
fi
VENV_PY="${VENV_DIR}/bin/python"
"${VENV_PY}" -c "import sys; print('Python', sys.version)"

# ── Install aqtinstall via uv into the venv (VIRTUAL_ENV required) ───────────
# uv pip install reads VIRTUAL_ENV to determine the target environment.
# Without it, uv may install into a different location.
if ! "${VENV_PY}" -c "import aqt" 2>/dev/null; then
    log "Installing aqtinstall into ${VENV_DIR} (VIRTUAL_ENV=${VENV_DIR})"
    VIRTUAL_ENV="${VENV_DIR}" uv pip install aqtinstall==3.1.*
fi
log "aqt: $("${VENV_PY}" -c 'import aqt; print(aqt.__version__)')"

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

AQT_ARGS=(install-qt "${QT_HOST}" "desktop" "${QT_VERSION}" "${QT_ARCH}" -m "${QT_MODULES[@]}")
if [[ -n "${QT_MIRROR:-}" ]]; then
    AQT_ARGS+=(--base "${QT_MIRROR}")
fi

VIRTUAL_ENV="${VENV_DIR}" "${VENV_PY}" -m aqt "${AQT_ARGS[@]}"

# ── Install MinGW-w64 ${WINLIBS_VERSION} toolchain from WinLibs ──────────────
# Qt's official SDK only ships MinGW 13.1.0; for 14.x we download WinLibs
# directly. The zip contains a single top-level `mingw64/` directory which
# we move up so the layout mirrors the aqtinstall-style path
# `/opt/Qt/Tools/mingw${QT_MINGW_VER}_64/...`. WinLibs ships binaries
# prefixed with `x86_64-w64-mingw32-` (e.g. `g++.exe`, `gcc.exe`,
# `windres.exe`), so downstream scripts need no adjustment.
WINLIBS_URL="https://github.com/brechtsanders/winlibs_mingw/releases/download/${WINLIBS_TAG}/winlibs-x86_64-posix-seh-gcc-${WINLIBS_VERSION}-mingw-w64ucrt-12.0.0-r1.zip"
MINGW_DIR="${QT_INSTALL_DIR}/Tools/mingw${QT_MINGW_VER}_64"
MINGW_GPP="${MINGW_DIR}/bin/x86_64-w64-mingw32-g++.exe"

if [[ ! -x "${MINGW_GPP}" ]]; then
    log "Downloading MinGW ${WINLIBS_VERSION} (WinLibs ${WINLIBS_TAG}) ..."
    curl -fL --retry 3 -o /tmp/mingw.zip "${WINLIBS_URL}"
    log "Extracting to ${MINGW_DIR} ..."
    mkdir -p "${MINGW_DIR}"
    7z x /tmp/mingw.zip -o"${MINGW_DIR}" -y >/dev/null
    # WinLibs zip top-level is `mingw64/`; flatten it.
    if [[ -d "${MINGW_DIR}/mingw64" ]]; then
        mv "${MINGW_DIR}/mingw64/"* "${MINGW_DIR}/"
        rmdir "${MINGW_DIR}/mingw64"
    fi
    rm /tmp/mingw.zip
else
    log "MinGW already installed at ${MINGW_DIR}, skipping."
fi

# ── Verify installation ──────────────────────────────────────────────────────
QMAKE="${QT_BIN}/qmake6.exe"

[[ -x "${QMAKE}"    ]] || err "qmake6.exe not found at ${QMAKE}"
[[ -x "${MINGW_GPP}" ]] || err "MinGW g++ not found at ${MINGW_GPP}"

log "Qt ${QT_VERSION} installed:"
log "  qmake:  ${QMAKE}"
log "  g++:    ${MINGW_GPP}"
"${QMAKE}" -v 2>/dev/null || true
"${MINGW_GPP}" --version 2>/dev/null | head -1 || true

log "Done."
