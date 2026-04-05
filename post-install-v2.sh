#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# shellcheck source=lib/v2/common.sh
source "${ROOT_DIR}/lib/v2/common.sh"
# shellcheck source=lib/v2/profiles.sh
source "${ROOT_DIR}/lib/v2/profiles.sh"
# shellcheck source=lib/profile-json.sh
source "${ROOT_DIR}/lib/profile-json.sh"

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
  --action <tipo>        install | check-fix | configure | reinstall | remove | clean | clean-obsolete | optimize | logs | health
  --profile <nombre>     Perfil de uso del equipo
  --mode <tipo>          full | utils | debug-clean
  --profile-json <ruta>  JSON de comprobacion/personalizacion (estado deseado)
  --dry-run              Simula cambios
  --non-interactive      No hace preguntas
  --interactive          Fuerza menu guiado
  --list-profiles        Muestra perfiles disponibles
  --list-actions         Muestra acciones disponibles
  -h, --help             Ayuda

Ejemplos:
  sudo ./post-install-v2.sh --action install --profile workstation --mode full
  sudo ./post-install-v2.sh --action check-fix --profile workstation --mode full
  sudo ./post-install-v2.sh --action configure --profile dev-web
  sudo ./post-install-v2.sh --action reinstall --profile gaming --mode full
  sudo ./post-install-v2.sh --action remove --profile creator
  sudo ./post-install-v2.sh --action clean --non-interactive
  sudo ./post-install-v2.sh --action logs
  sudo ./post-install-v2.sh --action health
  sudo ./post-install-v2.sh --profile-json ./config/customization-profile.example.json --action health

Modo interactivo:
  En el asistente puedes usar:
  r = regresar | c = cancelar | s = salir
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
      --profile-json)
        PROFILE_JSON="$2"
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
    install|check-fix|configure|reinstall|remove|clean|clean-obsolete|optimize|logs|health)
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
  clear
  echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${WHITE}  DEBIAN POST-INSTALL V2 - MENU PRINCIPAL        ${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
  echo -e "${CYAN}Perfil actual:${NC} ${PROFILE} | ${CYAN}Modo:${NC} ${INSTALL_MODE}"
  echo -e "${CYAN}Acción actual:${NC} ${ACTION} | ${CYAN}Dry-run:${NC} ${DRY_RUN}"
}

show_action_menu_v2() {
  echo ""
  echo -e "${BOLD}Seleccione una opción:${NC}"
  echo -e "  ${GREEN}[1]${NC} Instalar"
  echo -e "  ${GREEN}[2]${NC} Check and Fix"
  echo -e "  ${GREEN}[3]${NC} Configurar"
  echo -e "  ${GREEN}[4]${NC} Reinstalar"
  echo -e "  ${GREEN}[5]${NC} Eliminar"
  echo -e "  ${GREEN}[6]${NC} Limpieza general"
  echo -e "  ${GREEN}[7]${NC} Limpiar reemplazados"
  echo -e "  ${GREEN}[8]${NC} Optimizar"
  echo -e "  ${GREEN}[9]${NC} Ver logs"
  echo -e "  ${GREEN}[10]${NC} Panel de salud"
  echo -e "  ${GRAY}[r]${NC} Regresar"
  echo -e "  ${YELLOW}[c]${NC} Cancelar"
  echo -e "  ${RED}[s]${NC} Salir"
  echo -n -e "\n${CYAN}Opción [1-10,r,c,s]: ${NC}"
}

interactive_wizard() {
  local step="action"
  local input

  while true; do
    case "${step}" in
      action)
        show_banner
        show_action_menu_v2
        read -r input
        case "${input,,}" in
          1) ACTION="install"; step="profile" ;;
          2) ACTION="check-fix"; step="profile" ;;
          3) ACTION="configure"; step="profile" ;;
          4) ACTION="reinstall"; step="profile" ;;
          5) ACTION="remove"; step="profile" ;;
          6) ACTION="clean"; return 0 ;;
          7) ACTION="clean-obsolete"; return 0 ;;
          8) ACTION="optimize"; return 0 ;;
          9) ACTION="logs"; return 0 ;;
          10) ACTION="health"; return 0 ;;
          r) ;;
          c)
            log "WARN" "Asistente cancelado por usuario"
            return 1
            ;;
          s)
            log "INFO" "Saliendo por solicitud del usuario"
            exit 0
            ;;
          *)
            log "WARN" "Opcion invalida, intenta nuevamente"
            ;;
        esac
        ;;

      profile)
        clear
        section "Seleccion de perfil"
        print_profiles_help
        echo ""
        echo "Comandos: r=regresar, c=cancelar, s=salir"
        input="$(prompt_with_default "Perfil" "${PROFILE}")"
        case "${input,,}" in
          r) step="action" ;;
          c)
            log "WARN" "Asistente cancelado por usuario"
            return 1
            ;;
          s)
            log "INFO" "Saliendo por solicitud del usuario"
            exit 0
            ;;
          workstation|dev-web|dev-app|dev-mobile|gaming|creator|minimal)
            PROFILE="${input}"
            step="mode"
            ;;
          *) log "WARN" "Perfil invalido, intenta nuevamente" ;;
        esac
        ;;

      mode)
        clear
        section "Seleccion de modo"
        echo "Modos: full | utils | debug-clean"
        echo "Comandos: r=regresar, c=cancelar, s=salir"
        input="$(prompt_with_default "Modo" "${INSTALL_MODE}")"
        case "${input,,}" in
          r) step="profile" ;;
          c)
            log "WARN" "Asistente cancelado por usuario"
            return 1
            ;;
          s)
            log "INFO" "Saliendo por solicitud del usuario"
            exit 0
            ;;
          full|utils|debug-clean)
            INSTALL_MODE="${input}"
            return 0
            ;;
          *) log "WARN" "Modo invalido, intenta nuevamente" ;;
        esac
        ;;
    esac
  done
}

