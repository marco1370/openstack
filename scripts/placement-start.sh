#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [placement] $*"; }

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
cur.execute("CREATE DATABASE IF NOT EXISTS placement")
cur.execute("GRANT ALL ON placement.* TO 'placement'@'%%' IDENTIFIED BY 'placementpass'")
cur.execute("FLUSH PRIVILEGES")
c.commit()
print("placement database ready")
PYEOF

mkdir -p /var/log/placement
log "waiting for MariaDB..."
until python3 /tmp/wait_db.py; do sleep 2; done

log "creating placement database..."
python3 /tmp/init_db.py

log "waiting for keystone..."
until curl -sf http://keystone:5000/v3/ &>/dev/null; do sleep 3; done

log "registering placement in keystone..."
export OS_AUTH_URL=http://keystone:5000/v3
export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=${ADMIN_PASS}
export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3

openstack user show placement &>/dev/null || \
  openstack user create --domain default --password placementpass placement
openstack role assignment list --user placement --project service | grep -q admin || \
  openstack role add --project service --user placement admin
openstack service list | grep -q placement || \
  openstack service create --name placement --description "Placement API" placement
openstack endpoint list --service placement --region RegionOne | grep -q public || {
  openstack endpoint create --region RegionOne placement public   http://placement:8778
  openstack endpoint create --region RegionOne placement internal http://placement:8778
  openstack endpoint create --region RegionOne placement admin    http://placement:8778
}

log "syncing placement database..."
placement-manage db sync

log "installing waitress..."
/var/lib/kolla/venv/bin/pip install waitress -q

cat > /tmp/placement_serve.py << 'PYEOF'
import sys
sys.argv = ['placement-api']
from waitress import serve
from placement.wsgi import init_application
app = init_application()
serve(app, host='0.0.0.0', port=8778, threads=4)
PYEOF

log "starting placement-api (waitress)..."
exec /var/lib/kolla/venv/bin/python3 /tmp/placement_serve.py
