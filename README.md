# Debian Custom Post Install

Automatizacion de post-instalacion para Debian 13 (Trixie) con dos enfoques complementarios:

- V1 interactiva monolitica, orientada a categorias de uso: [post-install.sh](post-install.sh)
- V2 modular por acciones, perfiles y modos: [post-install-v2.sh](post-install-v2.sh)

## Objetivo del proyecto

- Optimizar y personalizar Debian sin tocar kernel.
- Instalar herramientas por necesidad real (categoria/perfil).
- Ofrecer flujos de mantenimiento: check-fix, limpieza, remocion y salud.
- Mejorar compatibilidad Windows con Bottles/Wine cuando se requiera.

## Restriccion principal

Este proyecto no modifica ni reemplaza el kernel en ninguna version.

## Estructura del repositorio

- [post-install.sh](post-install.sh): flujo V1 interactivo por categorias.
- [post-install-v2.sh](post-install-v2.sh): orquestador V2 por accion/perfil/modo.
- [run-module.sh](run-module.sh): lanzador modular legacy por tareas.
- [lib/common.sh](lib/common.sh): utilidades compartidas del flujo modular legacy.
- [modules](modules): modulos legacy separados por dominio.
- [lib/v2/common.sh](lib/v2/common.sh): utilidades V2 (logging, compatibilidad, APT/Flatpak, prompts).
- [lib/v2/profiles.sh](lib/v2/profiles.sh): matriz de perfiles y acciones.
- [modules/v2](modules/v2): modulos V2 del sistema.
- [docs/modules.md](docs/modules.md): catalogo de categorias/modulos.
- [docs/v2/ARCHITECTURE.md](docs/v2/ARCHITECTURE.md): arquitectura operativa V2.

## Requisitos

- Debian 13 (Trixie) recomendado.
- Usuario con privilegios sudo.
- Conexion a internet.
- Ejecutar scripts con root/sudo.

## V1 interactiva por categorias

Ejecucion:

```bash
sudo bash post-install.sh
```

### Menu principal V1

- [1] Instalar por categorias
- [2] Check and Fix por categoria
- [3] Reconfigurar categoria
- [4] Limpieza general
- [5] Limpiar innecesarios (reemplazados)
- [6] Panel de salud
- [7] Aplicar UX/UI
- [8] Eliminar por categoria (purga segura)
- [9] Comprobar actualizaciones + configurar cron
- [10] Referencias oficiales
- [11] Limpiar temporales y descargas de instaladores
- [12] Verificar por categoria
- [13] Limpiar duplicados (BD apps)
- [14] Eliminar cron de mantenimiento

Navegacion:

- Regresar: `0` o `00` en submenus
- Cancelar: `c`
- Salir: `q` o `0`

### Categorias disponibles en V1

- Optimizacion del sistema
- Navegadores
- Ofimatica
- Multimedia
- Dev Core
- Dev CLI
- Dev Web (VS Code)
- Dev Contenedores
- Dev Mobile
- Comunicacion
- Virtualizacion
- Hardware/Drivers
- VPN Libre
- Diseno grafico
- Diseno video
- Diseno 3D
- AI / ML / Agentes
- Gaming nativo
- Compatibilidad Windows (Bottles/Wine)
- Ciberseguridad
- Acceso remoto
- Monitoreo
- Backup
- Seguridad

### Check and Fix en V1

- Verifica el estado del modulo/categoria.
- Reinstala paquetes faltantes o necesarios.
- Reaplica postconfiguraciones del modulo.
- Cuando aplica, limpia preconfiguracion antes de instalar la version correctiva por defecto.

### Eliminar por categoria en V1 (purga segura)

- Purga el bloque de paquetes asociado a la categoria seleccionada.
- Evita remover paquetes compartidos con otras categorias instaladas.
- Purga Flatpak de la categoria cuando no esta compartido.

### Compatibilidad visible en consola (V1)

Durante instalacion se imprimen flags por paquete:

- `[COMPAT:OK]`: paquete compatible con el entorno actual.
- `[COMPAT:BLOCK]`: paquete bloqueado por arquitectura/recursos u otra regla.

Novedades incluidas:

- Virtualizacion con VirtualBox ademas de QEMU/libvirt.
- Gaming con deteccion equivalente APT/Flatpak para Steam, Heroic y ProtonUp-Qt.
- Brave incluido en navegadores con repositorio oficial APT.
- Utilidades para drivers/hardware no nativo: inxi, lshw, hwinfo, fwupd, firmware no libre y reporte local.
- Stack VPN gratuito cliente: OpenVPN + WireGuard + plugins NetworkManager.
- Editor de texto actualizado: reemplazo de mousepad por gedit en limpieza correctiva.
- Verificacion por categoria para auditar estado de paquetes y flatpaks por modulo.
- Limpieza de duplicados desde biblioteca JSON de aplicaciones.
- Perfilado GPU por categoria de uso (general/gaming/design/ai) sin reemplazo de kernel.
- Fixes UX en XFCE: inhibicion de bloqueo/suspension en xfconf + override de logind para tapa/inactividad.
- Mitigacion de duplicados Office: prioridad a Flatpak para LibreOffice y purga de paquete APT cuando procede.
- Integracion XFCE reforzada: xfce4-goodies, pavucontrol, xfce4-power-manager-plugins y gvfs-backends.

## V2 por accion, perfil y modo

Ejecucion recomendada:

```bash
sudo bash post-install-v2.sh --action install --profile workstation --mode full
```

Asistente interactivo:

```bash
sudo bash post-install-v2.sh
```

Navegacion en asistente:

- `r` regresar
- `c` cancelar
- `s` salir

### Perfiles V2

- workstation
- dev-web
- dev-app
- dev-mobile
- gaming
- creator
- ai-ml
- minimal

`ai-ml` instala base esencial para IA/ML (Python cientifico + herramientas de desarrollo) y permite seleccionar bundles interdependientes:

- `ml-core`
- `dl-runtime`
- `agents-stack`

### Modos V2

- full: pipeline completo por perfil
- utils: base + UX + utilidades minimas
- debug-clean: limpieza de residuos y dependencias sobrantes

### Acciones V2

- install: instalacion segun perfil/modo
- check-fix: validacion y reinstalacion correctiva
- configure: reaplica configuraciones
- reinstall: remove + install
- remove: elimina paquetes/apps del perfil
- remove-category: purga por categoria con proteccion de paquetes compartidos
- clean: limpieza general de residuos
- clean-obsolete: limpia paquetes reemplazados
- clean-duplicates: limpia duplicados usando biblioteca JSON de aplicaciones
- clean-files: limpia temporales y descargas de instaladores no necesarios
- optimize: reaplica optimizaciones base
- updates-cron: revisa actualizaciones y configura cron de mantenimiento
- remove-cron: elimina cron/script de mantenimiento instalado por el flujo V2
- logs: muestra ultimo log
- refs: muestra referencias oficiales
- health: panel de estado de salud
- verify: audita integridad de herramientas instaladas y compatibilidad del perfil
- verify-category: audita integridad por categoria

Opciones avanzadas nuevas:

- `--catalog-json <ruta>`: biblioteca JSON de apps/fuentes/duplicados.
- `--gpu-profile <tipo>`: `auto|intel|amd|nvidia|none`.
- `--gpu-purpose <tipo>`: `auto|general|gaming|design|ai`.

UX del asistente:

- Menus largos de V1/V2 se muestran en columnas para reducir scroll y mejorar legibilidad.

### Compatibilidad visible en consola (V2)

Tambien usa flags de compatibilidad por paquete:

- `[COMPAT:OK]`
- `[COMPAT:BLOCK]`

En V2 tambien se incluyeron:

- VS Code en perfiles de desarrollo y creator/workstation donde aplica.
- VirtualBox en perfiles orientados a desarrollo/uso general.
- Perfil gaming alineado con instalacion real: base APT para Vulkan/GameMode y apps gaming principales por Flatpak cuando corresponde.
- Herramientas de hardware/drivers y VPN libre en el core/base de sistema.
- Reemplazo mousepad -> gedit en `clean-obsolete`.
- En workstation, LibreOffice se prioriza por Flatpak para evitar duplicados con APT.
- Ajustes anti-bloqueo en XFCE (power manager/screensaver/logind) durante `ux-light`.
- Perfil `ai-ml` con instalacion esencial y seleccion de bundles IA en el asistente interactivo.
- Accion `verify` para comprobacion de integridad de perfil (APT/Flatpak/comandos base/imports IA).
- Accion `verify-category` para comprobacion por categoria.
- Accion `clean-duplicates` para limpieza de duplicados segun catalogo.
- Perfilado GPU por uso para gaming/diseno/IA sin reemplazar kernel automaticamente.

## Biblioteca JSON de aplicaciones

Se incluye una biblioteca base en:

- [config/app-library.json](config/app-library.json)

Objetivo:

- Declarar fuentes globales (APT/Flathub).
- Mantener catalogo por categoria/perfil.
- Definir reglas de duplicados y preferencia de fuente.
- Servir de base para `clean-duplicates` y para trazabilidad de instalacion.

Normalizacion aplicada (v1.1.0 del catalogo):

- `debian13_base`: base esencial y bloque de optimizacion recomendado.
- `debian13_replacements`: reemplazos sugeridos para Debian 13.
- `category_classification`: separacion por categoria entre esencial, opcional y pesado.
- `integrity_rules`: comandos/imports de referencia para verificadores.

Actualizacion catalogo (v1.1.1):

- `sources.third_party_optional`: fuentes externas opcionales para paquetes que no siempre existen en repos base Debian/Flathub.
- Si una fuente externa no esta configurada, el instalador omite ese item con trazabilidad (`[REPO:MISSING]` o `[FLATPAK:MISSING]`) sin abortar el flujo.
- `sources.apt`: se define por canales oficiales Debian (`main`, `security`, `updates`) en lugar de una ruta unica simplificada.
- Cuando aplica, el diagnostico de `REPO:MISSING` consulta `/var/log/apt/history.log` para detectar paquetes que existieron en repos previos.

