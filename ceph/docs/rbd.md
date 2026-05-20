# RBD — Block Storage

RADOS Block Device (RBD) provides thin-provisioned, copy-on-write block images backed by the Ceph cluster.  
In this dev setup, images live in a dedicated pool and are managed via the `rbd` CLI inside `ceph-mon`.

---

## Create the RBD pool

Do this once. The `rbd` pool name is conventional but you can use any name.

```bash
# Create pool with 32 PGs (appropriate for a 3-OSD dev cluster)
docker exec ceph-mon ceph osd pool create rbd 32

# Initialize the pool for RBD use
docker exec ceph-mon rbd pool init rbd

# Verify
docker exec ceph-mon ceph osd lspools | grep rbd
```

---

## Image operations

### Create an image

```bash
# 1 GiB image in the rbd pool
docker exec ceph-mon rbd create --size 1024 rbd/myimage

# 10 GiB image
docker exec ceph-mon rbd create --size 10240 rbd/bigdisk

# Specify features explicitly (for compatibility with older kernels)
docker exec ceph-mon rbd create --size 1024 \
  --image-feature layering \
  rbd/myimage
```

### List images

```bash
# List all images in the rbd pool
docker exec ceph-mon rbd ls rbd

# List with sizes
docker exec ceph-mon rbd ls -l rbd
```

Example output:

```
NAME      SIZE   PARENT  FMT  PROT  LOCK
bigdisk   10GiB          2
myimage   1GiB           2
```

### Inspect an image

```bash
docker exec ceph-mon rbd info rbd/myimage
```

Example output:

```
rbd image 'myimage':
        size 1 GiB in 256 objects
        order 22 (4 MiB objects)
        snapshot_count: 0
        id: 1b2c3d4e5f6a
        block_name_prefix: rbd_data.1b2c3d4e5f6a
        format: 2
        features: layering
        op_features:
        flags:
        create_timestamp: ...
        access_timestamp: ...
        modify_timestamp: ...
```

### Resize an image

RBD images can be grown online. Shrinking requires the `--allow-shrink` flag and risks data loss.

```bash
# Grow to 2 GiB
docker exec ceph-mon rbd resize --size 2048 rbd/myimage

# Verify
docker exec ceph-mon rbd info rbd/myimage | grep size

# Shrink (destructive — truncates data beyond new size)
docker exec ceph-mon rbd resize --size 512 rbd/myimage --allow-shrink
```

> After resizing, the filesystem inside the image (if any) must also be resized — `resize2fs`, `xfs_growfs`, etc.

### Delete an image

```bash
# Delete (fails if the image has snapshots — remove them first)
docker exec ceph-mon rbd rm rbd/myimage

# Force-remove including all snapshots
docker exec ceph-mon rbd snap purge rbd/myimage
docker exec ceph-mon rbd rm rbd/myimage
```

---

## Snapshots

```bash
# Create a snapshot
docker exec ceph-mon rbd snap create rbd/myimage@snap1

# List snapshots
docker exec ceph-mon rbd snap ls rbd/myimage

# Protect a snapshot (required before cloning)
docker exec ceph-mon rbd snap protect rbd/myimage@snap1

# Clone a snapshot into a new image
docker exec ceph-mon rbd clone rbd/myimage@snap1 rbd/myimage-clone

# Flatten a clone (make it independent of the parent snapshot)
docker exec ceph-mon rbd flatten rbd/myimage-clone

# Rollback an image to a snapshot (destroys writes after the snapshot)
docker exec ceph-mon rbd snap rollback rbd/myimage@snap1

# Unprotect and delete a snapshot
docker exec ceph-mon rbd snap unprotect rbd/myimage@snap1
docker exec ceph-mon rbd snap rm rbd/myimage@snap1

# Delete all snapshots
docker exec ceph-mon rbd snap purge rbd/myimage
```

---

## Exporting and importing images

```bash
# Export an image to a local file
docker exec ceph-mon rbd export rbd/myimage - > myimage.bin

# Import a local file as an RBD image
docker exec -i ceph-mon rbd import - rbd/restored < myimage.bin

# Export/import in diff format (only changed blocks — faster for incremental backup)
docker exec ceph-mon rbd export-diff rbd/myimage@snap1 - > myimage-diff.bin
```

---

## Mapping an image (Linux host — not WSL2)

On a standard Linux host with the `rbd` kernel module loaded, you can map an RBD image as a block device:

```bash
# On a real Linux host (NOT WSL2)
sudo rbd map rbd/myimage
# /dev/rbd0

sudo mkfs.ext4 /dev/rbd0
sudo mount /dev/rbd0 /mnt/myimage

# Unmap
sudo umount /mnt/myimage
sudo rbd unmap /dev/rbd0
```

### WSL2 limitation

> **`rbd map` does not work inside WSL2.**  
> The WSL2 kernel does not include the `rbd` kernel module. Running `sudo modprobe rbd` will fail.
>
> **Alternatives inside WSL2 / Windows:**
> - Use the RGW S3 interface for object-level access (see [s3.md](s3.md))
> - Use `rbd export` to pull an image file and mount it via loop device (WSL2 doesn't support loop either)
> - Run a full Linux VM (VirtualBox / Hyper-V) alongside Docker Desktop for kernel-module features

---

## RBD pool sizing reference

| OSDs | Recommended PGs per pool |
|------|--------------------------|
| 3    | 32–64                    |
| 5    | 64–128                   |
| 10+  | 128–256                  |

For this 3-OSD dev cluster, `32` PGs per pool is sufficient.

```bash
# Check PG distribution
docker exec ceph-mon ceph osd pool autoscale-status
```

---

## Disk usage

```bash
# Pool-level usage
docker exec ceph-mon ceph df

# Image-level disk usage (actual vs provisioned)
docker exec ceph-mon rbd du rbd/myimage
```
