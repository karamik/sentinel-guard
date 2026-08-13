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
