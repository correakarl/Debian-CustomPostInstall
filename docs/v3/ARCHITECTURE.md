# Arquitectura V3

## Objetivo

V3 es un flujo declarativo y no interactivo, orientado a automatizacion reproducible con catalogo JSON hardware-aware.

Enfasis:

- install/check-fix/verify en una sola interfaz
- verify-category para auditoria puntual
- deteccion de capacidades del sistema
- priorizacion por fuentes (flatpak, managers, docker, apt)
- salida resumida con codigos de retorno utiles para CI/manual

Restriccion obligatoria:

- no modificar ni reemplazar kernel

## Componente principal

- Orquestador: [post-install-v3.sh](../../post-install-v3.sh)

V3 usa por defecto:

- catalogo: [config/app-library-v2.json](../../config/app-library-v2.json)
- log runtime: ./.runtime-logs/debian-postinstall-v3.log

## Interfaz CLI

Uso:

- ./post-install-v3.sh [opciones]
- ./post-install-v3.sh [perfil] [dry-run] (modo legado)

Opciones:

- --action <install|check-fix|verify|verify-category>
- --profile <nombre>
- --category <nombre> (requerido en verify-category)
- --catalog-json <ruta>
- --dry-run
- --list-profiles
- --list-categories
- --help

## Modelo de ejecucion

Pipeline principal:

1. parse_args
2. check_prerequisites
3. detect_capabilities
4. resolucion de categorias
5. ejecucion por categoria
6. resumen final + codigo de salida

Categorias objetivo:

- install/check-fix/verify: categorias del perfil
- verify-category: solo la categoria indicada

## Acciones

### install

- instala faltantes por categoria
- ejecuta pre-actions de perfil cuando aplican
- procesa post-actions por categoria
- ejecuta limpieza final

### check-fix

- mismo flujo base de install
- pensado para recuperar faltantes/desalineaciones
- mantiene resumen de fallos de instalacion

### verify

- no instala ni limpia
- audita paquetes/apps faltantes del perfil
- retorna codigo 2 si hay faltantes

### verify-category

- no instala ni limpia
- audita faltantes solo en categoria objetivo
- requiere --category
- retorna codigo 2 si hay faltantes

## Deteccion de capacidades

V3 evalua capability_detectors desde catalogo y llena un mapa CAPABILITIES.

Ejemplos de capacidades:

- gpu_vendor
- ram_total_gb
- storage_free_gb
- cpu_cores_threads
- cpu_features

Reglas soportadas en condiciones:

- cap:true/false
- cap:>=N
- cap:<=N
- cpu_features con vmx|svm

Uso operativo:

- filtrar conditional_packages
- ajustar instalacion a hardware real

## Estrategia de fuentes y deduplicacion

Orden de trabajo por categoria:

1. Flatpak
2. Managers
3. Docker
4. APT

Deduplicacion:

- consulta duplicate_registry del catalogo
- bloquea APT cuando el equivalente Flatpak preferido ya esta instalado

## Estructura del catalogo usada por V3

Claves requeridas:

- usage_profiles.<perfil>.include_categories
- categories.<categoria>.packages.flatpak
- categories.<categoria>.packages.managers
- categories.<categoria>.packages.docker
- categories.<categoria>.packages.apt
- categories.<categoria>.conditional_packages
- categories.<categoria>.post_actions
- capability_detectors
- duplicate_registry

Notas:

- packages.apt admite array u objeto con subgrupos
- conditional_packages se filtra por source=apt y requires_any

## Post-actions soportadas en V3

Actualmente mapeadas:

- enable_i386_architecture
- configure_docker_user_group
- apply_sysctl_optimizations
- enable_zram_with_adaptive_size
- configure_earlyoom_thresholds
- setup_timeshift_auto_snapshots
- configure_steam_proton_experimental (solo nota)

Si aparece una accion no mapeada, se reporta WARN y se omite.

## Codigos de salida

- 0: ejecucion correcta
- 1: error de validacion/entrada/perfil-categoria invalida
- 2: verify o verify-category con faltantes
- 3: check-fix con fallos de instalacion

## Logging

Salida:

- consola + append en ./.runtime-logs/debian-postinstall-v3.log

Resumen final:

- presentes
- faltantes
- fallos_instalacion

## Ejemplos recomendados

Instalacion perfil desktop:

- ./post-install-v3.sh --action install --profile general_desktop

Correccion perfil developer:

- ./post-install-v3.sh --action check-fix --profile developer_fullstack

Auditoria de perfil:

- ./post-install-v3.sh --action verify --profile gaming_enthusiast --dry-run

Auditoria de categoria puntual:

- ./post-install-v3.sh --action verify-category --category optimization_base --dry-run

Descubrimiento de inventario:

- ./post-install-v3.sh --list-profiles
- ./post-install-v3.sh --list-categories

## Riesgos operativos conocidos

- algunos paquetes pueden no existir en repos activos (se registran como faltantes)
- managers externos dependen de conectividad y origen remoto
- docker requiere permisos/grupo y puede necesitar re-login

## Troubleshooting rapido

- Categoria invalida:
  - ejecutar --list-categories y corregir typo
- Perfil invalido:
  - ejecutar --list-profiles
- Catalogo invalido:
  - validar JSON con jq y ruta de --catalog-json
- Verify con retorno 2:
  - revisar faltantes y decidir install o check-fix

## Validacion minima recomendada

- bash -n post-install-v3.sh
- smoke: --help, --list-profiles, --list-categories
- verify-category en una categoria real
- revision del log v3 generado
