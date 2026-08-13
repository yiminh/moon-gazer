// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-blue; icon-glyph: moon;
//
// Moon Gazer — iPhone widget
// Reads the live snapshot your Mac publishes to a secret GitHub Gist.
// Small / Medium / Large, each designed for its size (not a shrunk desktop view).

const RAW_URL = "__RAW_URL__";

// ---- palette (bright, matches the app's Cupertino accents) -------------------
const BG = "#0E0E12";
const C = {
  claude: "#FF7A66", codex: "#3DD6A8", omlx: "#5FD0E0",
  warn: "#F2BF40", danger: "#F0594D", green: "#4DC772", amber: "#F2BF40",
};
const white = (a) => new Color("#FFFFFF", a);
const TXT1 = white(0.95), TXT2 = white(0.55), TXT3 = white(0.32);

// ---- helpers ----------------------------------------------------------------
function mono(size) { return new Font("Menlo", size); }
function clamp(v, a, b) { return Math.min(Math.max(v, a), b); }

function shortDur(secs) {
  secs = Math.max(0, Math.floor(secs));
  if (secs < 3600) return Math.floor(secs / 60) + "m";
  const h = Math.floor(secs / 3600);
  if (h < 24) return h + "h";
  return Math.floor(h / 24) + "d " + (h % 24) + "h";
}

// fraction (0..1) of a window's time that has elapsed — the pace tick position
function elapsedFrac(win, now) {
  if (!win || win.resetsAt == null || win.seconds == null || win.seconds <= 0) return null;
  return clamp((win.seconds - (win.resetsAt - now)) / win.seconds, 0, 1);
}

function txt(stack, s, font, color) {
  const t = stack.addText(String(s));
  t.font = font; t.textColor = color; t.lineLimit = 1;
  return t;
}

// A crisp bar drawn with DrawContext: rounded track + fill + optional time tick.
function barImage(w, h, pct, colorHex, frac) {
  const S = 3, W = w * S, H = h * S, r = H / 2;
  const ctx = new DrawContext();
  ctx.size = new Size(W, H);
  ctx.opaque = false; ctx.respectScreenScale = false;
  const rect = (x, ww) => { const p = new Path(); p.addRoundedRect(new Rect(x, 0, ww, H), r, r); ctx.addPath(p); ctx.fillPath(); };
  ctx.setFillColor(white(0.12)); rect(0, W);
  const fw = Math.max(H, (W * clamp(pct, 0, 100)) / 100);
  ctx.setFillColor(new Color(pct >= 90 ? C.danger : colorHex, 1)); rect(0, fw);
  if (frac != null) {
    const tw = Math.max(2, Math.round(S * 0.9));
    const x = clamp(frac * W, 0, W - tw);
    ctx.setFillColor(white(0.9));
    ctx.fillRect(new Rect(x, 0, tw, H));
  }
  return ctx.getImage();
}
function addBar(stack, w, h, pct, colorHex, frac) {
  const img = stack.addImage(barImage(w, h, pct, colorHex, frac));
  img.imageSize = new Size(w, h);
  return img;
}

function txtFit(stack, s, font, color, scale) {
  const t = txt(stack, s, font, color);
  t.minimumScaleFactor = scale;
  return t;
}
function hero(col, pct) {
  const hr = col.addStack();
  hr.centerAlignContent();
  txt(hr, pct == null ? "--" : pct, mono(36), TXT1);
  txt(hr, "%", mono(16), TXT2);
}
const SEC = 11; // secondary text size shared by Claude/Codex reset and OMLX numbers

// =============================================================================
// MEDIUM — three columns; one big number + one bar + one text line each.
// =============================================================================
function renderMedium(w, data, now) {
  w.setPadding(14, 16, 12, 16);
  const barW = 92;
  const body = w.addStack();
  body.spacing = 0;
  mediumColumn(body, "CLAUDE", C.claude, data.claude, barW, now);
  body.addSpacer();
  mediumColumn(body, "CODEX", C.codex, data.codex, barW, now);
  body.addSpacer();
  mediumOMLX(body, data.omlx, barW);
  w.addSpacer(8);
  footer(w, data, now);
}

function mediumColumn(body, name, accentHex, d, barW, now) {
  const col = body.addStack();
  col.layoutVertically(); col.spacing = 0;
  const h = col.addStack(); h.centerAlignContent();
  txt(h, name, mono(12), new Color(accentHex, 1));
  h.addSpacer();
  if (d && d.plan) txt(h, d.plan, mono(9), TXT3);
  col.addSpacer(8);

  const weekly = d && d.windows && d.windows[0];
  if (d && d.error && !weekly) { txt(col, "--", mono(36), TXT3); return; }
  hero(col, weekly ? weekly.pct : null);
  col.addSpacer(5);
  addBar(col, barW, 7, weekly ? weekly.pct : 0, accentHex, elapsedFrac(weekly, now));
  col.addSpacer(6);
  if (weekly && weekly.resetsAt) txtFit(col, "resets in " + shortDur(weekly.resetsAt - now), mono(SEC), TXT2, 0.6);
}

