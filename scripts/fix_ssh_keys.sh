#!/bin/bash
#
# Limpia de ~/.ssh/known_hosts las entradas de una red de clase C y vuelve a
# rellenarlas escaneando los equipos activos de esa red (nmap) y recogiendo
# su fingerprint SSH actual (ssh-keyscan). Útil cuando varias máquinas de un
# aula/laboratorio han reutilizado las mismas IPs y SSH avisa de "host key
# changed" al conectar.
#
# Uso:
#   fix_ssh_keys.sh [red]
#   fix_ssh_keys.sh -h | --help
#
#   [red]   Red de clase C sobre la que actuar, en formato IP con el último
#           octeto a 0 (ej. 192.168.1.0). Solo se usan los tres primeros
#           octetos: se procesa la red <red>.0/24 completa (direcciones
#           .1 a .254). Opcional: si se omite, se autodetecta la red local
#           del equipo (misma lógica que obtener_macs_ip_red.sh) y se
#           muestra por terminal antes de continuar.
#
# Qué hace, en orden:
#   1. Hace un backup de ~/.ssh/known_hosts (known_hosts.backup.<fecha_hora>).
#   2. Elimina de known_hosts (ssh-keygen -R) las entradas de las 254 IPs de
#      la red indicada.
#   3. Escanea esa red con nmap -sn para encontrar los equipos activos.
#   4. Para cada IP activa, añade su fingerprint actual a known_hosts
#      (ssh-keyscan -H).
#
# Requisitos: nmap y ssh-keyscan/ssh-keygen disponibles en el PATH. Se
# recomienda ejecutar con sudo (nmap necesita privilegios para ARP); si no
# se usa, el script avisa y pregunta si continuar. Si se ejecuta con sudo,
# opera sobre el known_hosts del usuario real (vía $SUDO_USER), no el de
# root, y le devuelve la propiedad de los ficheros al terminar.
#
# Ejemplo:
#   fix_ssh_keys.sh 192.168.1.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/obtener_macs_ip_red.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/obtener_macs_ip_red.sh"
fi

mostrar_uso() {
    cat <<'EOF'
Uso: fix_ssh_keys.sh [red]

  [red]   Red de clase C a procesar, en formato IP con el último octeto a 0
          (ej: 192.168.1.0). Se procesa la red <red>.0/24 completa.
          Opcional: si se omite, se autodetecta la red local del equipo.

Ejemplo:
  fix_ssh_keys.sh 192.168.1.0
EOF
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    mostrar_uso
    exit 0
fi

echo "🔧 Solucionando conflictos de SSH keys..."

if ! verificar_root; then
    echo "⚠️  Este script no se está ejecutando como root (sudo); nmap puede fallar o dar resultados incompletos sin privilegios." >&2
    read -r -p "¿Quieres continuar de todas formas? [s/N] " respuesta
    case "$respuesta" in
        [sSyY]|[sS][iI]|[yY][eE][sS]) ;;
        *) echo "Cancelado por el usuario."; exit 1 ;;
    esac
fi

red="$1"

if [ -z "$red" ]; then
    echo "🔎 No se indicó <red>; detectando la red local del equipo..."
    if ! command -v autodetectar_red_local >/dev/null 2>&1 || ! red="$(autodetectar_red_local)" || [ -z "$red" ]; then
        echo "❌ Error: no se pudo detectar automáticamente la red local. Indícala manualmente (ej: 192.168.1.0)." >&2
        mostrar_uso
        exit 1
    fi
    echo "🔎 Red local detectada: $red"
fi

# Determinar el known_hosts del usuario real: con sudo, ~/.ssh/known_hosts
# apunta al de root, no al del usuario que ha invocado el script.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    ssh_user="$SUDO_USER"
else
    ssh_user="$(id -un)"
fi
ssh_home="$(getent passwd "$ssh_user" | cut -d: -f6)"
ssh_dir="$ssh_home/.ssh"
known_hosts="$ssh_dir/known_hosts"

mkdir -p "$ssh_dir"
touch "$known_hosts"

# Crear backup
cp "$known_hosts" "$known_hosts.backup.$(date +%Y%m%d_%H%M%S)"

# Extraer los primeros tres octetos de la red
network=$(echo "$red" | cut -d'.' -f1-3)

# Eliminar entradas conflictivas de la red $1 (primer parámetro)
echo "🗑️ Eliminando entradas antiguas para la red $network.0/24..."
for i in {1..254}; do
    ssh-keygen -R "$network.$i" -f "$known_hosts" >/dev/null 2>&1
done

# Añadir fingerprints correctos de los equipos activos
echo "🔍 Obteniendo nuevos fingerprints para la red $network.0/24..."
for ip in $(nmap -sn $network.0/24 | grep -oE "$network\.[0-9]+"); do
    if ssh-keyscan -H "$ip" >> "$known_hosts" 2>/dev/null; then
        echo "✅ Añadido: $ip"
    else
        echo "⚠️  No se pudo añadir: $ip" >&2
    fi
done

# Si se ha ejecutado con sudo, devolver la propiedad al usuario real
# (si no, known_hosts y su backup quedarían como propiedad de root).
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    chown -R "$ssh_user:$(id -gn "$ssh_user")" "$ssh_dir"
fi

echo "🎯 Listo! Red $network.0/24 procesada correctamente."
