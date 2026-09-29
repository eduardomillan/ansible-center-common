#!/bin/bash
# network_scanner_v2.sh

# Configuración
USE_SFTP=true  # Cambiar a false para usar sshpass/SSH ***

# Valores por defecto - Usar variables de entorno para evitar hardcoding
# SECURITY: Valores por defecto para lab (cambiar según tu entorno)
DEFAULT_USER="${NETWORK_SCANNER_USER:-lliurex}"
DEFAULT_PASS="${NETWORK_SCANNER_PASS:-lliurex}"
# Nota: Para mayor seguridad, pasar las credenciales como parámetros:
#   ./network_scanner_v2.sh 192.168.0.0/24 tu_usuario tu_password
USERNAME=""
PASSWORD=""
NETWORK=""
DESTDIR="/opt/bocamgmt"
OUTPUT_FILE="network_scan_results.txt"
TEMP_FILE="/tmp/network_scan_temp.txt"



# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 <red_cidr> [usuario] [contraseña]"
    echo "Ejemplo: $0 192.168.0.0/24"
    echo "Ejemplo: $0 192.168.0.0/24 miUsuario miPassword"
    echo ""
    echo "Si no se especifica usuario/contraseña, se usan:"
    echo "Usuario: $DEFAULT_USER"
    echo "Contraseña: $DEFAULT_PASS"
    exit 1
}



# Función para verificar permisos de sudo
check_sudo_permissions() {
    if ! sudo -n true 2>/dev/null; then
        echo "=========================================="
        echo "ERROR: Permisos de sudo requeridos"
        echo "=========================================="
        echo "Este script necesita permisos de administrador para:"
        echo "  - Ejecutar nmap con privilegios"
        echo "  - Acceder a la tabla ARP"
        echo "  - Realizar escaneo de red"
        echo ""
        echo "Por favor, ejecuta el script con:"
        echo "  sudo $0 $@"
        echo "=========================================="
        exit 1
    fi
}



# Función para verificar e instalar dependencias
check_dependencies() {
    local missing_deps=()

    if ! command -v nmap >/dev/null 2>&1; then
        missing_deps+=("nmap")
    fi

    if ! command -v sshpass >/dev/null 2>&1; then
        missing_deps+=("sshpass")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "=========================================="
        echo "ERROR: Dependencias faltantes"
        echo "=========================================="
        echo "Las siguientes herramientas necesarias no están instaladas:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Instálalas con:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install ${missing_deps[*]}"
        echo "=========================================="
        exit 1
    fi
}



# Función para log con timestamp
log_message() {
    local message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] $message"
}



# Función para diagnosticar el problema SSH
diagnose_ssh_connection() {
    local ip=$1
    local user=$2
    local pass=$3

    echo "=== DIAGNÓSTICO SSH ==="
    echo "IP: $ip"
    echo "Usuario: $user"

    # 1. Verificar si el host es alcanzable
    echo "1. Verificando conectividad..."
    if ping -c 2 -W 1 "$ip" &>/dev/null; then
        echo "   ✓ Host alcanzable"
    else
        echo "   ✗ Host NO alcanzable"
        #return 1
    fi

    # 2. Verificar si el puerto SSH está abierto
    echo "2. Verificando puerto SSH (22)..."
    if nc -z -w 2 "$ip" 22 &>/dev/null; then
        echo "   ✓ Puerto 22 abierto"
    else
        echo "   ✗ Puerto 22 cerrado"
        #return 1
    fi

    # 3. Verificar autenticación sin sshpass (para ver error real)
    echo "3. Probando autenticación SSH..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=yes "$user@$ip" "echo 'Éxito'" 2>&1 | head -5
    #sshpass -p your_password ssh user@hostname

    return 0
}