function mediumOMLX(body, o, barW) {
  const col = body.addStack();
  col.layoutVertically(); col.spacing = 0;
  const h = col.addStack(); h.centerAlignContent();
  txt(h, "OMLX", mono(12), new Color(C.omlx, 1));
  h.addSpacer();
  const online = o ? !!o.online : false;
  const dot = h.addText(online ? "● " : "○ ");
  dot.font = mono(9); dot.textColor = new Color(online ? C.green : C.danger, 1);
  txt(h, "MLX", mono(9), TXT3);
  col.addSpacer(8);

  if (!o || !o.configured) { txt(col, "off", mono(20), TXT3); return; }
  if (!online) { txt(col, "--", mono(36), TXT3); col.addSpacer(4); txt(col, "offline", mono(SEC), new Color(C.amber, 1)); return; }
  hero(col, o.gpu);
  col.addSpacer(5);
  addBar(col, barW, 7, o.gpu == null ? 0 : o.gpu, C.omlx, null);
  col.addSpacer(6);
  // MEM% | PP | TG — spread left / center / right
  const r = col.addStack(); r.centerAlignContent();
  txt(r, o.memPct == null ? "--" : o.memPct + "%", mono(SEC), TXT1);
  r.addSpacer();
  if (o.ppTps != null) txt(r, "" + o.ppTps, mono(SEC), TXT2);
  r.addSpacer();
  if (o.tgTps != null) txt(r, "" + o.tgTps, mono(SEC), TXT1);
}

function memColor(p) { return p >= 90 ? C.danger : (p >= 70 ? C.warn : C.omlx); }

// =============================================================================
// LARGE — three stacked bands (top/middle/bottom), one per provider, full width.
// =============================================================================
function renderLarge(w, data, now) {
  w.setPadding(16, 18, 14, 18);
  band(w, "CLAUDE", C.claude, data.claude, now, false);
  divider(w);
  band(w, "CODEX", C.codex, data.codex, now, false);
  divider(w);
  bandOMLX(w, data.omlx);
  w.addSpacer();
  footer(w, data, now);
}

function divider(w) {
  w.addSpacer(9);
  const img = w.addImage(solidLine(300, 1, white(0.07)));
  img.imageSize = new Size(300, 1);
  w.addSpacer(9);
}
function solidLine(wd, ht, color) {
  const ctx = new DrawContext(); ctx.size = new Size(wd, ht); ctx.opaque = false; ctx.respectScreenScale = false;
  ctx.setFillColor(color); ctx.fillRect(new Rect(0, 0, wd, ht)); return ctx.getImage();
}

// A band: left = name + big % + plan; right = labelled bars, % right-aligned.
function band(w, name, accentHex, d, now) {
  const row = w.addStack();
  row.centerAlignContent();

  const left = row.addStack();
  left.layoutVertically(); left.spacing = 1;
  left.size = new Size(96, 0);
  txt(left, name, mono(13), new Color(accentHex, 1));
  const weekly = d && d.windows && d.windows[0];
  const session = d && d.windows && d.windows[1];
  const hr = left.addStack(); hr.centerAlignContent();
  txt(hr, weekly ? weekly.pct : "--", mono(40), TXT1);
  txt(hr, "%", mono(17), TXT2);
  if (d && d.plan) txt(left, d.plan, mono(10), TXT3);

  row.addSpacer(14);
  const right = row.addStack();
  right.layoutVertically(); right.spacing = 8;
  const barW = 196;
  if (weekly) bandBar(right, "Weekly", weekly, accentHex, barW, now);
  if (session) bandBar(right, "Session", session, accentHex, barW, now);
  else txt(right, "Session:  idle", mono(10), TXT3);
}

// "Label:"  [reset/note]        NN%   — the % is always last, same size everywhere.
function bandBar(stack, label, win, accentHex, barW, now) {
  bandRow(stack, label, win.resetsAt ? shortDur(win.resetsAt - now) : "", win.pct,
          accentHex, barW, elapsedFrac(win, now));
}
function bandRow(stack, label, note, pct, colorHex, barW, frac) {
  const top = stack.addStack();
  top.centerAlignContent();
  txt(top, label + ":", mono(11), TXT2);
  top.addSpacer();
  if (note) txt(top, note, mono(10), TXT3);
  top.addSpacer(8);
  txt(top, pct == null ? "--" : pct + "%", mono(12), TXT1);
  stack.addSpacer(3);
  addBar(stack, barW, 6, pct == null ? 0 : pct, colorHex, frac == null ? null : frac);
}

