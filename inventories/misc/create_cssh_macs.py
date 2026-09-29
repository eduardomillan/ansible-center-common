#!/usr/bin/env python3
"""
Script para convertir archivo de MACs a formato CSSH
Uso: python macs_to_cssh.py archivo_macs.txt [nombre_grupo]
"""

import sys
import re

def macs_to_cssh(macs_file, group_name="grupo"):
    """
    Convierte archivo de MACs a formato CSSH
    
    Args:
        macs_file (str): Ruta al archivo de MACs
        group_name (str): Nombre base para los grupos CSSH
    
    Returns:
        str: Contenido del archivo CSSH generado
    """
    try:
        with open(macs_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: No se pudo encontrar el archivo {macs_file}")
        return None
    except Exception as e:
        print(f"Error al leer el archivo: {e}")
        return None
    
    # Procesar las líneas
    hosts = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#') or 'DOWN' in line:
            continue
            
        # Extraer MAC, IP y nombre
        parts = line.split()
        if len(parts) >= 3:
            mac = parts[0]
            ip = parts[1]
            name = parts[2]
            
            # Limpiar el nombre (remover caracteres no válidos)
            clean_name = re.sub(r'[^a-zA-Z0-9_-]', '', name)
            if clean_name:
                hosts.append((clean_name, ip))
    
    if not hosts:
        print("No se encontraron hosts válidos en el archivo")
        return None
    
    # Generar contenido CSSH
    cssh_content = "# Archivo CSSH generado automáticamente desde MACs\n"
    cssh_content += f"# Ejemplo de uso: cssh -c archivo_cssh.txt {group_name} -l usuario\n\n"
    
    # Agrupar por prefijo de IP (primeros tres octetos)
    ip_groups = {}
    for name, ip in hosts:
        ip_parts = ip.split('.')
        prefix = '.'.join(ip_parts[:3])
        if prefix not in ip_groups:
            ip_groups[prefix] = []
        ip_groups[prefix].append((name, ip))
    
    # Generar grupos CSSH
    for prefix, host_list in ip_groups.items():
        # Usar el nombre del grupo proporcionado o generar uno automático
        if len(ip_groups) == 1:
            # Si solo hay un grupo, usar el nombre proporcionado
            current_group_name = group_name
        else:
            # Si hay múltiples grupos, añadir sufijo con el prefijo IP
            current_group_name = f"{group_name}_{prefix.replace('.', '_')}"
        
        ips = [ip for _, ip in host_list]
        host_names = [name for name, _ in host_list]
        
        cssh_content += f"# {current_group_name}: {', '.join(host_names)}\n"
        
        # Formato compacto si las IPs son consecutivas
        if len(ips) > 1:
            # Verificar si son IPs consecutivas en el último octeto
            last_octets = [int(ip.split('.')[-1]) for ip in ips]
            last_octets.sort()
            
            # Verificar si todos los últimos octetos son consecutivos
            is_consecutive = all(last_octets[i] + 1 == last_octets[i + 1] 
                               for i in range(len(last_octets) - 1))
            
            if is_consecutive:
                # IPs consecutivas, usar formato compacto
                base_ip = '.'.join(ips[0].split('.')[:3])
                range_str = f"{{{last_octets[0]}..{last_octets[-1]}}}"
                cssh_content += f"{current_group_name} {base_ip}.{range_str}\n"
            else:
                # IPs no consecutivas, listar individualmente
                cssh_content += f"{current_group_name} {','.join(ips)}\n"
        else:
            # Solo un host
            cssh_content += f"{current_group_name} {ips[0]}\n"
        
        cssh_content += "\n"
    
    return cssh_content

def main():
    if len(sys.argv) < 2:
        print("Uso: python macs_to_cssh.py archivo_macs.txt [nombre_grupo]")
        print("Ejemplo: python macs_to_cssh.py macs_1fpb_alu.txt")
        print("Ejemplo: python macs_to_cssh.py macs_1fpb_alu.txt biblioteca")
        sys.exit(1)
    
    macs_file = sys.argv[1]
    group_name = sys.argv[2] if len(sys.argv) >= 3 else "grupo"
    
    # Validar nombre del grupo (solo letras, números y guiones)
    if not re.match(r'^[a-zA-Z0-9_-]+$', group_name):
        print("Error: El nombre del grupo solo puede contener letras, números, guiones y guiones bajos")
        sys.exit(1)
    
    cssh_content = macs_to_cssh(macs_file, group_name)
    
    if cssh_content:
        # Generar nombre de archivo de salida
        base_name = macs_file.replace('.txt', '')
        output_file = f"cssh_{base_name}_generated.txt"
        
        # Guardar archivo
        try:
            with open(output_file, 'w') as f:
                f.write(cssh_content)
            print(f"Archivo CSSH generado: {output_file}")
            
            # Mostrar contenido en pantalla
            print("\nContenido del archivo generado:")
            print("=" * 50)
            print(cssh_content)
            
        except Exception as e:
            print(f"Error al guardar el archivo: {e}")
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
