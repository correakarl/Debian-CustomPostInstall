#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

install_windows_compat_stack() {
  # i386 habilitado para runtimes Win32 y librerias compartidas.
  if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
    run_cmd dpkg --add-architecture i386
    apt_update
  fi

  local pkgs=(
    wine wine64 wine32 winetricks cabextract p7zip-full
    libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386
    libgl1-mesa-dri libgl1-mesa-dri:i386
    fonts-liberation fonts-noto fonts-noto-color-emoji
  )

  for pkg in "${pkgs[@]}"; do
    apt_install "${pkg}"
  done
}

install_bottles_flatpak() {
  ensure_flatpak
  install_flatpak_app com.usebottles.bottles

  # Permisos recomendados para compatibilidad amplia de aplicaciones.
  run_cmd sudo -u "${TARGET_USER}" flatpak override --user \
    --filesystem=home --share=network --socket=x11 --socket=wayland \
    --device=all com.usebottles.bottles
}

configure_bottles_hints() {
  local notes_file="${TARGET_HOME}/.local/share/postinstall-v2-bottles-notes.txt"
  mkdir -p "$(dirname "${notes_file}")"
  cat > "${notes_file}" <<'EOF'
Bottles recomendado para compatibilidad de apps Windows.
Perfiles sugeridos en Bottles:
- Application: software de oficina o utilidades.
- Gaming: solo para juegos que no esten soportados por Steam/Proton o Heroic/Lutris.

Componentes base ya preparados por el script:
- Wine (64/32), winetricks y librerias Vulkan/OpenGL i386.
- Fuentes y utilidades de extraccion de instaladores.
- Permisos base de Flatpak para Bottles.

Flujo recomendado:
1. Priorizar gaming nativo Linux (Steam/Proton, Heroic, Lutris).
2. Usar Bottles para apps Windows no-juego o casos puntuales.
3. Dentro de Bottles, instalar dependencias por app (VC++/.NET/DXVK) segun necesidad.
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
