# Modulos

## infra

Objetivo: preparar repositorios externos y conectividad APT.

Acciones:
- Ajusta sources.list para Debian 13.
- Importa keyrings (Microsoft, Google, Opera).
- Crea listas de repos para VS Code, Edge, Chrome y Opera.
- Fuerza IPv4 para APT.

## base

Objetivo: instalar herramientas generales para cualquier perfil.

Acciones:
- Instala utilidades CLI base.
- Instala fuentes comunes.
- Activa y configura ufw con OpenSSH.

## optimization

Objetivo: mejorar estabilidad y rendimiento diario.

Acciones:
- Instala zram-tools, earlyoom y utilidades de sistema.
- Configura swappiness segun RAM.
- Aplica perfil sysctl con fq_codel y bbr.

## dev

Objetivo: preparar entorno de desarrollo moderno.

Acciones:
- Instala compilacion/toolchain y CLI dev.
- Instala VS Code y stack de contenedores (Docker/Podman).
- Configura fnm + Node LTS + pnpm.

## multimedia

Objetivo: reproducir y gestionar contenido multimedia.

Acciones:
- Instala vlc/mpv/ffmpeg.
- Instala apps Flatpak de comunicacion y musica.

## security-remote

Objetivo: acceso remoto seguro y auditoria base.

Acciones:
- Instala OpenSSH y herramientas remotas.
- Instala utilidades de seguridad y diagnostico.
- Aplica hardening basico SSH (sin root login).

## ux

Objetivo: dejar una experiencia de uso inicial consistente.

Acciones:
- Despliega tema Fake10 (si existe archivo local).
- Configura gtk settings.
- Agrega aliases de shell utiles.
