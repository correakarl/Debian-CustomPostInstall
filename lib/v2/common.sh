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
LOG_DIR="${ROOT_DIR:-$(pwd)}/.runtime-logs"
LOG_FILE=""
RUN_STARTED_AT=""
RUN_STARTED_EPOCH=""
RUN_LOG_FINALIZED_V2="false"

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
  mkdir -p "${LOG_DIR}"
  rotate_logs_v2
  ts="$(date +%F-%H%M%S)"
  LOG_FILE="${LOG_DIR}/debian-postinstall-v2-${ts}.log"
  export LOG_FILE
  RUN_STARTED_AT="$(date '+%F %T %z')"
  RUN_STARTED_EPOCH="$(date +%s)"
  exec > >(tee -a "${LOG_FILE}") 2>&1
  log "OK" "Logging habilitado: ${LOG_FILE}"
  log "INFO" "[RUN-START][V2] ts=${RUN_STARTED_AT} pid=$$"
}

rotate_logs_v2() {
  local keep=6
  local total_limit_bytes=$((25 * 1024 * 1024))
  local logs=("${LOG_DIR}"/debian-postinstall-v2-*.log)

  if [[ ! -e "${logs[0]}" ]]; then
    return 0
  fi

  IFS=$'\n' logs=($(ls -t "${LOG_DIR}"/debian-postinstall-v2-*.log 2>/dev/null))

  if [[ ${#logs[@]} -gt ${keep} ]]; then
    local i
    for ((i=keep; i<${#logs[@]}; i++)); do
      rm -f "${logs[$i]}" 2>/dev/null || true
    done
  fi

  local total_bytes=0
  local f
  for f in "${logs[@]}"; do
    [[ -f "${f}" ]] || continue
    total_bytes=$((total_bytes + $(wc -c < "${f}" 2>/dev/null || echo 0)))
  done

  if (( total_bytes > total_limit_bytes )); then
    local idx=$(( ${#logs[@]} - 1 ))
    while (( idx >= 0 && total_bytes > total_limit_bytes )); do
      f="${logs[$idx]}"
      if [[ -f "${f}" ]]; then
        total_bytes=$((total_bytes - $(wc -c < "${f}" 2>/dev/null || echo 0)))
        rm -f "${f}" 2>/dev/null || true
      fi
      idx=$((idx - 1))
    done
  fi
}

finalize_logging_v2() {
  local exit_code="$1"
  [[ "${RUN_LOG_FINALIZED_V2}" == "true" ]] && return 0
  RUN_LOG_FINALIZED_V2="true"

  local ended_at ended_epoch duration
  ended_at="$(date '+%F %T %z')"
  ended_epoch="$(date +%s)"
  duration=$((ended_epoch - ${RUN_STARTED_EPOCH:-ended_epoch}))

  log "INFO" "[RUN-END][V2] ts=${ended_at} pid=$$ exit=${exit_code} duration_sec=${duration}"
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

is_pkgmgr_command_v2() {
  case "$1" in
    apt|apt-get|dpkg)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

repair_package_manager_v2() {
  log "WARN" "Fallo detectado en gestor de paquetes. Intentando autoreparacion..."

  if command -v fuser >/dev/null 2>&1; then
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
       fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
       fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
      log "ERROR" "Lock activo de APT/DPKG. Cierra otro proceso y reintenta"
      return 1
    fi
  fi

  dpkg --configure -a >/dev/null 2>&1 || true
  apt --fix-broken install -y >/dev/null 2>&1 || true
  apt-get install -f -y >/dev/null 2>&1 || true
  apt clean >/dev/null 2>&1 || true

  if dpkg --audit | grep -q .; then
    log "ERROR" "Autoreparacion incompleta: quedan paquetes con incidencias"
    return 1
  fi

  log "OK" "Autoreparacion APT/DPKG completada"
  return 0
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY" "$*"
    return 0
  fi

  if "$@"; then
    return 0
  fi

  if is_pkgmgr_command_v2 "$1"; then
    repair_package_manager_v2 || return 1
    "$@"
    return $?
  fi

  return 1
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

show_spinner_v2() {
  local msg="$1"
  shift

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    "$@"
    return $?
  fi

  local spin='|/-\\'
  local i=0

  "$@" >/dev/null 2>&1 &
  local pid=$!

  while kill -0 "${pid}" 2>/dev/null; do
    printf "\r%s %s" "${spin:i++%${#spin}:1}" "${msg}"
    sleep 0.08
  done

  wait "${pid}"
  local status=$?
  printf "\r"

  if [[ ${status} -eq 0 ]]; then
    log "OK" "${msg}"
    return 0
  fi

  log "ERROR" "${msg}"
  return ${status}
}

apt_update() {
  show_spinner_v2 "Actualizando indices APT..." run_cmd apt update
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

pkg_seen_in_apt_history_v2() {
  local pkg="$1"
  local base_pkg="${pkg%:i386}"

  [[ -r "/var/log/apt/history.log" ]] || return 1
  grep -Eq "Install: .*${base_pkg}(:[a-z0-9]+)?" /var/log/apt/history.log
}

pkg_effectively_installed_v2() {
  local pkg="$1"

  case "${pkg}" in
    steam)
      pkg_installed steam || flatpak list --app --columns=application 2>/dev/null | grep -q '^com.valvesoftware.Steam$'
      ;;
    heroic-games-launcher)
      pkg_installed heroic-games-launcher || flatpak list --app --columns=application 2>/dev/null | grep -q '^com.heroicgameslauncher.hgl$'
      ;;
    protonup-qt)
      pkg_installed protonup-qt || flatpak list --app --columns=application 2>/dev/null | grep -q '^net.davidotek.pupgui2$'
      ;;
    glxinfo)
      command -v glxinfo >/dev/null 2>&1 || pkg_installed mesa-utils
      ;;
    *)
      pkg_installed "${pkg}"
      ;;
  esac
}

apt_install() {
  local pkg="$1"
  local compat_reason=""

  if ! check_package_compatibility_v2 "${pkg}" compat_reason; then
    log "SKIP" "[COMPAT:BLOCK] ${pkg} - ${compat_reason}"
    return 0
  fi

  log "INFO" "[COMPAT:OK] ${pkg}"

  if ! apt_candidate_available_v2 "${pkg}"; then
    if pkg_seen_in_apt_history_v2 "${pkg}"; then
      log "SKIP" "[REPO:MISSING] ${pkg} no disponible hoy (detectado antes en history.log; revisar repos externos)"
    else
      log "SKIP" "[REPO:MISSING] ${pkg} no disponible en indices APT actuales (posible repo externo no configurado)"
    fi
    return 0
  fi

  if pkg_installed "${pkg}"; then
    log "SKIP" "${pkg} ya instalado"
    return 0
  fi
  show_spinner_v2 "Instalando ${pkg}..." run_cmd apt install -y "${pkg}"
}

apt_reinstall() {
  local pkg="$1"
  local compat_reason=""

  if ! check_package_compatibility_v2 "${pkg}" compat_reason; then
    log "SKIP" "[COMPAT:BLOCK] ${pkg} - ${compat_reason}"
    return 0
  fi

  if ! apt_candidate_available_v2 "${pkg}"; then
    if pkg_seen_in_apt_history_v2 "${pkg}"; then
      log "SKIP" "[REPO:MISSING] ${pkg} no disponible hoy (detectado antes en history.log; revisar repos externos)"
    else
      log "SKIP" "[REPO:MISSING] ${pkg} no disponible en indices APT actuales (posible repo externo no configurado)"
    fi
    return 0
  fi

  if pkg_installed "${pkg}"; then
    show_spinner_v2 "Reinstalando ${pkg}..." run_cmd apt install --reinstall -y "${pkg}"
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
  if ! flatpak_app_available_v2 "${app_id}"; then
    log "SKIP" "[FLATPAK:MISSING] ${app_id} no disponible en flathub o remoto no configurado"
    return 0
  fi

  if flatpak list --app --columns=application 2>/dev/null | grep -Fxq "${app_id}"; then
    log "SKIP" "Flatpak ${app_id} ya instalado"
    return 0
  fi
  show_spinner_v2 "Instalando Flatpak ${app_id}..." run_cmd flatpak install -y --noninteractive flathub "${app_id}"
}

remove_flatpak_app_if_installed() {
  local app_id="$1"
  if ! command -v flatpak >/dev/null 2>&1; then
    log "SKIP" "Flatpak no disponible"
    return 0
  fi

  if ! flatpak list --app --columns=application 2>/dev/null | grep -Fxq "${app_id}"; then
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

apt_candidate_available_v2() {
  local pkg="$1"
  local base_pkg="${pkg%:i386}"
  apt-cache show "${base_pkg}" >/dev/null 2>&1
}

flatpak_app_available_v2() {
  local app_id="$1"

  command -v flatpak >/dev/null 2>&1 || return 1
  flatpak remotes --columns=name 2>/dev/null | grep -qx 'flathub' || return 1
  flatpak remote-info flathub "${app_id}" >/dev/null 2>&1
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
