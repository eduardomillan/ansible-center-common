#!/usr/bin/env python3

# Script python que crea el inventory para Ansible a partir de las MAC suministradas en un archivo
#
# Cómo usar: sudo python3 createinv_macs.py macs.txt
#
# (Necesario ejecutar con sudo porque usa nmap...)
# Genera el archivo: INVENTORY_FILE (inventory_generated.ini)

# Usar con Ansible
# ansible-playbook -i inventory_mac.py macs.txt mi_playbook.yml --ask-become-pass

# Características:
# ✅ Lee MACs desde archivo (una por línea)
# ✅ Ignora comentarios (líneas que empiezan con #)
# ✅ Acepta formato: MAC, MAC IP o MAC IP Host
# ✅ Valida formato de MAC
# ✅ Genera inventory JSON para Ansible
# ✅ Muestra estadísticas de búsqueda

import subprocess
import json
import sys
import os

NETWORK_WIFI_ALU="10.252.25.0/24"
NETWORK_WIFI_PROFES="10.185.97.0/24"
NETWORK_MACROLAN="172.28.222.0/24"
NETWORK_HOME="192.168.0.0/24"

# Diccionario para mapear sufijos de red a sus valores
REDES_DISPONIBLES = {
    'WIFI_ALU': NETWORK_WIFI_ALU,
    'WIFI_PROFES': NETWORK_WIFI_PROFES,
    'MACROLAN': NETWORK_MACROLAN,
    'HOME': NETWORK_HOME
}

# Red por defecto
NETWORK=NETWORK_MACROLAN

ADMIN = "me.millan"
INVENTORY_FILE = "inventory_generated.ini"

def verificar_sudo():
    """Verifica si tenemos permisos de sudo"""
    try:
        subprocess.run(['sudo', '-n', 'true'],
                      check=True,
                      stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL,
                      timeout=10)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return False

