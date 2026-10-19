#!/usr/bin/env bash
# ============================================================================
#  debloat-vps.sh — rapikan mesin VPS tiap awal sesi:
#   1) hapus sisa agen cloud pihak ketiga bila ada
#      (/usr/local/qcloud, tat_agent, /etc/ld.so.preload, libonion_security)
#      Catatan: runner GitHub-hosted berjalan di Azure dan TIDAK punya file
#      ini — blok ini hanya jaring pengaman (no-op bila tidak ada).
#   2) bebaskan disk: toolchain besar yang tidak dipakai sesi ini
#      (dotnet, ghc, boost, Android SDK, hostedtoolcache), docker prune.
#   3) bersihkan cache: apt, journal, npm/pip/yarn.
#  Semua best-effort: kegagalan tidak menghentikan sesi.
#
#  Env: VPS_USER (opsional), GITHUB_STEP_SUMMARY (opsional).
# ============================================================================
set -uo pipefail
export XY_TAG='VpsFree:debloat'
. "$(dirname "$0")/lib-common.sh"

avail_bytes() { df -B1 --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9'; }
human() {
  awk -v b="${1:-0}" 'BEGIN{ if (b>=1073741824) printf "%.2f GB", b/1073741824; else printf "%.0f MB", b/1048576 }'
}

before="$(avail_bytes)"; [ -z "$before" ] && before=0
log "disk bebas sebelum: $(human "$before")"

# ---------- 1) sisa agen cloud pihak ketiga / preload mencurigakan ----------
found=0
for p in /usr/local/qcloud /usr/local/tat /usr/lib/onion; do
  [ -e "$p" ] || continue
  if sudo rm -rf "$p" >/dev/null 2>&1; then log "dihapus: $p"; found=1; fi
done
if [ -f /etc/ld.so.preload ]; then
  log "ld.so.preload ditemukan: $(head -c 200 /etc/ld.so.preload | tr '\n' ' ')"
  sudo rm -f /etc/ld.so.preload >/dev/null 2>&1 && { log 'dihapus: /etc/ld.so.preload'; found=1; }
fi
for lib in /lib/*/libonion_security.so* /usr/lib/libonion_security.so* \
           /usr/lib/*/libonion_security.so* /usr/local/lib/libonion_security.so*; do
  [ -e "$lib" ] || continue
  sudo rm -f "$lib" >/dev/null 2>&1 && { log "dihapus: $lib"; found=1; }
done
for svc in tat_agent ydservice YunJing barad_agent SGAgent; do
  sudo systemctl stop "$svc" >/dev/null 2>&1 || true
  sudo systemctl disable "$svc" >/dev/null 2>&1 || true
done
sudo rm -f /etc/systemd/system/tat_agent.service /etc/systemd/system/ydservice.service \
  >/dev/null 2>&1 || true
[ "$found" -eq 0 ] && log 'sisa agen cloud pihak ketiga: tidak ditemukan (bersih).'

# ---------- 2) toolchain besar yang tidak dipakai sesi ini ----------
BIG=(
  /usr/share/dotnet
  /opt/ghc
  /usr/local/share/boost
  /usr/local/lib/android
  /usr/local/share/powershell
  /opt/hostedtoolcache
)
for d in "${BIG[@]}"; do
  [ -d "$d" ] || continue
  if sudo rm -rf "$d" >/dev/null 2>&1; then
    log "dihapus (tidak dipakai): $d"
  else
    log "gagal menghapus (dilewati): $d"
  fi
done

if command -v docker >/dev/null 2>&1; then
  if sudo docker system prune -af --volumes >/dev/null 2>&1; then
    log 'docker: image/container/cache dibersihkan.'
  fi
fi

# ---------- 3) cache paket & log ----------
sudo apt-get autoremove -y -qq >/dev/null 2>&1 || true
sudo apt-get clean -qq >/dev/null 2>&1 || true
sudo rm -rf /var/cache/apt/archives >/dev/null 2>&1 || true
sudo journalctl --vacuum-size=50M >/dev/null 2>&1 || true
for h in /root "/home/${VPS_USER:-vps}" /home/runner; do
  [ -d "$h" ] || continue
  sudo rm -rf "$h/.npm/_cacache" "$h/.cache/pip" "$h/.cache/yarn" >/dev/null 2>&1 || true
done
log 'cache apt/journal/npm/pip dibersihkan.'

# ---------- ringkasan ----------
after="$(avail_bytes)"; [ -z "$after" ] && after=0
freed=$(( after - before )); [ "$freed" -lt 0 ] && freed=0
log "disk bebas sesudah: $(human "$after") (dibebaskan ~$(human "$freed"))"

{
  printf '### Debloat VPS\n\n'
  printf '| | |\n|---|---|\n'
  printf '| Disk bebas sebelum | %s |\n' "$(human "$before")"
  printf '| Disk bebas sesudah | %s |\n' "$(human "$after")"
  printf '| Dibebaskan | ~%s |\n' "$(human "$freed")"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true
exit 0
