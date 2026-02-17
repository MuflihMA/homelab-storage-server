#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
USERS_CONF="users.conf"
PASSWD_FILE="webdav/users.passwd"

die()  { echo "❌ $1" >&2; exit 1; }
log()  { echo "▶ $1"; }

# ---------- pre-flight ----------
[ -f "$ENV_FILE" ]    || die ".env not found"
[ -f "$USERS_CONF" ]  || die "users.conf not found"
command -v htpasswd >/dev/null || die "htpasswd not installed (apt install apache2-utils)"

# ---------- input ----------
if [ $# -lt 1 ]; then
  echo "Usage: $0 <username> [groups] [samba:yes|no] [webdav:yes|no]"
  echo ""
  echo "Examples:"
  echo "  $0 alice                          # default: groups=storage, samba=yes, webdav=no"
  echo "  $0 alice storage|finance yes yes  # akses dua group, samba + webdav"
  echo "  $0 bob finance no yes             # webdav only"
  exit 1
fi

USERNAME="$1"
GROUPS="${2:-storage}"
SAMBA_ACCESS="${3:-yes}"
WEBDAV_ACCESS="${4:-no}"

# username validation
if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  die "Invalid username. Use lowercase letters, numbers, underscore or dash."
fi

# duplicate check
if grep -q "^${USERNAME}:" "$USERS_CONF"; then
  die "User '$USERNAME' already exists in users.conf"
fi

# ---------- password ----------
read -s -p "Password for $USERNAME: " PASSWORD; echo
read -s -p "Confirm password: " CONFIRM; echo
[ "$PASSWORD" = "$CONFIRM" ] || die "Passwords do not match"
[ -n "$PASSWORD" ]           || die "Password cannot be empty"

PASSVAR="SAMBA_${USERNAME^^}_PASSWORD"

# ---------- update users.conf ----------
echo "${USERNAME}:${GROUPS}:${SAMBA_ACCESS}:${WEBDAV_ACCESS}" >> "$USERS_CONF"
log "users.conf updated"

# ---------- update .env ----------
echo "${PASSVAR}=${PASSWORD}" >> "$ENV_FILE"
log ".env updated"

# ---------- apply ke container yang sedang jalan (tanpa restart) ----------
if docker ps --format '{{.Names}}' | grep -q "^samba$"; then
  if [ "$SAMBA_ACCESS" = "yes" ]; then
    log "Applying Samba user directly to running container..."

    # buat linux user di container
    docker exec samba sh -c "id $USERNAME &>/dev/null || useradd -M -s /sbin/nologin $USERNAME" 2>/dev/null || true

    # buat samba user
    docker exec -i samba sh -c "printf '%s\n%s\n' '$PASSWORD' '$PASSWORD' | smbpasswd -a -s $USERNAME" 2>/dev/null || true
    docker exec samba smbpasswd -e "$USERNAME" 2>/dev/null || true

    # join groups
    IFS='|' read -ra GROUP_LIST <<< "$GROUPS"
    for grp in "${GROUP_LIST[@]}"; do
      grp=$(echo "$grp" | tr -d '[:space:]')
      [ -z "$grp" ] && continue
      docker exec samba sh -c "getent group $grp &>/dev/null || groupadd $grp"
      docker exec samba usermod -aG "$grp" "$USERNAME"
    done

    log "  ✅ Samba user '$USERNAME' live (no restart needed)"
  fi
else
  log "  ⚠ Samba container not running — user will be created on next 'docker-compose up -d'"
fi

# ---------- webdav ----------
if [ "$WEBDAV_ACCESS" = "yes" ]; then
  mkdir -p webdav
  if [ ! -f "$PASSWD_FILE" ]; then
    htpasswd -cbB "$PASSWD_FILE" "$USERNAME" "$PASSWORD"
  else
    htpasswd -bB "$PASSWD_FILE" "$USERNAME" "$PASSWORD"
  fi
  log "WebDAV user '$USERNAME' added to $PASSWD_FILE"

  if docker ps --format '{{.Names}}' | grep -q "^webdav$"; then
    docker restart webdav
    log "  ✅ WebDAV container restarted (file reload)"
  fi
fi

echo ""
echo "✅ User '$USERNAME' successfully added"
echo "   Groups  : $GROUPS"
echo "   Samba   : $SAMBA_ACCESS"
echo "   WebDAV  : $WEBDAV_ACCESS"