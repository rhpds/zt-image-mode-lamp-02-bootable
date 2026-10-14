#!/bin/bash
# Solve script for Module 01: Prepare Production Configuration
# This creates the systemd service and app files if needed

set -e

echo "Solving Module 01..." >> /tmp/progress.log
echo "Timestamp: $(date)" >> /tmp/progress.log

# Ensure lamp-bootc directory and app subdirectory exist
echo "Ensuring lamp-bootc directory structure exists..." >> /tmp/progress.log
mkdir -p /home/rhel/lamp-bootc/app
chown -R rhel:rhel /home/rhel/lamp-bootc
echo "Directory structure ready" >> /tmp/progress.log

# Create app files if they don't exist (setup automation should have done this)
echo "Checking/creating application files..." >> /tmp/progress.log

# Create db-setup.sql if missing
if [ ! -f /home/rhel/lamp-bootc/app/db-setup.sql ]; then
    echo "Creating db-setup.sql..." >> /tmp/progress.log
    cat > /home/rhel/lamp-bootc/app/db-setup.sql << 'EOF'
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
    chown rhel:rhel /home/rhel/lamp-bootc/app/db-setup.sql
    echo "db-setup.sql created" >> /tmp/progress.log
else
    echo "db-setup.sql already exists" >> /tmp/progress.log
fi

# Create index.php if missing
if [ ! -f /home/rhel/lamp-bootc/app/index.php ]; then
    echo "Creating index.php..." >> /tmp/progress.log
    cat > /home/rhel/lamp-bootc/app/index.php << 'PHPEOF'
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
PHPEOF
    chown rhel:rhel /home/rhel/lamp-bootc/app/index.php
    echo "index.php created" >> /tmp/progress.log
else
    echo "index.php already exists" >> /tmp/progress.log
fi

# Create myapp.conf if missing
if [ ! -f /home/rhel/lamp-bootc/app/myapp.conf ]; then
    echo "Creating myapp.conf..." >> /tmp/progress.log
    cat > /home/rhel/lamp-bootc/app/myapp.conf << 'EOF'
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
    chown rhel:rhel /home/rhel/lamp-bootc/app/myapp.conf
    echo "myapp.conf created" >> /tmp/progress.log
else
    echo "myapp.conf already exists" >> /tmp/progress.log
fi

# Verify all files now exist
echo "Verifying all application files..." >> /tmp/progress.log
ls -lh /home/rhel/lamp-bootc/app/ >> /tmp/progress.log

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
echo "Files created:" >> /tmp/progress.log
ls -lh /home/rhel/lamp-bootc/ >> /tmp/progress.log
exit 0
