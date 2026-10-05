# SCRIPTS_HOWTO.md - Guía de Scripts

Documentación breve de los scripts auxiliares de `scripts/`. Son utilidades independientes de Ansible usadas para generar inventarios, convertir formatos y verificar/mantener la correspondencia MAC↔IP de los equipos del centro.

> **`$ANSIBLE_CENTER_PATH`**: si tienes definida esta variable de entorno apuntando a tu repo de datos privado (p. ej. `export ANSIBLE_CENTER_PATH="$HOME/ansible-center-boca"` — ver detalles en el `README.md` del repo, sección "Variable de entorno `ANSIBLE_CENTER_PATH`"), `obtener_macs_ip_red.sh`, `createinv_macs_v4.py` y `verifica_mac_ip_v3.py` la usan para localizar datos sin que tengas que pasar rutas completas:

> - **Redes predefinidas**: los tres la leen de `available_networks.json`, buscándolo en `$ANSIBLE_CENTER_PATH/inventories/` y, si no está definida la variable o no existe ahí, en `inventories/` del propio repo (`ansible-center-common`). Si no lo encuentran en ninguno de los dos sitios: `createinv_macs_v4.py`/`verifica_mac_ip_v3.py` usan un pequeño fallback embebido en el script; `obtener_macs_ip_red.sh` en cambio autodetecta la red local de la máquina (ver su propia sección más abajo).

> - **Fichero de MACs** (el argumento `macs.txt`/`archivo.txt` que le pasas): si no existe tal cual en el directorio actual, también se busca por su nombre en `$ANSIBLE_CENTER_PATH/inventories/` y luego en `inventories/` del propio repo. Así puedes ejecutar, por ejemplo, `sudo -E ./scripts/verifica_mac_ip_v3.py macs_inf3_alu.txt INFOR3` desde `ansible-center-common` aunque ese fichero viva en `ansible-center-boca/inventories/`. Para este fichero no hay fallback embebido: si no se encuentra en ningún sitio, el script termina con error.

> - **Dónde guardan su resultado `obtener_macs_ip_red.sh` y `createinv_macs_v4.py`**: ambos escriben dentro de un directorio `inventories/`, en `$ANSIBLE_CENTER_PATH/inventories/` si la variable está definida, o en `inventories/` **del directorio actual** (no del repo del script) si no — creando el directorio si no existe. El nombre del fichero incluye la red usada: `macs_<RED>_temp.txt` (`obtener_macs_ip_red.sh`) o `inventory_<RED>_generated.ini` (`createinv_macs_v4.py`), donde `<RED>` es `MACROLAN`/`LAN`/`LOCAL`, el nombre indicado por parámetro, o el CIDR si se pasó directamente (con `/` sustituido por `-`).
>
> ⚠️ **Ojo con `sudo`**: por defecto `sudo` limpia el entorno y no propaga `ANSIBLE_CENTER_PATH` al proceso elevado, aunque la tengas exportada en tu shell. Usa **`sudo -E`** (no `sudo` a secas) para que estos scripts la vean. Si se te olvida, el propio script lo detecta y te lo recuerda en el aviso/error.

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
| 1 | `obtener_macs_ip_red.sh` | Bash | Escaneo de red MACROLAN/LAN (`available_networks.json`) o autodetectada → lista MAC/IP | Sí (nmap) | `[LOCAL\|NOMBRE_RED\|CIDR]` (opcional) | `inventories/macs_<RED>_temp.txt` (en `$ANSIBLE_CENTER_PATH` o en el directorio actual) |
| 2 | `createinv_macs_v4.py` | Python | Inventario Ansible INI a partir de MACs (clave = hostname, IP en `ansible_host`), red predefinida o CIDR libre | Sí | `macs.txt [red\|CIDR]` | `inventories/inventory_<RED>_generated.ini` (en `$ANSIBLE_CENTER_PATH` o en el directorio actual) |
| 3 | `verifica_mac_ip_v3.py` | Python | Comprueba si las IPs de un fichero MAC/IP/HOST siguen siendo correctas, red predefinida o CIDR libre | Sí (nmap) | `archivo.txt [red]` | `archivo_result.txt` |
| 4 | `create_cssh_macs_v2.py` | Python | MACs/IPs → fichero ClusterSSH, agrupado por prefijo de IP con formato de lista `{a,b,c}` | No | `macs.txt [grupo]` | `cssh_<archivo>_generated.txt` |
| 5 | `fix_ssh_keys.sh` | Bash | Purga y regenera entradas de `known_hosts` para una red /24 | Sí (nmap, ssh-keyscan) | `<red_base> (ej. 192.168.1.0)` | Actualiza `~/.ssh/known_hosts` (+ backup) |

