#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [nova-compute] $*"; }

mkdir -p /var/log/nova /var/lib/nova/tmp /var/lib/nova/instances

# Host-network containers need explicit /etc/hosts for Docker service names
for entry in \
  "192.168.20.10 mariadb" \
  "192.168.20.11 rabbitmq" \
  "192.168.20.12 memcached" \
  "192.168.20.20 keystone" \
  "192.168.20.21 glance" \
  "192.168.20.22 cinder-api" \
  "192.168.20.40 placement" \
  "192.168.20.41 nova-api" \
  "192.168.20.50 neutron-server"; do
  grep -q "${entry##* }" /etc/hosts || echo "$entry" >> /etc/hosts
done

log "waiting for libvirt socket..."
until [ -S /run/libvirt/libvirt-sock ]; do sleep 2; done

log "waiting for nova-api..."
until curl -sf http://nova-api:8774/ &>/dev/null; do sleep 3; done

log "waiting for neutron-server..."
until curl -sf http://neutron-server:9696/ &>/dev/null; do sleep 3; done

log "starting nova-compute..."
exec nova-compute --config-file /etc/nova/nova.conf
