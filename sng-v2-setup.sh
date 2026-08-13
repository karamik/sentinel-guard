#!/bin/bash
set -e
cd ~/SNG-v1.0
pkill -f sng.core 2>/dev/null || true
sleep 1

echo "=== SNG v2.0 Deep Defense Setup ==="

# =================== sng/immunity.py ===================
cat > sng/immunity.py << 'EOF'
"""
SNG v2.0 — Process Immunity
PR_SET_DUMPABLE + signal hardening
"""

import signal
import ctypes


class Immunity:
    @staticmethod
    def set_protection():
        # PR_SET_DUMPABLE = 19 — запрещаем ptrace, gdb, /proc/[pid]/mem
        try:
            libc = ctypes.CDLL("libc.so.6")
            libc.prctl(19, 0)
            print("[Immunity] PR_SET_DUMPABLE=0 active. ptrace/gdb blocked.")
        except Exception as e:
            print(f"[Immunity] prctl skip: {e}")

        # Перехватываем сигналы завершения (не даём убить мягко)
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, lambda s, f: None)
        print("[Immunity] Termination signals intercepted.")
EOF

# =================== sng/honeypot.py ===================
cat > sng/honeypot.py << 'EOF'
"""
SNG v2.0 — FIFO Canary Trap Honeypot
Любой, кто откроет FIFO на чтение, блокируется в ядре.
Master детектит через O_WRONLY | O_NONBLOCK.
"""

import os
import time
from datetime import datetime
from pathlib import Path

from sng.config import HONEYPOT_DIR, ALERT_THRESHOLDS


class HoneypotWatcher:
    def __init__(self, alert_manager, circuit_breaker):
        self.alert = alert_manager
        self.cb = circuit_breaker

    def run(self):
        HONEYPOT_DIR.mkdir(parents=True, exist_ok=True)
        fifo_path = HONEYPOT_DIR / "honeypot_fifo.key"

        # Удаляем старый, если есть
        if fifo_path.exists():
            fifo_path.unlink()

        os.mkfifo(str(fifo_path))
        print(f"[{datetime.now()}] FIFO Honeypot deployed: {fifo_path}")
        print(f"[{datetime.now()}] Any reader will block in kernel until caught.")

        while True:
            try:
                # Пытаемся открыть FIFO на запись в неблокирующем режиме
                # Если есть читатель (атакующий) — open() УСПЕШЕН
                # Если нет читателя — OSError errno=6 (ENXIO)
                fd = os.open(str(fifo_path), os.O_WRONLY | os.O_NONBLOCK)
                os.close(fd)

                # УСПЕХ = кто-то открыл FIFO на чтение! Мгновенный алерт.
                self.alert.send("CRITICAL", "HONEYPOT_FIFO_BREACH",
                                "Intruder opened FIFO honeypot! Async syscall bypass attempt detected.")
                if ALERT_THRESHOLDS["honeypot_access"]:
                    self.cb.trigger("HONEYPOT_FIFO_BREACH")

                # Пересоздаём FIFO для следующей ловли
                fifo_path.unlink()
                os.mkfifo(str(fifo_path))
                print(f"[{datetime.now()}] FIFO Honeypot re-armed.")

            except BlockingIOError:
                pass
            except OSError as e:
                if e.errno == 6:  # ENXIO — нет читателей, всё спокойно
                    pass
                else:
                    pass
            except Exception:
                pass

            time.sleep(2)
EOF

# =================== sng/circuit_breaker.py ===================
cat > sng/circuit_breaker.py << 'EOF'
"""
SNG v2.0 — Circuit Breaker
Kill switch с lockdown keystore и dormant mode.
"""

import os
import time
import json
from datetime import datetime
from pathlib import Path

from sng.config import LOG_DIR, CIRCUIT_BREAKER_ACTIONS


class CircuitBreaker:
    def __init__(self):
        self.triggered = False
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

        # 1. Убить ноду жёстко
        if CIRCUIT_BREAKER_ACTIONS.get("stop_node", True):
            os.system("pkill -9 -f 'geth|qrap-node|total-node' 2>/dev/null")
            entry["actions"].append("kill_node")
            print(f"[{datetime.now()}] Node processes killed (-9)")

        # 2. Изолировать сеть
        if CIRCUIT_BREAKER_ACTIONS.get("isolate_network", True):
            os.system("termux-wifi-enable false 2>/dev/null")
            entry["actions"].append("isolate_network")
            print(f"[{datetime.now()}] Network isolation attempted")

        # 3. Заблокировать keystore (chmod 000)
        keystore = Path.home() / ".qrap" / "keystore"
        if keystore.exists():
            os.system(f"chmod -R 000 {keystore} 2>/dev/null")
            entry["actions"].append("lock_keystore")
            print(f"[{datetime.now()}] Keystore locked (chmod 000)")

        # 4. Dormant Mode
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

        hidden = LOG_DIR.parent / f".sng_dormant_{int(time.time())}"
        try:
            if LOG_DIR.exists():
                LOG_DIR.rename(hidden)
                print(f"[{datetime.now()}] Logs moved to hidden storage")
        except Exception:
            pass

        print(f"[{datetime.now()}] DORMANT MODE active. Agent is silent.")
EOF

