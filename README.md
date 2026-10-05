# Ansible Project - Sistema de Gestión de Infraestructura

Proyecto Ansible para la gestión automatizada de máquinas Linux (LliureX) en una red educativa. Proporciona playbooks para automatizar tareas comunes de administración de sistemas, configuración de red y despliegue de software.

## 📑 Tabla de Contenidos

- [Descripción](#-descripción)
- [Inicio Rápido](#-inicio-rápido)
  - [Requisitos](#requisitos)
  - [Instalación](#instalación)
  - [Estructura del Proyecto](#estructura-del-proyecto)
- [Configuración](#%EF%B8%8F-configuración)
  - [ansible.cfg](#ansiblecfg)
  - [Inventario](#inventario)
  - [Variable de entorno ANSIBLE_CENTER_PATH](#variable-de-entorno-ansible_center_path)
- [Playbooks Disponibles](#-playbooks-disponibles)
- [Ejemplos de Uso](#-ejemplos-de-uso)
  - [Ejecutar un playbook específico](#ejecutar-un-playbook-específico)
  - [Ejecutar en hosts específicos](#ejecutar-en-hosts-específicos)
- [Seguridad y Credenciales](#-seguridad-y-credenciales)
  - [Setupeo Inicial](#setupeo-inicial)
  - [Archivos de Configuración](#archivos-de-configuración)
  - [Host Key Checking](#host-key-checking)
- [Troubleshooting](#-troubleshooting)
  - [Conexión SSH rechazada](#conexión-ssh-rechazada)
  - [Permisos insuficientes](#permisos-insuficientes)
  - [Host no accesible](#host-no-accesible)
- [Recursos Útiles](#-recursos-útiles)
- [Autor](#-autor)
- [Notas](#-notas)

## 📋 Descripción

Este proyecto contiene una colección de playbooks Ansible para automatizar:

- **Gestión de Hostname**: Cambio de nombre de hosts
- **Instalación de Software**: Herramientas educativas y de desarrollo (Klavaro, Ktouch, Pinta, UnityHub, Veyon)
- **Administración de Usuarios**: Creación y gestión de usuarios del sistema
- **Configuración de Red**: Scanner de red, interfaces virtuales, Wake-on-LAN
- **Control Remoto**: Ejecución de scripts remotos, SSH check, reinicio y apagado de máquinas
- **Gestión de Alias**: Configuración de alias de red

## 🚀 Inicio Rápido

### Requisitos

- Ansible 2.9+ instalado
- Acceso SSH a los hosts gestionados
- Python 3.6+ en las máquinas remotas
- Credenciales SSH configuradas

### Instalación

```bash
# Clonar o copiar el proyecto
cd /path/to/ansible-center-common

# Crear tu inventario a partir de la plantilla (inventory.ini NO se versiona)
cp inventories/inventory.template.ini inventories/inventory.ini
vi inventories/inventory.ini

# Verificar conectividad
ansible all -i inventories/inventory.ini -m ping
```

### Estructura del Proyecto

```
ansible-center-common/
├── ansible.cfg                   # Configuración global de Ansible
├── ansible_install_prepare.sh    # Prepara un equipo LliureX cliente para Ansible
├── disable_host_key_cheking.sh   # Exporta ANSIBLE_HOST_KEY_CHECKING=False
├── setup_local_config.sh         # Crea los archivos locales/privados (no versionados)
├── group_vars/
│   └── all.yml                   # Variables globales (usuario remoto, admin, etc.)
├── inventories/                  # Inventarios y variables
│   ├── inventory.template.ini    # Plantilla: copiar a inventory.ini antes de usar
│   ├── macs_sample.txt           # Ejemplo de fichero MAC/IP/HOST para scripts/
│   ├── vault_secrets.yml         # Credenciales encriptadas (local, NO versionado)
│   └── misc/
├── playbooks/                    # Colección de playbooks (ver AGENTS.md)
│   ├── alias_mgmt_boca_off/
│   ├── change-hostname/
│   ├── create-lliurex-user/
│   ├── exec-remote-script/
│   ├── interfaz_virtual_boca/
│   ├── klavaro-ktouch-install/
│   ├── network-scanner/
│   ├── pinta-install/
│   ├── poweroff/
│   ├── restart/
│   ├── ssh-check/
│   ├── unityhub-install/
│   ├── veyon-install/
│   └── wake-on-lan/
├── scripts/                      # Utilidades auxiliares (ver scripts/SCRIPTS_HOWTO.md)
├── csshs/                        # Ficheros de configuración para ClusterSSH (cssh)
├── SECURITY.md                   # Guía detallada de seguridad y credenciales
├── GRAPHICAL_ENVS.md             # Alternativas de interfaz gráfica para Ansible (AWX, etc.)
└── SAMPLES.txt                   # Ejemplos sueltos de invocación de ansible-playbook
```

## ⚙️ Configuración

### ansible.cfg

El archivo `ansible.cfg` contiene la configuración global:

```ini
[defaults]
inventory = inventory.ini
#remote_user = me.millan
host_key_checking = False
retry_files_enabled = False
deprecation_warnings = False

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
timeout = 30

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = True
```

**Opciones principales:**
- `inventory`: Ruta del archivo de inventario
- `host_key_checking`: Desabilita verificación de clave de host (útil en redes de laboratorio con IPs cambiantes por DHCP)
- `ssh_args` / `pipelining`: Optimizan la conexión SSH y evitan prompts de verificación de host
- `become`: Habilita escalada de privilegios con sudo
- `become_ask_pass`: Solicita contraseña para sudo

### Inventario

Este repositorio es el **público/común** (`ansible-center-common`); los inventarios reales con IPs, MACs y hostnames de un centro concreto son datos privados y viven en un repositorio separado (p. ej. `ansible-center-boca`). Por eso `inventories/inventory.ini` **no** se versiona aquí (ver `.gitignore`); en su lugar se incluye una plantilla.

**Primer uso**:
```bash
cp inventories/inventory.template.ini inventories/inventory.ini
vi inventories/inventory.ini
```

Formato básico de `inventory.template.ini`:

```ini
[devices]
192.168.1.100
192.168.1.101
192.168.1.102

[devices:vars]
ansible_user=ubuntu
ansible_become=yes
```

También admite el formato con nombres y variables (recomendado si generas el inventario con `scripts/createinv_macs_v4.py`, ver `scripts/SCRIPTS_HOWTO.md`):

```ini
[lab_machines]
lab-pc-01 ansible_host=192.168.1.100 mac_address=AA:BB:CC:DD:EE:01
lab-pc-02 ansible_host=192.168.1.101 mac_address=AA:BB:CC:DD:EE:02

[lab_machines:vars]
ansible_user=ubuntu
ansible_become=yes
```

### Variable de entorno `ANSIBLE_CENTER_PATH`

Si trabajas con ambos repos a la vez (este repo público `ansible-center-common` y tu repo privado de datos, p. ej. `ansible-center-boca`) en el mismo equipo, los scripts de `scripts/` (ver `scripts/SCRIPTS_HOWTO.md`) pueden localizar automáticamente tanto el `inventories/available_networks.json` como los ficheros de MACs (`macs_*.txt`) de tu repo privado, sin que tengas que pasar rutas completas cada vez ni ejecutar los scripts desde dentro de ese repo.

Para ello, exporta `ANSIBLE_CENTER_PATH` apuntando a la raíz de tu repo de datos:

```bash
# Por ejemplo, en tu ~/.bashrc o ~/.zshrc
export ANSIBLE_CENTER_PATH="$HOME/ansible-center-boca"
```

⚠️ **Importante si usas `sudo`**: estos scripts necesitan sudo para ejecutar `nmap`, pero `sudo` **limpia el entorno por defecto** y no propaga `ANSIBLE_CENTER_PATH` (ni ninguna otra variable que hayas exportado en tu shell) al proceso elevado. Usa `sudo -E` para conservarla:

```bash
# Aunque estés en ansible-center-common y macs_inf3_alu.txt viva en
# ansible-center-boca/inventories/, esto funciona (nota el -E):
sudo -E ./scripts/verifica_mac_ip_v3.py macs_inf3_alu.txt INFOR3
```

Si olvidas el `-E`, el script lo detecta y te lo recuerda en el propio mensaje de aviso/error.

**Orden de búsqueda** que siguen los scripts, tanto para las redes predefinidas como para el fichero de MACs que les pases como argumento:

1. Tal cual se ha indicado (ruta relativa al directorio actual o absoluta) — si existe, se usa sin más.
2. `$ANSIBLE_CENTER_PATH/inventories/<nombre_fichero>` (si la variable está definida).
3. `inventories/<nombre_fichero>` del propio repo donde vive el script (`ansible-center-common`) — este es el comportamiento por defecto si no defines la variable, útil para quien solo ha clonado el repo público.
4. Solo para las redes predefinidas: si no se encuentra `available_networks.json` en ninguno de los sitios anteriores, un pequeño conjunto embebido en el propio script, como último recurso (avisando por `stderr`). Para el fichero de MACs no hay fallback: si no se encuentra en ninguno de los sitios anteriores, el script termina con un error.

`inventories/available_networks.sample.json` **no** forma parte de esta búsqueda: es solo una plantilla de ejemplo para copiar a `available_networks.json` y adaptar a tu centro, no una fuente que los scripts consulten en tiempo de ejecución. No es necesario definir `ANSIBLE_CENTER_PATH` si ejecutas los scripts dentro de tu repo privado (donde ya existen `inventories/available_networks.json` y tus ficheros de MACs).

## 🎯 Playbooks Disponibles

Consultar `AGENTS.md` para lista completa de playbooks y sus usos.

## 💡 Ejemplos de Uso

### Ejecutar un playbook específico

```bash
# Cambiar hostname en todos los dispositivos
ansible-playbook playbooks/change-hostname/change_host_name.yml -i inventories/inventory.ini -e "host_name=new-hostname"

# Instalar Veyon en máquinas seleccionadas
ansible-playbook playbooks/veyon-install/main.yml -i inventories/inventory.ini --limit lab_machines

# Reiniciar máquinas
ansible-playbook playbooks/restart/restart.yml -i inventories/inventory.ini
```

### Ejecutar en hosts específicos

```bash
# Solo en ciertos hosts
ansible-playbook playbook.yml -i inventories/inventory.ini -l host1,host2

# Por grupo
ansible-playbook playbook.yml -i inventories/inventory.ini -l lab_machines
```

## 🔐 Seguridad y Credenciales

### ⚠️ IMPORTANTE: Configuración de Credenciales

Este proyecto ha sido securizado para **NO contener credenciales en el control de versiones**. Las contraseñas no se almacenan hardcodeadas.

#### Setupeo Inicial

Ejecuta el script de configuración local:

```bash
./setup_local_config.sh
```

Este script creará los archivos locales necesarios:
- `password_ENV.txt` - Variables de entorno con tus credenciales (NO versionado)
- `.vault_pass` - Contraseña para Ansible Vault (NO versionado)
- `ansible.cfg.local` - Configuración personal (NO versionado)

El proyecto combina **Ansible Vault** (`inventories/vault_secrets.yml`, encriptado, para credenciales compartidas) con **`--ask-pass`/`--ask-become-pass`** (contraseñas puntuales por SSH/sudo). Para la guía completa — crear/editar el vault, autenticación SSH con claves, variables de entorno, patrón de inventarios seguros y troubleshooting de credenciales — consulta **[SECURITY.md](SECURITY.md)**.

### Archivos de Configuración

**Archivos versionados (públicos):**
- `.gitignore` - Define qué archivos excluir (incluye el patrón para separar este repo público de la configuración privada de cada centro)
- `password_ENV.txt.example` - Template del archivo de variables
- `.vault_pass.example` - Instrucciones para crear `.vault_pass`
- `inventories/inventory.template.ini` - Plantilla de inventario

**Archivos NO versionados (locales, privados de cada centro):**
- `password_ENV.txt` - Tus credenciales reales
- `.vault_pass` - Tu contraseña de vault
- `ansible.cfg.local` - Tu configuración personal
- `inventories/inventory.ini` - Tu inventario real (copiado desde la plantilla)
- `inventories/vault_secrets.yml` - Credenciales compartidas encriptadas con Ansible Vault

### Host Key Checking

Actualmente **deshabilitado en `ansible.cfg`** para laboratorio educativo (útil en redes dinámicas):

```ini
[ssh_connection]
host_key_checking = False
```

**Para entornos de producción**, cambiar a:

```ini
[ssh_connection]
host_key_checking = True
```

## 🐛 Troubleshooting

### Conexión SSH rechazada

```bash
# Verificar conectividad SSH
ansible all -i inventories/inventory.ini -m ping

# Ver detalles de conexión
ansible all -i inventories/inventory.ini -m debug -a "var=ansible_connection"
```

### Permisos insuficientes

- Verificar usuario SSH tiene permisos sudo
- Habilitar `become: yes` en playbooks
- Verificar `become_ask_pass` solicitando contraseña correcta

### Host no accesible

```bash
# Verificar inventario
ansible-inventory -i inventories/inventory.ini --list

# Probar conectividad
ssh -v usuario@192.168.1.10
```

## 📚 Recursos Útiles

- [Documentación Oficial Ansible](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [LliureX](https://lliurex.net/) - Distribución Linux educativa

## 👤 Autor

Eduardo Millán

## 📝 Notas

- Los scripts helper en `scripts/` (generación de inventarios, conversión a ClusterSSH, verificación MAC/IP) facilitan tareas comunes — ver `scripts/SCRIPTS_HOWTO.md` para la documentación de cada uno
- Revisar `SAMPLES.txt` para ejemplos sueltos de invocación de `ansible-playbook`
- Ver `AGENTS.md` para documentación detallada de cada playbook
- Ver `SECURITY.md` para la guía completa de credenciales, Ansible Vault y autenticación SSH
- Ver `GRAPHICAL_ENVS.md` para alternativas de interfaz gráfica (AWX, Rundeck, Semaphore, etc.)
- Este repositorio es la parte pública/común; la configuración e inventarios reales de un centro concreto se gestionan en un repositorio privado aparte (p. ej. `ansible-center-boca`)

