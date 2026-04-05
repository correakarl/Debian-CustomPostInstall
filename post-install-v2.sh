#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/v2/common.sh
source "${ROOT_DIR}/lib/v2/common.sh"
# shellcheck source=lib/v2/profiles.sh
source "${ROOT_DIR}/lib/v2/profiles.sh"

# shellcheck source=modules/v2/10-system-core.sh
source "${ROOT_DIR}/modules/v2/10-system-core.sh"
# shellcheck source=modules/v2/20-ux-light.sh
source "${ROOT_DIR}/modules/v2/20-ux-light.sh"
# shellcheck source=modules/v2/30-compat-bottles.sh
source "${ROOT_DIR}/modules/v2/30-compat-bottles.sh"
# shellcheck source=modules/v2/40-gaming-native.sh
source "${ROOT_DIR}/modules/v2/40-gaming-native.sh"
# shellcheck source=modules/v2/50-dev-environments.sh
source "${ROOT_DIR}/modules/v2/50-dev-environments.sh"
# shellcheck source=modules/v2/60-debug-clean.sh
source "${ROOT_DIR}/modules/v2/60-debug-clean.sh"

usage() {
  cat <<'EOF'
Debian Post Install V2

Uso:
  sudo ./post-install-v2.sh [opciones]

Opciones:
  --action <tipo>        install | configure | reinstall | remove | clean | optimize | logs | health
  --profile <nombre>     Perfil de uso del equipo
  --mode <tipo>          full | utils | debug-clean
  --dry-run              Simula cambios
  --non-interactive      No hace preguntas
  --interactive          Fuerza menu guiado
  --list-profiles        Muestra perfiles disponibles
  --list-actions         Muestra acciones disponibles
  -h, --help             Ayuda

Ejemplos:
  sudo ./post-install-v2.sh --action install --profile workstation --mode full
  sudo ./post-install-v2.sh --action configure --profile dev-web
  sudo ./post-install-v2.sh --action reinstall --profile gaming --mode full
  sudo ./post-install-v2.sh --action remove --profile creator
  sudo ./post-install-v2.sh --action clean --non-interactive
  sudo ./post-install-v2.sh --action logs
  sudo ./post-install-v2.sh --action health
EOF
}

parse_args() {
  local force_interactive=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action)
        ACTION="$2"
        shift 2
        ;;
      --profile)
        PROFILE="$2"
        shift 2
        ;;
      --mode)
        INSTALL_MODE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      --interactive)
        force_interactive=true
        shift
        ;;
      --list-profiles)
        print_profiles_help
        exit 0
        ;;
      --list-actions)
        print_actions_help
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log "ERROR" "Opcion no valida: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ "${force_interactive}" == "true" ]]; then
    NON_INTERACTIVE=false
  fi
}

validate_profile() {
  case "${PROFILE}" in
    workstation|dev-web|dev-app|dev-mobile|gaming|creator|minimal)
      return 0
      ;;
    *)
      log "ERROR" "Perfil no soportado: ${PROFILE}"
      print_profiles_help
      exit 1
      ;;
  esac
}

validate_action() {
  case "${ACTION}" in
    install|configure|reinstall|remove|clean|optimize|logs|health)
      return 0
      ;;
    *)
      log "ERROR" "Accion no soportada: ${ACTION}"
      print_actions_help
      exit 1
      ;;
  esac
}

show_banner() {
  cat <<'EOF'
=============================================================
 Debian Post Install V2 - UX asistida
=============================================================
EOF
}

interactive_wizard() {
  section "Asistente interactivo"
  echo "Selecciona una accion para continuar:"
  echo "  1) install"
  echo "  2) configure"
  echo "  3) reinstall"
  echo "  4) remove"
  echo "  5) clean"
  echo "  6) optimize"
  echo "  7) logs"
  echo "  8) health"

  local action_opt
  action_opt="$(prompt_with_default "Opcion" "1")"
  case "${action_opt}" in
    1) ACTION="install" ;;
    2) ACTION="configure" ;;
    3) ACTION="reinstall" ;;
    4) ACTION="remove" ;;
    5) ACTION="clean" ;;
    6) ACTION="optimize" ;;
    7) ACTION="logs" ;;
    8) ACTION="health" ;;
    *) ACTION="install" ;;
  esac

  if [[ "${ACTION}" == "clean" || "${ACTION}" == "optimize" || "${ACTION}" == "logs" || "${ACTION}" == "health" ]]; then
    return 0
  fi

  section "Seleccion de perfil"
  print_profiles_help
  PROFILE="$(prompt_with_default "Perfil" "${PROFILE}")"

  section "Seleccion de modo"
  echo "Modos: full | utils | debug-clean"
  INSTALL_MODE="$(prompt_with_default "Modo" "${INSTALL_MODE}")"
}

