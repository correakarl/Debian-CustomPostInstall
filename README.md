# Debian Custom Post Install

Repositorio para automatizar post-instalacion de Debian 13 (Trixie) con dos enfoques:

- V1 monolitico interactivo: [post-install.sh](post-install.sh)
- V2 modular por perfiles y modo de uso: [post-install-v2.sh](post-install-v2.sh)

## Estructura

- [post-install.sh](post-install.sh): flujo completo interactivo (version OMNI-OPTIMIZER).
- [post-install-v2.sh](post-install-v2.sh): orquestador V2 por perfil/mode.
- [run-module.sh](run-module.sh): ejecutor modular por categorias.
- [lib/common.sh](lib/common.sh): utilidades compartidas para modulos.
- [modules/01-infra.sh](modules/01-infra.sh): repos, keyrings y red APT.
- [modules/02-base.sh](modules/02-base.sh): paquetes base + ufw.
- [modules/03-optimization.sh](modules/03-optimization.sh): zram, earlyoom, sysctl.
- [modules/04-dev.sh](modules/04-dev.sh): toolchain dev, docker, fnm/node.
- [modules/05-multimedia.sh](modules/05-multimedia.sh): multimedia + flatpak apps.
- [modules/06-security-remote.sh](modules/06-security-remote.sh): ssh y seguridad.
- [modules/07-ux.sh](modules/07-ux.sh): tema y perfil de shell.
- [docs/modules.md](docs/modules.md): detalle de objetivos por modulo.
- [lib/v2/common.sh](lib/v2/common.sh): utilidades base de la V2.
- [lib/v2/profiles.sh](lib/v2/profiles.sh): matriz de perfiles de uso.
- [modules/v2](modules/v2): modulos orientados a sistema, compatibilidad, gaming y depuracion.
- [docs/v2/ARCHITECTURE.md](docs/v2/ARCHITECTURE.md): arquitectura, perfiles y modos de V2.

## Requisitos

- Debian 13 (Trixie)
- Usuario con sudo
- Conexion a internet
- Ejecutar como root/sudo

## Uso rapido

### 1) Script completo interactivo

```bash
sudo bash post-install.sh
```

### 1.1) V2 por perfil (recomendado)

```bash
sudo bash post-install-v2.sh --profile workstation --mode full
sudo bash post-install-v2.sh --profile dev-web --mode full
sudo bash post-install-v2.sh --profile gaming --mode full
```

Perfiles disponibles:

- workstation
- dev-web
- dev-app
- dev-mobile
- gaming
- creator
- minimal

Modos disponibles:

- full: optimizacion base + UX ligera + Bottles + perfil
- utils: base + UX + utilidades minimas
- debug-clean: limpia paquetes reemplazados y artefactos no usados

### 2) Ejecucion modular

```bash
sudo bash run-module.sh infra
sudo bash run-module.sh base
sudo bash run-module.sh optimization
```

Para ejecutar todo de forma no interactiva:

```bash
sudo bash run-module.sh all
```

### 3) Modo simulacion (solo modular)

```bash
DRY_RUN=true sudo -E bash run-module.sh dev
```

En V2 tambien puedes simular:

```bash
DRY_RUN=true sudo -E bash post-install-v2.sh --profile dev-app --mode full --non-interactive
```

## Inicializar Git y subir cambios

Si aun no esta inicializado:

```bash
git init
git branch -M main
git add .
git commit -m "chore: init debian post-install project"
```

Luego conecta remoto y sube:

```bash
git remote add origin <URL-DEL-REPO>
git push -u origin main
```

## Nota

Los modulos son independientes para tareas puntuales. El script [post-install.sh](post-install.sh) se mantiene para instalaciones guiadas completas, mientras [post-install-v2.sh](post-install-v2.sh) unifica enfoque por perfil y modo de uso con optimizacion transversal del sistema.
