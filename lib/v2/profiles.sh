#!/usr/bin/env bash

# Matriz de perfiles de uso para V2.

set -o errexit
set -o nounset
set -o pipefail

profile_packages_apt() {
  local profile="$1"
  case "${profile}" in
    workstation)
      echo "code firefox-esr libreoffice-writer libreoffice-calc thunderbird gedit virtualbox openvpn wireguard-tools network-manager-openvpn network-manager-openvpn-gnome"
      ;;
    dev-web)
      echo "code build-essential git-lfs gh ripgrep fd-find fzf httpie docker-ce docker-ce-cli containerd.io docker-compose-plugin"
      ;;
    dev-app)
      echo "code build-essential cmake ninja-build clang gdb valgrind openjdk-21-jdk maven gradle virtualbox"
      ;;
    dev-mobile)
      echo "code openjdk-21-jdk android-sdk-platform-tools-adb android-sdk-platform-tools-common fastboot qemu-kvm"
      ;;
    gaming)
      echo "steam gamemode libgamemode0 mangohud vulkan-tools mesa-vulkan-drivers libgl1-mesa-dri mesa-utils"
      ;;
    creator)
      echo "code gimp inkscape krita blender kdenlive audacity ffmpeg obs-studio gedit"
      ;;
    minimal)
      echo "neovim htop tmux curl wget git"
      ;;
    *)
      echo ""
      ;;
  esac
}

profile_packages_flatpak() {
  local profile="$1"
  case "${profile}" in
    workstation)
      echo "md.obsidian.Obsidian"
      ;;
    dev-web)
      echo "com.getpostman.Postman"
      ;;
    dev-mobile)
      echo "com.google.AndroidStudio"
      ;;
    gaming)
      echo "com.heroicgameslauncher.hgl net.lutris.Lutris com.valvesoftware.Steam net.davidotek.pupgui2 org.freedesktop.Platform.VulkanLayer.MangoHud"
      ;;
    creator)
      echo "com.obsproject.Studio"
      ;;
    *)
      echo ""
      ;;
  esac
}

print_profiles_help() {
  cat <<'EOF'
Perfiles disponibles:
  workstation  - Oficina, navegacion y productividad general
  dev-web      - Desarrollo web y contenedores
  dev-app      - Desarrollo de aplicaciones de escritorio/backend
  dev-mobile   - Entorno base para desarrollo mobile
  gaming       - Gaming nativo Linux (sin Bottles para launcher de juegos)
  creator      - Diseno y creacion multimedia
  minimal      - Entorno minimo y liviano
EOF
}

print_actions_help() {
  cat <<'EOF'
Acciones disponibles:
  install     - Instalacion normal segun perfil/modo
  check-fix   - Verifica modulo/perfil y reinstala con configuracion correctiva
  configure   - Reaplicar configuraciones (UX y ajustes base)
  reinstall   - Reinstalar perfil (remove + install)
  remove      - Borrar paquetes/apps del perfil
  remove-category - Purga por categoria sin romper categorias compartidas
  clean       - Limpieza de paquetes/artefactos no usados
  clean-obsolete - Eliminar paquetes reemplazados por opciones modernas
  optimize    - Reaplicar optimizaciones del sistema
  updates-cron - Comprobar actualizaciones y configurar cron de mantenimiento
  logs        - Mostrar ultimo registro de logs
  refs        - Mostrar referencias oficiales
  health      - Mostrar panel de estado de salud
EOF
}
