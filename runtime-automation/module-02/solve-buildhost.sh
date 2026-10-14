#!/bin/bash
# Solve script for Module 02: Build Bootable Image
# This creates the production Containerfile and builds the bootable disk image

set -e

echo "Solving Module 02..." >> /tmp/progress.log
echo "Timestamp: $(date)" >> /tmp/progress.log

# Use local image name (not registry reference - matches what content teaches)
IMAGE_NAME="lamp-bootc"

echo "Using image name: $IMAGE_NAME" >> /tmp/progress.log

# Ensure directory exists
mkdir -p /home/rhel/lamp-bootc/app
chown -R rhel:rhel /home/rhel/lamp-bootc

# Ensure all prerequisite files exist (from Module 01)
echo "Checking prerequisite files..." >> /tmp/progress.log
if [ ! -f /home/rhel/lamp-bootc/app/db-setup.sql ] || \
   [ ! -f /home/rhel/lamp-bootc/app/index.php ] || \
   [ ! -f /home/rhel/lamp-bootc/app/myapp.conf ] || \
   [ ! -f /home/rhel/lamp-bootc/mariadb-setup.service ]; then
    echo "Missing prerequisite files - running Module 01 solve first..." >> /tmp/progress.log
    /root/runtime-automation/module-01/solve-buildhost.sh
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create prerequisite files" >> /tmp/progress.log
        exit 1
    fi
fi
echo "All prerequisite files verified" >> /tmp/progress.log

# Create production Containerfile.bootc
echo "Creating Containerfile.bootc..." >> /tmp/progress.log
cat > /home/rhel/lamp-bootc/Containerfile.bootc << 'EOF'
# Production LAMP Stack - Bootable Container Image
FROM registry.redhat.io/rhel10/rhel-bootc:10.1

# Install LAMP stack
RUN dnf install -y mariadb-server httpd php php-mysqlnd && \
    dnf clean all

# Copy application files (immutable - baked into image)
COPY app/db-setup.sql /var/local/setup.sql
COPY app/index.php /var/www/html/index.php
COPY app/myapp.conf /etc/httpd/conf.d/myapp.conf

# Copy and install systemd service for database initialization
COPY mariadb-setup.service /etc/systemd/system/mariadb-setup.service

# Enable services to start on boot
RUN systemctl enable mariadb httpd mariadb-setup

# Configure SELinux for Apache to connect to database
RUN setsebool -P httpd_can_network_connect_db on

# Configure firewall to allow HTTP
RUN firewall-offline-cmd --add-service=http

# Expose Apache port
EXPOSE 80
EOF
chown rhel:rhel /home/rhel/lamp-bootc/Containerfile.bootc

# Verify Containerfile was created
if [ -f /home/rhel/lamp-bootc/Containerfile.bootc ]; then
    echo "Containerfile.bootc created successfully" >> /tmp/progress.log
    ls -lh /home/rhel/lamp-bootc/Containerfile.bootc >> /tmp/progress.log
else
    echo "ERROR: Containerfile.bootc NOT created!" >> /tmp/progress.log
    exit 1
fi

# Build bootable container image
echo "Building bootable container image (this may take 2-3 minutes)..." >> /tmp/progress.log
cd /home/rhel/lamp-bootc
su - rhel -c "cd ~/lamp-bootc && podman build -f Containerfile.bootc -t ${IMAGE_NAME} ." >> /tmp/progress.log 2>&1

# Verify image was built
if su - rhel -c "podman images ${IMAGE_NAME}" | grep -q lamp-bootc; then
    echo "Bootable image built successfully" >> /tmp/progress.log
    su - rhel -c "podman images ${IMAGE_NAME}" >> /tmp/progress.log
else
    echo "ERROR: Bootable image NOT built!" >> /tmp/progress.log
    exit 1
fi

# Use bootc-image-builder to create VM disk image
echo "Creating VM disk image with bootc-image-builder (this will take 8-10 minutes)..." >> /tmp/progress.log
echo "Please wait - this is the longest step..." >> /tmp/progress.log

# Remove any existing output directory
rm -rf /home/rhel/lamp-bootc/output
mkdir -p /home/rhel/lamp-bootc/output
chown rhel:rhel /home/rhel/lamp-bootc/output

# Run bootc-image-builder
podman run --rm -it --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v /home/rhel/lamp-bootc/output:/output \
  -v /root/config.toml:/config.toml \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  registry.redhat.io/rhel10/bootc-image-builder:10.1 \
  --type qcow2 \
  --local \
  ${IMAGE_NAME} >> /tmp/progress.log 2>&1

# Verify disk image was created
if [ -f /home/rhel/lamp-bootc/output/qcow2/disk.qcow2 ]; then
    echo "VM disk image created successfully" >> /tmp/progress.log
    ls -lh /home/rhel/lamp-bootc/output/qcow2/disk.qcow2 >> /tmp/progress.log
else
    echo "ERROR: VM disk image NOT created!" >> /tmp/progress.log
    echo "Checking output directory:" >> /tmp/progress.log
    find /home/rhel/lamp-bootc/output -type f >> /tmp/progress.log 2>&1 || echo "No files found" >> /tmp/progress.log
    exit 1
fi

echo "Module 02 solve completed successfully" >> /tmp/progress.log
exit 0
