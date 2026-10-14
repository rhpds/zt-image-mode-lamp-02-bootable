#!/bin/bash
# Validation script for Module 01: Prepare Production Configuration
# Returns 0 if module objectives are met, non-zero otherwise

set -e

echo "Validating Module 01..." >> /tmp/progress.log

# Check if mariadb-setup.service exists
if [ ! -f /home/rhel/lamp-bootc/mariadb-setup.service ]; then
    echo "FAIL: mariadb-setup.service not found" >> /tmp/progress.log
    exit 1
fi

# Check if service file contains required sections
if ! grep -q "\[Unit\]" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing [Unit] section" >> /tmp/progress.log
    exit 1
fi

if ! grep -q "\[Service\]" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing [Service] section" >> /tmp/progress.log
    exit 1
fi

if ! grep -q "\[Install\]" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing [Install] section" >> /tmp/progress.log
    exit 1
fi

# Check for required directives
if ! grep -q "Type=oneshot" /home/rhel/lamp-bootc/mariadb-setup.service; then
    echo "FAIL: mariadb-setup.service missing Type=oneshot" >> /tmp/progress.log
    exit 1
fi

# Verify app files still exist
if [ ! -f /home/rhel/lamp-bootc/app/db-setup.sql ] || \
   [ ! -f /home/rhel/lamp-bootc/app/index.php ] || \
   [ ! -f /home/rhel/lamp-bootc/app/myapp.conf ]; then
    echo "FAIL: Application files missing" >> /tmp/progress.log
    exit 1
fi

echo "PASS: Module 01 validation successful" >> /tmp/progress.log
exit 0
