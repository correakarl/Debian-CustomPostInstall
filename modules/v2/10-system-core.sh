#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ensure_sources_trixie() {
  local sources="/etc/apt/sources.list"
  if grep -q 'non-free-firmware' "${sources}" 2>/dev/null; then
    log "SKIP" "sources.list ya contiene non-free-firmware"
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY" "Actualizaria ${sources} para trixie"
    return 0
  fi

  cp "${sources}" "${sources}.bak.$(date +%Y%m%d%H%M%S)"
  cat > "${sources}" <<'EOF'
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
EOF
  log "OK" "sources.list actualizado para trixie"
}

enable_i386_arch() {
  if dpkg --print-foreign-architectures | grep -q '^i386$'; then
    log "SKIP" "Arquitectura i386 ya habilitada"
    return 0
  fi
  run_cmd dpkg --add-architecture i386
  log "OK" "Arquitectura i386 habilitada"
}

configure_apt_network() {
  local apt_ipv4_conf="/etc/apt/apt.conf.d/99force-ipv4"
  if [[ ! -f "${apt_ipv4_conf}" ]]; then
    echo 'Acquire::ForceIPv4 "true";' > "${apt_ipv4_conf}"
    log "OK" "APT forzado a IPv4"
  else
    log "SKIP" "APT IPv4 ya configurado"
  fi
}

install_base_optimization_packages() {
  local pkgs=(
    curl wget ca-certificates gnupg apt-transport-https
    zram-tools earlyoom irqbalance tlp tlp-rdw thermald
    ufw fail2ban unattended-upgrades
    jq yq gedit
    inxi lshw hwinfo pciutils usbutils dmidecode fwupd nvidia-detect
    firmware-linux-nonfree firmware-misc-nonfree
    openvpn wireguard-tools network-manager-openvpn network-manager-openvpn-gnome
  )

  for pkg in "${pkgs[@]}"; do
    apt_install "${pkg}"
  done
}

configure_memory_and_kernel() {
  local swappiness=10
  local zram_fraction="0.50"

  if [[ "${TOTAL_RAM_GB}" -lt 4 ]]; then
    swappiness=1
    zram_fraction="0.75"
  fi

  if [[ -f /etc/default/zramswap ]]; then
    cat > /etc/default/zramswap <<EOF
ZRAM_FRACTION=${zram_fraction}
ZRAM_COMPRESSOR=lz4
EOF
  fi

  if ! grep -q 'POSTINSTALL_V2_CORE' /etc/sysctl.conf 2>/dev/null; then
    cat >> /etc/sysctl.conf <<EOF
# POSTINSTALL_V2_CORE
vm.swappiness=${swappiness}
vm.vfs_cache_pressure=50
net.core.default_qdisc=fq_codel
net.ipv4.tcp_congestion_control=bbr
EOF
  fi

  run_cmd sysctl -p
  ensure_zram_active_v2
  run_cmd systemctl restart earlyoom || true
  run_cmd systemctl enable --now fstrim.timer || true
}

configure_firewall() {
  run_cmd ufw --force enable || true
  run_cmd ufw allow OpenSSH || true
  log "OK" "Firewall base aplicado"
}

module_system_core() {
  log "INFO" "Modulo v2: system-core"
  ensure_sources_trixie
  enable_i386_arch
  configure_apt_network
  apt_update
  install_base_optimization_packages
  configure_memory_and_kernel
  configure_firewall
  log "OK" "Modulo v2 system-core completado"
}
