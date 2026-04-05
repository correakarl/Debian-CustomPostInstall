#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

install_ux_packages() {
  local pkgs=(
    fonts-firacode fonts-noto fonts-noto-color-emoji
    papirus-icon-theme arc-theme
    xdg-user-dirs xdg-utils
  )

  for pkg in "${pkgs[@]}"; do
    apt_install "${pkg}"
  done
}

configure_generic_gtk_style() {
  mkdir -p "${TARGET_HOME}/.config/gtk-3.0"
  cat > "${TARGET_HOME}/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Arc
gtk-icon-theme-name=Papirus
gtk-font-name=Fira Code 10
gtk-application-prefer-dark-theme=0
EOF

  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config/gtk-3.0"
}

configure_windows_ubuntu_like_shell() {
  local bashrc="${TARGET_HOME}/.bashrc"
  local payload
  payload=$(cat <<'EOF'
# POSTINSTALL_V2_SHELL
alias ll='ls -lah --color=auto'
alias update='sudo apt update && sudo apt upgrade -y'
alias purge='sudo apt autoremove -y && sudo apt clean'
alias fixnet='sudo systemctl restart NetworkManager systemd-resolved 2>/dev/null || true'
alias game-on='gamemoderun %command%'

# Atajo de teclado para cambio de idioma (si hay sesion grafica)
[[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]] && setxkbmap -option grp:alt_shift_toggle 2>/dev/null || true
EOF
)

  append_once "POSTINSTALL_V2_SHELL" "${bashrc}" "${payload}"
  chown "${TARGET_USER}:${TARGET_USER}" "${bashrc}"
}

configure_de_hints() {
  log "INFO" "Ajustes de UX DE-agnosticos aplicados"
  log "INFO" "Tip: para apariencia tipo Windows/Ubuntu, aplica Arc + Papirus desde la configuracion de tu entorno"
}

module_ux_light() {
  log "INFO" "Modulo v2: ux-light"
  install_ux_packages
  configure_generic_gtk_style
  configure_windows_ubuntu_like_shell
  configure_de_hints
  log "OK" "Modulo v2 ux-light completado"
}
