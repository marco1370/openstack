#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [cinder-scheduler] $*"; }

mkdir -p /var/log/cinder
log "waiting for cinder-api..."
until curl -sf http://cinder-api:8776/ &>/dev/null; do sleep 3; done

log "starting cinder-scheduler..."
exec cinder-scheduler --config-file /etc/cinder/cinder.conf