---

## 🔁 Uso habitual (flujo de trabajo)

Flujo recomendado de principio a fin, desde que no se conoce nada de la red hasta el mantenimiento periódico del inventario:

1. **Descubrir equipos** → `obtener_macs_ip_red.sh`
   Escanea la red (MACROLAN/LAN de `available_networks.json`, o la red local autodetectada si no hay fichero de redes) y genera un fichero MAC/IP inicial (`inventories/macs_<RED>_temp.txt`, en `$ANSIBLE_CENTER_PATH` o en el directorio actual). Es el punto de partida cuando todavía no existe un fichero `macs_*.txt` con los equipos del aula/centro.

2. **Generar el inventario Ansible** → `createinv_macs_v4.py macs.txt [red]`
   A partir del fichero de MACs (el generado en el paso 1, o uno ya existente), crea `inventories/inventory_<RED>_generated.ini` (en `$ANSIBLE_CENTER_PATH` o en el directorio actual), listo para usar con los playbooks de `playbooks/` (ver `AGENTS.md`).

3. **Mantenimiento periódico** → `verifica_mac_ip_v3.py macs.txt [red]`
   Con el tiempo, en redes DHCP las IPs pueden cambiar de equipo. Este script se ejecuta periódicamente para detectarlo y regenerar los datos actualizados (`archivo_result.txt`), que pueden volver a alimentar el paso 2.

4. **Acceso interactivo** → `create_cssh_macs_v2.py macs.txt grupo`
   Cuando se necesita abrir sesión en varias máquinas a la vez (por ejemplo, para revisar algo manualmente), este script genera el fichero de configuración para abrir una sesión ClusterSSH a todo un grupo.

5. **Solucionar avisos SSH** → `fix_ssh_keys.sh <red_base>`
   Si tras el paso 3 se detecta que las IPs han cambiado, los fingerprints SSH guardados en `known_hosts` quedan obsoletos. Este script limpia y regenera `known_hosts` para evitar errores de "host key verification failed" antes de volver a conectar (pasos 2 o 4).

---

## obtener_macs_ip_red.sh

**Propósito**: Escanea una red para obtener los pares MAC/IP activos. La red se determina automáticamente, o se puede indicar explícitamente con un parámetro opcional. **Requiere ejecutarse con `sudo`** (comprobado explícitamente al inicio): `nmap -sn` solo revela direcciones MAC (vía ARP) cuando corre como root; sin privilegios detecta los hosts activos pero el fichero de salida queda vacío sin avisar de por qué — por eso el script ahora rechaza ejecutarse sin root en vez de generar un resultado vacío silenciosamente.

**Uso**:
```bash
sudo ./obtener_macs_ip_red.sh                # red automática (ver más abajo)
sudo ./obtener_macs_ip_red.sh LOCAL          # fuerza la red local autodetectada
sudo ./obtener_macs_ip_red.sh WIFI_ALU       # nombre de red de available_networks.json
sudo ./obtener_macs_ip_red.sh 192.168.1.0/24 # CIDR directo

# Si usas $ANSIBLE_CENTER_PATH para que localice available_networks.json
# en tu repo privado, recuerda sudo -E (ver nota al principio del documento):
sudo -E ./obtener_macs_ip_red.sh INFOR3
```

