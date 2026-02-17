# Homelab Storage Server (Samba + WebDAV)

Storage server berbasis Docker Compose dengan:

- **Samba (SMB)** — untuk akses dari Windows, Linux, macOS, Android
- **WebDAV** — untuk browser, file manager, dan akses HTTP-based
- **Folder terpisah** antara Samba dan WebDAV (tidak share volume)
- **User management** via script tanpa perlu restart container

---

## Arsitektur

```
homelab-storage-server/
├── docker-compose.yml
├── .env                      ← passwords (tidak di-commit)
├── .env.example
├── users.conf                ← single source of truth untuk user
├── setup.sh
├── add-user.sh               ← tambah user (Samba + WebDAV)
├── remove-user.sh
├── list-users.sh
├── samba/
│   ├── Dockerfile            ← custom image dengan entrypoint
│   ├── entrypoint.sh         ← buat user/group otomatis saat container start
│   └── smb.conf              ← konfigurasi share
└── webdav/
    └── users.passwd          ← htpasswd file (tidak di-commit)
```

Storage di host:

```
/srv/
├── samba/
│   ├── storage/              ← share utama (group: storage)
│   └── finance/              ← contoh share per grup (opsional)
└── webdav/                   ← data WebDAV
```

---

## Konsep User Management

Semua user didefinisikan di `users.conf` dengan format:

```
username:groups:samba:webdav
```

| Field    | Keterangan                                 |
|----------|--------------------------------------------|
| username | nama user, lowercase                       |
| groups   | grup dipisah pipe `\|`, contoh `storage\|admins` |
| samba    | `yes` / `no`                               |
| webdav   | `yes` / `no`                               |

Password disimpan di `.env` dengan format `SAMBA_USERNAME_PASSWORD=...`

Ketika container Samba start, `entrypoint.sh` membaca `users.conf` dan secara otomatis:
- Membuat Linux user di container
- Mendaftarkan Samba user (`smbpasswd`)
- Memasukkan user ke group yang sesuai
- Men-set permission folder share berdasarkan group

Untuk tambah user saat container **sudah berjalan**, `add-user.sh` akan menggunakan `docker exec` langsung — **tanpa downtime**.

---

## Requirements

```bash
sudo apt update
sudo apt install -y docker.io docker-compose apache2-utils
sudo systemctl enable --now docker
```

Tambahkan user ke docker group:

```bash
sudo usermod -aG docker $USER
# logout lalu login kembali
```

Disable Samba bawaan Ubuntu (jika ada):

```bash
sudo systemctl stop smbd
sudo systemctl disable smbd
```

---

## Setup Awal

### 1. Clone dan copy env

```bash
cp .env.example .env
nano .env
```

Isi minimal yang wajib diubah:

```env
SAMBA_STORAGE_PATH=/srv/samba
WEBDAV_STORAGE_PATH=/srv/webdav
WEBDAV_AUTH_TYPE=Basic

# Password untuk user pertama (mamuflih)
SAMBA_MAMUFLIH_PASSWORD=isi_password_kamu
```

### 2. Edit users.conf

Edit `users.conf` sesuai user awal kamu:

```
# username:groups:samba:webdav
mamuflih:admins|storage:yes:yes
```

### 3. Jalankan setup

```bash
chmod +x setup.sh add-user.sh remove-user.sh list-users.sh
./setup.sh
```

Script ini akan:
- Membuat folder `/srv/samba/storage` dan `/srv/webdav` di host
- Men-set permission folder
- Membuat file `webdav/users.passwd` untuk user pertama

### 4. Build dan jalankan

```bash
docker-compose up -d
```

Cek status:

```bash
docker-compose ps
docker-compose logs samba
```

---

## Tambah User Baru

```bash
./add-user.sh <username> [groups] [samba] [webdav]
```

**Contoh:**

```bash
# Tambah alice ke group storage, akses Samba saja (default)
./add-user.sh alice

# Tambah alice ke dua group, akses Samba dan WebDAV
./add-user.sh alice "storage|finance" yes yes

# Tambah bob, WebDAV only
./add-user.sh bob storage no yes
```

