#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [keystone] $*"; }

# Write helper Python scripts to avoid bash/python quoting issues
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
cur.execute("CREATE DATABASE IF NOT EXISTS keystone")
cur.execute("GRANT ALL ON keystone.* TO 'keystone'@'%%' IDENTIFIED BY '%s'" % os.environ['KEYSTONE_DB_PASS'])
cur.execute("FLUSH PRIVILEGES")
c.commit()
print("keystone database ready")
PYEOF

mkdir -p /var/log/keystone
log "waiting for MariaDB..."
until python3 /tmp/wait_db.py; do sleep 2; done

log "creating keystone database..."
python3 /tmp/init_db.py

log "syncing database schema..."
keystone-manage db_sync

log "setting up fernet tokens..."
mkdir -p /etc/keystone/fernet-keys
keystone-manage fernet_setup --keystone-user root --keystone-group root
keystone-manage credential_setup --keystone-user root --keystone-group root

log "bootstrapping keystone..."
keystone-manage bootstrap \
  --bootstrap-password "${ADMIN_PASS}" \
  --bootstrap-admin-url http://keystone:5000/v3/ \
  --bootstrap-internal-url http://keystone:5000/v3/ \
  --bootstrap-public-url http://keystone:5000/v3/ \
  --bootstrap-region-id RegionOne

log "installing waitress..."
/var/lib/kolla/venv/bin/pip install waitress -q

cat > /tmp/keystone_serve.py << 'PYEOF'
import sys
sys.argv = ['keystone-api']   # clean argv so oslo.config doesn't see gunicorn flags
from waitress import serve
from keystone.server.wsgi import initialize_public_application
app = initialize_public_application()
serve(app, host='0.0.0.0', port=5000, threads=4)
PYEOF

log "starting keystone (waitress)..."
exec /var/lib/kolla/venv/bin/python3 /tmp/keystone_serve.py
