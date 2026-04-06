# Arquitectura V1

## Objetivo

V1 es el flujo monolitico e interactivo orientado a categorias de uso. Prioriza:

- rapidez para equipos de escritorio
- menu guiado para operacion diaria
- acciones correctivas (check-fix, verify, clean)
- trazabilidad por logs y estado

Restriccion obligatoria del proyecto:

- no modificar ni reemplazar kernel

## Alcance funcional

El orquestador principal es [post-install.sh](../../post-install.sh).

Capacidades principales:

- instalacion por categorias
- check-fix por categoria
- reconfiguracion/reinstalacion por categoria
- remove-category con proteccion por comparticion
- verify por categoria
- clean, clean-obsolete, clean-files
- updates-cron y remove-cron
- clean-duplicates basado en catalogo
- perfilado GPU por proposito
- auditoria opcional con profile-json

## Entradas y configuracion

Flags CLI soportadas:

- --dry-run | -n
- --verbose | -v
- --auto | -y
- --profile-json <ruta>
- --catalog-json <ruta>
- --gpu-profile <auto|intel|amd|nvidia|none>
- --gpu-purpose <auto|general|gaming|design|ai>
- --help | -h

Fuentes de datos usadas por V1:

- catalogo de apps: [config/app-library.json](../../config/app-library.json)
- catalogo v3-optimized en evolucion (misma ruta, seccion dedicada)
- snapshot/auditoria JSON: [config/customization-profile.example.json](../../config/customization-profile.example.json)
- librerias compartidas:
  - [lib/app-catalog.sh](../../lib/app-catalog.sh)
  - [lib/profile-json.sh](../../lib/profile-json.sh)

## Arquitectura interna

Bloques de V1:

1. Preflight
- validacion de usuario/entorno
- preparacion de logs/estado
- validacion de catalogo JSON

2. Infra critica
- reparacion segura de APT/DPKG
- preparacion de base universal
- infraestructura de red/apt/flatpak

3. Menu interactivo
- seleccion de accion
- seleccion de categorias por matriz V1
- cancelacion y regreso seguro sin salir del proceso

4. Ejecutores por accion
- instalacion/check-fix/reinstall por categoria
- limpiezas operativas
- verificacion de estado y referencias

5. Post-hooks
- acciones de cierre cuando hubo cambios
- dashboard final
- resumen de exitos/omitidos/fallos

## Mapa de acciones del menu V1

Menu principal V1:

- 1 Instalar por categorias
- 2 Check and Fix por categoria
- 3 Reconfigurar categoria
- 4 Limpieza general
- 5 Limpiar innecesarios (reemplazados)
- 6 Panel de salud
- 7 Aplicar UX/UI
- 8 Eliminar por categoria (purga segura)
- 9 Comprobar actualizaciones + configurar cron
- 10 Referencias oficiales
- 11 Limpiar temporales y descargas de instaladores
- 12 Verificar por categoria
- 13 Limpiar duplicados (BD apps)
- 14 Eliminar cron de mantenimiento

La lista de categorias se controla por arrays internos V1 para mantener orden y trazabilidad de estado.

## Modelo de instalacion

Orden efectivo de decision por categoria:

1. Pre-acciones de catalogo (allowlist)
2. Instalacion APT/Flatpak segun catalogo
3. Deteccion de equivalentes para evitar reinstalaciones
4. Post-acciones de catalogo (allowlist)
5. Registro en archivo de estado

Comportamientos clave:

- soporte DRY-RUN
- idempotencia por paquete/app
- omision de items no resolubles en repos con trazabilidad
- deduplicacion apt/flatpak para evitar UX degradada

## Check-Fix y Verify

Check-Fix en V1:

- valida categoria seleccionada
- limpia preconfig conflictiva cuando aplica
- reinstala componentes faltantes
- reaplica postconfiguracion del modulo

Verify por categoria en V1:

- compara esperado vs instalado por modulo
- revisa APT y Flatpak
- reporta faltantes con salida legible de consola

Panel de salud:

- estado funcional de componentes clave (ejemplo: docker/vscode)
- chequeos base de sysctl/zram/servicios

## Remove-Category seguro

Objetivo:

- eliminar paquetes de una categoria sin romper otras

Reglas:

- no purgar paquetes compartidos con categorias instaladas
- limpiar Flatpak asociado solo si no esta compartido
- registrar cambios en estado para mantener consistencia

## Logging y estado

Rutas de ejecucion:

- logs: ./.runtime-logs/debian-postinstall-*.log
- estado: ./.runtime-logs/debian-postinstall-status.log

Eventos relevantes:

- RUN-START / RUN-END con duracion
- acciones ejecutadas/omitidas/fallidas
- decisiones de compatibilidad y repos

## Integracion de cron

Actualizaciones y mantenimiento:

- accion de alta: updates-cron
- accion de baja: remove-cron

Se recomienda usar remove-cron antes de reprovisionar para evitar cron huerfano.

## Seguridad y compatibilidad

Guardas principales:

- no tocar kernel/bootloader
- reparacion APT/DPKG no destructiva
- validacion de usuario objetivo
- manejo defensivo de dependencias faltantes
- uso de catalogo como fuente unica de inventario

## Flujo recomendado de operacion

1. Verificacion inicial:
- sudo bash post-install.sh --dry-run

2. Instalacion guiada:
- sudo bash post-install.sh

3. Correccion posterior:
- opcion check-fix sobre categorias con faltantes

4. Auditoria puntual:
- opcion verify-category en categorias criticas

5. Mantenimiento:
- clean + clean-obsolete + clean-files

## Troubleshooting rapido

- Error de catalogo JSON:
  - validar sintaxis del archivo y ruta de --catalog-json
- Faltante de repos externos:
  - revisar trazas [REPO:MISSING] y decidir fuente alternativa
- Duplicados de escritorio:
  - ejecutar clean-duplicates y revisar preferencia de catalogo
- Locks de APT/DPKG:
  - cerrar procesos apt en paralelo y relanzar check-fix

## Validacion minima recomendada

- bash -n post-install.sh
- smoke test menu V1 en dry-run
- verify-category en al menos 2 categorias
- comprobacion de logs RUN-START/RUN-END
