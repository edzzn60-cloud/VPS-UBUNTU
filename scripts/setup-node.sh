#!/usr/bin/env bash
# ============================================================================
#  setup-node.sh — pasang / update Node.js + npm ke versi TERBARU (via nvm).
#   * nvm disimpan di home VPS_USER -> ikut state archive (tahan ganti sesi)
#   * dijalankan tiap sesi = auto-update ke rilis terbaru
#   * node/npm/npx/corepack di-symlink ke /usr/local/bin agar tersedia juga
#     untuk root dan shell non-login (mis. `ssh user@vps node -v`)
#
#  Env: VPS_USER (default vps).
# ============================================================================
set -uo pipefail
export XY_TAG='VpsFree:node'
. "$(dirname "$0")/lib-common.sh"

u="${VPS_USER:-vps}"
home="/home/$u"; [ "$u" = "root" ] && home="/root"
if ! id -u "$u" >/dev/null 2>&1; then
  log "user '$u' tidak ada — lewati update Node.js."; exit 0
fi

as_u() { sudo -u "$u" -H bash -c "$1"; }

if [ ! -s "$home/.nvm/nvm.sh" ]; then
  log 'memasang nvm...'
  if ! as_u 'curl -fsSL --connect-timeout 15 --max-time 120 https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash' >/dev/null 2>&1; then
    log 'gagal memasang nvm — lewati update Node.js.'; exit 0
  fi
fi

log 'meng-update Node.js + npm ke versi terbaru (butuh 1-2 menit)...'
out="$(as_u '. "$HOME/.nvm/nvm.sh" && nvm install node && nvm alias default node && npm install -g npm@latest && node -v && npm -v' 2>&1)" || true
node_v="$(printf '%s' "$out" | grep -E '^v[0-9]+\.' | tail -1)"
npm_v="$(printf '%s' "$out" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | tail -1)"

node_bin="$(as_u '. "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 && dirname "$(nvm which node 2>/dev/null)"' 2>/dev/null | tail -1)"
if [ -n "$node_bin" ] && [ -x "$node_bin/node" ]; then
  for b in node npm npx corepack; do
    [ -e "$node_bin/$b" ] || continue
    sudo ln -sf "$node_bin/$b" "/usr/local/bin/$b" 2>/dev/null || true
  done
fi

if [ -n "$node_v" ]; then
  log "Node.js $node_v + npm ${npm_v:-?} siap (user $u; perintah juga tersedia di /usr/local/bin)."
else
  log 'update Node.js selesai dengan peringatan — cek manual bila perlu.'
fi

{
  printf '### Node.js / npm\n\n'
  printf '| | |\n|---|---|\n'
  printf '| Node.js | %s |\n' "${node_v:-?}"
  printf '| npm | %s |\n' "${npm_v:-?}"
  printf '| user | %s (root juga bisa) |\n' "$u"
  printf '| cek | `node -v && npm -v` |\n'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true
exit 0
