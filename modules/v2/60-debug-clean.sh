#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Limpieza de paquetes y utilidades reemplazadas por opciones modernas.

cleanup_replaced_tools() {
  # exa fue reemplazado por eza en muchos flujos modernos.
  if pkg_installed exa; then
    apt_install eza || true
    apt_remove_if_installed exa
  fi

  # Reemplazo de editor ligero: mousepad -> gedit.
  if pkg_installed mousepad; then
    apt_install gedit || true
    apt_remove_if_installed mousepad
  fi

  # net-tools puede mantenerse por compatibilidad, pero se deja opcional remover.
  if pkg_installed net-tools; then
    if confirm_or_continue "Deseas remover net-tools y quedarte con iproute2?"; then
      apt_remove_if_installed net-tools
    else
      log "SKIP" "net-tools conservado"
    fi
  fi
}

cleanup_unused_artifacts() {
  run_cmd apt autoremove -y
  run_cmd apt autoclean -y || true
  run_cmd apt clean

  if command -v flatpak >/dev/null 2>&1; then
    run_cmd flatpak uninstall --unused -y || true
  fi
}

module_debug_clean() {
  log "INFO" "Modulo v2: debug-clean"
  cleanup_replaced_tools
  cleanup_unused_artifacts
  log "OK" "Modulo v2 debug-clean completado"
}
