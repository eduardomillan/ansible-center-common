#!/bin/bash
# Create LliureX User - Secure Version
# Usage: ./do_create_lliurex_user.sh
# The script will prompt for SSH password and sudo password

# Defaults (can be overridden via environment variables or command line args)
INVENTORY="${1:-../../inventories/inventory_inf2_alu.ini}"
PLAYBOOK="${2:-create_user_basic.yml}"
REMOTE_USER="${ANSIBLE_REMOTE_USER:-ubuntu}"
FORKS="${ANSIBLE_FORKS:-20}"

# Use vault for default user password instead of hardcoding
# To use this script:
# 1. Set up vault password: ~/.vault_pass or use --ask-vault-pass
# 2. Run: ./do_create_lliurex_user.sh

echo "Creating LliureX user..."
echo "Using inventory: $INVENTORY"
echo "Using user: $REMOTE_USER"
echo ""

ansible-playbook \
  -i "$INVENTORY" \
  "$PLAYBOOK" \
  -u "$REMOTE_USER" \
  -b \
  --forks "$FORKS" \
  --ask-pass \
  --ask-become-pass \
  --vault-password-file=../../.vault_pass \
  "$@"
