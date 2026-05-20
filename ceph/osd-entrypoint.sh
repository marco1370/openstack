#!/bin/bash
# Bootstrap and run Ceph OSDs inside Docker.
#
# The ceph-container OSD scripts expect pre-initialized OSD directories.
# This script creates them on first boot, then runs each ceph-osd in the
# foreground so Docker can track the container lifetime.

set -euo pipefail

CLUSTER="${CLUSTER:-ceph}"
OSD_COUNT="${OSD_COUNT:-3}"
OSD_BASE="/var/lib/ceph/osd"
ADMIN_KEY="/etc/ceph/${CLUSTER}.client.admin.keyring"
BOOTSTRAP_KEY="/var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring"

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') osd-entrypoint: $*"; }

# ── Wait for MON to be up ──────────────────────────────────────────────────
log "waiting for /etc/ceph/${CLUSTER}.conf ..."
until [ -f "/etc/ceph/${CLUSTER}.conf" ]; do sleep 2; done

log "waiting for admin keyring ..."
until [ -f "$ADMIN_KEY" ]; do sleep 2; done

log "waiting for cluster quorum ..."
until ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" health 2>/dev/null | grep -qE "HEALTH_(OK|WARN)"; do
  sleep 3
done

# ── Create bootstrap-osd keyring if missing ────────────────────────────────
if [ ! -f "$BOOTSTRAP_KEY" ]; then
  log "creating bootstrap-osd keyring ..."
  mkdir -p "/var/lib/ceph/bootstrap-osd"
  ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
    auth get-or-create client.bootstrap-osd \
    mon 'allow profile bootstrap-osd' \
    > "$BOOTSTRAP_KEY"
fi

# Create bootstrap-rgw keyring if missing (needed by ceph-rgw container)
if [ ! -f "/var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring" ]; then
  log "creating bootstrap-rgw keyring ..."
  mkdir -p "/var/lib/ceph/bootstrap-rgw"
  ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
    auth get-or-create client.bootstrap-rgw \
    mon 'allow profile bootstrap-rgw' \
    > "/var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring"
fi

# Suppress insecure global_id warning for dev clusters
ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
  config set mon auth_allow_insecure_global_id_reclaim false 2>/dev/null || true

# On a single-host dev cluster all OSDs share one host bucket, so the default
# host-level CRUSH chooseleaf can't place 3 replicas. Switch to OSD-level so
# replicas spread across the 3 OSDs on the same host.
if ! ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
    osd crush rule ls | grep -q "^replicated_rule_osd$"; then
  log "creating OSD-level CRUSH rule for single-host dev cluster ..."
  ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
    osd crush rule create-simple replicated_rule_osd default osd firstn
fi

# Move the ceph-osd host bucket into the default root
ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
  osd crush move ceph-osd root=default 2>/dev/null || true

# ── Bootstrap OSDs (idempotent on restart) ────────────────────────────────
for i in $(seq 0 $((OSD_COUNT - 1))); do
  OSD_DIR="${OSD_BASE}/${CLUSTER}-${i}"

  if [ -f "${OSD_DIR}/whoami" ]; then
    log "OSD ${i}: already initialised (id=$(cat "${OSD_DIR}/whoami")), skipping"
    continue
  fi

  log "OSD ${i}: bootstrapping ..."
  mkdir -p "${OSD_DIR}"

  OSD_FSID=$(cat /proc/sys/kernel/random/uuid)
  OSD_ID=$(ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" osd create "$OSD_FSID")
  log "OSD ${i}: got id=${OSD_ID} fsid=${OSD_FSID}"

  # Auth key for this OSD
  ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
    auth get-or-create "osd.${OSD_ID}" \
    osd 'allow *' mon 'allow rwx' \
    > "${OSD_DIR}/keyring"

  # Initialise bluestore filesystem
  ceph-osd --cluster "$CLUSTER" -i "$OSD_ID" \
    --mkfs \
    --osd-uuid "$OSD_FSID" \
    -k "${OSD_DIR}/keyring"

  echo "$OSD_ID"   > "${OSD_DIR}/whoami"
  echo "$OSD_FSID" > "${OSD_DIR}/fsid"

  # Register weight in CRUSH map
  ceph --cluster "$CLUSTER" -k "$ADMIN_KEY" \
    osd crush add "osd.${OSD_ID}" 1.0 host=ceph-osd 2>/dev/null || true

  log "OSD ${i}: ready as osd.${OSD_ID}"
done

# ── Start all OSDs ─────────────────────────────────────────────────────────
mapfile -t OSD_IDS < <(cat "${OSD_BASE}/${CLUSTER}-"*/whoami 2>/dev/null)
log "starting ${#OSD_IDS[@]} OSD(s): ${OSD_IDS[*]}"

LAST=$(( ${#OSD_IDS[@]} - 1 ))
for i in "${!OSD_IDS[@]}"; do
  ID="${OSD_IDS[$i]}"
  if [ "$i" -lt "$LAST" ]; then
    ceph-osd --cluster "$CLUSTER" -i "$ID" --foreground &
  else
    exec ceph-osd --cluster "$CLUSTER" -i "$ID" --foreground
  fi
done
