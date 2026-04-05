#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Uso:
  sudo ./run-module.sh <modulo>

Modulos disponibles:
  infra
  base
  optimization
  dev
  multimedia
  security-remote
  ux
  all

Opcional:
  DRY_RUN=true sudo -E ./run-module.sh <modulo>
EOF
}

run_mod() {
  local script="$1"
  echo "==> Ejecutando ${script}"
  bash "${ROOT_DIR}/modules/${script}"
}

main() {
  local mod="${1:-}"
  case "${mod}" in
    infra) run_mod "01-infra.sh" ;;
    base) run_mod "02-base.sh" ;;
    optimization) run_mod "03-optimization.sh" ;;
    dev) run_mod "04-dev.sh" ;;
    multimedia) run_mod "05-multimedia.sh" ;;
    security-remote) run_mod "06-security-remote.sh" ;;
    ux) run_mod "07-ux.sh" ;;
    all)
      run_mod "01-infra.sh"
      run_mod "02-base.sh"
      run_mod "03-optimization.sh"
      run_mod "04-dev.sh"
      run_mod "05-multimedia.sh"
      run_mod "06-security-remote.sh"
      run_mod "07-ux.sh"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      echo "Modulo invalido: ${mod}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
