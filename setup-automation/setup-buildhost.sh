#!/bin/bash
set -x
USER=rhel

echo "Adding wheel" > /root/post-run.log
usermod -aG wheel rhel

echo "Setup build host for LAMP production deployment lab" > /tmp/progress.log
chmod 666 /tmp/progress.log

# Base images for bootable container
BOOTC_BASE=registry.redhat.io/rhel10/rhel-bootc:10.1
BOOTC_BUILDER=registry.redhat.io/rhel10/bootc-image-builder:10.1
IMAGE_REF=registry-${GUID}.${DOMAIN}/lamp-bootc

# Set up libvirt and name resolution for nested virtualization
echo "Setting up libvirt for nested virtualization..." >> /tmp/progress.log
systemctl enable --now libvirtd
sed -i 's/hosts:\s\+ files/& libvirt libvirt_guest/' /etc/nsswitch.conf

# Set up registry authentication so we can pull Red Hat base images
echo "Configuring registry authentication..." >> /tmp/progress.log
mkdir -p ~/.config/containers
cat <<EOF> ~/.config/containers/auth.json
{
    "auths": {
      "registry.redhat.io": {
        "auth": "${REGISTRY_PULL_TOKEN}"
      }
    }
  }
EOF

# Pull required base images
echo "Pulling bootc base images..." >> /tmp/progress.log
podman pull $BOOTC_BASE
podman pull $BOOTC_BUILDER

# Set up local registry (TLS if credentials available, insecure otherwise)
if [ -n "${ZEROSSL_EAB_KEY_ID}" ] && [ -n "${ZEROSSL_HMAC_KEY}" ]; then
    echo "Setting up local TLS registry with ZeroSSL..." >> /tmp/progress.log
    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
    dnf install -y certbot

    CERT_DIR="/etc/letsencrypt/live/registry-${GUID}.${DOMAIN}"
    CERT_MAX_RETRIES=3
    CERT_RETRY=0
    while [ $CERT_RETRY -lt $CERT_MAX_RETRIES ]; do
        set +x
        certbot certonly --eab-kid "${ZEROSSL_EAB_KEY_ID}" --eab-hmac-key "${ZEROSSL_HMAC_KEY}" \
            --server "https://acme.zerossl.com/v2/DV90" --standalone --preferred-challenges http \
            -d registry-"${GUID}"."${DOMAIN}" --non-interactive --agree-tos -m trackbot@instruqt.com -v
        rm -f /var/log/letsencrypt/letsencrypt.log
        set -x

        if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
            echo "SSL certificates obtained successfully" >> /tmp/progress.log
            break
        fi

        CERT_RETRY=$((CERT_RETRY + 1))
        echo "Certificate attempt $CERT_RETRY of $CERT_MAX_RETRIES failed, retrying..." >> /tmp/progress.log
        sleep 15
    done

    if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
        echo "WARNING: Failed to obtain SSL certificates, falling back to insecure registry" >> /tmp/progress.log
        USE_TLS=false
    else
        USE_TLS=true
    fi
else
    echo "WARNING: ZeroSSL credentials not provided, using insecure registry" >> /tmp/progress.log
    USE_TLS=false
fi

# Remove existing registry container if present
podman rm -f registry 2>/dev/null || true

# Run local registry
if [ "$USE_TLS" = "true" ]; then
    echo "Starting local registry with TLS..." >> /tmp/progress.log
    podman run --privileged -d \
      --name registry \
      -p 443:5000 \
      -v /etc/letsencrypt/live/registry-"${GUID}"."${DOMAIN}"/fullchain.pem:/certs/fullchain.pem \
      -v /etc/letsencrypt/live/registry-"${GUID}"."${DOMAIN}"/privkey.pem:/certs/privkey.pem \
      -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/fullchain.pem \
      -e REGISTRY_HTTP_TLS_KEY=/certs/privkey.pem \
      quay.io/mmicene/registry:2
    REGISTRY_URL="https://registry-${GUID}.${DOMAIN}"
else
    echo "Starting insecure local registry (HTTP only)..." >> /tmp/progress.log
    podman run --privileged -d \
      --name registry \
      -p 5000:5000 \
      quay.io/mmicene/registry:2
    REGISTRY_URL="registry-${GUID}.${DOMAIN}:5000"

    # Configure podman to allow insecure registry
    mkdir -p /etc/containers/registries.conf.d
    cat <<EOF > /etc/containers/registries.conf.d/insecure-registry.conf
[[registry]]
location = "registry-${GUID}.${DOMAIN}:5000"
insecure = true
EOF
fi

# Validate registry is responding
sleep 5
REG_MAX_RETRIES=5
REG_RETRY=0
while [ $REG_RETRY -lt $REG_MAX_RETRIES ]; do
    if [ "$USE_TLS" = "true" ]; then
        HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://localhost/v2/ 2>/dev/null)
    else
        HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5000/v2/ 2>/dev/null)
    fi

    if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "200" ]; then
        echo "Registry is responding (HTTP $HTTP_CODE)" >> /tmp/progress.log
        break
    fi
    REG_RETRY=$((REG_RETRY + 1))
    echo "Registry not responding yet, retry $REG_RETRY of $REG_MAX_RETRIES..." >> /tmp/progress.log
    sleep 5
done

