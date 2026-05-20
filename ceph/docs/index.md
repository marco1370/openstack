# Ceph Dev Cluster — Documentation

Reference documentation for the Docker Compose Ceph (Quincy) development cluster.

---

## Contents

| Document | Description |
|----------|-------------|
| [prerequisites.md](prerequisites.md) | Software requirements, WSL2 setup, port checklist |
| [setup.md](setup.md) | First-time cluster bootstrap, dashboard enable, S3 test user |
| [usage.md](usage.md) | Start/stop/restart, health checks, admin keyring |
| [s3.md](s3.md) | S3 bucket and object operations, user CRUD, boto3 examples |
| [rbd.md](rbd.md) | Block image create/resize/snapshot, WSL2 kernel limitation |
| [pools.md](pools.md) | Pool create/delete, replication, CRUSH rules, quotas |
| [logging.md](logging.md) | Docker Compose log commands, runtime log levels, Prometheus |
| [troubleshooting.md](troubleshooting.md) | Quick-reference failure table and detailed diagnosis steps |

---

## Cluster at a glance

| Container  | Role                | IP             | Host port                       |
|------------|---------------------|----------------|---------------------------------|
| `ceph-mon` | Monitor             | 192.168.10.10  | —                               |
| `ceph-mgr` | Manager / Dashboard | 192.168.10.11  | **8443** (UI), **9283** (Prometheus) |
| `ceph-osd` | 3 × BlueStore OSD   | 192.168.10.21  | —                               |
| `ceph-rgw` | RADOS Gateway (S3)  | 192.168.10.30  | **7480**                        |

---

## Quickstart

```bash
# First boot
mkdir -p ~/ceph-data/{etc,lib,osd} && chmod 755 ~/ceph-data ~/ceph-data/{etc,lib,osd}
docker compose up -d
docker exec ceph-mon ceph status                  # wait for HEALTH_OK

# Every day
docker compose up -d                              # start
docker compose down                               # stop (data kept)

# S3
AWS_ACCESS_KEY_ID=testaccess \
AWS_SECRET_ACCESS_KEY=testsecret \
aws --endpoint-url http://localhost:7480 s3 ls

# Dashboard
open https://localhost:8443   # admin / admin123
```