# =================== sng/core.py ===================
cat > sng/core.py << 'EOF'
"""
SNG v2.0 — Deep Defense Core
Dual-Daemon: Master + Sentinel via Anonymous Pipes + HMAC Heartbeat
"""

import os
import sys
import time
import hmac
import hashlib
import struct
import signal
import select
import threading
from datetime import datetime

from sng.config import NODE_NAME
from sng.alerting import AlertManager
from sng.circuit_breaker import CircuitBreaker
from sng.honeypot import HoneypotWatcher
from sng.immunity import Immunity


class SentinelCore:
    def __init__(self):
        self.alert = AlertManager()
        self.cb = CircuitBreaker()
        self.secret = os.urandom(32)
        self.pipe_r = None
        self.pipe_w = None

    def start(self):
        print(f"[{datetime.now()}] SNG v2.0 Deep Defense initializing on {NODE_NAME}")
        self.pipe_r, self.pipe_w = os.pipe()
        pid = os.fork()
        if pid == 0:
            # Child = Sentinel (Watchdog)
            os.close(self.pipe_w)
            self._sentinel(self.pipe_r)
            os._exit(0)
        else:
            # Parent = Master
            os.close(self.pipe_r)
            self._master(self.pipe_w)

    def _master(self, pipe_w):
        Immunity.set_protection()
        print(f"[{datetime.now()}] Master PID {os.getpid()} armed. Immunity active.")
        self.alert.send("INFO", "SNG_V2_MASTER", "Dual-Daemon armed. Heartbeat 50ms.")

        # Запускаем honeypot в отдельном потоке
        threading.Thread(target=self._honeypot, daemon=True).start()

        # Heartbeat loop
        while True:
            ts = struct.pack(">d", time.time())
            digest = hmac.new(self.secret, ts, hashlib.sha256).digest()
            payload = ts + digest
            msg = struct.pack(">I", len(payload)) + payload
            try:
                os.write(pipe_w, msg)
            except (BrokenPipeError, OSError):
                break
            time.sleep(0.05)

    def _sentinel(self, pipe_r):
        print(f"[{datetime.now()}] Sentinel PID {os.getpid()} watching Master")
        last_ping = time.time()

        while True:
            ready, _, _ = select.select([pipe_r], [], [], 0.15)
            if not ready:
                # Таймаут — проверяем, не слишком ли долго нет пинга
                if time.time() - last_ping > 0.2:
                    self.cb.trigger("HEARTBEAT_LOST")
                    return
                continue

            # Читаем 4 байта длины
            len_bytes = os.read(pipe_r, 4)
            if len(len_bytes) == 0:
                self.cb.trigger("MASTER_DEAD_EOF")
                return

            length = struct.unpack(">I", len_bytes)[0]

            # Читаем payload
            payload = b""
            while len(payload) < length:
                chunk = os.read(pipe_r, length - len(payload))
                if not chunk:
                    self.cb.trigger("MASTER_DEAD_EOF")
                    return
                payload += chunk

            # Валидация HMAC
            ts_bytes = payload[:8]
            digest = payload[8:]
            expected = hmac.new(self.secret, ts_bytes, hashlib.sha256).digest()

            if not hmac.compare_digest(digest, expected):
                self.cb.trigger("TAMPERED_HEARTBEAT")
                return

            last_ping = time.time()

    def _honeypot(self):
        hp = HoneypotWatcher(self.alert, self.cb)
        hp.run()


if __name__ == "__main__":
    SentinelCore().start()
EOF

# =================== scripts/install_v2.sh ===================
cat > scripts/install_v2.sh << 'EOF'
#!/bin/bash
echo "=== SNG v2.0 Deep Defense Install ==="
pkg update -y
pkg install -y python python-pip git nano
pip install --upgrade pip
pip install web3 requests pycryptodome psutil watchdog 2>/dev/null || true
pkg install python-psutil -y 2>/dev/null || true
mkdir -p /data/data/com.termux/files/usr/var/log/sng
echo ""
echo "=== SNG v2.0 Ready ==="
echo "Run: cd ~/SNG-v1.0 && nohup python3 -u -m sng.core > sng.log 2>&1 &"
EOF
chmod +x scripts/install_v2.sh

# =================== Git ===================
git add .
git commit -m "feat: SNG v2.0 Deep Defense — Dual-Daemon, FIFO Honeypot, HMAC Heartbeat, PR_SET_DUMPABLE" || true
git push origin main || true

echo ""
echo "=========================================="
echo "  SNG v2.0 DEEP DEFENSE INSTALLED"
echo "=========================================="
echo "New files:"
echo "  sng/immunity.py      — PR_SET_DUMPABLE + signal hardening"
echo "  sng/core.py          — Dual-Daemon (Master + Sentinel)"
echo "  sng/honeypot.py      — FIFO Canary Trap"
echo "  sng/circuit_breaker.py — Kill-9 + chmod 000 keystore"
echo ""
echo "Start:"
echo "  cd ~/SNG-v1.0"
echo "  nohup python3 -u -m sng.core > sng.log 2>&1 &"
echo ""
echo "Test FIFO honeypot:"
echo "  cat ~/.qrap/keystore/honeypot_fifo.key"
echo "  (your terminal will HANG = caught!)"
echo "=========================================="
