#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

install_windows_compat_stack() {
  local pkgs=(
    wine wine64 winetricks cabextract p7zip-full
    libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386
  )

  for pkg in "${pkgs[@]}"; do
    apt_install "${pkg}"
  done
}

install_bottles_flatpak() {
  ensure_flatpak
  install_flatpak_app com.usebottles.bottles
}

configure_bottles_hints() {
  local notes_file="${TARGET_HOME}/.local/share/postinstall-v2-bottles-notes.txt"
  mkdir -p "$(dirname "${notes_file}")"
  cat > "${notes_file}" <<'EOF'
Bottles recomendado para compatibilidad de apps Windows.
Perfiles sugeridos en Bottles:
- Application: software de oficina o utilidades.
- Gaming: solo para juegos que no esten soportados por Steam/Proton o Heroic/Lutris.

Flujo recomendado:
1. Priorizar gaming nativo Linux (Steam/Proton, Heroic, Lutris).
2. Usar Bottles para apps Windows no-juego o casos puntuales.
EOF
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local/share"
}

module_compat_bottles() {
  log "INFO" "Modulo v2: compat-bottles"
  install_windows_compat_stack
  install_bottles_flatpak
  configure_bottles_hints
  log "OK" "Modulo v2 compat-bottles completado"
}
