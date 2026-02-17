#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
USERS_CONF="users.conf"
PASSWD_FILE="webdav/users.passwd"

die() { echo "❌ $1" >&2; exit 1; }
log() { echo "▶ $1"; }

[ $# -ne 1 ] && die "Usage: $0 <username>"
USERNAME="$1"

grep -q "^${USERNAME}:" "$USERS_CONF" || die "User '$USERNAME' not found in users.conf"

# ---------- ambil info user ----------
LINE=$(grep "^${USERNAME}:" "$USERS_CONF")
SAMBA_ACCESS=$(echo "$LINE" | cut -d: -f3 | tr -d '[:space:]')
WEBDAV_ACCESS=$(echo "$LINE" | cut -d: -f4 | tr -d '[:space:]')

# ---------- hapus dari container Samba ----------
if [ "$SAMBA_ACCESS" = "yes" ] && docker ps --format '{{.Names}}' | grep -q "^samba$"; then
  docker exec samba smbpasswd -x "$USERNAME" 2>/dev/null || true
  docker exec samba userdel "$USERNAME" 2>/dev/null || true
  log "Samba user '$USERNAME' removed from container"
fi

# ---------- hapus dari WebDAV ----------
if [ "$WEBDAV_ACCESS" = "yes" ] && [ -f "$PASSWD_FILE" ]; then
  htpasswd -D "$PASSWD_FILE" "$USERNAME" 2>/dev/null || true
  log "WebDAV user '$USERNAME' removed"

  if docker ps --format '{{.Names}}' | grep -q "^webdav$"; then
    docker restart webdav
  fi
fi

# ---------- hapus dari users.conf ----------
sed -i "/^${USERNAME}:/d" "$USERS_CONF"
log "users.conf updated"

# ---------- hapus password dari .env ----------
PASSVAR="SAMBA_${USERNAME^^}_PASSWORD"
sed -i "/^${PASSVAR}=/d" "$ENV_FILE"
log ".env updated"

echo ""
echo "✅ User '$USERNAME' removed"