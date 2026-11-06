"""Caldova morning digest renderer: 2-page, calm, executive PDF from a JSON spec.

Usage: python3 build_digest.py digest.json out.pdf
Page 1 = app-health trend + issues handled by SRE Agent (thread + GitHub links, 1-2 prevention bullets).
Page 2 = security and cost recommendations (owner + issue link each).
Palette is intentionally calm: navy / teal / green / blue on white. No red or yellow.
"""
import json, sys, textwrap
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.patches import FancyBboxPatch, Rectangle, Circle

W, H = 13.333, 7.5
NAVY, SLATE, MUTED = "#172B4D", "#334155", "#64748B"
BLUE, TEAL, GREEN = "#0078D4", "#008272", "#107C41"
PBLUE, PTEAL, PGREEN, PGRAY = "#EAF3F8", "#E7F5F2", "#E8F4EC", "#F5F7FA"
BORDER, WHITE, SKY = "#D8DEE8", "#FFFFFF", "#7FB2DD"
TONE = {"green": (GREEN, PGREEN), "teal": (TEAL, PTEAL), "blue": (BLUE, PBLUE), "navy": (NAVY, PBLUE)}
plt.rcParams.update({"font.family": "DejaVu Sans", "pdf.fonttype": 42, "text.parse_math": False})

D = json.load(open(sys.argv[1]))
OUT = sys.argv[2]


def wrap(t, w_in, size, bold=False):
    return textwrap.fill(t, max(8, int(w_in * 72 / ((0.62 if bold else 0.56) * size))))


def page():
    fig = plt.figure(figsize=(W, H))
    ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
    return fig, ax


def fax(fig, x, y, w, h):
    return fig.add_axes([x / W, y / H, w / W, h / H])


def card(ax, x, y, w, h, fc=WHITE, ec=BORDER, top=None):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0,rounding_size=0.1", fc=fc, ec=ec, lw=0.9))
    if top:
        ax.add_patch(Rectangle((x + 0.1, y + h - 0.06), w - 0.2, 0.06, fc=top, ec="none"))


def chip(ax, x, y, text, tone="green", size=9):
    fg, bg = TONE[tone]
    w = len(text) * size * 0.62 / 72 + 0.26
    ax.add_patch(FancyBboxPatch((x, y - 0.13), w, 0.26, boxstyle="round,pad=0,rounding_size=0.13", fc=bg, ec="none"))
    ax.text(x + w / 2, y, text, fontsize=size, color=fg, weight="bold", ha="center", va="center")
    return w


def link(ax, x, y, text, url, ha="left", size=10):
    t = ax.text(x, y, text + " \u2192", fontsize=size, color=BLUE, weight="bold", ha=ha, va="center")
    t.set_url(url)
    return len(text + " >") * size * 0.62 / 72


def check(ax, x, y, tone="green"):
    fg, _ = TONE[tone]
    ax.add_patch(Circle((x, y), 0.1, fc=fg, ec="none"))
    ax.text(x, y - 0.005, "\u2713", fontsize=9, color=WHITE, ha="center", va="center", weight="bold")


def header(ax, eyebrow, title, sub):
    ax.text(0.6, 7.02, eyebrow, fontsize=10.5, color=TEAL, weight="bold", va="center")
    ax.text(0.6, 6.7, title, fontsize=26, color=NAVY, weight="bold", va="top")
    ax.text(0.6, 6.12, sub, fontsize=13, color=SLATE, va="top")


def footer(ax, text, n):
    ax.plot([0.6, W - 0.6], [0.55, 0.55], color=BORDER, lw=0.8)
    ax.text(0.6, 0.38, text, fontsize=8.5, color=MUTED, va="center")
    ax.text(W - 0.6, 0.38, f"{D['brand']}  |  {D['date_label']}  |  {n} of 2", fontsize=8.5, color=MUTED,
            va="center", ha="right")


pdf = PdfPages(OUT, metadata={"Title": D["title_meta"], "Author": D["brand"]})

# ======================= PAGE 1: health + handled issues
P = D["page1"]
fig, ax = page()
header(ax, P["eyebrow"], P["title"], P["subtitle"])

LX, LW = 0.6, 6.85
# KPI tiles
kp = P["kpis"]; kw = (LW - 0.18 * (len(kp) - 1)) / len(kp)
for i, k in enumerate(kp):
    x = LX + i * (kw + 0.18)
    fg, bg = TONE[k.get("tone", "navy")]
    card(ax, x, 4.72, kw, 0.95, fc=bg if k.get("highlight") else WHITE)
    ax.text(x + 0.18, 5.33, k["value"], fontsize=20, color=fg if k.get("highlight") else NAVY, weight="bold", va="center")
    ax.text(x + 0.18, 4.93, k["label"], fontsize=9.5, color=SLATE, va="center")

# trend chart
T = P["trend"]
card(ax, LX, 0.8, LW, 3.72)
ax.text(LX + 0.22, 4.24, T["title"], fontsize=12, color=NAVY, weight="bold", va="center")
lx = LX + LW - 0.22
for s in reversed(T["series"]):
    w = len(s["name"]) * 9.5 * 0.56 / 72
    ax.text(lx, 4.24, s["name"], fontsize=9.5, color=SLATE, va="center", ha="right")
    ax.plot([lx - w - 0.38, lx - w - 0.1], [4.24, 4.24], color=s["color"] if s["color"][0] == "#" else eval(s["color"]),
            lw=2.6)
    lx -= w + 0.6
a = fax(fig, LX + 0.75, 1.32, LW - 1.05, 2.62)
for band in T.get("bands", []):
    a.axvspan(band["x0"], band["x1"], color=PGRAY, zorder=0)
    a.text((band["x0"] + band["x1"]) / 2, 8, band["label"], fontsize=8.8, color=MUTED, ha="center", va="center")
