#!/bin/bash
set -e

if [ -z "$SNG_TOKEN" ]; then
    echo "Error: SNG_TOKEN not set"
    echo "Usage: SNG_TOKEN=your-token bash install.sh"
    exit 1
fi

echo "=== Sentinel Guard Install ==="

NODE_TYPE=""
KEYSTORE=""

if pgrep -f "geth" >/dev/null 2>&1; then
    NODE_TYPE="geth"
    KEYSTORE="$HOME/.ethereum/keystore"
elif pgrep -f "erigon" >/dev/null 2>&1; then
    NODE_TYPE="erigon"
    KEYSTORE="$HOME/.local/share/erigon/keystore"
elif pgrep -f "besu" >/dev/null 2>&1; then
    NODE_TYPE="besu"
    KEYSTORE="$HOME/.besu/keystore"
elif pgrep -f "qrap-node" >/dev/null 2>&1; then
    NODE_TYPE="qrap"
    KEYSTORE="$HOME/.qrap/keystore"
else
    NODE_TYPE="unknown"
    KEYSTORE="$HOME/.sentinel/keystore"
fi

echo "Detected: $NODE_TYPE"

echo ""
read -p "Telegram Chat ID for alerts (get from @userinfobot, optional): " TG_CHAT
if [ -n "$TG_CHAT" ]; then
    echo "SNG_CHAT_ID=$TG_CHAT" >> /etc/sentinel/env
fi
echo "Keystore: $KEYSTORE"

INSTALL_DIR="/opt/sentinel-guard"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "Downloading..."
curl -fsSL "https://github.com/karamik/sentinel-guard/archive/refs/heads/main.tar.gz" | tar xz --strip-components=1

mkdir -p /etc/sentinel
cat > /etc/sentinel/env <<ENV
SNG_TOKEN=$SNG_TOKEN
NODE_TYPE=$NODE_TYPE
KEYSTORE_PATH=$KEYSTORE
API_ENDPOINT=https://api.qrap.site/v1/heartbeat
SNG_DRY_RUN=true
ENV

cat > /etc/systemd/system/sentinel-master.service <<'UNIT'
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
StandardOutput=journal
StandardError=journal
User=root

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/sentinel-deadman.service <<'UNIT'
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
StandardOutput=journal
StandardError=journal
User=root

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable sentinel-master sentinel-deadman
systemctl start sentinel-master sentinel-deadman

echo ""
echo "=== Installed ==="
echo "Status: systemctl status sentinel-master"
echo "Logs: journalctl -u sentinel-master -f"
