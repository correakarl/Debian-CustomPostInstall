#!/usr/bin/env bash

# Multimedia y comunicacion: codecs, players y apps Flatpak comunes.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

MULTIMEDIA_PACKAGES=(vlc mpv ffmpeg libavcodec-extra)

main() {
  require_root
  detect_target_user
  apt_update

  for pkg in "${MULTIMEDIA_PACKAGES[@]}"; do
    apt_install_if_missing "${pkg}"
  done

  ensure_flatpak
  install_flatpak_app com.spotify.Client
  install_flatpak_app com.discordapp.Discord
  install_flatpak_app md.obsidian.Obsidian
  install_flatpak_app io.github.mimbrero.WhatsAppDesktop

  log "OK" "Modulo multimedia completado"
}

main "$@"
