#!/bin/bash
# =============================================================================
# DEBIAN 13 (TRIXIE) - OMNI-OPTIMIZER & THEME ENGINE v8.2
# Autor: Karl Michael Correa Rivero (Full Stack Developer)
# Propósito: Post-instalación resiliente con fixes para Electron/VS Code en
#            entornos con restricciones de red, optimización DNS/IPv6, y
#            documentación técnica para mantenimiento futuro.
#
# MANTENIMIENTO:
#   • Logs: /var/log/debian-postinstall-*.log (rotación: últimos 2)
#   • Estado: /var/log/debian-postinstall-status.log
#   • Para añadir fix: función setup_XXX_fix() + llamar en configure_module_post_install()
#   • Estructura modular: lib/utils.sh, lib/modules/*.sh (futuro)
# =============================================================================

set -o pipefail
set -o errtrace  # Heredar ERR en funciones/subshells

# -----------------------------------------------------------------------------
# CONFIGURACIÓN DE COLORES Y FORMATEO
# -----------------------------------------------------------------------------
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# -----------------------------------------------------------------------------
# VARIABLES GLOBALES (Inicialización temprana - CRÍTICO)
# -----------------------------------------------------------------------------
declare -a REPORT_SUCCESS=() REPORT_SKIPPED=() REPORT_FAILED=()
declare -A INSTALLED_MODULES=() LEVEL_SELECTED=() RAM_LEVEL=()

# Paths de logs y estado
readonly LOGFILE="/var/log/debian-postinstall-$(date +%F-%H%M).log"
readonly STATUSFILE="/var/log/debian-postinstall-status.log"
readonly BACKUP_DIR="/root/.omni-backup"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Flags de control
DRY_RUN=false
VERBOSE=false
AUTO_CONFIRM=false
PROFILE_JSON=""

# Libreria de auditoria de perfil JSON (opcional)
if [[ -f "${SCRIPT_DIR}/lib/profile-json.sh" ]]; then
    # shellcheck source=lib/profile-json.sh
    source "${SCRIPT_DIR}/lib/profile-json.sh"
fi

# Usuario y entorno (definir ANTES de cualquier uso)
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Este script debe ejecutarse con sudo${NC}" >&2
    exit 1
fi

# Detectar usuario real de forma segura
SUDO_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
if [[ -z "$SUDO_USER" || "$SUDO_USER" == "root" ]]; then
    echo -e "${RED}Error: No se pudo detectar el usuario objetivo${NC}" >&2
    exit 1
fi

# VALIDACIÓN DE SEGURIDAD: Sanitizar SUDO_USER
if ! [[ "$SUDO_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo -e "${RED}Error: Nombre de usuario inválido o potencialmente malicioso${NC}" >&2
    exit 1
fi

readonly USER_HOME="/home/$SUDO_USER"
readonly DESKTOP_ENV="${XDG_CURRENT_DESKTOP:-unknown}"

# -----------------------------------------------------------------------------
# DETECCIÓN DE RECURSOS DEL SISTEMA
# -----------------------------------------------------------------------------
readonly TOTAL_RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "4")
readonly CPU_CORES=$(nproc 2>/dev/null || echo "2")
readonly SYSTEM_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
readonly GPU_VENDOR=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | grep -oiE 'nvidia|amd|intel' | tr '[:upper:]' '[:lower:]' || echo "unknown")
readonly IS_LOW_RAM=$([[ $TOTAL_RAM_GB -lt 4 ]] && echo "true" || echo "false")

# Configurar nivel RAM
if $IS_LOW_RAM; then
    RAM_LEVEL["minimal"]=1
    RAM_LEVEL["zram_fraction"]="0.75"
    RAM_LEVEL["swappiness"]="1"
else
    RAM_LEVEL["minimal"]=0
    RAM_LEVEL["zram_fraction"]="0.5"
    RAM_LEVEL["swappiness"]="10"
fi

# -----------------------------------------------------------------------------
# REDIRECCIÓN DE SALIDA: pantalla + log simultáneamente
# -----------------------------------------------------------------------------
exec > >(tee -a "$LOGFILE") 2>&1

# =============================================================================
# UTILIDADES CORE (lib/utils.sh equivalente)
# =============================================================================

# Logging con timestamp
log_msg() {
    echo -e "${CYAN}[${BOLD}$(date '+%H:%M:%S')${NC}${CYAN}]${NC} ${GRAY}→${NC} $1"
}

log_progress() {
    echo -e "${BLUE}[${BOLD}PROGRESO${NC}${BLUE}]${NC} ${WHITE}$1${NC}"
}

log_status() {
    local icon="" status_type="$1" message="$2"
    case "$status_type" in
        "ok") icon="${GREEN}+${NC}"; REPORT_SUCCESS+=("$message") ;;
        "skip") icon="${YELLOW}~${NC}"; REPORT_SKIPPED+=("$message") ;;
        "fail") icon="${RED}!${NC}"; REPORT_FAILED+=("$message") ;;
    esac
    echo -e "  ${icon} $message"
}

section_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

# Verificaciones de paquetes
is_apt_installed() { dpkg -l "$1" &>/dev/null; }
cmd_exists() { command -v "$1" &>/dev/null; }
is_flatpak_installed() { flatpak list --app --columns=application 2>/dev/null | grep -q "^$1$"; }

# Gestión de estado de módulos
mark_module_installed() {
    local module="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INSTALLED: $module" >> "$STATUSFILE"
    INSTALLED_MODULES["$module"]=1
    log_status "ok" "Módulo registrado: $module"
}

mark_module_removed() {
    local module="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - REMOVED: $module" >> "$STATUSFILE"
    unset 'INSTALLED_MODULES[$module]'
    log_status "ok" "Módulo removido: $module"
}

is_module_installed() {
    local module="$1"
    [[ "${INSTALLED_MODULES[$module]:-}" == "1" ]] && return 0
    grep -q "INSTALLED: $module" "$STATUSFILE" 2>/dev/null && return 0
    return 1
}

is_zram_active() {
    systemctl is-active --quiet zramswap 2>/dev/null && return 0
    systemctl is-active --quiet systemd-zram-setup@zram0 2>/dev/null && return 0
    swapon --show 2>/dev/null | grep -q 'zram' && return 0
    [[ -b /dev/zram0 ]] && return 0
    return 1
}

ensure_zram_active() {
    systemctl enable --now zramswap &>/dev/null || true
    systemctl restart zramswap &>/dev/null || true
    systemctl enable --now systemd-zram-setup@zram0 &>/dev/null || true
    if is_zram_active; then
        log_status "ok" "ZRAM activo"
    else
        log_status "fail" "ZRAM no pudo activarse automáticamente"
    fi
}

# Obtener versión LTS de Node.js con fallback
get_latest_lts_version() {
    local lts
    lts=$(curl -s --connect-timeout 10 https://nodejs.org/dist/index.json 2>/dev/null | \
          jq -r '.[]|select(.lts)|.version'|head -1|cut -d. -f1)
    if [[ -z "$lts" || ! "$lts" =~ ^[0-9]+$ ]]; then
        log_msg "${YELLOW}Advertencia: No se pudo obtener LTS de Node.js, usando v20 por defecto${NC}"
        lts="20"
    fi
    echo "$lts"
}

# =============================================================================
# SPINNER MEJORADO (Sin race conditions)
# =============================================================================

show_spinner() {
    local msg="$1"; shift
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    echo -ne "${GRAY}$msg ${NC}"
    
    # Ejecutar comando en background y capturar PID
    "$@" &>/dev/null &
    local pid=$!
    
    # Animación mientras el proceso esté activo
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${spin:i++%${#spin}:1} ${GRAY}$msg${NC}"
        sleep 0.08
    done
    
    # Esperar resultado final
    wait "$pid"
    local status=$?
    
    # Limpiar línea y mostrar resultado
    printf "\r"
    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $msg"
        return 0
    else
        echo -e "${RED}✗${NC} $msg (código: $status)"
        return 1
    fi
}

# Instalación APT con progreso
install_with_progress() {
    local pkg="$1" desc="${2:-$pkg}"
    local compat_reason=""
    
    if $DRY_RUN; then
        log_msg "[DRY-RUN] Instalaría: $desc"
        return 0
    fi
    
    if is_apt_installed "$pkg"; then
        log_status "skip" "$desc (ya instalado)"
        return 0
    fi

    if ! check_package_compatibility "$pkg" compat_reason; then
        log_status "skip" "[COMPAT:BLOCK] $desc - $compat_reason"
        return 0
    else
        log_msg "[COMPAT:OK] $desc"
    fi
    
    if show_spinner "Instalando $desc..." apt install -y "$pkg"; then
        log_status "ok" "$desc"
        return 0
    else
        log_status "fail" "$desc"
        return 1
    fi
}

# Verificación de compatibilidad por paquete con flag visible.
check_package_compatibility() {
    local pkg="$1"
    local __reason_var="$2"
    local reason=""

    case "$pkg" in
        steam|microsoft-edge-stable|google-chrome-stable|opera-stable|wine32|libvulkan1:i386|mesa-vulkan-drivers:i386|libgl1-mesa-dri:i386)
            if [[ "$SYSTEM_ARCH" != "amd64" ]]; then
                reason="requiere arquitectura amd64"
                printf -v "$__reason_var" '%s' "$reason"
                return 1
            fi
            ;;
        blender|kdenlive|obs-studio)
            if [[ $TOTAL_RAM_GB -lt 4 ]]; then
                reason="recomendado >= 4GB RAM"
                printf -v "$__reason_var" '%s' "$reason"
                return 1
            fi
            ;;
    esac

    printf -v "$__reason_var" '%s' "compatible"
    return 0
}

# Instalación Flatpak con progreso
install_flatpak_with_progress() {
    local app_id="$1" app_name="${2:-$app_id}"
    
    if $DRY_RUN; then
        log_msg "[DRY-RUN] Flatpak: $app_name"
        return 0
    fi
    
    if ! cmd_exists "flatpak"; then
        log_status "fail" "Flatpak no disponible"
        return 1
    fi
    
    if is_flatpak_installed "$app_id"; then
        log_status "skip" "Flatpak: $app_name"
        return 0
    fi
    
    if show_spinner "Instalando $app_name (Flatpak)..." \
       flatpak install flathub "$app_id" -y --noninteractive; then
        log_status "ok" "Flatpak: $app_name"
        return 0
    else
        log_status "fail" "Flatpak: $app_name"
        return 1
    fi
}

# =============================================================================
# VALIDACIÓN DEL ENTORNO (Pre-ejecución)
# =============================================================================

validate_environment() {
    local errors=0
    
    log_msg "Validando entorno de ejecución..."
    
    # 1. Conectividad básica a repositorios
    if ! curl -s --connect-timeout 10 https://deb.debian.org &>/dev/null; then
        log_msg "${RED}Error: Sin conexión a repositorios Debian${NC}"
        ((errors++))
    fi
    
    # 2. Espacio en disco (mínimo 10GB para instalación completa)
    local available_gb
    available_gb=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}' || echo "0")
    if [[ $available_gb -lt 10 ]]; then
        log_msg "${RED}Error: Espacio insuficiente (${available_gb}GB < 10GB requeridos)${NC}"
        ((errors++))
    fi
    
    # 3. Dependencias críticas del sistema
    local required_cmds=("curl" "wget" "gpg" "apt" "dpkg")
    for cmd in "${required_cmds[@]}"; do
        if ! cmd_exists "$cmd"; then
            log_msg "${RED}Error: '$cmd' no encontrado en PATH${NC}"
            ((errors++))
        fi
    done
    
    # 4. Permisos de escritura en directorios críticos
    if ! touch /var/log/debian-postinstall-test.log 2>/dev/null; then
        log_msg "${RED}Error: Sin permisos de escritura en /var/log${NC}"
        ((errors++))
    else
        rm -f /var/log/debian-postinstall-test.log
    fi
    
    # 5. HOME del usuario accesible
    if [[ ! -d "$USER_HOME" ]]; then
        log_msg "${RED}Error: Directorio home '$USER_HOME' no existe${NC}"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_msg "${RED}Validación fallida: $errors error(es) encontrado(s)${NC}"
        return 1
    fi
    
    log_status "ok" "Entorno validado correctamente"
    return 0
}

