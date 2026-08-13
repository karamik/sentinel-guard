#!/bin/bash
cd ~/SNG-v1.0
pkill -f sng.core 2>/dev/null
sleep 1

# 1. Разблокировать keystore
chmod 700 ~/.qrap/keystore 2>/dev/null
rm -f ~/.qrap/keystore/honeypot_fifo.key

# 2. Пересоздать файлы
echo '{"address":"0xFAKE_HONEYPOT_SNG","crypto":{"cipher":"aes-128-ctr","ciphertext":"DEADBEEF"},"version":3}' > ~/.qrap/keystore/honeypot_wallet.key
chmod 600 ~/.qrap/keystore/honeypot_wallet.key

# 3. Убрать FIFO, оставить только FileHoneypot (работает в Termux)
cat > sng/honeypot.py << 'PYEOF'
import os
import time
from datetime import datetime
from pathlib import Path
from sng.config import HONEYPOT_DIR, ALERT_THRESHOLDS

class HoneypotWatcher:
    def __init__(self, alert_manager, circuit_breaker):
        self.alert = alert_manager
        self.cb = circuit_breaker
        self.snapshots = {}

    def run(self):
        self._deploy()
        files = self._get_files()
        for f in files:
            self._snapshot(f)
        print(f"[{datetime.now()}] Honeypot watching {len(files)} files (poll 0.5s)")
        while True:
            for f in files:
                if self._check(f):
                    self.alert.send("CRITICAL", "HONEYPOT_BREACH",
                                    f"Honeypot {f.name} was accessed/modified!")
                    if ALERT_THRESHOLDS["honeypot_access"]:
                        self.cb.trigger("HONEYPOT_BREACH")
            time.sleep(0.5)

    def _deploy(self):
        HONEYPOT_DIR.mkdir(parents=True, exist_ok=True)
        fake_key = HONEYPOT_DIR / "honeypot_wallet.key"
        if not fake_key.exists():
            fake_key.write_text('{"address":"0xFAKE_HONEYPOT_SNG","crypto":{"cipher":"aes-128-ctr","ciphertext":"DEADBEEF"},"version":3}')
            fake_key.chmod(0o600)
            print(f"[{datetime.now()}] Deployed honeypot: {fake_key}")
        fake_config = HONEYPOT_DIR / "honeypot_config.json"
        if not fake_config.exists():
            fake_config.write_text('{"rpc_secret":"FAKE_SECRET_12345","api_key":"HONEYPOT_API_KEY"}')
            fake_config.chmod(0o600)
            print(f"[{datetime.now()}] Deployed honeypot: {fake_config}")

    def _get_files(self):
        return [f for f in HONEYPOT_DIR.iterdir()
                if "honeypot" in f.name.lower() or "fake" in f.name.lower()]

    def _snapshot(self, path):
        try:
            s = path.stat()
            self.snapshots[str(path)] = (s.st_size, s.st_mtime_ns)
        except Exception:
            pass

    def _check(self, path):
        try:
            s = path.stat()
            old = self.snapshots.get(str(path))
            current = (s.st_size, s.st_mtime_ns)
            if old and old != current:
                return True
            self.snapshots[str(path)] = current
            return False
        except Exception:
            return False
PYEOF

# 4. Починить CircuitBreaker (создавать папку логов)
cat > sng/circuit_breaker.py << 'PYEOF'
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
PYEOF

# 5. Запустить SNG
mkdir -p /data/data/com.termux/files/usr/var/log/sng
nohup python3 -u -m sng.core > sng.log 2>&1 &
sleep 3

echo "=== SNG v2.0 (FileHoneypot only) запущен ==="
cat sng.log | tail -8

# 6. Тест
echo ""
echo ">>> ТЕСТ: меняем honeypot-файл..."
echo "INTRUDER_WAS_HERE" >> ~/.qrap/keystore/honeypot_wallet.key
sleep 2

echo ""
echo "=== РЕЗУЛЬТАТ ==="
cat sng.log | tail -15
