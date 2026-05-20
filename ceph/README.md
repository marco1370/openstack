# Ceph Dev Cluster — Docker Compose

A minimal Ceph **Quincy (v17)** cluster for development and testing, running on Docker Compose inside WSL2.

> **Full documentation is in [`docs/`](docs/index.md)**  
> Prerequisites · Setup · S3 · RBD · Pools · Logging · Troubleshooting

## Architecture

| Container  | Role                | IP             | Exposed ports                       |
|------------|---------------------|----------------|-------------------------------------|
| `ceph-mon` | Monitor (quorum)    | 192.168.10.10  | —                                   |
| `ceph-mgr` | Manager (dashboard) | 192.168.10.11  | **8443** (Dashboard), **9283** (Prometheus) |
| `ceph-osd` | 3 × BlueStore OSD   | 192.168.10.21  | —                                   |
| `ceph-rgw` | RADOS Gateway (S3)  | 192.168.10.30  | **7480** (S3/Swift)                 |

All containers share a private bridge network `192.168.10.0/24`.

---

## Prerequisites

- **Docker Desktop** (Windows) with the WSL2 backend enabled
- **WSL2** Ubuntu distro (the one that holds `~/ceph-data`)
- `docker compose` v2 (`docker compose version` → v2.x)
- AWS CLI (`aws --version`) for S3 tests — optional but recommended

> **Why WSL2 only for data?**  
> Ceph requires a real Linux filesystem (xattr support, POSIX locks). Windows NTFS (`/mnt/d`) cannot host `ceph-data`; only the WSL2 ext4 volume works.

---

## Data layout

Compose files live on `D:\ceph` (Windows-accessible).  
Cluster state lives on the WSL2 ext4 filesystem:

| Host path (WSL2)       | Container mount       | Contents                          |
|------------------------|-----------------------|-----------------------------------|
| `~/ceph-data/etc/`     | `/etc/ceph`           | `ceph.conf`, admin/client keyrings |
| `~/ceph-data/lib/`     | `/var/lib/ceph`       | MON store, bootstrap keyrings     |
| `~/ceph-data/osd/`     | `/var/lib/ceph/osd`   | OSD bluestore dirs (`ceph-0/1/2`) |

Browse from Windows: `\\wsl$\Ubuntu\home\marco\ceph-data\`

---

## First-time setup

Run these steps once on a fresh machine (no `~/ceph-data` yet).

```bash
# 1. Clone / enter the project
cd ~/cloud/ceph          # or: cd /mnt/d/ceph

# 2. Create persistent data directories on the WSL2 filesystem
mkdir -p ~/ceph-data/{etc,lib,osd}
chmod 755 ~/ceph-data ~/ceph-data/{etc,lib,osd}

# 3. Pull images (optional, compose up does this too)
docker compose pull

# 4. Bring the cluster up
docker compose up -d

# 5. Watch startup — MON takes ~45 s, OSDs another ~30 s
docker compose logs -f
```

Wait until `ceph-mon` logs `HEALTH_OK` or run:

```bash
docker exec ceph-mon ceph status   # should show: health: HEALTH_OK
```

### Enable the Dashboard (first boot only)

The dashboard module needs to be activated and a user created after `ceph-mgr` starts:

```bash
docker exec ceph-mgr ceph mgr module enable dashboard
docker exec ceph-mgr ceph dashboard create-self-signed-cert
docker exec ceph-mgr bash -c "echo admin123 > /tmp/p && ceph dashboard ac-user-create admin -i /tmp/p administrator"
docker exec ceph-mgr ceph dashboard set-rgw-credentials
```

### Create the default S3 test user (first boot only)

```bash
docker exec ceph-rgw radosgw-admin user create \
  --uid=testuser --display-name="Test User" \
  --access-key=testaccess --secret=testsecret
```

---

## Day-to-day usage

### Start / stop

```bash
docker compose up -d          # start all services
docker compose down           # stop, keep ~/ceph-data intact
docker compose restart        # rolling restart
```

### Cluster health

```bash
docker exec ceph-mon ceph status          # overall status
docker exec ceph-mon ceph health detail   # verbose warnings/errors
docker exec ceph-mon ceph df              # pool/raw usage
docker exec ceph-mon ceph osd tree        # OSD layout
docker exec ceph-mon ceph osd stat        # OSD up/in counts
```

---

## Dashboard

| | |
|---|---|
| **URL** | https://localhost:8443 |
| **Username** | `admin` |
| **Password** | `admin123` |

Accept the self-signed certificate warning on first visit.

Features available out of the box:
- Cluster health, OSD map, pool list
- Object Gateway (RGW) view
- Prometheus metrics endpoint on `:9283`

---

## S3 / Object storage (RGW)

**Endpoint:** `http://localhost:7480`

