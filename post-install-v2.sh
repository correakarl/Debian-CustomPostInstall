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
  --profile <nombre>     Perfil de uso del equipo
  --mode <tipo>          full | utils | debug-clean
  --dry-run              Simula cambios
  --non-interactive      No hace preguntas
  --list-profiles        Muestra perfiles disponibles
  -h, --help             Ayuda

Ejemplos:
  sudo ./post-install-v2.sh --profile workstation --mode full
  sudo ./post-install-v2.sh --profile dev-web --mode full
  sudo ./post-install-v2.sh --profile gaming --mode full
  sudo ./post-install-v2.sh --mode debug-clean --non-interactive
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --list-profiles)
        print_profiles_help
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

run_mode() {
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

main() {
  parse_args "$@"
  require_root
  detect_context
  check_debian_version
  validate_profile

  if ! preflight_checks; then
    if ! confirm_or_continue "Preflight con errores. Deseas continuar?"; then
      exit 1
    fi
  fi

  log "INFO" "${V2_NAME} v${V2_VERSION}"
  log "INFO" "Usuario objetivo: ${TARGET_USER} | DE: ${DESKTOP_ENV} | RAM: ${TOTAL_RAM_GB}GB"
  log "INFO" "Perfil: ${PROFILE} | Modo: ${INSTALL_MODE} | Dry-run: ${DRY_RUN}"

  run_mode

  log "OK" "Post-instalacion V2 completada"
}

main "$@"
