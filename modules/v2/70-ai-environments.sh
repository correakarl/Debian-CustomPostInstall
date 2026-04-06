#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ai_minimal_essential_packages() {
  echo "python3 python3-venv python3-pip python3-dev python3-numpy python3-scipy python3-pandas python3-matplotlib python3-sklearn ipython3 git git-lfs"
}

ai_bundle_packages() {
  local bundle="$1"
  case "${bundle}" in
    ml-core)
      # Extra de productividad para flujo ML clasico.
      echo "python3-joblib python3-numexpr"
      ;;
    dl-runtime)
      # Dependencias frecuentes para pipelines de DL sin GPU propietaria.
      echo "python3-h5py python3-pil python3-tqdm"
      ;;
    agents-stack)
      # Base para clientes API/automatizaciones de agentes.
      echo "python3-requests python3-yaml"
      ;;
    *)
      echo ""
      ;;
  esac
}

configure_ai_runtime_notes() {
  local bundles_csv="$1"
  local notes_file="${TARGET_HOME}/.ai-runtime-notes.txt"

  cat > "${notes_file}" <<EOF
Entorno AI/ML base instalado.

Bundles seleccionados:
${bundles_csv}

Siguientes pasos recomendados:
1) Crear venv por proyecto: python3 -m venv .venv
2) Activar venv: source .venv/bin/activate
3) Actualizar pip: python -m pip install --upgrade pip
4) Instalar libs por proyecto (torch, transformers, etc.) segun necesidad real.

Verificacion rapida:
- python3 --version
- python3 -c "import numpy, pandas, sklearn; print('ok')"
EOF

  run_cmd chown "${TARGET_USER}:${TARGET_USER}" "${notes_file}"
}

module_ai_environments() {
  local bundles_csv="${1:-ml-core}"
  log "INFO" "Modulo v2: ai-environments (bundles=${bundles_csv})"

  local pkg
  for pkg in $(ai_minimal_essential_packages); do
    apt_install "${pkg}"
  done

  local bundle
  IFS=',' read -ra __bundles <<< "${bundles_csv}"
  for bundle in "${__bundles[@]}"; do
    case "${bundle}" in
      ml-core|dl-runtime|agents-stack)
        for pkg in $(ai_bundle_packages "${bundle}"); do
          apt_install "${pkg}"
        done
        ;;
      *)
        log "WARN" "Bundle AI no reconocido: ${bundle}"
        ;;
    esac
  done

  configure_ai_runtime_notes "${bundles_csv}"
  log "OK" "Modulo v2 ai-environments completado"
}
