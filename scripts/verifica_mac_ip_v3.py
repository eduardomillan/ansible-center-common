#!/usr/bin/env python3

# Verifica las IP según las MAC suministradas. Este proceso se realiza porque,
# en una red con servicio DHCP, es posible/probable que las IP asignadas a los
# equipos cambien con el tiempo.
#
# Se indica la red LAN en formato CIDR en una variable
#
# Ejecutar: python3 verificar_mac_ip.py archivo.txt [red]
#
# - donde archivo.txt es el archivo fuente con las MAC | IP | HOST originales
# - [red] es opcional: formato CIDR (ej: 192.168.1.0/24) o nombre predefinido
# - Crea un archivo de salida con el resultado de la verificación
#
# Usar red por defecto (macrolan)
# sudo python3 verificar_mac_ip.py equipos.txt
#
# Usar red predefinida por nombre
# sudo python3 verificar_mac_ip.py equipos.txt wifi_alu
#
# Usar red específica en formato CIDR
# sudo python3 verificar_mac_ip.py equipos.txt 192.168.1.0/24
#
# Ver ayuda
# python3 verificar_mac_ip.py
#

import subprocess
import json
import os
import re
import sys

# Fallback embebido por si no se encuentra inventories/available_networks.json
# ni su plantilla inventories/available_networks.sample.json
_REDES_FALLBACK = {
    'WIFI_ALU': '10.252.25.0/24',
    'WIFI_PROFES': '10.185.97.0/24',
    'MACROLAN': '172.28.222.0/24',
    'INFOR3': '10.113.44.64/26',
    'HOME': '192.168.0.0/24'
}
_RED_DEFAULT_FALLBACK = 'MACROLAN'


def _localizar_redes_disponibles():
    """Carga las redes predefinidas desde inventories/available_networks.json.

    Busca primero en $ANSIBLE_CENTER_PATH/inventories (variable de entorno
    que cada usuario apunta a su repo de datos, p.ej. ansible-center-boca)
    y, si no está definida o no contiene el fichero, en el inventories/
    del propio repo donde vive este script (ansible-center-common). Si no
    encuentra el fichero real, usa la plantilla available_networks.sample.json
    como respaldo y avisa; si no hay ninguno de los dos, usa un fallback
    embebido en el script.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidatos_dir = []

    center_path = os.environ.get('ANSIBLE_CENTER_PATH')
    if center_path:
        candidatos_dir.append(os.path.join(center_path, 'inventories'))

    candidatos_dir.append(os.path.normpath(os.path.join(script_dir, '..', 'inventories')))

    for directorio in candidatos_dir:
        for nombre_fichero in ('available_networks.json', 'available_networks.sample.json'):
            ruta = os.path.join(directorio, nombre_fichero)
            if not os.path.isfile(ruta):
                continue
            try:
                with open(ruta, 'r') as f:
                    datos = json.load(f)
                redes = {nombre.upper(): info['cidr'] for nombre, info in datos.get('networks', {}).items()}
                if not redes:
                    continue
                if nombre_fichero.endswith('.sample.json'):
                    print(f"⚠️  No se encontró available_networks.json; usando la plantilla de ejemplo ({ruta})", file=sys.stderr)
                default_red = str(datos.get('default', '')).upper()
                red_default = default_red if default_red in redes else next(iter(redes))
                return redes, red_default
            except (json.JSONDecodeError, OSError, KeyError, AttributeError) as e:
                print(f"⚠️  Error leyendo {ruta}: {e}", file=sys.stderr)

    print("⚠️  No se encontró available_networks.json ni available_networks.sample.json; usando redes por defecto embebidas en el script", file=sys.stderr)
    return dict(_REDES_FALLBACK), _RED_DEFAULT_FALLBACK


# Redes predefinidas
REDES_PREDEFINIDAS, _RED_DEFAULT_NOMBRE = _localizar_redes_disponibles()

# Red por defecto
NETWORK_DEFAULT = REDES_PREDEFINIDAS[_RED_DEFAULT_NOMBRE]

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

def obtener_red(parametro_red):
    """Obtiene la red a escanear basada en el parámetro proporcionado"""
    if not parametro_red:
        return NETWORK_DEFAULT
    
    # Si es un nombre predefinido, usar la red correspondiente
    if parametro_red.upper() in REDES_PREDEFINIDAS:
        return REDES_PREDEFINIDAS[parametro_red.upper()]
    
    # Verificar si es una red en formato CIDR válido
    if re.match(r'^\d+\.\d+\.\d+\.\d+/\d+$', parametro_red):
        return parametro_red
    
    # Si no es reconocido, mostrar error
    print(f"Error: Red no reconocida: {parametro_red}")
    print("Redes predefinidas disponibles:")
    for nombre, red in REDES_PREDEFINIDAS.items():
        print(f"  {nombre}: {red}")
    print("O especifique una red en formato CIDR (ej: 192.168.1.0/24)")
    sys.exit(1)

def escanear_red_completa(network):
    """Escanea toda la red una vez y devuelve un diccionario MAC->IP"""
    print(f"🔍 Escaneando red completa {network}...")
    mac_ip_map = {}

    try:
        resultado = subprocess.run(['nmap', '-sn', network],
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

def mostrar_ayuda():
    """Muestra la ayuda de uso"""
    print("Uso: python3 verificar_mac_ip.py archivo.txt [red]")
    print("\nArgumentos:")
    print("  archivo.txt  Archivo con MAC, IP y hosts (formato: MAC IP HOST)")
    print("  red          Opcional: Red a escanear")
    print("\nRedes predefinidas:")
    for nombre, red in REDES_PREDEFINIDAS.items():
        print(f"  {nombre:12} {red}")
    print("\nEjemplos:")
    print("  python3 verificar_mac_ip.py equipos.txt")
    print("  python3 verificar_mac_ip.py equipos.txt wifi_alu")
    print("  python3 verificar_mac_ip.py equipos.txt 192.168.1.0/24")
    print("  python3 verificar_mac_ip.py equipos.txt home")

def main():
    if verificar_sudo():
        print("✅ Permisos de sudo confirmados")
    else:
        print("Se necesitan permisos de sudo")
        sys.exit(1)

    # Procesar argumentos
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        mostrar_ayuda()
        sys.exit(1)

    archivo_entrada = sys.argv[1]
    
    # Obtener red (parámetro opcional)
    red_parametro = sys.argv[2] if len(sys.argv) == 3 else None
    network = obtener_red(red_parametro)
    
    print(f"🌐 Usando red: {network}")

    archivo_salida = archivo_entrada.replace('.txt', '_result.txt')

    print("📖 Leyendo archivo de configuración...")
    equipos = procesar_archivo(archivo_entrada)

    # Escanear la red UNA SOLA VEZ
    mac_ip_map = escanear_red_completa(network)
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
        f.write(f"RED ESCANEADA: {network}\n\n")

        f.write("RESULTADOS DETALLADOS:\n")
        f.write("----------------------\n")
        for resultado in resultados:
            f.write(resultado + '\n')

        f.write(f"\nRESUMEN:\n")
        f.write(f"--------\n")
        f.write(f"Red escaneada: {network}\n")
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
    print(f"   Red escaneada: {network}")
    print(f"   IPs correctas: {stats['correctas']}")
    print(f"   IPs incorrectas: {stats['incorrectas']}")
    print(f"   Equipos no encontrados: {stats['no_encontradas']}")
    print(f"   Archivo regenerado incluido en el reporte")

if __name__ == "__main__":
    main()
