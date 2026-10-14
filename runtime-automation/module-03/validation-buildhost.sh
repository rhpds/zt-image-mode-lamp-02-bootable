#!/bin/bash
# Validation script for Module 03: Deploy and Validate
# Returns 0 if module objectives are met, non-zero otherwise

set -e

echo "Validating Module 03..." >> /tmp/progress.log

GUID="${GUID}"
VM_NAME="lamp-vm"
SSH_KEY="/root/.ssh/${GUID}key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Check if VM is running
if ! virsh list | grep -q "$VM_NAME.*running"; then
    echo "FAIL: VM is not running" >> /tmp/progress.log
    virsh list >> /tmp/progress.log
    exit 1
fi

# Get VM IP address
VM_IP=$(virsh domifaddr $VM_NAME | grep ipv4 | awk '{print $4}' | cut -d'/' -f1)
if [ -z "$VM_IP" ]; then
    echo "FAIL: Could not get VM IP address" >> /tmp/progress.log
    virsh domifaddr $VM_NAME >> /tmp/progress.log
    exit 1
fi
echo "VM IP: $VM_IP" >> /tmp/progress.log

# Check MariaDB is running in VM
if ! ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "systemctl is-active mariadb" | grep -q "active"; then
    echo "FAIL: MariaDB is not running in VM" >> /tmp/progress.log
    exit 1
fi

# Check Apache is running in VM
if ! ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "systemctl is-active httpd" | grep -q "active"; then
    echo "FAIL: Apache is not running in VM" >> /tmp/progress.log
    exit 1
fi

# Check mariadb-setup service exists and is enabled
if ! ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "systemctl is-enabled mariadb-setup" | grep -q "enabled"; then
    echo "FAIL: mariadb-setup service is not enabled" >> /tmp/progress.log
    exit 1
fi

# Check database has data
DB_CHECK=$(ssh $SSH_OPTS -i $SSH_KEY core@$VM_IP "mariadb -u hellouser -pSecurePassword hellodb -se 'SELECT COUNT(*) FROM greetings;'" 2>/dev/null || echo "0")
if [ "$DB_CHECK" -lt 3 ]; then
    echo "FAIL: Database does not contain expected data (found $DB_CHECK rows)" >> /tmp/progress.log
    exit 1
fi

# Check application responds
if ! curl -s http://$VM_IP | grep -q "Hello, World"; then
    echo "FAIL: Application not responding correctly" >> /tmp/progress.log
    echo "Application response:" >> /tmp/progress.log
    curl -s http://$VM_IP | head -20 >> /tmp/progress.log 2>&1 || echo "curl failed" >> /tmp/progress.log
    exit 1
fi

echo "PASS: Module 03 validation successful" >> /tmp/progress.log
exit 0
