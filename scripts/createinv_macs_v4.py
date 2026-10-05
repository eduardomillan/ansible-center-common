#!/usr/bin/env python3

# Script python que crea el inventory para Ansible a partir de las MAC suministradas en un archivo
#
# Cómo usar: sudo python3 createinv_macs.py macs.txt [red]
#
# (Necesario ejecutar con sudo porque usa nmap...)
# Genera inventory_<RED>_generated.ini (p. ej. inventory_MACROLAN_generated.ini),
# dentro de inventories/: en $ANSIBLE_CENTER_PATH/inventories/ si esa variable
# está definida, o en inventories/ del directorio actual en caso contrario
# (se crea el directorio si no existe).

# Usar con Ansible
# ansible-playbook -i inventory_mac.py macs.txt mi_playbook.yml --ask-become-pass

# Características:
# ✅ Lee MACs desde archivo (una por línea)
# ✅ Ignora comentarios (líneas que empiezan con #)
# ✅ Acepta formato: MAC, MAC IP o MAC IP Host
# ✅ Valida formato de MAC
# ✅ Genera inventory INI para Ansible
# ✅ Muestra estadísticas de búsqueda
# ✅ Usa hostname como identificador principal
# ✅ IP como variable ansible_host
# ✅ Permite especificar cualquier red como parámetro opcional
#
#
# Usar red por defecto (MACROLAN)
# sudo python3 createinv_macs_v3.py macs.txt
#
# Usar redes predefinidas
# sudo python3 createinv_macs_v3.py macs.txt WIFI_ALU
# sudo python3 createinv_macs_v3.py macs.txt HOME
#
# Usar cualquier red en formato CIDR
# sudo python3 createinv_macs_v3.py macs.txt 192.168.1.0/24
# sudo python3 createinv_macs_v3.py macs.txt 10.252.25.0/24
# sudo python3 createinv_macs_v3.py macs.txt 172.16.0.0/16
# sudo python3 createinv_macs_v3.py macs.txt 10.0.0.0/8
#
# Ver ayuda
# python3 createinv_macs_v3.py
#

import subprocess
import json
import sys
import os
import re
import stat

# Fallback embebido por si no se encuentra inventories/available_networks.json
# ni su plantilla inventories/available_networks.sample.json
_REDES_FALLBACK = {
    'WIFI_ALU': '10.252.25.0/24',
    'WIFI_PROFES': '10.185.97.0/24',
    'MACROLAN': '172.28.222.0/24',
    'HOME': '192.168.0.0/24'
}
_RED_DEFAULT_FALLBACK = 'MACROLAN'


