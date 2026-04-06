# Arquitectura V2

## Objetivo

La V2 se disena para operar Debian 13 con enfoque de ciclo de vida completo:

- instalar por perfil y modo
- verificar y corregir (check-fix)
- reconfigurar o reinstalar
- limpiar residuos y reemplazados
- evaluar salud del sistema

Todo sin modificar ni reemplazar kernel.

## Componentes principales

- Orquestador: [post-install-v2.sh](../../post-install-v2.sh)
- Utilidades base: [lib/v2/common.sh](../../lib/v2/common.sh)
- Matriz de perfiles/acciones: [lib/v2/profiles.sh](../../lib/v2/profiles.sh)
- Modulos:
  - [modules/v2/10-system-core.sh](../../modules/v2/10-system-core.sh)
  - [modules/v2/20-ux-light.sh](../../modules/v2/20-ux-light.sh)
  - [modules/v2/30-compat-bottles.sh](../../modules/v2/30-compat-bottles.sh)
  - [modules/v2/40-gaming-native.sh](../../modules/v2/40-gaming-native.sh)
  - [modules/v2/50-dev-environments.sh](../../modules/v2/50-dev-environments.sh)
  - [modules/v2/60-debug-clean.sh](../../modules/v2/60-debug-clean.sh)

## Flujo operativo

1. Preflight y contexto
- root/sudo
- usuario objetivo
- checks basicos de red/espacio/comandos

2. Seleccion de accion
- via argumentos CLI o asistente interactivo

3. Ejecucion de pipeline segun accion
- instalacion, correccion, limpieza, health, logs

4. Registro y salida
- logging en ./.runtime-logs/debian-postinstall-v2-*.log

## Perfiles

Definidos en [lib/v2/profiles.sh](../../lib/v2/profiles.sh):

- workstation
- dev-web
- dev-app
- dev-mobile
- gaming
- creator
- ai-ml
- minimal

Consideraciones de perfiles:

- VS Code se mantiene disponible para ambientes de desarrollo y creator/workstation donde se define.
- VirtualBox se incluye en perfiles orientados a desarrollo/uso general.
- Gaming usa base APT para stack grafico/rendimiento y detecta Steam/Heroic/ProtonUp-Qt tambien cuando ya existen por Flatpak.
- ai-ml usa base esencial de IA/ML y habilita seleccion de bundles interdependientes (ml-core, dl-runtime, agents-stack).

## Modos

- full:
  - system-core
  - ux-light
  - compat-bottles
  - dev-environments (segun perfil)
  - gaming-native (solo gaming)
- utils:
  - system-core
  - ux-light
  - dev-environments (minimal)
- debug-clean:
  - debug-clean

## Acciones

- install: instala por perfil/modo
- check-fix: limpieza preventiva de preconfig conflictiva + reinstalacion correctiva + postconfig
- configure: reaplica configuraciones
- reinstall: remove + install
- remove: elimina paquetes/apps del perfil
- remove-category: purga por categoria con proteccion de paquetes compartidos
- clean: limpieza general de residuos
- clean-obsolete: limpieza de paquetes reemplazados
- clean-files: limpieza de temporales y descargas de instaladores no necesarios
- optimize: reaplica tuning base
- updates-cron: valida actualizaciones y configura cron de mantenimiento
- remove-cron: elimina cron/script de mantenimiento instalado por V2
- logs: muestra ultimo log
- refs: muestra referencias oficiales
- health: panel de estado
- verify: auditoria de integridad y compatibilidad por perfil
- verify-category: auditoria de integridad por categoria
- clean-duplicates: limpieza de duplicados segun biblioteca JSON de aplicaciones

## Compatibilidad y reglas visibles

La instalacion de paquetes evalua compatibilidad y muestra flags:

- [COMPAT:OK]
- [COMPAT:BLOCK]

Esto evita instalaciones no aptas por arquitectura o recursos en casos definidos.

## Biblioteca de aplicaciones y fuentes

Se incorpora una biblioteca JSON en [config/app-library.json](../../config/app-library.json) para:

- centralizar fuentes (APT/Flathub)
- declarar inventario por categoria
- definir reglas de deduplicacion (preferencia apt o flatpak)
- habilitar la accion `clean-duplicates`

Estructura normalizada del catalogo:

- `debian13_base`: base esencial + optimizacion recomendada
- `debian13_replacements`: reemplazos de paquetes legacy/base
- `category_classification`: clasificacion por categoria (esencial/opcional/pesado)
- `integrity_rules`: reglas de referencia para verificadores

Nota de compatibilidad:

- Se preservan los nodos `categories.<perfil>.apt/flatpak` para que las acciones actuales sigan funcionando sin migraciones adicionales.

Politica de origen comun:

- V1 y V2 consumen el mismo catalogo JSON mediante `lib/app-catalog.sh`.
- Nuevos cambios de inventario deben entrar primero por `config/app-library.json`.

## Perfilado GPU por uso

Se incorpora modulo de perfilado GPU en [modules/v2/80-gpu-profiles.sh](../../modules/v2/80-gpu-profiles.sh):

- `--gpu-profile`: auto/intel/amd/nvidia/none
- `--gpu-purpose`: general/gaming/design/ai

Objetivo: mejorar compatibilidad software-hardware por categoria sin forzar cambios de kernel.

## Salud y ZRAM

- Verificacion de salud incluye chequeo de ZRAM.
- El flujo de optimizacion intenta activar ZRAM de forma robusta (servicio y swap zram).

## Compatibilidad Windows y gaming

El modulo [modules/v2/30-compat-bottles.sh](../../modules/v2/30-compat-bottles.sh) provee base de compatibilidad Windows:

- Wine 64/32
- Winetricks
- librerias Vulkan/OpenGL i386
- Bottles via Flatpak
- ajustes base de permisos
- deteccion equivalente de componentes gaming instalados por Flatpak

## Hardware, drivers y VPN libre

System-core incorpora utilidades de comprobacion/configuracion de hardware:

- inxi, lshw, hwinfo, pciutils, usbutils, dmidecode
- fwupd
- firmware no libre (si aplica)

Tambien incluye stack VPN cliente gratuito:

- OpenVPN
- WireGuard
- Plugins de NetworkManager para OpenVPN

Para gaming, la via principal sigue siendo nativa Linux:

- Steam/Proton, incluyendo deteccion via Flatpak `com.valvesoftware.Steam`
- Heroic, incluyendo deteccion via Flatpak `com.heroicgameslauncher.hgl`
- Lutris
- ProtonUp-Qt via Flatpak `net.davidotek.pupgui2` cuando aplica
- MangoHud + gamemode

## Optimizacion y consumo

- ZRAM y swappiness adaptativo segun RAM
- EarlyOOM
- fstrim timer
- ajustes sysctl de red/memoria
- UX ligera para evitar carga innecesaria en background
- reemplazo de editores legacy (mousepad) por gedit en flujo clean-obsolete
- fixes de energia XFCE (xfconf + logind override) para reducir bloqueos/suspension inesperada
- deduplicado de Office: prioridad a LibreOffice Flatpak cuando esta presente

## Restriccion de kernel

La V2 no modifica ni reemplaza el kernel de Debian.
