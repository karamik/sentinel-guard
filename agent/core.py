import os
import sys
import time
import hmac
import hashlib
import struct
import signal
import select
import threading
import subprocess
from datetime import datetime

from sng.config import NODE_NAME
from sng.alerting import AlertManager
from sng.circuit_breaker import CircuitBreaker
from sng.honeypot import HoneypotWatcher
from sng.immunity import Immunity

ALIVE_FILE = os.path.expanduser("~/.qrap/.sng_alive")

class SentinelCore:
    def __init__(self):
        self.alert = AlertManager()
        self.cb = CircuitBreaker()
        self.secret = os.urandom(32)
        self.pipe_r = None
        self.pipe_w = None

    def start(self):
        print(f"[{datetime.now()}] SNG v2.1 Deep Defense initializing on {NODE_NAME}")
        self.pipe_r, self.pipe_w = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(self.pipe_w)
            self._sentinel(self.pipe_r)
            os._exit(0)
        else:
            os.close(self.pipe_r)
            self._master(self.pipe_w)

    def _pipe_heartbeat(self, pipe_w):
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

    def _master(self, pipe_w):
        # СРАЗУ запускаем heartbeat — до всех остальных действий
        threading.Thread(target=self._pipe_heartbeat, args=(pipe_w,), daemon=True).start()

        Immunity.set_protection()
        print(f"[{datetime.now()}] Master PID {os.getpid()} armed.")
        self.alert.send("INFO", "SNG_V2_MASTER", "Dual-Daemon + Deadman armed.")

        # Deadman Switch
        subprocess.Popen([sys.executable, "-m", "sng.deadman"],
                         cwd=os.path.expanduser("~/SNG-v1.0"),
                         stdout=open(os.devnull, "w"),
                         stderr=subprocess.STDOUT)
        print(f"[{datetime.now()}] Deadman Switch launched.")

        # Alive heartbeat для Deadman
        threading.Thread(target=self._alive_heartbeat, daemon=True).start()

        # Honeypot
        threading.Thread(target=self._honeypot, daemon=True).start()

        # Main thread ждёт сигнала
        while True:
            time.sleep(1)

    def _alive_heartbeat(self):
        while True:
            try:
                with open(ALIVE_FILE, "w") as f:
                    f.write(str(time.time()))
            except Exception:
                pass
            time.sleep(5)

    def _sentinel(self, pipe_r):
        print(f"[{datetime.now()}] Sentinel PID {os.getpid()} watching Master")
        last_ping = time.time()

        while True:
            ready, _, _ = select.select([pipe_r], [], [], 0.15)
            if not ready:
                # Таймаут — проверяем, не слишком ли долго нет пинга (1.0 сек на старте/сеть)
                if time.time() - last_ping > 1.0:
                    self.cb.trigger("HEARTBEAT_LOST")
                    return
                continue

            len_bytes = os.read(pipe_r, 4)
            if len(len_bytes) == 0:
                self.cb.trigger("MASTER_DEAD_EOF")
                return

            length = struct.unpack(">I", len_bytes)[0]
            payload = b""
            while len(payload) < length:
                chunk = os.read(pipe_r, length - len(payload))
                if not chunk:
                    self.cb.trigger("MASTER_DEAD_EOF")
                    return
                payload += chunk

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
