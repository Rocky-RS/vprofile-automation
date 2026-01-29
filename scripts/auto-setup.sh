#!/bin/bash

set -e

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root: sudo ./auto-setup.sh"
  exit 1
fi

echo "==============================="
echo " VPROFILE AUTO SETUP - UBUNTU"
echo " Source: Rocky-RS GitHub Repo"
echo "==============================="

echo "[1/8] Installing dependencies..."
apt update -y
apt install -y git curl unzip wget openjdk-17-jdk maven mysql-server nginx memcached rabbitmq-server

# -------------------------------
echo "[2/8] Configuring MySQL..."
systemctl start mysql
systemctl enable mysql

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS accounts;
CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY 'admin123';
GRANT ALL PRIVILEGES ON accounts.* TO 'admin'@'localhost';
FLUSH PRIVILEGES;
EOF

# -------------------------------
echo "[3/8] Cloning project from YOUR GitHub & importing DB..."
cd /opt
rm -rf vprofile-manual-setup || true

# 🔥 YOUR REPO AS SOURCE
git clone https://github.com/Rocky-RS/vprofile-manual-setup.git
cd vprofile-manual-setup

# Import DB
mysql -u admin -padmin123 accounts < src/main/resources/db_backup.sql

echo "[FIX] Updating application.properties for localhost..."

APP_PROP="/opt/vprofile-manual-setup/src/main/resources/application.properties"

sed -i 's/db01/localhost/g' "$APP_PROP"
sed -i 's/mc01/localhost/g' "$APP_PROP"
sed -i 's/rmq01/localhost/g' "$APP_PROP"

# -------------------------------
echo "[4/8] Configuring services..."

systemctl enable memcached
systemctl start memcached

systemctl enable rabbitmq-server
systemctl start rabbitmq-server

rabbitmqctl add_user test test || true
rabbitmqctl set_user_tags test administrator || true
rabbitmqctl set_permissions -p / test ".*" ".*" ".*" || true

# -------------------------------
echo "[5/8] Building application..."
mvn clean install -DskipTests

# -------------------------------
echo "[6/8] Installing Tomcat (SAFE ROOT DEPLOY)..."
cd /opt

# Stop tomcat if running
if pgrep -f tomcat >/dev/null; then
  echo "Stopping existing Tomcat..."
  /opt/tomcat/bin/shutdown.sh || true
  sleep 5
fi

# Clean old tomcat
rm -rf /opt/tomcat apache-tomcat-10.1.26* || true

# Install tomcat fresh
wget https://archive.apache.org/dist/tomcat/tomcat-10/v10.1.26/bin/apache-tomcat-10.1.26.tar.gz
tar -xzf apache-tomcat-10.1.26.tar.gz
mv apache-tomcat-10.1.26 tomcat

# Permissions
chmod +x /opt/tomcat/bin/*.sh

# -------- ROOT DEPLOY --------
echo "Deploying application as ROOT..."

# Ensure clean deployment
rm -rf /opt/tomcat/webapps/ROOT
rm -f /opt/tomcat/webapps/ROOT.war

# Deploy new WAR from YOUR repo
cp /opt/vprofile-manual-setup/target/*.war /opt/tomcat/webapps/ROOT.war

# Start tomcat
/opt/tomcat/bin/startup.sh

# -------------------------------
echo "[7/8] Configuring Nginx..."

cat <<EOF > /etc/nginx/sites-available/vprofile
server {
    listen 80;
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/vprofile /etc/nginx/sites-enabled/vprofile
rm -f /etc/nginx/sites-enabled/default

systemctl restart nginx

# -------------------------------
echo "[8/8] Final status check..."
systemctl status mysql --no-pager | head -n 3
systemctl status rabbitmq-server --no-pager | head -n 3
systemctl status memcached --no-pager | head -n 3
systemctl status nginx --no-pager | head -n 3

echo "==============================="
echo " 🎉 SETUP COMPLETED SUCCESSFULLY "
echo "==============================="
echo " 🌐 Access app: http://localhost"
echo "================================"

