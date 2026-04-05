#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

install_profile_packages() {
  local profile="$1"

  local apt_list
  apt_list="$(profile_packages_apt "${profile}")"
  local flatpak_list
  flatpak_list="$(profile_packages_flatpak "${profile}")"

  if [[ -z "${apt_list}" && -z "${flatpak_list}" ]]; then
    log "WARN" "Perfil sin paquetes definidos: ${profile}"
    return 0
  fi

  for pkg in ${apt_list}; do
    apt_install "${pkg}"
  done

  if [[ -n "${flatpak_list}" ]]; then
    ensure_flatpak
    for app in ${flatpak_list}; do
      install_flatpak_app "${app}"
    done
  fi
}

configure_dev_runtime() {
  local profile="$1"

  if [[ "${profile}" == "dev-web" || "${profile}" == "dev-app" || "${profile}" == "dev-mobile" ]]; then
    if command -v docker >/dev/null 2>&1; then
      run_cmd usermod -aG docker "${TARGET_USER}"
      run_cmd systemctl enable --now docker || true
    fi

    if [[ ! -d "${TARGET_HOME}/.local/share/fnm" ]]; then
      run_cmd sudo -u "${TARGET_USER}" bash -c 'curl -fsSL https://fnm.vercel.app/install | bash'
      append_once "POSTINSTALL_V2_FNM" "${TARGET_HOME}/.bashrc" "# POSTINSTALL_V2_FNM\nexport FNM_DIR=\"\$HOME/.local/share/fnm\"\n[ -s \"\$FNM_DIR/fnm.sh\" ] && source \"\$FNM_DIR/fnm.sh\""
      run_cmd sudo -u "${TARGET_USER}" bash -lc 'source ~/.bashrc && fnm install --lts && fnm use --lts && npm i -g pnpm'
    fi
  fi
}

module_dev_environments() {
  local profile="$1"
  log "INFO" "Modulo v2: dev-environments (${profile})"
  install_profile_packages "${profile}"
  configure_dev_runtime "${profile}"
  log "OK" "Modulo v2 dev-environments completado"
}
