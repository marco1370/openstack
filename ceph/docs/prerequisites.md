# Prerequisites

This document covers everything you need installed and configured before bringing up the Ceph cluster.

---

## 1. Docker Desktop (Windows)

Install Docker Desktop for Windows with the **WSL2 backend** enabled.

- Download: https://www.docker.com/products/docker-desktop
- During installation choose **"Use the WSL 2 based engine"**
- After install, open **Settings → Resources → WSL Integration** and enable integration for your Ubuntu distro

Verify:

```bash
docker version
# Client: Docker Engine - Community
# Server: Docker Desktop
```

---

## 2. Docker Compose v2

Docker Compose v2 ships as a Docker CLI plugin (`docker compose`, not `docker-compose`).  
It is bundled with Docker Desktop — no separate install needed.

Verify:

```bash
docker compose version
# Docker Compose version v2.x.x
```

> If you see `docker-compose: command not found` you are on v1. Upgrade Docker Desktop.  
> The project uses `docker compose` (v2 syntax) throughout.

---

## 3. WSL2 Ubuntu

All cluster **data must live on the WSL2 ext4 filesystem** — not on the Windows NTFS drive.  
Ceph requires POSIX extended attributes (`xattr`) and advisory locks that NTFS cannot provide.

Verify WSL2 is running:

```powershell
# In PowerShell (Windows)
wsl --status
# Default Version: 2
```

Verify you are inside WSL2 (not WSL1):

```bash
# In your WSL2 shell
uname -r
# Should contain "microsoft" and end in "-WSL2"
# e.g. 5.15.167.4-microsoft-standard-WSL2
```

If your distro is on WSL1, convert it:

```powershell
wsl --set-version Ubuntu 2
```

---

## 4. AWS CLI (optional — for S3 testing)

The AWS CLI is the easiest way to interact with the RGW S3 endpoint.

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y awscli

# Verify
aws --version
# aws-cli/2.x.x Python/3.x ...
```

Alternatively use any S3-compatible client: `s3cmd`, `rclone`, `mc` (MinIO client), `boto3`, etc.

---

## 5. Port availability

Ensure the following ports are free on `localhost` before starting:

| Port | Service               |
|------|-----------------------|
| 7480 | RGW S3/Swift endpoint |
| 8443 | Ceph Dashboard (HTTPS)|
| 9283 | Prometheus metrics    |

Check for conflicts:

```bash
ss -tlnp | grep -E '7480|8443|9283'
# No output = ports are free
```

---

## Summary checklist

- [ ] Docker Desktop installed, WSL2 backend enabled
- [ ] `docker compose version` shows v2.x
- [ ] WSL2 Ubuntu distro active (not WSL1)
- [ ] `~/ceph-data` will be created on the ext4 filesystem (not `/mnt/d`)
- [ ] Ports 7480, 8443, 9283 are free
- [ ] AWS CLI installed (optional)
