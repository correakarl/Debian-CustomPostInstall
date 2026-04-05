#!/usr/bin/env bash

# Paquetes base del sistema y configuracion inicial de firewall.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

BASE_PACKAGES=(
  curl wget git ca-certificates gnupg apt-transport-https
  neovim htop less tree bash-completion zip unzip p7zip-full
  tar zstd net-tools dnsutils iputils-ping traceroute
  ufw fail2ban unattended-upgrades
  fonts-firacode fonts-noto fonts-noto-color-emoji fontconfig
  jq yq gawk sed grep findutils
)

configure_ufw() {
  if ! dpkg -s ufw >/dev/null 2>&1; then
    log "SKIP" "ufw no esta instalado"
    return 0
  fi

  if ufw status | grep -q 'Status: active'; then
    log "SKIP" "ufw ya esta activo"
  else
    run_cmd ufw --force enable
  fi

  run_cmd ufw allow OpenSSH
  log "OK" "ufw configurado con regla OpenSSH"
}

main() {
  require_root
  detect_target_user

  apt_update
  for pkg in "${BASE_PACKAGES[@]}"; do
    apt_install_if_missing "${pkg}"
  done

  configure_ufw
  log "OK" "Modulo base completado"
}

main "$@"