# =============================================================================
# PARSEO DE FLAGS Y AYUDA
# =============================================================================

parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=true
                log_msg "[DRY-RUN] activado: solo simulación"
                shift ;;
            --verbose|-v)
                VERBOSE=true
                set -x
                log_msg "[VERBOSE] activado: trazabilidad completa"
                shift ;;
            --auto|-y)
                AUTO_CONFIRM=true
                log_msg "[AUTO-CONFIRM] activado: sin prompts"
                shift ;;
            --help|-h)
                show_help
                exit 0 ;;
            --profile-json)
                PROFILE_JSON="$2"
                shift 2 ;;
            *)
                shift ;;
        esac
    done
}

show_help() {
    cat <<EOF
OMNI-OPTIMIZER v8.2 - Post-instalación resiliente para Debian 13

USO: sudo ./post-install.sh [OPCIONES]

OPCIONES:
  -n, --dry-run     Simular sin ejecutar cambios
  -v, --verbose     Trazabilidad completa (debug)
  -y, --auto        Confirmar automáticamente prompts
    --profile-json    Ruta a JSON de auditoría de personalización/comprobación
  -h, --help        Mostrar ayuda

EJEMPLOS:
  sudo ./post-install.sh                    # Instalación normal
  sudo ./post-install.sh --dry-run          # Probar sin instalar
  sudo ./post-install.sh -v -y              # Auto + verbose
    sudo ./post-install.sh --profile-json ./config/customization-profile.example.json

NOTAS:
  • Logs: /var/log/debian-postinstall-*.log
  • Estado: /var/log/debian-postinstall-status.log
  • Fix VS Code: aplicado automáticamente en entornos con latencia
  • Requiere: conexión a internet, 10GB libres, usuario no-root con sudo
EOF
}

# =============================================================================
# INFRAESTRUCTURA CRÍTICA
# =============================================================================

setup_critical_infra() {
    log_msg "Configurando infraestructura crítica..."
    
    # 1. Sudoers Fix (con validación)
    local sudoers_file="/etc/sudoers.d/$SUDO_USER"
    if [[ ! -f "$sudoers_file" ]]; then
        if ! echo "$SUDO_USER ALL=(ALL:ALL) ALL" | tee "$sudoers_file" &>/dev/null; then
            log_status "fail" "No se pudo crear sudoers para $SUDO_USER"
            return 1
        fi
        chmod 440 "$sudoers_file"
        # Validar sintaxis de sudoers
        if ! visudo -c -f "$sudoers_file" &>/dev/null; then
            rm -f "$sudoers_file"
            log_status "fail" "Sintaxis de sudoers inválida, archivo revertido"
            return 1
        fi
        log_status "ok" "Privilegios sudoers para $SUDO_USER"
    fi

    # 2. Arquitectura i386 para gaming/compatibilidad
    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
        if dpkg --add-architecture i386 &>/dev/null; then
            apt update &>/dev/null
            log_status "ok" "Arquitectura i386 habilitada"
        else
            log_status "fail" "No se pudo añadir arquitectura i386"
        fi
    fi

    # 3. DNS optimizado (compatible con systemd-resolved)
    configure_dns_optimized

    # 4. Forzar IPv4 para apt (evitar timeouts en IPv6)
    local apt_ipv4_conf="/etc/apt/apt.conf.d/99force-ipv4"
    if [[ ! -f "$apt_ipv4_conf" ]]; then
        echo 'Acquire::ForceIPv4 "true";' > "$apt_ipv4_conf"
        log_status "ok" "APT forzado a IPv4 para evitar timeouts"
    fi

    # 5. Repositorios Externos con GPG moderno (keyrings)
    log_msg "Configurando repositorios externos..."
    setup_external_repos

    # Actualizar índices
    if apt update &>/dev/null; then
        log_status "ok" "Repositorios externos listos"
    else
        log_status "fail" "Error actualizando repositorios"
        return 1
    fi
    
    return 0
}

# Configuración DNS compatible con systemd-resolved
configure_dns_optimized() {
    local resolv_conf="/etc/resolv.conf"
    local systemd_resolved_active=false
    
    # Detectar si systemd-resolved está gestionando DNS
    if systemctl is-active --quiet systemd-resolved 2>/dev/null && \
       [[ -L "$resolv_conf" && "$(readlink -f "$resolv_conf")" == *systemd* ]]; then
        systemd_resolved_active=true
    fi
    
    if $systemd_resolved_active; then
        # Configurar vía systemd-resolved
        local resolved_conf="/etc/systemd/resolved.conf"
        if ! grep -q "^DNS=8.8.8.8 1.1.1.1" "$resolved_conf" 2>/dev/null; then
            cp "$resolved_conf" "${resolved_conf}.bak" 2>/dev/null
            cat <<EOF > "$resolved_conf"
[Resolve]
DNS=8.8.8.8 1.1.1.1 9.9.9.9
FallbackDNS=
Domains=
LLMNR=no
MulticastDNS=no
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
EOF
            systemctl restart systemd-resolved &>/dev/null
            log_status "ok" "DNS optimizado vía systemd-resolved"
        fi
    else
        # Método tradicional con backup
        if ! grep -q "nameserver 8.8.8.8" "$resolv_conf" 2>/dev/null; then
            cp "$resolv_conf" "${resolv_conf}.omni-bak" 2>/dev/null
            cat <<EOF > "$resolv_conf"
# OMNI-OPTIMIZER: DNS optimizado para latencia/restricciones
# Prioridad IPv4 para evitar timeouts en IPv6
options timeout:2 attempts:3 rotate
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 9.9.9.9
EOF
            log_status "ok" "DNS optimizado: 8.8.8.8 + 1.1.1.1 (IPv4 priority)"
        fi
    fi
}

# Configuración de repositorios externos con keyrings modernos
setup_external_repos() {
    local keyring_dir="/usr/share/keyrings"
    
    # Microsoft GPG key (formato moderno)
    if [[ ! -f "$keyring_dir/microsoft.gpg" ]]; then
        if wget -qO- https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null | \
           gpg --dearmor -o "$keyring_dir/microsoft.gpg" 2>/dev/null; then
            chmod 644 "$keyring_dir/microsoft.gpg"
            log_status "ok" "Llave Microsoft importada (formato moderno)"
        else
            log_status "fail" "No se pudo importar llave Microsoft"
        fi
    fi
    
    # VS Code repo
    if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
        echo "deb [arch=amd64 signed-by=$keyring_dir/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
        log_status "ok" "Repositorio VS Code añadido"
    fi

    # Edge repo
    if [[ ! -f /etc/apt/sources.list.d/microsoft-edge.list ]]; then
        echo "deb [arch=amd64 signed-by=$keyring_dir/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list
        log_status "ok" "Repositorio Edge añadido"
    fi

    # Chrome repo
    if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]]; then
        if wget -q -O - https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null | \
           gpg --dearmor -o "$keyring_dir/google-chrome.gpg" 2>/dev/null; then
            chmod 644 "$keyring_dir/google-chrome.gpg"
            echo "deb [arch=amd64 signed-by=$keyring_dir/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
            log_status "ok" "Repositorio Chrome añadido"
        else
            log_status "fail" "No se pudo importar llave Google Chrome"
        fi
    fi

    # Opera repo
    if [[ ! -f /etc/apt/sources.list.d/opera-stable.list ]]; then
        if wget -qO- https://deb.opera.com/archive.key 2>/dev/null | \
           gpg --dearmor -o "$keyring_dir/opera.gpg" 2>/dev/null; then
            chmod 644 "$keyring_dir/opera.gpg"
            echo "deb [arch=amd64 signed-by=$keyring_dir/opera.gpg] https://deb.opera.com/opera-stable/ stable non-free" > /etc/apt/sources.list.d/opera-stable.list
            log_status "ok" "Repositorio Opera añadido"
        else
            log_status "fail" "No se pudo importar llave Opera"
        fi
    fi
}

# =============================================================================
# FIX ESPECÍFICO: VS Code / Electron (Red resiliente)
# =============================================================================

