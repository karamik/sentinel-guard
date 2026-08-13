import os
from pathlib import Path

ENV_FILE = Path("/etc/sentinel/env")
if ENV_FILE.exists():
    for line in ENV_FILE.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            os.environ.setdefault(k, v.strip())

CHAIN_ID = 888888
RPC_URL = os.getenv("QRAP_RPC", "http://localhost:8545")
NODE_NAME = os.getenv("QRAP_NODE_NAME", "sentinel-node-01")
NODE_TYPE = os.getenv("NODE_TYPE", "unknown")

TELEGRAM_BOT_TOKEN = os.getenv("SNG_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("SNG_CHAT_ID", "")
ALERT_SIGNING_KEY = os.getenv("SNG_SIGNING_KEY", "")

LOG_DIR = Path("/var/log/sentinel")
LOG_DIR.mkdir(parents=True, exist_ok=True)

KEYSTORE_PATH = os.getenv("KEYSTORE_PATH", str(Path.home() / ".sentinel" / "keystore"))
HONEYPOT_DIR = Path(KEYSTORE_PATH)
DB_PATH = LOG_DIR / "sentinel_threats.db"

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

USE_LOCAL_LLM = False
LLM_MODEL = "llama3.1:8b"
