#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

flatpak_app_ready_for_dedupe_v2() {
  local app_id="$1"
  if ! command -v flatpak >/dev/null 2>&1; then
    return 1
  fi

  if ! flatpak list --app --columns=application 2>/dev/null | grep -q "^${app_id}$"; then
    return 1
  fi

  local desktop_global desktop_user
  desktop_global="/var/lib/flatpak/exports/share/applications/${app_id}.desktop"
  desktop_user="${TARGET_HOME}/.local/share/flatpak/exports/share/applications/${app_id}.desktop"
  [[ -f "${desktop_global}" || -f "${desktop_user}" ]]
}

purge_office_duplicates_conservative_v2() {
  local app_id="org.libreoffice.LibreOffice"

  if ! flatpak_app_ready_for_dedupe_v2 "${app_id}"; then
    log "SKIP" "No aplica purga LibreOffice APT: Flatpak no operativo/exportado"
    return 0
  fi

  local apt_candidates
  if command -v jq >/dev/null 2>&1 && [[ -f "${APP_CATALOG_JSON:-}" ]]; then
    apt_candidates="$(jq -r '.duplicates[]? | select(.name=="libreoffice") | .apt_packages[]?' "${APP_CATALOG_JSON}" | paste -sd ' ' -)"
  else
    apt_candidates="libreoffice-common libreoffice-core libreoffice-writer libreoffice-calc libreoffice-impress"
  fi

  local purged=0 pkg
  for pkg in ${apt_candidates}; do
    if pkg_installed "${pkg}"; then
      apt_purge_if_installed "${pkg}" || true
      purged=$((purged + 1))
    fi
  done

  if [[ "${purged}" -gt 0 ]]; then
    log "OK" "LibreOffice APT purgado de forma conservadora (paquetes: ${purged})"
  else
    log "SKIP" "Sin paquetes LibreOffice APT que purgar"
  fi
}

schedule_xfce_fixes_on_login_v2() {
  local script_path="${TARGET_HOME}/.local/bin/postinstall-v2-xfce-fixes-on-login.sh"
  local autostart_dir="${TARGET_HOME}/.config/autostart"
  local desktop_path="${autostart_dir}/postinstall-v2-xfce-fixes.desktop"
  local pending_dir="${TARGET_HOME}/.config/postinstall-v2"
  local pending_marker="${pending_dir}/xfce-fixes.pending"

  run_cmd mkdir -p "${TARGET_HOME}/.local/bin" "${autostart_dir}" "${pending_dir}"
  : > "${pending_marker}"
  chown "${TARGET_USER}:${TARGET_USER}" "${pending_marker}"

  cat > "${script_path}" <<'EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

pending_marker="$HOME/.config/postinstall-v2/xfce-fixes.pending"
if [[ ! -f "${pending_marker}" ]]; then
  exit 0
fi

if command -v xfconf-query >/dev/null 2>&1; then
  xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/presentation-mode -n -t bool -s true || true
  xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -n -t bool -s false || true
  xfconf-query -c xfce4-screensaver -p /saver/enabled -n -t bool -s false || true
fi

rm -f "${pending_marker}" || true
rm -f "$HOME/.config/autostart/postinstall-v2-xfce-fixes.desktop" || true
EOF

  chmod +x "${script_path}"
  chown "${TARGET_USER}:${TARGET_USER}" "${script_path}"

  cat > "${desktop_path}" <<EOF
[Desktop Entry]
Type=Application
Name=PostInstall V2 XFCE Fixes (one-shot)
Exec=${script_path}
X-GNOME-Autostart-enabled=true
OnlyShowIn=XFCE;
NoDisplay=true
EOF

  chown "${TARGET_USER}:${TARGET_USER}" "${desktop_path}"

  local profile_fallback
  profile_fallback=$(cat <<'EOF'
# POSTINSTALL_V2_XFCE_FIXES_FALLBACK
if [[ -f "$HOME/.config/postinstall-v2/xfce-fixes.pending" ]] && [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]]; then
  "$HOME/.local/bin/postinstall-v2-xfce-fixes-on-login.sh" >/dev/null 2>&1 || true
fi
EOF
)
  append_once "POSTINSTALL_V2_XFCE_FIXES_FALLBACK" "${TARGET_HOME}/.profile" "${profile_fallback}"
  chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.profile"

  log "INFO" "Fixes XFCE programados para siguiente inicio de sesion grafica"
}

install_ux_packages() {
  local pkgs=(
    fonts-firacode fonts-noto fonts-noto-color-emoji
    papirus-icon-theme arc-theme
    xdg-user-dirs xdg-utils
    pavucontrol gvfs-backends
  )

  if [[ "${DESKTOP_ENV}" =~ [Xx][Ff][Cc][Ee] ]] || pkg_installed xfce4-session; then
    pkgs+=(xfce4-goodies xfce4-power-manager xfce4-power-manager-plugins xfce4-screensaver)
  fi

  for pkg in "${pkgs[@]}"; do
    apt_install "${pkg}"
  done
}

apply_desktop_environment_fixes_v2() {
  log "INFO" "Aplicando fixes de energia/desktop para XFCE"

  purge_office_duplicates_conservative_v2

  if [[ "${DESKTOP_ENV}" =~ [Xx][Ff][Cc][Ee] ]] || pkg_installed xfce4-session; then
    if command -v xfconf-query >/dev/null 2>&1; then
      local user_uid user_bus
      user_uid="$(id -u "${TARGET_USER}" 2>/dev/null || true)"
      if [[ -n "${user_uid}" ]]; then
        user_bus="unix:path=/run/user/${user_uid}/bus"

        if [[ -S "/run/user/${user_uid}/bus" ]]; then
          run_cmd sudo -u "${TARGET_USER}" env DBUS_SESSION_BUS_ADDRESS="${user_bus}" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/presentation-mode -n -t bool -s true || true
          run_cmd sudo -u "${TARGET_USER}" env DBUS_SESSION_BUS_ADDRESS="${user_bus}" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -n -t bool -s false || true
          run_cmd sudo -u "${TARGET_USER}" env DBUS_SESSION_BUS_ADDRESS="${user_bus}" xfconf-query -c xfce4-screensaver -p /saver/enabled -n -t bool -s false || true
          log "OK" "Preferencias XFCE de energia/bloqueo aplicadas"
        else
          log "SKIP" "Sesion grafica no activa; se programa aplicacion diferida de xfconf"
          schedule_xfce_fixes_on_login_v2
        fi
      else
        log "SKIP" "No se pudo resolver UID de usuario para xfconf"
      fi
    else
      log "SKIP" "xfconf-query no disponible"
    fi

    run_cmd mkdir -p /etc/systemd/logind.conf.d
    cat > /etc/systemd/logind.conf.d/90-postinstall-v2-power.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
    run_cmd systemctl restart systemd-logind || true
    log "OK" "Override de logind aplicado (tapa/inactividad)"

    apt_purge_if_installed light-locker || true
  else
    log "SKIP" "XFCE no detectado; se omiten ajustes específicos"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    run_cmd update-desktop-database || true
  fi
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
  apply_desktop_environment_fixes_v2
  configure_de_hints
  log "OK" "Modulo v2 ux-light completado"
}
