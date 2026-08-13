// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-blue; icon-glyph: moon;
//
// Moon Gazer — iPhone widget
// Reads the live snapshot your Mac publishes to a secret GitHub Gist and renders
// Claude / Codex / OMLX at a glance. Small, medium and large layouts.
//
// The Mac's setup script fills in the gist URL below (replaces __RAW_URL__).
// If you're wiring it by hand, paste your gist's raw URL here.

const RAW_URL = "__RAW_URL__";

// ---- palette (matches the Terminal template) --------------------------------
const BG = "#0E0E12";
const C = {
  claude: "#D9785A", codex: "#10A37F", omlx: "#7B8CFF",
  warn: "#F2BF40", danger: "#F0594D", green: "#4DC772", amber: "#F2BF40",
};
const white = (a) => new Color("#FFFFFF", a);
const TXT1 = white(0.92), TXT2 = white(0.58), TXT3 = white(0.34);

// ---- helpers ----------------------------------------------------------------
function mono(size) { return new Font("Menlo", size); }

function shortDur(secs) {
  secs = Math.max(0, Math.floor(secs));
  if (secs < 60) return secs + "s";
  const m = Math.floor(secs / 60);
  if (m < 60) return m + "m";
  const h = Math.floor(m / 60);
  if (h < 24) return h + "h " + (m % 60) + "m";
  return Math.floor(h / 24) + "d " + (h % 24) + "h";
}

function barColor(pct, accent) { return new Color(pct >= 90 ? C.danger : accent, 1); }

function addBar(stack, pct, accentHex, width, h) {
  h = h || 4;
  const track = stack.addStack();
  track.size = new Size(width, h);
  track.backgroundColor = white(0.09);
  track.cornerRadius = h / 2;
  const fill = track.addStack();
  fill.size = new Size(Math.max(h, (width * Math.min(Math.max(pct, 0), 100)) / 100), h);
  fill.backgroundColor = barColor(pct, accentHex);
  fill.cornerRadius = h / 2;
}

function txt(stack, s, font, color) {
  const t = stack.addText(String(s));
  t.font = font;
  t.textColor = color;
  t.lineLimit = 1;
  return t;
}

// pace: how usage compares to elapsed time in the window
function pace(win, now) {
  if (win == null || win.resetsAt == null || win.seconds == null) return null;
  const elapsed = win.seconds - (win.resetsAt - now);
  const frac = Math.min(Math.max(elapsed / win.seconds, 0), 1);
  return win.pct - frac * 100;
}

function statusLine(counts) {
  if (!counts) return { text: "—", color: TXT3 };
  if (counts.working > 0) return { text: "WORKING ×" + counts.working, color: new Color(C.green, 1) };
  if (counts.idle > 0) return { text: "IDLE ×" + counts.idle, color: new Color(C.amber, 1) };
  return { text: "QUIET", color: TXT3 };
}

// ---- provider column (Claude / Codex) ---------------------------------------
function providerColumn(parent, name, accentHex, d, barW, lg, now) {
  const col = parent.addStack();
  col.layoutVertically();
  col.spacing = lg ? 3 : 2;

  txt(col, name, mono(lg ? 12 : 11), new Color(accentHex, 1));
  if (d.error && (!d.windows || d.windows.length === 0)) {
    txt(col, "--", mono(22), TXT3);
    txt(col, d.error, mono(8), new Color(C.amber, 1)).lineLimit = 2;
    return col;
  }

  const weekly = d.windows && d.windows[0];
  const session = d.windows && d.windows[1];

  if (weekly) {
    const row = col.addStack();
    row.centerAlignContent();
    txt(row, weekly.pct, mono(lg ? 30 : 24), TXT1);
    txt(row, "%", mono(lg ? 13 : 11), TXT2);
    row.addSpacer();
    if (d.plan) txt(row, d.plan, mono(9), TXT3);
    addBar(col, weekly.pct, accentHex, barW, lg ? 5 : 4);
    const meta = col.addStack();
    txt(meta, weekly.label, mono(8), TXT3);
    meta.addSpacer();
    if (weekly.resetsAt) txt(meta, shortDur(weekly.resetsAt - now), mono(8), TXT3);
    if (lg) {
      const p = pace(weekly, now);
      if (p != null) {
        const s = Math.round(p);
        if (p > 8) txt(col, "▲ " + s + "% over pace", mono(8), new Color(p > 18 ? C.danger : C.amber, 1));
        else if (p < -8) txt(col, "▼ " + -s + "% under pace", mono(8), new Color(C.green, 1));
        else txt(col, "● on pace", mono(8), TXT3);
      }
    }
  }

  if (session) {
    col.addSpacer(lg ? 5 : 3);
    const row = col.addStack();
    txt(row, session.label, mono(8), TXT3);
    row.addSpacer();
    txt(row, session.pct + "%", mono(9), TXT2);
    addBar(col, session.pct, accentHex, barW, 3);
  } else if (name === "CODEX") {
    col.addSpacer(lg ? 5 : 3);
    txt(col, "5h · idle", mono(8), TXT3);
  }

  col.addSpacer();
  const st = statusLine(d.counts);
  txt(col, st.text, mono(lg ? 9 : 8), st.color);
  if (lg && d.tasks && d.tasks.length) {
    for (const t of d.tasks.slice(0, 3)) {
      const mark = t.state === "working" ? "●" : t.state === "idle" ? "○" : "✓";
      txt(col, mark + " " + t.name, mono(8), t.state === "finished" ? TXT2 : TXT1);
    }
  }
  return col;
}