for s in T["series"]:
    col = s["color"] if s["color"][0] == "#" else eval(s["color"])
    xs = [p[0] for p in s["points"]]; ys = [float("nan") if p[1] is None else p[1] for p in s["points"]]
    a.plot(xs, ys, color=col, lw=s.get("lw", 2.4), marker="o" if s.get("dots") else None, ms=3.2)
for m in T.get("markers", []):
    a.scatter([m["x"]], [m["y"]], s=95, color=GREEN, zorder=5, edgecolor=WHITE, linewidth=1.5)
if T.get("marker_label"):
    ml = T["marker_label"]
    a.annotate(ml["text"], xy=(ml["x"], ml["y"]), xytext=(ml["tx"], ml["ty"]), fontsize=9.5, color=GREEN,
               weight="bold", ha="center", arrowprops=dict(arrowstyle="-", color=GREEN, lw=1))
for sp in ("top", "right", "left"):
    a.spines[sp].set_visible(False)
a.spines["bottom"].set_color(BORDER)
a.set_ylim(-8, 108); a.set_yticks([0, 50, 100]); a.set_yticklabels(["0%", "50%", "100%"])
a.set_xlim(T["xlim"][0], T["xlim"][1])
a.set_xticks([t[0] for t in T["xticks"]]); a.set_xticklabels([t[1] for t in T["xticks"]])
a.tick_params(colors=SLATE, labelsize=9.5, length=0)
a.yaxis.grid(True, color="#EEF1F5", lw=0.8); a.set_axisbelow(True)
ax.text(LX + 0.22, 1.0, T["caption"], fontsize=9.5, color=MUTED, va="center")

# handled issues (right column)
RX, RW = 7.7, W - 0.6 - 7.7
ax.text(RX, 5.55, P["handled_title"], fontsize=13, color=NAVY, weight="bold", va="center")
y_top = 5.32
for inc in P["incidents"]:
    h = inc["height"]
    y0 = y_top - h
    fg, bg = TONE[inc["tone"]]
    card(ax, RX, y0, RW, h, top=fg)
    yy = y0 + h - 0.32
    chip(ax, RX + 0.22, yy, inc["chip"], inc["tone"])
    if inc.get("when"):
        ax.text(RX + RW - 0.22, yy, inc["when"], fontsize=9.5, color=MUTED, ha="right", va="center", weight="bold")
    yy -= 0.3
    tt = wrap(inc["title"], RW - 0.44, 12, True)
    ax.text(RX + 0.22, yy, tt, fontsize=12, color=NAVY, weight="bold", va="top")
    yy -= 0.24 * (tt.count("\n") + 1) + 0.16
    for f in inc.get("actions", []):
        check(ax, RX + 0.32, yy, inc["tone"])
        ax.text(RX + 0.5, yy, f["text"], fontsize=9.8, color=NAVY, va="center")
        if f.get("thread_url"):
            link(ax, RX + RW - 0.22, yy, f.get("thread_label", "Thread"), f["thread_url"], ha="right", size=9.5)
        yy -= 0.29
    yy -= 0.04
    ax.text(RX + 0.22, yy, inc["prevent_label"], fontsize=9.8, color=TEAL, weight="bold", va="center")
    lw_ = link(ax, RX + RW - 0.22, yy, inc["issue_label"], inc["issue_url"], ha="right", size=9.5)
    yy -= 0.27
    for b in inc["prevent"][:2]:
        ax.text(RX + 0.3, yy, "\u2022  " + b, fontsize=9.8, color=SLATE, va="center")
        yy -= 0.25
    y_top = y0 - 0.15

footer(ax, P["footer"], 1)
pdf.savefig(fig); plt.close(fig)

# ======================= PAGE 2: security + cost recommendations
Q = D["page2"]
fig, ax = page()
header(ax, Q["eyebrow"], Q["title"], Q["subtitle"])
CW = (W - 1.2 - 0.3) / 2
for ci, col in enumerate(Q["columns"]):
    cx = 0.6 + ci * (CW + 0.3)
    fg, bg = TONE[col["tone"]]
    card(ax, cx, 0.8, CW, 4.9, top=fg)
    ax.text(cx + 0.25, 5.33, col["title"], fontsize=15, color=NAVY, weight="bold", va="center")
    ax.text(cx + CW - 0.25, 5.33, col["kpi"], fontsize=11, color=fg, weight="bold", va="center", ha="right")
    rows = col["rows"]; rh = (4.25 - 0.15) / len(rows)
    for ri, r in enumerate(rows):
        ry = 4.95 - (ri + 1) * rh
        ax.add_patch(FancyBboxPatch((cx + 0.18, ry + 0.06), CW - 0.36, rh - 0.12,
                                    boxstyle="round,pad=0,rounding_size=0.08", fc=PGRAY, ec="none"))
        top = ry + rh - 0.3
        wch = chip(ax, cx + 0.34, top, r["chip"], r.get("tone", col["tone"]), size=8.8)
        ax.text(cx + 0.34 + wch + 0.15, top, r["title"], fontsize=12, color=NAVY, weight="bold", va="center")
        ax.text(cx + 0.34, top - 0.36, r["why"], fontsize=10, color=SLATE, va="center")
        ax.text(cx + 0.34, top - 0.7, "Owner: " + r["owner"], fontsize=9.5, color=MUTED, va="center")
        link(ax, cx + CW - 0.34, top - 0.7, r["issue_label"], r["issue_url"], ha="right", size=9.5)
footer(ax, Q["footer"], 2)
pdf.savefig(fig); plt.close(fig)
pdf.close()
print("wrote", OUT)
