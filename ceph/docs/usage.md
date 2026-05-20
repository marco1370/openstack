# Day-to-Day Usage

Covers routine cluster operations: starting, stopping, restarting, and checking health.

---

## Start the cluster

```bash
docker compose up -d
```

All four services start in dependency order: MON → MGR → OSD → RGW.  
The cluster is ready when `ceph status` shows `HEALTH_OK` (takes ~2 minutes on cold boot).

```bash
docker exec ceph-mon ceph status
```

---

## Stop the cluster

```bash
docker compose down
```

This stops and removes the containers but **preserves all data** in `~/ceph-data`.  
The next `docker compose up -d` resumes from the saved state — no re-bootstrapping needed.

---

## Restart a single service

```bash
docker compose restart ceph-mgr    # restart just the manager
docker compose restart ceph-rgw    # restart just the gateway
docker compose restart             # restart all services
```

> After restarting `ceph-osd`, wait ~30 s for OSDs to come back `in` before running commands.

---

## Check cluster health

### Quick status

```bash
docker exec ceph-mon ceph status
```

Example healthy output:

```
  cluster:
    id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    health: HEALTH_OK

  services:
    mon: 1 daemons, quorum ceph-mon (age 5m)
    mgr: ceph-mgr(active, since 4m)
    osd: 3 osds: 3 up (since 3m), 3 in (since 3m)
    rgw: 1 daemon active (1 hosts, 1 zones)

  data:
    pools:   4 pools, 97 pgs
    objects: 237 objects, 1.6 KiB
    usage:   75 MiB used, 29 GiB / 29 GiB avail
    pgs:     97 active+clean
```

### Detailed health warnings

```bash
docker exec ceph-mon ceph health detail
```

### Disk usage

```bash
docker exec ceph-mon ceph df
```

Example output:

```
--- RAW STORAGE ---
CLASS    SIZE    AVAIL    USED  RAW USED  %RAW USED
hdd    29 GiB  29 GiB  75 MiB    75 MiB       0.25
TOTAL  29 GiB  29 GiB  75 MiB    75 MiB       0.25

--- POOLS ---
POOL                   ID  PGS  STORED  OBJECTS  USED  %USED  MAX AVAIL
.mgr                    1    1  577KiB        2  ...    0      9.6 GiB
.rgw.root               2   32  1.3KiB        4  ...    0      9.6 GiB
default.rgw.log         3   32  3.6KiB      175  ...    0      9.6 GiB
default.rgw.control     4   32     0B          8     0B     0      9.6 GiB
```

### OSD status

```bash
docker exec ceph-mon ceph osd tree
docker exec ceph-mon ceph osd stat
docker exec ceph-mon ceph osd dump | grep ^osd
```

### Monitor quorum

```bash
docker exec ceph-mon ceph mon stat
docker exec ceph-mon ceph quorum_status --format json-pretty
```

### Placement group (PG) status

```bash
docker exec ceph-mon ceph pg stat
docker exec ceph-mon ceph pg dump --format plain 2>/dev/null | grep -v "^pg_stat"
```

---

## Live watching

Poll cluster status every 3 seconds:

```bash
watch -n3 docker exec ceph-mon ceph status
```

Watch OSD in/out changes:

```bash
watch -n5 'docker exec ceph-mon ceph osd stat'
```

---

## Container lifecycle reference

| Goal                          | Command                                  |
|-------------------------------|------------------------------------------|
| Start all                     | `docker compose up -d`                   |
| Stop all (keep data)          | `docker compose down`                    |
| Stop all + remove volumes     | `docker compose down -v` *(don't use — see below)* |
| Restart one service           | `docker compose restart <service>`       |
| View running containers       | `docker compose ps`                      |
| View resource usage           | `docker stats ceph-mon ceph-mgr ceph-osd ceph-rgw` |
| Open shell in container       | `docker exec -it ceph-mon bash`          |
| Run a ceph command            | `docker exec ceph-mon ceph <subcommand>` |

> **Warning:** `docker compose down -v` removes named volumes. This project uses bind mounts (`~/ceph-data`), so `-v` won't wipe data — but avoid it as habit.

---

## Admin keyring

The admin keyring is written to `~/ceph-data/etc/ceph.client.admin.keyring` on first boot.  
It is shared across all containers via the bind mount.

To use `ceph` commands directly from WSL2 (without `docker exec`):

```bash
sudo apt install -y ceph-common    # install ceph CLI tools

# Point at the config and keyring on the host
export CEPH_CONF=~/ceph-data/etc/ceph.conf
export CEPH_KEYRING=~/ceph-data/etc/ceph.client.admin.keyring

ceph -c "$CEPH_CONF" -k "$CEPH_KEYRING" status
```
