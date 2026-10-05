#!/bin/bash
#
# Orquesta el flujo completo para ejecutar un playbook contra equipos reales,
# sin tener que lanzar a mano obtener_macs_ip_red.sh, createinv_macs_v4.py y
# ansible-playbook por separado. Pensado para ejecutarse desde
# ansible-center-common; los datos privados (playbooks propios del centro,
# inventories, available_networks.json...) se buscan en $ANSIBLE_CENTER_PATH
# si está definida (ver README.md, sección "Variable de entorno
# ANSIBLE_CENTER_PATH"), igual que el resto de scripts de esta carpeta.
#
# Uso:
#   run_playbook.sh --playbook RUTA --inventory ARCHIVO.ini [-- ARGS...]
#   run_playbook.sh --playbook RUTA --macs ARCHIVO.txt [--red RED] [-- ARGS...]
#   run_playbook.sh --playbook RUTA --discover [--red RED] [-- ARGS...]
#
#   --playbook RUTA   Ruta relativa dentro de playbooks/ (ej. ssh-check/check.yml).
#                      Se busca primero en $ANSIBLE_CENTER_PATH/playbooks/ y
#                      después en playbooks/ de este repo.
#   --inventory ARCH  Usa ese inventory .ini directamente (no genera nada).
#   --macs ARCH       Genera el inventory a partir de ese fichero de MACs
#                      (createinv_macs_v4.py), con la red indicada en --red.
#   --discover        Escanea la red en vivo primero (obtener_macs_ip_red.sh)
#                      y genera el inventory a partir de ese resultado.
#                      Requiere ejecutar este script como root (sudo/sudo -E),
#                      igual que obtener_macs_ip_red.sh.
#   --red RED         Red a usar con --macs/--discover: nombre de
#                      available_networks.json, CIDR, o LOCAL. Opcional (cada
#                      script usa su propio valor por defecto si se omite).
#   --                Todo lo que sigue se reenvía tal cual a ansible-playbook
#                      (--limit, -e, --ask-become-pass, --ask-vault-pass...).
#
# El propio ansible-playbook se ejecuta con el directorio de trabajo en
# $ANSIBLE_CENTER_PATH (si está definida), para que recoja su ansible.cfg,
# group_vars y vault_secrets.yml reales; si no, en la raíz de este repo.
#
# Ejemplos:
#   run_playbook.sh --playbook ssh-check/check.yml --inventory inventories/inventory_inf3.ini
#   run_playbook.sh --playbook ssh-check/check.yml --macs macs_inf3_alu.txt --red INFOR3
#   sudo -E run_playbook.sh --playbook ssh-check/check.yml --discover --red INFOR3 -- --ask-become-pass

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mostrar_uso() {
    cat >&2 <<'EOF'
Uso:
  run_playbook.sh --playbook RUTA --inventory ARCHIVO.ini [-- ARGS...]
  run_playbook.sh --playbook RUTA --macs ARCHIVO.txt [--red RED] [-- ARGS...]
  run_playbook.sh --playbook RUTA --discover [--red RED] [-- ARGS...]

  --playbook RUTA   Ruta relativa dentro de playbooks/ (ej. ssh-check/check.yml)
  --inventory ARCH  Usa ese inventory .ini directamente
  --macs ARCH       Genera el inventory desde ese fichero de MACs
  --discover        Escanea la red en vivo primero y genera el inventory a partir del resultado
  --red RED         Red a usar en --macs/--discover (opcional)
  --                Todo lo siguiente se reenvía a ansible-playbook

Ejemplos:
  run_playbook.sh --playbook ssh-check/check.yml --inventory inventories/inventory_inf3.ini
  run_playbook.sh --playbook ssh-check/check.yml --macs macs_inf3_alu.txt --red INFOR3
  sudo -E run_playbook.sh --playbook ssh-check/check.yml --discover --red INFOR3 -- --ask-become-pass
EOF
}

repo_base() {
    if [ -n "${ANSIBLE_CENTER_PATH:-}" ]; then
        printf '%s\n' "${ANSIBLE_CENTER_PATH%/}"
    else
        printf '%s\n' "$(cd "$SCRIPT_DIR/.." && pwd)"
    fi
}

resolver_playbook() {
    local rel="$1" base candidato encontrado=""
    for base in "$(repo_base)" "$(cd "$SCRIPT_DIR/.." && pwd)"; do
        candidato="$base/playbooks/$rel"
        if [ -f "$candidato" ]; then
            printf '%s\n' "$candidato"
            return 0
        fi
    done
    return 1
}

resolver_inventory_existente() {
    local nombre="$1" base candidato
    if [ -f "$nombre" ]; then
        realpath "$nombre"
        return 0
    fi
    for base in "$(repo_base)" "$(cd "$SCRIPT_DIR/.." && pwd)"; do
        candidato="$base/inventories/$(basename "$nombre")"
        if [ -f "$candidato" ]; then
            realpath "$candidato"
            return 0
        fi
    done
    return 1
}