def cargar_macs_desde_archivo(archivo_macs):
    """Carga las MAC addresses desde un archivo, incluyendo hostnames si existen"""
    equipos = []
    try:
        with open(archivo_macs, 'r') as f:
            for linea_num, linea in enumerate(f, 1):
                linea = linea.strip()
                if linea and not linea.startswith('#'):
                    partes = linea.split()
                    if partes:
                        mac = partes[0].strip().upper()
                        if len(mac) == 17 and ':' in mac:
                            # Extraer IP si existe (segunda columna)
                            ip_original = partes[1] if len(partes) > 1 else ""
                            # Extraer hostname si existe (tercera columna o más)
                            hostname = partes[2] if len(partes) > 2 else f"equipo-{mac.replace(':', '-').lower()}"
                            equipos.append({
                                'mac': mac,
                                'ip_original': ip_original,
                                'host_name': hostname
                            })
                        else:
                            print(f"Advertencia: Formato MAC inválido en línea {linea_num}: {linea}", file=sys.stderr)
    except FileNotFoundError:
        print(f"Error: Archivo {archivo_macs} no encontrado", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error leyendo archivo: {e}", file=sys.stderr)
        sys.exit(1)

    return equipos

def obtener_ips_por_mac(macs_buscar):
    """Obtiene las IPs correspondientes a las MACs buscadas usando sudo"""
    mac_ip_map = {}
    try:
        # Escanear red con sudo - CORREGIDA LA RED
        print(f"🔍 Escaneando red {NETWORK} con nmap...", file=sys.stderr)
        result = subprocess.run(
            ['sudo', 'nmap', '-sn', NETWORK],
            capture_output=True,
            text=True,
            timeout=300,
            check=True
        )
        output = result.stdout

        lines = output.split('\n')
        current_ip = ""

        for line in lines:
            if 'Nmap scan report' in line:
                ip_match = None
                if '(' in line and ')' in line:
                    ip_match = line.split('(')[1].split(')')[0]
                else:
                    parts = line.split()
                    ip_match = parts[-1] if parts else ""

                if ip_match and all(part.isdigit() for part in ip_match.split('.')):
                    current_ip = ip_match

            elif 'MAC Address:' in line and current_ip:
                mac_part = line.split('MAC Address:')[1].strip()
                mac_actual = mac_part.split()[0].upper()

                if mac_actual in macs_buscar:
                    mac_ip_map[mac_actual] = current_ip

                current_ip = ""

    except subprocess.CalledProcessError as e:
        print(f"Error ejecutando nmap: {e}", file=sys.stderr)
        if "root" in e.stderr or "sudo" in e.stderr:
            print("❌ Se necesitan permisos de sudo para ejecutar nmap", file=sys.stderr)
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("❌ Timeout escaneando la red", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error inesperado: {e}", file=sys.stderr)
        sys.exit(1)

    return mac_ip_map

def main():
    # Procesar parámetros de línea de comandos
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("Uso: python3 inventory_mac.py archivo_macs.txt [red]", file=sys.stderr)
        print("Redes disponibles: " + ", ".join(REDES_DISPONIBLES.keys()), file=sys.stderr)
        sys.exit(1)

    archivo_macs = sys.argv[1]


    # Procesar segundo parámetro (red) si existe
    if len(sys.argv) == 3:
        red_solicitada = sys.argv[2].upper()
        if red_solicitada in REDES_DISPONIBLES:
            global NETWORK
            NETWORK = REDES_DISPONIBLES[red_solicitada]
            print(f"🌐 Usando red: {red_solicitada} ({NETWORK})", file=sys.stderr)
        else:
            print(f"❌ Error: Red '{sys.argv[2]}' no válida", file=sys.stderr)
            print(f"💡 Redes disponibles: {', '.join(REDES_DISPONIBLES.keys())}", file=sys.stderr)
            sys.exit(1)

    # Verificar permisos de sudo primero
    if not verificar_sudo():
        print("❌ Este script requiere permisos de sudo para ejecutar nmap", file=sys.stderr)
        print("💡 Ejecuta con: sudo python3 inventory_mac.py archivo_macs.txt [red]", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(archivo_macs):
        print(f"Error: Archivo {archivo_macs} no encontrado", file=sys.stderr)
        sys.exit(1)

    # Cargar equipos desde archivo (incluyendo hostnames)
    equipos = cargar_macs_desde_archivo(archivo_macs)

    if not equipos:
        print("Error: No se encontraron MACs válidas en el archivo", file=sys.stderr)
        sys.exit(1)

    # Crear lista de MACs para buscar
    macs_buscar = [equipo['mac'] for equipo in equipos]

    print(f"🔍 Buscando {len(equipos)} equipos en la red {NETWORK}...", file=sys.stderr)

    # Obtener IPs (ahora con sudo)
    mac_ip_map = obtener_ips_por_mac(macs_buscar)

    # Generar inventory INI con información completa incluyendo MAC como variable
    with open(INVENTORY_FILE, 'w') as f:
        f.write('[devices]\n')

        encontradas = 0
        for equipo in equipos:
            mac = equipo['mac']
            host_name = equipo['host_name']

            if mac in mac_ip_map:
                ip = mac_ip_map[mac]
                # Escribir línea con IP y variables incluyendo MAC y host_name
                f.write(f'{ip} mac_address={mac} host_name={host_name}\n')
                encontradas += 1
                print(f"✅ Encontrado: {mac} -> {ip} ({host_name})", file=sys.stderr)
            else:
                # Si no se encuentra, incluir con IP original si existe
                ip_original = equipo['ip_original']
                if ip_original and all(part.isdigit() for part in ip_original.split('.')):
                    f.write(f'{ip_original} mac_address={mac} host_name={host_name} estado=no_encontrado\n')
                else:
                    # Si no hay IP, comentar la línea pero incluir las variables para referencia
                    f.write(f'# {host_name} mac_address={mac} host_name={host_name} [NO ENCONTRADO EN RED]\n')
                print(f"❌ No encontrado: {mac} ({host_name})", file=sys.stderr)

        f.write('\n[devices:vars]\n')
        f.write(f'ansible_user={ADMIN}\n')
        f.write('ansible_become=yes\n')
        f.write('ansible_connection=ssh\n')

    print(f"📊 Resultado: {encontradas}/{len(equipos)} equipos encontrados en la red", file=sys.stderr)
    print(f"💾 Inventory guardado en: {INVENTORY_FILE}", file=sys.stderr)

if __name__ == "__main__":
    main()