**Comportamiento**: sin argumentos, determina la red a escanear en este orden:
1. Red `MACROLAN` de `available_networks.json`.
2. Si no existe, red `LAN` de ese mismo fichero.
3. Si no existe ninguna de las dos, o no se encuentra el fichero en ningún sitio: autodetecta la red local de la máquina (prioriza la interfaz de la ruta por defecto a Internet; si no puede determinarla, usa la primera red local válida, descartando `lo` y direcciones link-local `169.254.0.0/16`).
4. Si tampoco es posible autodetectarla (por ejemplo, no hay comando `ip` disponible), el script termina con error en vez de escanear una red arbitraria.

Con un argumento, en cambio:
- `LOCAL` fuerza la autodetección de la red local (paso 3 anterior), ignorando `available_networks.json` aunque exista.
- Si tiene forma de CIDR (ej. `192.168.1.0/24`), se usa directamente como red a escanear.
- En cualquier otro caso, se interpreta como el identificador de una red dentro de `available_networks.json` (ej. `WIFI_ALU`, `INFOR3`); si no se encuentra ahí (o no existe el fichero), el script termina con error indicándolo.

En cada caso avisa por `stdout`/`stderr` de qué red ha elegido y de dónde la ha obtenido. Después ejecuta `nmap -sn` sobre esa red y, con `awk`, extrae de la salida cada MAC junto a su IP, guardando el resultado en `macs_<RED>_temp.txt` (p. ej. `macs_MACROLAN_temp.txt`, `macs_LOCAL_temp.txt`, `macs_INFOR3_temp.txt`, o `macs_192.168.1.0-24_temp.txt` si se usó un CIDR directo — el `/` se sustituye por `-` para que sea un nombre de fichero válido) dentro de un directorio `inventories/`: en `$ANSIBLE_CENTER_PATH/inventories/` si esa variable está definida, o en `inventories/` del **directorio actual** en caso contrario (creando el directorio si no existe). Si el fichero queda vacío (ningún host de esa red devolvió MAC) lo avisa explícitamente en vez de dar un falso "✅" — normalmente indica que la red escaneada no es accesible por ARP desde esta máquina (red distinta, a través de un router), o que el script no se ejecutó con privilegios de root. Es el script más simple del conjunto; sirve como generador inicial de los ficheros `macs_*.txt` que consumen el resto de scripts.

---

## createinv_macs_v4.py

**Propósito**: Genera un inventario Ansible INI (`inventory_<RED>_generated.ini`) a partir de un fichero de MACs, resolviendo la IP actual de cada equipo mediante un escaneo `nmap -sn`. Es la versión más completa del generador de inventarios.

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
- Conserva los permisos del fichero de MACs original y los aplica al fichero generado.
- El fichero de salida incluye cabecera con metadatos (red escaneada, archivo fuente).
- Se guarda como `inventory_<RED>_generated.ini` (ej. `inventory_MACROLAN_generated.ini`, `inventory_INFOR3_generated.ini`, o `inventory_192.168.1.0-24_generated.ini` si se usó un CIDR directo) dentro de un directorio `inventories/`: en `$ANSIBLE_CENTER_PATH/inventories/` si esa variable está definida, o en `inventories/` del directorio actual en caso contrario (creando el directorio si no existe) — mismo criterio que `obtener_macs_ip_red.sh`.

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
- Escanea una sola vez la red indicada (con `sudo nmap -sn`, igual que `createinv_macs_v4.py`, para asegurar que se detectan direcciones MAC vía ARP aunque el script no se haya invocado ya como root) y construye un mapa MAC→IP. Si no detecta ninguna MAC pese a tener equipos que verificar, avisa explícitamente de que puede ser un problema de privilegios o de alcance de red (ARP no atraviesa routers), en vez de limitarse a marcar todo como "no encontrado" sin explicación.
- Para cada equipo del fichero de entrada, compara la IP esperada con la IP actual encontrada: marca como correcta (✅), incorrecta (⚠️, indicando la IP esperada) o no encontrada (❌).
- Genera `archivo_result.txt` (junto al fichero de entrada ya resuelto, por lo que respeta igualmente `$ANSIBLE_CENTER_PATH`) con el detalle, un resumen de estadísticas y una sección final con los datos actualizados (`MAC IP_ACTUAL HOST`) lista para sustituir al fichero original.

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