# [MANTENIMIENTO]: Esta función aplica lecciones de entornos con restricciones
# Problema: "Failed to fetch" en Marketplace por SSL/latencia/IPv6
# Solución: Purge cache + SSL bypass + IPv4 priority + GPG moderno
setup_vscode_network_fix() {
    log_msg "Aplicando fix de red para VS Code (Electron/Venezuela fix)..."
    local code_user_dir="$USER_HOME/.config/Code/User"
    
    # 1. Purge de cache de Electron (base de datos corrupta por micro-cortes)
    local cache_dirs=("$USER_HOME/.config/Code/CachedData" 
                      "$USER_HOME/.config/Code/Cache" 
                      "$USER_HOME/.config/Code/CachedExtensions")
    local purged=false
    for dir in "${cache_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir" 2>/dev/null && purged=true
        fi
    done
    $purged && log_status "ok" "Cache de Electron purgado (evita 'Failed to fetch')"
    
    # 2. Crear/actualizar settings.json con configuraciones de red resilientes
    mkdir -p "$code_user_dir"
    local settings_file="$code_user_dir/settings.json"
    
    # Config base para entornos con latencia/restricciones
    local -A vscode_fixes=(
        ["http.proxyStrictSSL"]="false"
        ["http.proxySupport"]="\"off\""
        ["update.mode"]="\"none\""
        ["extensions.autoUpdate"]="false"
        ["telemetry.telemetryLevel"]="\"off\""
        ["security.workspace.trust.enabled"]="false"
    )
    
    if [[ ! -f "$settings_file" ]]; then
        # Crear archivo nuevo con configuración completa
        {
            echo "{"
            local first=true
            for key in "${!vscode_fixes[@]}"; do
                $first || echo ","
                printf '  "%s": %s' "$key" "${vscode_fixes[$key]}"
                first=false
            done
            echo -e "\n}"
        } > "$settings_file"
        log_status "ok" "VS Code settings.json creado con fix de red"
    else
        # Usar jq para manipulación segura de JSON (si está disponible)
        if cmd_exists "jq"; then
            for key in "${!vscode_fixes[@]}"; do
                if ! jq -e "has(\"$key\")" "$settings_file" &>/dev/null; then
                    local value="${vscode_fixes[$key]}"
                    # Parsear valor: si tiene comillas es string, si no es boolean
                    if [[ "$value" =~ ^\" ]]; then
                        jq --arg k "$key" --arg v "${value//\"/}" \
                           '. + {($k): $v}' "$settings_file" > "${settings_file}.tmp"
                    else
                        jq --arg k "$key" --argjson v "$value" \
                           '. + {($k): $v}' "$settings_file" > "${settings_file}.tmp"
                    fi
                    mv "${settings_file}.tmp" "$settings_file"
                fi
            done
            log_status "ok" "VS Code settings.json actualizado con fix de red (jq)"
        else
            # Fallback sin jq: solo añadir si no existe (menos robusto)
            for key in "${!vscode_fixes[@]}"; do
                if ! grep -q "\"$key\"" "$settings_file" 2>/dev/null; then
                    sed -i "/^}/i\\    \"$key\": ${vscode_fixes[$key]}," "$settings_file" 2>/dev/null
                fi
            done
            log_status "ok" "VS Code settings.json actualizado (fallback)"
        fi
    fi
    
    # 3. Forzar permisos correctos
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config/Code" 2>/dev/null
    
    # 4. Crear script de diagnóstico para el usuario (opcional)
    local diagnostic_script="$USER_HOME/.vscode-network-diagnostic.sh"
    cat <<'DIAGNOSTIC_EOF' > "$diagnostic_script"
#!/bin/bash
# VS Code Network Diagnostic - Ejecutar si Marketplace falla
echo "=== Diagnóstico de red para VS Code ==="
echo "1. Verificando conectividad..."
curl -I --connect-timeout 5 https://marketplace.visualstudio.com &>/dev/null && echo "✓ Marketplace accesible" || echo "✗ Marketplace no accesible"
echo "2. Verificando DNS..."
nslookup marketplace.visualstudio.com 8.8.8.8 &>/dev/null && echo "✓ DNS responde" || echo "✗ DNS timeout"
echo "3. Verificando IPv4/IPv6..."
curl -4 -I --connect-timeout 5 https://marketplace.visualstudio.com &>/dev/null && echo "✓ IPv4 funciona" || echo "✗ IPv4 falla"
curl -6 -I --connect-timeout 5 https://marketplace.visualstudio.com &>/dev/null 2>&1 | grep -q "Failed" && echo "⚠ IPv6 puede tener problemas" || echo "✓ IPv6 funciona"
echo ""
echo "Si falla: ejecutar 'rm -rf ~/.config/Code/CachedData' y reiniciar VS Code"
DIAGNOSTIC_EOF
    chmod +x "$diagnostic_script"
    chown "$SUDO_USER:$SUDO_USER" "$diagnostic_script"
    
    log_status "ok" "Fix VS Code completado + script de diagnóstico creado"
}

# Fix genérico para apps Electron (Discord, Spotify, WhatsApp)
setup_electron_apps_fix() {
    log_msg "Aplicando fix de red para apps Electron..."
    
    # Discord
    if [[ -d "$USER_HOME/.config/discord" ]]; then
        local discord_settings="$USER_HOME/.config/discord/0.0.XX/settings.json"
        mkdir -p "$(dirname "$discord_settings")"
        if [[ ! -f "$discord_settings" ]]; then
            echo '{"HTTPProxyStrictSSL":false}' > "$discord_settings"
            log_status "ok" "Discord: fix SSL aplicado"
        fi
    fi
    
    # Spotify
    if [[ -d "$USER_HOME/.config/spotify" ]]; then
        # Spotify no tiene settings.json público, pero podemos forzar env var
        if ! grep -q "SPOTIFY_HTTPS" "$USER_HOME/.bashrc" 2>/dev/null; then
            echo 'export SPOTIFY_HTTPS=0  # Fix para entornos con SSL restrictivo' >> "$USER_HOME/.bashrc"
            log_status "ok" "Spotify: variable de entorno para SSL aplicada"
        fi
    fi
    
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config" 2>/dev/null
    log_status "ok" "Fix Electron apps completado"
}

# =============================================================================
# HOOKS DE CONFIGURACIÓN: PRE/POST INSTALACIÓN
# =============================================================================

pre_install_hooks() {
    log_msg "Ejecutando hooks PRE-instalación..."
    
    # Infraestructura crítica primero
    setup_critical_infra || {
        log_msg "${RED}Error en infraestructura crítica, continuando con precaución${NC}"
    }
    
    # Actualizar índices
    apt update &>/dev/null
    
    # Configurar Flatpak si no existe
    if ! is_apt_installed "flatpak"; then
        if apt install -y flatpak &>/dev/null; then
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>/dev/null
            log_status "ok" "Flatpak instalado y configurado"
        else
            log_status "fail" "No se pudo instalar Flatpak"
        fi
    fi
    
    log_status "ok" "Hooks PRE-instalación completados"
}

post_install_hooks() {
    log_msg "Ejecutando hooks POST-instalación..."
    
    # Actualizar cache de fuentes
    fc-cache -f &>/dev/null
    
    # Recargar systemd
    systemctl daemon-reload &>/dev/null
    
    # Limpieza de paquetes
    apt autoclean &>/dev/null
    
    # Actualizar base de datos de localizaciones
    updatedb &>/dev/null
    
    log_status "ok" "Hooks POST-instalación completados"
}

# =============================================================================
# GESTIÓN DE LOGS: Rotación automática
# =============================================================================

rotate_logs() {
    local keep=2
    local logs=($(ls -t /var/log/debian-postinstall-*.log 2>/dev/null))
    
    if [[ ${#logs[@]} -gt $keep ]]; then
        for ((i=keep; i<${#logs[@]}; i++)); do
            [[ "${logs[$i]}" != "$LOGFILE" ]] && rm -f "${logs[$i]}" 2>/dev/null
        done
        log_status "ok" "Logs antiguos rotados (últimos $keep conservados)"
    fi
    
    # Rotar archivos de estado
    local states=($(ls -t /var/log/debian-postinstall-status*.log 2>/dev/null))
    [[ ${#states[@]} -gt 1 ]] && rm -f "${states[@]:1}" 2>/dev/null
}

# =============================================================================
# BACKUP DE CONFIGURACIONES CRÍTICAS
# =============================================================================

backup_critical_configs() {
    if $DRY_RUN; then return 0; fi
    
    local timestamp=$(date +%F-%H%M)
    local backup_path="$BACKUP_DIR/$timestamp"
    
    mkdir -p "$backup_path" || {
        log_status "fail" "No se pudo crear directorio de backup"
        return 1
    }
    
    # Configurar permisos restrictivos
    chmod 700 "$BACKUP_DIR" "$backup_path"
    
    log_msg "Backup de configs en $backup_path..."
    
    # Archivos de configuración críticos
    local configs=(
        "/etc/apt/sources.list"
        "/etc/sysctl.conf" 
        "/etc/default/zramswap"
        "/etc/fstab"
        "/etc/ssh/sshd_config"
        "/etc/resolv.conf"
    )
    
    for cfg in "${configs[@]}"; do
        if [[ -f "$cfg" ]]; then
            cp "$cfg" "$backup_path/" 2>/dev/null && \
            chmod 600 "$backup_path/$(basename "$cfg")" && \
            log_status "ok" "Backup: $(basename "$cfg")"
        fi
    done
    
    # Backup de config de usuario
    if [[ -d "$USER_HOME/.config" ]]; then
        mkdir -p "$backup_path/user-config"
        cp -r "$USER_HOME/.config" "$backup_path/user-config/" 2>/dev/null && \
        chown -R "$SUDO_USER:$SUDO_USER" "$backup_path/user-config" && \
        log_status "ok" "Backup: config de usuario"
    fi
    
    # Registrar último backup
    echo "$backup_path" > "$BACKUP_DIR/latest"
    chmod 600 "$BACKUP_DIR/latest"
    
    log_status "ok" "Backup completado"
    return 0
}

# =============================================================================
# OPTIMIZACIÓN DEL SISTEMA BASE
# =============================================================================

readonly OPTIMIZATION_APT=(
    zram-tools earlyoom irqbalance tlp tlp-rdw thermald preload 
    haveged sysstat lm-sensors picom xdotool wmctrl
)

apply_system_optimizations() {
    section_header "[OPTIMIZACIÓN] Aplicando mejoras al sistema base"
    
    # Instalar paquetes de optimización
    for pkg in "${OPTIMIZATION_APT[@]}"; do
        install_with_progress "$pkg" "Optimización: $pkg"
    done
    
    # ZRAM configuration
    if [[ -f /etc/default/zramswap ]]; then
        cat <<EOF > /etc/default/zramswap
# OMNI-OPTIMIZER: Configuración ZRAM
ZRAM_FRACTION=${RAM_LEVEL["zram_fraction"]}
ZRAM_COMPRESSOR=lz4
EOF
        ensure_zram_active
        log_status "ok" "ZRAM configurado (${RAM_LEVEL["zram_fraction"]} RAM, lz4)"
    fi
    
    # EarlyOOM configuration
    if [[ -f /etc/default/earlyoom ]]; then
        sed -i 's/EARLYOOM_ARGS=""/EARLYOOM_ARGS="-m 3 -s 5"/' /etc/default/earlyoom 2>/dev/null
        systemctl restart earlyoom &>/dev/null
        log_status "ok" "EarlyOOM configurado (3% RAM / 5% swap)"
    fi
    
    # Sysctl optimizations
    if ! grep -q "vm.swappiness=${RAM_LEVEL["swappiness"]}" /etc/sysctl.conf 2>/dev/null; then
        cat <<EOF >> /etc/sysctl.conf
# OMNI-OPTIMIZER: Optimizaciones de kernel
vm.swappiness=${RAM_LEVEL["swappiness"]}
vm.vfs_cache_pressure=50
net.core.default_qdisc=fq_codel
net.ipv4.tcp_congestion_control=bbr
EOF
        sysctl -p &>/dev/null
        log_status "ok" "Sysctl optimizado"
    fi
    
    # Swap file de 4GB (si no existe)
    if [[ ! -f /swapfile ]]; then
        if fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none 2>/dev/null; then
            chmod 600 /swapfile
            mkswap /swapfile &>/dev/null
            swapon /swapfile &>/dev/null
            grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
            log_status "ok" "Swap file de 4GB creado"
        else
            log_status "fail" "No se pudo crear swap file"
        fi
    fi
    
    # Early KMS para Intel
    if [[ "$GPU_VENDOR" == "intel" ]]; then
        if ! grep -q "^i915$" /etc/initramfs-tools/modules 2>/dev/null; then
            echo "i915" >> /etc/initramfs-tools/modules
            update-initramfs -u &>/dev/null
            log_status "ok" "Early KMS para Intel habilitado"
        fi
    fi
    
    # TRIM automático para SSD
    systemctl enable --now fstrim.timer &>/dev/null
    
    # Font rendering optimizado
    if [[ ! -f "$USER_HOME/.config/fontconfig/fonts.conf" ]]; then
        mkdir -p "$USER_HOME/.config/fontconfig"
        cat <<'FONTCONF_EOF' > "$USER_HOME/.config/fontconfig/fonts.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
  </match>
</fontconfig>
FONTCONF_EOF
        chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config/fontconfig"
        fc-cache -f &>/dev/null
        log_status "ok" "Font rendering optimizado"
    fi
    
    mark_module_installed "optimization"
    echo -e "${GREEN}✓ Optimización del sistema base completada${NC}\n"
}

# =============================================================================
# ARQUITECTURA DE PAQUETES POR MÓDULO
# =============================================================================

# Base universal (siempre instalada)
readonly UNIVERSAL_BASE=(
    curl wget git ca-certificates gnupg apt-transport-https 
    neovim gedit htop less tree bash-completion zip unzip p7zip-full 
    tar zstd net-tools dnsutils iputils-ping traceroute 
    ufw fail2ban unattended-upgrades 
    fonts-firacode fonts-noto fonts-noto-color-emoji fontconfig 
    jq yq gawk sed grep findutils 
    gtk2-engines-murrine gtk2-engines-pixbuf libfreetype6-dev
)

# Módulos por categoría
readonly MODULE_BROWSERS=(firefox-esr google-chrome-stable microsoft-edge-stable opera-stable)
readonly MODULE_OFFICE=(libreoffice-writer libreoffice-calc libreoffice-impress evince okular thunderbird)
readonly MODULE_MULTIMEDIA=(vlc mpv ffmpeg libavcodec-extra)
readonly MODULE_DEV_CORE=(code build-essential pkg-config libssl-dev git-lfs gh terminator tmux)
readonly MODULE_DEV_CLI=(fzf ripgrep fd-find bat exa httpie mkcert)
readonly MODULE_DEV_WEB=(code docker-ce docker-ce-cli containerd.io docker-compose-plugin)
readonly MODULE_DEV_CONTAINERS=(podman podman-docker kubectl helm)
readonly MODULE_DEV_MOBILE=(adb fastboot scrcpy)
readonly MODULE_DESIGN_GRAPHIC=(gimp inkscape krita fontforge)
readonly MODULE_DESIGN_VIDEO=(kdenlive audacity obs-studio handbrake-cli)
readonly MODULE_DESIGN_3D=(blender freecad)
readonly MODULE_GAMING_NATIVE=(steam heroic-games-launcher retroarch protonup-qt vulkan-tools libvulkan1 mesa-vulkan-drivers libgl1-mesa-dri gamemode libgamemode0 mangohud glxinfo mesa-utils preload)
readonly MODULE_WINDOWS_COMPAT=(wine wine64 wine32 winetricks cabextract p7zip-full libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 libgl1-mesa-dri libgl1-mesa-dri:i386)
readonly MODULE_COMMUNICATION=(telegram-desktop signal-desktop)
readonly MODULE_VIRTUALIZATION=(qemu-system libvirt-daemon-system virt-manager virtinst virtualbox)
readonly MODULE_HARDWARE_DRIVERS=(inxi lshw hwinfo pciutils usbutils dmidecode fwupd nvidia-detect firmware-linux-nonfree firmware-misc-nonfree)
readonly MODULE_VPN_FREE=(openvpn wireguard-tools network-manager-openvpn network-manager-openvpn-gnome)
readonly MODULE_CYBERSEC=(nmap wireshark tcpdump netcat-openbsd socat lynis nikto hashcat john gpg)
readonly MODULE_REMOTE=(openssh-server openssh-client sshuttle mosh vsftpd lftp tigervnc-standalone-server rsync rclone syncthing)
readonly MODULE_MONITORING=(netdata iotop iftop nethogs psensor smartmontools)
readonly MODULE_BACKUP=(timeshift borgbackup restic)
readonly MODULE_SECURITY=(auditd apparmor-utils chkrootkit rkhunter)

# Apps Flatpak organizadas por módulo
readonly -A FLATPAK_APPS=(
    ["multimedia"]="com.spotify.Client"
    ["communication"]="com.discordapp.Discord md.obsidian.Obsidian io.github.mimbrero.WhatsAppDesktop"
    ["gaming"]="com.heroicgameslauncher.hgl net.davidotek.pupgui2"
    ["windows_compat"]="com.usebottles.bottles"
)

# =============================================================================
# LÓGICA DE INSTALACIÓN CON HOOKS Y FIXES
# =============================================================================

install_universal_base() {
    if $DRY_RUN; then 
        log_msg "[DRY-RUN] Base universal: simulación"
        return 0
    fi
    
    backup_critical_configs
    pre_install_hooks
    
    section_header "[BASE] Instalando componentes universales"
    
    # Configurar repositorios Debian con non-free-firmware
    if ! grep -q "non-free-firmware" /etc/apt/sources.list 2>/dev/null; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
        cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
EOF
        apt update &>/dev/null
        log_status "ok" "Repositorios Debian configurados con non-free-firmware"
    fi
    
    # Instalar paquetes base
    for pkg in "${UNIVERSAL_BASE[@]}"; do
        install_with_progress "$pkg" "Base: $pkg"
    done
    
    # Configurar UFW básico
    if is_apt_installed "ufw"; then
        ufw --force enable &>/dev/null
        ufw allow OpenSSH &>/dev/null
        log_status "ok" "UFW activado con regla SSH"
    fi
    
    # Configurar entorno de usuario
    configure_user_environment
    
    post_install_hooks
    mark_module_installed "universal_base"
    echo -e "${GREEN}✓ Base universal completada${NC}\n"
}

install_module() {
    local module_name="$1"; shift
    local apt_packages=("$@")
    
    if $DRY_RUN; then 
        log_msg "[DRY-RUN] Módulo $module_name: simulación"
        return 0
    fi
    
    pre_install_hooks
    
    # Caso especial: optimización
    if [[ "$module_name" == "optimization" ]]; then
        apply_system_optimizations
        post_install_hooks
        return
    fi
    
    section_header "[MÓDULO] Instalando: $module_name"
    
    # Instalar paquetes APT del módulo
    for pkg in "${apt_packages[@]}"; do
        install_with_progress "$pkg" "$module_name: $pkg"
    done
    
    # Instalar Flatpaks asociados al módulo
    if cmd_exists "flatpak"; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>/dev/null
        for category in "${!FLATPAK_APPS[@]}"; do
            if [[ "$category" == "$module_name" || "$module_name" == "communication" && "$category" == "communication" ]]; then
                for app_id in ${FLATPAK_APPS[$category]}; do
                    install_flatpak_with_progress "$app_id"
                done
            fi
        done
    fi
    
    # Hooks post-instalación específicos del módulo
    configure_module_post_install "$module_name"
    
    post_install_hooks
    mark_module_installed "$module_name"
    echo -e "${GREEN}✓ Módulo $module_name completado${NC}\n"
}

configure_module_post_install() {
    local module="$1"
    
    case "$module" in
        "dev_web")
            # Docker: añadir usuario al grupo
            if cmd_exists "docker"; then
                usermod -aG docker "$SUDO_USER" &>/dev/null
                systemctl enable --now docker &>/dev/null
                log_status "ok" "Usuario $SUDO_USER añadido al grupo docker"
            fi
            # mkcert: instalar CA local
            if cmd_exists "mkcert"; then
                sudo -u "$SUDO_USER" mkcert -install &>/dev/null && \
                log_status "ok" "mkcert CA local instalada"
            fi
            # Node.js + pnpm vía FNM
            install_fnm
            # FIX VS Code: aplicar después de instalar
            if is_apt_installed "code"; then
                setup_vscode_network_fix
            fi
            ;;
        "gaming")
            # GameMode daemon
            if is_apt_installed "gamemoded"; then
                systemctl enable --now gamemoded &>/dev/null
                log_status "ok" "GameMode habilitado"
            fi
            # Heroic Games Launcher en español
            if cmd_exists "flatpak" && is_flatpak_installed "com.heroicgameslauncher.hgl"; then
                sudo -u "$SUDO_USER" flatpak override --user --env=LANG=es_ES.UTF-8 com.heroicgameslauncher.hgl &>/dev/null
                log_status "ok" "Heroic configurado en español"
            fi
            # Optimizaciones específicas de gaming
            apply_gaming_optimizations
            ;;
        "multimedia")
            # Fix para apps Electron (Discord/Spotify)
            setup_electron_apps_fix
            ;;
        "windows_compat")
            setup_windows_compatibility
            ;;
        "hardware_drivers")
            setup_hardware_diagnostics
            ;;
        "vpn_free")
            setup_vpn_free_profiles
            ;;
        "remote")
            # SSH Server hardening básico
            if is_apt_installed "openssh-server"; then
                systemctl enable --now ssh &>/dev/null
                # Deshabilitar login root por SSH
                if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
                    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null
                    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null
                    systemctl reload ssh &>/dev/null
                fi
                log_status "ok" "SSH configurado (root login deshabilitado)"
            fi
            ;;
    esac
}

setup_hardware_diagnostics() {
    log_msg "Configurando utilidades de hardware y drivers no nativos..."

    local report_file="$USER_HOME/.hardware-driver-report.txt"
    {
        echo "=== Hardware/Drivers Report ==="
        echo "Fecha: $(date)"
        echo "Arquitectura: $(dpkg --print-architecture 2>/dev/null)"
        echo ""
        echo "-- CPU --"
        lscpu 2>/dev/null | grep -E 'Model name|CPU\(s\)|Vendor ID' || true
        echo ""
        echo "-- GPU --"
        lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true
        echo ""
        echo "-- USB --"
        lsusb 2>/dev/null || true
        echo ""
        echo "-- Firmware packages --"
        dpkg -l 2>/dev/null | grep -E 'firmware-linux|firmware-misc-nonfree|nvidia-detect|fwupd' || true
    } > "$report_file"

    chown "$SUDO_USER:$SUDO_USER" "$report_file"
    log_status "ok" "Reporte de hardware generado: $report_file"
}

setup_vpn_free_profiles() {
    log_msg "Configurando base VPN gratuita (OpenVPN/WireGuard)..."

    local vpn_notes="$USER_HOME/.vpn-free-notes.txt"
    cat <<'EOF' > "$vpn_notes"
VPN libre configurada (cliente):

Incluye:
- OpenVPN
- WireGuard
- Plugins NetworkManager para OpenVPN

Proveedores con plan gratuito compatibles mediante config OpenVPN/WireGuard:
- ProtonVPN Free (archivos de configuración)
- Windscribe Free (según disponibilidad regional)

Recomendación:
1) Importar archivo .ovpn o perfil WireGuard en NetworkManager.
2) Probar conectividad con: curl ifconfig.me
EOF
    chown "$SUDO_USER:$SUDO_USER" "$vpn_notes"
    log_status "ok" "Guía VPN gratuita creada: $vpn_notes"
}

setup_windows_compatibility() {
    log_msg "Aplicando configuración de compatibilidad Windows (Bottles/Wine)..."

    # Garantizar arquitectura i386 para librerías Win32
    if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
        dpkg --add-architecture i386 &>/dev/null && apt update &>/dev/null
    fi

    # Instalar Bottles si no está presente
    if cmd_exists "flatpak"; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>/dev/null
        install_flatpak_with_progress "com.usebottles.bottles" "Bottles (compatibilidad Windows)"

        # Permisos recomendados para mayor compatibilidad de apps Windows
        sudo -u "$SUDO_USER" flatpak override --user --filesystem=home --share=network --socket=x11 --socket=wayland com.usebottles.bottles &>/dev/null
        log_status "ok" "Bottles configurado con permisos base recomendados"
    else
        log_status "fail" "Flatpak no disponible para instalar Bottles"
    fi

    # Nota rápida para el usuario
    cat <<'EOF' > "$USER_HOME/.bottles-compat-notes.txt"
Bottles/Wine habilitado para compatibilidad Windows.

Recomendación:
1) Usar perfil 'Application' para apps de productividad.
2) Instalar dependencias runtime desde la misma botella (DXVK, VC++ runtimes, .NET) según app.
3) Para juegos, priorizar Steam/Proton, Heroic o Lutris antes de Bottles.
EOF
    chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.bottles-compat-notes.txt"

    log_status "ok" "Compatibilidad Windows configurada (Wine + Bottles + ajustes base)"
}

