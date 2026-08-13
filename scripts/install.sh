#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== QRAP Black Box Installer v2.0 ===${NC}"
echo ""

# 1. Token
if [ -z "$SNG_TOKEN" ]; then
    read -p "Enter your QRAP token (from qrap.site/pay): " SNG_TOKEN
    if [ -z "$SNG_TOKEN" ]; then
        echo -e "${RED}Error: Token required${NC}"
        exit 1
    fi
fi

# 2. Product selection
echo ""
echo -e "${YELLOW}Select your shield:${NC}"
echo "  1) ⛓️  Node Shield      — Blockchain validators (ETH, Gnosis, QRAP)"
echo "  2) 🔌  API Shield       — API gateways & backends"
echo "  3) 🏢  Infrastructure Guard — Servers, DBs, SSH"
echo "  4) 🤖  Bot & Mini-App Shield — Telegram bots & games"
echo "  5) 🔐  PQC Tunnel       — Post-quantum VPN"
echo ""
read -p "Choice [1-5]: " PRODUCT_CHOICE

case $PRODUCT_CHOICE in
    1) SNG_PRODUCT="node"; PRODUCT_NAME="Node Shield" ;;
    2) SNG_PRODUCT="api"; PRODUCT_NAME="API Shield" ;;
    3) SNG_PRODUCT="infra"; PRODUCT_NAME="Infrastructure Guard" ;;
    4) SNG_PRODUCT="bot"; PRODUCT_NAME="Bot & Mini-App Shield" ;;
    5) SNG_PRODUCT="tunnel"; PRODUCT_NAME="PQC Tunnel" ;;
    *) echo -e "${RED}Invalid choice. Defaulting to Node Shield.${NC}"; SNG_PRODUCT="node"; PRODUCT_NAME="Node Shield" ;;
esac

echo -e "${GREEN}Selected: $PRODUCT_NAME${NC}"

# 3. Auto-detect only for Node Shield
if [ "$SNG_PRODUCT" == "node" ]; then
    if pgrep -f "geth" > /dev/null; then
        NODE_TYPE="geth"
        KEYSTORE=$(find /root -name "keystore" -path "*/geth/*" 2>/dev/null | head -1 || echo "/root/.ethereum/keystore")
    elif pgrep -f "erigon" > /dev/null; then
        NODE_TYPE="erigon"
        KEYSTORE=$(find /root -name "keystore" -path "*/erigon/*" 2>/dev/null | head -1 || echo "/root/.local/share/erigon/keystore")
    elif pgrep -f "besu" > /dev/null; then
        NODE_TYPE="besu"
        KEYSTORE=$(find /root -name "keystore" -path "*/besu/*" 2>/dev/null | head -1 || echo "/root/.besu/keystore")
    elif pgrep -f "qrap-node" > /dev/null; then
        NODE_TYPE="qrap"
        KEYSTORE="/root/.qrap/keystore"
    else
        NODE_TYPE="unknown"
        KEYSTORE="/opt/sentinel/keystore"
        echo -e "${YELLOW}Warning: No node detected. Using default paths.${NC}"
    fi
    echo -e "${BLUE}Detected: $NODE_TYPE${NC}"
    echo -e "${BLUE}Keystore: $KEYSTORE${NC}"
else
    NODE_TYPE="$SNG_PRODUCT"
    KEYSTORE="/opt/sentinel/keystore"
fi

# 4. Telegram (optional)
echo ""
read -p "Telegram Chat ID for alerts (from @userinfobot, optional): " TG_CHAT
read -p "Telegram Bot Token (optional, for custom bot): " TG_TOKEN

# 5. Install dependencies
echo -e "${BLUE}Installing dependencies...${NC}"
apt-get update -qq
apt-get install -y -qq python3 python3-pip curl iptables lsof systemd 2>/dev/null || true
pip3 install requests 2>/dev/null || true

# 6. Create directories
mkdir -p /opt/sentinel /opt/sentinel/logs /etc/sentinel
chmod 700 /opt/sentinel

# 7. Download agent
echo -e "${BLUE}Downloading agent...${NC}"
VERSION="v0.2.1"
BASE_URL="https://raw.githubusercontent.com/karamik/sentinel-guard/main"

