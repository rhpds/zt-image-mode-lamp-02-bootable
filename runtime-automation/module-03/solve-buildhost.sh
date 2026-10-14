#!/bin/bash
# Solve script for Module 03: Deploy and Validate
# This deploys the bootable VM and verifies it works

set -e

echo "Solving Module 03..." >> /tmp/progress.log
echo "Timestamp: $(date)" >> /tmp/progress.log

GUID="${GUID}"
VM_NAME="lamp-vm"
DISK_SOURCE="/home/rhel/lamp-bootc/output/qcow2/disk.qcow2"
DISK_TARGET="/var/lib/libvirt/images/lamp-vm.qcow2"

# Verify disk image exists (from Module 02)
if [ ! -f "$DISK_SOURCE" ]; then
    echo "Disk image not found - running Module 02 solve first..." >> /tmp/progress.log
    echo "This will take 10-15 minutes (building bootable image)..." >> /tmp/progress.log
    /root/runtime-automation/module-02/solve-buildhost.sh
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create disk image" >> /tmp/progress.log
        exit 1
    fi
    # Verify disk was created
    if [ ! -f "$DISK_SOURCE" ]; then
        echo "ERROR: Disk image still not found after Module 02 solve" >> /tmp/progress.log
        ls -la /home/rhel/lamp-bootc/output/ >> /tmp/progress.log 2>&1 || echo "output dir not found" >> /tmp/progress.log
        exit 1
    fi
fi
echo "Disk image found at $DISK_SOURCE" >> /tmp/progress.log
ls -lh "$DISK_SOURCE" >> /tmp/progress.log

# Stop and destroy existing VM if present
echo "Cleaning up any existing VM..." >> /tmp/progress.log
virsh destroy $VM_NAME 2>/dev/null || true
virsh undefine $VM_NAME 2>/dev/null || true
rm -f $DISK_TARGET
echo "Cleanup complete" >> /tmp/progress.log

# Copy disk image to libvirt storage
echo "Copying disk image to libvirt storage..." >> /tmp/progress.log
cp $DISK_SOURCE $DISK_TARGET
chown qemu:qemu $DISK_TARGET
echo "Disk image copied" >> /tmp/progress.log
ls -lh $DISK_TARGET >> /tmp/progress.log

# Create and start VM
echo "Creating VM with virt-install..." >> /tmp/progress.log
virt-install --name $VM_NAME \
  --disk $DISK_TARGET \
  --import \
  --memory 2048 \
  --vcpus 2 \
  --os-variant rhel10-unknown \
  --graphics none \
  --noautoconsole >> /tmp/progress.log 2>&1

# Wait for VM to boot
echo "Waiting for VM to boot (30 seconds)..." >> /tmp/progress.log
sleep 30

# Verify VM is running
if ! virsh list | grep -q "$VM_NAME.*running"; then
    echo "ERROR: VM is not running" >> /tmp/progress.log
    virsh list >> /tmp/progress.log
    exit 1
fi
echo "VM is running" >> /tmp/progress.log

# Get VM IP address
echo "Getting VM IP address..." >> /tmp/progress.log
VM_IP=""
for i in {1..10}; do
    VM_IP=$(virsh domifaddr $VM_NAME | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
    if [ -n "$VM_IP" ]; then
        echo "VM IP: $VM_IP" >> /tmp/progress.log
        break
    fi
    echo "Waiting for IP address (attempt $i/10)..." >> /tmp/progress.log
    sleep 5
done

if [ -z "$VM_IP" ]; then
    echo "ERROR: Could not get VM IP address" >> /tmp/progress.log
    virsh domifaddr $VM_NAME >> /tmp/progress.log
    exit 1
fi

# Wait a bit more for services to start
echo "Waiting for services to start..." >> /tmp/progress.log
sleep 20

# Setup SSH options
SSH_KEY="/root/.ssh/${GUID}key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Verify services are running via SSH
echo "Verifying MariaDB service..." >> /tmp/progress.log
if ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "systemctl is-active mariadb" | grep -q "active"; then
    echo "MariaDB is active" >> /tmp/progress.log
else
    echo "WARNING: MariaDB may not be active yet" >> /tmp/progress.log
fi

echo "Verifying Apache service..." >> /tmp/progress.log
if ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "systemctl is-active httpd" | grep -q "active"; then
    echo "Apache is active" >> /tmp/progress.log
else
    echo "WARNING: Apache may not be active yet" >> /tmp/progress.log
fi

# Test application via curl from host
echo "Testing application from host..." >> /tmp/progress.log
if curl -s http://$VM_IP | grep -q "Hello, World"; then
    echo "Application responds correctly" >> /tmp/progress.log
else
    echo "WARNING: Application may not be ready yet" >> /tmp/progress.log
    curl -s http://$VM_IP | head -10 >> /tmp/progress.log 2>&1 || echo "curl failed" >> /tmp/progress.log
fi

echo "Module 03 solve completed successfully" >> /tmp/progress.log
echo "VM Name: $VM_NAME" >> /tmp/progress.log
echo "VM IP: $VM_IP" >> /tmp/progress.log
echo "SSH: ssh -i $SSH_KEY core@$VM_IP" >> /tmp/progress.log
exit 0