Script akan:
1. Meminta password (tidak ditampilkan di terminal)
2. Menyimpan password ke `.env`
3. Menambahkan baris ke `users.conf`
4. Langsung mengaplikasikan user ke container Samba yang berjalan (**tanpa restart/downtime**)
5. Jika WebDAV: update `users.passwd` dan restart WebDAV container

---

## Hapus User

```bash
./remove-user.sh alice
```

---

## List User

```bash
./list-users.sh
```

Output contoh:

```
USERNAME        GROUPS                    SAMBA    WEBDAV
--------------------------------------------------------------
mamuflih        admins|storage            yes      yes
alice           storage                   yes      no
bob             finance                   no       yes
```

---

## Akses

### Samba

**Windows:**

```
\\IP_SERVER\Storage
```

Buka File Explorer → klik address bar → ketik path di atas → masukkan username dan password.

**Linux (file manager):**

```
smb://IP_SERVER/Storage
```

**Linux (terminal mount):**

```bash
sudo mount -t cifs //IP_SERVER/Storage /mnt/storage \
  -o username=alice,password=yourpass,uid=$(id -u),gid=$(id -g)
```

**macOS (Finder):**

`Cmd + K` → ketik `smb://IP_SERVER/Storage`

### WebDAV

**Browser:**

```
http://IP_SERVER/
```

**Linux (terminal mount):**

```bash
sudo mount -t davfs http://IP_SERVER/ /mnt/webdav
```

**Windows:**

Map Network Drive → pilih "Connect to a website..." → masukkan `http://IP_SERVER/`

---

## Tambah Share Baru (Samba)

Misalnya ingin menambahkan share khusus untuk group `finance`:

### 1. Buat folder di host

```bash
sudo mkdir -p /srv/samba/finance
sudo chmod 2775 /srv/samba/finance
```

### 2. Tambahkan section di `samba/smb.conf`

```ini
[Finance]
   path = /shared/finance
   browseable = yes
   writable = yes
   valid users = @finance @admins
   create mask = 0660
   directory mask = 2770
   force group = finance
```

### 3. Reload konfigurasi Samba (tanpa restart)

```bash
docker exec samba smbcontrol smbd reload-config
```

### 4. Tambahkan user ke group finance

```bash
./add-user.sh bob finance yes no
```

---

## Manajemen Manual via docker exec

Jika diperlukan, bisa langsung exec ke container:

```bash
# Cek user Samba yang terdaftar
docker exec samba pdbedit -L

# Ganti password user
docker exec -i samba sh -c "printf 'newpass\nnewpass\n' | smbpasswd -s alice"

# Disable user sementara
docker exec samba smbpasswd -d alice

# Enable kembali
docker exec samba smbpasswd -e alice

# Reload smb.conf tanpa restart
docker exec samba smbcontrol smbd reload-config
```

---

## Security Notes

- **Jangan expose port 139/445 ke internet publik.** Samba hanya aman di jaringan lokal / VPN.
- **WebDAV berjalan di HTTP (plain).** Jika diakses dari luar LAN, wajib pakai reverse proxy dengan TLS (Nginx Proxy Manager / Traefik).
- File `.env` dan `webdav/users.passwd` sudah di-exclude di `.gitignore` — jangan pernah di-commit.
- Untuk keamanan lebih: pertimbangkan firewall (`ufw`) yang hanya izinkan akses ke port Samba dari subnet LAN saja.

---

## Catatan untuk API

Struktur ini sudah dirancang agar mudah di-wrap dengan API (misalnya FastAPI). Operasi yang perlu dilakukan API:

| Aksi           | Implementasi                                      |
|----------------|---------------------------------------------------|
| Tambah user    | Update `users.conf` + `.env`, `docker exec` Samba |
| Hapus user     | `smbpasswd -x`, `htpasswd -D`, update files       |
| List user      | Baca `users.conf`                                 |
| Ganti password | `smbpasswd` via exec, update `.env`               |

---

## Catatan Umum

Project ini cocok untuk:

- Home server / NAS sederhana
- Small office internal storage
- Lab environment

Tidak direkomendasikan untuk public service tanpa hardening tambahan.