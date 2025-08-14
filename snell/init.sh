#!/bin/bash

set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root. Use sudo." >&2
  exit 1
fi

# Check if the system is Linux
if [[ "$(uname)" != "Linux" ]]; then
  echo "[ERROR] This script only supports Linux systems."
  exit 1
fi

# Check for CentOS 7
if [[ -f /etc/centos-release ]]; then
  CENTOS_VERSION=$(cat /etc/centos-release | grep -oE '[0-9]+' | head -1)
  if [[ $CENTOS_VERSION -ne 7 ]]; then
    echo "[WARN] This script is optimized for CentOS 7."
  fi
else
  echo "[WARN] This script is optimized for CentOS 7."
fi

echo "[INFO] Checking dependencies..."
for pkg in curl unzip; do
  if ! command -v $pkg &>/dev/null; then
    echo "[INFO] Installing missing dependency: $pkg..."
    yum install -y $pkg
  fi
  if ! command -v $pkg &>/dev/null; then
    echo "[ERROR] Failed to install $pkg. Please install it manually."
    exit 1
  fi
  echo "[OK] $pkg is installed."
done

echo "[INFO] Detecting system architecture..."
ARCH=$(uname -m)
case $ARCH in
  x86_64)
    FILE_URL="https://dogitect.github.io/tortuga/snell/snell-server/snell-server-v5.0.0-linux-amd64.zip"
    ;;
  i386)
    FILE_URL="https://dogitect.github.io/tortuga/snell/snell-server/snell-server-v5.0.0-linux-i386.zip"
    ;;
  aarch64)
    FILE_URL="https://dogitect.github.io/tortuga/snell/snell-server/snell-server-v5.0.0-linux-aarch64.zip"
    ;;
  armv7l)
    FILE_URL="https://dogitect.github.io/tortuga/snell/snell-server/snell-server-v5.0.0-linux-armv7l.zip"
    ;;
  *)
    echo "[ERROR] Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "[INFO] Downloading Snell server binary for $ARCH..."
TMP_TGZ="/tmp/$(basename $FILE_URL)"
curl -s -L $FILE_URL -o $TMP_TGZ
if [[ $? -ne 0 || ! -s $TMP_TGZ ]]; then
  echo "[ERROR] Download failed."
  exit 1
fi

echo "[INFO] Extracting Snell server binary..."
unzip -o $TMP_TGZ -d /tmp
if [[ ! -f /tmp/snell-server ]]; then
  echo "[ERROR] Extraction failed."
  exit 1
fi

echo "[INFO] Installing Snell server to /usr/local/bin..."
mv -f /tmp/snell-server /usr/local/bin/
chmod +x /usr/local/bin/snell-server

echo "[INFO] Generating random port and PSK..."
RANDOM_PORT=$(( ( RANDOM % 55535 )  + 10000 ))
PSK=$(head -c 32 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32)

echo "[INFO] Creating configuration file at /etc/snell/server.conf..."
mkdir -p /etc/snell
cat <<EOL > /etc/snell/server.conf
[snell-server]
listen = 0.0.0.0:${RANDOM_PORT}
psk = ${PSK}
ipv6 = false
EOL

echo "[INFO] Creating systemd service file at /etc/systemd/system/snell.service..."
cat <<EOL > /etc/systemd/system/snell.service
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nobody
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell/server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOL

echo "[INFO] Reloading systemd and starting Snell service..."
systemctl daemon-reload
systemctl enable snell.service
systemctl restart snell.service

if systemctl is-active --quiet snell.service; then
  echo "[SUCCESS] Snell Proxy Service has been installed and started."
  echo "[INFO] Port: ${RANDOM_PORT}"
  echo "[INFO] PSK:  ${PSK}"
  echo "[INFO] Config: /etc/snell/server.conf"
  echo "[INFO] Service: snell.service (systemd)"
else
  echo "[ERROR] Snell service failed to start. Please check 'systemctl status snell.service' for details."
  exit 1
fi
