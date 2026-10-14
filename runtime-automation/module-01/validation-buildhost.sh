#!/bin/bash
# Validation script for Module 01: Prepare Production Configuration
# Returns 0 if module objectives are met, non-zero otherwise

set -e

echo "Validating Module 01..." >> /tmp/progress.log
echo "Timestamp: $(date)" >> /tmp/progress.log

# Check if lamp-bootc directory exists
if [ ! -d /home/rhel/lamp-bootc ]; then
    echo "FAIL: /home/rhel/lamp-bootc directory does not exist" >> /tmp/progress.log
    exit 1
fi

# Check if app directory exists
if [ ! -d /home/rhel/lamp-bootc/app ]; then
    echo "FAIL: /home/rhel/lamp-bootc/app directory does not exist" >> /tmp/progress.log
    exit 1
fi

# Check app files exist
echo "Checking application files..." >> /tmp/progress.log
if [ ! -f /home/rhel/lamp-bootc/app/db-setup.sql ]; then
    echo "FAIL: db-setup.sql not found" >> /tmp/progress.log
    ls -la /home/rhel/lamp-bootc/app/ >> /tmp/progress.log 2>&1 || echo "Directory listing failed" >> /tmp/progress.log
    exit 1
fi

if [ ! -f /home/rhel/lamp-bootc/app/index.php ]; then
    echo "FAIL: index.php not found" >> /tmp/progress.log
    ls -la /home/rhel/lamp-bootc/app/ >> /tmp/progress.log 2>&1 || echo "Directory listing failed" >> /tmp/progress.log
    exit 1
fi

if [ ! -f /home/rhel/lamp-bootc/app/myapp.conf ]; then
    echo "FAIL: myapp.conf not found" >> /tmp/progress.log
    ls -la /home/rhel/lamp-bootc/app/ >> /tmp/progress.log 2>&1 || echo "Directory listing failed" >> /tmp/progress.log
    exit 1
fi
echo "Application files verified" >> /tmp/progress.log

# Check if mariadb-setup.service exists
if [ ! -f /home/rhel/lamp-bootc/mariadb-setup.service ]; then
    echo "FAIL: mariadb-setup.service not found" >> /tmp/progress.log
    echo "Directory contents:" >> /tmp/progress.log
    ls -la /home/rhel/lamp-bootc/ >> /tmp/progress.log 2>&1 || echo "Directory listing failed" >> /tmp/progress.log
    exit 1
fi

# Check if service file contains required sections
echo "Validating mariadb-setup.service contents..." >> /tmp/progress.log
if ! grep -q "\[Unit\]" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing [Unit] section" >> /tmp/progress.log
    cat /home/rhel/lamp-bootc/mariadb-setup.service >> /tmp/progress.log
    exit 1
fi

if ! grep -q "\[Service\]" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing [Service] section" >> /tmp/progress.log
    cat /home/rhel/lamp-bootc/mariadb-setup.service >> /tmp/progress.log
    exit 1
fi

if ! grep -q "\[Install\]" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing [Install] section" >> /tmp/progress.log
    cat /home/rhel/lamp-bootc/mariadb-setup.service >> /tmp/progress.log
    exit 1
fi

# Check for required directives
if ! grep -q "Type=oneshot" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing Type=oneshot" >> /tmp/progress.log
    cat /home/rhel/lamp-bootc/mariadb-setup.service >> /tmp/progress.log
    exit 1
fi

echo "PASS: Module 01 validation successful" >> /tmp/progress.log
echo "All required files verified:" >> /tmp/progress.log
ls -lh /home/rhel/lamp-bootc/app/ >> /tmp/progress.log
ls -lh /home/rhel/lamp-bootc/mariadb-setup.service >> /tmp/progress.log
exit 0
