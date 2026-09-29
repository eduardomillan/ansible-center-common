#!/bin/bash

# =============================================
# Descripción: Instala Pinta en máquinas remotas
# Uso: ./script.sh [usuario] [parámetros de ansible-playbook]
# Ejemplo: ./script.sh lliurex
# Ejemplo: ANSIBLE_REMOTE_USER=admin ./script.sh
# =============================================

# Variables
INVENTORY="${1:-../../inventories/inventory_millanets.ini}"
PLAYBOOK="${2:-instalar_pinta_advanced.yml}"

# Usar variable de entorno ANSIBLE_REMOTE_USER si está definida, sino usar parámetro
REMOTE_USER="${ANSIBLE_REMOTE_USER:-ubuntu}"

echo "Instalando Pinta..."
echo "Inventario: $INVENTORY"
echo "Usuario: $REMOTE_USER"
echo ""

# ========================================================================
# Ejecución
# ========================================================================
ansible-playbook \
  -i "$INVENTORY" \
  --user "$REMOTE_USER" \
  --ask-pass \
  -b \
  --ask-become-pass \
  "$PLAYBOOK" \
  "${@:3}"  # Pasar argumentos adicionales

