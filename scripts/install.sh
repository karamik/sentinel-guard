#!/bin/bash
set -e

if [ -z "\" ]; then
    echo "Error: SNG_TOKEN not set"
    echo "Usage: SNG_TOKEN=your-token bash install.sh"
    exit 1
fi

echo "=== Sentinel Guard Install ==="

NODE_TYPE=""
KEYSTORE=""

if pgrep -f "geth" >/dev/null 2>&1; then
    NODE_TYPE="geth"
    KEYSTORE="\/data/data/com.termux/files/home/.ethereum/keystore"
elif pgrep -f "erigon" >/dev/null 2>&1; then
    NODE_TYPE="erigon"
    KEYSTORE="\/data/data/com.termux/files/home/.local/share/erigon/keystore"
elif pgrep -f "besu" >/dev/null 2>&1; then
    NODE_TYPE="besu"
    KEYSTORE="\/data/data/com.termux/files/home/.besu/keystore"
elif pgrep -f "qrap-node" >/dev/null 2>&1; then
    NODE_TYPE="qrap"
    KEYSTORE="\/data/data/com.termux/files/home/.qrap/keystore"
else
    NODE_TYPE="unknown"
    KEYSTORE="\/data/data/com.termux/files/home/.sentinel/keystore"
fi

echo "Detected: \"
echo "Keystore: \"

INSTALL_DIR="/opt/sentinel-guard"
mkdir -p "\"
cd "\"

echo "Downloading..."
curl -fsSL "https://github.com/karamik/sentinel-guard/archive/refs/heads/main.tar.gz" | tar xz --strip-components=1

mkdir -p /etc/sentinel
echo "SNG_TOKEN=\" > /etc/sentinel/env
echo "NODE_TYPE=\" >> /etc/sentinel/env
echo "KEYSTORE_PATH=\" >> /etc/sentinel/env
echo "API_ENDPOINT=https://api.qrap.site/v1/heartbeat" >> /etc/sentinel/env

cat > /etc/systemd/system/sentinel-master.service <<EOF
[Unit]
Description=Sentinel Guard Master
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/sentinel/env
Environment=PYTHONPATH=/opt/sentinel-guard
WorkingDirectory=/opt/sentinel-guard
ExecStart=/usr/bin/python3 -m agent.core
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/sentinel-deadman.service <<EOF
[Unit]
Description=Sentinel Guard Deadman
After=sentinel-master.service

[Service]
Type=simple
EnvironmentFile=/etc/sentinel/env
Environment=PYTHONPATH=/opt/sentinel-guard
WorkingDirectory=/opt/sentinel-guard
ExecStart=/usr/bin/python3 -m agent.deadman
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sentinel-master sentinel-deadman
systemctl start sentinel-master sentinel-deadman

echo ""
echo "=== Installed ==="
echo "Status: systemctl status sentinel-master"
echo "Logs: journalctl -u sentinel-master -f"