remove_profile_packages() {
  section "Borrado de paquetes/apps del perfil ${PROFILE}"

  local apt_list
  apt_list="$(profile_packages_apt "${PROFILE}")"
  local flatpak_list
  flatpak_list="$(profile_packages_flatpak "${PROFILE}")"

  for pkg in ${apt_list}; do
    apt_purge_if_installed "${pkg}"
  done

  for app in ${flatpak_list}; do
    remove_flatpak_app_if_installed "${app}"
  done

  log "OK" "Borrado del perfil ${PROFILE} finalizado"
}

run_install_mode() {
  case "${INSTALL_MODE}" in
    full)
      module_system_core
      module_ux_light
      module_compat_bottles
      module_dev_environments "${PROFILE}"
      if [[ "${PROFILE}" == "gaming" ]]; then
        module_gaming_native
      fi
      ;;
    utils)
      module_system_core
      module_ux_light
      module_dev_environments "minimal"
      ;;
    debug-clean)
      module_debug_clean
      ;;
    *)
      log "ERROR" "Modo no soportado: ${INSTALL_MODE}"
      usage
      exit 1
      ;;
  esac
}

health_panel_v2() {
  section "Panel de estado de salud"
  local passed=0 total=0

  ((total++))
  if curl -s --connect-timeout 6 https://deb.debian.org >/dev/null 2>&1; then
    log "OK" "Conectividad hacia repositorios Debian"
    ((passed++))
  else
    log "WARN" "Sin conectividad hacia repositorios Debian"
  fi

  ((total++))
  local disk_use
  disk_use=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}' 2>/dev/null || echo 100)
  if [[ "${disk_use}" -lt 85 ]]; then
    log "OK" "Disco raíz en rango saludable (${disk_use}%)"
    ((passed++))
  else
    log "WARN" "Disco raíz alto (${disk_use}%)"
  fi

  ((total++))
  if systemctl is-active --quiet zramswap 2>/dev/null; then
    log "OK" "ZRAM activo"
    ((passed++))
  else
    log "WARN" "ZRAM no activo"
  fi

  ((total++))
  local failed_units
  failed_units=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
  if [[ "${failed_units}" -eq 0 ]]; then
    log "OK" "Servicios systemd sin fallos"
    ((passed++))
  else
    log "WARN" "Servicios systemd con fallo: ${failed_units}"
  fi

  ((total++))
  if command -v flatpak >/dev/null 2>&1; then
    local apps_count
    apps_count=$(flatpak list --app --columns=application 2>/dev/null | wc -l)
    log "OK" "Flatpak disponible (${apps_count} apps)"
    ((passed++))
  else
    log "WARN" "Flatpak no instalado"
  fi

  section "Resumen de salud"
  log "INFO" "Resultado: ${passed}/${total} checks en estado correcto"
  log "INFO" "Sugerencias:"
  log "INFO" "  1) --action clean para limpiar residuos"
  log "INFO" "  2) --action optimize para reaplicar tuning"
  log "INFO" "  3) --action logs para revisar trazas"
}

run_action() {
  case "${ACTION}" in
    install)
      run_install_mode
      ;;
    configure)
      section "Configuracion"
      module_ux_light
      module_dev_environments "${PROFILE}"
      ;;
    reinstall)
      section "Reinstalacion"
      remove_profile_packages
      run_install_mode
      ;;
    remove)
      remove_profile_packages
      ;;
    clean)
      section "Limpieza"
      module_debug_clean
      ;;
    optimize)
      section "Optimizacion"
      module_system_core
      ;;
    logs)
      show_log_tail 120
      ;;
    health)
      health_panel_v2
      ;;
  esac
}

main() {
  parse_args "$@"
  require_root
  setup_logging
  show_banner
  detect_context
  check_debian_version

  if [[ $# -eq 0 && "${NON_INTERACTIVE}" == "false" ]]; then
    interactive_wizard
  fi

  validate_action
  if [[ "${ACTION}" != "clean" && "${ACTION}" != "optimize" && "${ACTION}" != "logs" && "${ACTION}" != "health" ]]; then
    validate_profile
  fi

  if ! preflight_checks; then
    if ! confirm_or_continue "Preflight con errores. Deseas continuar?"; then
      exit 1
    fi
  fi

  log "INFO" "${V2_NAME} v${V2_VERSION}"
  log "INFO" "Usuario objetivo: ${TARGET_USER} | DE: ${DESKTOP_ENV} | RAM: ${TOTAL_RAM_GB}GB"
  log "INFO" "Accion: ${ACTION} | Perfil: ${PROFILE} | Modo: ${INSTALL_MODE} | Dry-run: ${DRY_RUN}"

  section "Resumen y guia"
  log "INFO" "install/reinstall aplican modulos segun perfil"
  log "INFO" "configure reaplica ajustes de UX y runtime"
  log "INFO" "remove purga paquetes/apps del perfil"
  log "INFO" "clean elimina residuos y dependencias obsoletas"
  log "INFO" "optimize re-aplica optimizaciones base"
  log "INFO" "logs muestra el ultimo registro"
  log "INFO" "health muestra el panel de estado de salud"

  run_action

  section "Finalizado"
  log "OK" "Proceso completado"
  log "OK" "Archivo de log: ${LOG_FILE}"
}

main "$@"
