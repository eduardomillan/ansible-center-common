# SCRIPTS_HOWTO.md - Guía de Scripts

Documentación breve de los scripts auxiliares de `scripts/`. Son utilidades independientes de Ansible usadas para generar inventarios, convertir formatos y verificar/mantener la correspondencia MAC↔IP de los equipos del centro.

> Nota: este directorio contenía anteriormente varias versiones sucesivas de cada script (`v1`, `v2`, `v3`...). Se han eliminado las versiones obsoletas, quedando solo la más completa y perfeccionada de cada familia.

> **Redes predefinidas**: `createinv_macs_v4.py` y `verifica_mac_ip_v3.py` ya no llevan las redes hardcodeadas; las leen de `inventories/available_networks.json`. Orden de búsqueda:
> 1. `$ANSIBLE_CENTER_PATH/inventories/available_networks.json`, si tienes definida la variable de entorno `ANSIBLE_CENTER_PATH` apuntando a tu repo de datos privado (p. ej. `ansible-center-boca`) — ver detalles y cómo configurarla en el `README.md` del repo (sección "Variable de entorno `ANSIBLE_CENTER_PATH`").
> 2. `inventories/available_networks.json` del propio repo donde vive el script (`ansible-center-common`), si no has definido la variable.
> 3. `inventories/available_networks.sample.json` (plantilla) en ese mismo repo, avisando por `stderr`.
> 4. Un pequeño fallback embebido en el script, como último recurso.

