# Sentinel Guard
Active defense agent for blockchain validators.

## Install

    curl -fsSL https://raw.githubusercontent.com/karamik/sentinel-guard/main/scripts/install.sh | SNG_TOKEN=YOUR_TOKEN bash

## Architecture

- agent/core.py - Dual-Daemon (Master + Sentinel)
- agent/honeypot.py - File & FIFO honeypots
- agent/circuit_breaker.py - Kill switch, keystore lock, network isolation
- agent/heartbeat.py - HMAC-signed pulse to api.qrap.site
- agent/deadman.py - Passive lockdown if all guardians killed

## Requirements

- Ubuntu 20.04+ / Debian 11+
- Python 3.9+
- systemd

## Uninstall

    sudo bash scripts/uninstall.sh
