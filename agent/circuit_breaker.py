import os
import time
import json
from datetime import datetime
from pathlib import Path
from agent.config import LOG_DIR, CIRCUIT_BREAKER_ACTIONS

class CircuitBreaker:
    def __init__(self):
        self.triggered = False
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        self.log_file = LOG_DIR / "circuit_breaker.log"

    def trigger(self, reason):
        if self.triggered:
            return
        self.triggered = True
        from agent.config import SNG_DRY_RUN
        if SNG_DRY_RUN:
            print(f"[{datetime.now()}] DRY RUN: Circuit Breaker WOULD trigger for: {reason}")
            self.alert.send("CRITICAL", "DRY_RUN_CIRCUIT_BREAKER", f"Would trigger: {reason}. Set SNG_DRY_RUN=false to enable.")
            return
        entry = {
            "timestamp": datetime.now().isoformat(),
            "reason": reason,
            "actions": []
        }
        print(f"\n{'='*60}")
        print(f" CIRCUIT BREAKER ACTIVATED: {reason}")
        print(f"{'='*60}")
        if CIRCUIT_BREAKER_ACTIONS.get("stop_node", True):
            os.system("pkill -9 -f 'geth|erigon|besu|qrap-node|sentinel-master' 2>/dev/null")
            entry["actions"].append("kill_node")
            print(f"[{datetime.now()}] Node processes killed (-9)")
        if CIRCUIT_BREAKER_ACTIONS.get("isolate_network", True):
            os.system("iptables -A OUTPUT -j DROP 2>/dev/null || true")
            entry["actions"].append("isolate_network")
            print(f"[{datetime.now()}] Network isolation attempted (iptables)")
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
