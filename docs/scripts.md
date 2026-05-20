# Start Scripts Reference

Each service has an entrypoint script in `/home/marco/openstack-scripts/` that is bind-mounted read-only into the container. The scripts are idempotent: they use `CREATE DATABASE IF NOT EXISTS`, `openstack user show ... || openstack user create ...`, etc., so they are safe to re-run on container restart.

## keystone-start.sh

1. Wait for MariaDB to accept connections (pymysql probe, 2 s interval)
2. Create `keystone` DB and grant `keystone@%`
3. Run `keystone-manage db_sync`
4. Set up fernet and credential key repositories
5. `keystone-manage bootstrap` — creates `admin` user, default domain, service catalog endpoints, `RegionOne`
6. Launch `uwsgi` on port 5000 (2 worker processes)

Bootstrap is not guarded by an existence check — running it against an already-bootstrapped DB is safe; it is idempotent.

## glance-start.sh

1. Wait for MariaDB
2. Create `glance` DB and grant `glance@%`
3. Wait for Keystone (`curl` probe)
4. Register Glance in Keystone:
   - Create `service` project if missing
   - Create `glance` user if missing (`openstack user show glance || ...`)
   - Assign `admin` role on `service` project
   - Create `image` service endpoint (public/internal/admin → `http://glance:9292`)
5. Run `glance-manage db_sync`
6. Launch `glance-api`

**Known issue (fixed):** the original existence check used `grep -q '^| glance'` which never matched because `openstack user list` output has UUID columns before the name. The corrected check is `openstack user show glance`.

## cinder-api-start.sh

1. Wait for MariaDB
2. Create `cinder` DB and grant `cinder@%`
3. Wait for Keystone
4. Register Cinder in Keystone:
   - Create `service` project if missing
   - Create `cinder` user if missing
   - Assign `admin` role
   - Create `volumev3` service and endpoints (`http://cinder-api:8776/v3/%(project_id)s`)
5. Run `cinder-manage db sync`
6. Launch `cinder-api`

Same `openstack user show` fix applies here.

## cinder-volume-start.sh

1. Wait for `cinder-api` to respond on port 8776
2. Launch `cinder-volume` (connects to RabbitMQ and Ceph RBD)

No DB or Keystone setup — that is owned by `cinder-api-start.sh`.

## Other scripts (not in `./scripts/` — on host only)

The following scripts are expected at `/home/marco/openstack-scripts/` on the Docker host but are not included in this repo. They follow the same pattern as the scripts above.

| Script | Service | Notes |
|---|---|---|
| `nova-api-start.sh` | os-nova-api | Creates `nova`, `nova_api`, `nova_cell0` DBs; registers Nova in Keystone; runs `nova-manage db sync` and cell mapping |
| `nova-conductor-start.sh` | os-nova-conductor | Waits for Nova API, launches `nova-conductor` |
| `nova-scheduler-start.sh` | os-nova-scheduler | Waits for Nova API, launches `nova-scheduler` |
| `nova-libvirt-start.sh` | os-nova-libvirt | Starts `libvirtd` daemon |
| `nova-compute-start.sh` | os-nova-compute | Writes `my_ip` to `nova.conf`, waits for libvirt socket, launches `nova-compute` |
| `neutron-server-start.sh` | os-neutron-server | Creates `neutron` DB; registers Neutron in Keystone; runs `neutron-db-manage upgrade heads`; launches `neutron-server` |
| `neutron-linuxbridge-agent-start.sh` | os-neutron-lb-agent | Launches `neutron-linuxbridge-agent` |
| `neutron-agents-start.sh` | os-neutron-agents | Launches DHCP agent + metadata proxy |
| `placement-start.sh` | os-placement | Creates `placement` DB; registers Placement in Keystone; runs `placement-manage db sync`; launches `placement-api` via uwsgi |
| `horizon-start.sh` | os-horizon | Configures `local_settings.py` (Keystone endpoint), runs `manage.py collectstatic`, starts Apache |

## Writing a new start script

Follow this pattern:

```bash
#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [<service>] $*"; }

# 1. Wait for dependency
log "waiting for MariaDB..."
until python3 -c "import pymysql,sys; pymysql.connect(...); sys.exit(0)" 2>/dev/null; do sleep 2; done

# 2. Idempotent DB setup
python3 -c "
import pymysql
c = pymysql.connect(...)
c.cursor().execute('CREATE DATABASE IF NOT EXISTS <db>')
...
"

# 3. Idempotent Keystone registration
openstack user show <svc> &>/dev/null || openstack user create ...

# 4. DB schema migration
<svc>-manage db sync

# 5. exec the daemon (PID 1)
exec <svc>-server --config-file /etc/.../<svc>.conf
```

Using `exec` as the final command ensures the daemon runs as PID 1 and receives Docker signals (`SIGTERM` on `docker stop`).
