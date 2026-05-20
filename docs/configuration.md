# Configuration Reference

All config files live in `./config/` and are bind-mounted read-only into the relevant containers.

---

## keystone.conf

Identity service. Fernet tokens, SQL backend (MariaDB).

Key settings:
- Token provider: `fernet`
- Fernet key repository: `/etc/keystone/fernet-keys` (bind-mounted from `./data/keystone/fernet-keys`)
- Database: `mysql+pymysql://keystone:keystonepass@mariadb/keystone`
- Token cache: Memcached at `memcached:11211`

---

## glance-api.conf

Image service. Stores images as RBD objects in the Ceph `images` pool.

Key settings:
- Store backend: `rbd`
- RBD pool: `images`
- Ceph config: `/etc/ceph/ceph.conf`
- Ceph user: `glance` (keyring: `ceph.client.glance.keyring`)
- Database: `mysql+pymysql://glance:glancepass@mariadb/glance`

---

## nova.conf

Compute service. KVM/libvirt driver, Neutron networking, Placement integration.

Key settings:

| Section | Key | Value |
|---|---|---|
| `[DEFAULT]` | `compute_driver` | `libvirt.LibvirtDriver` |
| `[DEFAULT]` | `transport_url` | `rabbit://guest:guest@rabbitmq:5672/` |
| `[DEFAULT]` | `use_neutron` | `True` |
| `[libvirt]` | `virt_type` | `kvm` |
| `[libvirt]` | `connection_uri` | `qemu:///system` |
| `[libvirt]` | `disk_cachemodes` | `network=writeback` |
| `[vnc]` | `novncproxy_base_url` | `http://localhost:6080/vnc_lite.html` |
| `[vnc]` | `server_proxyclient_address` | `192.168.20.1` |
| `[scheduler]` | `discover_hosts_in_cells_interval` | `30` |

`my_ip` is written at container startup by `nova-compute-start.sh`.

---

## neutron.conf

Network service. ML2 core plugin, RabbitMQ transport, Nova port notifications.

Key settings:

| Section | Key | Value |
|---|---|---|
| `[DEFAULT]` | `core_plugin` | `ml2` |
| `[DEFAULT]` | `service_plugins` | *(empty — no L3 router)* |
| `[DEFAULT]` | `dhcp_agents_per_network` | `1` |
| `[DEFAULT]` | `notify_nova_on_port_*` | `True` |

---

## ml2_conf.ini

ML2 plugin config. Flat provider network only (no tenant networks, no L3).

| Section | Key | Value |
|---|---|---|
| `[ml2]` | `type_drivers` | `flat,vlan` |
| `[ml2]` | `tenant_network_types` | *(empty)* |
| `[ml2]` | `mechanism_drivers` | `linuxbridge` |
| `[ml2_type_flat]` | `flat_networks` | `provider` |
| `[securitygroup]` | `enable_security_group` | `False` |

Security groups are disabled. All VMs on the provider network share the same L2 segment without filtering.

---

## cinder.conf

Block storage. Single Ceph RBD backend, backup also to Ceph.

Key settings:

| Section | Key | Value |
|---|---|---|
| `[DEFAULT]` | `enabled_backends` | `ceph` |
| `[ceph]` | `volume_driver` | `cinder.volume.drivers.rbd.RBDDriver` |
| `[ceph]` | `rbd_pool` | `volumes` |
| `[ceph]` | `rbd_user` | `cinder` |
| `[ceph]` | `rbd_store_chunk_size` | `4` (MB) |
| `[ceph]` | `rbd_max_clone_depth` | `5` |
| `[backup]` | `backup_driver` | `cinder.backup.drivers.ceph.CephBackupDriver` |
| `[backup]` | `backup_ceph_pool` | `backups` |
| `[backup]` | `backup_ceph_user` | `cinder-backup` |

---

## placement.conf

Placement API. Resource inventory/allocation for Nova scheduling.

- Database: `mysql+pymysql://placement:placementpass@mariadb/placement`
- Auth: Keystone password auth, service project

---

## dhcp_agent.ini

DHCP agent. Uses dnsmasq via the linuxbridge interface driver.

- Interface driver: `linuxbridge`
- DHCP driver: `dnsmasq`

---

## metadata_agent.ini

Metadata proxy. Forwards instance metadata requests to Nova's metadata endpoint.

- Nova metadata host: `nova-api` (internal service network)
- Shared secret: `metasecret123` (matches `[neutron].metadata_proxy_shared_secret` in `nova.conf`)

---

## Ceph files

| File | Purpose |
|---|---|
| `ceph.conf` | Cluster config — fsid, MON address (192.168.10.10) |
| `ceph.client.glance.keyring` | Auth key for Glance → `images` pool |
| `ceph.client.cinder.keyring` | Auth key for Cinder + Nova → `volumes` pool |
| `ceph.client.cinder-backup.keyring` | Auth key for Cinder backup → `backups` pool |

Nova Compute also mounts `ceph.client.cinder.keyring` so it can attach Cinder volumes directly via RBD (live attachment without copying data through the API).

---

## Environment variables (`x-openstack-env`)

Defined once in `docker-compose.yml` under the `x-openstack-env` anchor and merged into every service:

| Variable | Default |
|---|---|
| `MYSQL_ROOT_PASSWORD` | `rootpass` |
| `ADMIN_PASS` | `adminpass` |
| `KEYSTONE_DB_PASS` | `keystonepass` |
| `GLANCE_DB_PASS` / `GLANCE_PASS` | `glancepass` |
| `CINDER_DB_PASS` / `CINDER_PASS` | `cinderpass` |
| `NOVA_DB_PASS` / `NOVA_PASS` | `novapass` |
| `PLACEMENT_DB_PASS` / `PLACEMENT_PASS` | `placementpass` |
| `NEUTRON_DB_PASS` / `NEUTRON_PASS` | `neutronpass` |

Change all of these before any non-local deployment.
