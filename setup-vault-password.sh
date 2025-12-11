#!/bin/bash
# This script stores the Ansible Vault password in AWS Parameter Store
# Run this ONCE to setup the vault password

PARAMETER_NAME="/ansible/phonebook/vault-password"
REGION="us-east-1"

echo "=== Setup Ansible Vault Password in AWS Parameter Store ==="
echo ""
echo "Enter your vault password (it will be hidden):"
read -s VAULT_PASSWORD

if [ -z "$VAULT_PASSWORD" ]; then
    echo "Error: Password cannot be empty!"
    exit 1
fi

echo ""
echo "Storing password in Parameter Store..."

aws ssm put-parameter \
    --name "$PARAMETER_NAME" \
    --value "$VAULT_PASSWORD" \
    --type "SecureString" \
    --description "Ansible Vault password for Phonebook project" \
    --region "$REGION" \
    --overwrite

if [ $? -eq 0 ]; then
    echo "✓ Password successfully stored in Parameter Store: $PARAMETER_NAME"
    echo "✓ You can now encrypt your vault file using:"
    echo "  ansible-vault encrypt group_vars/vault.yml"
    echo ""
    echo "✓ Ansible will automatically retrieve the password from Parameter Store"
else
    echo "✗ Failed to store password in Parameter Store"
    echo "Make sure you have proper IAM permissions for SSM Parameter Store"
    exit 1
fi
