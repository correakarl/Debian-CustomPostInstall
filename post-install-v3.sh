#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_FILE="${CATALOG_FILE:-${ROOT_DIR}/config/app-library-v2.json}"
LOG_DIR="${ROOT_DIR}/.runtime-logs"
LOG_FILE="${LOG_DIR}/debian-postinstall-v3.log"

ACTION="install"
PROFILE="general_desktop"
CATEGORY=""
DRY_RUN="false"
SUDO_CMD=""
APT_UPDATED="false"

declare -A CAPABILITIES

CHECK_PRESENT_TOTAL=0
CHECK_MISSING_TOTAL=0
INSTALL_FAILURES=0

[[ $EUID -ne 0 ]] && SUDO_CMD="sudo"

usage() {
    cat <<'EOF'
Debian Post-Install V3

Uso:
  ./post-install-v3.sh [opciones]
  ./post-install-v3.sh [perfil] [dry-run]

Opciones:
    --action <tipo>        install | check-fix | verify | verify-category
  --profile <nombre>     Perfil del catalogo v2
    --category <nombre>    Categoria para accion verify-category
  --catalog-json <ruta>  Ruta al catalogo JSON (app-library-v2.json)
  --dry-run              Simula cambios
  --list-profiles        Muestra perfiles disponibles
    --list-categories      Muestra categorias disponibles
  -h, --help             Ayuda

Compatibilidad legada:
  ./post-install-v3.sh general_desktop true
EOF
}

log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

list_profiles() {
    jq -r '.usage_profiles | keys[]' "$CATALOG_FILE" 2>/dev/null || true
}

list_categories() {
    jq -r '.categories | keys[]' "$CATALOG_FILE" 2>/dev/null || true
}

parse_args() {
    if [[ $# -ge 1 && "$1" != --* ]]; then
        PROFILE="$1"
        shift
        if [[ $# -ge 1 && ("$1" == "true" || "$1" == "false") ]]; then
            DRY_RUN="$1"
            shift
        fi
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action)
                ACTION="${2:-}"
                shift 2
                ;;
            --profile)
                PROFILE="${2:-}"
                shift 2
                ;;
            --category)
                CATEGORY="${2:-}"
                shift 2
                ;;
            --catalog-json)
                CATALOG_FILE="${2:-}"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --list-profiles)
                check_prerequisites
                list_profiles
                exit 0
                ;;
            --list-categories)
                check_prerequisites
                list_categories
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Opcion no valida: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    case "$ACTION" in
        install|check-fix|verify|verify-category) ;;
        *)
            echo "Accion no soportada: $ACTION" >&2
            usage
            exit 1
            ;;
    esac

    case "$DRY_RUN" in
        true|false) ;;
        *)
            echo "Valor invalido para DRY_RUN: $DRY_RUN (use true|false)" >&2
            exit 1
            ;;
    esac

    if [[ "$ACTION" == "verify-category" && -z "$CATEGORY" ]]; then
        echo "La accion verify-category requiere --category <nombre>" >&2
        exit 1
    fi
}

check_prerequisites() {
    mkdir -p "$LOG_DIR"

    local missing=()
    for cmd in jq curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "ERROR" "Faltan comandos esenciales: ${missing[*]}"
        exit 1
    fi

    if [[ ! -f "$CATALOG_FILE" ]]; then
        log "ERROR" "Catalogo JSON no encontrado: $CATALOG_FILE"
        exit 1
    fi

    if ! jq empty "$CATALOG_FILE" >/dev/null 2>&1; then
        log "ERROR" "Catalogo JSON invalido: $CATALOG_FILE"
        exit 1
    fi
}

is_integer() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

