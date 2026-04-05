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
ACTION="${ACTION:-install}"
PROFILE_JSON="${PROFILE_JSON:-}"

TARGET_USER=""
TARGET_HOME=""
TOTAL_RAM_GB=4
DESKTOP_ENV="unknown"
SYSTEM_ARCH="amd64"
LOG_DIR="/var/log"
LOG_FILE=""

log() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

section() {
  printf '\n==== %s ====\n' "$1"
}

setup_logging() {
  local ts
  ts="$(date +%F-%H%M%S)"
  LOG_FILE="${LOG_DIR}/debian-postinstall-v2-${ts}.log"
  export LOG_FILE
  exec > >(tee -a "${LOG_FILE}") 2>&1
  log "OK" "Logging habilitado: ${LOG_FILE}"
}

show_log_tail() {
  local lines="${1:-60}"
  local latest
  latest="$(ls -t ${LOG_DIR}/debian-postinstall-v2-*.log 2>/dev/null | head -n1 || true)"
  if [[ -z "${latest}" ]]; then
    log "WARN" "No se encontraron logs de V2 en ${LOG_DIR}"
    return 0
  fi
  section "Ultimo log V2: ${latest}"
  tail -n "${lines}" "${latest}" || true
}

is_zram_active_v2() {
  systemctl is-active --quiet zramswap 2>/dev/null && return 0
  systemctl is-active --quiet systemd-zram-setup@zram0 2>/dev/null && return 0
  swapon --show 2>/dev/null | grep -q zram && return 0
  [[ -b /dev/zram0 ]] && return 0
  return 1
}

ensure_zram_active_v2() {
  run_cmd systemctl enable --now zramswap || true
  run_cmd systemctl restart zramswap || true
  run_cmd systemctl enable --now systemd-zram-setup@zram0 || true

  if is_zram_active_v2; then
    log "OK" "ZRAM activo"
  else
    log "WARN" "ZRAM sigue inactivo tras intentos de activacion"
  fi
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
  SYSTEM_ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

  export TARGET_USER TARGET_HOME TOTAL_RAM_GB DESKTOP_ENV SYSTEM_ARCH
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
  local compat_reason=""

  if ! check_package_compatibility_v2 "${pkg}" compat_reason; then
    log "SKIP" "[COMPAT:BLOCK] ${pkg} - ${compat_reason}"
    return 0
  fi

  log "INFO" "[COMPAT:OK] ${pkg}"

  if pkg_installed "${pkg}"; then
    log "SKIP" "${pkg} ya instalado"
    return 0
  fi
  log "INFO" "Instalando ${pkg}"
  run_cmd apt install -y "${pkg}"
}

apt_reinstall() {
  local pkg="$1"
  local compat_reason=""

  if ! check_package_compatibility_v2 "${pkg}" compat_reason; then
    log "SKIP" "[COMPAT:BLOCK] ${pkg} - ${compat_reason}"
    return 0
  fi

  if pkg_installed "${pkg}"; then
    log "INFO" "Reinstalando ${pkg}"
    run_cmd apt install --reinstall -y "${pkg}"
  else
    apt_install "${pkg}"
  fi
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

apt_purge_if_installed() {
  local pkg="$1"
  if ! pkg_installed "${pkg}"; then
    log "SKIP" "${pkg} no instalado"
    return 0
  fi
  log "INFO" "Purgando ${pkg}"
  run_cmd apt purge -y "${pkg}"
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

remove_flatpak_app_if_installed() {
  local app_id="$1"
  if ! command -v flatpak >/dev/null 2>&1; then
    log "SKIP" "Flatpak no disponible"
    return 0
  fi

  if ! flatpak list --app --columns=application 2>/dev/null | grep -q "^${app_id}$"; then
    log "SKIP" "Flatpak ${app_id} no instalado"
    return 0
  fi

  log "INFO" "Eliminando Flatpak ${app_id}"
  run_cmd flatpak uninstall -y --noninteractive "${app_id}"
}

check_package_compatibility_v2() {
  local pkg="$1"
  local __reason_var="$2"
  local reason="compatible"

  case "${pkg}" in
    steam|wine32|libvulkan1:i386|mesa-vulkan-drivers:i386|libgl1-mesa-dri:i386)
      if [[ "${SYSTEM_ARCH}" != "amd64" ]]; then
        reason="requiere arquitectura amd64"
        printf -v "${__reason_var}" '%s' "${reason}"
        return 1
      fi
      ;;
    blender|kdenlive|obs-studio)
      if [[ "${TOTAL_RAM_GB}" -lt 4 ]]; then
        reason="recomendado >= 4GB RAM"
        printf -v "${__reason_var}" '%s' "${reason}"
        return 1
      fi
      ;;
  esac

  printf -v "${__reason_var}" '%s' "${reason}"
  return 0
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

prompt_with_default() {
  local prompt_text="$1"
  local default_value="$2"
  local answer

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  read -r -p "${prompt_text} [${default_value}]: " answer
  if [[ -z "${answer}" ]]; then
    printf '%s\n' "${default_value}"
  else
    printf '%s\n' "${answer}"
  fi
}
