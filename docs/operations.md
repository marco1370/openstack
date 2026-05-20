# Operations Runbook

## Start / stop

```bash
# Start all services
docker compose up -d

# Stop all services (preserves volumes)
docker compose down

# Stop and wipe all data (destructive)
docker compose down -v

# Restart a single service
docker compose restart glance

# Recreate a single service (picks up config changes)
docker compose up -d --force-recreate glance
```

## Health check

```bash
# Quick overview
docker ps --format "table {{.Names}}\t{{.Status}}" | grep os-

# Watch until all healthy (~3 min on first boot)
watch -n5 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep os-'

# Verify compute and network from inside Keystone
docker exec os-keystone bash -c "
  export OS_AUTH_URL=http://keystone:5000/v3
  export OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=adminpass
  export OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default
  export OS_IDENTITY_API_VERSION=3
  openstack compute service list
  openstack network agent list"
```

## Logs

```bash
# Tail logs for any service
docker logs os-glance --tail 80 -f
docker logs os-nova-compute --tail 80 -f
docker logs os-neutron-server --tail 80 -f

# All OpenStack services at once (noisy)
docker compose logs -f --tail 20
```

## OpenStack CLI

All commands below assume you are inside `os-keystone` with admin credentials exported:

```bash
docker exec -it os-keystone bash

export OS_AUTH_URL=http://keystone:5000/v3
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=adminpass
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3
```

### Images

```bash
# List images
openstack image list

# Upload a new image (from inside the container or via a mounted path)
openstack image create \
  --disk-format qcow2 --container-format bare \
  --file /path/to/image.qcow2 \
  --public my-image

# Delete image
openstack image delete <id>
```

### Flavors

```bash
openstack flavor list
openstack flavor create --ram 512 --disk 1 --vcpus 1 m1.tiny
```

### Networks

```bash
# List networks and subnets
openstack network list
openstack subnet list

# Create provider network (first time)
openstack network create \
  --share --external \
  --provider-network-type flat \
  --provider-physical-network provider \
  provider

openstack subnet create \
  --network provider \
  --subnet-range 192.168.30.0/24 \
  --gateway 192.168.30.1 \
  --allocation-pool start=192.168.30.10,end=192.168.30.200 \
  provider-subnet
```

### Compute (VMs)

```bash
# Boot a VM
openstack server create \
  --image cirros \
  --flavor m1.tiny \
  --network provider \
  --wait \
  my-vm

# List VMs and their state
openstack server list

# Detailed info (host, IP, fault messages)
openstack server show my-vm

# Console log
openstack console log show my-vm

# Delete VM
openstack server delete my-vm
```

### Volumes

```bash
# Create a volume
openstack volume create --size 10 my-vol

# Attach to a running VM
openstack server add volume my-vm my-vol

# List volumes
openstack volume list

# Create a backup
openstack volume backup create --name my-vol-bak my-vol
```

## Ceph connectivity check

```bash
# From Glance container
docker exec os-glance ceph -c /etc/ceph/ceph.conf --id glance health

# From Cinder volume container
docker exec os-cinder-volume ceph -c /etc/ceph/ceph.conf --id cinder health

# List RBD images in the volumes pool
docker exec os-cinder-volume rbd -p volumes ls
```

## Database access

```bash
docker exec -it os-mariadb mariadb -u root -prootpass

# Common queries
SHOW DATABASES;
USE nova; SHOW TABLES;
SELECT * FROM instances WHERE deleted=0;
```

## Config changes

Config files are bind-mounted read-only. To apply a change:

1. Edit the file in `./config/`
2. Restart the affected container:
   ```bash
   docker compose restart <service-name>
   ```

Start scripts (`/home/marco/openstack-scripts/`) are also bind-mounted. Edit on the host, then restart the container to re-run the script.

## First-boot checklist

After `docker compose up -d` and all containers are healthy:

- [ ] Upload the CirrOS test image:
  ```bash
  openstack image create --disk-format qcow2 --container-format bare \
    --file /var/lib/glance/images/cirros.img --public cirros
  ```
  *(or mount `./images/cirros.img` into the Glance container)*

- [ ] Create the provider network and subnet (see Networks section above)

- [ ] Create at least one flavor (e.g. `m1.tiny`)

- [ ] Boot a test VM and verify it gets an IP and is reachable via noVNC (http://localhost:6080)
