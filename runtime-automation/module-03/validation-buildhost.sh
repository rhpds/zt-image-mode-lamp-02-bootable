#!/bin/bash
# Validation script for Module 03: Deploy and Validate
# Returns 0 if module objectives are met, non-zero otherwise

set -e

echo "Validating Module 03..." >> /tmp/progress.log
echo "Timestamp: $(date)" >> /tmp/progress.log

GUID="${GUID}"
VM_NAME="lamp-vm"
SSH_KEY="/root/.ssh/${GUID}key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Check if VM is running
echo "Checking VM status..." >> /tmp/progress.log
if ! virsh list | grep -q "$VM_NAME.*running"; then
    echo "FAIL: VM is not running" >> /tmp/progress.log
    echo "All VMs:" >> /tmp/progress.log
    virsh list --all >> /tmp/progress.log
    exit 1
fi
echo "VM is running" >> /tmp/progress.log

# Get VM IP address
VM_IP=$(virsh domifaddr $VM_NAME | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
if [ -z "$VM_IP" ]; then
    echo "FAIL: Could not get VM IP address" >> /tmp/progress.log
    virsh domifaddr $VM_NAME >> /tmp/progress.log
    exit 1
fi
echo "VM IP: $VM_IP" >> /tmp/progress.log

# Wait a moment for services to be fully ready
echo "Waiting for services to stabilize..." >> /tmp/progress.log
sleep 5

# Check application responds with database content
# If we get all three messages, it proves MariaDB, Apache, PHP, and database initialization all worked
echo "Checking application response..." >> /tmp/progress.log
APP_RESPONSE=$(curl -s http://$VM_IP 2>&1)

if ! echo "$APP_RESPONSE" | grep -q "Hello, World!"; then
    echo "FAIL: Application not responding with expected content" >> /tmp/progress.log
    echo "Application response:" >> /tmp/progress.log
    echo "$APP_RESPONSE" | head -20 >> /tmp/progress.log
    exit 1
fi

# Verify all three greeting messages are present (proves database was initialized)
MESSAGE_COUNT=0
if echo "$APP_RESPONSE" | grep -q "Hello, World!"; then
    MESSAGE_COUNT=$((MESSAGE_COUNT + 1))
fi
if echo "$APP_RESPONSE" | grep -q "Welcome to LAMP with Image Mode!"; then
    MESSAGE_COUNT=$((MESSAGE_COUNT + 1))
fi
if echo "$APP_RESPONSE" | grep -q "This is a production bootable image!"; then
    MESSAGE_COUNT=$((MESSAGE_COUNT + 1))
fi

if [ "$MESSAGE_COUNT" -lt 3 ]; then
    echo "FAIL: Application shows only $MESSAGE_COUNT of 3 expected messages" >> /tmp/progress.log
    echo "This indicates database initialization may have failed" >> /tmp/progress.log
    exit 1
fi

echo "Application responds correctly with all database messages" >> /tmp/progress.log

echo "PASS: Module 03 validation successful" >> /tmp/progress.log
echo "Summary:" >> /tmp/progress.log
echo "- VM: Running" >> /tmp/progress.log
echo "- IP: $VM_IP" >> /tmp/progress.log
echo "- Application: Responding with all 3 database messages" >> /tmp/progress.log
echo "- LAMP stack: Verified working (Apache + PHP + MariaDB)" >> /tmp/progress.log
exit 0