def _rutas_candidatas_inventories():
    """Directorios inventories/ donde buscar datos del centro (redes, MACs...).

    Primero el de $ANSIBLE_CENTER_PATH (variable de entorno que cada usuario
    apunta a su repo de datos, p.ej. ansible-center-boca) y después el del
    propio repo donde vive este script (ansible-center-common).
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidatos_dir = []

    center_path = os.environ.get('ANSIBLE_CENTER_PATH')
    if center_path:
        candidatos_dir.append(os.path.join(center_path, 'inventories'))

    candidatos_dir.append(os.path.normpath(os.path.join(script_dir, '..', 'inventories')))
    return candidatos_dir


def _aviso_sudo_sin_preservar_entorno():
    """Si el proceso corre bajo sudo y no ve ANSIBLE_CENTER_PATH, puede ser
    porque 'sudo' limpia el entorno por defecto (no porque la variable no
    esté definida en tu shell). Devuelve una pista para el usuario, o
    cadena vacía si no aplica."""
    if os.environ.get('SUDO_USER') and not os.environ.get('ANSIBLE_CENTER_PATH'):
        return (f"\n💡 Si tienes ANSIBLE_CENTER_PATH definida en tu shell, recuerda que "
                f"'sudo' no la conserva por defecto; usa 'sudo -E' para propagarla, "
                f"p. ej.: sudo -E {os.path.basename(sys.argv[0])} ...")
    return ""


def _resolver_ruta_datos(nombre_archivo):
    """Localiza un fichero de datos (MACs, inventarios...) dado por el usuario.

    Si `nombre_archivo` existe tal cual (ruta relativa al directorio actual
    o absoluta), se usa sin modificar. Si no, se busca su nombre base dentro
    de cada inventories/ candidato (ver _rutas_candidatas_inventories), para
    poder invocar el script con solo el nombre del fichero aunque los datos
    vivan en otro repo (p. ej. ansible-center-boca vía $ANSIBLE_CENTER_PATH).
    Devuelve la ruta encontrada, o None si no se encuentra en ningún sitio.
    """
    if os.path.isfile(nombre_archivo):
        return nombre_archivo

    nombre_base = os.path.basename(nombre_archivo)
    for directorio in _rutas_candidatas_inventories():
        ruta = os.path.join(directorio, nombre_base)
        if os.path.isfile(ruta):
            return ruta

    return None


def _localizar_redes_disponibles():
    """Carga las redes predefinidas desde inventories/available_networks.json.

    Busca en los directorios de _rutas_candidatas_inventories() (primero
    $ANSIBLE_CENTER_PATH/inventories, luego el inventories/ del propio
    repo). No se usa available_networks.sample.json como fuente real: es
    solo una plantilla de ejemplo para copiar y adaptar. Si no se encuentra
    el fichero real en ninguno de los dos sitios, usa un fallback embebido
    en el script.
    """
    for directorio in _rutas_candidatas_inventories():
        ruta = os.path.join(directorio, 'available_networks.json')
        if not os.path.isfile(ruta):
            continue
        try:
            with open(ruta, 'r') as f:
                datos = json.load(f)
            redes = {nombre.upper(): info['cidr'] for nombre, info in datos.get('networks', {}).items()}
            if not redes:
                continue
            default_red = str(datos.get('default', '')).upper()
            red_default = default_red if default_red in redes else next(iter(redes))
            return redes, red_default
        except (json.JSONDecodeError, OSError, KeyError, AttributeError) as e:
            print(f"⚠️  Error leyendo {ruta}: {e}", file=sys.stderr)

    print(f"⚠️  No se encontró available_networks.json (ni en $ANSIBLE_CENTER_PATH/inventories ni en el repo); usando redes por defecto embebidas en el script{_aviso_sudo_sin_preservar_entorno()}", file=sys.stderr)
    return dict(_REDES_FALLBACK), _RED_DEFAULT_FALLBACK


# Diccionario para mapear nombres de red a sus valores CIDR
REDES_DISPONIBLES, _RED_DEFAULT_NOMBRE = _localizar_redes_disponibles()

# Red por defecto
NETWORK = REDES_DISPONIBLES[_RED_DEFAULT_NOMBRE]

ADMIN = "me.millan"


def _determinar_directorio_salida():
    """Directorio donde guardar el inventory generado.

    $ANSIBLE_CENTER_PATH/inventories si esa variable está definida, o
    inventories/ del directorio actual en caso contrario. Se crea si no
    existe (mismo criterio que scripts/obtener_macs_ip_red.sh).
    """
    center_path = os.environ.get('ANSIBLE_CENTER_PATH')
    directorio = os.path.join(center_path.rstrip('/'), 'inventories') if center_path else 'inventories'
    os.makedirs(directorio, exist_ok=True)
    return directorio

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

def obtener_permisos_archivo(ruta_archivo):
    """Obtiene los permisos del archivo de origen"""
    try:
        stat_info = os.stat(ruta_archivo)
        return stat.S_IMODE(stat_info.st_mode)
    except Exception:
        # Si hay error, usar permisos por defecto (644)
        return 0o777


def aplicar_permisos_archivo(ruta_archivo, permisos):
    """Aplica los permisos especificados al archivo"""
    try:
        os.chmod(ruta_archivo, permisos)
    except Exception as e:
        print(f"Advertencia: No se pudieron aplicar permisos al archivo: {e}", file=sys.stderr)


def validar_formato_red(red):
    """Valida que la red tenga formato CIDR válido"""
    patron_cidr = r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$'
    if not re.match(patron_cidr, red):
        return False

    # Validar partes de la IP
    partes_ip = red.split('/')[0].split('.')
    for parte in partes_ip:
        if not 0 <= int(parte) <= 255:
            return False

    # Validar máscara
    mascara = int(red.split('/')[1])
    if not 0 <= mascara <= 32:
        return False

    return True

def obtener_red(parametro_red):
    """Obtiene (cidr, etiqueta) de la red a escanear según el parámetro dado.

    La etiqueta se usa para nombrar el fichero de salida (inventory_<etiqueta>_generated.ini):
    el nombre de red predefinido, o el propio CIDR con '/' sustituido por '-'
    si se indicó directamente.
    """
    if not parametro_red:
        return NETWORK, _RED_DEFAULT_NOMBRE

    # Si es un nombre predefinido, usar la red correspondiente
    if parametro_red.upper() in REDES_DISPONIBLES:
        nombre = parametro_red.upper()
        return REDES_DISPONIBLES[nombre], nombre

    # Verificar si es una red en formato CIDR válido
    if validar_formato_red(parametro_red):
        return parametro_red, parametro_red.replace('/', '-')

    # Si no es reconocido, mostrar error
    print(f"❌ Error: Formato de red no válido: {parametro_red}", file=sys.stderr)
    print("💡 Formatos aceptados:", file=sys.stderr)
    print("   - Nombres predefinidos: " + ", ".join(REDES_DISPONIBLES.keys()), file=sys.stderr)
    print("   - Formato CIDR: 192.168.1.0/24, 10.0.0.0/16, etc.", file=sys.stderr)
    sys.exit(1)

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

def obtener_ips_por_mac(macs_buscar, network):
    """Obtiene las IPs correspondientes a las MACs buscadas usando sudo"""
    mac_ip_map = {}
    try:
        # Escanear red con sudo
        print(f"🔍 Escaneando red {network} con nmap...", file=sys.stderr)
        result = subprocess.run(
            ['sudo', 'nmap', '-sn', network],
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

def mostrar_ayuda():
    """Muestra la ayuda de uso"""
    print("Uso: python3 createinv_macs.py archivo_macs.txt [red]", file=sys.stderr)
    print("\nArgumentos:", file=sys.stderr)
    print("  archivo_macs.txt  Archivo con direcciones MAC (formato: MAC [IP] [hostname])", file=sys.stderr)
    print("  red               Opcional: Red a escanear (nombre predefinido o formato CIDR)", file=sys.stderr)
    print("\nRedes predefinidas:", file=sys.stderr)
    for nombre, red in REDES_DISPONIBLES.items():
        print(f"  {nombre:12} {red}", file=sys.stderr)
    print("\nEjemplos:", file=sys.stderr)
    print("  sudo python3 createinv_macs.py macs.txt", file=sys.stderr)
    print("  sudo python3 createinv_macs.py macs.txt WIFI_ALU", file=sys.stderr)
    print("  sudo python3 createinv_macs.py macs.txt 192.168.1.0/24", file=sys.stderr)
    print("  sudo python3 createinv_macs.py macs.txt 10.0.0.0/16", file=sys.stderr)

def main():
    # Procesar parámetros de línea de comandos
    if len(sys.argv) < 2:
        mostrar_ayuda()
        sys.exit(1)

    archivo_macs_arg = sys.argv[1]

    # Determinar qué red usar
    red_parametro = sys.argv[2] if len(sys.argv) >= 3 else None
    network, red_etiqueta = obtener_red(red_parametro)

    if red_parametro:
        print(f"🌐 Usando red especificada: {network}", file=sys.stderr)
    else:
        print(f"🌐 Usando red por defecto: {network}", file=sys.stderr)

    # Verificar permisos de sudo primero
    if not verificar_sudo():
        print("❌ Este script requiere permisos de sudo para ejecutar nmap", file=sys.stderr)
        print("💡 Ejecuta con: sudo python3 createinv_macs.py archivo_macs.txt [red]", file=sys.stderr)
        sys.exit(1)

    archivo_macs = _resolver_ruta_datos(archivo_macs_arg)
    if archivo_macs is None:
        print(f"Error: Archivo {archivo_macs_arg} no encontrado (ni en el directorio actual ni en inventories/ de $ANSIBLE_CENTER_PATH o del repo){_aviso_sudo_sin_preservar_entorno()}", file=sys.stderr)
        sys.exit(1)
    if archivo_macs != archivo_macs_arg:
        print(f"📂 Usando {archivo_macs} (resuelto vía inventories/)", file=sys.stderr)

    # Obtener permisos del archivo de MACs original
    permisos_originales = obtener_permisos_archivo(archivo_macs)
    print(f"Permisos originales del {archivo_macs}: {permisos_originales}", file=sys.stderr)

    # Cargar equipos desde archivo (incluyendo hostnames)
    equipos = cargar_macs_desde_archivo(archivo_macs)

    if not equipos:
        print("Error: No se encontraron MACs válidas en el archivo", file=sys.stderr)
        sys.exit(1)

    # Crear lista de MACs para buscar
    macs_buscar = [equipo['mac'] for equipo in equipos]

    print(f"🔍 Buscando {len(equipos)} equipos en la red {network}...", file=sys.stderr)

    # Obtener IPs (ahora con sudo) - pasando la red como parámetro
    mac_ip_map = obtener_ips_por_mac(macs_buscar, network)

    dir_salida = _determinar_directorio_salida()
    inventory_file = os.path.join(dir_salida, f"inventory_{red_etiqueta}_generated.ini")
    print(f"💾 Guardando en {inventory_file}", file=sys.stderr)

    # Generar inventory INI con hostname como identificador principal
    with open(inventory_file, 'w') as f:
        f.write('# Inventory generado automáticamente\n')
        f.write(f'# Red escaneada: {network}\n')
        f.write(f'# Archivo fuente: {archivo_macs}\n\n')

        f.write('[devices]\n')

        encontradas = 0
        for equipo in equipos:
            mac = equipo['mac']
            host_name = equipo['host_name']

            if mac in mac_ip_map:
                ip = mac_ip_map[mac]
                # Escribir línea con HOSTNAME como identificador principal
                f.write(f'{host_name} ansible_host={ip} mac_address={mac} host_name={host_name}\n')
                encontradas += 1
                print(f"✅ Encontrado: {mac} -> {host_name} ({ip})", file=sys.stderr)
            else:
                # Si no se encuentra, incluir con IP original si existe
                ip_original = equipo['ip_original']
                if ip_original and all(part.isdigit() for part in ip_original.split('.')):
                    f.write(f'{host_name} ansible_host={ip_original} mac_address={mac} host_name={host_name} estado=no_encontrado\n')
                    print(f"⚠️  Usando IP original: {mac} -> {host_name} ({ip_original}) [NO ENCONTRADO EN ESCANEO]", file=sys.stderr)
                else:
                    # Si no hay IP, comentar la línea pero incluir las variables para referencia
                    f.write(f'#{host_name} ansible_host=desconocido mac_address={mac} host_name={host_name} estado=no_encontrado\n')
                    print(f"❌ No encontrado: {mac} ({host_name})", file=sys.stderr)

        f.write('\n[devices:vars]\n')
        f.write(f'ansible_user={ADMIN}\n')
        f.write('ansible_become=yes\n')
        f.write('ansible_connection=ssh\n')

    # Aplicar los mismos permisos al archivo generado
    aplicar_permisos_archivo(inventory_file, permisos_originales)

    print(f"📊 Resultado: {encontradas}/{len(equipos)} equipos encontrados en la red", file=sys.stderr)
    print(f"💾 Inventory guardado en: {inventory_file}", file=sys.stderr)
    print(f"🎯 Identificadores principales: hostnames (ej: {equipos[0]['host_name']})", file=sys.stderr)


if __name__ == "__main__":
    main()
