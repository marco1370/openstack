#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [horizon] $*"; }

VENV=/var/lib/kolla/venv
SETTINGS=/etc/openstack-dashboard/local_settings

log "configuring local_settings..."
sed -i 's|OPENSTACK_HOST = "127.0.0.1"|OPENSTACK_HOST = "keystone"|' "$SETTINGS"
sed -i 's|OPENSTACK_KEYSTONE_URL = "http://%s/identity/v3" % OPENSTACK_HOST|OPENSTACK_KEYSTONE_URL = "http://keystone:5000/v3"|' "$SETTINGS"
grep -q "^ALLOWED_HOSTS" "$SETTINGS" || echo "ALLOWED_HOSTS = ['*']" >> "$SETTINGS"
grep -q "^WEBROOT" "$SETTINGS" || echo "WEBROOT = '/'" >> "$SETTINGS"
grep -q "^SECRET_KEY" "$SETTINGS" || echo "SECRET_KEY = 'horizon-secret-$(hostname)'" >> "$SETTINGS"

# Force correct memcached location — append at end so it overrides any existing CACHES block
cat >> "$SETTINGS" << 'EOF'

# Override cache to point at the memcached container
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.PyMemcacheCache',
        'LOCATION': 'memcached:11211',
    }
}
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
EOF

# Link settings into Django's expected location
LOCAL_PY=$VENV/lib/python3.10/site-packages/openstack_dashboard/local/local_settings.py
ln -sf "$SETTINGS" "$LOCAL_PY"

log "installing waitress..."
$VENV/bin/pip install waitress -q

log "collecting static files..."
DJANGO_SETTINGS_MODULE=openstack_dashboard.settings \
  $VENV/bin/python3 $VENV/bin/manage.py collectstatic --noinput -c -v 0 2>/dev/null || true

log "waiting for keystone..."
until curl -sf http://keystone:5000/v3/ &>/dev/null; do sleep 3; done

cat > /tmp/horizon_serve.py << 'PYEOF'
import sys, os
sys.argv = ['horizon']
os.environ['DJANGO_SETTINGS_MODULE'] = 'openstack_dashboard.settings'
from waitress import serve
import django
django.setup()
from django.core.wsgi import get_wsgi_application
app = get_wsgi_application()
serve(app, host='0.0.0.0', port=80, threads=8)
PYEOF

log "starting horizon (waitress on :80)..."
exec $VENV/bin/python3 /tmp/horizon_serve.py
