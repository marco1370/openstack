#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [neutron-server] $*"; }

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
cur.execute("CREATE DATABASE IF NOT EXISTS neutron")
cur.execute("GRANT ALL ON neutron.* TO 'neutron'@'%%' IDENTIFIED BY 'neutronpass'")
cur.execute("FLUSH PRIVILEGES")
c.commit()
print("neutron database ready")
PYEOF

mkdir -p /var/log/neutron /var/lib/neutron/tmp
log "waiting for MariaDB..."
until python3 /tmp/wait_db.py; do sleep 2; done
python3 /tmp/init_db.py

log "waiting for keystone..."
until curl -sf http://keystone:5000/v3/ &>/dev/null; do sleep 3; done

log "registering neutron in keystone..."
export OS_AUTH_URL=http://keystone:5000/v3
export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=${ADMIN_PASS}
export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3

openstack user show neutron &>/dev/null || \
  openstack user create --domain default --password neutronpass neutron
openstack role assignment list --user neutron --project service 2>/dev/null | grep -q admin || \
  openstack role add --project service --user neutron admin
openstack service list | grep -q network || \
  openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint list --service network --region RegionOne | grep -q public || {
  openstack endpoint create --region RegionOne network public   http://neutron-server:9696
  openstack endpoint create --region RegionOne network internal http://neutron-server:9696
  openstack endpoint create --region RegionOne network admin    http://neutron-server:9696
}

log "syncing neutron database..."
neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head

log "starting neutron-server..."
exec neutron-server \
  --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini
