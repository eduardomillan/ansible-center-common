# Función para escanear la red
scan_network() {
    log_message "Iniciando escaneo de la red $NETWORK"
    log_message "Filtros activos: Excluyendo IP .1 y IPs >= .240"

    # Crear archivo temporal en el directorio actual
    local nmap_temp_file="./nmap_scan_$$.tmp"
    local nmap_error_file="./nmap_error_$$.tmp"

    log_message "Archivo temporal de nmap: $nmap_temp_file"

    # Ejecutar nmap y guardar resultado en archivo temporal
    log_message "Ejecutando: nmap -sn $NETWORK"
    nmap -sn $NETWORK > "$nmap_temp_file" 2> "$nmap_error_file"
    local nmap_exit_code=$?

    # Verificar si nmap se ejecutó correctamente
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

    # Mostrar información del archivo
    local file_size=$(du -h "$nmap_temp_file" | cut -f1)
    local total_lines=$(wc -l < "$nmap_temp_file")
    log_message "Resultados de nmap guardados ($file_size, $total_lines líneas). Procesando..."

    # Variables temporales para el procesamiento
    local current_ip=""
    local current_hostname=""
    local current_mac=""
    local current_line=0

    # Procesar el archivo temporal línea por línea
    while IFS= read -r line; do
        ((current_line++))

        # Mostrar progreso
        if [ $total_lines -gt 0 ]; then
            percentage=$(( (current_line * 100) / total_lines ))
            printf "\rProcesando línea %d/%d (%d%%)" "$current_line" "$total_lines" "$percentage"
        fi

        # Caso 1: Línea con "Nmap scan report for"
        if [[ $line == *"Nmap scan report for"* ]]; then
            # Procesar host anterior si existe
            if [ -n "$current_ip" ] && [ -n "$current_mac" ]; then
                process_host "$current_ip" "$current_mac" "$current_hostname"
            elif [ -n "$current_ip" ] && [ -z "$current_mac" ]; then
                # Host sin MAC, intentar obtenerla
                current_mac=$(get_mac_from_arp "$current_ip")
                if [ -n "$current_mac" ] && [ "$current_mac" != "Unknown" ]; then
                    process_host "$current_ip" "$current_mac" "$current_hostname"
                fi
            fi

            # Resetear variables para nuevo host
            current_ip=""
            current_hostname=""
            current_mac=""

            # Extraer IP y hostname de la línea
            if [[ $line =~ \(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\) ]]; then
                # Formato: hostname (ip)
                current_ip="${BASH_REMATCH[1]}"
                current_hostname=$(echo "$line" | awk '{for(i=5;i<=NF;i++) if ($i != "(") printf "%s ", $i; print ""}' | sed 's/ (*$//')
            else
                # Formato: ip o hostname solo
                local possible_ip=$(echo "$line" | awk '{print $5}')
                if [[ $possible_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    current_ip="$possible_ip"
                    current_hostname="unknown"
                else
                    current_hostname=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
                    current_ip=""
                fi
            fi

            # Si tenemos IP, verificar si debe ser excluida
            if [ -n "$current_ip" ] && should_exclude_ip "$current_ip"; then
                log_message "IP $current_ip excluida por filtro"
                current_ip=""
                current_hostname=""
            fi

        # Caso 2: Línea con MAC Address
        elif [[ $line == *"MAC Address:"* ]]; then
            current_mac=$(echo "$line" | awk '{print $3}')

            # Si no tenemos IP de la línea anterior, intentar extraerla
            if [ -z "$current_ip" ] && [[ $line =~ \([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\) ]]; then
                current_ip="${BASH_REMATCH[1]}"

                # Verificar si la IP debe ser excluida
                if [ -n "$current_ip" ] && should_exclude_ip "$current_ip"; then
                    log_message "IP $current_ip excluida por filtro"
                    current_ip=""
                    current_hostname=""
                    current_mac=""
                fi
            fi

        # Caso 3: Línea con "Host is up" (para hosts sin MAC)
        elif [[ $line == *"Host is up"* ]] && [ -n "$current_ip" ] && [ -z "$current_mac" ]; then
            # Esta línea indica que el host está activo pero no tenemos MAC
            # La MAC se intentará obtener via ARP después
            :
        fi

    done < "$nmap_temp_file"

    # Procesar último host si quedó pendiente
    if [ -n "$current_ip" ] && [ -n "$current_mac" ]; then
        process_host "$current_ip" "$current_mac" "$current_hostname"
    elif [ -n "$current_ip" ] && [ -z "$current_mac" ]; then
        # Último host sin MAC, intentar obtenerla
        current_mac=$(get_mac_from_arp "$current_ip")
        if [ -n "$current_mac" ] && [ "$current_mac" != "Unknown" ]; then
            process_host "$current_ip" "$current_mac" "$current_hostname"
        fi
    fi

    echo ""  # Nueva línea después de la barra de progreso

    # Limpiar archivos temporales
    rm -f "$nmap_temp_file" "$nmap_error_file"
    log_message "Archivo temporal eliminado: $nmap_temp_file"

    return 0
}
