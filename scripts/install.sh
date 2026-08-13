#!/bin/bash
pkg update -y && pkg install -y python python-pip git
pip install web3 requests pycryptodome psutil watchdog