# Función para obtener el contenido de myhost remoto
get_remote_myhost() {
    local ip=$1
    local mac=$2

    # Validaciones básicas
    [ -z "$ip" ] && return 1
    [ -z "$mac" ] && return 1

    # Preparar contenido esperado
    local expected_content=$(generate_myhost "$ip" "$mac")

    # Intentar leer archivo existente
    local remote_content=$(echo "$PASSWORD" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USERNAME@$ip" "sudo -S cat $DESTDIR/myhost 2>/dev/null")

    # Si existe y tiene contenido válido, retornarlo
    if [ $? -eq 0 ] && [ -n "$remote_content" ] && [[ "$remote_content" =~ ^host[0-9A-F]{6}$ ]]; then
        echo $remote_content
        return 0
    fi

}



# Función robusta que maneja hostnames inválidos
get_remote_hostname() {
    local ip=$1
    local mac=$2

    local remote_hostname=$(echo "$PASSWORD" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$USERNAME@$ip" "sudo -S hostname 2>/dev/null")
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -n "$remote_hostname" ] && [ "$remote_hostname" != "unknown" ]; then
        #echo "✓ Hostname válido: $remote_hostname"
        echo "$remote_hostname"
        return 0
    else
        # Si el hostname es inválido, generar uno basado en la MAC
        #echo "✗ Hostname inválido o error, generando alternativo..."
        local fallback_hostname=$(generate_fallback_hostname "$mac")
        echo "$fallback_hostname"
        return 1
    fi
}




# Función simplificada para cambiar hostname
change_remote_hostname() {
    local ip=$1
    local cur_hostname=$2
    local new_hostname=$3

    # Change hostname in /etc/hosts & /etc/hostname
    # sudo sed -i "s/$CUR_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
    # sudo sed -i "s/$CUR_HOSTNAME/$NEW_HOSTNAME/g" /etc/hostname


    # Comando compacto
    local cmd="
        echo '$PASSWORD' | sudo -S sed -i 's/$cur_hostname/$new_hostname/g' /etc/hosts 2>/dev/null ||
        echo '$PASSWORD' | sudo -S hostnamectl set-hostname '$new_hostname' 2>/dev/null ||
        echo '$PASSWORD' | sudo -S bash -c 'echo \"$new_hostname\" > /etc/hostname' 2>/dev/null ||
        echo '$PASSWORD' | sudo -S hostname '$new_hostname' 2>/dev/null
    "

    echo "$PASSWORD" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$USERNAME@$ip" "$cmd" &>/dev/null

    if [ $? -eq 0 ]; then
        echo "✓ Hostname cambiado a: $new_hostname"
        return 0
    else
        echo "✗ Error cambiando hostname"
        return 1
    fi
}


# Función para generar hostname de respaldo
generate_fallback_hostname() {
    local mac=$1
    local clean_mac=$(echo "$mac" | tr -d ':' | tr -d '-' | tr '[:lower:]' '[:upper:]')
    local last_six="${clean_mac: -6}"
    echo "host${last_six}"
}



# Función modificada para usar sudo remotamente
create_remote_myhost_suded() {
    local ip=$1
    local mac=$2

    # Preparar contenido
    local expected_content=$(generate_myhost "$ip" "$mac")


    # Comando con sudo -S (lee password desde stdin)
    local create_cmd="sudo -S mkdir -p $DESTDIR &&
                     echo '$expected_content' | sudo tee $DESTDIR/myhost >/dev/null &&
                     sudo chmod 777 $DESTDIR &&
                     sudo chmod 666 $DESTDIR/myhost"


    # Ejecutar con echo del password piped to sudo -S
    local result=$(echo "$PASSWORD" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USERNAME@$ip" "$create_cmd" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$expected_content"
    else
        echo ""
    fi
}


# Función que genera el nombre para el myhost
generate_myhost() {
  local ip=$1
  local mac=$2

  # Verificar que se pasen los parámetros
  if [ -z "$mac" ] || [ -z "$ip" ]; then
    echo "Error: Se requieren los parámetros MAC e IP." >&2
    return 1
  fi

  # Convertir la MAC a mayúsculas y quitar los separadores
  local mac_formateada=$(echo "$mac" | tr '[:lower:]' '[:upper:]' | tr -d '[:punct:]')

  # Extraer el cuarto byte de la IP
  local cuarto_byte_ip=$(echo "$ip" | awk -F'.' '{print $4}')

  # Construir la cadena myhost
  local myhost="host-${mac_formateada}-${cuarto_byte_ip}"

  echo "$myhost"
}



# Comprobar si existe el myhost y crearlo si no es así
create_remote_myhost() {
    local ip=$1
    local mac=$2

    # Primero verificar si el archivo ya existe
    local existing_myhost=$(get_remote_myhost "$ip" "$mac")
    if [ -n "$existing_myhost" ]; then
        echo "$existing_myhost"
        return 0
    fi

    create_remote_myhost_suded "$ip" "$mac"
}



# Función para verificar si una IP ya existe en el archivo
ip_exists() {
    local ip=$1
    grep -q " $ip " "$TEMP_FILE"
}



# Función para actualizar registro existente según la mac
update_entry_by_mac() {
  local the_mac=$1
  local new_ip=$2
  local new_hostname=$3
  local new_myhost=$4

  log_message "Updating entry by mac: $the_mac $ip $hostname $myhost"

  # Verifica que se hayan pasado todos los parámetros
  if [ -z "$TEMP_FILE" ] || [ -z "$the_mac" ] || [ -z "$new_ip" ] || [ -z "$new_hostname" ] || [ -z "$new_myhost" ]; then
    echo "Uso: update_entry_by_mac <ruta_del_archivo> <mac> <ip> <hostname> <myhost>"
    return 1
  fi

  # Usa awk para buscar la MAC y actualizar la línea
  awk -v mac="$the_mac" -v ip="$new_ip" -v host="$new_hostname" -v myhost="$new_myhost" '
  $1 == mac {
    $2 = ip
    $3 = host
    $4 = myhost
  }
  { print }' "$TEMP_FILE" > temp_file && mv temp_file "$TEMP_FILE"
}



# Función para añadir nuevo registro
add_new_record() {
    local mac=$1
    local ip=$2
    local hostname=$3
    local myhost=$4

    echo "$mac $ip $hostname $myhost" >> "$TEMP_FILE"
}



# Función para determinar si excluir una IP
should_exclude_ip() {
    local ip=$1
    local last_octet=$(echo "$ip" | cut -d'.' -f4)

    # Verificar que last_octet es un número
    if ! [[ "$last_octet" =~ ^[0-9]+$ ]]; then
        return 1  # No excluir si no es número válido
    fi

    # Excluir .1 (gateway/router)
    if [ "$last_octet" -eq 1 ]; then
        return 0  # true = excluir
    fi

    # Excluir <= .11 (IPs de red/broadcast/reservadas)
    if [ "$last_octet" -ge 1 ] && [ "$last_octet" -le 11 ]; then
        return 0  # true = excluir
    fi


    # Excluir >= .240 (IPs de red/broadcast/reservadas)
    if [ "$last_octet" -ge 240 ] && [ "$last_octet" -le 254 ]; then
        return 0  # true = excluir
    fi

    return 1  # false = no excluir
}



# Función helper para calcular porcentaje
calculate_percentage() {
    local current=$1
    local total=$2
    if [ $total -eq 0 ]; then
        echo "0.0"
    else
        awk "BEGIN {printf \"%.1f\", 100 * $current / $total}"
    fi
}



# Función para escanear la red
scan_network() {
    log_message "Iniciando escaneo de la red $NETWORK"
    log_message "Filtros activos: Excluyendo IP <=.11 y IPs >= .240"

    # Variables temporales para el procesamiento
    local current_ip=""
    local current_hostname=""
    local current_mac=""


    # Obtener directorio del script
    local script_dir=$(dirname "$(readlink -f "$0")")
    local nmap_temp_file="${script_dir}/nmap_scan_$$.tmp"
    local nmap_error_file="${script_dir}/nmap_error_$$.tmp"

    log_message "Archivo temporal: $nmap_temp_file"

    # Ejecutar nmap con redirección de errores
    log_message "Ejecutando: nmap -sn $NETWORK"
    nmap -sn $NETWORK > "$nmap_temp_file" 2> "$nmap_error_file"
    local nmap_exit_code=$?

    # Verificar errores
    if [ $nmap_exit_code -ne 0 ]; then
        log_message "ERROR: nmap falló con código $nmap_exit_code"
        if [ -s "$nmap_error_file" ]; then
            log_message "Mensaje de error: $(cat "$nmap_error_file")"
        fi
        rm -f "$nmap_temp_file" "$nmap_error_file"
        return 1
    fi

    if [ ! -s "$nmap_temp_file" ]; then
        log_message "ERROR: nmap no produjo resultados"
        rm -f "$nmap_temp_file" "$nmap_error_file"
        return 1
    fi

    # Mostrar tamaño del archivo temporal
    local file_size=$(du -h "$nmap_temp_file" | cut -f1)
    log_message "Resultados de nmap guardados ($file_size). Procesando..."

    # Contar líneas para progreso
    local total_lines=$(wc -l < "$nmap_temp_file")
    local current_line=0

    # Procesar archivo
    while IFS= read -r line; do
        ((current_line++))

        # En la línea del printf:
        percentage=$(calculate_percentage $current_line $total_lines)
        #printf "\rProcesando línea %d/%d (%s%%)" "$current_line" "$total_lines" "$percentage"

        #log_message "Line: $line"

        # Caso 1: Línea con "Nmap scan report for" (puede tener diferentes formatos)
        if [[ $line == *"Nmap scan report for"* ]]; then
            # Resetear MAC para nuevo host
            current_mac=""

            # Diferentes formatos que puede tener nmap:
            # 1. "Nmap scan report for hostname (ip)"
            # 2. "Nmap scan report for ip"
            # 3. "Nmap scan report for hostname"

            if [[ $line =~ \(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\) ]]; then
                # Formato: hostname (ip)
                current_ip="${BASH_REMATCH[1]}"
                current_hostname=$(echo "$line" | awk '{print $5}')
            else
                # Formato: ip o hostname solo
                local possible_ip=$(echo "$line" | awk '{print $5}')
                if [[ $possible_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    current_ip="$possible_ip"
                    current_hostname="unknown"
                else
                    current_hostname="$possible_ip"
                    # La IP vendrá en líneas siguientes
                    current_ip=""
                fi
            fi

            #log_message "Current ip: $current_ip"

            # Si tenemos IP, verificar si debe ser excluida
            if [ -n "$current_ip" ] && should_exclude_ip "$current_ip"; then
                log_message "IP $current_ip excluida por filtro"
                current_ip=""
                current_hostname=""
                continue
            fi

        # Caso 2: Línea con MAC Address
        elif [[ $line == *"MAC Address:"* ]]; then
            current_mac=$(echo "$line" | awk '{print $3}')

            # Si no tenemos IP de la línea anterior, intentar extraerla
            if [ -z "$current_ip" ] && [[ $line =~ \([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\) ]]; then
                current_ip="${BASH_REMATCH[1]}"
            fi

            # Verificar si tenemos todos los datos necesarios
            if [ -n "$current_ip" ] && [ -n "$current_mac" ]; then
                process_host "$current_ip" "$current_mac" "$current_hostname"
                # Resetear para siguiente host
                current_ip=""
                current_hostname=""
                current_mac=""
            fi

            #log_message "Current mac: $current_mac"

        # Caso 3: Línea con "Host is up" (puede contener IP si no se encontró MAC)
        elif [[ $line == *"Host is up"* ]] && [ -n "$current_ip" ] && [ -z "$current_mac" ]; then
            # Intentar obtener MAC desde ARP
            current_mac=$(get_mac_from_arp "$current_ip")

            if [ -n "$current_mac" ] && [ "$current_mac" != "Unknown" ]; then
                process_host "$current_ip" "$current_mac" "$current_hostname"
            else
                log_message "Host $current_ip activo pero no se pudo obtener MAC"
            fi

            # Resetear para siguiente host
            current_ip=""
            current_hostname=""
            current_mac=""
        fi

    done < "$nmap_temp_file"

    # Procesar último host si quedó pendiente
    if [ -n "$current_ip" ] && [ -n "$current_mac" ]; then
        process_host "$current_ip" "$current_mac" "$current_hostname"
    fi

    echo ""  # Nueva línea después del progreso

    # Limpiar archivos temporales
    rm -f "$nmap_temp_file" "$nmap_error_file"
    log_message "Archivos temporales eliminados"
    log_message "Procesamiento de resultados completado"

}



# Procesar cada IP o hostname encontrado con el escaneo
process_host() {
    local ip=$1
    local mac=$2
    local hostname=$3

    remote_hostname=$(get_remote_hostname "$ip" "$mac")

    # Si el hostname está vacío o es "unknown", intentar resolverlo
    if [ -z "$hostname" ] || [ "$hostname" == "unknown" ]; then
        hostname=$remote_hostname
    fi

    #Borrar la información creada previamente
    #delete_remote_myhost $ip $mac all

    # Obtener o crear el archivo myhost
    myhost_content=$(create_remote_myhost "$ip" "$mac")

    log_message "HOST ENCONTRADO: IP=$ip | MAC=$mac | Hostname=$hostname | MyHost=$myhost_content"


    if [ "$remote_hostname" != "$myhost_content" ]; then
        change_remote_hostname $ip $remote_hostname $myhost_content
    fi


    if [ -z "$myhost_content" ]; then
        myhost_content="ERROR"
        log_message "MAC $mac → ✗ No se pudo obtener/crear myhost"
    fi

    # Verificar si la IP ya existe en el archivo
    if ip_exists "$ip"; then
        log_message "MAC $mac → Actualizando registro existente"
        update_entry_by_mac "$mac" "$ip" "$hostname" "$myhost_content"
    else
        log_message "MAC $mac → Añadiendo nuevo registro"
        add_new_record "$mac" "$ip" "$hostname" "$myhost_content"
    fi

    log_message "MAC $mac → Registro completo: $mac $ip $hostname $myhost_content"
    echo "--------------------------------------------------"
}



# Función para obtener MAC desde tabla ARP (como respaldo)
get_mac_from_arp() {
    local ip=$1
    # Forzar ping para poblar ARP
    ping -c 1 -W 1 "$ip" >/dev/null 2>&1

    # Buscar en tabla ARP
    local mac=$(arp -n "$ip" 2>/dev/null | awk '/^'$ip'/ {print $3}')

    if [ -n "$mac" ] && [[ $mac =~ ^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$ ]]; then
        echo "$mac"
    else
        echo "Unknown"
    fi
}



# Función con diferentes niveles de eliminación
delete_remote_myhost() {
    local ip=$1
    local mac=$2
    local mode="${3:-file}"  # file, dir, all

    case "$mode" in
        "file")
            # Eliminar solo el archivo
            delete_remote_myhost_file "$ip" "$mac"
            ;;
        "dir")
            # Eliminar directorio completo
            delete_remote_destdir "$ip" "$mac"
            ;;
        "all")
            # Eliminar archivo y luego directorio si está vacío
            if delete_remote_myhost_file "$ip" "$mac"; then
                delete_remote_destdir_if_empty "$ip" "$mac"
            fi
            ;;
        *)
            echo "Modo inválido: $mode (usar: file, dir, all)"
            return 1
            ;;
    esac
}



# Función auxiliar para eliminar solo el archivo myhost
delete_remote_myhost_file() {
    local ip=$1
    local mac=$2

    local cmd="echo '$PASSWORD' | sudo -S rm -f '$DESTDIR/myhost'"
    echo "$PASSWORD" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$ip" "$cmd" &>/dev/null
}


# Función auxiliar para eliminar directorio si está vacío
delete_remote_destdir_if_empty() {
    local ip=$1
    local mac=$2

    local cmd="
        if [ -d '$DESTDIR' ] && [ -z \"\$(ls -A '$DESTDIR')\" ]; then
            echo '$PASSWORD' | sudo -S rmdir '$DESTDIR'
        fi
    "
    echo "$PASSWORD" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$ip" "$cmd" &>/dev/null
}


# Función para eliminar directorio completo de mn3ts
delete_remote_destdir() {
    local ip=$1
    local mac=$2

    echo "=== ELIMINANDO DIRECTORIO COMPLETO EN $ip ==="

    # Comando para eliminar directorio recursivamente
    local delete_cmd="
        if [ -d '$DESTDIR' ]; then
            echo 'Eliminando directorio $DESTDIR...'
            echo '$PASSWORD' | sudo -S rm -rf '$DESTDIR'

            if [ ! -d '$DESTDIR' ]; then
                echo 'DIR_DELETED'
            else
                echo 'DIR_DELETE_FAILED'
                exit 1
            fi
        else
            echo 'DIR_NOT_FOUND'
        fi
    "

    local result=$(echo "$PASSWORD" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$USERNAME@$ip" "$delete_cmd" 2>&1)

    case "$result" in
        *"DIR_DELETED"*)
            echo "✓ Directorio $DESTDIR eliminado completamente"
            return 0
            ;;
        *"DIR_NOT_FOUND"*)
            echo "⚠ Directorio $DESTDIR no existía"
            return 0
            ;;
        *"DIR_DELETE_FAILED"*)
            echo "✗ Error eliminando directorio"
            return 1
            ;;
        *)
            echo "✗ Error desconocido: $result"
            return 1
            ;;
    esac
}



