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
