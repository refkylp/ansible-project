#!/bin/bash
# This script retrieves the Ansible Vault password from AWS Parameter Store
# Used automatically by Ansible when vault_password_file is configured

PARAMETER_NAME="/ansible/phonebook/vault-password"
REGION="us-east-1"

# DEBUG - log that script was called
echo "DEBUG: get-vault-password.sh called at $(date)" >> /tmp/vault-debug.log

# Retrieve password from Parameter Store and output to stdout
PASSWORD=$(aws ssm get-parameter \
    --name "$PARAMETER_NAME" \
    --with-decryption \
    --region "$REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to retrieve vault password from Parameter Store" >&2
    echo "Make sure the parameter exists: $PARAMETER_NAME" >&2
    exit 1
fi

# Output password without trailing newline (critical for Ansible)
printf '%s' "$PASSWORD"