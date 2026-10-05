#!/bin/bash

# Obtener las MAC asociadas a las IPs de la red.
#
# Uso: obtener_macs_ip_red.sh [LOCAL|NOMBRE_RED|CIDR]
#
# Sin argumentos, la red a escanear se determina en este orden:
#   1. Red "MACROLAN" de inventories/available_networks.json
#   2. Red "LAN" de ese mismo fichero (si no existe MACROLAN)
#   3. Red local autodetectada (si no existe el fichero, o no define
#      ninguna de las dos claves anteriores)
#
# Con un argumento:
#   - LOCAL         fuerza la autodetección de la red local (la red en la
#                    que está trabajando la máquina), ignorando el JSON.
#   - NOMBRE_RED     busca ese identificador en available_networks.json
#                    (p. ej. WIFI_ALU, INFOR3...).
#   - CIDR           se usa directamente como red a escanear (ej. 192.168.1.0/24).
#
# El fichero available_networks.json se busca primero en
# $ANSIBLE_CENTER_PATH/inventories/ (repo de datos privado, p. ej.
# ansible-center-boca) y después en inventories/ de este mismo repo.
# available_networks.sample.json NUNCA se usa como fuente real, es solo
# una plantilla de ejemplo.
#
# El resultado se guarda como inventories/macs_<RED>_temp.txt, donde <RED>
# es la red indicada (LOCAL, el nombre de available_networks.json usado, o
# el propio CIDR si se pasó directamente) o la que se haya resuelto
# automáticamente (MACROLAN, LAN o LOCAL si fue autodetectada). El
# directorio inventories/ se busca/crea en:
#   - $ANSIBLE_CENTER_PATH/inventories/, si la variable está definida.
#   - ./inventories/ (del directorio actual) en caso contrario.

rutas_candidatas_inventories() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ -n "${ANSIBLE_CENTER_PATH:-}" ]; then
        printf '%s\n' "${ANSIBLE_CENTER_PATH%/}/inventories"
    fi
    printf '%s\n' "$(cd "$script_dir/.." && pwd)/inventories"
}

localizar_json_redes() {
    local dir
    while IFS= read -r dir; do
        if [ -f "$dir/available_networks.json" ]; then
            printf '%s\n' "$dir/available_networks.json"
            return 0
        fi
    done < <(rutas_candidatas_inventories)
    return 1
}

obtener_cidr_de_json() {
    local json_path="$1" red_nombre="$2"
    [ -f "$json_path" ] || return 1
    python3 - "$json_path" "$red_nombre" <<'PYEOF'
import json, sys
ruta, nombre = sys.argv[1], sys.argv[2]
try:
    with open(ruta) as f:
        datos = json.load(f)
    for clave, info in datos.get('networks', {}).items():
        if clave.upper() == nombre.upper():
            print(info.get('cidr', ''))
            sys.exit(0)
except (json.JSONDecodeError, OSError, KeyError, AttributeError, TypeError):
    pass
print('')
PYEOF
}

autodetectar_red_local() {
    command -v ip >/dev/null 2>&1 || return 1

    local iface_principal
    iface_principal="$(ip route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"

    local linea cidr iface primera_cidr=""
    while IFS= read -r linea; do
        [ -z "$linea" ] && continue
        cidr="$(awk '{print $1}' <<< "$linea")"
        case "$cidr" in 169.254.*) continue ;; esac
        iface="$(awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}' <<< "$linea")"
        [ "$iface" = "lo" ] && continue

        if [ -n "$iface_principal" ] && [ "$iface" = "$iface_principal" ]; then
            echo "$cidr"
            return 0
        fi
        [ -z "$primera_cidr" ] && primera_cidr="$cidr"
    done < <(ip -o -4 route show scope link 2>/dev/null)

    if [ -n "$primera_cidr" ]; then
        echo "$primera_cidr"
        return 0
    fi
    return 1
}

