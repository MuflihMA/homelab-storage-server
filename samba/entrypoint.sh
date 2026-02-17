#!/bin/bash
set -e

USERS_CONF="/etc/samba/users.conf"
SHARED_ROOT="/shared"

log()  { echo "▶ $1"; }
warn() { echo "⚠ $1"; }
die()  { echo "❌ $1" >&2; exit 1; }

[ -f "$USERS_CONF" ] || die "users.conf not found at $USERS_CONF"
[ -f "/etc/samba/smb.conf" ] || die "smb.conf not found"

# ---------- process each user ----------
while IFS=':' read -r username groups samba_access webdav_access; do
  # skip comment lines and empty lines
  [[ "$username" =~ ^#|^[[:space:]]*$ ]] && continue

  # trim whitespace
  username=$(echo "$username" | tr -d '[:space:]')
  groups=$(echo "$groups" | tr -d '[:space:]')
  samba_access=$(echo "$samba_access" | tr -d '[:space:]')

  # get password from env (format: SAMBA_USERNAME_PASSWORD)
  PASSVAR="SAMBA_${username^^}_PASSWORD"
  PASSWORD="${!PASSVAR:-}"

  if [ -z "$PASSWORD" ]; then
    warn "No password env var $PASSVAR found for user '$username', skipping"
    continue
  fi

  log "Setting up user: $username (groups: $groups)"

  # create linux user if not exists (needed for file ownership)
  if ! id "$username" &>/dev/null; then
    useradd -M -s /sbin/nologin "$username"
  fi

  # create and join groups
  IFS='|' read -ra GROUP_LIST <<< "$groups"
  for grp in "${GROUP_LIST[@]}"; do
    grp=$(echo "$grp" | tr -d '[:space:]')
    [ -z "$grp" ] && continue
    getent group "$grp" &>/dev/null || groupadd "$grp"
    usermod -aG "$grp" "$username"
  done

  # create samba user
  if [ "$samba_access" = "yes" ]; then
    # smbpasswd -a adds user, -s reads from stdin, -e enables
    printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -a -s "$username" 2>/dev/null || true
    smbpasswd -e "$username" 2>/dev/null || true
    log "  ✅ Samba user '$username' ready"
  fi

done < "$USERS_CONF"

# ---------- setup folder permissions per group ----------
log "Setting up share folder permissions..."

# for each share folder under /shared, set group ownership
# folder name should match group name
for dir in "$SHARED_ROOT"/*/; do
  [ -d "$dir" ] || continue
  grp=$(basename "$dir")

  if getent group "$grp" &>/dev/null; then
    chown -R root:"$grp" "$dir"
    chmod -R 2775 "$dir"   # setgid: new files inherit group
    log "  📁 $dir → group:$grp (2775)"
  else
    # shared folder not tied to a specific group — open permissions
    chmod -R 2775 "$dir"
    log "  📁 $dir → no group match, set 2775"
  fi
done

log "Starting Samba..."
exec /usr/sbin/smbd --foreground --no-process-group