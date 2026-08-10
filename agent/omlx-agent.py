#!/usr/bin/env python3
"""
omlx-agent — a tiny, dependency-free GPU/MEM metrics endpoint for Moon Gazer.

Run this on the machine you want Moon Gazer's OMLX pane to watch (e.g. the Mac
running your local model). It serves JSON on http://0.0.0.0:<port>/metrics with
the GPU utilization and memory usage. No sudo, no third-party packages.

    python3 omlx-agent.py            # serves on :8082
    python3 omlx-agent.py --port 9000

Apple Silicon only for GPU% (reads ioreg "Device Utilization %"). Memory works on
any macOS. Point Moon Gazer at it with:
    ~/.config/moongazer/config.json  ->  {"omlxUrl": "http://<this-host>:8082/metrics"}
"""
import argparse
import json
import re
import socket
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def gpu_percent():
    """Apple Silicon GPU utilization via ioreg (no sudo). None if unavailable."""
    try:
        out = subprocess.run(
            ["ioreg", "-r", "-d", "1", "-c", "IOAccelerator"],
            capture_output=True, text=True, timeout=4).stdout
    except Exception:
        return None
    vals = [int(m) for m in re.findall(r'"Device Utilization %"=(\d+)', out)]
    if not vals:
        vals = [int(m) for m in re.findall(r'"GPU Activity\(%\)"=(\d+)', out)]
    return max(vals) if vals else None


def memory():
    """(used_gb, total_gb, percent) — 'used' ≈ active + wired + compressed."""
    try:
        total = int(subprocess.run(["sysctl", "-n", "hw.memsize"],
                                   capture_output=True, text=True, timeout=4).stdout.strip())
        vm = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=4).stdout
    except Exception:
        return None, None, None
    page = 4096
    m = re.search(r"page size of (\d+) bytes", vm)
    if m:
        page = int(m.group(1))

    def pages(label):
        mm = re.search(rf"{label}:\s+(\d+)", vm)
        return int(mm.group(1)) if mm else 0

    used_pages = pages("Pages active") + pages("Pages wired down") + pages("Pages occupied by compressor")
    used = used_pages * page
    pct = round(used / total * 100, 1) if total else None
    return round(used / 1e9, 2), round(total / 1e9, 2), pct


def collect():
    used, total, pct = memory()
    return {
        "host": socket.gethostname().split(".")[0],
        "gpu": gpu_percent(),
        "mem_used_gb": used,
        "mem_total_gb": total,
        "mem_pct": pct,
    }


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.rstrip("/") not in ("", "/metrics"):
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(collect()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # quiet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8082)
    ap.add_argument("--host", default="0.0.0.0")
    args = ap.parse_args()
    print(f"omlx-agent serving on http://{args.host}:{args.port}/metrics")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
