#!/bin/bash
# Validation script for Module 02: Build Bootable Image
# Returns 0 if module objectives are met, non-zero otherwise

set -e

echo "Validating Module 02..." >> /tmp/progress.log

# Use local image name (matches what content teaches)
IMAGE_NAME="lamp-bootc"

# Check if Containerfile.bootc exists
if [ ! -f /home/rhel/lamp-bootc/Containerfile.bootc ]; then
    echo "FAIL: Containerfile.bootc not found" >> /tmp/progress.log
    exit 1
fi

# Check if Containerfile contains required elements
if ! grep -q "FROM registry.redhat.io/rhel10/rhel-bootc" /home/rhel/lamp-bootc/Containerfile.bootc; then
    echo "FAIL: Containerfile.bootc missing rhel-bootc base" >> /tmp/progress.log
    exit 1
fi

if ! grep -q "COPY app/db-setup.sql" /home/rhel/lamp-bootc/Containerfile.bootc; then
    echo "FAIL: Containerfile.bootc missing COPY for db-setup.sql" >> /tmp/progress.log
    exit 1
fi

if ! grep -q "COPY app/index.php" /home/rhel/lamp-bootc/Containerfile.bootc; then
    echo "FAIL: Containerfile.bootc missing COPY for index.php" >> /tmp/progress.log
    exit 1
fi

if ! grep -q "COPY mariadb-setup.service" /home/rhel/lamp-bootc/Containerfile.bootc; then
    echo "FAIL: Containerfile.bootc missing COPY for mariadb-setup.service" >> /tmp/progress.log
    exit 1
fi

# Check if bootable image was built
if ! su - rhel -c "podman images ${IMAGE_NAME}" | grep -q lamp-bootc; then
    echo "FAIL: Bootable container image not found" >> /tmp/progress.log
    su - rhel -c "podman images" >> /tmp/progress.log
    exit 1
fi

# Check if disk image was created
if [ ! -f /home/rhel/lamp-bootc/output/qcow2/disk.qcow2 ]; then
    echo "FAIL: VM disk image not found" >> /tmp/progress.log
    echo "Expected: /home/rhel/lamp-bootc/output/qcow2/disk.qcow2" >> /tmp/progress.log
    exit 1
fi

# Verify disk image is reasonable size (should be > 1GB)
DISK_SIZE=$(stat -c%s /home/rhel/lamp-bootc/output/qcow2/disk.qcow2 2>/dev/null || echo 0)
if [ "$DISK_SIZE" -lt 1000000000 ]; then
    echo "FAIL: Disk image too small ($DISK_SIZE bytes)" >> /tmp/progress.log
    exit 1
fi

echo "PASS: Module 02 validation successful" >> /tmp/progress.log
exit 0
