#!/bin/bash
cd ~/SNG-v1.0
pkill -f sng.core 2>/dev/null
sleep 1

cat > sng/honeypot.py << 'PYEOF'
import os
import time
import threading
from datetime import datetime
from pathlib import Path
from sng.config import HONEYPOT_DIR, ALERT_THRESHOLDS

class FileHoneypot:
    def __init__(self, alert_manager, circuit_breaker):
        self.alert = alert_manager
        self.cb = circuit_breaker
        self.snapshots = {}

    def run(self):
        self._deploy()
        files = self._get_files()
        for f in files:
            self._snapshot(f)
        print(f"[{datetime.now()}] FileHoneypot watching {len(files)} files (poll 0.5s)")
        while True:
            for f in files:
                if self._check(f):
                    self.alert.send("CRITICAL", "HONEYPOT_FILE_BREACH",
                                    f"Honeypot {f.name} was accessed/modified!")
                    if ALERT_THRESHOLDS["honeypot_access"]:
                        self.cb.trigger("HONEYPOT_FILE_BREACH")
            time.sleep(0.5)

    def _deploy(self):
        HONEYPOT_DIR.mkdir(parents=True, exist_ok=True)
        fake_key = HONEYPOT_DIR / "honeypot_wallet.key"
        if not fake_key.exists():
            fake_key.write_text('{"address":"0xFAKE_HONEYPOT_SNG","crypto":{"cipher":"aes-128-ctr","ciphertext":"DEADBEEF"},"version":3}')
            fake_key.chmod(0o600)
            print(f"[{datetime.now()}] Deployed file honeypot: {fake_key}")
        fake_config = HONEYPOT_DIR / "honeypot_config.json"
        if not fake_config.exists():
            fake_config.write_text('{"rpc_secret":"FAKE_SECRET_12345","api_key":"HONEYPOT_API_KEY"}')
            fake_config.chmod(0o600)
            print(f"[{datetime.now()}] Deployed file honeypot: {fake_config}")

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


class FifoHoneypot:
    def __init__(self, alert_manager, circuit_breaker):
        self.alert = alert_manager
        self.cb = circuit_breaker

    def run(self):
        HONEYPOT_DIR.mkdir(parents=True, exist_ok=True)
        fifo_path = HONEYPOT_DIR / "honeypot_fifo.key"
        if fifo_path.exists():
            fifo_path.unlink()
        try:
            os.mkfifo(str(fifo_path))
            print(f"[{datetime.now()}] FIFO Honeypot deployed (experimental): {fifo_path}")
        except Exception as e:
            print(f"[{datetime.now()}] FIFO deploy failed: {e}")
            return

        while True:
            try:
                fd = os.open(str(fifo_path), os.O_WRONLY | os.O_NONBLOCK)
                os.close(fd)
                self.alert.send("CRITICAL", "HONEYPOT_FIFO_BREACH",
                                "Intruder opened FIFO honeypot!")
                if ALERT_THRESHOLDS["honeypot_access"]:
                    self.cb.trigger("HONEYPOT_FIFO_BREACH")
                fifo_path.unlink()
                os.mkfifo(str(fifo_path))
            except OSError as e:
                if e.errno != 6:
                    pass
            except Exception:
                pass
            time.sleep(2)


class HoneypotWatcher:
    def __init__(self, alert_manager, circuit_breaker):
        self.alert = alert_manager
        self.cb = circuit_breaker

    def run(self):
        threading.Thread(target=FileHoneypot(self.alert, self.cb).run, daemon=True).start()
        FifoHoneypot(self.alert, self.cb).run()
PYEOF

# Удалить старый FIFO (toybox не ловит)
rm -f ~/.qrap/keystore/honeypot_fifo.key

# Пересоздать обычные файлы
mkdir -p ~/.qrap/keystore
echo '{"address":"0xFAKE_HONEYPOT_SNG","crypto":{"cipher":"aes-128-ctr","ciphertext":"DEADBEEF"},"version":3}' > ~/.qrap/keystore/honeypot_wallet.key
chmod 600 ~/.qrap/keystore/honeypot_wallet.key

# Запустить SNG
nohup python3 -u -m sng.core > sng.log 2>&1 &
sleep 3

echo "=== SNG v2.0 File+FIFO запущен ==="
cat sng.log | tail -10

echo ""
echo "=== ТЕСТ: меняем файл ==="
echo "INTRUDER_WAS_HERE" >> ~/.qrap/keystore/honeypot_wallet.key
sleep 2

echo ""
echo "=== РЕЗУЛЬТАТ ==="
cat sng.log | tail -10
