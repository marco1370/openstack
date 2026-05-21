#!/bin/bash
set -e
log() { echo "$(date -u +%H:%M:%S) [nova-libvirt] $*"; }

mkdir -p /run/libvirt /var/lib/libvirt/images /var/log/libvirt

# Allow libvirt to run as root in container
if [ -f /etc/libvirt/libvirtd.conf ]; then
  sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "root"/' /etc/libvirt/libvirtd.conf
  sed -i 's/#unix_sock_ro_perms = "0777"/unix_sock_ro_perms = "0777"/' /etc/libvirt/libvirtd.conf
  sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0777"/' /etc/libvirt/libvirtd.conf
  sed -i 's/#auth_unix_ro = "none"/auth_unix_ro = "none"/' /etc/libvirt/libvirtd.conf
  sed -i 's/#auth_unix_rw = "none"/auth_unix_rw = "none"/' /etc/libvirt/libvirtd.conf
fi

# Configure QEMU to run as root (required in container — /dev/kvm owned by root:tss)
if [ -f /etc/libvirt/qemu.conf ]; then
  sed -i 's/#user = "root"/user = "root"/' /etc/libvirt/qemu.conf
  sed -i 's/#group = "root"/group = "root"/' /etc/libvirt/qemu.conf
  grep -q '^user = "root"' /etc/libvirt/qemu.conf || echo 'user = "root"' >> /etc/libvirt/qemu.conf
  grep -q '^group = "root"' /etc/libvirt/qemu.conf || echo 'group = "root"' >> /etc/libvirt/qemu.conf
fi

# Ensure QEMU can access /dev/kvm
chmod 666 /dev/kvm 2>/dev/null || true

log "starting virtlogd..."
virtlogd --daemon

log "starting libvirtd..."
exec libvirtd
