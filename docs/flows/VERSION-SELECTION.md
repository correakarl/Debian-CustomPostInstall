# Guia Operativa Comparativa: V1 vs V2 vs V3

## Objetivo

Esta guia permite elegir rapidamente que version del flujo usar en Debian-CustomPostInstall, segun tipo de operador, nivel de control requerido y escenario tecnico.

Regla transversal a todas las versiones:

- ninguna version modifica o reemplaza el kernel

## Resumen ejecutivo

- Usa V1 si necesitas operacion guiada por menu, ajustes de escritorio y trabajo manual por categorias.
- Usa V2 si necesitas ciclo de vida completo por perfil/modo/accion con mayor cobertura operativa y mantenimiento.
- Usa V3 si necesitas ejecucion declarativa, simple y automatizable para install/check-fix/verify con enfoque en catalogo v2 y capacidades de hardware.

## Matriz de decision rapida

| Criterio | V1 (post-install.sh) | V2 (post-install-v2.sh) | V3 (post-install-v3.sh) |
|---|---|---|---|
| Tipo de flujo | Interactivo monolitico | Modular por accion/perfil/modo | Declarativo no interactivo |
| Perfil de usuario objetivo | Usuario tecnico de escritorio | Operador avanzado / mantenimiento continuo | Operador que prioriza simplicidad y automatizacion |
| Curva de aprendizaje | Baja-media | Media-alta | Baja |
| Granularidad por categoria | Alta (menu por categoria) | Alta (accion + categoria/perfil) | Alta en verify-category; media en install/check-fix por perfil |
| Modo interactivo | Si | Si y no interactivo | No |
| DRY-RUN | Si | Si | Si |
| Verificacion por perfil | Parcial/por modulo | Si (`verify`) | Si (`verify`) |
| Verificacion por categoria | Si (menu) | Si (`verify-category`) | Si (`verify-category`) |
| Limpieza de duplicados por catalogo | Si | Si (`clean-duplicates`) | Deduplica en instalacion APT vs Flatpak preferido |
| Perfilado GPU | Si | Si (modulo 80 + flags) | Indirecto por capacidad/catalogo |
| Integracion AI bundles | Basica por categoria | Completa (`ai-ml` + bundles) | Dependiente del catalogo perfil/categoria |
| Mantenimiento (cron, clean, optimize) | Alto | Muy alto | Basico (cleanup final del flujo) |
| Idonea para automatizar via script CI | Media | Alta | Alta |
| Complejidad operacional | Media | Alta | Baja-media |

## Arbol de decision operativo

1. Necesitas menu guiado y decidir sobre la marcha por categoria.
- Elegir V1.

2. Necesitas una accion especifica de ciclo de vida (install/check-fix/reinstall/remove/clean/verify) con perfiles y modos definidos.
- Elegir V2.

3. Necesitas ejecucion simple por CLI con pocas opciones, soportando verify y verify-category de forma directa.
- Elegir V3.

4. Necesitas bundles AI interdependientes y flujo de operacion completo para perfiles de trabajo.
- Elegir V2.

5. Necesitas auditoria puntual de una sola categoria con comandos cortos.
- Elegir V3 (`--action verify-category --category <cat>`).

## Comparativa por escenarios reales

### Escenario A: Usuario desktop que quiere post-instalacion guiada

Recomendado: V1.

Motivo:

- menu claro
- feedback visual continuo
- operaciones comunes en un unico flujo

Comando base:

```bash
sudo bash post-install.sh
```

### Escenario B: Equipo de soporte interno (runbook con acciones repetibles)

Recomendado: V2.

Motivo:

- acciones explicitas
- perfil/modo
- cobertura de mantenimiento y limpieza avanzada

Comandos base:

```bash
sudo ./post-install-v2.sh --action install --profile workstation --mode full
sudo ./post-install-v2.sh --action check-fix --profile workstation --mode full
sudo ./post-install-v2.sh --action verify --profile workstation
```

