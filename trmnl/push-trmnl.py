#!/usr/bin/env python3
"""
Push the Moon Gazer snapshot to a TRMNL Private Plugin (Webhook strategy).

Runs MoonGazer --json, flattens it into a small, Liquid-friendly shape (reset
countdowns and pace are computed HERE so the plugin markup stays trivial), and
POSTs it to your plugin's webhook. Standard library only.

TRMNL webhook contract:
  POST https://usetrmnl.com/api/custom_plugins/<uuid>
  Content-Type: application/json
  body: {"merge_variables": { ... }}
  limits: 2 KB per payload, 12 posts/hour (5 KB / 30 per hour on TRMNL+).

Config — pick either:
  • env  TRMNL_WEBHOOK=https://usetrmnl.com/api/custom_plugins/<uuid>
  • file ~/.config/moongazer/trmnl.json  ->  {"webhook": "https://.../<uuid>"}

Usage:
  python3 push-trmnl.py            # build + POST
  python3 push-trmnl.py --dry-run  # print the payload, don't POST (for sample data)
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

SUP = os.path.expanduser("~/Library/Application Support/MoonGazer")
BIN = os.environ.get("MOONGAZER_BIN", os.path.join(SUP, "MoonGazer"))
CONFIG = os.path.expanduser("~/.config/moongazer/trmnl.json")


def webhook_url():
    env = os.environ.get("TRMNL_WEBHOOK")
    if env:
        return env.strip()
    try:
        return json.load(open(CONFIG))["webhook"].strip()
    except Exception:
        return None


def short_dur(secs):
    secs = max(0, int(secs))
    if secs < 3600:
        return f"{secs // 60}m"
    h = secs // 3600
    return f"{h}h" if h < 24 else f"{h // 24}d {h % 24}h"


def snapshot():
    raw = subprocess.run([BIN, "--json"], capture_output=True, text=True, timeout=45).stdout
    return json.loads(raw)


def pace(win, now):
    """(text, over, on, short) comparing usage% to elapsed-time% in the window.
    `short` is a compact chip: ▲ 12% / ▼ 32% / ● ON."""
    if not win or win.get("resetsAt") is None or not win.get("seconds"):
        return None
    frac = min(max((win["seconds"] - (win["resetsAt"] - now)) / win["seconds"], 0), 1)
    d = win["pct"] - frac * 100
    n = round(abs(d))
    if d > 8:
        return (f"{n}% OVER PACE", True, False, f"▲ {n}%")
    if d < -8:
        return (f"{n}% UNDER PACE", False, False, f"▼ {n}%")
    return ("ON PACE", False, True, "● ON")


def elapsed_pct(win, now):
    """How far through the window's TIME we are, 0-100 — the pace-tick position."""
    if not win or win.get("resetsAt") is None or not win.get("seconds"):
        return None
    frac = min(max((win["seconds"] - (win["resetsAt"] - now)) / win["seconds"], 0), 1)
    return round(frac * 100)


def tasks_summary(d):
    """Compact one-line activity for the bottom of a column: the running task if
    any (▸ prefix), else the most recent finished task, else empty."""
    d = d or {}
    tasks = d.get("tasks") or []
    working = int((d.get("counts") or {}).get("working") or 0)
    if working:
        for t in tasks:
            if t.get("state") == "working":
                return ("▸ " + (t.get("name") or "task"), True)
        return (f"▸ {working} RUNNING", True)
    for t in tasks:
        parts = [x for x in ((t.get("name") or "").strip(), (t.get("detail") or "").strip()) if x]
        if parts:
            return (" · ".join(parts), False)
    return ("", False)


def model_short(label):
    """Turn an extra-window label like 'GPT-5.3-Codex-Spark Weekly 7d' into a
    compact uppercase row label ('GPT-5.3-CODEX-SPARK')."""
    s = re.sub(r"\s+(Session \d+h|Daily 24h|Weekly 7d|Limit \d+d)$", "", label or "").strip()
    return s.upper() if s else "MODEL"


