#!/usr/bin/env bash

USERS_CONF="users.conf"

[ -f "$USERS_CONF" ] || { echo "❌ users.conf not found"; exit 1; }

echo ""
printf "%-15s %-25s %-8s %-8s\n" "USERNAME" "GROUPS" "SAMBA" "WEBDAV"
echo "--------------------------------------------------------------"

while IFS=':' read -r username groups samba_access webdav_access; do
  [[ "$username" =~ ^#|^[[:space:]]*$ ]] && continue
  printf "%-15s %-25s %-8s %-8s\n" \
    "$(echo "$username" | tr -d '[:space:]')" \
    "$(echo "$groups" | tr -d '[:space:]')" \
    "$(echo "$samba_access" | tr -d '[:space:]')" \
    "$(echo "$webdav_access" | tr -d '[:space:]')"
done < "$USERS_CONF"

echo ""