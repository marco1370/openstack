#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [nova-novncproxy] $*"; }

mkdir -p /var/log/nova

log "waiting for nova-api..."
until curl -sf http://nova-api:8774/ &>/dev/null; do sleep 3; done

log "starting nova-novncproxy..."
exec nova-novncproxy --config-file /etc/nova/nova.conf
