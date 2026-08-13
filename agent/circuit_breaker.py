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

    def trigger(self, reason, severity="HIGH"):
        if self.triggered:
            return
        self.triggered = True
        from agent.config import SNG_DRY_RUN
        import time
        abort_file = "/tmp/sentinel_abort"
        if os.path.exists(abort_file):
            os.remove(abort_file)
        print(f"[{datetime.now()}] LOCKDOWN in 5 seconds. Create /tmp/sentinel_abort to abort.")
        self.alert.send("CRITICAL", "LOCKDOWN_PENDING", f"{reason}. Abort with: touch /tmp/sentinel_abort")
        for i in range(5, 0, -1):
            time.sleep(1)
            if os.path.exists(abort_file):
                os.remove(abort_file)
                print(f"[{datetime.now()}] LOCKDOWN ABORTED by user.")
                self.alert.send("INFO", "LOCKDOWN_ABORTED", "User aborted lockdown via /tmp/sentinel_abort")
                return
        if SNG_DRY_RUN:
        from agent.config import SEVERITY_LEVELS
        level = SEVERITY_LEVELS.get(severity, SEVERITY_LEVELS["HIGH"])
        if not level.get("circuit_breaker", True):
            print(f"[{datetime.now()}] MEDIUM threat: {reason}. Alert sent. Node NOT killed (circuit_breaker disabled for this level).")
            self.alert.send("HIGH", f"THREAT_{severity}", f"{reason}. Circuit Breaker suppressed by severity level.")
            return
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
