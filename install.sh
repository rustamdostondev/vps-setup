#!/usr/bin/env bash
# =====================================================================
#  vps-setup installer — puts the `vps` CLI on this machine.
#
#  One-liner:
#    curl -fsSL https://raw.githubusercontent.com/rustamdostondev/vps-setup/main/install.sh | sudo bash
#
#  Options (env vars):
#    VPS_SETUP_REPO=user/repo   install from a fork
#    VPS_SETUP_REF=main         branch or tag to install from
# =====================================================================
set -euo pipefail

REPO="${VPS_SETUP_REPO:-rustamdostondev/vps-setup}"
REF="${VPS_SETUP_REF:-main}"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${REF}/vps"
BIN_DIR="/usr/local/bin"
BIN="${BIN_DIR}/vps"

# colors + banner only on a real color terminal
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  BOLD=$'\033[1m'; GRN=$'\033[1;32m'; RED=$'\033[1;31m'; YLW=$'\033[1;33m'; CYN=$'\033[1;36m'; DIM=$'\033[2m'; C0=$'\033[0m'
else
  BOLD=""; GRN=""; RED=""; YLW=""; CYN=""; DIM=""; C0=""
fi
if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]* ]]; then
  CHK="✓"; ARR="→"
else
  CHK="+"; ARR="->"
fi
say()  { echo -e "$1"; }
fail() { echo -e "${RED}x $1${C0}" >&2; exit 1; }

if [[ -t 1 && "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]* ]]; then
  say ""
  say "${CYN}  ██╗   ██╗██████╗ ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗ ${C0}"
  say "${CYN}  ██║   ██║██╔══██╗██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${C0}"
  say "${CYN}  ██║   ██║██████╔╝███████╗    ███████╗█████╗     ██║   ██║   ██║██████╔╝${C0}"
  say "${CYN}  ╚██╗ ██╔╝██╔═══╝ ╚════██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${C0}"
  say "${CYN}   ╚████╔╝ ██║     ███████║    ███████║███████╗   ██║   ╚██████╔╝██║     ${C0}"
  say "${CYN}    ╚═══╝  ╚═╝     ╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${C0}"
fi
say ""
say "  ${BOLD}vps-setup installer${C0}  ${DIM}(${REPO} @ ${REF})${C0}"
say ""

# --- checks ----------------------------------------------------------
# (placeholder literal split so a blanket sed replace keeps this guard working)
[[ "$REPO" == *"YOUR-GITHUB-""USERNAME"* ]] \
  && fail "This installer still points at a placeholder repo.
  Set it explicitly:  VPS_SETUP_REPO=youruser/vps-setup bash install.sh"

[[ $EUID -ne 0 ]] && fail "Root required. Re-run with sudo:
  curl -fsSL https://raw.githubusercontent.com/${REPO}/${REF}/install.sh | sudo bash"

command -v curl >/dev/null || fail "curl is required (apt-get install -y curl)"

if [[ "$(uname -s)" != "Linux" ]]; then
  say "${YLW}  ! Non-Linux system detected — the CLI will install, but service"
  say "    installation only works on Ubuntu/Debian servers.${C0}"
fi

# --- download --------------------------------------------------------
say "${DIM}  ${ARR} downloading ${RAW_URL}${C0}"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -fsSL "$RAW_URL" -o "$TMP" || fail "download failed — check the repo name and your network"

# sanity: did we actually get the CLI, not an error page?
head -2 "$TMP" | grep -q "VPS-SETUP-CLI" || fail "downloaded file is not the vps CLI (wrong repo/branch?)"
bash -n "$TMP" || fail "downloaded script failed a syntax check — refusing to install"

# --- install ---------------------------------------------------------
install -m 0755 "$TMP" "$BIN"
VER=$("$BIN" version 2>/dev/null || echo "vps-setup")

say ""
say "${GRN}  ${CHK} ${VER} installed ${ARR} ${BIN}${C0}"
say ""
say "  ${BOLD}Get started:${C0}"
say "    ${CYN}sudo vps${C0}              ${DIM}interactive menu — pick services with arrow keys${C0}"
say "    ${CYN}sudo vps install all${C0}  ${DIM}install the full stack non-interactively${C0}"
say "    ${CYN}vps help${C0}              ${DIM}all commands${C0}"
say ""