if [ $REG_RETRY -eq $REG_MAX_RETRIES ]; then
    echo "FATAL: Registry is not responding" >> /tmp/progress.log
    exit 1
fi

# Configure /etc/hosts for libvirt guest access
echo "10.0.2.2 buildhost.${GUID}.${DOMAIN}" >> /etc/hosts
echo "10.0.2.2 registry-${GUID}.${DOMAIN}" >> /etc/hosts
mkdir -p ~/etc
cp /etc/hosts ~/etc/hosts

# Generate SSH key for VM access
echo "Generating SSH keys..." >> /tmp/progress.log
ssh-keygen -t ed25519 -f ~/.ssh/${GUID}key -N '' -C "LAMP Lab SSH Key"

# Create config.toml for bootc-image-builder (defines VM user)
echo "Creating bootc-image-builder config..." >> /tmp/progress.log
cat <<EOF> /root/config.toml
[[customizations.user]]
name = "core"
password = "redhat"
groups = ["wheel"]
key = "$(cat ~/.ssh/${GUID}key.pub)"
EOF

# Create directory structure for bootable LAMP image
echo "Creating LAMP bootable image directory..." >> /tmp/progress.log
mkdir -p /home/rhel/lamp-bootc/app
chown -R rhel:rhel /home/rhel/lamp-bootc

# Create LAMP application files (same as Lab 1 output)
echo "Creating LAMP application files..." >> /tmp/progress.log
cat <<'EOF' > /home/rhel/lamp-bootc/app/db-setup.sql
-- Create database and user
CREATE DATABASE IF NOT EXISTS hellodb;
CREATE USER IF NOT EXISTS 'hellouser'@'localhost' IDENTIFIED BY 'SecurePassword';
GRANT ALL PRIVILEGES ON hellodb.* TO 'hellouser'@'localhost';
FLUSH PRIVILEGES;

USE hellodb;

-- Create table
CREATE TABLE IF NOT EXISTS greetings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO greetings (message) VALUES ('Hello, World!');
INSERT INTO greetings (message) VALUES ('Welcome to LAMP with Image Mode!');
INSERT INTO greetings (message) VALUES ('This is a production bootable image!');
EOF

cat <<'EOF' > /home/rhel/lamp-bootc/app/index.php
<!DOCTYPE html>
<html>
<head>
    <title>LAMP Application - Production Bootable Image</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            background-color: #f5f5f5;
        }
        h1 { color: #c00; }
        .message {
            background: white;
            padding: 20px;
            margin: 10px 0;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .info {
            background: #e3f2fd;
            padding: 10px;
            border-radius: 5px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <h1>LAMP Application - Production Bootable Image</h1>

    <?php
    $host = '127.0.0.1';
    $db   = 'hellodb';
    $user = 'hellouser';
    $pass = 'SecurePassword';
    $charset = 'utf8mb4';

    $dsn = "mysql:host=$host;dbname=$db;charset=$charset";
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ];

    try {
        $pdo = new PDO($dsn, $user, $pass, $options);
        $stmt = $pdo->query('SELECT message, created_at FROM greetings ORDER BY created_at DESC');

        echo "<h2>Messages from Database:</h2>";
        while ($row = $stmt->fetch()) {
            echo "<div class='message'>";
            echo "<strong>" . htmlspecialchars($row['message']) . "</strong><br>";
            echo "<small>Created: " . htmlspecialchars($row['created_at']) . "</small>";
            echo "</div>";
        }
    } catch (\PDOException $e) {
        echo "<div style='color: red; padding: 20px; background: #ffebee; border-radius: 5px;'>";
        echo "<strong>Database Error:</strong> Could not connect.<br>";
        echo "<small>Check MariaDB service is running</small>";
        echo "</div>";
    }
    ?>

    <div class='info'>
        <strong>Environment:</strong> Production Bootable Image<br>
        <strong>Workflow:</strong> Immutable (files copied at build time)<br>
        <strong>Host:</strong> <?php echo gethostname(); ?>
    </div>
</body>
</html>
EOF

cat <<'EOF' > /home/rhel/lamp-bootc/app/myapp.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/error_log
    CustomLog /var/log/httpd/access_log combined
</VirtualHost>
EOF

chown -R rhel:rhel /home/rhel/lamp-bootc

# Create helpful README
cat <<'EOF' > /home/rhel/lamp-bootc/README.md
# LAMP Production Bootable Image Lab

## What's Here

This directory contains the application files you created in Lab 1 (or they've been provided for you):

```
~/lamp-bootc/app/
├── db-setup.sql    # Database schema and initial data
├── index.php       # PHP application
└── myapp.conf      # Apache configuration
```

## What You'll Build

In this lab, you'll create a **production bootable image** that:

- Uses COPY directives (not volume mounts) - immutable
- Packages the LAMP app into a bootable RHEL image
- Can be deployed as a virtual machine
- Includes systemd services for automatic startup

## Key Differences from Lab 1

**Lab 1 (Development):**
- Volume mounts (mutable)
- Files on host, mounted into container
- Fast iteration

**Lab 2 (Production):**
- COPY directives (immutable)
- Files baked into image at build time
- Consistent, repeatable deployments
EOF

chown rhel:rhel /home/rhel/lamp-bootc/README.md

echo "Setup complete!" >> /tmp/progress.log
echo "LAMP production environment ready at /home/rhel/lamp-bootc" >> /tmp/progress.log
