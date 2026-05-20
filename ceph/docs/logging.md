# Logging

How to view, follow, and filter logs from each Ceph service running under Docker Compose.

---

## Docker Compose logs

### All services — follow

```bash
docker compose logs -f
```

### All services — last N lines

```bash
docker compose logs --tail=100
```

### Single service

```bash
docker compose logs ceph-mon          # Monitor
docker compose logs ceph-mgr          # Manager
docker compose logs ceph-osd          # OSD (all 3)
docker compose logs ceph-rgw          # RADOS Gateway
```

### Single service — follow

```bash
docker compose logs -f ceph-mon
docker compose logs -f ceph-osd
docker compose logs -f ceph-rgw
```

### With timestamps

```bash
docker compose logs -f --timestamps ceph-mon
```

### Since a specific time

```bash
docker compose logs --since="2024-01-15T10:00:00" ceph-osd
docker compose logs --since=30m ceph-rgw        # last 30 minutes
docker compose logs --since=1h                  # all services, last hour
```

---

## Runtime log levels

Ceph uses a numeric verbosity scale: `0` (errors only) → `20` (extremely verbose).  
Default is `0`/`1` for most subsystems.

### View current log levels

```bash
docker exec ceph-mon ceph config show osd.0 | grep log
docker exec ceph-mon ceph config show mon.ceph-mon | grep log
```

### Temporarily raise a subsystem's log level

Changes take effect immediately without restarting the daemon.

```bash
# OSD — increase objectstore and bluestore verbosity
docker exec ceph-mon ceph tell osd.0 injectargs \
  '--debug-osd=5 --debug-bluestore=5'

# MON — increase monitor log level
docker exec ceph-mon ceph tell mon.ceph-mon injectargs \
  '--debug-mon=5'

# RGW — increase gateway log level
docker exec ceph-mon ceph tell client.rgw.rgw1 injectargs \
  '--debug-rgw=5'

# Reset to defaults
docker exec ceph-mon ceph tell osd.0 injectargs \
  '--debug-osd=0 --debug-bluestore=0'
```

### Persist a log level in ceph.conf

Edit `~/ceph-data/etc/ceph.conf` and add to the relevant section:

```ini
[osd]
debug osd = 5
debug bluestore = 5

[mon]
debug mon = 5

[client.rgw]
debug rgw = 5
```

---

## Log file locations (inside containers)

By default the ceph-container image logs to `stdout`/`stderr` (captured by Docker).  
If a daemon writes to disk, logs land at:

| Daemon    | Log path (inside container)          |
|-----------|--------------------------------------|
| MON       | `/var/log/ceph/ceph-mon.ceph-mon.log`|
| MGR       | `/var/log/ceph/ceph-mgr.ceph-mgr.log`|
| OSD 0–2   | `/var/log/ceph/ceph-osd.{0,1,2}.log` |
| RGW       | `/var/log/ceph/ceph-client.rgw.*.log` |

```bash
# Read MON log directly inside the container
docker exec ceph-mon cat /var/log/ceph/ceph-mon.ceph-mon.log 2>/dev/null \
  || echo "logging to stdout (no file)"

# Tail OSD log
docker exec ceph-osd tail -f /var/log/ceph/ceph-osd.0.log 2>/dev/null
```

---

## Cluster audit log

Ceph records every administrative operation (pool create/delete, OSD in/out, etc.)  
in the cluster audit log:

```bash
docker exec ceph-mon ceph log last 50
```

Filter by severity:

```bash
docker exec ceph-mon ceph log last 20 warn
docker exec ceph-mon ceph log last 20 err
```

---

## Slow OSD / perf counters

```bash
# Dump all performance counters for an OSD
docker exec ceph-mon ceph tell osd.0 perf dump

# Watch a counter live (crude polling)
watch -n2 'docker exec ceph-mon ceph tell osd.0 perf dump | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(json.dumps(d[\"bluestore\"],indent=2))"'
```

---

## Prometheus metrics

The `ceph-mgr` container exposes a Prometheus scrape endpoint on port **9283**.

```bash
# Fetch all metrics (outputs thousands of lines)
curl -s http://localhost:9283/metrics | head -50

# Filter for specific metrics
curl -s http://localhost:9283/metrics | grep ceph_health_status
curl -s http://localhost:9283/metrics | grep ceph_osd_
```

Useful metrics:

| Metric                     | Description                        |
|----------------------------|------------------------------------|
| `ceph_health_status`       | 0=OK, 1=WARN, 2=ERR                |
| `ceph_osd_up`              | Number of OSDs that are up         |
| `ceph_osd_in`              | Number of OSDs that are in cluster |
| `ceph_pool_stored`         | Bytes stored per pool              |
| `ceph_pool_rd` / `_wr`     | Read/write ops per pool            |
| `ceph_rgw_req`             | RGW total requests                 |

---

## Watching health events live

```bash
# Continuously poll cluster health
watch -n3 'docker exec ceph-mon ceph health detail 2>/dev/null'

# Stream OSD events from compose logs
docker compose logs -f ceph-osd | grep -E "ERROR|WARN|starting|ready"

# Stream RGW access log (HTTP requests)
docker compose logs -f ceph-rgw | grep -E "GET|PUT|DELETE|POST"
```
