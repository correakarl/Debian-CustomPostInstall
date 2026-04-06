# Arquitectura V2

## Objetivo

V2 es el flujo modular orientado a ciclo de vida completo de un equipo Debian:

- instalar por perfil/modo
- comprobar y reparar (check-fix)
- configurar/reinstalar/remover
- limpiar residuos y duplicados
- auditar integridad por perfil o categoria

Restriccion del proyecto:

- no modificar ni reemplazar kernel

## Componentes

Orquestador y librerias:

- [post-install-v2.sh](../../post-install-v2.sh)
- [lib/v2/common.sh](../../lib/v2/common.sh)
- [lib/v2/profiles.sh](../../lib/v2/profiles.sh)
- [lib/app-catalog.sh](../../lib/app-catalog.sh)
- [lib/profile-json.sh](../../lib/profile-json.sh)

Modulos V2:

- [modules/v2/10-system-core.sh](../../modules/v2/10-system-core.sh)
- [modules/v2/20-ux-light.sh](../../modules/v2/20-ux-light.sh)
- [modules/v2/30-compat-bottles.sh](../../modules/v2/30-compat-bottles.sh)
- [modules/v2/40-gaming-native.sh](../../modules/v2/40-gaming-native.sh)
- [modules/v2/50-dev-environments.sh](../../modules/v2/50-dev-environments.sh)
- [modules/v2/60-debug-clean.sh](../../modules/v2/60-debug-clean.sh)
- [modules/v2/70-ai-environments.sh](../../modules/v2/70-ai-environments.sh)
- [modules/v2/80-gpu-profiles.sh](../../modules/v2/80-gpu-profiles.sh)

## Entradas y configuracion

CLI principal:

- --action <tipo>
- --profile <nombre>
- --mode <full|utils|debug-clean>
- --category <nombre>
- --ai-bundles <ml-core,dl-runtime,agents-stack>
- --catalog-json <ruta>
- --gpu-profile <auto|intel|amd|nvidia|none>
- --gpu-purpose <auto|general|gaming|design|ai>
- --profile-json <ruta>
- --dry-run
- --non-interactive | --interactive
- --list-profiles | --list-actions

Catalogo usado en V2:

- [config/app-library.json](../../config/app-library.json)

## Perfiles soportados

Perfiles vigentes:

- workstation
- dev-web
- dev-app
- dev-mobile
- gaming
- creator
- ai-ml
- minimal

Particularidad de ai-ml:

- instala base esencial
- habilita bundles IA seleccionables
- integra validaciones de integridad especificas

## Modos de ejecucion

### full

Pipeline nominal:

- system-core
- ux-light
- compat-bottles
- gaming-native (si perfil gaming)
- dev-environments (segun perfil)
- ai-environments (si perfil ai-ml)
- gpu-profiles (segun accion/perfil)

### utils

Pipeline reducido:

- system-core
- ux-light
- utilidades minimas

### debug-clean

Pipeline de saneamiento:

- debug-clean

## Acciones soportadas

Acciones operativas:

- install
- check-fix
- configure
- reinstall
- remove
- remove-category
- clean
- clean-obsolete
- clean-files
- clean-duplicates
- optimize
- updates-cron
- remove-cron
- logs
- refs
- health
- verify
- verify-category

## Modelo de control

Secuencia general de V2:

1. parse_args y validaciones
2. validacion de catalogo y dependencias
3. modo interactivo o no interactivo
4. dispatch por accion
5. ejecucion de modulos/pipelines
6. snapshots/logs/resumen

Guardas de entrada:

- profile obligatorio para acciones que operan por perfil
- category obligatoria para remove-category/verify-category
- validacion de action contra lista cerrada

## Integridad y auditoria

### verify

- audita integridad del perfil
- revisa esperado vs instalado por fuente
- integra chequeos de compatibilidad

### verify-category

- audita una categoria puntual
- reporta faltantes APT/Flatpak
- evita ruido de otras categorias

### profile-json

- valida estado deseado definido por JSON
- util para compliance interno y repetibilidad

## Reglas de deduplicacion

Fuente de verdad:

- duplicate_registry dentro de [config/app-library.json](../../config/app-library.json)

Accion dedicada:

- clean-duplicates

Comportamiento:

- respeta fuente preferida
- evita remover variante activa en uso
- aplica estrategia conservadora para office/desktop

## Integracion GPU y hardware

GPU profiles (modulo 80):

- tipo: auto/intel/amd/nvidia/none
- proposito: general/gaming/design/ai

Objetivo:

- ajustar stack software-hardware sin tocar kernel

## Compatibilidad Windows y gaming

Compatibilidad Windows (modulo 30):

- Wine 64/32
- Winetricks
- libs i386 Vulkan/OpenGL
- Bottles

Gaming nativo (modulo 40):

- Steam/Heroic/Lutris/ProtonUp-Qt
- deteccion cruzada apt/flatpak para idempotencia
- soporte de utilidades rendimiento (gamemode/mangohud)

## UX y robustez de escritorio

UX light (modulo 20):

- ajustes de energia/suspension para XFCE
- mitigacion de bloqueos por power manager/screensaver/logind
- fallback diferido cuando no hay sesion grafica activa

## Cron de mantenimiento

Alta/baja de cron:

- updates-cron crea cron/script de mantenimiento
- remove-cron elimina cron/script

Logs de cron:

- almacenados en ./.runtime-logs
- recorte preventivo para controlar tamano

## Logging y trazabilidad

Rutas V2:

- ./.runtime-logs/debian-postinstall-v2-*.log
- ./.runtime-logs/debian-postinstall-v2-error-*.log
- ./.runtime-logs/debian-postinstall-v2-status.log

Trazas clave:

- RUN-START / RUN-END
- accion/perfil/modo/dry-run
- decisiones de compatibilidad/repos

## Casos de uso recomendados

Instalacion completa workstation:

- sudo ./post-install-v2.sh --action install --profile workstation --mode full

Correccion de perfil gaming:

- sudo ./post-install-v2.sh --action check-fix --profile gaming --mode full

Auditoria de categoria AI:

- sudo ./post-install-v2.sh --action verify-category --category ai-environments

Limpieza de duplicados desde catalogo:

- sudo ./post-install-v2.sh --action clean-duplicates --catalog-json ./config/app-library.json

## Troubleshooting rapido

- Accion invalida:
  - usar --list-actions
- Perfil invalido:
  - usar --list-profiles
- Repos faltantes:
  - revisar log y eventos REPO:MISSING
- Inconsistencias post-instalacion:
  - ejecutar check-fix y luego verify

## Validacion minima recomendada

- bash -n post-install-v2.sh
- bash -n modules/v2/*.sh
- smoke de acciones install/check-fix/verify-category
- inspeccion de logs v2 generados
