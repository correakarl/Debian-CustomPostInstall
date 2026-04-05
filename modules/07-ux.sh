#!/usr/bin/env bash

# UX: tema, atajos y shell profile para una experiencia inicial consistente.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

configure_theme() {
  local theme_archive="${SCRIPT_DIR}/../Fake10-v5.tar.gz"
  mkdir -p "${TARGET_HOME}/.themes" "${TARGET_HOME}/.icons"

  if [[ -f "${theme_archive}" ]]; then
    tar -xzf "${theme_archive}" -C "${TARGET_HOME}/.themes" || true
    log "OK" "Tema Fake10 desplegado en ~/.themes"
  else
    log "SKIP" "No se encontro Fake10-v5.tar.gz"
  fi

  mkdir -p "${TARGET_HOME}/.config/gtk-3.0"
  cat > "${TARGET_HOME}/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Fake10
gtk-icon-theme-name=Papirus
gtk-font-name=Fira Code 10
gtk-application-prefer-dark-theme=0
EOF
}

configure_shell_profile() {
  local bashrc="${TARGET_HOME}/.bashrc"
  if grep -q 'OMNI-MODULAR-ALIASES' "${bashrc}" 2>/dev/null; then
    log "SKIP" "Alias modulares ya presentes"
    return 0
  fi

  cat >> "${bashrc}" <<'EOF'
# OMNI-MODULAR-ALIASES
alias ll='ls -lah --color=auto'
alias update='sudo apt update && sudo apt upgrade -y'
alias purge='sudo apt autoremove -y && sudo apt clean'
alias sysinfo='echo "=== CPU ===" && lscpu | grep "Model name" && echo "=== RAM ===" && free -h && echo "=== DISK ===" && df -h /'
EOF
}

main() {
  require_root
  detect_target_user
  configure_theme
  configure_shell_profile
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.themes" "${TARGET_HOME}/.icons" "${TARGET_HOME}/.config/gtk-3.0" || true
  log "OK" "Modulo ux completado"
}

main "$@"