###################################################################################3
# Programa principal
###################################################################################3


# Verificar argumentos
if [ $# -lt 1 ]; then
    show_help
fi

NETWORK=$1

# Obtener credenciales (si se proporcionan)
if [ $# -ge 2 ]; then
    USERNAME=$2
else
    USERNAME=$DEFAULT_USER
fi

if [ $# -ge 3 ]; then
    PASSWORD=$3
else
    PASSWORD=$DEFAULT_PASS
fi

# Verificar permisos de sudo al inicio
check_sudo_permissions "$@"

# Verificar dependencias
check_dependencies

echo "=========================================="
echo "      ESCANER DE RED"
echo "=========================================="
echo "Red: $NETWORK"
echo "Usuario: $USERNAME"
echo "Contraseña: [oculta]"
echo "Ejecutando con permisos de sudo: ✓"
echo "Formato salida: MAC IP Hostname MyHost"
echo "=========================================="

# Crear archivo temporal vacío (sin encabezados)
> "$TEMP_FILE"

# Si el archivo de salida existe, copiar su contenido (sin encabezados)
if [ -f "$OUTPUT_FILE" ]; then
    # Filtrar líneas que no son encabezados
    grep -v "MAC,IP,Hostname,MyHost" "$OUTPUT_FILE" | grep -v "====" > "$TEMP_FILE"
else
    > "$OUTPUT_FILE"
fi


# Ejecutar escaneo
scan_network

# Reemplazar archivo original con el temporal
mv "$TEMP_FILE" "$OUTPUT_FILE"

echo "=========================================="
log_message "ESCANEO COMPLETADO"
echo "=========================================="

# Mostrar resumen final
total_hosts=$(wc -l < "$OUTPUT_FILE" 2>/dev/null)
success_hosts=$(grep -v "ERROR" "$OUTPUT_FILE" | wc -l 2>/dev/null)
error_hosts=$((total_hosts - success_hosts))

log_message "TOTAL HOSTS ENCONTRADOS: $total_hosts"
log_message "HOSTS CON MYHOST EXITOSO: $success_hosts"
log_message "HOSTS CON ERROR EN MYHOST: $error_hosts"
log_message "ARCHIVO DE RESULTADOS: $OUTPUT_FILE"
log_message "ÚLTIMA ACTUALIZACIÓN: $(date)"

echo "=========================================="
echo "Contenido del archivo de resultados:"
echo "=========================================="
cat "$OUTPUT_FILE"
echo "=========================================="

# Verificar si hubo errores de conexión
if [ "$error_hosts" -gt 0 ]; then
    echo "ADVERTENCIA: Hubo $error_hosts errores al obtener/crear myhost"
    echo "Puede que necesites verificar las credenciales proporcionadas"
    echo "Hosts con error:"
    grep "ERROR" "$OUTPUT_FILE" | awk '{print $2}'
fi

echo "=========================================="