detect_capabilities() {
    log "INFO" "Detectando capacidades del sistema..."
    local detectors
    detectors=$(jq -r '.capability_detectors | keys[]' "$CATALOG_FILE" 2>/dev/null) || return 0

    local det
    for det in $detectors; do
        local result="false"
        local probe_cmds
        probe_cmds=$(jq -r ".capability_detectors.${det}.probe[]?" "$CATALOG_FILE" 2>/dev/null) || true
        local fallback_cmds
        fallback_cmds=$(jq -r ".capability_detectors.${det}.fallback[]?" "$CATALOG_FILE" 2>/dev/null) || true

        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            if eval "$cmd" &>/dev/null; then
                result="true"
                break
            fi
        done <<< "$probe_cmds"

        if [[ "$result" == "false" ]]; then
            while IFS= read -r cmd; do
                [[ -z "$cmd" ]] && continue
                if eval "$cmd" &>/dev/null; then
                    result="true"
                    break
                fi
            done <<< "$fallback_cmds"
        fi

        case "$det" in
            gpu_vendor)
                CAPABILITIES[$det]="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -oiE 'nvidia|amd|intel|broadcom' | head -1 || echo "unknown")"
                ;;
            ram_total_gb)
                CAPABILITIES[$det]="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024/1024)}' || echo "0")"
                ;;
            storage_free_gb)
                CAPABILITIES[$det]="$(df -BG / 2>/dev/null | awk 'NR==2 {print int($4)}' || echo "0")"
                ;;
            cpu_cores_threads)
                CAPABILITIES[$det]="$(nproc 2>/dev/null || echo "0")"
                ;;
            cpu_features)
                CAPABILITIES[$det]="$(grep -oE 'avx2|avx512|sse4_2|fma|aes|vmx|svm' /proc/cpuinfo 2>/dev/null | sort -u | tr '\n' ' ' || true)"
                ;;
            *)
                CAPABILITIES[$det]="$result"
                ;;
        esac

        log "DEBUG" "$det -> ${CAPABILITIES[$det]}"
    done
}

check_capability() {
    local condition="$1"

    if [[ "$condition" == *":"* ]]; then
        local cap="${condition%%:*}"
        local expected="${condition#*:}"
        local actual="${CAPABILITIES[$cap]:-false}"

        case "$expected" in
            ">="*)
                local rhs="${expected#>=}"
                is_integer "$actual" && is_integer "$rhs" && (( actual >= rhs )) && return 0
                ;;
            "<="*)
                local rhs="${expected#<=}"
                is_integer "$actual" && is_integer "$rhs" && (( actual <= rhs )) && return 0
                ;;
            "vmx|svm")
                [[ "$actual" == *"vmx"* || "$actual" == *"svm"* ]] && return 0
                ;;
            *)
                [[ "$actual" == "$expected" ]] && return 0
                ;;
        esac
        return 1
    fi

    local val="${CAPABILITIES[$condition]:-false}"
    [[ "$val" == "true" ]] && return 0
    [[ -n "$val" && "$val" != "false" && "$val" != "0" && "$val" != "unknown" ]] && return 0
    return 1
}

is_duplicate_blocked() {
    local pkg="$1"
    local source="$2"

    command -v flatpak &>/dev/null || return 1

    local registry_keys
    registry_keys=$(jq -r '.duplicate_registry | keys[]?' "$CATALOG_FILE" 2>/dev/null) || return 1

    local key
    for key in $registry_keys; do
        local preferred
        preferred=$(jq -r ".duplicate_registry.${key}.preferred" "$CATALOG_FILE" 2>/dev/null) || continue
        if [[ "$source" == "apt" && "$preferred" == "flatpak" ]]; then
            local flatpak_id
            flatpak_id=$(jq -r ".duplicate_registry.${key}.flatpak // empty" "$CATALOG_FILE" 2>/dev/null)
            if [[ -n "$flatpak_id" ]] && flatpak list --app --columns=application 2>/dev/null | grep -q "^${flatpak_id}$"; then
                log "INFO" "Omitiendo APT '$pkg' (equivalente Flatpak '$flatpak_id' instalado)"
                return 0
            fi
        fi
    done
    return 1
}

apt_update_once() {
    [[ "$APT_UPDATED" == "true" ]] && return 0
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN" "$SUDO_CMD apt update"
        APT_UPDATED="true"
        return 0
    fi

    log "INFO" "Actualizando indices APT..."
    if $SUDO_CMD apt update >/dev/null 2>&1; then
        APT_UPDATED="true"
    else
        log "WARN" "No se pudo actualizar indices APT; se continua con estado actual"
    fi
}

collect_profile_categories() {
    jq -r --arg p "$PROFILE" '.usage_profiles[$p].include_categories[]?' "$CATALOG_FILE" 2>/dev/null || true
}

category_exists() {
    local category="$1"
    jq -e --arg c "$category" '.categories[$c] != null' "$CATALOG_FILE" >/dev/null 2>&1
}

