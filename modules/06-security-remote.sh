#!/usr/bin/env bash

# Seguridad y acceso remoto: hardening basico de SSH y utilidades de auditoria.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

SECURITY_REMOTE_PACKAGES=(
  openssh-server openssh-client sshuttle mosh rsync rclone syncthing
  nmap wireshark tcpdump netcat-openbsd socat lynis nikto gpg
  auditd apparmor-utils chkrootkit rkhunter
)

harden_ssh() {
  local sshd_cfg="/etc/ssh/sshd_config"
  if ! dpkg -s openssh-server >/dev/null 2>&1; then
    log "SKIP" "openssh-server no instalado"
    return 0
  fi

  if grep -q '^PermitRootLogin no' "${sshd_cfg}" 2>/dev/null; then
    log "SKIP" "PermitRootLogin no ya aplicado"
  else
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "${sshd_cfg}"
    log "INFO" "Hardening SSH aplicado: PermitRootLogin no"
  fi

  run_cmd systemctl enable --now ssh
  run_cmd systemctl reload ssh
}

main() {
  require_root
  detect_target_user
  apt_update

  for pkg in "${SECURITY_REMOTE_PACKAGES[@]}"; do
    apt_install_if_missing "${pkg}"
  done

  harden_ssh
  log "OK" "Modulo security-remote completado"
}

main "$@"
