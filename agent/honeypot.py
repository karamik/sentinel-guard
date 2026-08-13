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
        self.last_alert = {}  # cooldown per file

    def run(self):
        self._deploy()
        files = self._get_files()
        for f in files:
            self._snapshot(f)
        print(f"[{datetime.now()}] Honeypot watching {len(files)} files (poll 0.5s)")
        while True:
            for f in files:
                if self._check(f):
                    # Cooldown: max 1 alert per 10 seconds per file
                    now = time.time()
                    if now - self.last_alert.get(str(f), 0) < 10:
                        continue
                    self.last_alert[str(f)] = now
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
            changed = old and old != current
            self.snapshots[str(path)] = current  # FIX: update always!
            return changed
        except Exception:
            return False