run_profile_pre_actions() {
    local actions
    actions=$(jq -r --arg p "$PROFILE" '.usage_profiles[$p].pre_actions_global[]?' "$CATALOG_FILE" 2>/dev/null) || return 0
    [[ -z "$actions" ]] && return 0

    local action
    for action in $actions; do
        case "$action" in
            enable_i386_architecture)
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "DRY-RUN" "$SUDO_CMD dpkg --add-architecture i386 && $SUDO_CMD apt update"
                else
                    if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
                        $SUDO_CMD dpkg --add-architecture i386
                        $SUDO_CMD apt update >/dev/null 2>&1 || true
                    fi
                fi
                ;;
            *)
                log "WARN" "Pre-accion '$action' no mapeada"
                ;;
        esac
    done
}

install_flatpak() {
    local category="$1"
    local mode="$2"

    local apps
    apps=$(jq -r --arg c "$category" '.categories[$c].packages.flatpak[]?' "$CATALOG_FILE" 2>/dev/null) || return 0
    [[ -z "$apps" ]] && return 0

    if ! command -v flatpak &>/dev/null; then
        log "WARN" "Flatpak no disponible; se omiten apps Flatpak en '$category'"
        return 0
    fi

    log "INFO" "[1/4] Flatpak para $category..."
    local app
    for app in $apps; do
        if flatpak list --app --columns=application 2>/dev/null | grep -q "^${app}$"; then
            ((CHECK_PRESENT_TOTAL++)) || true
            log "DEBUG" "Ya instalado: $app"
            continue
        fi

        ((CHECK_MISSING_TOTAL++)) || true
        if [[ "$mode" == "verify" || "$mode" == "verify-category" ]]; then
            log "WARN" "Falta Flatpak: $app"
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN" "flatpak install -y --noninteractive flathub $app"
            continue
        fi

        log "INFO" "Instalando Flatpak: $app"
        flatpak install -y --noninteractive flathub "$app" >/dev/null 2>&1 || {
            ((INSTALL_FAILURES++)) || true
            log "WARN" "Fallo instalando Flatpak: $app"
        }
    done
}

setup_managers() {
    local category="$1"
    log "INFO" "[2/4] Managers para $category..."

    local managers
    managers=$(jq -r --arg c "$category" '.categories[$c].packages.managers | keys[]?' "$CATALOG_FILE" 2>/dev/null) || return 0

    local mgr
    for mgr in $managers; do
        local enabled
        enabled=$(jq -r --arg c "$category" --arg m "$mgr" '.categories[$c].packages.managers[$m].install // false' "$CATALOG_FILE" 2>/dev/null) || continue
        [[ "$enabled" != "true" ]] && continue

        case "$mgr" in
            nvm)
                [[ -d "$HOME/.nvm" ]] && continue
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "DRY-RUN" "Instalaria NVM"
                    continue
                fi
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash >/dev/null 2>&1 || {
                    ((INSTALL_FAILURES++)) || true
                    log "WARN" "Fallo instalando nvm"
                }
                ;;
            pyenv)
                command -v pyenv &>/dev/null && continue
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "DRY-RUN" "Instalaria pyenv"
                    continue
                fi
                $SUDO_CMD apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev >/dev/null 2>&1 || true
                curl -fsSL https://pyenv.run | bash >/dev/null 2>&1 || {
                    ((INSTALL_FAILURES++)) || true
                    log "WARN" "Fallo instalando pyenv"
                }
                ;;
            *)
                log "WARN" "Manager '$mgr' no implementado en v3"
                ;;
        esac
    done
}