function bandOMLX(w, o) {
  const row = w.addStack();
  row.centerAlignContent();

  const left = row.addStack();
  left.layoutVertically(); left.spacing = 1;
  left.size = new Size(96, 0);
  const head = left.addStack(); head.centerAlignContent();
  txt(head, "OMLX", mono(13), new Color(C.omlx, 1));
  head.addSpacer(4);
  const online = o && o.online;
  const dot = head.addText(online ? "●" : "○");
  dot.font = mono(9); dot.textColor = new Color(online ? C.green : C.danger, 1);
  txt(left, (online && o.gpu != null) ? o.gpu : "--", mono(40), TXT1);
  txt(left, "MLX", mono(10), TXT3);

  row.addSpacer(14);
  const right = row.addStack();
  right.layoutVertically(); right.spacing = 8;
  const barW = 196;
  if (!o || !o.configured) { txt(right, "not set up", mono(11), TXT3); return; }
  if (!online) { txt(right, "offline", mono(12), new Color(C.amber, 1)); return; }

  // GPU row carries PP/TG (844/61) in the note slot — aligned above MEM's 47/96G.
  const ppTg = (o.ppTps != null && o.tgTps != null) ? (o.ppTps + "/" + o.tgTps) : "";
  bandRow(right, "GPU", ppTg, o.gpu, C.omlx, barW, null);
  const memNote = (o.memUsedGb != null) ? (o.memUsedGb.toFixed(0) + "/" + Math.round(o.memTotalGb) + "G") : "";
  bandRow(right, "MEM", memNote, o.memPct, memColor(o.memPct), barW, null);
  if (o.model) {
    const m = txt(right, o.model, mono(10), new Color(C.omlx, 1));
    m.lineLimit = 2; m.minimumScaleFactor = 0.7;
  }
}

// =============================================================================
// SMALL — three compact rows: name, %, a bar with tick.
// =============================================================================
function renderSmall(w, data, now) {
  w.setPadding(12, 13, 11, 13);
  const rows = [
    { name: "CLAUDE", accent: C.claude, w: firstWin(data.claude) },
    { name: "CODEX", accent: C.codex, w: firstWin(data.codex) },
    { name: "OMLX", accent: C.omlx, w: null, gpu: (data.omlx && data.omlx.online) ? data.omlx.gpu : null },
  ];
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    const pct = r.w ? r.w.pct : (r.gpu != null ? r.gpu : null);
    const line = w.addStack();
    line.centerAlignContent();
    txt(line, r.name, mono(10), new Color(r.accent, 1));
    line.addSpacer();
    txt(line, pct == null ? "--" : pct, mono(14), TXT1);
    txt(line, r.name === "OMLX" ? " gpu" : "%", mono(8), TXT3);
    w.addSpacer(3);
    addBar(w, 130, 5, pct == null ? 0 : pct, r.accent, r.w ? elapsedFrac(r.w, now) : null);
    if (i < rows.length - 1) w.addSpacer(9);
  }
  w.addSpacer();
  footer(w, data, now);
}
function firstWin(d) { return d && d.windows && d.windows[0] ? d.windows[0] : null; }

// ---- footer -----------------------------------------------------------------
function footer(w, data, now) {
  const f = w.addStack();
  f.centerAlignContent();
  const age = now - (data.updated || now);
  const stale = age > 300;
  txt(f, "updated " + shortDur(age) + " ago" + (stale ? " ⚠" : ""), mono(8), stale ? new Color(C.amber, 1) : TXT3);
  f.addSpacer();
  txt(f, "🌙", mono(9), TXT3);
}

// ---- main -------------------------------------------------------------------
async function main() {
  const w = new ListWidget();
  w.backgroundColor = new Color(BG);
  w.refreshAfterDate = new Date(Date.now() + 60 * 1000);
  const now = Math.floor(Date.now() / 1000);

  let data;
  try {
    const req = new Request(RAW_URL + (RAW_URL.includes("?") ? "&" : "?") + "t=" + Date.now());
    req.timeoutInterval = 15;
    data = await req.loadJSON();
  } catch (e) {
    w.setPadding(16, 16, 16, 16);
    txt(w, "Moon Gazer", mono(13), TXT1);
    txt(w, RAW_URL.indexOf("__RAW") === 0 ? "run setup on the Mac" : "can't reach feed", mono(10), new Color(C.amber, 1));
    return finish(w);
  }

  const fam = config.widgetFamily || "medium";
  if (fam === "small") renderSmall(w, data, now);
  else if (fam === "large" || fam === "extraLarge") renderLarge(w, data, now);
  else renderMedium(w, data, now);
  return finish(w);
}

function finish(w) {
  if (config.runsInWidget) Script.setWidget(w);
  else {
    const fam = config.widgetFamily;
    if (fam === "small") w.presentSmall();
    else if (fam === "large") w.presentLarge();
    else w.presentMedium();
  }
  Script.complete();
}

await main();
