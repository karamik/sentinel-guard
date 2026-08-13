"""
SNG v2.1 — Deadman Switch (Переключатель Мертвеца)
Независимый процесс. Если Master не обновляет alive-файл >10 секунд —
автоматически блокирует keystore и убивает ноду.
"""

import os
import time
import json
from datetime import datetime
from pathlib import Path

ALIVE_FILE = Path.home() / ".qrap" / ".sng_alive"
KEYSTORE = Path.home() / ".qrap" / "keystore"
TIMEOUT = 10
CHECK_INTERVAL = 2

def lockdown(reason):
    print(f"[{datetime.now()}] DEADMAN: LOCKDOWN: {reason}")
    if KEYSTORE.exists():
        os.system(f"chmod -R 000 {KEYSTORE} 2>/dev/null")
        print(f"[{datetime.now()}] DEADMAN: Keystore locked (chmod 000)")
    os.system("pkill -9 -f 'geth|qrap-node|total-node' 2>/dev/null")
    log_dir = Path("/data/data/com.termux/files/usr/var/log/sng")
    log_dir.mkdir(parents=True, exist_ok=True)
    with open(log_dir / "deadman.log", "a") as f:
        f.write(json.dumps({
            "timestamp": datetime.now().isoformat(),
            "reason": reason,
            "action": "lockdown"
        }) + "\n")

def main():
    print(f"[{datetime.now()}] DEADMAN SWITCH armed. Timeout {TIMEOUT}s. PID {os.getpid()}")
    ALIVE_FILE.parent.mkdir(parents=True, exist_ok=True)
    ALIVE_FILE.write_text(str(time.time()))
    while True:
        time.sleep(CHECK_INTERVAL)
        if not ALIVE_FILE.exists():
            lockdown("alive_file_missing")
            break
        try:
            ts = float(ALIVE_FILE.read_text().strip())
        except Exception:
            lockdown("alive_file_corrupted")
            break
        if time.time() - ts > TIMEOUT:
            lockdown("alive_file_stale")
            break
    while True:
        time.sleep(60)

if __name__ == "__main__":
    main()
