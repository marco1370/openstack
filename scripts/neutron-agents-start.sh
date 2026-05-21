#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [neutron-agents] $*"; }

mkdir -p /var/log/neutron /var/lib/neutron/tmp /etc/neutron/plugins/ml2

for entry in \
  "192.168.20.10 mariadb" \
  "192.168.20.11 rabbitmq" \
  "192.168.20.12 memcached" \
  "192.168.20.20 keystone" \
  "192.168.20.41 nova-api" \
  "192.168.20.50 neutron-server"; do
  grep -q "${entry##* }" /etc/hosts || echo "$entry" >> /etc/hosts
done

log "waiting for neutron-server..."
until curl -sf http://neutron-server:9696/ &>/dev/null; do sleep 3; done

log "starting neutron-dhcp-agent in background..."
neutron-dhcp-agent \
  --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/dhcp_agent.ini \
  --log-file /var/log/neutron/dhcp-agent.log &

# ── DHCP + NAT setup for provider network ─────────────────────────────────
# Wait for neutron-linuxbridge-agent to create the provider bridge, then:
#   1. Assign gateway IP to bridge
#   2. Start dnsmasq for DHCP
#   3. Set up MASQUERADE so VMs get internet via whatever host interface is up
PROVIDER_BRIDGE="brq6771abbe-81"
PROVIDER_CIDR="192.168.30.0/24"
PROVIDER_GW="192.168.30.1"
PROVIDER_RANGE_START="192.168.30.100"
PROVIDER_RANGE_END="192.168.30.200"

(
  log "waiting for provider bridge ${PROVIDER_BRIDGE}..."
  until ip link show "${PROVIDER_BRIDGE}" &>/dev/null; do sleep 3; done
  log "provider bridge up"

  # Assign GW IP to bridge
  ip addr show "${PROVIDER_BRIDGE}" | grep -q "${PROVIDER_GW}/" || \
    ip addr add "${PROVIDER_GW}/24" dev "${PROVIDER_BRIDGE}"

  # Connect Docker bridge and neutron bridge via veth pair (one L2 domain)
  ip link del veth-docker 2>/dev/null || true
  ip link add veth-docker type veth peer name veth-neutron
  ip link set veth-docker master br-d4d5fc11c40f
  ip link set veth-neutron master "${PROVIDER_BRIDGE}"
  ip link set veth-docker up
  ip link set veth-neutron up
  log "veth pair connected: br-d4d5fc11c40f <-> ${PROVIDER_BRIDGE}"

  # Kill stale dnsmasq
  pkill -f "dnsmasq-provider" 2>/dev/null || true
  sleep 1

  # Start dnsmasq with static MAC→IP reservations for all neutron ports
  dnsmasq \
    --interface="${PROVIDER_BRIDGE}" \
    --bind-interfaces \
    --no-hosts \
    --no-resolv \
    --dhcp-range="${PROVIDER_RANGE_START},${PROVIDER_RANGE_END},255.255.255.0,86400s" \
    --dhcp-option=3,${PROVIDER_GW} \
    --dhcp-option=6,8.8.8.8 \
    --dhcp-host=fa:16:3e:8e:71:d3,192.168.30.134 \
    --dhcp-host=fa:16:3e:e7:00:f0,192.168.30.125 \
    --dhcp-host=fa:16:3e:41:e6:06,192.168.30.161 \
    --pid-file=/var/run/dnsmasq-provider.pid \
    --log-dhcp \
    --log-facility=/var/log/neutron/dnsmasq-provider.log \
    --except-interface=lo
  log "dnsmasq started on ${PROVIDER_BRIDGE}"

  # MASQUERADE: VMs get internet via whatever host interface is the default route
  # MASQUERADE (unlike SNAT) auto-adapts when laptop's network/IP changes
  iptables -t nat -C POSTROUTING -s "${PROVIDER_CIDR}" ! -d "${PROVIDER_CIDR}" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "${PROVIDER_CIDR}" ! -d "${PROVIDER_CIDR}" -j MASQUERADE
  iptables -C FORWARD -i "${PROVIDER_BRIDGE}" -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 1 -i "${PROVIDER_BRIDGE}" -j ACCEPT
  iptables -C FORWARD -o "${PROVIDER_BRIDGE}" -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 2 -o "${PROVIDER_BRIDGE}" -j ACCEPT
  log "NAT/MASQUERADE rules set — VMs will follow host default route automatically"

  # Disable bridge-nf-call-iptables so VM traffic isn't filtered by iptables
  sysctl -w net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
  sysctl -w net.bridge.bridge-nf-call-ip6tables=0 2>/dev/null || true
  log "bridge-nf-call-iptables disabled"
) &

log "starting neutron-metadata-agent..."
exec neutron-metadata-agent \
  --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/metadata_agent.ini
