# First-Time Setup

Follow these steps in order on a **fresh machine** (no existing `~/ceph-data`).  
If you are restarting an existing cluster, skip to [Day-to-day Usage](usage.md).

---

## Step 1 — Clone the project

```bash
# The Compose files live on the Windows-accessible path
cd /mnt/d/ceph          # Windows drive (files only, not data)
# or from WSL2 home:
cd ~/cloud/ceph
```

---

## Step 2 — Create persistent data directories

All cluster state must live on the **WSL2 ext4 filesystem** (not `/mnt/d`).

```bash
mkdir -p ~/ceph-data/{etc,lib,osd}
chmod 755 ~/ceph-data ~/ceph-data/{etc,lib,osd}
```

Resulting layout:

```
~/ceph-data/
├── etc/     →  /etc/ceph          (ceph.conf, keyrings)
├── lib/     →  /var/lib/ceph      (MON store, bootstrap keys)
└── osd/     →  /var/lib/ceph/osd  (OSD bluestore: ceph-0, ceph-1, ceph-2)
```

> These directories persist across `docker compose down` / `up` cycles.  
> Browse them from Windows at `\\wsl$\Ubuntu\home\marco\ceph-data\`

---

## Step 3 — Pull container images

This is optional — `compose up` pulls automatically — but doing it first gives a cleaner startup log.

```bash
docker compose pull
# Pulls: quay.io/ceph/daemon:latest-quincy
```

---

## Step 4 — Start the cluster

```bash
docker compose up -d
```

**Startup sequence** (takes ~2 minutes total):

| Phase | Container   | What happens                                  | Wait time |
|-------|-------------|-----------------------------------------------|-----------|
| 1     | `ceph-mon`  | Bootstraps cluster, writes `ceph.conf`        | ~45 s     |
| 2     | `ceph-mgr`  | Attaches to MON, loads modules               | ~15 s     |
| 3     | `ceph-osd`  | Bootstraps 3 BlueStore OSDs, registers CRUSH | ~30 s     |
| 4     | `ceph-rgw`  | Connects to MON, starts S3 listener          | ~15 s     |

Watch the logs as services come up:

```bash
docker compose logs -f
```

Or poll cluster status:

```bash
watch -n3 'docker exec ceph-mon ceph status 2>/dev/null || echo "not ready yet"'
```

The cluster is ready when you see:

```
  health: HEALTH_OK
  ...
  osd: 3 osds: 3 up (since ...), 3 in (since ...)
```

---

## Step 5 — Enable the Dashboard

The dashboard module must be activated once after the first boot.  
Run all commands after `ceph-mgr` is up:

```bash
# Enable the dashboard module
docker exec ceph-mgr ceph mgr module enable dashboard

# Generate a self-signed TLS certificate
docker exec ceph-mgr ceph dashboard create-self-signed-cert

# Create the admin user (password: admin123)
docker exec ceph-mgr bash -c \
  "echo admin123 > /tmp/p && ceph dashboard ac-user-create admin -i /tmp/p administrator"

# Point the dashboard at the RGW daemon
docker exec ceph-mgr ceph dashboard set-rgw-credentials
```

Verify the dashboard is reachable:

```bash
curl -sk https://localhost:8443/ | grep -o '<title>[^<]*</title>'
# <title>Ceph</title>
```

Open in browser: **https://localhost:8443** — accept the self-signed cert warning.

| Field    | Value      |
|----------|------------|
| Username | `admin`    |
| Password | `admin123` |

---

## Step 6 — Create the default S3 test user

```bash
docker exec ceph-rgw radosgw-admin user create \
  --uid=testuser \
  --display-name="Test User" \
  --access-key=testaccess \
  --secret=testsecret
```

Verify the RGW endpoint is responding:

```bash
curl -s http://localhost:7480
# <?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult ...
```

Test with AWS CLI:

```bash
AWS_ACCESS_KEY_ID=testaccess \
AWS_SECRET_ACCESS_KEY=testsecret \
aws --endpoint-url http://localhost:7480 s3 ls
# (empty — no buckets yet)
```

---

## What was created

After a successful first-time setup:

```
~/ceph-data/
├── etc/
│   ├── ceph.conf                       # cluster config
│   ├── ceph.client.admin.keyring       # admin credentials
│   └── ceph.mon.keyring
├── lib/
│   ├── mon/
│   │   └── ceph-ceph-mon/              # MON store (LevelDB)
│   ├── bootstrap-osd/
│   │   └── ceph.keyring
│   └── bootstrap-rgw/
│       └── ceph.keyring
└── osd/
    ├── ceph-0/                         # OSD 0 (BlueStore)
    ├── ceph-1/                         # OSD 1
    └── ceph-2/                         # OSD 2
```

---

## Re-running setup after a full wipe

If you deleted `~/ceph-data` and want a clean cluster:

```bash
docker compose down
rm -rf ~/ceph-data
# Then repeat Steps 2–6 above
```