# Instalación de FNM + Node.js LTS + pnpm
install_fnm() {
    local fnm_dir="$USER_HOME/.local/share/fnm"
    
    if [[ -d "$fnm_dir" ]]; then
        log_status "skip" "FNM ya instalado"
        return 0
    fi
    
    log_msg "Instalando FNM + Node.js LTS + pnpm..."
    
    # Descargar e instalar FNM con verificación
    if ! sudo -u "$SUDO_USER" bash -c 'curl -fsSL https://fnm.vercel.app/install | bash' &>/dev/null; then
        log_status "fail" "No se pudo instalar FNM"
        return 1
    fi
    
    # Configurar variables de entorno en .bashrc
    if ! grep -q "fnm" "$USER_HOME/.bashrc" 2>/dev/null; then
        cat <<EOF >> "$USER_HOME/.bashrc"

# OMNI-OPTIMIZER: FNM (Fast Node Manager)
export FNM_DIR="\$HOME/.local/share/fnm"
[ -s "\$FNM_DIR/fnm.sh" ] && source "\$FNM_DIR/fnm.sh"
# Auto-instalar LTS al iniciar
if command -v fnm &>/dev/null; then
    LTS_VERSION=\$(fnm list-remote --lts 2>/dev/null | tail -1 | grep -oP 'v\K[0-9]+' || echo "20")
    fnm install \$LTS_VERSION &>/dev/null && fnm use \$LTS_VERSION &>/dev/null || true
fi
EOF
    fi
    
    # Instalar Node.js LTS y pnpm
    local lts_version
    lts_version=$(get_latest_lts_version)
    
    if sudo -u "$SUDO_USER" bash -c "source $USER_HOME/.bashrc && fnm install $lts_version && npm install -g pnpm" &>/dev/null; then
        log_status "ok" "Node.js LTS v${lts_version} + pnpm instalados"
    else
        log_status "fail" "Error instalando Node.js/pnpm"
    fi
}

