#!/bin/bash

# Script para ejecutar el playbook de instalación

echo "=== Instalador de Klavaro y KTouch para Lliurex 23 ==="

# Ejecutar el playbook
echo "Ejecutando playbook de instalación..."
ansible-playbook -i ../../inventories/inventory_inf3.ini --user me.millan playbook_klavaro_ktouch_install.yml --forks 7 --ask-pass --ask-become-pass

echo "=== Proceso completado ==="
