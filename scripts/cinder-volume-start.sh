#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [cinder-volume] $*"; }

log "waiting for cinder-api..."
until curl -sf http://cinder-api:8776/ &>/dev/null; do sleep 3; done

log "starting cinder-volume (Ceph RBD backend)..."
exec cinder-volume --config-file /etc/cinder/cinder.conf