# Optimizaciones específicas para gaming
apply_gaming_optimizations() {
    # Network tweaks para baja latencia
    if ! grep -q "net.core.default_qdisc=fq_codel" /etc/sysctl.conf 2>/dev/null; then
        echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p &>/dev/null
        log_status "ok" "Red optimizada para gaming (fq_codel + BBR)"
    fi
    
    # MangoHud configuration
    if is_apt_installed "mangohud" && [[ ! -f "$USER_HOME/.config/MangoHud/MangoHud.conf" ]]; then
        mkdir -p "$USER_HOME/.config/MangoHud"
        cat <<EOF > "$USER_HOME/.config/MangoHud/MangoHud.conf"
# OMNI-OPTIMIZER: Configuración MangoHud
fps
gpu_stats
cpu_stats
ram
vram
frame_timing
EOF
        chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config/MangoHud"
        log_status "ok" "MangoHud configurado"
    fi
    
    # Gamemode auto-start para juegos
    if is_apt_installed "gamemode"; then
        log_msg "Tip: Usa 'gamemoderun %command%' en opciones de lanzamiento de Steam"
    fi
}

# Optimizaciones para sistemas con poca RAM
apply_minimal_optimizations() {
    section_header "[MINIMAL] Optimizaciones para ${TOTAL_RAM_GB}GB RAM"
    
    # Swappiness agresivo
    if ! grep -q "vm.swappiness=1" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.swappiness=1" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure=200" >> /etc/sysctl.conf
        sysctl -p &>/dev/null
        log_status "ok" "Swappiness=1 (agresivo para baja RAM)"
    fi
    
    # ZRAM aumentado
    if is_apt_installed "zram-tools" && [[ -f /etc/default/zramswap ]]; then
        echo -e "ZRAM_FRACTION=0.75\nZRAM_COMPRESSOR=lz4" > /etc/default/zramswap
        ensure_zram_active
        log_status "ok" "ZRAM al 75% de RAM disponible"
    fi
    
    # Desactivar servicios innecesarios
    for service in bluetooth cups ModemManager; do
        if systemctl list-unit-files "$service.service" 2>/dev/null | grep -q enabled; then
            systemctl disable --now "$service" &>/dev/null && \
            log_status "ok" "Servicio '$service' desactivado"
        fi
    done
    
    log_status "ok" "Optimizaciones minimalistas aplicadas"
}

# =============================================================================
# CONFIGURACIÓN DE ENTORNO DE USUARIO (UX del SO)
# =============================================================================

configure_user_environment() {
    section_header "[ENTORNO] Configurando experiencia de usuario"
    log_msg "Preparando entorno para $SUDO_USER..."
    
    # Crear estructura de directorios estándar
    mkdir -p "$USER_HOME"/{projects/{web,apps,experiments},dev/{sandbox,tools},docs/{personal,work},downloads/{temp,archive},Screenshots}
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME"
    log_status "ok" "Directorios estándar creados"
    
    # Git config plantilla (solo si no existe)
    if ! sudo -u "$SUDO_USER" git config --global user.name &>/dev/null; then
        cat <<EOF > "$USER_HOME/.gitconfig"
[user]
    name = Tu Nombre
    email = tu@email.com
[core]
    editor = neovim
    autocrlf = input
[init]
    defaultBranch = main
[pull]
    rebase = true
[push]
    default = simple
[alias]
    co = checkout
    br = branch
    ci = commit
    st = status
    unstage = reset HEAD --
    last = log -1 HEAD
EOF
        chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.gitconfig"
        log_status "ok" "Git config creado con aliases útiles"
    else
        log_status "skip" "Git config ya existe"
    fi
    
    # SSH keys reminder
    if [[ ! -f "$USER_HOME/.ssh/id_ed25519" && ! -f "$USER_HOME/.ssh/id_rsa" ]]; then
        log_msg "SSH: generar claves con: ssh-keygen -t ed25519 -C \"tu@email.com\""
        log_status "skip" "SSH keys pendientes de generar"
    else
        log_status "ok" "SSH keys detectadas"
    fi
    
    # Apps por defecto (si xdg-utils está disponible)
    if cmd_exists "xdg-settings"; then
        xdg-settings set default-web-browser firefox-esr.desktop 2>/dev/null
        xdg-settings set default-url-scheme-handler firefox-esr.desktop 2>/dev/null
        cmd_exists "code" && xdg-mime default code.desktop text/plain 2>/dev/null
        log_status "ok" "Apps por defecto configuradas"
    fi
    
    # Docker sin sudo (ya manejado en configure_module_post_install, pero verificar)
    if cmd_exists "docker" && ! groups "$SUDO_USER" 2>/dev/null | grep -q docker; then
        usermod -aG docker "$SUDO_USER" &>/dev/null
        log_status "ok" "Usuario en grupo docker (re-login o 'newgrp docker' para aplicar)"
    fi
    
    # Aliases útiles en .bashrc
    if ! grep -q "# OMNI-OPTIMIZER aliases" "$USER_HOME/.bashrc" 2>/dev/null; then
        cat <<'ALIASES_EOF' >> "$USER_HOME/.bashrc"

# === OMNI-OPTIMIZER: Aliases útiles ===
alias ll='ls -lah --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias update='sudo apt update && sudo apt upgrade -y'
alias purge='sudo apt autoremove -y && sudo apt clean'
alias docker-clean='docker system prune -af --volumes'
alias git-undo='git reset --soft HEAD~1'
alias mkcd='mkdir -p "$1" && cd "$1" # Usage: mkcd dirname'
alias sysinfo='echo "=== CPU ===" && lscpu | grep "Model name" && echo -e "\n=== RAM ===" && free -h && echo -e "\n=== DISK ===" && df -h /'
ALIASES_EOF
        chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.bashrc"
        log_status "ok" "Aliases útiles añadidos a .bashrc"
    fi
    
    # Script de bienvenida
    local welcome_script="$USER_HOME/.omni-welcome.sh"
    cat <<WELCOME_EOF > "$welcome_script"
#!/bin/bash
echo "╔════════════════════════════════╗"
echo "║  Entorno listo para trabajar  ║"
echo "╚════════════════════════════════╝"
echo "Atajos: Super+T (Terminal) | Super+E (Archivos) | Alt+Shift (Idioma)"
echo "Comandos: update (actualizar) | purge (limpiar) | docker-clean"
echo "Próximos: 1) nano ~/.gitconfig  2) ssh-keygen  3) cd ~/projects"
echo ""
echo "Fix VS Code aplicado: Si Marketplace falla, ejecuta ~/.vscode-network-diagnostic.sh"
WELCOME_EOF
    chmod +x "$welcome_script"
    chown "$SUDO_USER:$SUDO_USER" "$welcome_script"
    
    # Auto-ejecutar bienvenida en bashrc
    grep -q ".omni-welcome.sh" "$USER_HOME/.bashrc" 2>/dev/null || \
        echo '[[ -f ~/.omni-welcome.sh ]] && source ~/.omni-welcome.sh' >> "$USER_HOME/.bashrc"
    
    log_status "ok" "Entorno de usuario configurado"
    echo -e "${GREEN}✓ Entorno listo para $SUDO_USER${NC}\n"
}

# =============================================================================
# CONFIGURACIÓN UX/UI: Fake10 Theme + Shortcuts
# =============================================================================

configure_visual_theme() {
    section_header "[TEMA] Desplegando Interfaz Visual Fake10"
    local theme_file="Fake10-v5.tar.gz"
    
    if [[ -f "$theme_file" ]]; then
        mkdir -p "$USER_HOME/.themes" "$USER_HOME/.icons"
        if tar -xzf "$theme_file" -C "$USER_HOME/.themes/" --strip-components=1 2>/dev/null || \
           tar -xzf "$theme_file" -C "$USER_HOME/.themes/" 2>/dev/null; then
            chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.themes" "$USER_HOME/.icons"
            log_status "ok" "Tema Fake10 desplegado"
        else
            log_status "fail" "Error extrayendo archivo de tema"
        fi
    else
        log_status "fail" "Archivo $theme_file no encontrado (opcional)"
        log_msg "Tip: Descarga Fake10 y colócalo en el directorio del script"
    fi
    
    # Configurar GTK 3.0
    mkdir -p "$USER_HOME/.config/gtk-3.0"
    cat <<EOF > "$USER_HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Fake10
gtk-icon-theme-name=Papirus
gtk-font-name=Fira Code 10
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
gtk-application-prefer-dark-theme=0
EOF
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config/gtk-3.0" 2>/dev/null
    log_status "ok" "GTK 3.0 configurado"
    
    # Aplicar en XFCE si está disponible
    if [[ "$DESKTOP_ENV" =~ [Xx][Ff][Cc][Ee] ]]; then
        if cmd_exists "xfconf-query"; then
            sudo -u "$SUDO_USER" xfconf-query -c xsettings -p /Net/ThemeName -s "Fake10" 2>/dev/null
            sudo -u "$SUDO_USER" xfconf-query -c xsettings -p /Net/IconThemeName -s "Papirus" 2>/dev/null
            sudo -u "$SUDO_USER" xfconf-query -c xsettings -p /Gtk/FontName -s "Fira Code 10" 2>/dev/null
            log_status "ok" "Tema aplicado en XFCE"
        fi
    fi
}

configure_universal_shortcuts() {
    log_msg "Configurando atajos universales + cambio de idioma"
    
    mkdir -p "$USER_HOME/.local/bin"
    
    # Script centralizado de atajos
    local shortcuts_script="$USER_HOME/.local/bin/omni-shortcuts"
    cat <<'SHORTCUTS_EOF' > "$shortcuts_script"
#!/bin/bash
# OMNI-OPTIMIZER: Centralizador de atajos de teclado
case "$1" in
    "terminal")
        command -v terminator &>/dev/null && terminator & || \
        command -v xfce4-terminal &>/dev/null && xfce4-terminal & || \
        gnome-terminal &>/dev/null && gnome-terminal & || \
        xterm &
        ;;
    "filemanager")
        command -v thunar &>/dev/null && thunar & || \
        command -v nautilus &>/dev/null && nautilus & || \
        xdg-open ~ &
        ;;
    "lock")
        command -v xflock4 &>/dev/null && xflock4 || \
        loginctl lock-session 2>/dev/null || \
        dm-tool lock 2>/dev/null
        ;;
    "screenshot")
        command -v flameshot &>/dev/null && flameshot gui || \
        command -v scrot &>/dev/null && scrot -s ~/Screenshots/%Y-%m-%d_%H%M%S.png || \
        import -window root ~/Screenshots/$(date +%F_%T).png
        ;;
    "app-launcher")
        command -v rofi &>/dev/null && rofi -show drun || \
        command -v dmenu &>/dev/null && dmenu_run || \
        echo "App launcher no disponible"
        ;;
    *)
        echo "Uso: $0 {terminal|filemanager|lock|screenshot|app-launcher}"
        exit 1
        ;;
