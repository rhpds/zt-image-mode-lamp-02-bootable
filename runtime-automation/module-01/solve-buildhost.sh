#!/bin/bash
# Solve script for Module 01: Prepare Production Configuration
# This creates the systemd service for database initialization

set -e

echo "Solving Module 01..." >> /tmp/progress.log
echo "Timestamp: $(date)" >> /tmp/progress.log

# Ensure lamp-bootc directory exists
echo "Ensuring lamp-bootc directory exists..." >> /tmp/progress.log
mkdir -p /home/rhel/lamp-bootc
chown rhel:rhel /home/rhel/lamp-bootc
echo "Directory ready" >> /tmp/progress.log

# Verify app files exist (created by setup automation)
echo "Verifying application files..." >> /tmp/progress.log
if [ ! -f /home/rhel/lamp-bootc/app/db-setup.sql ]; then
    echo "ERROR: db-setup.sql not found" >> /tmp/progress.log
    exit 1
fi
if [ ! -f /home/rhel/lamp-bootc/app/index.php ]; then
    echo "ERROR: index.php not found" >> /tmp/progress.log
    exit 1
fi
if [ ! -f /home/rhel/lamp-bootc/app/myapp.conf ]; then
    echo "ERROR: myapp.conf not found" >> /tmp/progress.log
    exit 1
fi
echo "Application files verified" >> /tmp/progress.log

# Create mariadb-setup.service systemd unit
echo "Creating mariadb-setup.service..." >> /tmp/progress.log
cat > /home/rhel/lamp-bootc/mariadb-setup.service << 'EOF'
[Unit]
Description=MariaDB Database Initialization
After=mariadb.service
Requires=mariadb.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mariadb -u root < /var/local/setup.sql
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
chown rhel:rhel /home/rhel/lamp-bootc/mariadb-setup.service

# Verify service file was created
if [ -f /home/rhel/lamp-bootc/mariadb-setup.service ]; then
    echo "mariadb-setup.service created successfully" >> /tmp/progress.log
    ls -lh /home/rhel/lamp-bootc/mariadb-setup.service >> /tmp/progress.log
else
    echo "ERROR: mariadb-setup.service NOT created!" >> /tmp/progress.log
    exit 1
fi

echo "Module 01 solve completed successfully" >> /tmp/progress.log
exit 0
