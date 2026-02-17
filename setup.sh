#!/usr/bin/env bash
set -euo pipefail

set -a
source .env
set +a

log()  { echo "▶ $1"; }
warn() { echo "⚠ $1"; }
die()  { echo "❌ $1" >&2; exit 1; }

# ---------- validasi env ----------
[ -n "${SAMBA_STORAGE_PATH:-}" ]  || die "SAMBA_STORAGE_PATH not set in .env"
[ -n "${WEBDAV_STORAGE_PATH:-}" ] || die "WEBDAV_STORAGE_PATH not set in .env"

# ---------- buat folder storage di host ----------
log "Creating storage directories..."

# Samba — folder per share/group, sesuaikan dengan smb.conf
sudo mkdir -p "${SAMBA_STORAGE_PATH}/storage"
# sudo mkdir -p "${SAMBA_STORAGE_PATH}/finance"   # uncomment jika ada share finance

# WebDAV
sudo mkdir -p "${WEBDAV_STORAGE_PATH}"

# ---------- set permission di host ----------
log "Setting folder permissions..."

# Samba folders: writable by current user (container pakai uid yang sama)
sudo chown -R "${USER}:${USER}" "${SAMBA_STORAGE_PATH}"
sudo chmod -R 2775 "${SAMBA_STORAGE_PATH}"

# WebDAV folder
sudo chown -R "${USER}:${USER}" "${WEBDAV_STORAGE_PATH}"
sudo chmod -R 755 "${WEBDAV_STORAGE_PATH}"

# ---------- setup webdav initial user ----------
log "Setting up WebDAV passwd file..."

mkdir -p webdav

if [ ! -s webdav/users.passwd ]; then
  log "Creating WebDAV users from users.conf..."
  FIRST_WEBDAV_USER=true
  WEBDAV_COUNT=0

  while IFS=':' read -r username groups samba_access webdav_access; do
    # skip komentar, baris kosong, dan separator
    [[ "$username" =~ ^#|^[[:space:]]*$|^-+$ ]] && continue
    username=$(echo "$username" | tr -d '[:space:]')
    webdav_access=$(echo "$webdav_access" | tr -d '[:space:]')

    if [ "$webdav_access" = "yes" ]; then
      PASSVAR="SAMBA_${username^^}_PASSWORD"
      PASSWORD="${!PASSVAR:-}"
      if [ -n "$PASSWORD" ]; then
        if [ "$FIRST_WEBDAV_USER" = true ]; then
          htpasswd -cbB webdav/users.passwd "$username" "$PASSWORD"
          FIRST_WEBDAV_USER=false
        else
          htpasswd -bB webdav/users.passwd "$username" "$PASSWORD"
        fi
        log "  ✅ WebDAV user '$username' created"
        WEBDAV_COUNT=$((WEBDAV_COUNT + 1))
      else
        warn "  No password env var SAMBA_${username^^}_PASSWORD found for '$username', skipping"
      fi
    fi
  done < users.conf

  if [ "$WEBDAV_COUNT" -eq 0 ]; then
    warn "Tidak ada WebDAV user yang dibuat!"
    warn "Pastikan users.conf punya user aktif dengan webdav=yes DAN password-nya ada di .env"
    warn "Contoh users.conf: mamuflih:admins|storage:yes:yes"
    warn "Contoh .env: SAMBA_MAMUFLIH_PASSWORD=yourpassword"
  fi
fi

log "✅ Setup selesai"
log "👉 Jalankan: docker-compose build && docker-compose up -d"