setup_docker() {
    local category="$1"
    local install_engine
    install_engine=$(jq -r --arg c "$category" '.categories[$c].packages.docker.install_engine // false' "$CATALOG_FILE" 2>/dev/null) || return 0
    [[ "$install_engine" != "true" ]] && return 0

    log "INFO" "[3/4] Docker para $category..."

    if [[ "$DRY_RUN" != "true" ]] && ! command -v docker &>/dev/null; then
        log "INFO" "Instalando Docker Engine..."
        $SUDO_CMD apt install -y ca-certificates curl gnupg >/dev/null 2>&1 || true
        $SUDO_CMD install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | $SUDO_CMD gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        $SUDO_CMD chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | $SUDO_CMD tee /etc/apt/sources.list.d/docker.list >/dev/null
        $SUDO_CMD apt update >/dev/null 2>&1
        $SUDO_CMD apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || {
            ((INSTALL_FAILURES++)) || true
            log "WARN" "Fallo instalando Docker Engine"
        }
        $SUDO_CMD systemctl enable --now docker >/dev/null 2>&1 || true
        $SUDO_CMD usermod -aG docker "${SUDO_USER:-$USER}" >/dev/null 2>&1 || true
    elif [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN" "Instalaria Docker Engine si no esta presente"
    fi

    local images
    images=$(jq -r --arg c "$category" '.categories[$c].packages.docker.reference_images // {} | to_entries[]? | .value' "$CATALOG_FILE" 2>/dev/null) || true
    local img
    for img in $images; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN" "docker pull $img"
            continue
        fi
        command -v docker &>/dev/null || break
        docker pull "$img" >/dev/null 2>&1 || {
            ((INSTALL_FAILURES++)) || true
            log "WARN" "Fallo pulling: $img"
        }
    done
}

collect_apt_packages() {
    local category="$1"
    jq -r --arg c "$category" '
        (.categories[$c].packages.apt // empty) as $apt |
        if ($apt | type) == "array" then
            $apt[]
        elif ($apt | type) == "object" then
            $apt | to_entries[] | .value | if type == "array" then .[] else . end
        else
            empty
        end
    ' "$CATALOG_FILE" 2>/dev/null || true
}

conditional_package_matches() {
    local category="$1"
    local pkg="$2"
    local reqs

    reqs=$(jq -r --arg c "$category" --arg p "$pkg" '.categories[$c].conditional_packages[]? | select(.source == "apt" and .package == $p) | .requires_any[]?' "$CATALOG_FILE" 2>/dev/null) || true
    [[ -z "$reqs" ]] && return 0

    local req
    for req in $reqs; do
        if check_capability "$req"; then
            return 0
        fi
    done
    return 1
}

install_apt() {
    local category="$1"
    local mode="$2"
    log "INFO" "[4/4] APT para $category..."

    local all_pkgs cond_pkgs
    all_pkgs="$(collect_apt_packages "$category")"
    cond_pkgs=$(jq -r --arg c "$category" '.categories[$c].conditional_packages[]? | select(.source == "apt") | .package' "$CATALOG_FILE" 2>/dev/null) || true

    local pkg
    for pkg in $all_pkgs $cond_pkgs; do
        [[ -z "$pkg" ]] && continue

        if [[ " $cond_pkgs " == *" $pkg "* ]] && ! conditional_package_matches "$category" "$pkg"; then
            log "DEBUG" "Omitiendo $pkg (requisitos no cumplidos)"
            continue
        fi

        is_duplicate_blocked "$pkg" "apt" && continue

        if dpkg -s "$pkg" >/dev/null 2>&1; then
            ((CHECK_PRESENT_TOTAL++)) || true
            log "DEBUG" "Ya instalado: $pkg"
            continue
        fi

        ((CHECK_MISSING_TOTAL++)) || true
        if [[ "$mode" == "verify" || "$mode" == "verify-category" ]]; then
            log "WARN" "Falta paquete APT: $pkg"
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN" "$SUDO_CMD apt install -y $pkg"
            continue
        fi

        apt_update_once
        log "INFO" "Instalando APT: $pkg"
        $SUDO_CMD apt install -y "$pkg" >/dev/null 2>&1 || {
            ((INSTALL_FAILURES++)) || true
            log "WARN" "Fallo instalando APT: $pkg"
        }
    done
}

run_post_actions() {
    local category="$1"
    local actions
    actions=$(jq -r --arg c "$category" '.categories[$c].post_actions[]?' "$CATALOG_FILE" 2>/dev/null) || return 0
    [[ -z "$actions" ]] && return 0

    log "INFO" "Post-acciones para $category..."

    local action
    for action in $actions; do
        case "$action" in
            enable_i386_architecture)
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "DRY-RUN" "$SUDO_CMD dpkg --add-architecture i386"
                else
                    if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
                        $SUDO_CMD dpkg --add-architecture i386
                    fi
                fi
                ;;
            configure_docker_user_group)
                [[ "$DRY_RUN" == "true" ]] || $SUDO_CMD usermod -aG docker "${SUDO_USER:-$USER}" >/dev/null 2>&1 || true
                ;;
            apply_sysctl_optimizations)
                if [[ "$DRY_RUN" != "true" ]]; then
                    local tweaks
                    tweaks=$(jq -r --arg c "$category" '.categories[$c].sysctl_tweaks // {} | to_entries[] | "\(.key)=\(.value)"' "$CATALOG_FILE" 2>/dev/null) || true
                    local t
                    for t in $tweaks; do
                        $SUDO_CMD sysctl -w "$t" >/dev/null 2>&1 || true
                        echo "$t" | $SUDO_CMD tee -a /etc/sysctl.d/99-postinstall.conf >/dev/null
                    done
                    $SUDO_CMD sysctl -p /etc/sysctl.d/99-postinstall.conf >/dev/null 2>&1 || true
                fi
                ;;
            enable_zram_with_adaptive_size)
                [[ "$DRY_RUN" == "true" ]] || $SUDO_CMD systemctl enable --now zram-config >/dev/null 2>&1 || true
                ;;
            configure_earlyoom_thresholds)
                [[ "$DRY_RUN" == "true" ]] || $SUDO_CMD systemctl enable --now earlyoom >/dev/null 2>&1 || true
                ;;
            setup_timeshift_auto_snapshots)
                [[ "$DRY_RUN" == "true" ]] || $SUDO_CMD systemctl enable --now timeshift.timer >/dev/null 2>&1 || true
                ;;
            configure_steam_proton_experimental)
                log "INFO" "Configurar Proton en Steam de forma manual (Settings -> Compatibility)"
                ;;
            *)
                log "WARN" "Accion '$action' no mapeada. Omitiendo."
                ;;
        esac
    done
}

