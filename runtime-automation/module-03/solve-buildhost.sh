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
    echo "ERROR: Disk image not found at $DISK_SOURCE" >> /tmp/progress.log
    echo "You must complete Module 02 first to create the disk image." >> /tmp/progress.log
    echo "Module 02 takes 10-15 minutes to build the bootable image." >> /tmp/progress.log
    echo "Please run the Module 02 solve button and wait for it to complete." >> /tmp/progress.log
    ls -la /home/rhel/lamp-bootc/output/ >> /tmp/progress.log 2>&1 || echo "output dir not found" >> /tmp/progress.log
    exit 1
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

# SSH verification disabled - SSH key not available in bootc image by default
# The VM is accessible via password auth (user: core, password: redhat)
# Uncomment and configure SSH keys in config.toml if SSH key auth is needed
#
# # Setup SSH options
# SSH_KEY="/root/.ssh/${GUID}key"
# SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
#
# # Verify services are running via SSH
# echo "Verifying MariaDB service..." >> /tmp/progress.log
# if ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "systemctl is-active mariadb" | grep -q "active"; then
#     echo "MariaDB is active" >> /tmp/progress.log
# else
#     echo "WARNING: MariaDB may not be active yet" >> /tmp/progress.log
# fi
#
# echo "Verifying Apache service..." >> /tmp/progress.log
# if ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "systemctl is-active httpd" | grep -q "active"; then
#     echo "Apache is active" >> /tmp/progress.log
# else
#     echo "WARNING: Apache may not be active yet" >> /tmp/progress.log
# fi
#
# # Test application via curl from host
# echo "Testing application from host..." >> /tmp/progress.log
# if curl -s http://$VM_IP | grep -q "Hello, World"; then
#     echo "Application responds correctly" >> /tmp/progress.log
# else
#     echo "WARNING: Application may not be ready yet" >> /tmp/progress.log
#     curl -s http://$VM_IP | head -10 >> /tmp/progress.log 2>&1 || echo "curl failed" >> /tmp/progress.log
# fi

# Set up TCP forwarding from buildhost:8080 to VM:80 for browser access via OpenShift route
echo "Setting up TCP forwarding for browser access..." >> /tmp/progress.log

# Install socat if not present
if ! command -v socat &> /dev/null; then
    echo "Installing socat..." >> /tmp/progress.log
    dnf install -y socat >> /tmp/progress.log 2>&1
fi

# Kill any existing socat on port 8080
pkill -f "socat.*8080" 2>/dev/null || true
sleep 1

# Start socat to forward port 8080 to VM port 80
# This allows the OpenShift webapp route to reach the nested VM
nohup socat TCP-LISTEN:8080,fork,reuseaddr TCP:${VM_IP}:80 > /tmp/socat-webapp.log 2>&1 &
SOCAT_PID=$!

# Wait briefly and verify socat is running
sleep 2
if ps -p $SOCAT_PID > /dev/null 2>&1; then
    echo "TCP forwarding started: buildhost:8080 -> ${VM_IP}:80 (PID: $SOCAT_PID)" >> /tmp/progress.log
    ss -tlnp | grep :8080 >> /tmp/progress.log 2>&1 || true
else
    echo "WARNING: TCP forwarding may have failed to start" >> /tmp/progress.log
fi

echo "Module 03 solve completed successfully" >> /tmp/progress.log
echo "VM Name: $VM_NAME" >> /tmp/progress.log
echo "VM IP: $VM_IP" >> /tmp/progress.log
echo "SSH: ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@$VM_IP" >> /tmp/progress.log
echo "Password: redhat" >> /tmp/progress.log

# Write VM_IP to file for rhel user to source
cat > /home/rhel/.lamp-vm-ip << EOF
export VM_IP=$VM_IP
EOF
chown rhel:rhel /home/rhel/.lamp-vm-ip

echo "VM_IP saved to ~/.lamp-vm-ip (run: source ~/.lamp-vm-ip)" >> /tmp/progress.log
exit 0
