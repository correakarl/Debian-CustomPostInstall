# Estado del Proyecto

Ultima actualizacion: 2026-04-05
Responsable actual: Karl + Copilot

## En progreso

- Consolidar estabilidad de UX en XFCE para evitar bloqueos/suspensiones no deseadas.
- Mantener paridad funcional entre flujo V1 y V2 para fixes criticos.
- Extender capacidades tipo CRUD con mayor granularidad de seleccion y auditoria de integridad.
- Afinar mapa de paquetes por categoria (gaming/diseno/ai) segun pruebas reales de hardware.
- Verificar en campo la ejecucion de hooks declarativos `pre/post` de V1/V2 con hardware mixto.

## Completado recientemente

- Se agrego estrategia Flatpak-first para LibreOffice para mitigar apps duplicadas.
- Se incorporaron fixes de energia y bloqueo en XFCE (xfconf + logind override).
- Se agregaron paquetes de integracion UX relevantes (xfce4-goodies, pavucontrol, gvfs-backends, plugins de power manager).
- Se creo CHANGELOG.md con formato SemVer y seccion Unreleased.
- Se agrego perfil `ai-ml` en V2 con bundles seleccionables para ML/DL/agentes.
- Se agrego accion `verify` para validar estado instalado, faltantes y compatibilidad por perfil.
- Se agrego accion `verify-category` para auditoria por categoria.
- Se agrego accion `clean-duplicates` para limpieza de duplicados desde biblioteca JSON.
- Se agrego biblioteca [config/app-library.json](config/app-library.json) como base de inventario/fuentes/reglas de deduplicacion.
- Se agrego perfilado GPU por tipo/proposito para mejorar compatibilidad por categoria.
- Se completo paridad V1 para categoria AI, verificacion por categoria y limpieza de duplicados por catalogo.
- Se migro resolucion de perfiles/categorias de V1 y V2 a origen comun JSON con `lib/app-catalog.sh`.
- Se integro ejecucion de acciones declarativas del catalogo en V2 (`install`/`configure`) con allowlist segura.
- Se endurecio deduplicacion Office en V2: purga APT solo con Flatpak operativo/exportado y respeto de paquetes en hold.
- Se agrego fallback de aplicacion diferida de xfconf en V2 cuando no hay sesion grafica activa.
- Se agrego fallback secundario en login de usuario para ejecutar el one-shot aunque autostart XDG no dispare.
- Se agrego validacion preventiva de disponibilidad de dependencias APT/Flatpak en V1/V2 para omitir items no resolubles sin abortar flujo.
- Se agrego opcion de eliminacion de cron de mantenimiento en V1 y accion `remove-cron` en V2.
- Se incorporaron `LICENSE` (CC BY 4.0) y `NOTICE` para garantizar atribucion del proyecto.
- Se actualizo catalogo a `1.1.1` con metadata de repos externos opcionales para paquetes no presentes en fuentes base.
- Menus de opciones/categorias en V1 y V2 ajustados a vista por columnas para reducir scroll.
- Spinner de progreso recuperado en V2 para update/install/reinstall.
- Hooks PRE/POST de V1 y acciones post de V2 optimizados para evitar ejecuciones no necesarias segun accion actual.
- Corregido bug de parseo en V1 que inyectaba tokens JSON en listas de paquetes/flatpak durante instalacion por categoria.
- Mensajes `REPO:MISSING` ahora usan evidencia de `/var/log/apt/history.log` para distinguir repos externos previamente disponibles.
- `sources.apt` del catalogo normalizado a canales oficiales Debian (`main/security/updates`).
- Corregida deteccion cruzada APT/Flatpak en V1/V2 para que cada comprobacion respete su fuente real y evitar diagnosticos incorrectos (ej. virtualization/virtualbox).
- Snapshot/autoguardado ajustado en V1/V2 para ejecutarse solo cuando hubo acciones que modifican estado.
- Se documento flujo completo del aplicativo en `docs/flows/debian-postinstall-full-flow.drawio`.
- V1/V2 ahora guardan logs de ejecucion/error y estado en `./.runtime-logs/` dentro del proyecto, excluido del repo.
- V1/V2 ahora registran inicio/fin de cada ejecucion con marca temporal y duracion; se agrego control de crecimiento de logs/estado para reducir consumo de disco en chequeos repetidos.

## Proximo

- Etiquetar release v8.5.0 en git y publicar release notes.
- Crear diagnostico extendido para validar estado de:
  - XFCE power manager
  - screensaver
  - override de logind
  - deduplicacion de Office
- Definir smoke tests minimos para V1 y V2 post-instalacion.
- Ajustar catalogo de reemplazos base Debian 13 segun resultados de campo (equipos Intel/AMD/NVIDIA).
- Definir smoke test automatizable para validar hooks `pre/post` en perfiles `gaming`, `design`, `ai-ml`.
- Revisar paquetes no resolubles detectados en indices actuales (`steam`, `virtualbox`, `wine32`, `signal-desktop`, `telegram-desktop`, `netdata`, `helm`, `scrcpy`, `qemu-kvm`, `android-sdk-platform-tools-adb`, `exa`) y decidir estrategia por repo/alternativa.

## Riesgos y bloqueos

- Ajustes xfconf quedan mitigados con doble fallback (autostart + login shell); validar ejecucion one-shot en distintos display managers.
- Diferencias de entorno (X11/Wayland/sesiones remotas) pueden afectar comportamiento de bloqueo.
- Disponibilidad de repositorios externos/third-party puede variar por mirror/politica local y afectar instalacion de paquetes opcionales.

## Decision de arquitectura vigente

- No modificar ni reemplazar kernel.
- Priorizar estabilidad sobre cambios agresivos.
- Evitar duplicidad APT/Flatpak en apps de uso diario cuando degrade la UX.

## Comandos de validacion recomendados

- bash -n post-install.sh
- bash -n post-install-v2.sh
- bash -n modules/v2/20-ux-light.sh
- bash -n lib/v2/profiles.sh

## Notas de operacion

- Mantener este archivo vivo despues de cada lote de cambios.
- Si una tarea queda parcial, moverla a Proximo con contexto minimo reproducible.
