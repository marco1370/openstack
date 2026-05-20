#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [cinder-api] $*"; }

log "waiting for MariaDB..."
until python3 -c "
import pymysql, sys
try:
    pymysql.connect(host='mariadb', user='root', password='${MYSQL_ROOT_PASSWORD}')
    sys.exit(0)
except: sys.exit(1)
" 2>/dev/null; do sleep 2; done

log "creating cinder database..."
python3 -c "
import pymysql
c = pymysql.connect(host='mariadb', user='root', password='${MYSQL_ROOT_PASSWORD}')
cur = c.cursor()
cur.execute(\"CREATE DATABASE IF NOT EXISTS cinder\")
cur.execute(\"GRANT ALL ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '${CINDER_DB_PASS}'\")
cur.execute('FLUSH PRIVILEGES')
c.commit()
"

log "waiting for keystone..."
until curl -sf http://keystone:5000/v3/ &>/dev/null; do sleep 3; done

log "registering cinder in keystone..."
export OS_AUTH_URL=http://keystone:5000/v3
export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=${ADMIN_PASS}
export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3

openstack project list | grep -q service || openstack project create --domain default service
openstack user list | grep -q '^| cinder' || \
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
