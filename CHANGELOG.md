# Changelog

Todos los cambios relevantes del proyecto se documentan en este archivo.

Formato basado en Keep a Changelog y versionado semantico (SemVer).

## [Unreleased]

### Added
- V3: Nuevo flujo operativo con acciones `install`, `check-fix` y `verify` para unificar instalacion y comprobacion en un mismo script.
- V3: Nueva accion `verify-category` con parametro `--category` para auditar una categoria puntual con paridad funcional mas cercana a V2.
- V3: Nueva opcion `--list-categories` para descubrir categorias del catalogo directamente desde CLI.
- Catalogo: Se agrega bloque `v3_optimized` con `option_groups`, `usage_categories`, `capability_detectors` y `package_constraints` para habilitar instalacion condicionada por hardware en futura V3.
- Catalogo: Nuevos `task_bundles` `sys_admin` (mantenimiento/recuperacion) y `productivity_plus` (captura/audio/bluetooth) en `config/app-library.json`.
- V2: Nuevo perfil `ai-ml` para entorno de IA (ML/DL/agentes) con base esencial.
- V2: Nuevo modulo `modules/v2/70-ai-environments.sh` para instalar stacks IA por bundles.
- V2: Nuevo parametro `--ai-bundles` y selector interactivo de bundles (`ml-core`, `dl-runtime`, `agents-stack`).
- V2: Nueva accion `verify` para comprobar integridad de perfil, paquetes faltantes y compatibilidad.
- V2: Nueva categoria `ai-environments` para purga por categoria.
- V2: Nueva accion `verify-category` para auditar estado de paquetes/apps por categoria.
- V2: Nueva accion `clean-duplicates` para limpieza de duplicados basada en biblioteca JSON.
- V2: Nueva biblioteca [config/app-library.json](config/app-library.json) con fuentes, catalogo por categoria y reglas de duplicados.
- V2: Nuevo modulo [modules/v2/80-gpu-profiles.sh](modules/v2/80-gpu-profiles.sh) para perfilado GPU por tipo y proposito.
- Nueva libreria compartida [lib/app-catalog.sh](lib/app-catalog.sh) para resolver perfiles/categorias desde JSON en V1 y V2.
- V1: Nueva categoria `ai_environments` para stack IA/ML/agentes en el flujo monolitico.
- V1: Nueva opcion de `Verificar por categoria` para auditoria por modulo.
- V1: Nueva opcion `Limpiar duplicados (BD apps)` basada en catalogo JSON.
- V1: Nueva opcion para eliminar cron de mantenimiento instalado por el aplicativo.
- V1: Perfilado GPU por categoria de uso (general/gaming/design/ai) con deteccion de vendor.
- V2: Nueva accion `remove-cron` para eliminar cron/script de mantenimiento instalado por V2.
- Proyecto: Archivo `LICENSE` (CC BY 4.0) y `NOTICE` para formalizar licencia y atribucion.

