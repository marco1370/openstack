# Pool Management

Ceph stores all data in **pools** — logical partitions with their own replication rules,  
PG counts, and CRUSH rules. This cluster ships with four RGW-managed pools; you create  
additional pools for RBD, CephFS, or arbitrary object workloads.

---

## Existing pools (post-setup)

```bash
docker exec ceph-mon ceph osd lspools
```

| Pool                    | Purpose                          |
|-------------------------|----------------------------------|
| `.mgr`                  | Manager module state             |
| `.rgw.root`             | RGW zone/region metadata         |
| `default.rgw.log`       | RGW access/usage logs            |
| `default.rgw.control`   | RGW control objects              |
| `default.rgw.meta`      | RGW user/bucket metadata         |
| `default.rgw.buckets.index` | Bucket object index          |
| `default.rgw.buckets.data`  | Actual object data           |

The RGW pools are created automatically when the gateway starts.

---

## Create a pool

```bash
# Syntax: ceph osd pool create <pool-name> <pg-num>
docker exec ceph-mon ceph osd pool create mypool 32

# Verify
docker exec ceph-mon ceph osd lspools | grep mypool
```

### Choosing the PG count

For a **3-OSD dev cluster**, `32` PGs per pool is appropriate.  
In production, the autoscaler handles this automatically.

| Total OSDs | PGs per pool |
|------------|--------------|
| 3          | 32           |
| 5          | 64           |
| 10         | 128          |
| 20+        | 256+         |

Enable the PG autoscaler for automatic tuning:

```bash
docker exec ceph-mon ceph mgr module enable pg_autoscaler
docker exec ceph-mon ceph osd pool set mypool pg_autoscale_mode on
```

---

## Replication

### View current replication factor

```bash
docker exec ceph-mon ceph osd pool get mypool size
# size: 3

docker exec ceph-mon ceph osd pool get mypool min_size
# min_size: 2
```

- `size` — number of replicas written (default: 3)
- `min_size` — minimum replicas required to allow I/O (default: 2)

### Change the replication factor

```bash
# Set 3 replicas (default)
docker exec ceph-mon ceph osd pool set mypool size 3

# Set minimum replicas (I/O is blocked if fewer are available)
docker exec ceph-mon ceph osd pool set mypool min_size 2
```

> On a single-host dev cluster all OSDs are on the same host bucket, so the default  
> host-level CRUSH rule cannot place 3 replicas. The `osd-entrypoint.sh` already creates  
> an OSD-level CRUSH rule (`replicated_rule_osd`) to handle this.

### Apply the OSD-level CRUSH rule to a pool

```bash
# List available CRUSH rules
docker exec ceph-mon ceph osd crush rule ls

# Apply the OSD-level rule
docker exec ceph-mon ceph osd pool set mypool crush_rule replicated_rule_osd

# Verify
docker exec ceph-mon ceph osd pool get mypool crush_rule
# crush_rule: replicated_rule_osd
```

---

## Erasure coding (advanced)

Erasure-coded pools use less raw storage than replicated pools (e.g., k=2, m=1 uses 1.5× instead of 3×).  
Only useful once you have more OSDs.

```bash
# Create an erasure code profile (k=2 data chunks, m=1 parity)
docker exec ceph-mon ceph osd erasure-code-profile set myprofile k=2 m=1

# Create an erasure-coded pool
docker exec ceph-mon ceph osd pool create ec-pool 32 32 erasure myprofile

# Enable overwrites (required for RGW use)
docker exec ceph-mon ceph osd pool set ec-pool allow_ec_overwrites true
```

---

## Pool quotas

```bash
# Set a size quota (bytes)
docker exec ceph-mon ceph osd pool set-quota mypool max_bytes $((10 * 1024 * 1024 * 1024))   # 10 GiB

# Set an object count quota
docker exec ceph-mon ceph osd pool set-quota mypool max_objects 1000000

# View quotas
docker exec ceph-mon ceph osd pool get-quota mypool

# Remove quotas (set to 0 = unlimited)
docker exec ceph-mon ceph osd pool set-quota mypool max_bytes 0
docker exec ceph-mon ceph osd pool set-quota mypool max_objects 0
```

---

## Pool statistics

```bash
# Overall pool usage
docker exec ceph-mon ceph df detail

# PG distribution per pool
docker exec ceph-mon ceph osd pool stats mypool

# Autoscaler status
docker exec ceph-mon ceph osd pool autoscale-status
```

---

## Pool flags

```bash
# Mark a pool as application-type rbd / rgw / cephfs (best practice)
docker exec ceph-mon ceph osd pool application enable mypool rbd

# Check application tags
docker exec ceph-mon ceph osd pool application get mypool
```

---

## Delete a pool

Pool deletion is protected by two safety flags to prevent accidents.

```bash
# Step 1 — allow pool deletion cluster-wide (temporary)
docker exec ceph-mon ceph config set mon mon_allow_pool_delete true

# Step 2 — delete the pool (name must be typed twice)
docker exec ceph-mon ceph osd pool delete mypool mypool \
  --yes-i-really-really-mean-it

# Step 3 — re-enable the protection
docker exec ceph-mon ceph config set mon mon_allow_pool_delete false
```

> Deletion is **immediate and irreversible**. All objects in the pool are lost.

---

## CRUSH rules

```bash
# List all CRUSH rules
docker exec ceph-mon ceph osd crush rule ls

# Show a specific rule
docker exec ceph-mon ceph osd crush rule dump replicated_rule_osd

# Create a simple OSD-level rule (already done by osd-entrypoint.sh)
docker exec ceph-mon ceph osd crush rule create-simple \
  replicated_rule_osd default osd firstn

# Dump the full CRUSH map (binary → text)
docker exec ceph-mon bash -c \
  "ceph osd getcrushmap -o /tmp/crushmap.bin && \
   crushtool -d /tmp/crushmap.bin -o /tmp/crushmap.txt && \
   cat /tmp/crushmap.txt"
```
