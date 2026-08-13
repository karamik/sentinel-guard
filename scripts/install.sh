#!/bin/bash
set -e

if [ -z "$SNG_TOKEN" ]; then
    echo "Error: SNG_TOKEN not set"
    echo "Usage: SNG_TOKEN=your-token bash install.sh"
    exit 1
fi

echo "=== Sentinel Guard Install ==="

# Detect node type
NODE_TYPE=""
KEystore_PATH=""
if pgrep -f geth >/dev/null 2>&1; then
    NODE_TYPE="geth"
    KEYSTORE_PATH="$HOME/.ethereum/keystore"
elif pgrep -f erigon >/dev/null 2>&1; then
    NODE_TYPE="erigon"
    KEYSTORE_PATH="$HOME/.local/share/erigon/keystore"
elif pgrep -f qrap-node >/dev/null 2>&1; then
    NODE_TYPE="qrap"
    KEYSTORE_PATH="$HOME/.qrap/keystore"
else
    NODE_TYPE="unknown"
    KEYSTORE_PATH="$HOME/.sentinel/keystore"
fi

echo "Detected node: $NODE_TYPE"
echo "Keystore: $KEYSTORE_PATH"

# Install dir
INSTALL_DIR="/opt/sentinel-guard"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download from GitHub
echo "Downloading agent..."
curl -fsSL https://github.com/karamik/sentinel-guard/archive/refs/heads/main.tar.gz | tar xz --strip-components=1

# Create env file
mkdir -p /etc/sentinel
cat > /etc/sentinel/env <<EOF
SNG_TOKEN=$SNG_TOKEN
NODE_TYPE=$NODE_TYPE
KEYSTORE_PATH=$KEYSTORE_PATH
API_ENDPOINT=https://api.qrap.site/v1/heartbeat
EOF

# Create systemd service for master
cat > /etc/systemd/system/sentinel-master.service <<EOF
[Unit]
Description=Sentinel Guard Master
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/sentinel/env
Environment=PYTHONPATH=$INSTALL_DIR
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 -m agent.core
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for deadman
cat > /etc/systemd/system/sentinel-deadman.service <<EOF
[Unit]
Description=Sentinel Guard Deadman
After=sentinel-master.service

[Service]
Type=simple
EnvironmentFile=/etc/sentinel/env
Environment=PYTHONPATH=$INSTALL_DIR
WorkingDirectory=$INSTALL_DIR
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
echo "=== Sentinel Guard Installed ==="
echo "Node type: $NODE_TYPE"
echo "Status: systemctl status sentinel-master"
echo "Logs: journalctl -u sentinel-master -f"
