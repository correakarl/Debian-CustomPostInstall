#!/usr/bin/env bash

# Infraestructura base: repos externos, DNS y ajustes APT de red.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

setup_external_repos() {
  local keyring_dir="/usr/share/keyrings"
  mkdir -p "${keyring_dir}"

  if [[ ! -f "${keyring_dir}/microsoft.gpg" ]]; then
    log "INFO" "Importando llave Microsoft"
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o "${keyring_dir}/microsoft.gpg"
    chmod 644 "${keyring_dir}/microsoft.gpg"
  else
    log "SKIP" "Llave Microsoft ya existe"
  fi

  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    cat > /etc/apt/sources.list.d/vscode.list <<EOF
Deb [arch=amd64 signed-by=${keyring_dir}/microsoft.gpg] https://packages.microsoft.com/repos/code stable main
EOF
    sed -i 's/^Deb /deb /' /etc/apt/sources.list.d/vscode.list
    log "INFO" "Repositorio VS Code agregado"
  fi

  if [[ ! -f /etc/apt/sources.list.d/microsoft-edge.list ]]; then
    cat > /etc/apt/sources.list.d/microsoft-edge.list <<EOF
Deb [arch=amd64 signed-by=${keyring_dir}/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main
EOF
    sed -i 's/^Deb /deb /' /etc/apt/sources.list.d/microsoft-edge.list
    log "INFO" "Repositorio Edge agregado"
  fi

  if [[ ! -f "${keyring_dir}/google-chrome.gpg" ]]; then
    log "INFO" "Importando llave Google Chrome"
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o "${keyring_dir}/google-chrome.gpg"
    chmod 644 "${keyring_dir}/google-chrome.gpg"
  fi

  if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]]; then
    cat > /etc/apt/sources.list.d/google-chrome.list <<EOF
Deb [arch=amd64 signed-by=${keyring_dir}/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main
EOF
    sed -i 's/^Deb /deb /' /etc/apt/sources.list.d/google-chrome.list
    log "INFO" "Repositorio Chrome agregado"
  fi

  if [[ ! -f "${keyring_dir}/opera.gpg" ]]; then
    log "INFO" "Importando llave Opera"
    wget -qO- https://deb.opera.com/archive.key | gpg --dearmor -o "${keyring_dir}/opera.gpg"
    chmod 644 "${keyring_dir}/opera.gpg"
  fi

  if [[ ! -f /etc/apt/sources.list.d/opera-stable.list ]]; then
    cat > /etc/apt/sources.list.d/opera-stable.list <<EOF
Deb [arch=amd64 signed-by=${keyring_dir}/opera.gpg] https://deb.opera.com/opera-stable/ stable non-free
EOF
    sed -i 's/^Deb /deb /' /etc/apt/sources.list.d/opera-stable.list
    log "INFO" "Repositorio Opera agregado"
  fi
}

configure_dns_ipv4() {
  local apt_ipv4_conf="/etc/apt/apt.conf.d/99force-ipv4"
  if [[ ! -f "${apt_ipv4_conf}" ]]; then
    echo 'Acquire::ForceIPv4 "true";' > "${apt_ipv4_conf}"
    log "INFO" "APT forzado a IPv4"
  else
    log "SKIP" "APT IPv4 ya configurado"
  fi
}

main() {
  require_root
  detect_target_user
  ensure_debian_sources
  setup_external_repos
  configure_dns_ipv4
  apt_update
  log "OK" "Modulo infra completado"
}

main "$@"