def provider(name, d, now):
    # windows come flattened as [weekly, (session?), *extra-model-quotas]; classify
    # by window LENGTH rather than position, since a null 5h session lets a model
    # quota slide into the old session slot (Codex GPT-5.3-Codex-Spark after upgrade).
    windows = (d or {}).get("windows") or []
    weekly = windows[0] if windows else None
    rest = windows[1:]
    session = next((w for w in rest if w.get("seconds") and w["seconds"] < 21_600), None)
    extras = [w for w in rest if w is not session]
    # secondary slot: real 5h session first, else the first model quota, else idle
    if session:
        sec, sec_label = session, "5H"
    elif extras:
        sec, sec_label = extras[0], model_short(extras[0].get("label"))
    else:
        sec, sec_label = None, "SESSION 5H"
    p = pace(weekly, now) if weekly else None
    task, task_working = tasks_summary(d)
    out = {
        "name": name,
        "plan": (d or {}).get("plan") or "",
        "weekly": round(weekly["pct"]) if weekly else None,
        "weekly_reset": short_dur(weekly["resetsAt"] - now) if weekly and weekly.get("resetsAt") else "",
        "weekly_elapsed": elapsed_pct(weekly, now),
        "has_sec": bool(sec),
        "sec_label": sec_label,
        "sec_pct": round(sec["pct"]) if sec else None,
        "sec_reset": short_dur(sec["resetsAt"] - now) if sec and sec.get("resetsAt") else "",
        "sec_elapsed": elapsed_pct(sec, now),
        "pace": p[0] if p else "",
        "pace_over": p[1] if p else False,
        "pace_on": p[2] if p else False,
        "pace_short": p[3] if p else "",
        "task": task,
        "task_working": task_working,
    }
    return out


def build(snap):
    import time
    now = int(time.time())
    o = snap.get("omlx") or {}
    omlx = {
        "configured": bool(o.get("configured")),
        "online": bool(o.get("online")),
        "gpu": round(o["gpu"]) if o.get("gpu") is not None else None,
        "mem": round(o["memPct"]) if o.get("memPct") is not None else None,
        "mem_gb": (f'{round(o["memUsedGb"])}/{round(o["memTotalGb"])}G'
                   if o.get("memUsedGb") is not None and o.get("memTotalGb") is not None else ""),
        "model": o.get("model") or "",
        "pp": o.get("ppTps"),
        "tg": o.get("tgTps"),
    }
    upd = int(snap.get("updated", now))
    age = now - upd
    return {
        "updated_ago": short_dur(age),
        "updated_at": time.strftime("%H:%M", time.localtime(upd)),
        "stale": age > 1800,
        "claude": provider("CLAUDE", snap.get("claude"), now),
        "codex": provider("CODEX", snap.get("codex"), now),
        "omlx": omlx,
    }


def main():
    dry = "--dry-run" in sys.argv
    payload = {"merge_variables": build(snapshot())}
    body = json.dumps(payload)
    if len(body.encode()) > 2048:
        print(f"warning: payload is {len(body.encode())} bytes (> 2KB TRMNL limit)", file=sys.stderr)
    if dry:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return
    url = webhook_url()
    if not url:
        sys.exit("no webhook configured — set TRMNL_WEBHOOK or ~/.config/moongazer/trmnl.json")
    # POST via curl: it uses the system CA bundle, so this works regardless of which
    # python is on PATH (python.org builds often lack certs -> SSL verify errors).
    r = subprocess.run(
        ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "-X", "POST", url,
         "-H", "Content-Type: application/json", "--data-binary", body],
        capture_output=True, text=True, timeout=25)
    code = (r.stdout or "").strip()
    if r.returncode != 0 or not code.startswith("2"):
        sys.exit(f"post failed (curl exit {r.returncode}, HTTP {code}) {r.stderr.strip()}")
    print(f"posted ({len(body.encode())}B) -> HTTP {code}")


if __name__ == "__main__":
    main()
