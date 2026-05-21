#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [glance] $*"; }

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
cur.execute("CREATE DATABASE IF NOT EXISTS glance")
cur.execute("GRANT ALL ON glance.* TO 'glance'@'%%' IDENTIFIED BY '%s'" % os.environ['GLANCE_DB_PASS'])
cur.execute("FLUSH PRIVILEGES")
c.commit()
print("glance database ready")
PYEOF

mkdir -p /var/log/glance
log "waiting for MariaDB..."
until python3 /tmp/wait_db.py; do sleep 2; done

log "creating glance database..."
python3 /tmp/init_db.py

log "waiting for keystone..."
until curl -sf http://keystone:5000/v3/ &>/dev/null; do sleep 3; done

log "registering glance in keystone..."
export OS_AUTH_URL=http://keystone:5000/v3
export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=${ADMIN_PASS}
export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3

openstack project list | grep -q service || openstack project create --domain default service
openstack user show glance &>/dev/null || \
  openstack user create --domain default --password "${GLANCE_PASS}" glance
openstack role assignment list --user glance --project service | grep -q admin || \
  openstack role add --project service --user glance admin
openstack service list | grep -q image || \
  openstack service create --name glance --description "OpenStack Image" image
openstack endpoint list --service image --region RegionOne | grep -q public || {
  openstack endpoint create --region RegionOne image public   http://glance:9292
  openstack endpoint create --region RegionOne image internal http://glance:9292
  openstack endpoint create --region RegionOne image admin    http://glance:9292
}

log "syncing glance database..."
glance-manage db_sync

log "starting glance-api..."
exec glance-api --config-file /etc/glance/glance-api.conf