Compatibilidad:

- Se mantienen `categories.<perfil>.apt` y `categories.<perfil>.flatpak` para no romper acciones existentes.

Origen unico de datos (V1 y V2):

- Ambos flujos leen perfiles/categorias desde `config/app-library.json` por medio de `lib/app-catalog.sh`.
- La recomendacion operativa es no agregar listas de paquetes directas en scripts; agregar/editar primero en el catalogo.

Detalle relevante de deteccion:

- Steam puede detectarse por paquete APT o Flatpak `com.valvesoftware.Steam`.
- Heroic puede detectarse por APT o Flatpak `com.heroicgameslauncher.hgl`.
- ProtonUp-Qt puede detectarse por APT o Flatpak `net.davidotek.pupgui2`.
- `glxinfo` se considera cubierto cuando existe el comando o esta instalado `mesa-utils`.

## Compatibilidad Windows (Bottles/Wine)

Disponible en V1 (categoria dedicada) y V2 (modulo compat-bottles):

- Wine 64/32
- Winetricks
- Librerias i386 Vulkan/OpenGL
- Bottles (Flatpak)
- Overrides y notas base para mejorar ejecucion de apps Windows

Nota tecnica: aun con este stack, algunas apps Windows requieren runtimes adicionales (VC++, .NET, DXVK) o pueden no ser compatibles por restricciones del proveedor.

## JSON de personalizacion y comprobacion

Ahora ambas versiones pueden recibir un JSON para auditar el estado deseado del sistema.

Archivo ejemplo:

- [config/customization-profile.example.json](config/customization-profile.example.json)

Libreria compartida de auditoria:

- [lib/profile-json.sh](lib/profile-json.sh)

Campos soportados en JSON:

- `name`: nombre del perfil
- `wanted.packages`: paquetes APT deseados
- `wanted.flatpaks`: apps Flatpak deseadas
- `wanted.services_enabled`: servicios que deben estar habilitados
- `wanted.files_exist`: archivos/rutas que deben existir
- `wanted.sysctl`: pares clave/valor de sysctl esperados
- `blocked_packages`: paquetes que no deberian estar instalados

Flags de auditoria en consola:

- `[JSON][WANT:OK]`
- `[JSON][WANT:MISS]`
- `[JSON][BLOCKED:OK]`
- `[JSON][BLOCKED:FOUND]`

Uso en V1:

```bash
sudo bash post-install.sh --profile-json ./config/customization-profile.example.json
```

Uso en V2:

```bash
sudo bash post-install-v2.sh --profile-json ./config/customization-profile.example.json --action health
```

## Logs y salud

V2 guarda logs en:

- `./.runtime-logs/debian-postinstall-v2-YYYY-MM-DD-HHMMSS.log`

Comandos utiles:

```bash
sudo bash post-install-v2.sh --action logs
sudo bash post-install-v2.sh --action health
sudo bash post-install-v2.sh --action updates-cron
sudo bash post-install-v2.sh --action remove-cron
sudo bash post-install-v2.sh --action refs
```

En V1, el panel de salud se ejecuta desde la opcion [6] del menu principal.

Limpieza de temporales/descargas (V1 opcion [11] y V2 accion `clean-files`):

- limpia `/tmp` y `/var/tmp` de entradas antiguas
- elimina instaladores comunes sobrantes en `~/Downloads` (`.deb`, `.AppImage`, `.iso`, `.zip`, `.tar.*`, etc.)
- elimina descargas temporales incompletas (`.tmp`, `.part`, `.crdownload`)

Chequeo de ZRAM mejorado en ambas versiones:

- Verifica servicio y swap zram real.
- Intenta activacion automatica cuando corresponde.

## Ejemplos practicos

Instalacion V2 en perfil developer web:

```bash
sudo bash post-install-v2.sh --action install --profile dev-web --mode full
```

Check and Fix correctivo V2:

```bash
sudo bash post-install-v2.sh --action check-fix --profile workstation --mode full
```

Limpieza de reemplazados V2:

```bash
sudo bash post-install-v2.sh --action clean-obsolete
```

Simulacion sin cambios (dry-run):

```bash
DRY_RUN=true sudo -E bash post-install-v2.sh --action install --profile dev-app --mode full --non-interactive
```

## Licencia y atribucion

- Licencia del proyecto: [LICENSE](LICENSE) (Creative Commons Attribution 4.0, CC BY 4.0).
- Atribucion y avisos: [NOTICE](NOTICE).

Autor principal:

- Karl Michael Correa Rivero

## Flujo del aplicativo

- Diagrama completo V1/V2 (acciones, caminos de error y guardas): [docs/flows/debian-postinstall-full-flow.drawio](docs/flows/debian-postinstall-full-flow.drawio)
