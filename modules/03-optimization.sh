#!/usr/bin/env bash

# Optimizaciones de memoria, servicios y kernel para uso diario.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

OPTIMIZATION_PACKAGES=(
  zram-tools earlyoom irqbalance tlp tlp-rdw thermald preload
  haveged sysstat lm-sensors
)

apply_sysctl_profile() {
  local swappiness="${1:-10}"
  if ! grep -q 'OMNI-MODULAR-OPT' /etc/sysctl.conf 2>/dev/null; then
    cat >> /etc/sysctl.conf <<EOF
# OMNI-MODULAR-OPT
vm.swappiness=${swappiness}
vm.vfs_cache_pressure=50
net.core.default_qdisc=fq_codel
net.ipv4.tcp_congestion_control=bbr
EOF
  fi
  run_cmd sysctl -p
}

configure_zram() {
  local ram_gb
  ram_gb=$(free -g | awk '/^Mem:/{print $2}')
  local fraction="0.50"
  local swappiness="10"

  if [[ "${ram_gb}" -lt 4 ]]; then
    fraction="0.75"
    swappiness="1"
  fi

  if [[ -f /etc/default/zramswap ]]; then
    cat > /etc/default/zramswap <<EOF
ZRAM_FRACTION=${fraction}
ZRAM_COMPRESSOR=lz4
EOF
  fi

  run_cmd systemctl restart zramswap || true
  apply_sysctl_profile "${swappiness}"
}

main() {
  require_root
  detect_target_user
  apt_update

  for pkg in "${OPTIMIZATION_PACKAGES[@]}"; do
    apt_install_if_missing "${pkg}"
  done

  configure_zram
  run_cmd systemctl enable --now fstrim.timer || true
  run_cmd systemctl restart earlyoom || true

  log "OK" "Modulo optimization completado"
}

main "$@"
