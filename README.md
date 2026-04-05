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

### Compatibilidad visible en consola (V1)

Durante instalacion se imprimen flags por paquete:

- `[COMPAT:OK]`: paquete compatible con el entorno actual.
- `[COMPAT:BLOCK]`: paquete bloqueado por arquitectura/recursos u otra regla.

Novedades incluidas:

- Virtualizacion con VirtualBox ademas de QEMU/libvirt.
- Gaming con ProtonUp-Qt para gestion de versiones Proton GE.
- Utilidades para drivers/hardware no nativo: inxi, lshw, hwinfo, fwupd, firmware no libre y reporte local.
- Stack VPN gratuito cliente: OpenVPN + WireGuard + plugins NetworkManager.
- Editor de texto actualizado: reemplazo de mousepad por gedit en limpieza correctiva.

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
- minimal

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
- clean: limpieza general de residuos
- clean-obsolete: limpia paquetes reemplazados
- optimize: reaplica optimizaciones base
- logs: muestra ultimo log
- health: panel de estado de salud

### Compatibilidad visible en consola (V2)

Tambien usa flags de compatibilidad por paquete:

- `[COMPAT:OK]`
- `[COMPAT:BLOCK]`

En V2 tambien se incluyeron:

- VS Code en perfiles de desarrollo y creator/workstation donde aplica.
- VirtualBox en perfiles orientados a desarrollo/uso general.
- ProtonUp-Qt en perfil gaming (APT y/o Flatpak segun flujo).
- Herramientas de hardware/drivers y VPN libre en el core/base de sistema.
- Reemplazo mousepad -> gedit en `clean-obsolete`.

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

- `/var/log/debian-postinstall-v2-YYYY-MM-DD-HHMMSS.log`

Comandos utiles:

```bash
sudo bash post-install-v2.sh --action logs
sudo bash post-install-v2.sh --action health
```

En V1, el panel de salud se ejecuta desde la opcion [6] del menu principal.

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
