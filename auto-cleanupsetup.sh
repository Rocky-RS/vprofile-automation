#!/bin/bash
set -e

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root: sudo ./cleanup-vprofile.sh"
  exit 1
fi

echo "==============================="
echo " 🧹 VPROFILE FULL CLEANUP"
echo "==============================="

# -------------------------------
echo "[1/9] Resetting failed services..."
systemctl reset-failed nginx || true
systemctl reset-failed mysql || true
systemctl reset-failed memcached || true
systemctl reset-failed rabbitmq-server || true

# -------------------------------
echo "[2/9] Stopping services..."
systemctl stop nginx || true
systemctl stop mysql || true
systemctl stop memcached || true
systemctl stop rabbitmq-server || true

# Stop tomcat safely
if [ -d "/opt/tomcat" ]; then
  echo "Stopping Tomcat..."
  chmod +x /opt/tomcat/bin/*.sh || true
  /opt/tomcat/bin/shutdown.sh || true
fi

sleep 3

# -------------------------------
echo "[3/9] Disabling services (autostart)..."
systemctl disable nginx || true
systemctl disable mysql || true
systemctl disable memcached || true
systemctl disable rabbitmq-server || true

# -------------------------------
echo "[4/9] Killing leftover processes..."
pkill -f nginx || true
pkill -f mysqld || true
pkill -f rabbitmq || true
pkill -f memcached || true
pkill -f tomcat || true
pkill -f java || true

# -------------------------------
echo "[5/9] Removing Tomcat..."
rm -rf /opt/tomcat
rm -rf /opt/apache-tomcat-10.1.26*
rm -f /opt/apache-tomcat-10.1.26.tar.gz

# -------------------------------
echo "[6/9] Removing project files..."
rm -rf /opt/vprofile-manual-setup   # YOUR SOURCE REPO
rm -rf /opt/vprofile-automation     # YOUR AUTOMATION REPO (if present)

# -------------------------------
echo "[7/9] Cleaning Nginx config..."
rm -f /etc/nginx/sites-enabled/vprofile
rm -f /etc/nginx/sites-available/vprofile

# Restore default nginx site
if [ -f /etc/nginx/sites-available/default ]; then
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi

# -------------------------------
echo "[8/9] Cleaning databases + users..."

# Start mysql only if socket exists
systemctl start mysql || true
sleep 3

mysql -u root <<EOF || true
DROP DATABASE IF EXISTS accounts;
DROP USER IF EXISTS 'admin'@'localhost';
FLUSH PRIVILEGES;
EOF

systemctl stop mysql || true
systemctl disable mysql || true

# -------------------------------
echo "[9/9] Cleaning RabbitMQ users..."

systemctl start rabbitmq-server || true
sleep 5
rabbitmqctl delete_user test || true
systemctl stop rabbitmq-server || true
systemctl disable rabbitmq-server || true

# -------------------------------
echo "[FINAL] Clearing ports..."

fuser -k 80/tcp || true
fuser -k 8080/tcp || true
fuser -k 3306/tcp || true
fuser -k 5672/tcp || true
fuser -k 11211/tcp || true

# -------------------------------
echo "==============================="
echo " ✅ CLEANUP COMPLETED SUCCESSFULLY"
echo "==============================="
echo " 🧼 System is now in FRESH state"
echo " 🚀 Ready for fresh deployment"
echo "================================"