```bash
export AWS_ACCESS_KEY_ID=testaccess
export AWS_SECRET_ACCESS_KEY=testsecret
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT=http://localhost:7480

# Create a bucket
aws --endpoint-url $ENDPOINT s3 mb s3://my-bucket

# Upload a file
aws --endpoint-url $ENDPOINT s3 cp ./file.txt s3://my-bucket/

# List objects
aws --endpoint-url $ENDPOINT s3 ls s3://my-bucket/

# Download a file
aws --endpoint-url $ENDPOINT s3 cp s3://my-bucket/file.txt ./file-copy.txt

# Delete a bucket (must be empty first)
aws --endpoint-url $ENDPOINT s3 rm s3://my-bucket --recursive
aws --endpoint-url $ENDPOINT s3 rb s3://my-bucket
```

### Manage RGW users

```bash
# Create a new user
docker exec ceph-rgw radosgw-admin user create \
  --uid=alice --display-name="Alice" \
  --access-key=alicekey --secret=alicesecret

# List users
docker exec ceph-rgw radosgw-admin user list

# Show a user's keys
docker exec ceph-rgw radosgw-admin user info --uid=alice

# Delete a user
docker exec ceph-rgw radosgw-admin user rm --uid=alice
```

---

## RBD — Block storage

```bash
# Create the rbd pool
docker exec ceph-mon ceph osd pool create rbd 32
docker exec ceph-mon rbd pool init rbd

# Create a 1 GiB image
docker exec ceph-mon rbd create --size 1024 rbd/myimage

# Inspect
docker exec ceph-mon rbd info rbd/myimage
docker exec ceph-mon rbd ls rbd

# Resize to 2 GiB
docker exec ceph-mon rbd resize --size 2048 rbd/myimage

# Delete
docker exec ceph-mon rbd rm rbd/myimage
```

> RBD images can be mapped as block devices on the host with `rbd map`, but that requires the `rbd` kernel module — not available in WSL2 by default.

---

## Pools

```bash
# List pools
docker exec ceph-mon ceph osd lspools

# Create a pool (32 PGs is enough for a 3-OSD dev cluster)
docker exec ceph-mon ceph osd pool create mypool 32

# Set replication factor
docker exec ceph-mon ceph osd pool set mypool size 3

# Delete a pool (requires confirmation flags)
docker exec ceph-mon ceph osd pool delete mypool mypool \
  --yes-i-really-really-mean-it
```

---

## Logs

```bash
docker compose logs ceph-mon          # monitor logs
docker compose logs ceph-osd          # OSD bootstrap + runtime logs
docker compose logs ceph-rgw          # gateway logs
docker compose logs -f                # follow all services
```

---

## Teardown and reset

```bash
# Stop containers (data preserved)
docker compose down

# Full wipe — destroys all cluster data
docker compose down
rm -rf ~/ceph-data
```

After a full wipe, repeat the **First-time setup** section.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ceph status` hangs or fails | MON not ready yet | Wait 60 s; check `docker compose logs ceph-mon` |
| `HEALTH_WARN: 1 mgr modules have failed` | Dashboard module not enabled | Run the Dashboard setup commands above |
| OSDs never come up | Data dir permissions wrong | `chmod 755 ~/ceph-data/osd` |
| S3 returns 403 | RGW user not created | Run the S3 test-user creation command |
| RGW container exits immediately | MON/OSD not healthy | Bring up mon+osd first; RGW depends on them |
| `HEALTH_WARN: clock skew` | WSL2 clock drift after suspend | `sudo hwclock -s` in WSL2 |

---

## Notes

- `osd-entrypoint.sh` bootstraps OSD directories on first boot and runs all 3 `ceph-osd` processes in the foreground — required because the upstream `OSD_DIRECTORY_SINGLE` script only activates pre-existing directories.
- All pools use an OSD-level CRUSH rule (`replicated_rule_osd`) so 3 replicas spread across the 3 OSDs on a single host rather than requiring 3 separate hosts.
- `privileged: true` on `ceph-osd` is required for BlueStore device management.
- **For production** use [cephadm](https://docs.ceph.com/en/latest/cephadm/) or [Rook-Ceph](https://rook.io/) instead.
