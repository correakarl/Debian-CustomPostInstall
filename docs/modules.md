# Catalogo de categorias y modulos

Este documento resume las categorias actualmente usadas por el flujo V1 (menu interactivo) y su equivalente funcional en V2 cuando aplica.

## Categorias V1

### optimization

Objetivo: optimizacion base del sistema.

Incluye:
- zram-tools, earlyoom, ajustes sysctl y parametros de memoria.
- optimizacion de latencia de red (fq_codel/bbr).
- ajustes para estabilidad diaria sin intervenir kernel.

### browsers

Objetivo: navegacion web y compatibilidad de sitios.

Incluye:
- firefox-esr
- chrome/edge/opera segun disponibilidad y compatibilidad

### office

Objetivo: productividad y documentos.

Incluye:
- libreoffice (writer/calc/impress)
- visores de documentos
- cliente de correo

### multimedia

Objetivo: reproduccion y creacion multimedia base.

Incluye:
- vlc, mpv, ffmpeg
- apps flatpak de comunicacion y musica cuando aplica

### dev_core

Objetivo: toolchain base de desarrollo.

Incluye:
- build-essential, pkg-config, ssl-dev, git-lfs
- terminales y utilidades base

### dev_cli

Objetivo: productividad en linea de comandos.

Incluye:
- fzf, ripgrep, fd-find, bat/eza, httpie, mkcert

### dev_web

Objetivo: stack web moderno.

Incluye:
- VS Code
- Docker y compose plugin
- postconfiguracion de runtime web

### dev_containers

Objetivo: contenedores y orquestacion ligera.

Incluye:
- podman/podman-docker
- herramientas de contenedores para pruebas y desarrollo

### dev_mobile

Objetivo: herramientas base para desarrollo mobile.

Incluye:
- adb
- fastboot
- scrcpy

### communication

Objetivo: mensajeria y colaboracion.

Incluye:
- clientes de comunicacion compatibles con Debian y/o repos externos

### virtualization

Objetivo: virtualizacion local.

Incluye:
- qemu/libvirt
- virt-manager y herramientas asociadas
- virtualbox para escenarios de VM de escritorio

### hardware_drivers

Objetivo: comprobacion y soporte de hardware/driver no nativo.

Incluye:
- inventario y diagnostico (inxi, lshw, hwinfo, pciutils, usbutils, dmidecode)
- utilidades de firmware (fwupd)
- firmware no libre cuando aplica (firmware-linux-nonfree, firmware-misc-nonfree)
- soporte de deteccion nvidia (nvidia-detect)

### vpn_free

Objetivo: base para uso de VPN gratuita por perfiles OpenVPN/WireGuard.

Incluye:
- openvpn
- wireguard-tools
- plugins NetworkManager OpenVPN
- notas de uso para proveedores con plan free

### design_graphic

Objetivo: diseno grafico y edicion 2D.

Incluye:
- gimp, inkscape, krita, fontforge

### design_video

Objetivo: edicion y produccion audiovisual.

Incluye:
- kdenlive, audacity, obs-studio, handbrake-cli

### design_3d

Objetivo: modelado y CAD base.

Incluye:
- blender
- freecad

### gaming

Objetivo: gaming nativo Linux.

Incluye:
- base APT para retroarch, Vulkan, MangoHud, GameMode y utilidades graficas
- Steam, Heroic, Lutris y ProtonUp-Qt detectables/instalables por Flatpak cuando aplica
- deteccion equivalente para no reinstalar si ya existen por Flatpak o paquete proveedor

Nota:
- `glxinfo` no se trata como paquete APT independiente; se considera cubierto por `mesa-utils` o por la existencia del comando.

### browsers

Objetivo: navegacion general y compatibilidad de uso diario.

Incluye:
- firefox-esr
- brave-browser
- google-chrome-stable
- microsoft-edge-stable
- opera-stable

Nota:
- Brave usa su repositorio oficial APT antes de la instalacion.

### windows_compat

Objetivo: compatibilidad de aplicaciones Windows.

Incluye:
- wine64/wine32
- winetricks y utilidades auxiliares
- librerias i386 Vulkan/OpenGL
- Bottles (Flatpak) con configuracion base

### cybersec

Objetivo: diagnostico y seguridad operativa.

Incluye:
- nmap, wireshark, tcpdump, lynis, nikto, etc.

### remote

Objetivo: acceso remoto y transferencia segura.

Incluye:
- openssh, rsync, rclone, syncthing y herramientas de tunel

### monitoring

Objetivo: observabilidad del sistema.

Incluye:
- iotop, iftop, nethogs, psensor, smartmontools

### backup

Objetivo: respaldo y recuperacion.

Incluye:
- timeshift, borgbackup, restic

### security

Objetivo: hardening y validacion basica de seguridad.

Incluye:
- auditd, apparmor-utils, chkrootkit, rkhunter

## Operaciones relevantes

### Check and Fix

En V1 existe una opcion dedicada para check and fix por categoria:

- verifica estado por categoria
- limpia preconfiguracion conflictiva cuando aplica
- reinstala/repara
- reaplica postconfiguraciones correctivas

### Remove category (purga segura)

En V1 se puede eliminar por categoria con proteccion de impacto:

- purga paquetes del bloque seleccionado
- evita purgar paquetes compartidos con categorias instaladas
- limpia Flatpak asociado cuando no esta compartido

### Limpiar innecesarios

El flujo incluye limpieza de paquetes reemplazados por alternativas modernas y limpieza de residuos del sistema.

Ejemplo aplicado:
- mousepad se reemplaza por gedit.

### Limpieza de temporales y descargas

En V1 existe una opcion dedicada para limpieza post-instalacion:

- borra entradas antiguas de `/tmp` y `/var/tmp`
- elimina instaladores comunes no necesarios de `~/Downloads`
- limpia descargas temporales incompletas (`.tmp`, `.part`, `.crdownload`)

### Actualizaciones y cron

Existe una opcion para:

- comprobar actualizaciones disponibles
- configurar una tarea cron de mantenimiento con log

## Restriccion

Ninguna categoria modifica o reemplaza el kernel.