esac
SHORTCUTS_EOF
    chmod +x "$shortcuts_script"
    chown "$SUDO_USER:$SUDO_USER" "$shortcuts_script"
    
    # Configurar cambio de idioma: Alt+Shift
    if [[ "$DESKTOP_ENV" =~ [Xx][Ff][Cc][Ee] ]] && cmd_exists "xfconf-query"; then
        sudo -u "$SUDO_USER" xfconf-query -c xfce4-keyboard-layout -p /Default/XkbDisable -n -t bool -s false 2>/dev/null
        sudo -u "$SUDO_USER" xfconf-query -c xfce4-keyboard-layout -p /Default/XkbOptions/Group -n -t string -s "grp:alt_shift_toggle" 2>/dev/null
    fi
    
    # Persistir configuración de teclado en sesión
    if ! grep -q "setxkbmap.*alt_shift_toggle" "$USER_HOME/.bashrc" 2>/dev/null; then
        echo '[[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]] && setxkbmap -option grp:alt_shift_toggle 2>/dev/null' >> "$USER_HOME/.bashrc"
    fi
    log_status "ok" "Cambio de idioma: Alt+Shift configurado"
    
    # Atajos específicos para XFCE
    if [[ "$DESKTOP_ENV" =~ [Xx][Ff][Cc][Ee] ]] && cmd_exists "xfconf-query"; then
        local -A xfce_shortcuts=(
            ["<Primary><Alt>t"]="terminal"
            ["<Super>e"]="filemanager" 
            ["<Super>l"]="lock"
            ["<Super>d"]="app-launcher"
            ["<Super>Print"]="screenshot"
        )
        
        for keybinding in "${!xfce_shortcuts[@]}"; do
            local action="${xfce_shortcuts[$keybinding]}"
            sudo -u "$SUDO_USER" xfconf-query -c xfce4-keyboard-shortcuts \
                -p "/commands/custom/$keybinding" -n -t string \
                -s "$shortcuts_script $action" 2>/dev/null
        done
        
        # Atajos de ventana tipo Windows
        sudo -u "$SUDO_USER" xfconf-query -c xfwm4 -p /general/tile_left_key -n -t string -s "<Super>Left" 2>/dev/null
        sudo -u "$SUDO_USER" xfconf-query -c xfwm4 -p /general/tile_right_key -n -t string -s "<Super>Right" 2>/dev/null
        sudo -u "$SUDO_USER" xfconf-query -c xfwm4 -p /general/maximize_window_key -n -t string -s "<Super>Up" 2>/dev/null
        
        log_status "ok" "Atajos XFCE vinculados a omni-shortcuts"
    fi
}

