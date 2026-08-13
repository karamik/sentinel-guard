"""
Alert Manager — Telegram через curl (Termux-stable)
"""

import json
import os
from datetime import datetime
from pathlib import Path

from sng.config import TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, LOG_DIR, NODE_NAME


class AlertManager:
    def __init__(self):
        self.log_file = LOG_DIR / "alerts.jsonl"

    def send(self, severity, code, message):
        alert = {
            "timestamp": datetime.now().isoformat(),
            "node": NODE_NAME,
            "severity": severity,
            "code": code,
            "message": message
        }

        with open(self.log_file, "a") as f:
            f.write(json.dumps(alert) + "\n")

        icon = {"INFO": "ℹ️ ", "HIGH": "⚠️ ", "CRITICAL": "🚨 "}.get(severity, "• ")
        print(f"{icon}[{datetime.now()}] [{severity}] {code}: {message}")

        self._telegram(alert)

    def _telegram(self, alert):
        if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
            return
        text = f"SNG Alert | {NODE_NAME}\n{alert['severity']} | {alert['code']}\n{alert['message']}\n{alert['timestamp']}"
        cmd = (
            f'curl -s -X POST "https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage" '
            f'-d "chat_id={TELEGRAM_CHAT_ID}" '
            f'-d "text={text}" > /dev/null 2>&1'
        )
        os.system(cmd)
