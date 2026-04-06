#!/usr/bin/env bash

# Catalogo unificado de aplicaciones para V1/V2.
# Expone funciones de lectura desde JSON para evitar duplicidad en scripts.

set -o nounset
set -o pipefail

catalog_is_ready() {
  local catalog_path="$1"
  [[ -f "${catalog_path}" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq empty "${catalog_path}" >/dev/null 2>&1 || return 1
  return 0
}

catalog_require_ready_or_exit() {
  local catalog_path="$1"
  local caller_label="$2"

  if catalog_is_ready "${catalog_path}"; then
    return 0
  fi

  echo "[CATALOG][ERROR] Catalogo no disponible o invalido: ${catalog_path}" >&2
  echo "[CATALOG][ERROR] Requisitos: archivo JSON valido + jq" >&2
  echo "[CATALOG][ERROR] Caller: ${caller_label}" >&2
  exit 1
}

catalog_read_list() {
  local catalog_path="$1"
  local jq_path="$2"

  if ! catalog_is_ready "${catalog_path}"; then
    printf '%s\n' ""
    return 0
  fi

  jq -r "(${jq_path})[]?" "${catalog_path}" | paste -sd ' ' -
}

catalog_get_profile_apt() {
  local catalog_path="$1"
  local profile="$2"
  catalog_read_list "${catalog_path}" ".profiles[\"${profile}\"].apt // []"
}

catalog_get_profile_flatpak() {
  local catalog_path="$1"
  local profile="$2"
  catalog_read_list "${catalog_path}" ".profiles[\"${profile}\"].flatpak // []"
}

catalog_get_v1_category_apt() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v1_categories[\"${category}\"].apt // []"
}

catalog_get_v1_category_flatpak() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v1_categories[\"${category}\"].flatpak // []"
}

catalog_get_v2_category_apt() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v2_categories[\"${category}\"].apt // []"
}

catalog_get_v2_category_flatpak() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v2_categories[\"${category}\"].flatpak // []"
}

catalog_get_profile_pre_actions() {
  local catalog_path="$1"
  local profile="$2"
  catalog_read_list "${catalog_path}" ".profiles[\"${profile}\"].pre_actions // []"
}

catalog_get_profile_post_actions() {
  local catalog_path="$1"
  local profile="$2"
  catalog_read_list "${catalog_path}" ".profiles[\"${profile}\"].post_actions // []"
}

catalog_get_v1_category_pre_actions() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v1_categories[\"${category}\"].pre_actions // []"
}

catalog_get_v1_category_post_actions() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v1_categories[\"${category}\"].post_actions // []"
}

catalog_get_v2_category_pre_actions() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v2_categories[\"${category}\"].pre_actions // []"
}

catalog_get_v2_category_post_actions() {
  local catalog_path="$1"
  local category="$2"
  catalog_read_list "${catalog_path}" ".v2_categories[\"${category}\"].post_actions // []"
}
