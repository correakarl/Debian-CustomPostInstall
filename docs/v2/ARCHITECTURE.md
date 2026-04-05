# Arquitectura V2

## Objetivo

La V2 esta pensada para:

- Optimizar Debian 13 a nivel de sistema base sin depender del entorno grafico.
- Ofrecer una experiencia de personalizacion tipo Windows/Ubuntu con bajo consumo.
- Soportar perfiles de uso (trabajo, desarrollo, gaming, creator, minimal).
- Priorizar gaming nativo Linux y usar Bottles para compatibilidad Windows.
- Incluir un modo de depuracion/limpieza para remover herramientas reemplazadas.

## Flujo principal

Script: [post-install-v2.sh](../../post-install-v2.sh)

1. Validacion de contexto (root, usuario objetivo, preflight).
2. Seleccion de modo y perfil.
3. Ejecucion de modulos:
   - [modules/v2/10-system-core.sh](../../modules/v2/10-system-core.sh)
   - [modules/v2/20-ux-light.sh](../../modules/v2/20-ux-light.sh)
   - [modules/v2/30-compat-bottles.sh](../../modules/v2/30-compat-bottles.sh)
   - [modules/v2/50-dev-environments.sh](../../modules/v2/50-dev-environments.sh)
   - [modules/v2/40-gaming-native.sh](../../modules/v2/40-gaming-native.sh) (solo perfil gaming)
   - [modules/v2/60-debug-clean.sh](../../modules/v2/60-debug-clean.sh) (modo debug-clean)

## Perfiles

Definidos en [lib/v2/profiles.sh](../../lib/v2/profiles.sh).

- workstation: entorno general de productividad.
- dev-web: web + contenedores + Node.
- dev-app: escritorio/backend compilado.
- dev-mobile: base mobile con ADB/Fastboot.
- gaming: stack nativo Linux para juegos.
- creator: multimedia y diseno.
- minimal: entorno liviano.

## Modos

- full:
  - system-core
  - ux-light
  - compat-bottles
  - dev-environments (segun perfil)
  - gaming-native (si perfil gaming)
- utils:
  - system-core
  - ux-light
  - dev-environments (minimal)
- debug-clean:
  - debug-clean

## Compatibilidad Windows y Gaming

- Bottles se instala como via recomendada para apps Windows no gaming.
- Gaming prioriza Steam/Proton + Heroic + Lutris + MangoHud + gamemode.
- Se evita usar Bottles como camino principal de gaming.

## Consumo de recursos

- ZRAM y swappiness adaptativo segun RAM.
- EarlyOOM, fstrim, ajustes sysctl de red/memoria.
- UX ligera (GTK + iconos + aliases) sin capas pesadas en background.

## Depuracion y limpieza

Modo [debug-clean](../../post-install-v2.sh) con:

- Remocion opcional de herramientas heredadas.
- APT autoremove/autoclean.
- Flatpak uninstall --unused.
