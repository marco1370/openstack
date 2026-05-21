#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [cinder-api] $*"; }

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
cur.execute("CREATE DATABASE IF NOT EXISTS cinder")
cur.execute("GRANT ALL ON cinder.* TO 'cinder'@'%%' IDENTIFIED BY '%s'" % os.environ['CINDER_DB_PASS'])
cur.execute("FLUSH PRIVILEGES")
c.commit()
print("cinder database ready")
PYEOF

mkdir -p /var/log/cinder /var/lib/cinder/tmp
log "waiting for MariaDB..."
until python3 /tmp/wait_db.py; do sleep 2; done

log "creating cinder database..."
python3 /tmp/init_db.py

log "waiting for keystone..."
until curl -sf http://keystone:5000/v3/ &>/dev/null; do sleep 3; done

log "registering cinder in keystone..."
export OS_AUTH_URL=http://keystone:5000/v3
export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=${ADMIN_PASS}
export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3

openstack project list | grep -q service || openstack project create --domain default service
openstack user show cinder &>/dev/null || \
  openstack user create --domain default --password "${CINDER_PASS}" cinder
openstack role assignment list --user cinder --project service | grep -q admin || \
  openstack role add --project service --user cinder admin
openstack service list | grep -q volumev3 || \
  openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
openstack endpoint list --service volumev3 --region RegionOne | grep -q public || {
  openstack endpoint create --region RegionOne volumev3 public   'http://cinder-api:8776/v3/%(project_id)s'
  openstack endpoint create --region RegionOne volumev3 internal 'http://cinder-api:8776/v3/%(project_id)s'
  openstack endpoint create --region RegionOne volumev3 admin    'http://cinder-api:8776/v3/%(project_id)s'
}

log "syncing cinder database..."
cinder-manage db sync

log "starting cinder-api..."
exec cinder-api --config-file /etc/cinder/cinder.conf