### Changed
- V3: `post-install-v3.sh` ahora usa rutas robustas basadas en `ROOT_DIR`, valida JSON de catalogo al inicio y soporta CLI con `--action`, `--profile`, `--catalog-json`, `--dry-run` y `--list-profiles`.
- V3: Script marcado como ejecutable para permitir invocacion directa `./post-install-v3.sh`.
- V3: Se corrige evaluacion de capacidades para detectores no booleanos (ej. `gpu_vendor`) y se mejora parseo de paquetes APT para estructuras array/objeto del catalogo.
- V3: Se corrige la logica de `enable_i386_architecture` en `dry-run` para evitar cambios reales no deseados y se agrega fase de `pre_actions_global` por perfil.
- V3: Se agrega resumen final de verificacion (`presentes/faltantes/fallos_instalacion`) y codigos de salida diferenciados para `verify` y `check-fix`.
- Catalogo: `task_bundles.sys_admin` y `task_bundles.productivity_plus` ahora incluyen `conditional_apt` para casos dependientes de capacidad (ej. Bluetooth/SMART).
- Biblioteca JSON actualizada a `1.1.3` para base de organizacion V3-Optimized hardware-aware.
- Biblioteca JSON actualizada a `1.1.2` para incluir nuevos bundles operativos (`sys_admin`, `productivity_plus`).
- V1/V2: cada ejecucion ahora registra marcas `[RUN-START]` y `[RUN-END]` con timestamp, PID, codigo de salida y duracion para trazabilidad de inicio/fin del proceso actual.
- V2: se agrega rotacion automatica de logs (`./.runtime-logs`) por cantidad y tamano total para evitar crecimiento de disco en ejecuciones frecuentes de `check-fix`.
- V1: archivo de estado `debian-postinstall-status.log` se recorta automaticamente a las ultimas 4000 lineas para controlar uso de disco.
- V1/V2: logs de cron de mantenimiento se recortan de forma preventiva cuando superan 5MB.
- V1/V2: logs de ejecucion/error y estado se redirigen a carpeta local del proyecto `./.runtime-logs/` (no versionada) en lugar de `/var/log`; incluye logs de cron de mantenimiento.
- Biblioteca JSON actualizada a `1.1.1` con metadata de `sources.third_party_optional` para paquetes que dependen de repos externos opcionales.
- V1 y V2 ahora muestran menus largos en columnas para reducir scroll en asistente interactivo.
- V2 recupera spinner de progreso en `apt update`, instalacion/reinstalacion APT e instalacion Flatpak.
- V1 limita hooks PRE/POST a una sola ejecucion por operacion de lote para evitar tareas post-instalacion redundantes.
- V2 evita post-acciones redundantes en `install/configure` (`desktop_fixes`, `ai_runtime_notes`, `dedupe_from_catalog`) cuando no aplican al flujo actual.
- V1 corrige parseo defensivo de listas de paquetes/flatpak desde catalogo para evitar tokens JSON (`[`, `]`, `,`, `"`) en instalacion por modulo.
- V1 deja de ejecutar dedupe de LibreOffice dentro del hardening UX general para no afectar categorias no relacionadas (ej. virtualization).
- V1/V2 mejoran diagnostico de `REPO:MISSING` consultando `/var/log/apt/history.log` cuando existe evidencia de instalaciones previas.
- Catalogo `sources.apt` actualizado a endpoints oficiales Debian por canal (`main`, `security`, `updates`).
- V1/V2: validacion/instalacion de paquetes ahora es estricta por fuente (APT se evalua por `dpkg`, Flatpak por `flatpak list`) para evitar falsos positivos entre fuentes mixtas.
- V1/V2: snapshot autogenerado ahora es condicional a acciones mutantes; salir sin ejecutar cambios no dispara snapshot ni post-procesos innecesarios.
- Se agrega diagrama de flujo integral en `docs/flows/debian-postinstall-full-flow.drawio` (V1/V2, rutas de error y guardas de robustez).
- V2: El menu interactivo incorpora opcion de verificacion de integridad y paso adicional de bundles para perfil `ai-ml`.
- V2: El pipeline `full`/`configure` ejecuta modulo AI cuando el perfil seleccionado es `ai-ml`.
- V2: El pipeline `full`/`configure` aplica perfilado GPU por categoria de uso (gaming/diseno/ai/general).
- V2: El modulo dev-environments ahora anuncia plan de instalacion por fuente (APT/Flatpak).
- V2: `install` y `configure` ahora ejecutan acciones declarativas `pre/post` desde catalogo JSON mediante allowlist segura (`desktop_fixes`, `gpu_profile`, `ai_runtime_notes`, `dedupe_from_catalog`).
- V2: `clean-duplicates` y `desktop_fixes` pasan a modo conservador para Office: solo purgan APT si el Flatpak preferido esta realmente operativo/exportado y omiten paquetes APT en `hold`.
- V2: Se agrega fallback diferido para `xfconf` via autostart one-shot cuando no existe sesion grafica activa (sin DBus de usuario disponible).
- V2: Se agrega fallback secundario en login de usuario (`.profile` + marcador pendiente) para no depender unicamente de autostart XDG.
- V1/V2: instalacion APT y Flatpak ahora valida disponibilidad en repos/remotos antes de instalar; paquetes/apps no resolubles se omiten con trazabilidad (`[REPO:MISSING]`, `[FLATPAK:MISSING]`) para evitar fallos de flujo.
- V1: El instalador por modulo ahora muestra plan de instalacion por fuente (APT/Flatpak).
- V1: Menus y arrays de categorias alineados con nueva categoria AI para mantener paridad funcional.
- Biblioteca JSON de apps normalizada a v1.1.0 para separar base esencial, reemplazos Debian 13 y paquetes opcionales pesados por categoria.
- V1 y V2 ahora resuelven perfiles/categorias desde `config/app-library.json` usando `lib/app-catalog.sh` como origen comun.
- V1 reduce duplicidad interna de matrices en procesos de install/check/remove/verify usando registro unificado de modulos.
- V2 centraliza listado de categorias en una sola constante para reducir divergencias.

### Fixed
- V2: `parse_args` ahora valida opciones que requieren valor (`--catalog-json`, `--profile`, etc.) y muestra error de uso en lugar de abortar con `variable sin asignar` cuando falta el argumento.
- V3: `--category` ahora tambien filtra ejecucion en `install`, `check-fix` y `verify` (no solo en `verify-category`), evitando que se procesen categorias adicionales del perfil cuando se solicita una categoria puntual.
- V3: cuando se usa `--category` explicita en `install`, `check-fix` o `verify`, se permite ejecutar categorias validas aunque no pertenezcan al `--profile` actual (se registra advertencia en log en lugar de abortar).
- V3: `check-fix` ahora resuelve aliases de paquetes APT no instalables en Debian (`ionice`->`util-linux`, `journalctl`->`systemd`, `cpupower-utils`->`linux-cpupower`) y omite con traza `[REPO:MISSING]` los paquetes no disponibles en repos, evitando falsos fallos de instalacion.
- V3: se mapea la post-accion `enable_fwupd_refresh_timer` para eliminar advertencias de accion no implementada en `optimization_base`.
- Catalogo V3 (`config/app-library-v2.json`): se corrigen paquetes de `optimization_base` para Debian Trixie (`util-linux`, `linux-cpupower`, `systemd`).
- V3: deduplicacion cruzada APT/Flatpak en ambos sentidos por categoria (registro de duplicados + heuristica de equivalencia), para evitar instalar una app por una fuente cuando ya existe su equivalente en la otra.

### Docs
- Se crea documentacion exhaustiva por version: [docs/v1/ARCHITECTURE.md](docs/v1/ARCHITECTURE.md), [docs/v2/ARCHITECTURE.md](docs/v2/ARCHITECTURE.md) y [docs/v3/ARCHITECTURE.md](docs/v3/ARCHITECTURE.md).
- Se agrega guia operativa comparativa [docs/flows/VERSION-SELECTION.md](docs/flows/VERSION-SELECTION.md) con matriz de decision rapida V1/V2/V3.
- README actualiza el indice de arquitectura para cubrir V1/V2/V3.
- Documentacion actualizada con paridad V1/V2 para AI, verificacion por categoria, limpieza de duplicados y perfilado GPU.
- Archivos tocados: README.md, docs/modules.md, docs/v2/ARCHITECTURE.md, config/app-library.json.

### Internal
- Se mantuvo compatibilidad retro con `categories.<perfil>.apt/flatpak` para no romper verificadores/limpieza existentes.
- Se introdujo validacion de catalogo al inicio de V1/V2 para evitar ejecucion con metadata inconsistente.

## [8.5.0] - 2026-04-05

### Added
- V1: Nueva funcion de fixes de escritorio para endurecer comportamiento de energia y bloqueo en XFCE.
- V1: Paquetes de integracion XFCE agregados a base universal: xfce4-goodies, xfce4-power-manager, xfce4-power-manager-plugins, xfce4-screensaver, pavucontrol, gvfs-backends.
- V1: Mapeo Flatpak para Office: org.libreoffice.LibreOffice.
- V2: Nueva funcion de fixes en ux-light para aplicar ajustes anti-bloqueo en XFCE y logind.
- V2: Instalacion de paquetes UX adicionales: pavucontrol y gvfs-backends.

### Changed
- V1: Version visible del script actualizada de v8.2 a v8.5.
- V1: El modulo office en APT prioriza visores/correo y mueve LibreOffice a estrategia Flatpak-first.
- V1: Los desktop fixes se ejecutan durante configuracion de entorno y post-config de office.
- V2: Perfil workstation prioriza LibreOffice Flatpak sobre LibreOffice APT.

### Fixed
- Bloqueo/suspension fantasma en XFCE mitigado con ajustes en xfconf, desactivacion de xfce4-screensaver y override de systemd-logind para tapa/inactividad.
- Duplicidad de accesos de LibreOffice (APT + Flatpak) mitigada con purga de APT cuando existe Flatpak.
- Conflicto de lock manager reducido al purgar light-locker en flujos XFCE.

### Docs
- Documentacion actualizada para reflejar hardening XFCE, deduplicacion APT/Flatpak y set de integracion UX.
- Archivos tocados: README.md, docs/modules.md, docs/v2/ARCHITECTURE.md.

[Unreleased]: https://github.com/correakarl/Debian-CustomPostInstall/compare/v8.5.0...HEAD
[8.5.0]: https://github.com/correakarl/Debian-CustomPostInstall/releases/tag/v8.5.0
