#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
PASSWD_FILE="webdav/users.passwd"

die() {
  echo "❌ $1" >&2
  exit 1
}

[ -f "$ENV_FILE" ] || die ".env not found"
command -v htpasswd >/dev/null || die "htpasswd not installed"

set -a
source "$ENV_FILE"
set +a

[ -n "${WEBDAV_USERS:-}" ] || die "WEBDAV_USERS not set"

if [ $# -ne 1 ]; then
  die "Usage: $0 <username>"
fi

USERNAME="$1"

PASSVAR="WEBDAV_${USERNAME^^}_PASSWORD"

if ! grep -q "^$PASSVAR=" "$ENV_FILE"; then
  read -s -p "Enter WebDAV password for $USERNAME: " PASSWORD
  echo
  read -s -p "Confirm password: " CONFIRM
  echo
  [ "$PASSWORD" = "$CONFIRM" ] || die "Password mismatch"
  echo "$PASSVAR=$PASSWORD" >> "$ENV_FILE"
else
  PASSWORD="${!PASSVAR}"
fi

if [ ! -f "$PASSWD_FILE" ]; then
  htpasswd -cb "$PASSWD_FILE" "$USERNAME" "$PASSWORD"
else
  htpasswd -b "$PASSWD_FILE" "$USERNAME" "$PASSWORD"
fi

if ! echo "$WEBDAV_USERS" | grep -qw "$USERNAME"; then
  sed -i "s/^WEBDAV_USERS=.*/WEBDAV_USERS=$WEBDAV_USERS,$USERNAME/" "$ENV_FILE"
fi

echo "✅ WebDAV user '$USERNAME' added"
echo "👉 Run: docker-compose restart webdav"
