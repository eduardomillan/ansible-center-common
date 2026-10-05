# AGENTS.md - Playbooks Disponibles

Documentación detallada de todos los playbooks Ansible disponibles en este proyecto. Cada "agente" es un playbook especializado para una tarea específica de administración de sistemas.

## 📑 Índice de Playbooks

1. [change-hostname](#change-hostname)
2. [create-lliurex-user](#create-lliurex-user)
3. [exec-remote-script](#exec-remote-script)
4. [interfaz_virtual_boca](#interfaz_virtual_boca)
5. [klavaro-ktouch-install](#klavaro-ktouch-install)
6. [network-scanner](#network-scanner)
7. [pinta-install](#pinta-install)
8. [poweroff](#poweroff)
9. [restart](#restart)
10. [ssh-check](#ssh-check)
11. [unityhub-install](#unityhub-install)
12. [veyon-install](#veyon-install)
13. [wake-on-lan](#wake-on-lan)
14. [alias_mgmt_boca_off](#alias_mgmt_boca_off)

---

## change-hostname

**Propósito**: Cambiar el nombre de host (hostname) en máquinas remotas

**Ubicación**: `playbooks/change-hostname/`

**Archivos principales**:
- `change_host_name.yml` - Playbook principal
- `copy_change_hostname.yml` - Playbook alternativo
- `do_change_host_name.sh` - Script helper

**Descripción**:
Automatiza el cambio de hostname en máquinas Linux. Actualiza:
- Archivo `/etc/hostname`
- Archivo `/etc/hosts`
- Configuración actual del sistema

**Uso**:
```bash
ansible-playbook playbooks/change-hostname/change_host_name.yml \
  -i inventories/inventory.ini \
  -e "host_name=nuevo-nombre"
```

**Variables requeridas**:
- `host_name`: Nuevo nombre de host (ej: `lab-pc-01`)

**Requisitos**:
- Acceso sudo a las máquinas
- Grupo de hosts definido como `devices` en inventario

**Notas**:
- Requiere reinicio para aplicar completamente en algunos casos
- Usa `hostnamectl` para compatibilidad con systemd

---

## create-lliurex-user

**Propósito**: Crear nuevos usuarios en máquinas LliureX

**Ubicación**: `playbooks/create-lliurex-user/`

**Descripción**:
Automatiza la creación de usuarios locales en máquinas Linux/LliureX con:
- Creación de cuenta de usuario
- Configuración de shell (bash)
- Permisos sudo (opcional)
- Directorios home

**Uso**:
```bash
ansible-playbook playbooks/create-lliurex-user/main.yml \
  -i inventories/inventory.ini \
  -e "username=nuevouser"
```

**Variables**:
- `username`: Nombre de usuario a crear (ej: `alumno01`)
- `user_password`: Contraseña (opcional, puede ser vacía)
- `sudoers`: Boolean para agregar a grupo sudo (true/false)

**Requisitos**:
- Acceso sudo
- Sistema operativo compatible con LliureX

---

## exec-remote-script

**Propósito**: Ejecutar scripts personalizados en máquinas remotas

**Ubicación**: `playbooks/exec-remote-script/`

**Descripción**:
Playbook flexible para ejecutar scripts bash o shell en hosts remotos. Útil para:
- Ejecutar comandos complejos
- Ejecutar scripts personalizados
- Operaciones puntuales no cubiertas por otros playbooks

**Uso**:
```bash
# Ejecutar comando directo
ansible-playbook playbooks/exec-remote-script/main.yml \
  -i inventories/inventory.ini \
  -e "command='whoami'"

# Ejecutar script local en remoto
ansible-playbook playbooks/exec-remote-script/main.yml \
  -i inventories/inventory.ini \
  -e "script_path=/path/to/script.sh"
```

**Variables**:
- `command`: Comando a ejecutar
- `script_path`: Ruta del script a ejecutar

---

## interfaz_virtual_boca

**Propósito**: Configurar interfaces de red virtuales

**Ubicación**: `playbooks/interfaz_virtual_boca/`

**Descripción**:
Administra la configuración de interfaces de red virtuales, útil para:
- Crear interfaces virtuales (VLAN, bridge)
- Configurar múltiples IPs en una interfaz
- Gestionar configuración de red avanzada

**Nota**: Específico para configuración de red educativa (BOCA - entorno de laboratorio)

---

## klavaro-ktouch-install

**Propósito**: Instalar herramientas educativas de mecanografía

**Ubicación**: `playbooks/klavaro-ktouch-install/`

**Descripción**:
Instala automáticamente las aplicaciones educativas:
- **Klavaro**: Software de mecanografía avanzado
- **KTouch**: Tutor de mecanografía para KDE

Ideal para entornos educativos.

**Uso**:
```bash
ansible-playbook playbooks/klavaro-ktouch-install/main.yml \
  -i inventories/inventory.ini \
  -l lab_machines
```

**Requisitos**:
- Máquinas con gestor de paquetes (apt/yum)
- Acceso sudo
- Conectividad a repositorios de paquetes

---

## network-scanner

**Propósito**: Escanear y mapear la red local

**Ubicación**: `playbooks/network-scanner/`

**Descripción**:
Ejecuta escaneos de red para:
- Descubrir hosts activos en la red
- Identificar puertos abiertos
- Mapear servicios disponibles

**Uso**:
```bash
ansible-playbook playbooks/network-scanner/scan.yml \
  -i inventories/inventory.ini \
  -e "network_range=192.168.1.0/24"
```

**Herramientas utilizadas**:
- `nmap` - Para escaneo de puertos
- `ping` - Para descubrimiento de hosts

---

## pinta-install

**Propósito**: Instalar Pinta (editor de imágenes educativo)

**Ubicación**: `playbooks/pinta-install/`

**Descripción**:
Instala Pinta, una herramienta educativa de edición de imágenes similar a Paint.

**Uso**:
```bash
ansible-playbook playbooks/pinta-install/main.yml \
  -i inventories/inventory.ini
```

**Requisitos**:
- Acceso sudo
- Gestor de paquetes disponible

---

## poweroff

**Propósito**: Apagar máquinas remotas

**Ubicación**: `playbooks/poweroff/`

**Descripción**:
Apaga de forma ordenada las máquinas especificadas.

**Uso**:
```bash
ansible-playbook playbooks/poweroff/poweroff.yml \
  -i inventories/inventory.ini \
  -l machines_to_shutdown
```

**Advertencia**: ⚠️ Operación destructiva, requiere confirmación

---

## restart

**Propósito**: Reiniciar máquinas remotas

**Ubicación**: `playbooks/restart/`

**Descripción**:
Reinicia las máquinas remotas de forma ordenada, esperando a que se completen los servicios.

**Uso**:
```bash
ansible-playbook playbooks/restart/restart.yml \
  -i inventories/inventory.ini
```

**Comportamiento**:
- Notifica a usuarios conectados antes de reiniciar
- Espera a que se completen procesos críticos
- Registra logs de reinicio

---

## ssh-check

**Propósito**: Verificar conectividad SSH a hosts

**Ubicación**: `playbooks/ssh-check/`

**Descripción**:
Verifica que la conectividad SSH esté disponible en todos los hosts del inventario. Útil para:
- Diagnosticar problemas de conectividad
- Validar configuración SSH
- Probar nuevos hosts

**Uso**:
```bash
ansible-playbook playbooks/ssh-check/check.yml \
  -i inventories/inventory.ini
```

**Output**:
- Lista de hosts accesibles
- Lista de hosts no accesibles
- Detalles de errores de conexión

---

## unityhub-install

**Propósito**: Instalar Unity Hub (plataforma de desarrollo de juegos)

**Ubicación**: `playbooks/unityhub-install/`

**Descripción**:
Instala Unity Hub en máquinas para desarrollo de aplicaciones Unity. Útil en:
- Laboratorios de programación
- Cursos de desarrollo de juegos
- Entornos educativos

**Uso**:
```bash
ansible-playbook playbooks/unityhub-install/main.yml \
  -i inventories/inventory.ini \
  -l development_machines
```

**Requisitos**:
- Sistema operativo compatible
- Suficiente espacio en disco (Unity requiere varios GB)
- Acceso sudo

---

## veyon-install

**Propósito**: Instalar Veyon (software de supervisión educativa)

**Ubicación**: `playbooks/veyon-install/`

**Descripción**:
Instala Veyon, software de supervisión y control remoto diseñado para aulas educativas. Permite:
- Ver pantallas de alumnos
- Controlar máquinas remotamente
- Ejecutar lecciones guiadas

**Uso**:
```bash
ansible-playbook playbooks/veyon-install/main.yml \
  -i inventories/inventory.ini \
  -l lab_machines
```

**Componentes**:
- Veyon Server (en máquinas a supervisar)
- Veyon Master (en máquina del profesor)

**Requisitos**:
- Acceso sudo en todas las máquinas
- Conectividad de red entre máquinas

---

## wake-on-lan

**Propósito**: Encender máquinas remotas usando Wake-on-LAN (WOL)

**Ubicación**: `playbooks/wake-on-lan/`

**Descripción**:
Envía "paquetes mágicos" (magic packets) para encender máquinas que tengan WOL habilitado. Útil para:
- Encender máquinas de laboratorio antes de clase
- Automatizar encendido de equipos
- Ahorrar energía

**Uso**:
```bash
ansible-playbook playbooks/wake-on-lan/wol.yml \
  -i inventories/inventory.ini \
  -e "target_host=lab-pc-01"
```

**Variables**:
- `target_host`: Host a encender
- `mac_address`: Dirección MAC de la interfaz de red

**Requisitos**:
- Wake-on-LAN debe estar habilitado en BIOS
- Host debe estar en la misma subred
- Herramienta `wakeonlan` instalada

---

## alias_mgmt_boca_off

**Propósito**: Gestionar alias de red en configuración BOCA

**Ubicación**: `playbooks/alias_mgmt_boca_off/`

**Descripción**:
Administra alias de red IP en máquinas que no están activas en BOCA (entorno de laboratorio específico).

**Nota**: Playbook específico para infraestructura educativa particular

---

## 🚀 Ejecución General

### Ejecutar todos los playbooks en orden

```bash
ansible-playbook playbooks/*/main.yml -i inventories/inventory.ini
```

### Ejecutar con verbosidad para debugging

```bash
# Verbosidad normal
ansible-playbook playbook.yml -i inventories/inventory.ini -v

# Verbosidad extendida
ansible-playbook playbook.yml -i inventories/inventory.ini -vv

# Verbosidad máxima
ansible-playbook playbook.yml -i inventories/inventory.ini -vvv
```

### Ejecución en paralelo

```bash
# Ejecutar en 5 máquinas simultáneamente (por defecto es 5)
ansible-playbook playbook.yml -i inventories/inventory.ini --forks 10
```

### Ejecución con límite de hosts

```bash
# Solo en host1 y host2
ansible-playbook playbook.yml -i inventories/inventory.ini --limit host1,host2

# Solo en grupo específico
ansible-playbook playbook.yml -i inventories/inventory.ini --limit lab_machines

# Excluir hosts
ansible-playbook playbook.yml -i inventories/inventory.ini --limit 'all:!host1'
```

---

## 📋 Matriz de Compatibilidad

| Playbook | LliureX | Ubuntu | Debian | RHEL | Notas |
|----------|---------|--------|--------|------|-------|
| change-hostname | ✅ | ✅ | ✅ | ✅ | Universal |
| create-lliurex-user | ✅ | ✅ | ✅ | ✅ | Ajustable |
| exec-remote-script | ✅ | ✅ | ✅ | ✅ | Universal |
| interfaz_virtual_boca | ✅ | ✅ | ✅ | ✅ | Específico |
| klavaro-ktouch-install | ✅ | ✅ | ✅ | ⚠️ | Apt-based |
| network-scanner | ✅ | ✅ | ✅ | ✅ | Requiere nmap |
| pinta-install | ✅ | ✅ | ✅ | ⚠️ | Apt-based |
| poweroff | ✅ | ✅ | ✅ | ✅ | Universal |
| restart | ✅ | ✅ | ✅ | ✅ | Universal |
| ssh-check | ✅ | ✅ | ✅ | ✅ | Universal |
| unityhub-install | ⚠️ | ✅ | ⚠️ | ⚠️ | Arquitectura |
| veyon-install | ✅ | ✅ | ✅ | ⚠️ | Apt-based |
| wake-on-lan | ✅ | ✅ | ✅ | ✅ | Requiere WOL |

**Leyenda**: ✅ Soportado | ⚠️ Parcialmente soportado | ❌ No soportado

---

## 🔍 Troubleshooting de Playbooks

### El playbook no ejecuta

1. Verificar conectividad: `ansible all -i inventories/inventory.ini -m ping`
2. Verificar permisos sudo: `ansible all -i inventories/inventory.ini -m command -a "sudo whoami"`
3. Revisar logs: `ansible-playbook playbook.yml -i inventories/inventory.ini -vvv`

### Errores de permisos

```bash
# Ejecutar con usuario específico
ansible-playbook playbook.yml -i inventories/inventory.ini -u ubuntu

# Especificar clave SSH
ansible-playbook playbook.yml -i inventories/inventory.ini --private-key=~/.ssh/id_rsa
```

### Timeout en conexiones

Aumentar timeout en `ansible.cfg`:
```ini
[ssh_connection]
timeout = 60
```

---

## 📚 Referencias

- Consultar archivos dentro de cada carpeta de playbook para detalles específicos
- Ver `README.md` para información general del proyecto
- Revisar `STRUCTURE.txt` para estructura recomendada de proyectos Ansible
- Ver `scripts/SCRIPTS_HOWTO.md` para la documentación de los scripts auxiliares (generación de inventarios, conversión a ClusterSSH, verificación MAC/IP, etc.) usados para alimentar los inventarios que consumen estos playbooks