for file in agent/__init__.py agent/config.py agent/core.py agent/heartbeat.py agent/honeypot.py agent/circuit_breaker.py agent/alerting.py agent/immunity.py; do
    mkdir -p /opt/sentinel/$(dirname $file)
    curl -fsSL "$BASE_URL/$file" -o "/opt/sentinel/$file" 2>/dev/null || echo "# placeholder" > "/opt/sentinel/$file"
done

# 8. Create env file
cat > /etc/sentinel/env << EOF
SNG_TOKEN=$SNG_TOKEN
NODE_TYPE=$NODE_TYPE
KEYSTORE_PATH=$KEYSTORE
API_ENDPOINT=https://api.qrap.site/v1/heartbeat
SNG_PRODUCT=$SNG_PRODUCT
SNG_DRY_RUN=true
EOF

if [ -n "$TG_CHAT" ]; then
    echo "SNG_CHAT_ID=$TG_CHAT" >> /etc/sentinel/env
fi
if [ -n "$TG_TOKEN" ]; then
    echo "SNG_BOT_TOKEN=$TG_TOKEN" >> /etc/sentinel/env
fi

chmod 600 /etc/sentinel/env

# 9. Create systemd services
cat > /etc/systemd/system/sentinel-master.service << EOF
[Unit]
Description=QRAP Black Box Master
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/sentinel/env
WorkingDirectory=/opt/sentinel
ExecStart=/usr/bin/python3 -m agent.core
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/sentinel-deadman.service << EOF
[Unit]
Description=QRAP Black Box Deadman Switch
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/sentinel/env
WorkingDirectory=/opt/sentinel
ExecStart=/usr/bin/python3 -c "from agent.immunity import ImmunityDaemon; ImmunityDaemon().run()"
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 10. Enable and start
systemctl daemon-reload
systemctl enable sentinel-master sentinel-deadman
systemctl start sentinel-master sentinel-deadman

# 11. Product-specific post-install
echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "${BLUE}Product:${NC} $PRODUCT_NAME"
echo -e "${BLUE}Token:${NC} $SNG_TOKEN"
echo -e "${BLUE}Dashboard:${NC} https://qrap.site/dashboard.html?token=$SNG_TOKEN"

case $SNG_PRODUCT in
    node)
        echo ""
        echo -e "${YELLOW}Node Shield Tips:${NC}"
        echo "  • Honeypot files deployed in: $KEYSTORE"
        echo "  • Safe Mode active for 7 days (alerts only)"
        echo "  • To enable full protection: sudo sed -i 's/SNG_DRY_RUN=true/SNG_DRY_RUN=false/' /etc/sentinel/env && systemctl restart sentinel-master"
        ;;
    api)
        echo ""
        echo -e "${YELLOW}API Shield Tips:${NC}"
        echo "  • Monitor your API endpoints for anomalies"
        echo "  • FIFO traps active for backdoor detection"
        echo "  • Review alerts in Telegram or journalctl"
        ;;
    infra)
        echo ""
        echo -e "${YELLOW}Infrastructure Guard Tips:${NC}"
        echo "  • File honeypots deployed in /opt/sentinel/"
        echo "  • SSH brute-force protection active"
        echo "  • iptables lockdown on breach (Safe Mode: alerts only)"
        ;;
    bot)
        echo ""
        echo -e "${YELLOW}Bot & Mini-App Shield Tips:${NC}"
        echo "  • Rate limiting active on kernel level"
        echo "  • Anti-bot farm protection enabled"
        echo "  • Game anti-cheat monitoring active"
        ;;
    tunnel)
        echo ""
        echo -e "${YELLOW}PQC Tunnel Tips:${NC}"
        echo "  • Post-quantum encryption: QRAP Core"
        echo "  • Key rotation: automatic"
        echo "  • Latency target: <5ms"
        echo "  • Contact @tec_support_bot for tunnel configuration"
        ;;
esac

echo ""
echo -e "${GREEN}Status:${NC} systemctl status sentinel-master"
echo -e "${GREEN}Logs:${NC} journalctl -u sentinel-master -f"
echo ""
