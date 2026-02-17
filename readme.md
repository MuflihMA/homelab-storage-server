# Storage Server (Samba + WebDAV) with Docker Compose

Storage server sederhana berbasis Docker Compose di Ubuntu Server dengan:
- Samba (SMB) untuk Windows/Linux
- WebDAV untuk browser / file manager
- Satu folder data yang dishare ke dua service
- User management via script (.sh)

---

## Arsitektur

- OS: Ubuntu Server
- Container:
  - dperson/samba
  - bytemark/webdav
- Data disimpan di host (bind mount)

---

## Struktur Folder

```
storage-server/
├── docker-compose.yml
├── .env
├── .env.example
├── setup.sh
├── add-samba-user.sh
├── data/
├── samba/
│ ├── smb.conf.template
│ └── smb.conf
└── webdav/
└── users.passwd
```


---

## Requirement

```bash
sudo apt update
sudo apt install -y docker.io docker-compose apache2-utils
sudo systemctl enable --now docker
```

Tambahkan user ke docker group (opsional) :

```
sudo usermod -aG docker $USER
logout
```

### Disable Samba bawaan Ubuntu (kalau ada)
```
sudo systemctl stop smbd
sudo systemctl disable smbd
```

## Setup Awal
### Copy env
```bash
cp .env.example .env
nano .env
```

- Contoh `.env`:
```.env
STORAGE_PATH=./data

SAMBA_SHARE_NAME=Storage
SAMBA_USERS=storage
SAMBA_STORAGE_PASSWORD=storagepass

WEBDAV_AUTH_TYPE=Basic
```

## Setup Konfigurasi
```bash
chmod +x setup.sh
./setup.sh
```

## Jalankan Service
```bash
docker-compose up -d
```

- Cek status:
```bash
docker-compose ps
```

## Akses
### Samba
- Windows:
```pgsql
\\IP_SERVER\Storage
```
- Linux:
```cpp
smb://IP_SERVER/Storage
```

Login :
```nginx
storage / storagepass
```

### WebDAV
```cpp
http://IP_SERVER/
```
Login pakai user di `webdav/users.passwd`.

## Tambah User Samba
```bash
./add-samba-user.sh alice
docker-compose up -d
```

## Tambah User WebDAV
```bash
htpasswd -B webdav/users.passwd bob
docker-compose restart webdav
```

## Security Notes
Tambahkan ke `.gitignore`:
```bash
.env
samba/smb.conf
webdav/users.passwd
```
WebDAV berjalan di HTTP (tanpa TLS).
Gunakan HTTPS jika diakses dari internet publik.

## Catatan
Project ini cocok untuk:
- Home server
- Small office
- Internal storage
Tidak direkomendasikan untuk public service tanpa hardening tambahan.
