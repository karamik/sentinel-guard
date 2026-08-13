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

from agent.config import NODE_NAME
from agent.alerting import AlertManager
from agent.circuit_breaker import CircuitBreaker
from agent.honeypot import HoneypotWatcher
from agent.immunity import Immunity
from agent.heartbeat import send_heartbeat

class SentinelCore:
    def __init__(self):
        self.alert = AlertManager()
        self.cb = CircuitBreaker()
        self.secret = os.urandom(32)
        self.pipe_r = None
        self.pipe_w = None

    def start(self):
        print(f"[{datetime.now()}] Sentinel Guard initializing on {NODE_NAME}")
        self.pipe_r, self.pipe_w = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(self.pipe_w)
            self._sentinel(self.pipe_r)
            os._exit(0)
        else:
            os.close(self.pipe_r)
            self._master(self.pipe_w)

    def _master(self, pipe_w):
        Immunity.set_protection()
        print(f"[{datetime.now()}] Master PID {os.getpid()} armed. Immunity active.")
        self.alert.send("INFO", "SENTINEL_MASTER", "Dual-Daemon armed. Heartbeat active.")
        threading.Thread(target=self._honeypot, daemon=True).start()
        threading.Thread(target=self._api_heartbeat, daemon=True).start()
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

    def _api_heartbeat(self):
        while True:
            if not send_heartbeat():
                self.alert.send("CRITICAL", "SUBSCRIPTION_EXPIRED", "Shutting down agent.")
                time.sleep(5)
                os._exit(0)
            time.sleep(30)

    def _sentinel(self, pipe_r):
        print(f"[{datetime.now()}] Sentinel PID {os.getpid()} watching Master")
        last_ping = time.time()
        while True:
            ready, _, _ = select.select([pipe_r], [], [], 0.15)
            if not ready:
                if time.time() - last_ping > 0.2:
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