// ---- OMLX column ------------------------------------------------------------
function omlxColumn(parent, o, barW, lg, now) {
  const col = parent.addStack();
  col.layoutVertically();
  col.spacing = lg ? 3 : 2;

  const head = col.addStack();
  head.centerAlignContent();
  txt(head, "OMLX", mono(lg ? 12 : 11), new Color(C.omlx, 1));
  head.addSpacer();
  const online = o && o.online;
  const dot = head.addText(online ? "●" : "○");
  dot.font = mono(8);
  dot.textColor = new Color(online ? C.green : C.danger, 1);

  if (!o || !o.configured) { txt(col, "not set up", mono(9), TXT3); return col; }
  if (!online) { txt(col, "--", mono(22), TXT3); txt(col, "offline", mono(9), new Color(C.amber, 1)); return col; }

  if (o.gpu != null) {
    const row = col.addStack();
    row.centerAlignContent();
    txt(row, o.gpu, mono(lg ? 30 : 24), TXT1);
    txt(row, "%", mono(lg ? 13 : 11), TXT2);
    row.addSpacer();
    txt(row, "GPU", mono(9), TXT3);
    addBar(col, o.gpu, C.omlx, barW, lg ? 5 : 4);
  }
  if (o.memPct != null) {
    col.addSpacer(lg ? 5 : 3);
    const row = col.addStack();
    txt(row, "MEM", mono(8), TXT3);
    row.addSpacer();
    if (lg && o.memUsedGb != null) txt(row, o.memUsedGb.toFixed(0) + "/" + Math.round(o.memTotalGb) + "G", mono(8), TXT3);
    txt(row, o.memPct + "%", mono(9), TXT2);
    addBar(col, o.memPct, o.memPct >= 90 ? C.danger : (o.memPct >= 70 ? C.warn : C.omlx), barW, 3);
  }
  if (lg) {
    if (o.model) { col.addSpacer(4); txt(col, "MODEL", mono(7), TXT3); txt(col, o.model, mono(8), new Color(C.omlx, 1)).lineLimit = 2; }
    const tp = col.addStack();
    if (o.ppTps != null) txt(tp, "PP " + o.ppTps, mono(8), TXT2);
    tp.addSpacer();
    if (o.tgTps != null) txt(tp, "TG " + o.tgTps, mono(8), TXT2);
  }
  col.addSpacer();
  return col;
}

// ---- small layout -----------------------------------------------------------
function renderSmall(w, data, now) {
  w.setPadding(12, 13, 12, 13);
  const rows = [
    { name: "CLAUDE", accent: C.claude, pct: pick(data.claude), sub: null },
    { name: "CODEX", accent: C.codex, pct: pick(data.codex), sub: null },
    { name: "OMLX", accent: C.omlx, pct: data.omlx && data.omlx.online ? data.omlx.gpu : null, sub: "GPU" },
  ];
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    const line = w.addStack();
    line.centerAlignContent();
    txt(line, r.name, mono(10), new Color(r.accent, 1));
    line.addSpacer();
    txt(line, r.pct == null ? "--" : r.pct + "%", mono(13), TXT1);
    w.addSpacer(3);
    addBar(w, r.pct == null ? 0 : r.pct, r.accent, 128, 4);
    if (i < rows.length - 1) w.addSpacer(8);
  }
  w.addSpacer();
  footer(w, data, now, true);
}
function pick(d) { return d && d.windows && d.windows[0] ? d.windows[0].pct : null; }

// ---- medium / large layout --------------------------------------------------
function renderColumns(w, data, lg, now) {
  w.setPadding(14, 15, 12, 15);
  const barW = lg ? 92 : 86;
  const body = w.addStack();
  body.spacing = 10;
  providerColumn(body, "CLAUDE", C.claude, data.claude, barW, lg, now);
  body.addSpacer();
  providerColumn(body, "CODEX", C.codex, data.codex, barW, lg, now);
  body.addSpacer();
  omlxColumn(body, data.omlx, barW, lg, now);
  w.addSpacer(6);
  footer(w, data, now, false);
}

function footer(w, data, now, small) {
  const f = w.addStack();
  const age = now - (data.updated || now);
  const stale = age > 300;
  const t = txt(f, (small ? "" : "updated ") + shortDur(age) + " ago" + (stale ? " ⚠" : ""),
    mono(small ? 7 : 8), stale ? new Color(C.amber, 1) : TXT3);
  f.addSpacer();
  if (!small) txt(f, "🌙", mono(8), TXT3);
}

// ---- main -------------------------------------------------------------------
async function main() {
  const w = new ListWidget();
  w.backgroundColor = new Color(BG);
  w.refreshAfterDate = new Date(Date.now() + 60 * 1000); // hint; iOS decides the real cadence
  const now = Math.floor(Date.now() / 1000);

  let data;
  try {
    const req = new Request(RAW_URL + (RAW_URL.includes("?") ? "&" : "?") + "t=" + Date.now());
    req.timeoutInterval = 15;
    data = await req.loadJSON();
  } catch (e) {
    txt(w, "Moon Gazer", mono(12), TXT1);
    txt(w, "can't reach feed", mono(9), new Color(C.amber, 1));
    txt(w, RAW_URL === "__RAW_URL__" ? "run setup on the Mac" : "offline?", mono(8), TXT3);
    return finish(w);
  }

  const fam = config.widgetFamily || "medium";
  if (fam === "small") renderSmall(w, data, now);
  else renderColumns(w, data, fam === "large" || fam === "extraLarge", now);
  return finish(w);
}

function finish(w) {
  if (config.runsInWidget) { Script.setWidget(w); }
  else {
    const fam = config.widgetFamily;
    if (fam === "small") w.presentSmall();
    else if (fam === "large") w.presentLarge();
    else w.presentMedium();
  }
  Script.complete();
}

await main();
