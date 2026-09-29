#!/bin/bash
# network_scanner_dual.sh

# Configuración
USE_SFTP=true  # Cambiar a false para usar sshpass/SSH

# ... (parte inicial del script igual)

# Función unificada que usa SFTP o SSH
create_remote_myhost() {
    local ip=$1
    local mac=$2

    if [ "$USE_SFTP" = true ]; then
        create_remote_myhost_sftp "$ip" "$mac"
    else
        create_remote_myhost_ssh "$ip" "$mac"
    fi
}

# Función SSH (versión original)
create_remote_myhost_ssh() {
    local ip=$1
    local mac=$2

    # Primero verificar si el archivo ya existe
    local existing_myhost=$(get_remote_myhost_ssh "$ip" "$mac")
    if [ -n "$existing_myhost" ]; then
        echo "$existing_myhost"
        return 0
    fi

    # Limpiar MAC y obtener últimos 6 dígitos
    local clean_mac=$(echo "$mac" | tr -d ':' | tr '[:lower:]' '[:upper:]')
    local last_six=${clean_mac: -6}
    local new_myhost="host${last_six}"

    log_message "MAC $mac → Creando myhost via SSH en $ip"

    # Comando SSH
    local cmd="mkdir -p /opt/mn3ts && echo '$new_myhost' > /opt/mn3ts/myhost && chmod -R 777 /opt/mn3ts"

    if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USERNAME@$ip" "$cmd" 2>/dev/null; then
        log_message "MAC $mac → ✓ ÉXITO via SSH"
        echo "$new_myhost"
        return 0
    else
        log_message "MAC $mac → ✗ FALLO SSH"
        echo ""
        return 1
    fi
}

# Función SFTP
create_remote_myhost_sftp() {
    local ip=$1
    local mac=$2

    # Verificar si ya existe
    local existing_myhost=$(get_remote_myhost_sftp "$ip" "$mac")
    if [ -n "$existing_myhost" ]; then
        echo "$existing_myhost"
        return 0
    fi

    # Limpiar MAC y obtener últimos 6 dígitos
    local clean_mac=$(echo "$mac" | tr -d ':' | tr '[:lower:]' '[:upper:]')
    local last_six=${clean_mac: -6}
    local new_myhost="host${last_six}"

    # Archivo temporal
    local temp_file="/tmp/myhost_${ip}_$$.txt"
    echo "$new_myhost" > "$temp_file"

    log_message "MAC $mac → Creando myhost via SFTP en $ip"

    # Script SFTP batch
    local sftp_batch="
mkdir /opt/mn3ts
put $temp_file /opt/mn3ts/myhost
chmod 777 /opt/mn3ts
chmod 666 /opt/mn3ts/myhost
quit
"

    # Ejecutar SFTP
    if echo "$sftp_batch" | sshpass -p "$PASSWORD" sftp -b - -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USERNAME@$ip" 2>/dev/null; then
        log_message "MAC $mac → ✓ ÉXITO via SFTP"
        rm -f "$temp_file"
        echo "$new_myhost"
        return 0
    else
        log_message "MAC $mac → ✗ FALLO SFTP"
        rm -f "$temp_file"
        echo ""
        return 1
    fi
}

# Función para verificar con SSH
get_remote_myhost_ssh() {
    local ip=$1
    local mac=$2

    local content=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$USERNAME@$ip" "cat /opt/mn3ts/myhost 2>/dev/null" 2>/dev/null)

    if [ -n "$content" ]; then
        log_message "MAC $mac → ✓ MyHost existe via SSH: $content"
        echo "$content"
        return 0
    fi

    echo ""
    return 1
}

# Función para verificar con SFTP
get_remote_myhost_sftp() {
    local ip=$1
    local mac=$2

    local temp_file="/tmp/myhost_check_${ip}_$$.txt"

    if sshpass -p "$PASSWORD" sftp -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$USERNAME@$ip:/opt/mn3ts/myhost" "$temp_file" 2>/dev/null; then
        local content=$(cat "$temp_file" 2>/dev/null | tr -d '\0')
        if [ -n "$content" ]; then
            log_message "MAC $mac → ✓ MyHost existe via SFTP: $content"
            rm -f "$temp_file"
            echo "$content"
            return 0
        fi
    fi

    rm -f "$temp_file"
    echo ""
    return 1
}
