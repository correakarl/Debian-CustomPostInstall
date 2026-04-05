#!/usr/bin/env bash

# Utilidades para auditar un perfil JSON de estado deseado.
# Este archivo es compartido por V1 y V2.

set -o nounset
set -o pipefail

json_profile_resolve_path() {
  local input_path="$1"
  local target_home="$2"

  if [[ "${input_path}" == ~/* ]]; then
    printf '%s\n' "${target_home}${input_path#~}"
    return 0
  fi

  printf '%s\n' "${input_path}"
}

json_profile_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "${value}"
}

json_profile_write_array_from_name() {
  local array_name="$1"
  local indent="$2"
  local -n ref_array="$array_name"
  local index

  printf '[\n'
  for index in "${!ref_array[@]}"; do
    printf '%s  "%s"' "${indent}" "$(json_profile_escape "${ref_array[$index]}")"
    if [[ $index -lt $((${#ref_array[@]} - 1)) ]]; then
      printf ','
    fi
    printf '\n'
  done
  printf '%s]' "${indent}"
}

json_profile_write_snapshot() {
  local output_path="$1"
  local profile_name="$2"
  local target_home="$3"
  local source_tag="$4"
  local categories_name="$5"
  local pkg_callback="$6"
  local flatpak_callback="$7"

  local -n categories_ref="$categories_name"
  local -a installed_categories=() wanted_packages=() wanted_flatpaks=() wanted_services=() wanted_files=()
  local -A seen_packages=() seen_flatpaks=()
  local category pkg app

  for category in "${categories_ref[@]}"; do
    local category_detected=false

    for pkg in $(${pkg_callback} "${category}"); do
      [[ -z "${pkg}" ]] && continue
      if dpkg -s "${pkg}" >/dev/null 2>&1; then
        category_detected=true
        if [[ -z "${seen_packages[$pkg]:-}" ]]; then
          wanted_packages+=("${pkg}")
          seen_packages[$pkg]=1
        fi
      fi
    done

    for app in $(${flatpak_callback} "${category}"); do
      [[ -z "${app}" ]] && continue
      if command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=application 2>/dev/null | grep -q "^${app}$"; then
        category_detected=true
        if [[ -z "${seen_flatpaks[$app]:-}" ]]; then
          wanted_flatpaks+=("${app}")
          seen_flatpaks[$app]=1
        fi
      fi
    done

    if [[ "${category_detected}" == "true" ]]; then
      installed_categories+=("${category}")
    fi
  done

  local service_candidates=(fstrim.timer zramswap systemd-zram-setup@zram0 earlyoom docker libvirtd ssh NetworkManager)
  local service
  for service in "${service_candidates[@]}"; do
    if systemctl is-enabled "${service}" >/dev/null 2>&1; then
      wanted_services+=("${service}")
    fi
  done

  [[ -f "${target_home}/.bashrc" ]] && wanted_files+=("~/.bashrc")
  [[ -f "${target_home}/.config/gtk-3.0/settings.ini" ]] && wanted_files+=("~/.config/gtk-3.0/settings.ini")

  mkdir -p "$(dirname "${output_path}")"

  local swappiness vfs_cache_pressure hostname
  swappiness="$(sysctl -n vm.swappiness 2>/dev/null || echo '')"
  vfs_cache_pressure="$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo '')"
  hostname="$(hostname 2>/dev/null || echo unknown-host)"

  {
    printf '{\n'
    printf '  "name": "%s",\n' "$(json_profile_escape "${profile_name}")"
    printf '  "generated_at": "%s",\n' "$(date --iso-8601=seconds)"
    printf '  "source": "%s",\n' "$(json_profile_escape "${source_tag}")"
    printf '  "host": {\n'
    printf '    "hostname": "%s",\n' "$(json_profile_escape "${hostname}")"
    printf '    "target_home": "%s"\n' "$(json_profile_escape "${target_home}")"
    printf '  },\n'
    printf '  "detected": {\n'
    printf '    "categories_installed": '
    json_profile_write_array_from_name installed_categories '    '
    printf '\n'
    printf '  },\n'
    printf '  "wanted": {\n'
    printf '    "packages": '
    json_profile_write_array_from_name wanted_packages '    '
    printf ',\n'
    printf '    "flatpaks": '
    json_profile_write_array_from_name wanted_flatpaks '    '
    printf ',\n'
    printf '    "services_enabled": '
    json_profile_write_array_from_name wanted_services '    '
    printf ',\n'
    printf '    "files_exist": '
    json_profile_write_array_from_name wanted_files '    '
    printf ',\n'
    printf '    "sysctl": {\n'
    printf '      "vm.swappiness": "%s",\n' "$(json_profile_escape "${swappiness}")"
    printf '      "vm.vfs_cache_pressure": "%s"\n' "$(json_profile_escape "${vfs_cache_pressure}")"
    printf '    }\n'
    printf '  },\n'
    printf '  "blocked_packages": [],\n'
    printf '  "notes": "Snapshot autogenerado del estado detectado tras ejecutar el script."\n'
    printf '}\n'
  } > "${output_path}"
}

json_profile_show_snapshot_summary() {
  local snapshot_path="$1"

  if [[ ! -f "${snapshot_path}" ]]; then
    echo "[SNAPSHOT] No existe snapshot previo. Se generara al finalizar esta ejecucion."
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "[SNAPSHOT] Snapshot encontrado: ${snapshot_path}"
    return 0
  fi

  local generated_at categories pkg_count flatpak_count
  generated_at="$(jq -r '.generated_at // "desconocido"' "${snapshot_path}")"
  categories="$(jq -r '.detected.categories_installed[]?' "${snapshot_path}" | paste -sd ', ' -)"
  pkg_count="$(jq -r '(.wanted.packages // []) | length' "${snapshot_path}")"
  flatpak_count="$(jq -r '(.wanted.flatpaks // []) | length' "${snapshot_path}")"

  echo "[SNAPSHOT] Archivo: ${snapshot_path}"
  echo "[SNAPSHOT] Generado: ${generated_at}"
  echo "[SNAPSHOT] Categorias detectadas: ${categories:-ninguna}"
  echo "[SNAPSHOT] Paquetes detectados: ${pkg_count} | Flatpaks detectados: ${flatpak_count}"
}

json_profile_audit() {
  local profile_json="$1"
  local target_home="$2"

  if [[ -z "${profile_json}" ]]; then
    echo "[JSON] Sin perfil JSON configurado, se omite auditoria."
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "[JSON][WARN] jq no disponible, no se puede auditar ${profile_json}."
    return 0
  fi

  if [[ ! -f "${profile_json}" ]]; then
    echo "[JSON][WARN] Archivo JSON no encontrado: ${profile_json}"
    return 0
  fi

  if ! jq empty "${profile_json}" >/dev/null 2>&1; then
    echo "[JSON][WARN] JSON invalido: ${profile_json}"
    return 0
  fi

  local profile_name
  profile_name="$(jq -r '.name // "perfil-sin-nombre"' "${profile_json}")"
  echo "[JSON] Auditoria de perfil: ${profile_name}"

  local ok=0
  local missing=0
  local warn=0

  local pkg
  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    if dpkg -s "${pkg}" >/dev/null 2>&1; then
      echo "[JSON][WANT:OK] paquete ${pkg}"
      ok=$((ok + 1))
    else
      echo "[JSON][WANT:MISS] paquete ${pkg}"
      missing=$((missing + 1))
    fi
  done < <(jq -r '.wanted.packages[]?' "${profile_json}")

  local app
  while IFS= read -r app; do
    [[ -z "${app}" ]] && continue
    if command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=application 2>/dev/null | grep -q "^${app}$"; then
      echo "[JSON][WANT:OK] flatpak ${app}"
      ok=$((ok + 1))
    else
      echo "[JSON][WANT:MISS] flatpak ${app}"
      missing=$((missing + 1))
    fi
  done < <(jq -r '.wanted.flatpaks[]?' "${profile_json}")

  local svc
  while IFS= read -r svc; do
    [[ -z "${svc}" ]] && continue
    if systemctl is-enabled "${svc}" >/dev/null 2>&1; then
      echo "[JSON][WANT:OK] service enabled ${svc}"
      ok=$((ok + 1))
    else
      echo "[JSON][WANT:MISS] service enabled ${svc}"
      missing=$((missing + 1))
    fi
  done < <(jq -r '.wanted.services_enabled[]?' "${profile_json}")

  local file_item
  while IFS= read -r file_item; do
    [[ -z "${file_item}" ]] && continue
    local resolved
    resolved="$(json_profile_resolve_path "${file_item}" "${target_home}")"
    if [[ -e "${resolved}" ]]; then
      echo "[JSON][WANT:OK] file ${resolved}"
      ok=$((ok + 1))
    else
      echo "[JSON][WANT:MISS] file ${resolved}"
      missing=$((missing + 1))
    fi
  done < <(jq -r '.wanted.files_exist[]?' "${profile_json}")

  local key
  while IFS= read -r key; do
    [[ -z "${key}" ]] && continue
    local desired current
    desired="$(jq -r --arg k "${key}" '.wanted.sysctl[$k]' "${profile_json}")"
    current="$(sysctl -n "${key}" 2>/dev/null || echo "<no-disponible>")"

    if [[ "${current}" == "${desired}" ]]; then
      echo "[JSON][WANT:OK] sysctl ${key}=${current}"
      ok=$((ok + 1))
    else
      echo "[JSON][WANT:MISS] sysctl ${key} actual=${current} deseado=${desired}"
      missing=$((missing + 1))
    fi
  done < <(jq -r '.wanted.sysctl | keys[]?' "${profile_json}")

  local blocked
  while IFS= read -r blocked; do
    [[ -z "${blocked}" ]] && continue
    if dpkg -s "${blocked}" >/dev/null 2>&1; then
      echo "[JSON][BLOCKED:FOUND] ${blocked} esta instalado pero marcado como bloqueado"
      warn=$((warn + 1))
    else
      echo "[JSON][BLOCKED:OK] ${blocked} no instalado"
      ok=$((ok + 1))
    fi
  done < <(jq -r '.blocked_packages[]?' "${profile_json}")

  echo "[JSON] Resumen perfil=${profile_name} ok=${ok} missing=${missing} warn=${warn}"
}