validar_formato_cidr() {
    local red="$1" octeto
    [[ "$red" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
    for octeto in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
        [ "$octeto" -le 255 ] || return 1
    done
    [ "${BASH_REMATCH[5]}" -le 32 ] || return 1
    return 0
}

aviso_sudo_sin_preservar_entorno() {
    if [ -n "${SUDO_USER:-}" ] && [ -z "${ANSIBLE_CENTER_PATH:-}" ]; then
        printf '\n💡 Si tienes ANSIBLE_CENTER_PATH definida en tu shell, recuerda que '\''sudo'\'' no la conserva por defecto; usa '\''sudo -E'\'' para propagarla, p. ej.: sudo -E %s' "$(basename "${BASH_SOURCE[0]}")"
    fi
}

determinar_red() {
    unset RED_CIDR RED_ORIGEN RED_NOMBRE
    local json_path cidr red

    if json_path="$(localizar_json_redes)"; then
        for red in MACROLAN LAN; do
            cidr="$(obtener_cidr_de_json "$json_path" "$red")"
            if [ -n "$cidr" ]; then
                RED_CIDR="$cidr"
                RED_ORIGEN="json:${red}:${json_path}"
                RED_NOMBRE="$red"
                return 0
            fi
        done
        echo "⚠️  Se encontró $json_path pero no define ni MACROLAN ni LAN; se intentará autodetectar la red local.$(aviso_sudo_sin_preservar_entorno)" >&2
    else
        echo "⚠️  No se encontró available_networks.json (ni en \$ANSIBLE_CENTER_PATH/inventories ni en el repo); se intentará autodetectar la red local.$(aviso_sudo_sin_preservar_entorno)" >&2
    fi

    if cidr="$(autodetectar_red_local)" && [ -n "$cidr" ]; then
        RED_CIDR="$cidr"
        RED_ORIGEN="autodetectada"
        RED_NOMBRE="LOCAL"
        return 0
    fi

    RED_ORIGEN="fallo"
    return 1
}

mostrar_uso() {
    echo "Uso: $(basename "${BASH_SOURCE[0]}") [LOCAL|NOMBRE_RED|CIDR]" >&2
}

sanear_nombre_archivo() {
    # Sustituye caracteres no aptos para un nombre de fichero (p. ej. "/" en un CIDR)
    tr '/' '-' <<< "$1"
}

resolver_red_param() {
    unset RED_CIDR RED_ORIGEN RED_NOMBRE
    local param="$1" param_mayus cidr json_path

    param_mayus="$(tr '[:lower:]' '[:upper:]' <<< "$param")"

    if [ "$param_mayus" = "LOCAL" ]; then
        if cidr="$(autodetectar_red_local)" && [ -n "$cidr" ]; then
            RED_CIDR="$cidr"
            RED_ORIGEN="param:LOCAL"
            RED_NOMBRE="LOCAL"
            return 0
        fi
        echo "❌ Error: no se pudo autodetectar la red local (LOCAL).$(aviso_sudo_sin_preservar_entorno)" >&2
        return 1
    fi

    if validar_formato_cidr "$param"; then
        RED_CIDR="$param"
        RED_ORIGEN="param:CIDR"
        RED_NOMBRE="$(sanear_nombre_archivo "$param")"
        return 0
    fi

    if json_path="$(localizar_json_redes)"; then
        cidr="$(obtener_cidr_de_json "$json_path" "$param_mayus")"
        if [ -n "$cidr" ]; then
            RED_CIDR="$cidr"
            RED_ORIGEN="param:JSON:${param_mayus}:${json_path}"
            RED_NOMBRE="$param_mayus"
            return 0
        fi
        echo "❌ Error: '$param' no es un CIDR válido ni una red definida en $json_path.$(aviso_sudo_sin_preservar_entorno)" >&2
    else
        echo "❌ Error: '$param' no es un CIDR válido, y no se encontró available_networks.json (ni en \$ANSIBLE_CENTER_PATH/inventories ni en el repo) para buscarlo como nombre de red.$(aviso_sudo_sin_preservar_entorno)" >&2
    fi
    mostrar_uso
    return 1
}

verificar_root() {
    [ "$(id -u)" -eq 0 ]
}

determinar_directorio_salida() {
    local dir
    if [ -n "${ANSIBLE_CENTER_PATH:-}" ]; then
        dir="${ANSIBLE_CENTER_PATH%/}/inventories"
    else
        dir="inventories"
    fi
    mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s\n' "$dir"
}

main() {
    if ! verificar_root; then
        echo "❌ Error: este script necesita privilegios de root para que nmap pueda obtener direcciones MAC (requiere ARP)." >&2
        echo "💡 Ejecuta con: sudo $(basename "${BASH_SOURCE[0]}") $*" >&2
        if [ -n "${ANSIBLE_CENTER_PATH:-}" ]; then
            echo "💡 Como tienes ANSIBLE_CENTER_PATH definida, usa 'sudo -E' en vez de 'sudo' para conservarla." >&2
        fi
        exit 1
    fi

    if [ "$#" -gt 1 ]; then
        echo "❌ Error: demasiados argumentos." >&2
        mostrar_uso
        exit 1
    fi

    if [ -n "${1:-}" ]; then
        resolver_red_param "$1" || exit 1
    elif ! determinar_red; then
        echo "❌ Error: no se pudo determinar la red a escanear (ni available_networks.json con MACROLAN/LAN, ni autodetección de la red local).$(aviso_sudo_sin_preservar_entorno)" >&2
        exit 1
    fi

    case "$RED_ORIGEN" in
        json:MACROLAN:*)  echo "✅ Red elegida: $RED_CIDR (desde available_networks.json, red MACROLAN)" ;;
        json:LAN:*)       echo "✅ Red elegida: $RED_CIDR (desde available_networks.json, red LAN; no se encontró MACROLAN)" ;;
        autodetectada)    echo "✅ Red elegida: $RED_CIDR (autodetectada de la interfaz de red local; no se encontró available_networks.json con MACROLAN/LAN)" ;;
        param:LOCAL)      echo "✅ Red elegida: $RED_CIDR (autodetectada de la interfaz de red local, forzado con el parámetro LOCAL)" ;;
        param:CIDR)       echo "✅ Red elegida: $RED_CIDR (CIDR indicado directamente por parámetro)" ;;
        param:JSON:*)     echo "✅ Red elegida: $RED_CIDR (desde available_networks.json, red indicada por parámetro: ${1^^})" ;;
    esac

    local dir_salida archivo_salida
    if ! dir_salida="$(determinar_directorio_salida)"; then
        echo "❌ Error: no se pudo crear el directorio de salida para el fichero de MACs." >&2
        exit 1
    fi
    archivo_salida="$dir_salida/macs_$(sanear_nombre_archivo "$RED_NOMBRE")_temp.txt"

    # Línea de salida estable para scripts que orquesten este (ver run_playbook.sh):
    # no depende del texto en español, que puede cambiar.
    echo "RUTA_SALIDA=$archivo_salida"

    if [ -n "${ANSIBLE_CENTER_PATH:-}" ]; then
        echo "💾 Guardando en $archivo_salida (ANSIBLE_CENTER_PATH definida)"
    else
        echo "💾 Guardando en $archivo_salida (ANSIBLE_CENTER_PATH no definida; usando inventories/ del directorio actual)"
    fi

    echo "🔍 Escaneando $RED_CIDR con nmap..."
    nmap -sn "$RED_CIDR" | awk '/^Nmap scan report/ {ip=$NF} /MAC Address:/ {mac=$3; print mac, ip}' > "$archivo_salida"

    if [ -s "$archivo_salida" ]; then
        echo "✅ Resultado guardado en $archivo_salida ($(wc -l < "$archivo_salida") equipos con MAC detectada)"
    else
        echo "⚠️  $archivo_salida se ha generado pero está VACÍO: nmap no ha devuelto ninguna dirección MAC en $RED_CIDR." >&2
        echo "💡 Si hay equipos activos en esa red, comprueba que estás en el mismo segmento local (nmap necesita ARP, no funciona a través de un router) y que nmap tiene permisos suficientes." >&2
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
