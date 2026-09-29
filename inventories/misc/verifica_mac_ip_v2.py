#!/usr/bin/env python3

# Verifica las IP según las MAC suministradas. Este proceso se realiza porque,
# en una red con servicio DHCP, es posible/probable que las IP asignadas a los
# equipos cambien con el tiempo.
#
# Se indica la red LAN en formato CIDR en una variable
#
# Ejecutar: python3 verificar_mac_ip.py archivo.txt
#
# - donde archivo.txt es el archivo fuente con las MAC | IP | HOST originales
# - Crea un archivo de salida con el resultado de la verificación

import subprocess
import re
import sys

NETWORK_WIFI_ALU="10.252.25.0/24"
NETWORK_WIFI_PROFES="10.185.97.0/24"
NETWORK_MACROLAN="172.28.222.0/24"
NETWORK_HOME="192.168.0.0/24"

NETWORK=NETWORK_MACROLAN

def verificar_sudo():
    """Verifica permisos de sudo y sale si no los tiene"""
    try:
        subprocess.run(['sudo', '-n', 'true'],
                      check=True,
                      stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: Se necesitan permisos de sudo para ejecutar este script")
        print("Ejecuta con: sudo python3 script.py")
        sys.exit(1)

def escanear_red_completa():
    """Escanea toda la red una vez y devuelve un diccionario MAC->IP"""
    print(f"🔍 Escaneando red completa {NETWORK}...")
    mac_ip_map = {}

    try:
        resultado = subprocess.run(['nmap', '-sn', NETWORK],
                                 capture_output=True, text=True, timeout=120)

        lineas = resultado.stdout.split('\n')
        ip_actual = ""

        for linea in lineas:
            if 'Nmap scan report' in linea:
                ip_match = re.search(r'(\d+\.\d+\.\d+\.\d+)', linea)
                if ip_match:
                    ip_actual = ip_match.group(1)
            elif 'MAC Address:' in linea:
                mac_match = re.search(r'(([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2})', linea)
                if mac_match and ip_actual:
                    mac_actual = mac_match.group(1).upper()
                    mac_ip_map[mac_actual] = ip_actual
                    ip_actual = ""

        return mac_ip_map

    except Exception as e:
        print(f"Error escaneando red: {e}")
        return {}

def procesar_archivo(archivo_entrada):
    """Lee el archivo con MAC, IP y hosts"""
    equipos = []
    with open(archivo_entrada, 'r') as f:
        for linea in f:
            linea = linea.strip()
            if linea:
                partes = linea.split()
                if len(partes) >= 2:
                    mac = partes[0].upper()
                    ip_esperada = partes[1]
                    host = partes[2] if len(partes) >= 3 else ""
                    equipos.append({'mac': mac, 'ip_esperada': ip_esperada, 'host': host})
    return equipos

def main():
    if verificar_sudo():
        print("✅ Permisos de sudo confirmados")
    else:
        print("Se necesitan permisos de sudo")
        sys.exit(1)

    if len(sys.argv) != 2:
        print("Uso: python3 verificar_mac_ip.py archivo.txt")
        sys.exit(1)

    archivo_entrada = sys.argv[1]
    archivo_salida = archivo_entrada.replace('.txt', '_result.txt')

    print("📖 Leyendo archivo de configuración...")
    equipos = procesar_archivo(archivo_entrada)

    # Escanear la red UNA SOLA VEZ
    mac_ip_map = escanear_red_completa()
    print(f"✅ Encontradas {len(mac_ip_map)} direcciones MAC en la red")

    resultados = []
    stats = {'correctas': 0, 'incorrectas': 0, 'no_encontradas': 0}

    print("📊 Procesando resultados...")
    for i, equipo in enumerate(equipos, 1):
        mac = equipo['mac']
        ip_esperada = equipo['ip_esperada']
        host = equipo['host']

        # Buscar la IP en el mapa ya creado
        ip_actual = mac_ip_map.get(mac)

        if ip_actual:
            if ip_actual == ip_esperada:
                resultado = f"✅ {mac} -> {ip_actual} {host} (IP CORRECTA)"
                stats['correctas'] += 1
            else:
                resultado = f"⚠️  {mac} -> {ip_actual} {host} (IP ESPERADA: {ip_esperada})"
                stats['incorrectas'] += 1
        else:
            resultado = f"❌ {mac} -> {ip_esperada} {host} (NO ENCONTRADO)"
            stats['no_encontradas'] += 1

        resultados.append(resultado)
        print(f"   Procesado {i}/{len(equipos)}: {mac} {host}")

    # Escribir resultados
    with open(archivo_salida, 'w') as f:
        f.write("VERIFICACIÓN IP POR MAC\n")
        f.write("=======================\n\n")

        f.write("RESULTADOS DETALLADOS:\n")
        f.write("----------------------\n")
        for resultado in resultados:
            f.write(resultado + '\n')

        f.write(f"\nRESUMEN:\n")
        f.write(f"--------\n")
        f.write(f"IPs correctas: {stats['correctas']}\n")
        f.write(f"IPs incorrectas: {stats['incorrectas']}\n")
        f.write(f"Equipos no encontrados: {stats['no_encontradas']}\n")
        f.write(f"Total verificados: {len(equipos)}\n")

        # Añadir archivo regenerado al final del reporte
        f.write(f"\nDATOS ACTUALIZADOS (MAC | IP_ACTUAL | HOST):\n")
        f.write(f"---------------------------------------------\n")
        for equipo in equipos:
            mac = equipo['mac']
            host = equipo['host']
            # Usar el mapa ya creado para obtener la IP actual
            ip_actual = mac_ip_map.get(mac)
            # Si no se encontró la IP, mantener la IP esperada original
            ip_final = ip_actual if ip_actual else equipo['ip_esperada']
            f.write(f"{mac} {ip_final} {host}\n")

    print(f"\n✅ Resultados guardados en: {archivo_salida}")
    print(f"\n📊 Resumen:")
    print(f"   IPs correctas: {stats['correctas']}")
    print(f"   IPs incorrectas: {stats['incorrectas']}")
    print(f"   Equipos no encontrados: {stats['no_encontradas']}")
    print(f"   Archivo regenerado incluido en el reporte")

if __name__ == "__main__":
    main()
