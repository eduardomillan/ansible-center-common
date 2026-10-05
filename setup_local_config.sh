#!/bin/bash
# Setup Local Configuration for Ansible Project
# This script helps create user-specific local configuration files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Ansible Project - Local Setup"
echo "=========================================="
echo ""

# Create password_ENV.txt if it doesn't exist
if [ ! -f "$SCRIPT_DIR/password_ENV.txt" ]; then
    echo "📝 Creating password_ENV.txt..."
    cp "$SCRIPT_DIR/password_ENV.txt.example" "$SCRIPT_DIR/password_ENV.txt"
    chmod 600 "$SCRIPT_DIR/password_ENV.txt"
    echo "✅ Created password_ENV.txt (mode 600)"
    echo "   Please edit it with your credentials:"
    echo "   vim $SCRIPT_DIR/password_ENV.txt"
else
    echo "⏭️  password_ENV.txt already exists"
fi

# Create .vault_pass if it doesn't exist
if [ ! -f "$SCRIPT_DIR/.vault_pass" ]; then
    echo ""
    echo "🔐 Creating .vault_pass..."
    read -sp "Enter Ansible Vault password: " vault_pass
    echo ""
    echo "$vault_pass" > "$SCRIPT_DIR/.vault_pass"
    chmod 600 "$SCRIPT_DIR/.vault_pass"
    echo "✅ Created .vault_pass (mode 600)"

    # Test vault password
    echo ""
    echo "Testing vault password..."
    if ansible-vault view "$SCRIPT_DIR/inventories/vault_secrets.yml" --vault-password-file="$SCRIPT_DIR/.vault_pass" > /dev/null 2>&1; then
        echo "✅ Vault password is correct!"
    else
        echo "❌ Vault password test failed. Please run this script again."
        rm "$SCRIPT_DIR/.vault_pass"
        exit 1
    fi
else
    echo "⏭️  .vault_pass already exists"
fi

# Create ansible.cfg.local if user wants
echo ""
echo "📋 Would you like to create ansible.cfg.local for custom settings? (y/n)"
read -r -t 5 response || response="n"
if [[ "$response" =~ ^[Yy]$ ]]; then
    if [ ! -f "$SCRIPT_DIR/ansible.cfg.local" ]; then
        cat > "$SCRIPT_DIR/ansible.cfg.local" <<'CFGEOF'
# Local Ansible Configuration Overrides
# This file is NOT versioned and specific to your environment

# Uncomment to use your local vault password file
# [defaults]
# vault_password_file = .vault_pass

# Uncomment to set specific SSH key
# [defaults]
# private_key_file = ~/.ssh/id_rsa

# Uncomment for custom forks setting (parallel execution)
# [defaults]
# forks = 20

# Add any other local customizations here
CFGEOF
        echo "✅ Created ansible.cfg.local"
        echo "   Edit it to customize your Ansible configuration:"
        echo "   vim $SCRIPT_DIR/ansible.cfg.local"
    else
        echo "⏭️  ansible.cfg.local already exists"
    fi
else
    echo "⏭️  Skipped ansible.cfg.local creation"
fi

echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit your local files with credentials:"
echo "   vim $SCRIPT_DIR/password_ENV.txt"
echo ""
echo "2. Test connectivity to your Ansible hosts:"
echo "   export ANSIBLE_REMOTE_USER='your_username'"
echo "   ansible all -i inventories/inventory.ini -m ping --ask-pass"
echo ""
echo "3. Source password_ENV.txt if you want to avoid re-entering password:"
echo "   source $SCRIPT_DIR/password_ENV.txt"
echo ""
echo "4. Run a playbook:"
echo "   ansible-playbook playbooks/change-hostname/change_host_name.yml \\"
echo "     -i inventories/inventory.ini \\"
echo "     -e 'ansible_remote_user=your_username' \\"
echo "     -e 'host_name=new-hostname' \\"
echo "     --ask-pass"
echo ""
