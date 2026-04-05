#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

install_gaming_base() {
  local pkgs=(
    steam gamemode libgamemode0 mangohud vulkan-tools
    mesa-vulkan-drivers libgl1-mesa-dri
    gamescope
  )

  for pkg in "${pkgs[@]}"; do
    apt_install "${pkg}"
  done
}

install_gaming_flatpaks() {
  ensure_flatpak
  install_flatpak_app com.valvesoftware.Steam
  install_flatpak_app com.heroicgameslauncher.hgl
  install_flatpak_app net.lutris.Lutris
  install_flatpak_app org.freedesktop.Platform.VulkanLayer.MangoHud
}

configure_gaming_tweaks() {
  if command -v systemctl >/dev/null 2>&1; then
    run_cmd systemctl enable --now gamemoded || true
  fi

  local hint_file="${TARGET_HOME}/.local/share/postinstall-v2-gaming.txt"
  mkdir -p "$(dirname "${hint_file}")"
  cat > "${hint_file}" <<'EOF'
Gaming nativo recomendado (sin Bottles para ruta principal):
1. Steam + Proton para biblioteca principal.
2. Heroic/Lutris para Epic, GOG y launchers alternativos.
3. MangoHud y gamemode para telemetria y rendimiento.

Tips:
- Steam Launch Options: gamemoderun %command%
- MangoHud: MANGOHUD=1 %command%
EOF
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local/share"
}

module_gaming_native() {
  log "INFO" "Modulo v2: gaming-native"
  install_gaming_base
  install_gaming_flatpaks
  configure_gaming_tweaks
  log "OK" "Modulo v2 gaming-native completado"
}