pre_cleanup_profile_defaults() {
  local profile="$1"

  # Nunca cambiar kernel: solo limpieza de preconfig de usuario y app runtime.
  case "${profile}" in
    workstation|dev-web|dev-app|dev-mobile|gaming|creator|minimal)
      local bottles_dir="${TARGET_HOME}/.var/app/com.usebottles.bottles"
      if [[ -d "${bottles_dir}" ]]; then
        rm -rf "${bottles_dir}" 2>/dev/null || true
        log "OK" "Preconfiguracion Bottles limpiada para fix correctivo"
      fi
      rm -f "${TARGET_HOME}/.config/gtk-3.0/settings.ini" 2>/dev/null || true
      ;;
  esac
}

check_and_fix_profile() {
  section "Check and Fix (${PROFILE})"
  pre_cleanup_profile_defaults "${PROFILE}"

  local apt_list
  apt_list="$(profile_packages_apt "${PROFILE}")"
  local flatpak_list
  flatpak_list="$(profile_packages_flatpak "${PROFILE}")"

  # Reinstalacion correctiva del perfil
  for pkg in ${apt_list}; do
    apt_reinstall "${pkg}"
  done

  if [[ -n "${flatpak_list}" ]]; then
    ensure_flatpak
    for app in ${flatpak_list}; do
      remove_flatpak_app_if_installed "${app}"
      install_flatpak_app "${app}"
    done
  fi

  # Reaplicar post-configuraciones del stack completo por modo.
  run_install_mode
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
    check-fix)
      check_and_fix_profile
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
    clean-obsolete)
      section "Limpieza de reemplazados"
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
    if ! interactive_wizard; then
      log "WARN" "Proceso cancelado por el usuario"
      exit 0
    fi
  fi

  validate_action
  if [[ "${ACTION}" != "clean" && "${ACTION}" != "clean-obsolete" && "${ACTION}" != "optimize" && "${ACTION}" != "logs" && "${ACTION}" != "health" ]]; then
    validate_profile
  fi

  if ! preflight_checks; then
    if ! confirm_or_continue "Preflight con errores. Deseas continuar?"; then
      exit 1
    fi
  fi

  if [[ -n "${PROFILE_JSON:-}" ]]; then
    section "Auditoria JSON de estado deseado"
    json_profile_audit "${PROFILE_JSON}" "${TARGET_HOME}"
  fi

  log "INFO" "${V2_NAME} v${V2_VERSION}"
  log "INFO" "Usuario objetivo: ${TARGET_USER} | DE: ${DESKTOP_ENV} | RAM: ${TOTAL_RAM_GB}GB"
  log "INFO" "Accion: ${ACTION} | Perfil: ${PROFILE} | Modo: ${INSTALL_MODE} | Dry-run: ${DRY_RUN}"

  section "Resumen y guia"
  log "INFO" "install/reinstall aplican modulos segun perfil"
  log "INFO" "configure reaplica ajustes de UX y runtime"
  log "INFO" "remove purga paquetes/apps del perfil"
  log "INFO" "clean elimina residuos y dependencias obsoletas"
  log "INFO" "clean-obsolete elimina paquetes reemplazados"
  log "INFO" "check-fix valida perfil/modulo y reinstala versión correctiva"
  log "INFO" "optimize re-aplica optimizaciones base"
  log "INFO" "logs muestra el ultimo registro"
  log "INFO" "health muestra el panel de estado de salud"
  log "INFO" "Restriccion: este script no modifica ni reemplaza el kernel"

  run_action

  section "Finalizado"
  log "OK" "Proceso completado"
  log "OK" "Archivo de log: ${LOG_FILE}"
}

main "$@"