configure_shell() {
    # Mejoras de bashrc si no existen
    if ! grep -q "OMNI-OPTIMIZER v8.2" "$USER_HOME/.bashrc" 2>/dev/null; then
        cat <<EOF >> "$USER_HOME/.bashrc"

# === OMNI-OPTIMIZER v8.2: Configuración de shell ===
export EDITOR="neovim"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --color=16'
export RIPGREP_CONFIG_PATH="\$HOME/.ripgreprc"

# Colores para ls
export LS_COLORS='rs=0:di=01;34:ln=01;36:*.tar=01;31:*.zip=01;31'

# Prompt mejorado (si es interactivo)
if [[ \$- == *i* ]]; then
    PS1='\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '
fi

# Funciones útiles
cacheclean() { sudo sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null; echo "✓ Cache limpiada"; }
sysmon() { echo "=== CPU ===" && top -bn1 | head -5 && echo -e "\n=== MEM ===" && free -h && echo -e "\n=== DISK ===" && df -h /; }
EOF
        chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.bashrc"
        log_status "ok" "Shell configurado con mejoras"
    fi
    
    # Configurar ripgrep
    if [[ ! -f "$USER_HOME/.ripgreprc" ]]; then
        cat <<EOF > "$USER_HOME/.ripgreprc"
--smart-case
--glob=!*.git/*
--glob=!node_modules/*
--glob=!.venv/*
--glob=!__pycache__/*
EOF
        log_status "ok" "ripgrep configurado"
    fi
}

# =============================================================================
# MENÚS INTERACTIVOS
# =============================================================================

show_main_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${WHITE}  DEBIAN 13 OMNI-OPTIMIZER v8.2 - MENU PRINCIPAL  ${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Recursos:${NC} ${TOTAL_RAM_GB}GB RAM | ${CPU_CORES} cores | GPU: ${GPU_VENDOR:-no detectada}"
    echo -e "${CYAN}Usuario:${NC} $SUDO_USER | ${CYAN}Entorno:${NC} ${DESKTOP_ENV^^}"
    $IS_LOW_RAM && echo -e "${YELLOW}⚠ AVISO: Modo minimalista recomendado (<4GB RAM)${NC}"
    $DRY_RUN && echo -e "${YELLOW}⚠ MODO DRY-RUN: Solo simulación${NC}"
    echo ""
    echo -e "${BOLD}Seleccione una opción:${NC}"
    echo -e "  ${GREEN}[1]${NC} Instalar por CATEGORÍAS"
    echo -e "  ${GREEN}[2]${NC} Check and Fix por categoría"
    echo -e "  ${GREEN}[3]${NC} Reconfigurar categoría"
    echo -e "  ${GREEN}[4]${NC} Limpieza general"
    echo -e "  ${GREEN}[5]${NC} Limpiar innecesarios (reemplazados)"
    echo -e "  ${GREEN}[6]${NC} Panel de salud"
    echo -e "  ${GREEN}[7]${NC} Aplicar UX/UI (Fake10 + Shortcuts)"
    echo -e "  ${GREEN}[8]${NC} Eliminar por categoría (purga segura)"
    echo -e "  ${GREEN}[9]${NC} Comprobar actualizaciones + configurar cron"
    echo -e "  ${GREEN}[10]${NC} Referencias oficiales"
    echo -e "  ${GRAY}[c]${NC} Cancelar operación actual"
    echo -e "  ${RED}[q]${NC} Salir inmediato"
    echo -e "  ${RED}[0]${NC} Salir y finalizar"
    echo -n -e "\n${CYAN}Opción [0-10,c,q]: ${NC}"
}

show_module_menu() {
    clear
    section_header "INSTALACIÓN POR MÓDULOS"
    echo -e "${CYAN}Seleccione módulos (múltiples: 1,3,5):${NC}"
    echo -e "${GRAY}Estado: (instalado) / (disponible)${NC}\n"
    
    local -a modules=(
        "Optimización del Sistema" "Navegadores" "Ofimática" "Multimedia" 
        "Dev Core" "Dev CLI" "Dev Web (VS Code)" "Dev Contenedores" 
        "Dev Mobile" "Comunicación" "Virtualización" "Hardware/Drivers" "VPN Libre" "Diseño Gráfico" "Diseño Video" "Diseño 3D" "Gaming Nativo"
        "Compatibilidad Windows (Bottles/Wine)" "Ciberseguridad" "Acceso Remoto" "Monitoreo" "Backup" "Seguridad"
    )
    local -a ids=(
        optimization browsers office multimedia dev_core dev_cli 
        dev_web dev_containers dev_mobile communication virtualization hardware_drivers vpn_free design_graphic design_video design_3d 
        gaming windows_compat cybersec remote monitoring backup security
    )
    
    for i in "${!modules[@]}"; do
        local status="(disponible)"
        is_module_installed "${ids[$i]}" && status="${GREEN}(instalado)${NC}"
        printf "  ${GREEN}[%2d]${NC} %s %s\n" $((i+1)) "$status" "${modules[$i]}"
    done
    echo -e "\n  ${GRAY}[00] Volver / Regresar${NC}"
    echo -e "  ${GRAY}[c] Cancelar${NC}"
    echo -e "  ${RED}[q] Salir${NC}"
    echo -n -e "\n${CYAN}Categorías [00-23,c,q]: ${NC}"
}

show_verification() {
    clear
    section_header "VERIFICACIÓN DE ESTADO"
    
    echo -e "${BOLD}Módulos instalados:${NC}"
    if [[ -f "$STATUSFILE" && -s "$STATUSFILE" ]]; then
        grep "INSTALLED:" "$STATUSFILE" | tail -15 | while read -r line; do 
            echo -e "  ${GREEN}+${NC} ${line#*INSTALLED: }"
        done
    else
        echo -e "  ${GRAY}(Sin instalaciones registradas)${NC}"
    fi
    
    echo -e "\n${BOLD}Paquetes críticos:${NC}"
    local critical_pkgs=(code docker firefox-esr steam flatpak)
    for pkg in "${critical_pkgs[@]}"; do
        if is_apt_installed "$pkg" || is_flatpak_installed "$pkg" 2>/dev/null; then
            echo -e "  ${GREEN}+${NC} $pkg"
        else
            echo -e "  ${RED}!${NC} $pkg"
        fi
    done
    
    echo -e "\n${BOLD}Optimizaciones:${NC}"
    grep -q "vm.swappiness" /etc/sysctl.conf 2>/dev/null && \
        echo -e "  ${GREEN}+${NC} Sysctl" || echo -e "  ${RED}!${NC} Sysctl"
    systemctl is-active --quiet zramswap 2>/dev/null && \
        echo -e "  ${GREEN}+${NC} ZRAM" || echo -e "  ${RED}!${NC} ZRAM"

    verify_functionality
    
    echo -e "\n${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

# =============================================================================
# VERIFICACIÓN DE FUNCIONALIDAD (no solo "instalado", sino "funciona")
# =============================================================================

verify_functionality() {
    section_header "[VERIFICACIÓN] Comprobando funcionalidad"
    local passed=0 total=0
    
    # Docker
    ((total++))
    if cmd_exists "docker" && docker info &>/dev/null 2>&1; then 
        echo -e "  ${GREEN}✓${NC} Docker: funcional"
        ((passed++))
    else 
        echo -e "  ${RED}✗${NC} Docker: no funcional"
    fi
    
    # VS Code
    ((total++))
    if cmd_exists "code"; then 
        echo -e "  ${GREEN}✓${NC} VS Code: disponible"
        ((passed++))
    else 
        echo -e "  ${RED}✗${NC} VS Code: no disponible"
    fi
    
    # Steam + Proton
    ((total++))
    if cmd_exists "steam"; then
        echo -e "  ${GREEN}✓${NC} Steam: instalado"
        ((passed++))
        ((total++))
        if ls "$USER_HOME/.steam/steam/steamapps/common/Proton"* &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Proton: disponible"
            ((passed++))
        else
            echo -e "  ${YELLOW}~${NC} Proton: activar en Steam Settings > Compatibility"
        fi
    else
        echo -e "  ${RED}✗${NC} Steam: no instalado"
    fi
    
    # Flatpak
    ((total++))
    if cmd_exists "flatpak"; then 
        local apps_count
        apps_count=$(flatpak list --app --columns=application 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✓${NC} Flatpak: $apps_count apps instaladas"
        ((passed++))
    else 
        echo -e "  ${RED}✗${NC} Flatpak: no disponible"
    fi
    
    # ZRAM
    ((total++))
    if is_zram_active; then 
        echo -e "  ${GREEN}✓${NC} ZRAM: activo"
        ((passed++))
    else 
        echo -e "  ${RED}✗${NC} ZRAM: no activo"
    fi
    
    # Red/Internet
    ((total++))
    if curl -s --connect-timeout 5 https://deb.debian.org &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Conectividad: OK"
        ((passed++))
    else
        echo -e "  ${RED}✗${NC} Conectividad: problemas de red"
    fi

    # Espacio en disco / (umbral 85%)
    ((total++))
    local root_use
    root_use=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}' 2>/dev/null || echo 100)
    if [[ $root_use -lt 85 ]]; then
        echo -e "  ${GREEN}✓${NC} Disco raíz: ${root_use}% usado"
        ((passed++))
    else
        echo -e "  ${YELLOW}~${NC} Disco raíz: ${root_use}% usado (recomendado <85%)"
    fi

    # Servicios críticos (systemd)
    ((total++))
    local failed_units
    failed_units=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
    if [[ $failed_units -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Servicios systemd: sin fallos"
        ((passed++))
    else
        echo -e "  ${YELLOW}~${NC} Servicios systemd con fallo: ${failed_units}"
    fi
    
    echo -e "\n${BOLD}Resumen:${NC} $passed/$total verificaciones exitosas"
    if [[ $passed -eq $total ]]; then
        echo -e "${GREEN}✓ Sistema completamente funcional${NC}"
    elif [[ $passed -ge $((total / 2)) ]]; then
        echo -e "${YELLOW}~ Sistema funcional con ajustes pendientes${NC}"
    else
        echo -e "${RED}✗ Sistema requiere atención${NC}"
    fi
    echo -e "\n${BOLD}Guía rápida:${NC}"
    echo -e "  1) Limpieza: ${WHITE}sudo apt autoremove -y && sudo apt clean${NC}"
    echo -e "  2) Ver fallos de servicios: ${WHITE}systemctl --failed${NC}"
    echo -e "  3) Reaplicar optimización: ${WHITE}opción [1]/[2] del menú${NC}"
    echo ""
}

# =============================================================================
# PROCESAMIENTO DE MENÚ
# =============================================================================

process_module_install() {
    local selection="$1"
    IFS=',' read -ra SEL <<< "$selection"
    
    local -a modules=(optimization browsers office multimedia dev_core dev_cli dev_web dev_containers dev_mobile communication virtualization hardware_drivers vpn_free design_graphic design_video design_3d gaming windows_compat cybersec remote monitoring backup security)
    local -a module_packages=(
        "" "${MODULE_BROWSERS[*]}" "${MODULE_OFFICE[*]}" "${MODULE_MULTIMEDIA[*]}" 
        "${MODULE_DEV_CORE[*]}" "${MODULE_DEV_CLI[*]}" "${MODULE_DEV_WEB[*]}" 
        "${MODULE_DEV_CONTAINERS[*]}" "${MODULE_DEV_MOBILE[*]}" "${MODULE_COMMUNICATION[*]}" "${MODULE_VIRTUALIZATION[*]}" "${MODULE_HARDWARE_DRIVERS[*]}" "${MODULE_VPN_FREE[*]}" "${MODULE_DESIGN_GRAPHIC[*]}" "${MODULE_DESIGN_VIDEO[*]}" 
        "${MODULE_DESIGN_3D[*]}" "${MODULE_GAMING_NATIVE[*]}" "${MODULE_WINDOWS_COMPAT[*]}" "${MODULE_CYBERSEC[*]}"
        "${MODULE_REMOTE[*]}" "${MODULE_MONITORING[*]}" "${MODULE_BACKUP[*]}" "${MODULE_SECURITY[*]}"
    )
    
    for idx in "${SEL[@]}"; do
        idx=$((10#$idx - 1))  # Convertir a base 10 y ajustar índice
        
        # Validar índice
        if [[ $idx -lt 0 || $idx -ge ${#modules[@]} ]]; then 
            echo -e "${RED}Índice inválido: $((idx+1))${NC}"
            continue
        fi
        
        local mod="${modules[$idx]}"
        
        # Verificar si ya está instalado
        if is_module_installed "$mod"; then 
            echo -e "${YELLOW}~ '$mod' ya instalado${NC}"
            continue
        fi
        
        # Obtener paquetes del módulo
        local pkgs_str="${module_packages[$idx]}"
        local pkgs=()
        [[ -n "$pkgs_str" ]] && read -ra pkgs <<< "$pkgs_str"
        
        # Instalar módulo
        if [[ ${#pkgs[@]} -gt 0 ]]; then
            install_module "$mod" "${pkgs[@]}"
        else
            install_module "$mod"  # Caso especial: optimization
        fi
    done
    
    echo -e "${GREEN}✓ Módulos procesados${NC}"
    echo -e "${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

process_reinstall() {
    local selection="$1"
    IFS=',' read -ra SEL <<< "$selection"
    
    local -a modules=(optimization browsers office multimedia dev_core dev_cli dev_web dev_containers dev_mobile communication virtualization hardware_drivers vpn_free design_graphic design_video design_3d gaming windows_compat cybersec remote monitoring backup security)
    
    for idx in "${SEL[@]}"; do
        idx=$((10#$idx - 1))
        [[ $idx -lt 0 || $idx -ge ${#modules[@]} ]] && continue
        
        local mod="${modules[$idx]}"
        
        if ! is_module_installed "$mod"; then 
            echo -e "${YELLOW}~ '$mod' no instalado${NC}"
            continue
        fi
        
        # Re-ejecutar hooks de configuración sin reinstalar paquetes
        pre_install_hooks
        configure_module_post_install "$mod"
        post_install_hooks
        
        echo -e "${GREEN}✓ $mod reconfigurado${NC}"
    done
    
    echo -e "${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

pre_cleanup_module_defaults() {
    local module="$1"

    case "$module" in
        windows_compat)
            local bottles_dir="$USER_HOME/.var/app/com.usebottles.bottles"
            if [[ -d "$bottles_dir" ]]; then
                rm -rf "$bottles_dir" 2>/dev/null
                log_status "ok" "Preconfiguración Bottles limpiada para reinstalación correctiva"
            fi
            ;;
        optimization)
            sed -i '/# OMNI-OPTIMIZER: Optimizaciones de kernel/,+4d' /etc/sysctl.conf 2>/dev/null || true
            log_status "ok" "Preconfiguración de optimización limpiada"
            ;;
    esac
}

process_check_and_fix() {
    local selection="$1"
    IFS=',' read -ra SEL <<< "$selection"

    local -a modules=(optimization browsers office multimedia dev_core dev_cli dev_web dev_containers dev_mobile communication virtualization hardware_drivers vpn_free design_graphic design_video design_3d gaming windows_compat cybersec remote monitoring backup security)
    local -a module_packages=(
        "" "${MODULE_BROWSERS[*]}" "${MODULE_OFFICE[*]}" "${MODULE_MULTIMEDIA[*]}"
        "${MODULE_DEV_CORE[*]}" "${MODULE_DEV_CLI[*]}" "${MODULE_DEV_WEB[*]}"
        "${MODULE_DEV_CONTAINERS[*]}" "${MODULE_DEV_MOBILE[*]}" "${MODULE_COMMUNICATION[*]}" "${MODULE_VIRTUALIZATION[*]}" "${MODULE_HARDWARE_DRIVERS[*]}" "${MODULE_VPN_FREE[*]}" "${MODULE_DESIGN_GRAPHIC[*]}" "${MODULE_DESIGN_VIDEO[*]}"
        "${MODULE_DESIGN_3D[*]}" "${MODULE_GAMING_NATIVE[*]}" "${MODULE_WINDOWS_COMPAT[*]}" "${MODULE_CYBERSEC[*]}"
        "${MODULE_REMOTE[*]}" "${MODULE_MONITORING[*]}" "${MODULE_BACKUP[*]}" "${MODULE_SECURITY[*]}"
    )

    install_universal_base

    for idx in "${SEL[@]}"; do
        idx=$((10#$idx - 1))
        [[ $idx -lt 0 || $idx -ge ${#modules[@]} ]] && continue

        local mod="${modules[$idx]}"
        local pkgs_str="${module_packages[$idx]}"
        local pkgs=()
        [[ -n "$pkgs_str" ]] && read -ra pkgs <<< "$pkgs_str"

        section_header "[CHECK&FIX] $mod"
        pre_cleanup_module_defaults "$mod"

        for pkg in "${pkgs[@]}"; do
            install_with_progress "$pkg" "check: $mod:$pkg"
        done

        configure_module_post_install "$mod"
        post_install_hooks
        mark_module_installed "$mod"
        log_status "ok" "Check and Fix completado: $mod"
    done

    echo -e "${GREEN}✓ Check and Fix finalizado${NC}"
    echo -e "${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

process_purge() {
    echo -e "${YELLOW}Limpieza general...${NC}"
    
    # APT cleanup
    apt autoremove -y &>/dev/null
    apt clean &>/dev/null
    apt autoclean &>/dev/null
    
    # Flatpak cleanup
    if cmd_exists "flatpak"; then
        flatpak uninstall --unused -y &>/dev/null
    fi
    
    # Logs antiguos
    journalctl --vacuum-time=7d &>/dev/null
    
    log_status "ok" "Limpieza completada"
    echo -e "${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

process_cleanup_obsolete() {
    section_header "LIMPIEZA DE INNECESARIOS (REEMPLAZADOS)"

    # Nunca tocar kernel: solo paquetes de usuario/herramientas.
    local obsolete_pkgs=(exa mousepad)

    # Instalar reemplazo sugerido cuando aplique
    install_with_progress "eza" "Reemplazo moderno para exa"
    install_with_progress "gedit" "Reemplazo de editor de texto (mousepad -> gedit)"

    for pkg in "${obsolete_pkgs[@]}"; do
        if is_apt_installed "$pkg"; then
            apt purge -y "$pkg" &>/dev/null && \
            log_status "ok" "Paquete obsoleto eliminado: $pkg"
        else
            log_status "skip" "Paquete obsoleto no presente: $pkg"
        fi
    done

    apt autoremove -y &>/dev/null
    apt clean &>/dev/null

    log_status "ok" "Limpieza de innecesarios completada"
    echo -e "${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

pkg_needed_by_other_installed_categories() {
    local pkg="$1" current="$2"
    local -n _mods="$3"
    local -n _pkg_map="$4"

    for i in "${!_mods[@]}"; do
        local mod="${_mods[$i]}"
        [[ "$mod" == "$current" ]] && continue
        is_module_installed "$mod" || continue

        local other_pkgs=()
        [[ -n "${_pkg_map[$i]}" ]] && read -ra other_pkgs <<< "${_pkg_map[$i]}"
        for p in "${other_pkgs[@]}"; do
            if [[ "$p" == "$pkg" ]]; then
                return 0
            fi
        done
    done
    return 1
}

flatpak_needed_by_other_installed_categories() {
    local app_id="$1" current="$2"
    for category in "${!FLATPAK_APPS[@]}"; do
        [[ "$category" == "$current" ]] && continue
        is_module_installed "$category" || continue
        for app in ${FLATPAK_APPS[$category]}; do
            [[ "$app" == "$app_id" ]] && return 0
        done
    done
    return 1
}

process_remove_category() {
    local selection="$1"
    IFS=',' read -ra SEL <<< "$selection"

    local -a modules=(optimization browsers office multimedia dev_core dev_cli dev_web dev_containers dev_mobile communication virtualization hardware_drivers vpn_free design_graphic design_video design_3d gaming windows_compat cybersec remote monitoring backup security)
    local -a module_packages=(
        "" "${MODULE_BROWSERS[*]}" "${MODULE_OFFICE[*]}" "${MODULE_MULTIMEDIA[*]}"
        "${MODULE_DEV_CORE[*]}" "${MODULE_DEV_CLI[*]}" "${MODULE_DEV_WEB[*]}"
        "${MODULE_DEV_CONTAINERS[*]}" "${MODULE_DEV_MOBILE[*]}" "${MODULE_COMMUNICATION[*]}" "${MODULE_VIRTUALIZATION[*]}" "${MODULE_HARDWARE_DRIVERS[*]}" "${MODULE_VPN_FREE[*]}" "${MODULE_DESIGN_GRAPHIC[*]}" "${MODULE_DESIGN_VIDEO[*]}"
        "${MODULE_DESIGN_3D[*]}" "${MODULE_GAMING_NATIVE[*]}" "${MODULE_WINDOWS_COMPAT[*]}" "${MODULE_CYBERSEC[*]}"
        "${MODULE_REMOTE[*]}" "${MODULE_MONITORING[*]}" "${MODULE_BACKUP[*]}" "${MODULE_SECURITY[*]}"
    )

    for idx in "${SEL[@]}"; do
        idx=$((10#$idx - 1))
        [[ $idx -lt 0 || $idx -ge ${#modules[@]} ]] && continue

        local mod="${modules[$idx]}"
        local pkgs=()
        [[ -n "${module_packages[$idx]}" ]] && read -ra pkgs <<< "${module_packages[$idx]}"

        section_header "[REMOVE] Purga segura: $mod"

        for pkg in "${pkgs[@]}"; do
            pkg_needed_by_other_installed_categories "$pkg" "$mod" modules module_packages && {
                log_status "skip" "$pkg conservado (usado por otra categoría instalada)"
                continue
            }
            if is_apt_installed "$pkg"; then
                apt purge -y "$pkg" &>/dev/null && log_status "ok" "Purgado: $pkg"
            fi
        done

        if cmd_exists flatpak && [[ -n "${FLATPAK_APPS[$mod]:-}" ]]; then
            for app in ${FLATPAK_APPS[$mod]}; do
                flatpak_needed_by_other_installed_categories "$app" "$mod" && {
                    log_status "skip" "Flatpak conservado: $app (compartido)"
                    continue
                }
                flatpak uninstall -y "$app" &>/dev/null && log_status "ok" "Flatpak purgado: $app"
            done
        fi

        mark_module_removed "$mod"
    done

    apt autoremove -y &>/dev/null
    apt clean &>/dev/null

    log_status "ok" "Purga por categoría completada"
    echo -e "${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

process_updates_and_cron() {
    section_header "ACTUALIZACIONES + CRON"

    apt update &>/dev/null
    local up_count
    up_count=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
    log_status "ok" "Actualizaciones disponibles: $up_count"

    local cron_script="/usr/local/bin/debian-postinstall-maintenance.sh"
    cat <<'EOF' > "$cron_script"
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
LOGFILE="/var/log/debian-postinstall-cron.log"
{
  echo "[$(date '+%F %T')] === Maintenance check ==="
  apt update -qq || true
  updates=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
  echo "updates_available=$updates"
  failed_units=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
  echo "failed_units=$failed_units"
  if swapon --show 2>/dev/null | grep -q zram; then
    echo "zram=active"
  else
    echo "zram=inactive"
  fi
  echo "---"
} >> "$LOGFILE"
EOF
    chmod +x "$cron_script"

    cat <<'EOF' > /etc/cron.d/debian-postinstall-maintenance
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 6 * * * root /usr/local/bin/debian-postinstall-maintenance.sh
EOF
    chmod 644 /etc/cron.d/debian-postinstall-maintenance

    log_status "ok" "Cron configurado: /etc/cron.d/debian-postinstall-maintenance"
    log_status "ok" "Script cron: $cron_script"
    echo -e "${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

show_official_references() {
    clear
    section_header "REFERENCIAS OFICIALES"
    cat <<'EOF'
Debian Documentation: https://www.debian.org/doc/
Debian Packages: https://packages.debian.org/
Debian Wiki: https://wiki.debian.org/

VS Code Linux: https://code.visualstudio.com/docs/setup/linux
Docker Engine: https://docs.docker.com/engine/install/debian/
Podman Docs: https://podman.io/docs

Flatpak Docs: https://docs.flatpak.org/
Flathub: https://flathub.org/

Bottles: https://docs.usebottles.com/
WineHQ: https://wiki.winehq.org/

Steam Linux: https://help.steampowered.com/
ProtonUp-Qt: https://davidotek.github.io/protonup-qt/

VirtualBox Manual: https://www.virtualbox.org/manual/
libvirt Docs: https://libvirt.org/docs.html

OpenVPN Community Docs: https://openvpn.net/community-resources/
WireGuard Docs: https://www.wireguard.com/

fwupd: https://fwupd.org/
EOF
    echo -e "\n${CYAN}Presione ENTER para continuar...${NC}"
    read -r
}

# =============================================================================
# DASHBOARD FINAL
# =============================================================================

show_final_dashboard() {
    rotate_logs
    
    # Verificar funcionalidad si no es dry-run
    if ! $DRY_RUN; then
        verify_functionality
    fi
    
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${WHITE}  INSTALACIÓN COMPLETADA - OMNI-OPTIMIZER v8.2  ${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Log:${NC} $LOGFILE"
    echo -e "${CYAN}Estado:${NC} $STATUSFILE\n"
    
    echo -e "${BOLD}${GREEN}RESUMEN DE INSTALACIÓN:${NC}"
    echo -e "  Éxitos: ${#REPORT_SUCCESS[@]} | Omitidos: ${#REPORT_SKIPPED[@]} | Fallos: ${#REPORT_FAILED[@]}"
    
    if [[ ${#REPORT_SUCCESS[@]} -gt 0 ]]; then
        echo -e "\n${BOLD}Últimas tareas exitosas:${NC}"
        printf "  + %s\n" "${REPORT_SUCCESS[@]: -5}"
    fi
    
    if [[ ${#REPORT_FAILED[@]} -gt 0 ]]; then
        echo -e "\n${BOLD}${YELLOW}Tareas con problemas (revisar log):${NC}"
        printf "  ! %s\n" "${REPORT_FAILED[@]: -3}"
    fi
    
    echo -e "\n${BOLD}${MAGENTA}OPTIMIZACIONES ACTIVAS:${NC}"
    echo -e "  + ZRAM LZ4 + EarlyOOM (gestión de memoria)"
    echo -e "  + Swap 4GB + swappiness=${RAM_LEVEL["swappiness"]} (ajustado a RAM)"
    echo -e "  + Red BBR + fq_codel (baja latencia)"
    echo -e "  + DNS optimizado (8.8.8.8/1.1.1.1) + IPv4 priority"
    echo -e "  + VS Code fix: SSL bypass + cache purge para entornos restrictivos"
    echo -e "  + Gaming: Proton + Vulkan + gamemode (nativo)"
    echo -e "  + Fake10 theme + atajos universales"
    
    echo -e "\n${BLUE}────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}${YELLOW}PRÓXIMOS PASOS RECOMENDADOS:${NC}"
    echo -e "  1. Reiniciar: ${WHITE}sudo reboot${NC}"
    echo -e "  2. VS Code: ${WHITE}code${NC} (Marketplace fix aplicado automáticamente)"
    echo -e "  3. Node.js: ${WHITE}fnm use --lts${NC} (o reiniciar terminal)"
    echo -e "  4. Gaming: ${WHITE}steam${NC} → Settings > Compatibility > Enable Steam Play"
    echo -e "  5. Tema: Configuración > Apariencia > Seleccionar 'Fake10'"
    echo -e "  6. Git: ${WHITE}nano ~/.gitconfig${NC} → Configurar nombre/email"
    echo -e "  7. SSH: ${WHITE}ssh-keygen -t ed25519${NC} → Generar claves"
    
    echo -e "\n${CYAN}FILOSOFÍA v8.2:${NC}"
    echo -e "  ✓ Kernel Debian estable: sin modificaciones"
    echo -e "  ✓ Infraestructura crítica automática (sudoers, i386, repos, DNS)"
    echo -e "  ✓ VS Code resiliente: fix para entornos con latencia/restricciones"
    echo -e "  ✓ Electron apps: SSL bypass + cache management"
    echo -e "  ✓ Gaming nativo: Proton + Vulkan, sin capas innecesarias"
    echo -e "  ✓ Fake10 theme + atajos estilo Ubuntu/Windows"
    echo -e "  ✓ Hooks pre/post: configuraciones SIEMPRE aplicadas"
    echo -e "  ✓ Verificación post-instalación: funcionalidad real"
    echo -e "  ✓ Validación de entorno: previene errores antes de ejecutar"
    echo -e "  ✓ Backups automáticos: rollback posible en configs críticas"
    
    $DRY_RUN && echo -e "\n${YELLOW}⚠ MODO DRY-RUN: Ningún cambio fue aplicado${NC}"
    
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    log_msg "=== FINALIZADO v8.2 ==="
    log_msg "Éxitos: ${#REPORT_SUCCESS[@]} | Omitidos: ${#REPORT_SKIPPED[@]} | Fallos: ${#REPORT_FAILED[@]}"
    echo -e "${CYAN}Gracias por usar OMNI-OPTIMIZER - Autor: Karl Michael Correa Rivero${NC}"
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================

main_menu_loop() {
    while true; do
        show_main_menu
        read -r main_opt
        
        case "$main_opt" in
            1)
                local base_ready=false
                while true; do
                    show_module_menu
                    read -r mod_selection
                    case "$mod_selection" in
                        00|""|r|R|c|C) break ;;
                        q|Q)
                            post_install_hooks
                            show_final_dashboard
                            return
                            ;;
                        *)
                            if ! $base_ready; then
                                install_universal_base
                                base_ready=true
                            fi
                            process_module_install "$mod_selection"
                            ;;
                    esac
                done
                ;;
            2)
                while true; do
                    show_module_menu
                    read -r sel
                    case "$sel" in
                        00|""|r|R|c|C) break ;;
                        q|Q)
                            post_install_hooks
                            show_final_dashboard
                            return
                            ;;
                        *) process_check_and_fix "$sel" ;;
                    esac
                done
                ;;
            3)
                while true; do
                    show_module_menu
                    read -r sel
                    case "$sel" in
                        00|""|r|R|c|C) break ;;
                        q|Q)
                            post_install_hooks
                            show_final_dashboard
                            return
                            ;;
                        *) process_reinstall "$sel" ;;
                    esac
                done
                ;;
            4) process_purge ;;
            5) process_cleanup_obsolete ;;
            6) show_verification ;;
            7)
                configure_visual_theme
                configure_universal_shortcuts
                configure_shell
                echo -e "${GREEN}✓ UX/UI aplicada${NC}"
                echo -e "${CYAN}Presione ENTER para continuar...${NC}"
                read -r
                ;;
            8)
                while true; do
                    show_module_menu
                    read -r sel
                    case "$sel" in
                        00|""|r|R|c|C) break ;;
                        q|Q)
                            post_install_hooks
                            show_final_dashboard
                            return
                            ;;
                        *) process_remove_category "$sel" ;;
                    esac
                done
                ;;
            9) process_updates_and_cron ;;
            10) show_official_references ;;
            0)
                post_install_hooks
                show_final_dashboard
                break
                ;;
            c|C)
                echo -e "${YELLOW}Operación cancelada. Volviendo al menú...${NC}"
                sleep 1
                ;;
            q|Q)
                post_install_hooks
                show_final_dashboard
                break
                ;;
            *)
                echo -e "${YELLOW}Opción no reconocida${NC}"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# PUNTO DE ENTRADA PRINCIPAL
# =============================================================================

main() {
    # Parsear flags primero
    parse_flags "$@"
    
    # Rotar logs antiguos
    rotate_logs
    
    # Inicializar archivo de estado
    touch "$STATUSFILE" && chmod 644 "$STATUSFILE"
    
    # Cargar módulos ya instalados desde estado
    while IFS= read -r line; do
        if [[ $line =~ INSTALLED:\ (.+) ]]; then
            INSTALLED_MODULES["${BASH_REMATCH[1]}"]=1
        fi
    done < "$STATUSFILE" 2>/dev/null
    
    # Validar entorno antes de continuar
    if ! validate_environment; then
        echo -e "${RED}Validación fallida. Use --help para ver requisitos.${NC}"
        echo -e "${YELLOW}¿Forzar ejecución? (s/N): ${NC}"
        read -r force
        [[ "${force,,}" != "s" && "${force,,}" != "y" ]] && exit 1
    fi

    # Auditoria JSON opcional: compara estado deseado vs estado actual.
    if [[ -n "$PROFILE_JSON" ]] && declare -F json_profile_audit >/dev/null; then
        section_header "[JSON] Auditoría de personalización"
        json_profile_audit "$PROFILE_JSON" "$USER_HOME"
    fi
    
    # Banner de inicio
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${WHITE}  DEBIAN 13 OMNI-OPTIMIZER v8.2                 ${NC}"
    echo -e "${BOLD}${WHITE}  Autor: Karl Michael Correa Rivero             ${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Iniciando en 3...${NC}"; sleep 1
    echo -e "${CYAN}Iniciando en 2...${NC}"; sleep 1
    echo -e "${CYAN}Iniciando en 1...${NC}"; sleep 1
    
    # Ejecutar menú principal
    main_menu_loop
    
    exit 0
}

# Ejecutar main con todos los argumentos
main "$@"