# OpenStack Bobcat (2023.2) — Docker Compose + Ceph

![OpenStack](https://img.shields.io/badge/OpenStack-Bobcat%202023.2-red?logo=openstack)
![Docker Compose](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)
![Ceph](https://img.shields.io/badge/Storage-Ceph%20RBD-orange)
![Status](https://img.shields.io/badge/services-all%20healthy-brightgreen)

A production-style OpenStack Bobcat deployment running entirely in Docker Compose, using [Kolla](https://docs.openstack.org/kolla/latest/) container images and an external Ceph cluster for image (Glance) and block (Cinder) storage.

---

## 📋 Services

| Container | Role | Status | Port(s) |
|---|---|---|---|
| os-mariadb | MySQL-compatible database backend | healthy | 3306 (internal) |
| os-rabbitmq | AMQP message broker | healthy | 15672 (management) |
| os-memcached | Token / auth caching | up | — |
| os-keystone | Identity service (auth, service catalog) | healthy | 5000 |
| os-glance | Image service → Ceph RBD pool `images` | healthy | 9292 |
| os-placement | Placement API (resource inventory) | healthy | 8778 |
| os-nova-api | Compute API + noVNC proxy | healthy | 8774, 8775, 6080 |
| os-nova-conductor | Nova conductor | up | — |
| os-nova-scheduler | Nova scheduler | up | — |
| os-nova-libvirt | KVM / libvirt daemon | up | — |
| os-nova-compute | Compute worker (KVM) | up | — |
| os-cinder-api | Block storage API → Ceph RBD pool `volumes` | healthy | 8776 |
| os-cinder-scheduler | Cinder scheduler | up | — |
| os-cinder-volume | Cinder volume backend (Ceph RBD) | up | — |
| os-neutron-server | Network API | healthy | 9696 |
| os-neutron-lb-agent | Linuxbridge agent | up | — |
| os-neutron-agents | DHCP + metadata agents | up | — |
| os-horizon | Web dashboard | up | 8080 |
| os-vm-net-anchor | Forces Docker to create provider bridge | up | — |

---

## 🔧 Prerequisites

### Host requirements

- **OS**: Linux or Windows with WSL2 (Ubuntu 22.04 recommended)
- **Docker**: Docker Engine 24+ and Docker Compose v2
- **KVM**: `/dev/kvm` must be accessible from the host

  ```bash
  # Verify KVM is available
  $ ls -la /dev/kvm
  $ kvm-ok          # ubuntu: apt install cpu-checker
  ```

  > **WSL2 note**: nested virtualisation must be enabled. Add the following to `%USERPROFILE%\.wslconfig` and restart WSL:
  > ```ini
  > [wsl2]
  > nestedVirtualization=true
  > ```

- **Ceph cluster**: a running Ceph cluster reachable on the `ceph_ceph-net` Docker network (MON at `192.168.10.10`)

### Ceph keyrings

Place the following files in `./config/` before starting:

| File | Ceph pool |
|---|---|
| `config/ceph.conf` | Cluster config (fsid, MON host) |
| `config/ceph.client.glance.keyring` | `images` pool (Glance) |
| `config/ceph.client.cinder.keyring` | `volumes` pool (Cinder) |
| `config/ceph.client.cinder-backup.keyring` | `backups` pool (Cinder backup) |

### Start scripts

All service entrypoint scripts must exist at `/home/marco/openstack-scripts/`. The scripts handle first-run database creation, Keystone registration, and service launch.

---

## 🚀 Quick Start

```bash
# 1. Clone / enter the project directory
$ cd /mnt/d/openstack

# 2. Start all services
$ docker compose up -d

# 3. Watch health status (services become healthy within ~3 minutes)
$ watch -n5 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep os-'

# 4. All healthy — verify compute and network planes
$ docker exec os-keystone bash -c "
    export OS_AUTH_URL=http://keystone:5000/v3
    export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=adminpass
    export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
    export OS_IDENTITY_API_VERSION=3
    openstack compute service list
    openstack network agent list"
```

---

## 🔑 Credentials

| Service | URL | Username | Password |
|---|---|---|---|
| Horizon dashboard | http://localhost:8080 | admin | adminpass |
| Keystone API | http://localhost:5000/v3 | admin | adminpass |
| RabbitMQ management | http://localhost:15672 | guest | guest |

> Change passwords in `docker-compose.yml` under `x-openstack-env` before deploying to any non-local environment.

---

## 🖥️ VM Creation Walkthrough

Open a shell inside the Keystone container (it has the OpenStack CLI installed):

```bash
$ docker exec -it os-keystone bash
```

Set admin credentials:

```bash
$ export OS_AUTH_URL=http://keystone:5000/v3
$ export OS_PROJECT_NAME=admin
$ export OS_USERNAME=admin
$ export OS_PASSWORD=adminpass
$ export OS_USER_DOMAIN_NAME=Default
$ export OS_PROJECT_DOMAIN_NAME=Default
$ export OS_IDENTITY_API_VERSION=3
```

Verify available resources:

```bash
$ openstack image list
$ openstack flavor list
$ openstack network list
```

Boot a VM:

```bash
$ openstack server create \
    --image cirros \
    --flavor m1.tiny \
    --network provider \
    --wait \
    my-vm
```

Check the result:

```bash
$ openstack server list
$ openstack server show my-vm
```

The VM receives an IP from the `192.168.30.0/24` provider network. Access the console via noVNC at http://localhost:6080 or through Horizon.

---

## ⚙️ Configuration Files

| File | Purpose |
|---|---|
| `config/keystone.conf` | Identity service — fernet tokens, SQL backend |
| `config/glance-api.conf` | Image API — Ceph RBD store driver |
| `config/nova.conf` | Compute — libvirt driver, Neutron integration, Placement |
| `config/neutron.conf` | Network — ML2 plugin, RabbitMQ, Nova notifications |
| `config/ml2_conf.ini` | ML2: flat + vlan type drivers, linuxbridge mechanism |
| `config/cinder.conf` | Block storage — Ceph RBD backend, scheduler |
| `config/placement.conf` | Placement API — SQL backend, Keystone auth |
| `config/dhcp_agent.ini` | DHCP agent — interface driver, dnsmasq |
| `config/metadata_agent.ini` | Metadata proxy — Nova metadata endpoint |
| `config/ceph.conf` | Ceph cluster config (MON host, fsid) |
| `config/ceph.client.*.keyring` | Per-service Ceph authentication keyrings |

---

## 🌐 Networks

| Docker network | Subnet | Purpose |
|---|---|---|
| `openstack-net` | 192.168.20.0/24 | Internal service-to-service communication |
| `ceph_ceph-net` *(external)* | 192.168.10.0/24 | Connectivity to the Ceph MON/OSDs |
| `vm-provider-net` | 192.168.30.0/24 | VM provider network (flat, bridged to host) |

---

## 🐛 Troubleshooting

### Check container health

```bash
# All OpenStack containers and their health state
$ docker ps --format "table {{.Names}}\t{{.Status}}" | grep os-

# Tail logs for a specific service
$ docker logs os-glance --tail 80 -f
```

### HTTP 409 on Glance or Cinder startup

**Symptom**: container crash-loops with:
```
Conflict occurred attempting to store user - Duplicate entry found with name glance
(HTTP 409)
```

**Cause**: the start script attempted `openstack user create` even though the user already existed, because the existence check used a broken grep pattern:

```bash
# Before (broken) — never matches; format is "| <uuid> | glance | ..."
openstack user list | grep -q '^| glance' || openstack user create ...

# After (fixed) — directly queries Keystone for the user
openstack user show glance &>/dev/null || openstack user create ...
```

**Fix**: update `glance-start.sh` and `cinder-api-start.sh` in `/home/marco/openstack-scripts/`, then restart:

```bash
$ docker compose restart glance cinder-api
```

### Nova compute not scheduling VMs

```bash
$ docker exec os-keystone bash -c "
    export OS_AUTH_URL=http://keystone:5000/v3
    export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=adminpass
    export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
    export OS_IDENTITY_API_VERSION=3
    openstack compute service list"
```

All three services (`nova-scheduler`, `nova-conductor`, `nova-compute`) should show `enabled` / `up`. If `nova-compute` is down, check:

```bash
$ docker logs os-nova-compute --tail 50
$ docker logs os-nova-libvirt --tail 50
$ ls /dev/kvm   # must exist
```

### KVM unavailable on WSL2

```bash
# Check
$ ls /dev/kvm

# If missing, enable nested virtualisation in %USERPROFILE%\.wslconfig:
[wsl2]
nestedVirtualization=true
# Then: wsl --shutdown  (from PowerShell), reopen WSL
```

### Ceph connectivity

```bash
# From glance or cinder-volume container
$ docker exec os-glance ceph -c /etc/ceph/ceph.conf --id glance health
$ docker exec os-cinder-volume ceph -c /etc/ceph/ceph.conf --id cinder health
```

---

## 📚 Documentation

| Doc | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Service dependency graph, container map, network topology, startup order |
| [docs/configuration.md](docs/configuration.md) | Key settings for every config file and the env-var anchor |
| [docs/operations.md](docs/operations.md) | Day-2 runbook: start/stop, OpenStack CLI, Ceph checks, DB access, first-boot checklist |
| [docs/scripts.md](docs/scripts.md) | What each start script does and how to write a new one |
