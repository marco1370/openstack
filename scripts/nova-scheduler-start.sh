#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [nova-scheduler] $*"; }

mkdir -p /var/log/nova /var/lib/nova/tmp
log "waiting for nova-api..."
until curl -sf http://nova-api:8774/ &>/dev/null; do sleep 3; done

log "starting nova-scheduler..."
exec nova-scheduler --config-file /etc/nova/nova.conf
