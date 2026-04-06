#!/usr/bin/env bash

# Matriz de perfiles de uso para V2.

set -o errexit
set -o nounset
set -o pipefail

profile_packages_apt() {
  local profile="$1"
  catalog_get_profile_apt "${APP_CATALOG_JSON}" "${profile}"
}

profile_packages_flatpak() {
  local profile="$1"
  catalog_get_profile_flatpak "${APP_CATALOG_JSON}" "${profile}"
}

print_profiles_help() {
  cat <<'EOF'
Perfiles disponibles:
  workstation  - Oficina, navegacion y productividad general
  dev-web      - Desarrollo web y contenedores
  dev-app      - Desarrollo de aplicaciones de escritorio/backend
  dev-mobile   - Entorno base para desarrollo mobile
  gaming       - Gaming nativo Linux (sin Bottles para launcher de juegos)
  creator      - Diseno y creacion multimedia
  ai-ml        - Entorno de IA para ML/DL y agentes (base minimal + bundles)
  minimal      - Entorno minimo y liviano
EOF
}

print_actions_help() {
  cat <<'EOF'
Acciones disponibles:
  install     - Instalacion normal segun perfil/modo
  check-fix   - Verifica modulo/perfil y reinstala con configuracion correctiva
  configure   - Reaplicar configuraciones (UX y ajustes base)
  reinstall   - Reinstalar perfil (remove + install)
  remove      - Borrar paquetes/apps del perfil
  remove-category - Purga por categoria sin romper categorias compartidas
  clean       - Limpieza de paquetes/artefactos no usados
  clean-obsolete - Eliminar paquetes reemplazados por opciones modernas
  clean-files - Eliminar temporales y descargas de instaladores no necesarios
  optimize    - Reaplicar optimizaciones del sistema
  updates-cron - Comprobar actualizaciones y configurar cron de mantenimiento
  remove-cron - Eliminar cron/script de mantenimiento instalado por V2
  logs        - Mostrar ultimo registro de logs
  refs        - Mostrar referencias oficiales
  health      - Mostrar panel de estado de salud
  verify      - Verificar integridad de herramientas y estado del perfil
  verify-category - Verificar integridad por categoria
  clean-duplicates - Limpiar duplicados segun biblioteca JSON de aplicaciones
EOF
}
