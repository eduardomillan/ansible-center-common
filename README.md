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
- [Playbooks Disponibles](#-playbooks-disponibles)
- [Ejemplos de Uso](#-ejemplos-de-uso)
  - [Ejecutar un playbook específico](#ejecutar-un-playbook-específico)
  - [Ejecutar en hosts específicos](#ejecutar-en-hosts-específicos)
- [Seguridad y Credenciales](#-seguridad-y-credenciales)
  - [Setupeo Inicial](#setupeo-inicial)
  - [Estrategia Hybrid: Vault + --ask-pass](#estrategia-hybrid-vault---ask-pass)
  - [Variables de Entorno para Credenciales](#variables-de-entorno-para-credenciales)
  - [SSH Keys](#ssh-keys-recomendado)
  - [Archivos de Configuración](#archivos-de-configuración)
  - [Mejores Prácticas](#mejores-prácticas)
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
cd /path/to/Ansible

# Configurar inventario
# Editar archivo de inventario según tus hosts
vi inventories/inventory.ini

# Verificar conectividad
ansible all -i inventories/inventory.ini -m ping
```

### Estructura del Proyecto

```
Ansible/
├── ansible.cfg              # Configuración global de Ansible
├── ansible.cfg.off          # Configuración alternativa (deshabilitada)
├── inventories/             # Archivos de inventario y variables
│   ├── production/
│   ├── development/
│   └── inventory.ini
├── playbooks/               # Colección de playbooks
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
└── csshs/                   # Archivos CSS/HTML relacionados

```

## ⚙️ Configuración

### ansible.cfg

El archivo `ansible.cfg` contiene la configuración global:

```ini
[defaults]
inventory = inventory.ini
host_key_checking = False
retry_files_enabled = False

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = True
```

**Opciones principales:**
- `inventory`: Ruta del archivo de inventario
- `host_key_checking`: Desabilita verificación de clave de host (útil en redes de laboratorio)
- `become`: Habilita escalada de privilegios con sudo
- `become_ask_pass`: Solicita contraseña para sudo

### Inventario

Editar `inventories/inventory.ini` para definir tus hosts:

```ini
[all_devices]
host1 ansible_host=192.168.1.10 ansible_user=ubuntu
host2 ansible_host=192.168.1.11 ansible_user=ubuntu

[lab_machines]
lab-pc-01 ansible_host=192.168.100.50
lab-pc-02 ansible_host=192.168.100.51

[devices]
```

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

#### Estrategia Hybrid: Vault + --ask-pass

El proyecto usa un enfoque híbrido:

1. **Ansible Vault** (`inventories/vault_secrets.yml`): Almacena credenciales compartidas encriptadas
   - Default user password
   - Network scanner passwords
   - Otras credenciales compartidas

2. **--ask-pass / --ask-become-pass**: Solicita contraseñas interactivamente
   - SSH password: `--ask-pass`
   - Sudo password: `--ask-become-pass`

#### Usar Vault para Playbooks

```bash
# Ver contenido del vault (requiere contraseña)
ansible-vault view inventories/vault_secrets.yml --ask-vault-pass

# Editar vault
ansible-vault edit inventories/vault_secrets.yml --ask-vault-pass

# Ejecutar playbook con vault
ansible-playbook playbooks/change-hostname/change_host_name.yml \
  -i inventories/inventory.ini \
  --ask-vault-pass \
  -e "host_name=new-hostname"
```

#### Variables de Entorno para Credenciales

En lugar de hardcodear usuario y contraseña, usa variables de entorno:

```bash
# Opción 1: Exportar variables
export ANSIBLE_REMOTE_USER="tu_usuario"
ansible-playbook playbook.yml -i inventories/inventory.ini --ask-pass

# Opción 2: Pasar como parámetro
ansible-playbook playbook.yml -i inventories/inventory.ini \
  -e "ansible_remote_user=tu_usuario" \
  --ask-pass

# Opción 3: Usar archivo de variables locales
source password_ENV.txt
ansible-playbook playbook.yml -i inventories/inventory.ini --ask-pass
```

#### SSH Keys (Recomendado)

Para mayor seguridad, configura SSH keys:

```bash
# Generar clave SSH si no existe
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ansible_key

# Copiar clave pública a hosts
ssh-copy-id -i ~/.ssh/ansible_key.pub usuario@192.168.1.10

# Usar en ansible.cfg.local
echo "private_key_file = ~/.ssh/ansible_key" >> ansible.cfg.local

# Ahora no necesitas --ask-pass
ansible-playbook playbook.yml -i inventories/inventory.ini
```

### Archivos de Configuración

**Archivos versionados (públicos):**
- `.gitignore` - Define qué archivos excluir
- `password_ENV.txt.example` - Template del archivo de variables
- `.vault_pass.example` - Instrucciones para crear `.vault_pass`
- `inventories/vault_secrets.yml` - Encriptado (contenido seguro)

**Archivos NO versionados (locales, seguros):**
- `password_ENV.txt` - Tus credenciales reales
- `.vault_pass` - Tu contraseña de vault
- `ansible.cfg.local` - Tu configuración personal
- `inventories/inventory.local.ini` - Inventario local personalizado

### Mejores Prácticas

- ✅ **DO**: Usar SSH keys para autenticación
- ✅ **DO**: Usar `--ask-pass` para contraseñas puntuales
- ✅ **DO**: Encriptar secretos compartidos con Ansible Vault
- ✅ **DO**: Guardar credenciales en archivos locales (NO en git)
- ✅ **DO**: Usar variables de entorno para configuración sensible

- ❌ **DON'T**: Commitar `password_ENV.txt` con credenciales reales
- ❌ **DON'T**: Hardcodear contraseñas en playbooks o scripts
- ❌ **DON'T**: Usar `ansible_password` en inventarios públicos
- ❌ **DON'T**: Desabilitar SSH host key checking en producción

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

- Los scripts helper en `/scripts` facilitan tareas comunes
- Revisar `SAMPLES.txt` y `STRUCTURE.txt` para ejemplos y estructura recomendada
- Ver `AGENTS.md` para documentación detallada de cada playbook

