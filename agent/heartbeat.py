import os
import time
import requests
from datetime import datetime

API_ENDPOINT = os.getenv("API_ENDPOINT", "https://api.qrap.site/v1/heartbeat")
SNG_TOKEN = os.getenv("SNG_TOKEN", "")
NODE_NAME = os.getenv("QRAP_NODE_NAME", "sentinel-node")

def send_heartbeat():
    if not SNG_TOKEN or not API_ENDPOINT:
        return True
    try:
        payload = {"token": SNG_TOKEN, "timestamp": int(time.time()), "node": NODE_NAME}
        r = requests.post(API_ENDPOINT, json=payload, timeout=10)
        data = r.json()
        status = data.get("status", "unknown")
        if status == "inactive":
            print(f"[{datetime.now()}] HEARTBEAT: subscription inactive. Shutting down.")
            return False
        return True
    except Exception as e:
        print(f"[{datetime.now()}] HEARTBEAT error: {e}")
        return True