run_cleanup() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    log "INFO" "Limpieza final..."
    $SUDO_CMD apt autoremove -y >/dev/null 2>&1 || true
    $SUDO_CMD apt clean >/dev/null 2>&1 || true
    command -v flatpak &>/dev/null && flatpak uninstall --unused -y >/dev/null 2>&1 || true
}

process_profile() {
    log "INFO" "Iniciando accion=$ACTION perfil=$PROFILE dry_run=$DRY_RUN"
    detect_capabilities

    local categories
    if [[ "$ACTION" == "verify-category" ]]; then
        if ! category_exists "$CATEGORY"; then
            log "ERROR" "Categoria '$CATEGORY' no existe. Disponibles: $(list_categories | tr '\n' ' ')"
            return 1
        fi
        categories="$CATEGORY"
    else
        categories="$(collect_profile_categories)"
        if [[ -z "$categories" ]]; then
            log "ERROR" "Perfil '$PROFILE' no existe. Disponibles: $(list_profiles | tr '\n' ' ')"
            return 1
        fi
    fi

    if [[ "$ACTION" != "verify" && "$ACTION" != "verify-category" ]]; then
        run_profile_pre_actions
    fi

    local cat
    for cat in $categories; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "INFO" "Categoria: $cat"

        install_flatpak "$cat" "$ACTION"

        if [[ "$ACTION" != "verify" && "$ACTION" != "verify-category" ]]; then
            setup_managers "$cat"
            setup_docker "$cat"
        fi

        install_apt "$cat" "$ACTION"

        if [[ "$ACTION" != "verify" && "$ACTION" != "verify-category" ]]; then
            run_post_actions "$cat"
        fi
    done

    if [[ "$ACTION" != "verify" && "$ACTION" != "verify-category" ]]; then
        run_cleanup
    fi

    log "INFO" "Resumen: presentes=$CHECK_PRESENT_TOTAL faltantes=$CHECK_MISSING_TOTAL fallos_instalacion=$INSTALL_FAILURES"

    if [[ ("$ACTION" == "verify" || "$ACTION" == "verify-category") && "$CHECK_MISSING_TOTAL" -gt 0 ]]; then
        log "WARN" "Verificacion incompleta: hay componentes faltantes"
        return 2
    fi

    if [[ "$ACTION" == "check-fix" && "$INSTALL_FAILURES" -gt 0 ]]; then
        log "WARN" "Check-fix finalizo con fallos de instalacion"
        return 3
    fi

    log "INFO" "Perfil '$PROFILE' finalizado. Revisa $LOG_FILE para detalles."
    return 0
}

main() {
    parse_args "$@"
    check_prerequisites

    echo "Debian 13 Trixie Post-Install v3.0"
    echo "Accion: $ACTION | Perfil: $PROFILE | Categoria: ${CATEGORY:-n/a} | Dry-Run: $DRY_RUN"
    echo "Catalogo: $CATALOG_FILE"
    echo "Log: $LOG_FILE"

    process_profile
}

main "$@"