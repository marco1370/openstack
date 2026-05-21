#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [neutron-lb-agent] $*"; }

mkdir -p /var/log/neutron /var/lib/neutron/tmp /etc/neutron/plugins/ml2

for entry in \
  "192.168.20.10 mariadb" \
  "192.168.20.11 rabbitmq" \
  "192.168.20.12 memcached" \
  "192.168.20.20 keystone" \
  "192.168.20.50 neutron-server"; do
  grep -q "${entry##* }" /etc/hosts || echo "$entry" >> /etc/hosts
done

log "waiting for neutron-server..."
until curl -sf http://neutron-server:9696/ &>/dev/null; do sleep 3; done

# Detect the Docker bridge for vm-provider-net (192.168.30.0/24)
# vm-net-anchor ensures this bridge exists before we start
log "detecting provider bridge..."
PROVIDER_BRIDGE=""
for i in $(seq 1 30); do
  PROVIDER_BRIDGE=$(ip -o addr | awk '/192\.168\.30\./{print $2}' | head -1)
  [ -n "$PROVIDER_BRIDGE" ] && break
  # Also try route table
  PROVIDER_BRIDGE=$(ip route show | awk '/^192\.168\.30\.\//{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
  [ -n "$PROVIDER_BRIDGE" ] && break
  log "bridge not yet visible, retry $i/30..."
  sleep 2
done

log "provider bridge: ${PROVIDER_BRIDGE:-not found}"

cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini << EOF
[DEFAULT]
host = nova-compute
prevent_arp_spoofing = False

[linux_bridge]
$([ -n "$PROVIDER_BRIDGE" ] && echo "bridge_mappings = provider:$PROVIDER_BRIDGE" || echo "# WARNING: no provider bridge found")

[vxlan]
enable_vxlan = False

[securitygroup]
enable_security_group = False
firewall_driver = neutron.agent.firewall.NoopFirewallDriver
EOF

# WSL2 kernel doesn't support ebtables nat table; wrap ebtables to silently skip nat calls
cat > /usr/local/sbin/ebtables << 'EBTABLES_WRAPPER'
#!/bin/bash
for arg in "$@"; do [ "$arg" = "nat" ] && exit 0; done
exec /usr/sbin/ebtables "$@"
EBTABLES_WRAPPER
chmod +x /usr/local/sbin/ebtables
# Also wrap ebtables-restore used by some code paths
ln -sf /usr/local/sbin/ebtables /usr/local/sbin/ebtables-restore 2>/dev/null || true

log "starting neutron-linuxbridge-agent..."
exec neutron-linuxbridge-agent \
  --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/linuxbridge_agent.ini
