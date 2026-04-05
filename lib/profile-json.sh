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
