#!/usr/bin/env bash

# Stack de desarrollo: build tools, VS Code, contenedores y utilidades CLI.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

DEV_PACKAGES=(
  build-essential pkg-config libssl-dev git-lfs gh terminator tmux
  fzf ripgrep fd-find bat exa httpie mkcert
  code docker-ce docker-ce-cli containerd.io docker-compose-plugin
  podman podman-docker
)

install_fnm_node() {
  local fnm_dir="${TARGET_HOME}/.local/share/fnm"
  if [[ -d "${fnm_dir}" ]]; then
    log "SKIP" "fnm ya instalado"
    return 0
  fi

  run_cmd sudo -u "${TARGET_USER}" bash -c 'curl -fsSL https://fnm.vercel.app/install | bash'

  if ! grep -q 'OMNI-MODULAR-FNM' "${TARGET_HOME}/.bashrc" 2>/dev/null; then
    cat >> "${TARGET_HOME}/.bashrc" <<'EOF'
# OMNI-MODULAR-FNM
export FNM_DIR="$HOME/.local/share/fnm"
[ -s "$FNM_DIR/fnm.sh" ] && source "$FNM_DIR/fnm.sh"
EOF
  fi

  run_cmd sudo -u "${TARGET_USER}" bash -lc 'source ~/.bashrc && fnm install --lts && fnm use --lts && npm i -g pnpm'
}

configure_docker_access() {
  if command -v docker >/dev/null 2>&1; then
    run_cmd usermod -aG docker "${TARGET_USER}"
    run_cmd systemctl enable --now docker
    log "OK" "Docker habilitado y usuario agregado al grupo docker"
  fi
}

main() {
  require_root
  detect_target_user
  apt_update

  for pkg in "${DEV_PACKAGES[@]}"; do
    apt_install_if_missing "${pkg}"
  done

  configure_docker_access
  install_fnm_node
  log "OK" "Modulo dev completado"
}

main "$@"
