#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DRY_RUN="${DRY_RUN:-false}"

log() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    log "ERROR" "Este script debe ejecutarse con sudo/root"
    exit 1
  fi
}

detect_target_user() {
  local guessed
  guessed="${SUDO_USER:-$(logname 2>/dev/null || true)}"
  if [[ -z "${guessed}" || "${guessed}" == "root" ]]; then
    log "ERROR" "No se pudo detectar usuario objetivo (SUDO_USER/logname)"
    exit 1
  fi

  if ! [[ "${guessed}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log "ERROR" "Usuario objetivo invalido: ${guessed}"
    exit 1
  fi

  export TARGET_USER="${guessed}"
  export TARGET_HOME="/home/${TARGET_USER}"
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY" "$*"
    return 0
  fi
  "$@"
}

apt_update() {
  log "INFO" "Actualizando indice APT"
  run_cmd apt update
}

apt_install_if_missing() {
  local pkg="$1"
  if dpkg -s "${pkg}" >/dev/null 2>&1; then
    log "SKIP" "${pkg} ya instalado"
    return 0
  fi
  log "INFO" "Instalando ${pkg}"
  run_cmd apt install -y "${pkg}"
}

ensure_debian_sources() {
  local sources="/etc/apt/sources.list"
  if grep -q 'non-free-firmware' "${sources}" 2>/dev/null; then
    log "SKIP" "sources.list ya contiene non-free-firmware"
    return 0
  fi

  log "INFO" "Configurando repos Debian Trixie con non-free-firmware"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY" "Sobrescribiria ${sources}"
    return 0
  fi

  cp "${sources}" "${sources}.bak.$(date +%Y%m%d%H%M%S)"
  cat > "${sources}" <<'EOF'
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
EOF
}

ensure_flatpak() {
  apt_install_if_missing flatpak
  if ! flatpak remote-list 2>/dev/null | grep -q '^flathub'; then
    log "INFO" "Agregando remoto flathub"
    run_cmd flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  else
    log "SKIP" "flathub ya configurado"
  fi
}

install_flatpak_app() {
  local app_id="$1"
  if flatpak list --app --columns=application 2>/dev/null | grep -q "^${app_id}$"; then
    log "SKIP" "${app_id} ya instalado"
    return 0
  fi
  log "INFO" "Instalando Flatpak ${app_id}"
  run_cmd flatpak install -y --noninteractive flathub "${app_id}"
}
