import os
import time
import json
from datetime import datetime
from pathlib import Path
from sng.config import LOG_DIR, CIRCUIT_BREAKER_ACTIONS

class CircuitBreaker:
    def __init__(self):
        self.triggered = False
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        self.log_file = LOG_DIR / "circuit_breaker.log"

    def trigger(self, reason):
        if self.triggered:
            return
        self.triggered = True

        entry = {
            "timestamp": datetime.now().isoformat(),
            "reason": reason,
            "actions": []
        }

        print(f"\n{'='*60}")
        print(f" CIRCUIT BREAKER ACTIVATED: {reason}")
        print(f"{'='*60}")

        if CIRCUIT_BREAKER_ACTIONS.get("stop_node", True):
            os.system("pkill -9 -f 'geth|qrap-node|total-node' 2>/dev/null")
            entry["actions"].append("kill_node")
            print(f"[{datetime.now()}] Node processes killed (-9)")

        if CIRCUIT_BREAKER_ACTIONS.get("isolate_network", True):
            os.system("termux-wifi-enable false 2>/dev/null")
            entry["actions"].append("isolate_network")
            print(f"[{datetime.now()}] Network isolation attempted")

        if CIRCUIT_BREAKER_ACTIONS.get("dormant_mode", True):
            self.dormant_mode(reason)
            entry["actions"].append("dormant_mode")

        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def dormant_mode(self, reason):
        print(f"[{datetime.now()}] Entering DORMANT MODE: {reason}")
        for key in ["QRAP_RPC", "SNG_SIGNING_KEY", "SNG_BOT_TOKEN", "SNG_CHAT_ID"]:
            if key in os.environ:
                os.environ[key] = "REDACTED"
        print(f"[{datetime.now()}] DORMANT MODE active. Agent is silent.")