### Escenario C: Auditoria rapida por categoria sin menu

Recomendado: V3.

Motivo:

- sintaxis corta
- salida directa
- codigos de retorno utiles para automatizacion

Comando base:

```bash
./post-install-v3.sh --action verify-category --category optimization_base --dry-run
```

### Escenario D: Reconciliar faltantes de perfil con menor complejidad

Recomendado: V3.

Motivo:

- `check-fix` directo
- sin asistente
- resumen final de faltantes/fallos

Comando base:

```bash
./post-install-v3.sh --action check-fix --profile general_desktop
```

### Escenario E: Limpieza operativa integral y cron de mantenimiento

Recomendado: V2.

Motivo:

- acciones dedicadas `clean`, `clean-obsolete`, `clean-files`, `updates-cron`, `remove-cron`

Comandos base:

```bash
sudo ./post-install-v2.sh --action clean
sudo ./post-install-v2.sh --action updates-cron
```

## Fortalezas y trade-offs

### V1

Fortalezas:

- experiencia guiada
- muy util para escritorio y ajustes UX
- buena trazabilidad en menu

Trade-offs:

- menos amigable para automatizacion estricta
- mas acoplado a interaccion humana

### V2

Fortalezas:

- mayor alcance funcional
- acciones/mantenimiento maduros
- mejor para runbooks y operaciones repetitivas

Trade-offs:

- mayor complejidad de parametros
- curva de entrada mas alta

### V3

Fortalezas:

- interfaz corta y clara
- ideal para install/check-fix/verify
- verify-category rapido
- list-profiles/list-categories para descubrimiento inmediato

Trade-offs:

- no cubre todas las acciones operativas de V2 (por diseno)
- no incluye asistente interactivo

## Tabla de comandos minimos recomendados

| Objetivo | V1 | V2 | V3 |
|---|---|---|---|
| Instalar base trabajo | `sudo bash post-install.sh` | `sudo ./post-install-v2.sh --action install --profile workstation --mode full` | `./post-install-v3.sh --action install --profile general_desktop` |
| Corregir faltantes | Menu opcion 2 | `--action check-fix` | `--action check-fix` |
| Verificar perfil | Menu/verify por categoria | `--action verify --profile <p>` | `--action verify --profile <p>` |
| Verificar categoria | Menu opcion 12 | `--action verify-category --category <c>` | `--action verify-category --category <c>` |
| Listar perfiles/categorias | N/A en menu | `--list-profiles` | `--list-profiles` y `--list-categories` |
| Limpieza de duplicados | Menu opcion 13 | `--action clean-duplicates` | Implícita por preferencia en instalacion |

## Recomendacion oficial de uso combinado

Para operaciones robustas de campo:

1. Descubrimiento y baseline rapido:
- V3 `--list-profiles`, `--list-categories`, `--action verify --dry-run`

2. Provisionamiento principal:
- V2 `--action install --profile <perfil> --mode full`

3. Ajustes puntuales de escritorio/usuario:
- V1 cuando se requiera interaccion guiada

4. Auditoria de cierre:
- V3 `--action verify` o `--action verify-category`

## Politica de seleccion por riesgo

- Bajo riesgo operacional y usuario final interactivo:
  - V1
- Bajo riesgo con necesidad de automatizacion simple:
  - V3
- Cobertura operativa completa con mantenimiento continuo:
  - V2

## Referencias cruzadas

- Arquitectura V1: [docs/v1/ARCHITECTURE.md](../v1/ARCHITECTURE.md)
- Arquitectura V2: [docs/v2/ARCHITECTURE.md](../v2/ARCHITECTURE.md)
- Arquitectura V3: [docs/v3/ARCHITECTURE.md](../v3/ARCHITECTURE.md)
- Flujo integral: [docs/flows/debian-postinstall-full-flow.drawio](debian-postinstall-full-flow.drawio)
