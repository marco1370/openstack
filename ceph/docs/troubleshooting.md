# Troubleshooting

Quick-reference table of common failures, followed by detailed diagnosis steps.

---

## Quick-reference table

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ceph status` hangs or times out | MON not ready yet | Wait 60 s; check `docker compose logs ceph-mon` |
| `HEALTH_WARN: 1 mgr modules have failed` | Dashboard module not enabled | Run the [dashboard setup commands](setup.md#step-5--enable-the-dashboard) |
| `HEALTH_WARN: clock skew detected` | WSL2 clock drift after host sleep | `sudo hwclock -s` inside WSL2 |
| OSDs never appear in `ceph osd tree` | Data dir permissions wrong | `chmod 755 ~/ceph-data/osd` |
| `ceph-osd` container exits immediately | MON not yet healthy when OSD started | `docker compose restart ceph-osd` after MON is healthy |
| S3 returns `403 Forbidden` | RGW user not created | Run the [S3 test-user creation command](setup.md#step-6--create-the-default-s3-test-user) |
| S3 returns `Connection refused` on `:7480` | `ceph-rgw` not running | `docker compose ps ceph-rgw`; check `docker compose logs ceph-rgw` |
| Dashboard `502 Bad Gateway` | `ceph-mgr` restarting or module crash | `docker compose restart ceph-mgr`; wait 30 s |
| Dashboard login fails | Wrong password or user not created | Re-run the `ac-user-create` command |
| `HEALTH_WARN: X pgs not active` | OSDs still peering | Wait 60 s after OSD start; check `ceph pg stat` |
| `HEALTH_ERR: no osds` | OSDs all `down` or `out` | Check `docker compose logs ceph-osd`; look for bootstrap errors |
| Pool `HEALTH_WARN: pool X has no application` | Pool created without `application enable` | `ceph osd pool application enable <pool> <type>` |
| `HEALTH_WARN: mons are allowing insecure global_id` | Missing `auth_allow_insecure_global_id_reclaim` config | Already suppressed by `osd-entrypoint.sh` — if it reappears, see below |
| Containers cannot resolve each other by hostname | Docker network issue | `docker compose down && docker compose up -d` |
| Data lost after `docker compose down -v` | Volume mounts pruned | Bind-mount data lives in `~/ceph-data` — only `rm -rf ~/ceph-data` destroys it |

---

## Detailed diagnosis

### MON does not reach HEALTH_OK

```bash
docker compose logs ceph-mon | tail -50
docker exec ceph-mon ceph mon stat
docker exec ceph-mon ceph quorum_status --format json-pretty
```

Common sub-causes:
- `~/ceph-data/etc` is not writable → `chmod 755 ~/ceph-data/etc`
- Previous cluster state conflicts → wipe and restart: `docker compose down && rm -rf ~/ceph-data && docker compose up -d`

---

### OSDs do not come up

```bash
docker compose logs ceph-osd | grep -E "ERROR|error|failed|FAILED"
docker exec ceph-mon ceph osd stat
docker exec ceph-mon ceph osd tree
```

Check that the OSD directories are owned correctly:

```bash
ls -la ~/ceph-data/osd/
```

If the `ceph-` subdirectories are owned by `root` from a previous run and the container user cannot write to them:

```bash
sudo chown -R 167:167 ~/ceph-data/osd/    # 167 = ceph uid inside the container
```

Alternatively wipe the OSD data only (preserves MON state):

```bash
docker compose stop ceph-osd ceph-rgw
rm -rf ~/ceph-data/osd/ceph-*
rm -f ~/ceph-data/lib/bootstrap-osd/ceph.keyring
docker compose start ceph-osd ceph-rgw
```

---

### Clock skew warning

WSL2 can lose clock sync after the Windows host sleeps.

```bash
# Check time offset
docker exec ceph-mon ceph health detail | grep clock

# Fix: sync WSL2 hardware clock
sudo hwclock -s

