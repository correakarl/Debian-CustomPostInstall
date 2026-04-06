#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

detect_gpu_vendor_v2() {
  local vendor
  vendor="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | grep -oiE 'nvidia|amd|intel' | head -n1 | tr '[:upper:]' '[:lower:]' || true)"
  if [[ -z "${vendor}" ]]; then
    echo "none"
  else
    echo "${vendor}"
  fi
}

normalize_gpu_profile_v2() {
  local requested="$1"
  case "${requested,,}" in
    auto|intel|amd|nvidia|none)
      echo "${requested,,}"
      ;;
    *)
      log "WARN" "GPU profile no reconocido: ${requested}. Se usara auto"
      echo "auto"
      ;;
  esac
}

normalize_gpu_purpose_v2() {
  local requested="$1"
  case "${requested,,}" in
    general|gaming|design|ai)
      echo "${requested,,}"
      ;;
    *)
      log "WARN" "GPU purpose no reconocido: ${requested}. Se usara general"
      echo "general"
      ;;
  esac
}

resolve_gpu_purpose_from_profile_v2() {
  local profile="$1"
  case "${profile}" in
    gaming)
      echo "gaming"
      ;;
    creator)
      echo "design"
      ;;
    ai-ml)
      echo "ai"
      ;;
    *)
      echo "general"
      ;;
  esac
}

gpu_packages_for_v2() {
  local vendor="$1"
  local purpose="$2"

  case "${vendor}:${purpose}" in
    intel:general) echo "mesa-utils vainfo intel-media-va-driver-non-free" ;;
    intel:gaming) echo "vulkan-tools mesa-vulkan-drivers mangohud" ;;
    intel:design) echo "vulkan-tools mesa-vulkan-drivers" ;;
    intel:ai) echo "clinfo ocl-icd-libopencl1" ;;

    amd:general) echo "mesa-utils vainfo firmware-amd-graphics" ;;
    amd:gaming) echo "vulkan-tools mesa-vulkan-drivers mangohud" ;;
    amd:design) echo "vulkan-tools mesa-vulkan-drivers" ;;
    amd:ai) echo "clinfo ocl-icd-libopencl1" ;;

    nvidia:general) echo "nvidia-detect mesa-utils" ;;
    nvidia:gaming) echo "vulkan-tools mangohud" ;;
    nvidia:design) echo "vulkan-tools" ;;
    nvidia:ai) echo "clinfo ocl-icd-libopencl1" ;;

    *) echo "" ;;
  esac
}

module_gpu_profiles_v2() {
  local profile="$1"
  local requested_gpu_profile="$2"
  local requested_gpu_purpose="$3"

  local effective_profile
  effective_profile="$(normalize_gpu_profile_v2 "${requested_gpu_profile}")"

  local effective_purpose
  if [[ -z "${requested_gpu_purpose}" || "${requested_gpu_purpose}" == "auto" ]]; then
    effective_purpose="$(resolve_gpu_purpose_from_profile_v2 "${profile}")"
  else
    effective_purpose="$(normalize_gpu_purpose_v2 "${requested_gpu_purpose}")"
  fi

  local vendor
  if [[ "${effective_profile}" == "auto" ]]; then
    vendor="$(detect_gpu_vendor_v2)"
  else
    vendor="${effective_profile}"
  fi

  log "INFO" "GPU profile: vendor=${vendor} purpose=${effective_purpose}"

  if [[ "${vendor}" == "none" ]]; then
    log "SKIP" "No se detecto GPU compatible para aplicar perfil"
    return 0
  fi

  local pkg
  for pkg in $(gpu_packages_for_v2 "${vendor}" "${effective_purpose}"); do
    apt_install "${pkg}"
  done

  if [[ "${vendor}" == "nvidia" ]]; then
    log "INFO" "Nota: para drivers propietarios NVIDIA validar manualmente politica de kernel antes de instalar nvidia-driver"
  fi
}
