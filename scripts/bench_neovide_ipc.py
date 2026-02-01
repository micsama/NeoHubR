#!/usr/bin/env python3
import json
import socket
import sys
import time

# Config (edit here)
SOCK = "/tmp/neovide.sock"
COUNT = 10
SLEEP_SECS = 0.3
PATH_ARG = "."
DO_CREATE = True
DO_ACTIVATE = True


def send_rpc(payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8") + b"\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        s.connect(SOCK)
        s.sendall(data)
        buf = b""
        while True:
            try:
                chunk = s.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
            if b"\n" in buf:
                buf = buf.split(b"\n", 1)[0]
                break
    if not buf:
        return {}
    try:
        return json.loads(buf.decode("utf-8"))
    except Exception:
        return {}


def first_window_id(resp: dict) -> str:
    res = resp.get("result")
    if isinstance(res, list) and res:
        first = res[0]
        if isinstance(first, str):
            return first
        if isinstance(first, dict):
            return first.get("window_id") or first.get("id") or first.get("windowId") or ""
    if isinstance(res, dict):
        windows = res.get("windows")
        if isinstance(windows, list) and windows:
            first = windows[0]
            if isinstance(first, str):
                return first
            if isinstance(first, dict):
                return first.get("window_id") or first.get("id") or first.get("windowId") or ""
        return res.get("window_id") or res.get("id") or res.get("windowId") or ""
    return ""


def bench(label: str, payload: dict):
    start = time.perf_counter_ns()
    resp = send_rpc(payload)
    elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000
    print(f"{label}: {elapsed_ms:.2f}ms")
    return resp


def main():
    print(f"Socket: {SOCK}")
    print(f"Count: {COUNT} | Sleep: {SLEEP_SECS}s | DO_CREATE={int(DO_CREATE)} | DO_ACTIVATE={int(DO_ACTIVATE)}")

    for i in range(1, COUNT + 1):
        print(f"--- Iteration {i} ---")

        list_resp = bench("ListWindows", {"jsonrpc": "2.0", "id": 1, "method": "ListWindows"})
        list_id = first_window_id(list_resp)

        create_id = ""
        if DO_CREATE:
            create_resp = bench(
                "CreateWindow",
                {
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "CreateWindow",
                    "params": {"nvim_args": [PATH_ARG]},
                },
            )
            create_id = first_window_id(create_resp)

        if DO_ACTIVATE:
            target_id = list_id or create_id
            if target_id:
                bench(
                    "ActivateWindow",
                    {
                        "jsonrpc": "2.0",
                        "id": 3,
                        "method": "ActivateWindow",
                        "params": {"window_id": target_id},
                    },
                )
            else:
                print("ActivateWindow: skipped (no window_id)")

        time.sleep(SLEEP_SECS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