# Verify
date && docker exec ceph-mon date
```

For a persistent fix, install `systemd-timesyncd` or `ntpdate` in WSL2:

```bash
sudo apt install -y systemd-timesyncd
sudo systemctl enable --now systemd-timesyncd
```

---

### Insecure global_id warning

```bash
# Check if the warning is present
docker exec ceph-mon ceph health detail | grep global_id

# Suppress it (already done by osd-entrypoint.sh; re-apply if cluster was wiped)
docker exec ceph-mon ceph config set mon auth_allow_insecure_global_id_reclaim false
```

---

### S3 / RGW errors

**403 Forbidden:**

```bash
# Verify the user exists
docker exec ceph-rgw radosgw-admin user info --uid=testuser

# If missing, create it
docker exec ceph-rgw radosgw-admin user create \
  --uid=testuser --display-name="Test User" \
  --access-key=testaccess --secret=testsecret
```

**Empty response or no XML on GET `http://localhost:7480`:**

```bash
# Check RGW is running
docker compose ps ceph-rgw
docker compose logs ceph-rgw | tail -20

# Check port binding
ss -tlnp | grep 7480
```

**RGW starts but immediately restarts:**

```bash
docker compose logs ceph-rgw | grep -i "error\|fail\|exception"
```

Common cause: MON/OSD not healthy when RGW tried to connect. Restart once OSDs are up:

```bash
docker compose restart ceph-rgw
```

---

### Dashboard issues

**Cannot reach https://localhost:8443:**

```bash
docker compose ps ceph-mgr
docker compose logs ceph-mgr | tail -30

# Re-enable the module
docker exec ceph-mgr ceph mgr module enable dashboard
docker exec ceph-mgr ceph mgr module ls | grep dashboard
```

**Self-signed certificate error (curl):**

```bash
# Use -k to skip cert verification in dev
curl -sk https://localhost:8443/api/health/minimal
```

**Password reset:**

```bash
docker exec ceph-mgr bash -c \
  "echo newpassword > /tmp/p && ceph dashboard ac-user-set-password admin -i /tmp/p"
```

**RGW not showing in dashboard Object Gateway tab:**

```bash
docker exec ceph-mgr ceph dashboard set-rgw-credentials
# Then reload the browser page
```

---

### PGs stuck not-active / degraded

```bash
docker exec ceph-mon ceph pg stat
docker exec ceph-mon ceph health detail
docker exec ceph-mon ceph pg dump_stuck inactive
docker exec ceph-mon ceph pg dump_stuck unclean
```

For a dev cluster with 3 OSDs on one host, the most common cause is that the CRUSH rule is still host-level.  
Check:

```bash
docker exec ceph-mon ceph osd pool get .rgw.root crush_rule
# Should be: replicated_rule_osd (not replicated_rule)
```

Apply the OSD-level rule to all pools:

```bash
for pool in $(docker exec ceph-mon ceph osd lspools | awk '{print $2}'); do
  docker exec ceph-mon ceph osd pool set "$pool" crush_rule replicated_rule_osd
done
```

---

### Full wipe and clean restart

When everything is broken and you want a fresh cluster:

```bash
docker compose down
rm -rf ~/ceph-data
mkdir -p ~/ceph-data/{etc,lib,osd}
chmod 755 ~/ceph-data ~/ceph-data/{etc,lib,osd}
docker compose up -d
```

Then re-run the [first-time setup steps](setup.md).

---

## Getting more information

```bash
# Full cluster dump (large output — useful for bug reports)
docker exec ceph-mon ceph report > /tmp/ceph-report.json

# OSD crash history
docker exec ceph-mon ceph crash ls

# Detailed crash info
docker exec ceph-mon ceph crash info <crash-id>

# Archive a crash (silence the warning)
docker exec ceph-mon ceph crash archive <crash-id>
docker exec ceph-mon ceph crash archive-all
```
