#!/bin/bash

# Instalar Ansible
# Los equipos cliente solo necesitan tener:
#
# - SSH habilitado
# - Python3 instalado (normalmente ya viene en Lliurex)
# - Permisos de sudo para el usuario que uses
#

echo "Preparando equipo Lliurex para Ansible..."

#Repoman
sudo repoman-cli -e 2 -y
sudo apt update

# Instalar paquetes necesarios
sudo apt install -y ansible sshpass python3-apt openssh-client nmap ansible-lint

# Verificar instalación
echo "Ansible version:"
ansible --version

echo "Python3 version:"
python3 --version

# Para gestionar configuraciones más complejas
sudo apt install -y git tree vim

# Para monitorización
sudo apt install -y htop iotop

echo "Preparación completada. Ahora puedes:"
echo "1. Configurar SSH keys con los equipos cliente"
echo "2. Crear tu inventory.ini"
echo "3. Ejecutar ansible-playbook --ask-become-pass"
echo .
echo .
echo Crear estructura organizada
echo .

#Repoman
sudo repoman-cli -d 2 -y
