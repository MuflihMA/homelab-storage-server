#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
TEMPLATE_FILE="samba/smb.conf.template"
OUTPUT_FILE="samba/smb.conf"

# ---------- helpers ----------
die() {
  echo "❌ $1" >&2
  exit 1
}

info() {
  echo "▶ $1"
}

# ---------- pre-flight checks ----------
[ -f "$ENV_FILE" ] || die ".env file not found"
[ -f "$TEMPLATE_FILE" ] || die "smb.conf.template not found"

command -v envsubst >/dev/null || die "envsubst not installed"
command -v sed >/dev/null || die "sed not installed"

# ---------- input validation ----------
if [ $# -ne 1 ]; then
  die "Usage: $0 <username>"
fi

USERNAME="$1"

# username rules (safe for Samba + Linux)
if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  die "Invalid username. Use lowercase letters, numbers, underscore or dash."
fi

# ---------- load env ----------
set -a
source "$ENV_FILE"
set +a

# ---------- required env vars ----------
[ -n "${SAMBA_USERS:-}" ] || die "SAMBA_USERS not set in .env"

PASSVAR="SAMBA_${USERNAME^^}_PASSWORD"

# ---------- duplicate user check ----------
IFS=',' read -ra USERS <<< "$SAMBA_USERS"
for u in "${USERS[@]}"; do
  if [ "$u" = "$USERNAME" ]; then
    die "User '$USERNAME' already exists in SAMBA_USERS"
  fi
done

# ---------- password handling ----------
if ! grep -q "^$PASSVAR=" "$ENV_FILE"; then
  info "Password env var $PASSVAR not found, prompting…"
  read -s -p "Enter password for $USERNAME: " PASSWORD
  echo
  read -s -p "Confirm password: " CONFIRM
  echo

  [ "$PASSWORD" = "$CONFIRM" ] || die "Passwords do not match"
  [ -n "$PASSWORD" ] || die "Password cannot be empty"

  echo "$PASSVAR=$PASSWORD" >> "$ENV_FILE"
else
  info "Using existing password from .env ($PASSVAR)"
fi

# ---------- update SAMBA_USERS ----------
NEW_USERS="$SAMBA_USERS,$USERNAME"
sed -i "s/^SAMBA_USERS=.*/SAMBA_USERS=$NEW_USERS/" "$ENV_FILE"

# ---------- reload env & regenerate smb.conf ----------
set -a
source "$ENV_FILE"
set +a

info "Regenerating smb.conf..."
envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"

# ---------- final message ----------
echo
echo "✅ Samba user '$USERNAME' added successfully"
echo "👉 Next step:"
echo "   docker-compose up -d"


##!/usr/bin/env bash
# set -e

# if [ -z "$1" ]; then
#   echo "Usage: $0 <username>"
#   exit 1
#fi

# USERNAME="$1"
# PASSVAR="SAMBA_${USERNAME^^}_PASSWORD"

# set -a
# source .env
# set +a

# if grep -q "$USERNAME" <<< "$SAMBA_USERS"; then
#  echo "❌ User already exists"
#  exit 1
# fi

# read -s -p "Password for $USERNAME: " PASSWORD
# echo

# echo "$PASSVAR=$PASSWORD" >> .env
# sed -i "s/^SAMBA_USERS=.*/SAMBA_USERS=$SAMBA_USERS,$USERNAME/" .env

# set -a
# source .env
# set +a

# envsubst < samba/smb.conf.template > samba/smb.conf

# echo "✅ User $USERNAME added"
# echo "👉 Jalankan: docker compose up -d"
