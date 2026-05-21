#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [nova-api] $*"; }

cat > /tmp/wait_db.py << 'PYEOF'
import pymysql, sys, os
try:
    pymysql.connect(host='mariadb', user='root', password=os.environ['MYSQL_ROOT_PASSWORD'])
except Exception:
    sys.exit(1)
PYEOF

cat > /tmp/init_db.py << 'PYEOF'
import pymysql, os
c = pymysql.connect(host='mariadb', user='root', password=os.environ['MYSQL_ROOT_PASSWORD'])
cur = c.cursor()
for db in ('nova_api', 'nova'):
    cur.execute("CREATE DATABASE IF NOT EXISTS %s" % db)
    cur.execute("GRANT ALL ON %s.* TO 'nova'@'%%%%' IDENTIFIED BY 'novapass'" % db)
cur.execute("FLUSH PRIVILEGES")
c.commit()
print("nova databases ready")
PYEOF

mkdir -p /var/log/nova /var/lib/nova/tmp
log "waiting for MariaDB..."
until python3 /tmp/wait_db.py; do sleep 2; done
python3 /tmp/init_db.py

log "waiting for keystone..."
until curl -sf http://keystone:5000/v3/ &>/dev/null; do sleep 3; done

log "waiting for placement..."
until curl -sf http://placement:8778 &>/dev/null; do sleep 3; done

log "registering nova in keystone..."
export OS_AUTH_URL=http://keystone:5000/v3
export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=${ADMIN_PASS}
export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3

openstack user show nova &>/dev/null || \
  openstack user create --domain default --password novapass nova
openstack role assignment list --user nova --project service | grep -q admin || \
  openstack role add --project service --user nova admin
openstack service list | grep -q '| compute' || \
  openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint list --service compute --region RegionOne | grep -q public || {
  openstack endpoint create --region RegionOne compute public   http://nova-api:8774/v2.1
  openstack endpoint create --region RegionOne compute internal http://nova-api:8774/v2.1
  openstack endpoint create --region RegionOne compute admin    http://nova-api:8774/v2.1
}

log "syncing nova databases..."
nova-manage api_db sync
nova-manage db sync

log "setting up cells..."
nova-manage cell_v2 map_cell0 2>/dev/null || true
nova-manage cell_v2 list_cells | grep -q cell1 || \
  nova-manage cell_v2 create_cell --name=cell1 --verbose

log "starting nova-api..."
exec nova-api --config-file /etc/nova/nova.conf
