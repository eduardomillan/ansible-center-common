# SECURITY.md - Guía de Seguridad

Guía completa para manejar credenciales y configuración segura en este proyecto Ansible.

## 🔒 Principios de Seguridad

1. **Zero Hardcoding**: No hay credenciales en archivos versionados
2. **Layered Security**: Múltiples capas de protección (Vault + --ask-pass)
3. **Environment-based**: Configuración diferenciada por entorno (dev/staging/prod)
4. **Audit Trail**: Trazabilidad de cambios y accesos

## 📋 Tabla de Contenidos

- [Configuración Inicial](#configuración-inicial)
- [Ansible Vault](#ansible-vault)
- [Autenticación SSH](#autenticación-ssh)
- [Variables de Entorno](#variables-de-entorno)
- [Inventarios Seguros](#inventarios-seguros)
- [Troubleshooting](#troubleshooting)

---

## Configuración Inicial

### Paso 1: Ejecutar Setup Script

```bash
cd /path/to/Ansible
./setup_local_config.sh
```

Este script creará interactivamente:
1. `password_ENV.txt` - Variables de entorno personales
2. `.vault_pass` - Contraseña de Ansible Vault
3. `ansible.cfg.local` - Configuración local (opcional)

**Permisos correctos:**
```bash
chmod 600 password_ENV.txt .vault_pass
```

### Paso 2: Verificar Configuración

```bash
# Probar conectividad con autenticación --ask-pass
ansible all -i inventories/inventory.ini -m ping --ask-pass

# Probar Vault
ansible-vault view inventories/vault_secrets.yml --ask-vault-pass
```

---

## Ansible Vault

### ¿Qué está en el Vault?

El archivo `inventories/vault_secrets.yml` contiene credenciales compartidas:

```yaml
default_user_password: "bocallx24"  # Password para nuevos usuarios
network_scanner_password: "lliurex"  # Password para scanner
# Agregar más secretos compartidos aquí
```

### Crear/Editar Vault

**Crear nuevo vault:**
```bash
# Interactive
ansible-vault create inventories/vault_secrets.yml

# Con archivo de password
ansible-vault create inventories/vault_secrets.yml --vault-password-file=.vault_pass
```

**Editar vault existente:**
```bash
# Interactive
ansible-vault edit inventories/vault_secrets.yml

# Con archivo de password
ansible-vault edit inventories/vault_secrets.yml --vault-password-file=.vault_pass
```

**Ver vault sin editar:**
```bash
ansible-vault view inventories/vault_secrets.yml --ask-vault-pass
```

### Usar Vault en Playbooks

**En playbooks YAML:**
```yaml
---
- name: Create user with vault password
  hosts: all
  vars_files:
    - inventories/vault_secrets.yml
  
  tasks:
    - name: Create user
      user:
        name: newuser
        password: "{{ default_user_password | password_hash('sha512') }}"
        state: present
```

**En command line:**
```bash
ansible-playbook playbooks/create-lliurex-user/main.yml \
  -i inventories/inventory.ini \
  --ask-vault-pass
```

### Vault Password File

**Crear archivo de password (NO versionado):**
```bash
# Crear
echo "my_secure_vault_password_123" > .vault_pass
chmod 600 .vault_pass

# Usar
ansible-playbook playbook.yml --vault-password-file=.vault_pass
```

**Usar variable de entorno:**
```bash
export ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass
ansible-playbook playbook.yml
```

---

## Autenticación SSH

### Opción A: SSH Keys (Recomendado)

**Generar clave SSH:**
```bash
# Si no tienes clave SSH
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ansible_key -C "ansible@$(hostname)"
```

**Copiar clave pública a hosts:**
```bash
# Opción 1: ssh-copy-id
ssh-copy-id -i ~/.ssh/ansible_key.pub usuario@192.168.1.10

# Opción 2: Manual
ssh-add ~/.ssh/ansible_key
cat ~/.ssh/ansible_key.pub | ssh usuario@192.168.1.10 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
```

**Configurar en ansible.cfg.local:**
```ini
[defaults]
private_key_file = ~/.ssh/ansible_key

[ssh_connection]
ssh_args = -o IdentityFile=~/.ssh/ansible_key
```

**Usar en playbooks:**
```bash
# No necesita --ask-pass
ansible-playbook playbook.yml -i inventories/inventory.ini
```

### Opción B: Password-based (--ask-pass)

**Para solicitar contraseña en ejecución:**
```bash
# SSH password
ansible-playbook playbook.yml -i inventories/inventory.ini --ask-pass

# Sudo password
ansible-playbook playbook.yml -i inventories/inventory.ini --ask-become-pass

# Ambas
ansible-playbook playbook.yml -i inventories/inventory.ini --ask-pass --ask-become-pass
```

**Corto de flags:**
```bash
ansible-playbook playbook.yml -i inventories/inventory.ini -k -K
```

---

## Variables de Entorno

### Definir Variables

**En archivo shell (password_ENV.txt):**
```bash
#!/bin/bash
# LOCAL FILE - NOT VERSIONED

export ANSIBLE_REMOTE_USER="tu_usuario"
export ANSIBLE_HOST_KEY_CHECKING="False"
export ANSIBLE_VAULT_PASSWORD_FILE=".vault_pass"
# export ANSIBLE_BECOME_PASS="tu_password_sudo"  # NO recomendado
```

**Usar variables:**
```bash
source password_ENV.txt
ansible-playbook playbook.yml -i inventories/inventory.ini --ask-pass
```

### Variables en Command Line

```bash
# Usuario remoto
ansible-playbook playbook.yml -i inventories/inventory.ini -e "ansible_remote_user=tu_usuario"

# Múltiples variables
ansible-playbook playbook.yml -i inventories/inventory.ini \
  -e "ansible_remote_user=tu_usuario" \
  -e "admin_user=admin" \
  -e "host_name=new-hostname"
```

### Variables en Inventario

**Usar variables genéricas en inventarios:**
```ini
[all]
host1 ansible_host=192.168.1.10 ansible_user={{ ansible_remote_user }}
host2 ansible_host=192.168.1.11 ansible_user={{ ansible_remote_user }}
```

**Definir en group_vars/all.yml:**
```yaml
ansible_remote_user: "{{ lookup('env', 'ANSIBLE_REMOTE_USER') or default('ubuntu') }}"
```

---

## Inventarios Seguros

### Patrón Recomendado

**Template (versionado):**
```ini
# inventories/inventory.ini
[all_devices]
host1 ansible_host=192.168.1.10 ansible_user={{ ansible_remote_user }}
host2 ansible_host=192.168.1.11 ansible_user={{ ansible_remote_user }}
```

**Local personalizado (NO versionado):**
```ini
# inventories/inventory.local.ini (agregado a .gitignore)
[local_dev]
myhost ansible_host=192.168.1.50 ansible_user=mi_usuario
```

**Usar inventario local:**
```bash
ansible-playbook playbook.yml -i inventories/inventory.local.ini --ask-pass
```

### Group Variables Seguras

**Template (versionado):**
```yaml
# group_vars/all.yml
ansible_remote_user: "{{ lookup('env', 'ANSIBLE_REMOTE_USER') or default('ubuntu') }}"
admin_user: "{{ lookup('env', 'ADMIN_USER') or default('admin') }}"
```

**Incluir Vault (encriptado):**
```yaml
# group_vars/all.yml
vars_files:
  - inventories/vault_secrets.yml
```

---

## Troubleshooting

### Error: "Permission denied" en SSH

**Causa común:** Usuario incorrecto o SSH key no configurada

**Soluciones:**
```bash
# Verificar usuario actual
whoami

# Probar SSH manualmente
ssh -v usuario@192.168.1.10

# Usar -u flag en Ansible
ansible-playbook playbook.yml -i inventories/inventory.ini -u tu_usuario --ask-pass
```

### Error: "Vault password file not found"

```bash
# Verificar que .vault_pass existe
ls -la .vault_pass

# Crear si falta
echo "your_password" > .vault_pass
chmod 600 .vault_pass

# Usar --ask-vault-pass en su lugar
ansible-playbook playbook.yml --ask-vault-pass
```

### Error: "sudo: sorry, you must have a tty to run sudo"

**Solución:** Agregar `-b` flag en playbook o usar `ansible.cfg`:

```yaml
# playbook.yml
---
- hosts: all
  become: yes
  tasks:
    - name: Task requiring sudo
      command: systemctl status nginx
```

O en `ansible.cfg`:
```ini
[defaults]
allow_world_readable_tmpfiles = True
```

### Error: "Vault password may be empty"

```bash
# Verificar contenido de .vault_pass
cat .vault_pass | od -c  # Ver caracteres (debug)

# Crear nuevo .vault_pass
echo "my_password" > .vault_pass
chmod 600 .vault_pass
```

### Host no responde / Timeout

```bash
# Aumentar timeout en ansible.cfg.local
[ssh_connection]
timeout = 60

# O en command line
ansible-playbook playbook.yml --timeout=60
```

---

## Checklist de Seguridad

- [ ] `.vault_pass` existe y tiene permisos 600
- [ ] `password_ENV.txt` tiene permisos 600
- [ ] `.gitignore` incluye archivos sensibles
- [ ] No hay credenciales en git history (revisar si existen)
- [ ] Vault password es fuerte (>12 caracteres)
- [ ] SSH keys están generadas y copiadas a hosts
- [ ] `ansible.cfg` tiene `host_key_checking = False` solo en dev
- [ ] `group_vars/all.yml` usa variables, no hardcoded
- [ ] Inventarios usan `{{ ansible_remote_user }}`
- [ ] Scripts shell usan `--ask-pass` en lugar de hardcodeado

---

## Referencias

- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Ansible SSH Keys](https://docs.ansible.com/ansible/latest/user_guide/connection_details.html)
- [Best Practices - Securing Passwords](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html#keep-sensitive-variables-private)

