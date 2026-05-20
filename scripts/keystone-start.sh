#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [keystone] $*"; }

log "waiting for MariaDB..."
until python3 -c "
import pymysql, sys
try:
    pymysql.connect(host='mariadb', user='root', password='${MYSQL_ROOT_PASSWORD}')
    sys.exit(0)
except: sys.exit(1)
" 2>/dev/null; do sleep 2; done

log "creating keystone database..."
python3 -c "
import pymysql
c = pymysql.connect(host='mariadb', user='root', password='${MYSQL_ROOT_PASSWORD}')
cur = c.cursor()
cur.execute(\"CREATE DATABASE IF NOT EXISTS keystone\")
cur.execute(\"GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DB_PASS}'\")
cur.execute('FLUSH PRIVILEGES')
c.commit()
"

log "syncing database schema..."
keystone-manage db_sync

log "setting up fernet tokens..."
keystone-manage fernet_setup --keystone-user root --keystone-group root
keystone-manage credential_setup --keystone-user root --keystone-group root

log "bootstrapping keystone..."
keystone-manage bootstrap \
  --bootstrap-password "${ADMIN_PASS}" \
  --bootstrap-admin-url http://keystone:5000/v3/ \
  --bootstrap-internal-url http://keystone:5000/v3/ \
  --bootstrap-public-url http://keystone:5000/v3/ \
  --bootstrap-region-id RegionOne

log "starting keystone (uwsgi)..."
exec uwsgi \
  --http 0.0.0.0:5000 \
  --wsgi-file "$(which keystone-wsgi-public)" \
  --master --processes 2 --threads 1 \
  --lazy-apps \
  --pyargv "--config-file /etc/keystone/keystone.conf"
