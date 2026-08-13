"""
SNG v2.1 — Configuration
"""

import os
from pathlib import Path

CHAIN_ID = 888888
RPC_URL = os.getenv("QRAP_RPC", "http://localhost:8545")
NODE_NAME = os.getenv("QRAP_NODE_NAME", "sentinel-node-01")

FEESPLITTER_ADDRESS = os.getenv("QRAP_FEESPLITTER", "0x0000000000000000000000000000000000000000")
FEESPLITTER_GENESIS_HASH = os.getenv("QRAP_FEESPLITTER_HASH", "")

EXPECTED_SHARES = {
    "provers": 35,
    "validators": 25,
    "treasury": 20,
    "da": 15,
    "burn": 5
}

WATCHED_WALLETS = []

ALERT_THRESHOLDS = {
    "balance_drop_percent": 5.0,
    "suspicious_tx_value_eth": 100.0,
    "peer_change_count": 3,
    "cpu_spike_percent": 90.0,
    "honeypot_access": True,
    "contract_balance_drop": True,
}

CIRCUIT_BREAKER_ACTIONS = {
    "stop_node": True,
    "revoke_keys": False,
    "isolate_network": True,
    "dormant_mode": True,
}

# === TELEGRAM ===
TELEGRAM_BOT_TOKEN = "YOUR_BOT_TOKEN_HERE"
TELEGRAM_CHAT_ID = "438850682"

ALERT_SIGNING_KEY = os.getenv("SNG_SIGNING_KEY", "")

LOG_DIR = Path("/data/data/com.termux/files/usr/var/log/sng")
LOG_DIR.mkdir(parents=True, exist_ok=True)
HONEYPOT_DIR = Path.home() / ".qrap" / "keystore"
DB_PATH = LOG_DIR / "sng_threats.db"

USE_LOCAL_LLM = False
LLM_MODEL = "llama3.1:8b"