Los scripts están ordenados a continuación según el orden lógico en que se usan habitualmente (ver [Uso habitual](#-uso-habitual-flujo-de-trabajo)), no alfabéticamente.

## 📑 Índice

1. [obtener_macs_ip_red.sh](#obtener_macs_ip_redsh)
2. [createinv_macs_v4.py](#createinv_macs_v4py)
3. [verifica_mac_ip_v3.py](#verifica_mac_ip_v3py)
4. [create_cssh_macs_v2.py](#create_cssh_macs_v2py)
5. [fix_ssh_keys.sh](#fix_ssh_keyssh)

---

## 📋 Tabla resumen

| Orden | Script | Tipo | Propósito | Requiere sudo/nmap | Entrada | Salida |
|---|---|---|---|---|---|---|
| 1 | `obtener_macs_ip_red.sh` | Bash | Escaneo rápido de red fija (MACROLAN) → lista MAC/IP | Sí (nmap) | — | `macs_ip_temp.txt` |
| 2 | `createinv_macs_v4.py` | Python | Inventario Ansible INI a partir de MACs (clave = hostname, IP en `ansible_host`), red predefinida o CIDR libre | Sí | `macs.txt [red\|CIDR]` | `inventory_generated.ini` |
| 3 | `verifica_mac_ip_v3.py` | Python | Comprueba si las IPs de un fichero MAC/IP/HOST siguen siendo correctas, red predefinida o CIDR libre | Sí (nmap) | `archivo.txt [red]` | `archivo_result.txt` |
| 4 | `create_cssh_macs_v2.py` | Python | MACs/IPs → fichero ClusterSSH, agrupado por prefijo de IP con formato de lista `{a,b,c}` | No | `macs.txt [grupo]` | `cssh_<archivo>_generated.txt` |
| 5 | `fix_ssh_keys.sh` | Bash | Purga y regenera entradas de `known_hosts` para una red /24 | Sí (nmap, ssh-keyscan) | `<red_base> (ej. 192.168.1.0)` | Actualiza `~/.ssh/known_hosts` (+ backup) |

---

## 🔁 Uso habitual (flujo de trabajo)

Flujo recomendado de principio a fin, desde que no se conoce nada de la red hasta el mantenimiento periódico del inventario:

1. **Descubrir equipos** → `obtener_macs_ip_red.sh`
   Escanea la red y genera un fichero MAC/IP inicial (`macs_ip_temp.txt`). Es el punto de partida cuando todavía no existe un fichero `macs_*.txt` con los equipos del aula/centro.

2. **Generar el inventario Ansible** → `createinv_macs_v4.py macs.txt [red]`
   A partir del fichero de MACs (el generado en el paso 1, o uno ya existente), crea `inventory_generated.ini` listo para usar con los playbooks de `playbooks/` (ver `AGENTS.md`).

3. **Mantenimiento periódico** → `verifica_mac_ip_v3.py macs.txt [red]`
   Con el tiempo, en redes DHCP las IPs pueden cambiar de equipo. Este script se ejecuta periódicamente para detectarlo y regenerar los datos actualizados (`archivo_result.txt`), que pueden volver a alimentar el paso 2.

4. **Acceso interactivo** → `create_cssh_macs_v2.py macs.txt grupo`
   Cuando se necesita abrir sesión en varias máquinas a la vez (por ejemplo, para revisar algo manualmente), este script genera el fichero de configuración para abrir una sesión ClusterSSH a todo un grupo.

5. **Solucionar avisos SSH** → `fix_ssh_keys.sh <red_base>`
   Si tras el paso 3 se detecta que las IPs han cambiado, los fingerprints SSH guardados en `known_hosts` quedan obsoletos. Este script limpia y regenera `known_hosts` para evitar errores de "host key verification failed" antes de volver a conectar (pasos 2 o 4).

---

## obtener_macs_ip_red.sh

**Propósito**: Escaneo rápido de la red fija `172.28.222.0/24` (MACROLAN) para obtener los pares MAC/IP activos.

**Uso**:
```bash
sudo ./obtener_macs_ip_red.sh
```

**Comportamiento**: ejecuta `nmap -sn` sobre la red y, con `awk`, extrae de la salida cada MAC junto a su IP, guardando el resultado en `macs_ip_temp.txt`. Es el script más simple del conjunto; sirve como generador inicial de los ficheros `macs_*.txt` que consumen el resto de scripts.

---

## createinv_macs_v4.py

**Propósito**: Genera un inventario Ansible INI (`inventory_generated.ini`) a partir de un fichero de MACs, resolviendo la IP actual de cada equipo mediante un escaneo `nmap -sn`. Es la versión más completa del generador de inventarios.

**Uso**:
```bash
sudo python3 createinv_macs_v4.py macs.txt                  # red por defecto (MACROLAN)
sudo python3 createinv_macs_v4.py macs.txt WIFI_ALU          # red predefinida
sudo python3 createinv_macs_v4.py macs.txt 192.168.1.0/24    # red CIDR libre
python3 createinv_macs_v4.py                                 # ver ayuda
```

**Comportamiento**:
- Lee líneas `MAC [IP] [HOSTNAME]`; si falta el hostname, genera uno automático (`equipo-<mac>`).
- Acepta como red a escanear tanto nombres predefinidos — cargados desde `inventories/available_networks.json` (ver nota al principio de este documento) — como cualquier red en formato **CIDR** (ej. `10.0.0.0/16`), validando el formato.
- Requiere permisos sudo (los comprueba con `sudo -n true` antes de lanzar `nmap`).
- La clave de cada host en el inventario es el **hostname**; la IP se asigna a la variable estándar `ansible_host`, y se añaden `mac_address`/`host_name` como variables adicionales.
- Si no encuentra la MAC en el escaneo, usa la IP original del fichero (si existe, marcando `estado=no_encontrado`) o comenta la línea.
- Conserva los permisos del fichero de MACs original y los aplica al `inventory_generated.ini` generado.
- El fichero de salida incluye cabecera con metadatos (red escaneada, archivo fuente).

---

## verifica_mac_ip_v3.py

**Propósito**: Comprueba si las IPs registradas en un fichero `MAC IP HOST` siguen correspondiendo a esas MACs, útil en redes DHCP donde la IP puede cambiar con el tiempo. Es la versión más completa del verificador.

**Uso**:
```bash
sudo python3 verifica_mac_ip_v3.py equipos.txt                  # red por defecto (MACROLAN)
sudo python3 verifica_mac_ip_v3.py equipos.txt wifi_alu           # red predefinida
sudo python3 verifica_mac_ip_v3.py equipos.txt 192.168.1.0/24      # red CIDR libre
python3 verifica_mac_ip_v3.py                                      # ver ayuda
```

**Comportamiento**:
- Acepta como red a escanear nombres predefinidos — cargados desde `inventories/available_networks.json` (ver nota al principio de este documento) — o cualquier CIDR libre.
- Escanea una sola vez la red indicada y construye un mapa MAC→IP.
- Para cada equipo del fichero de entrada, compara la IP esperada con la IP actual encontrada: marca como correcta (✅), incorrecta (⚠️, indicando la IP esperada) o no encontrada (❌).
- Genera `archivo_result.txt` con el detalle, un resumen de estadísticas y una sección final con los datos actualizados (`MAC IP_ACTUAL HOST`) lista para sustituir al fichero original.

---

## create_cssh_macs_v2.py

**Propósito**: Convierte un fichero de MACs (formato `MAC IP HOST`) en un fichero de configuración para [ClusterSSH](https://github.com/duncs/clusterssh) (`cssh -c archivo.txt grupo`), agrupando los hosts por los 3 primeros octetos de su IP.

**Uso**:
```bash
python3 create_cssh_macs_v2.py macs_1fpb_alu.txt biblioteca
```

**Comportamiento**:
- Ignora líneas vacías, comentarios (`#`) y líneas con `DOWN`.
- Agrupa los hosts por prefijo de red (3 primeros octetos de la IP).
- Para cada grupo, lista los octetos finales entre llaves separados por comas: `grupo prefijo.{10,11,12}` — un formato explícito y predecible, sin intentar compactar en rangos `{inicio..fin}` (lo que evitaría errores si hay huecos en la numeración).
- Guarda el resultado en `cssh_<nombre_entrada>_generated.txt`.

---

## fix_ssh_keys.sh

**Propósito**: Resuelve conflictos de `known_hosts` cuando las IPs de una red /24 han cambiado de equipo (típico en redes con DHCP), eliminando las entradas antiguas y añadiendo los fingerprints SSH actuales.

**Uso**:
```bash
./fix_ssh_keys.sh 192.168.1.0
```

**Comportamiento**:
1. Hace backup de `~/.ssh/known_hosts` con timestamp.
2. Elimina (`ssh-keygen -R`) las entradas de las 254 IPs posibles de la red indicada.
3. Escanea la red con `nmap -sn` y usa `ssh-keyscan` para añadir los fingerprints de los hosts activos.

**Requisitos**: `nmap`, `ssh-keygen`, `ssh-keyscan` disponibles; permisos para escanear la red.
