# Architecture

## Overview

OpenStack Bobcat (2023.2) running in Docker Compose with Kolla container images. Block and image storage are delegated to an external Ceph cluster. Compute uses KVM via libvirt.

## Service dependency graph

```
MariaDB ──────────────────────────────────────┐
RabbitMQ ─────────────────────────────────────┤
                                               ▼
                                          Keystone (5000)
                                         /    |    \    \
                                        /     |     \    \
                                    Glance Cinder  Nova  Neutron
                                   (9292)  API    API    Server
                                            (8776) (8774) (9696)
                                              |       |
                                         Placement  Nova
                                          (8778)  Conductor
                                                  Scheduler
                                                  Libvirt
                                                  Compute
                                                     |
                                               Neutron LB Agent
                                               Neutron Agents
                                               (DHCP+Metadata)
```

## Container map

| Container | Image | IP | Port(s) |
|---|---|---|---|
| os-mariadb | mariadb:10.11 | 192.168.20.10 | 3306 (internal) |
| os-rabbitmq | rabbitmq:3.12-management | 192.168.20.11 | 15672 |
| os-memcached | memcached:1.6-alpine | 192.168.20.12 | — |
| os-keystone | kolla/keystone:2023.2 | 192.168.20.20 | 5000 |
| os-glance | kolla/glance-api:2023.2 | 192.168.20.21 | 9292 |
| os-cinder-api | kolla/cinder-api:2023.2 | 192.168.20.22 | 8776 |
| os-cinder-volume | kolla/cinder-volume:2023.2 | 192.168.20.23 | — |
| os-cinder-scheduler | kolla/cinder-scheduler:2023.2 | 192.168.20.24 | — |
| os-placement | kolla/placement-api:2023.2 | 192.168.20.40 | 8778 |
| os-nova-api | kolla/nova-api:2023.2 | 192.168.20.41 | 8774, 8775, 6080 |
| os-nova-conductor | kolla/nova-conductor:2023.2 | 192.168.20.42 | — |
| os-nova-scheduler | kolla/nova-scheduler:2023.2 | 192.168.20.43 | — |
| os-nova-libvirt | kolla/nova-libvirt:2023.2 | host network | — |
| os-nova-compute | kolla/nova-compute:2023.2 | host network | — |
| os-neutron-server | kolla/neutron-server:2023.2 | 192.168.20.50 | 9696 |
| os-neutron-lb-agent | kolla/neutron-linuxbridge-agent:2023.2 | host network | — |
| os-neutron-agents | kolla/neutron-dhcp-agent:2023.2 | host network | — |
| os-horizon | kolla/horizon:2023.2 | 192.168.20.30 | 8080→80 |
| os-vm-net-anchor | busybox | 192.168.30.254 | — |

## Networks

| Docker network | Subnet | Purpose |
|---|---|---|
| `openstack-net` | 192.168.20.0/24 | Internal service-to-service communication |
| `ceph_ceph-net` (external) | 192.168.10.0/24 | Reach Ceph MON/OSD at 192.168.10.10 |
| `vm-provider-net` | 192.168.30.0/24 | VM flat provider network (bridged to host) |

Containers that need host networking (`nova-compute`, `nova-libvirt`, `neutron-lb-agent`, `neutron-agents`) use `network_mode: host` so they can manipulate bridge interfaces and KVM devices directly.

## Storage paths

| Data | Location |
|---|---|
| MariaDB data | Docker volume `mariadb-data` |
| RabbitMQ data | Docker volume `rabbitmq-data` |
| VM disk images (ephemeral) | Docker volume `nova-instances` → `/var/lib/nova/instances` |
| Glance images | Ceph RBD pool `images` |
| Cinder volumes | Ceph RBD pool `volumes` |
| Cinder backups | Ceph RBD pool `backups` |
| Keystone fernet keys | `./data/keystone/fernet-keys` (bind mount) |

## Startup order

Docker Compose `depends_on` conditions enforce this sequence:

1. MariaDB + RabbitMQ (infrastructure, health-checked)
2. Keystone (depends on MariaDB healthy)
3. Glance, Placement (depends on MariaDB + Keystone healthy)
4. Cinder API (depends on MariaDB + RabbitMQ + Keystone healthy)
5. Nova API (depends on MariaDB + RabbitMQ + Keystone + Placement healthy)
6. Nova Conductor, Scheduler (depends on Nova API healthy)
7. Nova Libvirt (no dependency, starts in parallel)
8. Nova Compute (depends on Nova API healthy + Nova Libvirt started)
9. Neutron Server (depends on MariaDB + RabbitMQ + Keystone healthy)
10. Neutron agents (depends on Neutron Server healthy)
11. Horizon (depends on Keystone healthy)
