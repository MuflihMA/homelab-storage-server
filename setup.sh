#!/usr/bin/env bash
set -e

set -a
source .env
set +a

echo "📝 Generate smb.conf..."
envsubst < samba/smb.conf.template > samba/smb.conf

echo "🔐 Setup WebDAV initial user (if needed)..."
if [ ! -f webdav/users.passwd ]; then
  touch webdav/users.passwd
fi

if [ ! -s webdav/users.passwd ]; then
  echo "Create WebDAV user:"
  htpasswd -B webdav/users.passwd storage
fi

echo "✅ Setup selesai"
echo "👉 Jalankan: docker compose up -d"
