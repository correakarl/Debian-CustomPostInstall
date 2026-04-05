#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly V2_NAME="Debian Post Install V2"
readonly V2_VERSION="2.0.0"

DRY_RUN="${DRY_RUN:-false}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
INSTALL_MODE="${INSTALL_MODE:-full}"
PROFILE="${PROFILE:-workstation}"

TARGET_USER=""
TARGET_HOME=""
TOTAL_RAM_GB=4
DESKTOP_ENV="unknown"

log() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY" "$*"
    return 0
  fi
  "$@"
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    log "ERROR" "Debes ejecutar como root/sudo"
    exit 1
  fi
}

detect_context() {
  local guessed_user
  guessed_user="${SUDO_USER:-$(logname 2>/dev/null || true)}"

  if [[ -z "${guessed_user}" || "${guessed_user}" == "root" ]]; then
    log "ERROR" "No se pudo detectar usuario objetivo"
    exit 1
  fi

  if ! [[ "${guessed_user}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log "ERROR" "Usuario invalido: ${guessed_user}"
    exit 1
  fi

  TARGET_USER="${guessed_user}"
  TARGET_HOME="/home/${TARGET_USER}"
  TOTAL_RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 4)
  DESKTOP_ENV="${XDG_CURRENT_DESKTOP:-unknown}"

  export TARGET_USER TARGET_HOME TOTAL_RAM_GB DESKTOP_ENV
}

check_debian_version() {
  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
  if [[ "${codename}" != "trixie" ]]; then
    log "WARN" "Este script esta optimizado para Debian 13 (trixie). Detectado: ${codename:-desconocido}"
  else
    log "OK" "Debian 13 (trixie) detectado"
  fi
}

preflight_checks() {
  local errors=0

  if ! curl -s --connect-timeout 8 https://deb.debian.org >/dev/null 2>&1; then
    log "ERROR" "Sin conectividad a repos Debian"
    errors=$((errors + 1))
  fi

  local disk_gb
  disk_gb=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}' || echo 0)
  if [[ "${disk_gb}" -lt 8 ]]; then
    log "ERROR" "Espacio en disco insuficiente: ${disk_gb}GB"
    errors=$((errors + 1))
  fi

  for cmd in apt dpkg curl gpg; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      log "ERROR" "Comando faltante: ${cmd}"
      errors=$((errors + 1))
    fi
  done

  if [[ "${errors}" -gt 0 ]]; then
    log "ERROR" "Preflight fallo con ${errors} error(es)"
    return 1
  fi

  log "OK" "Preflight completado"
}

apt_update() {
  run_cmd apt update
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

apt_install() {
  local pkg="$1"
  if pkg_installed "${pkg}"; then
    log "SKIP" "${pkg} ya instalado"
    return 0
  fi
  log "INFO" "Instalando ${pkg}"
  run_cmd apt install -y "${pkg}"
}

apt_remove_if_installed() {
  local pkg="$1"
  if ! pkg_installed "${pkg}"; then
    log "SKIP" "${pkg} no instalado"
    return 0
  fi
  log "INFO" "Eliminando ${pkg}"
  run_cmd apt remove -y "${pkg}"
}

ensure_flatpak() {
  apt_install flatpak
  if ! flatpak remote-list 2>/dev/null | grep -q '^flathub'; then
    run_cmd flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    log "OK" "Flathub configurado"
  fi
}

install_flatpak_app() {
  local app_id="$1"
  if flatpak list --app --columns=application 2>/dev/null | grep -q "^${app_id}$"; then
    log "SKIP" "Flatpak ${app_id} ya instalado"
    return 0
  fi
  log "INFO" "Instalando Flatpak ${app_id}"
  run_cmd flatpak install -y --noninteractive flathub "${app_id}"
}

append_once() {
  local marker="$1"
  local target_file="$2"
  local payload="$3"

  if grep -q "${marker}" "${target_file}" 2>/dev/null; then
    log "SKIP" "${marker} ya presente en ${target_file}"
    return 0
  fi

  printf '\n%s\n' "${payload}" >> "${target_file}"
  log "OK" "Bloque ${marker} agregado en ${target_file}"
}

confirm_or_continue() {
  local question="$1"

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    return 0
  fi

  read -r -p "${question} [s/N]: " answer
  case "${answer,,}" in
    s|si|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}
