#!/bin/bash
set -e
echo "=== Sentinel Guard Uninstall ==="
systemctl stop sentinel-master sentinel-deadman 2>/dev/null || true
systemctl disable sentinel-master sentinel-deadman 2>/dev/null || true
rm -f /etc/systemd/system/sentinel-*.service
rm -rf /opt/sentinel-guard
rm -rf /var/log/sentinel
systemctl daemon-reload
echo "Uninstalled."