ejecutar_con_log() {
    # Ejecuta "$@", mostrando su salida en vivo por stderr (para no
    # mezclarla con lo que esta función devuelve por stdout), y la guarda
    # también en un fichero temporal cuya ruta imprime por stdout. El
    # llamador debe borrar ese fichero cuando termine de usarlo. Conserva
    # el código de salida real del comando (vía PIPESTATUS, no el de `tee`).
    local log_tmp estado
    log_tmp="$(mktemp)"
    "$@" 2>&1 | tee "$log_tmp" >&2
    estado=${PIPESTATUS[0]}
    printf '%s\n' "$log_tmp"
    return "$estado"
}

extraer_ruta_salida() {
    # Busca en el fichero de log la última línea "RUTA_SALIDA=..." (ver
    # obtener_macs_ip_red.sh y createinv_macs_v4.py) y devuelve solo la ruta.
    sed -n 's/^RUTA_SALIDA=//p' "$1" | tail -1
}

main() {
    local playbook_rel="" red="" modo="" macs_arg="" inventory_arg=""
    local -a extra_args=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --playbook) playbook_rel="${2:-}"; shift 2 ;;
            --red) red="${2:-}"; shift 2 ;;
            --inventory) modo="inventory"; inventory_arg="${2:-}"; shift 2 ;;
            --macs) modo="macs"; macs_arg="${2:-}"; shift 2 ;;
            --discover) modo="discover"; shift ;;
            --) shift; extra_args=("$@"); break ;;
            -h|--help) mostrar_uso; exit 0 ;;
            *) echo "❌ Error: argumento no reconocido: $1" >&2; mostrar_uso; exit 1 ;;
        esac
    done

    if [ -z "$playbook_rel" ]; then
        echo "❌ Error: falta --playbook" >&2
        mostrar_uso
        exit 1
    fi
    if [ -z "$modo" ]; then
        echo "❌ Error: indica uno de --inventory, --macs o --discover" >&2
        mostrar_uso
        exit 1
    fi

    local playbook_path
    if ! playbook_path="$(resolver_playbook "$playbook_rel")"; then
        echo "❌ Error: no se encontró el playbook '$playbook_rel' (ni en \$ANSIBLE_CENTER_PATH/playbooks/ ni en el repo)" >&2
        exit 1
    fi
    echo "📘 Playbook: $playbook_path"

    local inventory_path=""

    case "$modo" in
        inventory)
            if ! inventory_path="$(resolver_inventory_existente "$inventory_arg")"; then
                echo "❌ Error: no se encontró el inventory '$inventory_arg' (ni tal cual, ni en inventories/ de \$ANSIBLE_CENTER_PATH o del repo)" >&2
                exit 1
            fi
            if [ -n "$red" ]; then
                echo "ℹ️  --red se ignora: ya se ha indicado un --inventory directamente."
            fi
            ;;

        macs|discover)
            local macs_file="$macs_arg"

            if [ "$modo" = "discover" ]; then
                echo "== Paso 1/3: escaneo en vivo (obtener_macs_ip_red.sh) =="
                local log1 estado1
                log1="$(ejecutar_con_log "$SCRIPT_DIR/obtener_macs_ip_red.sh" ${red:+"$red"})"
                estado1=$?
                macs_file="$(extraer_ruta_salida "$log1")"
                rm -f "$log1"
                if [ "$estado1" -ne 0 ]; then
                    echo "❌ Error: falló el escaneo en vivo (obtener_macs_ip_red.sh)" >&2
                    exit 1
                fi
                if [ -z "$macs_file" ]; then
                    echo "❌ Error: no se pudo determinar dónde guardó obtener_macs_ip_red.sh el fichero de MACs" >&2
                    exit 1
                fi
                if [ ! -s "$macs_file" ]; then
                    echo "❌ Error: $macs_file está vacío; no se generará un inventory a partir de un escaneo sin resultados." >&2
                    exit 1
                fi
            fi

            echo "== Paso 2/3: generar inventory (createinv_macs_v4.py) =="
            local log2 estado2
            log2="$(ejecutar_con_log python3 "$SCRIPT_DIR/createinv_macs_v4.py" "$macs_file" ${red:+"$red"})"
            estado2=$?
            inventory_path="$(extraer_ruta_salida "$log2")"
            rm -f "$log2"
            if [ "$estado2" -ne 0 ]; then
                echo "❌ Error: falló la generación del inventory (createinv_macs_v4.py)" >&2
                exit 1
            fi
            if [ -z "$inventory_path" ]; then
                echo "❌ Error: no se pudo determinar dónde guardó createinv_macs_v4.py el inventory" >&2
                exit 1
            fi
            inventory_path="$(realpath "$inventory_path")"
            ;;
    esac

    echo "== Paso 3/3: ejecutar ansible-playbook =="
    local base
    base="$(repo_base)"
    echo "🚀 (cd $base && ansible-playbook $playbook_path -i $inventory_path ${extra_args[*]})"
    (cd "$base" && ansible-playbook "$playbook_path" -i "$inventory_path" "${extra_args[@]}")
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
