---
name: caldova-morning-digest
description: Build the 2-page Caldova morning digest PDF. Page 1 shows the app-health trend and the issues SRE Agent mitigated, with thread links, GitHub links and prevention bullets. Page 2 shows security and cost recommendations. Calm, modern, executive-ready.
---

# Caldova morning digest (2-page PDF)

Use this skill for the daily/morning Caldova operations digest, or when someone asks for an exec-ready ops summary to share from Teams.
It replaces the older 5–6 page executive review layout for the daily digest.

## Story the PDF must tell
"Ops is proactive now." SRE Agent handled the overnight issues within pre-approved guardrails and filed the permanent fix for the team.
Security and cost become the priorities the team can now act on.

## Format rules (non-negotiable)
- **2 pages maximum.** 16:9 landscape, 13.333 × 7.5 in, vector PDF (matplotlib `PdfPages`).
- **Calm palette only:** navy `#172B4D`, teal `#008272`, green `#107C41`, blue `#0078D4`, and pale tints on white.
  - **No red or yellow.** No severity "traffic-light" boxes, no four-box status scorecards.
- **One sans font family** (DejaVu Sans / Segoe UI / Aptos). Set `text.parse_math=False` so `$` amounts render correctly.
- Every page has an eyebrow line, a one-line takeaway title, a one-line subtitle, and a one-line source footer.
- No appendix pages.
- No raw URLs, resource IDs or digests on the page. Links are short labels (`Thread →`, `Issue #33 →`) with embedded URLs.

## Page 1 — Overnight reliability
- **Eyebrow:** `MORNING DIGEST | <date> | OVERNIGHT, <window> UTC`.
- **Title:** what the agent did, e.g. "SRE Agent fixed two payment incidents overnight".
- **KPI tiles (4):** incidents fixed by the agent, alert-to-fix time, orders success, payments success over the last 30 minutes.
  - Labels must stay at 18 characters or fewer.
- **Health trend chart:** success rate in 30-minute windows over the overnight window, one line per customer path (orders, payments).
  - Mark the agent fixes with green dots and one label.
  - Shade periods whose cause is outside Azure in pale gray.
  - Leave gaps where there was no traffic.
  - One caption line.
- **"Handled by SRE Agent" cards (1–2), each with:**
  - A chip: `Mitigated by SRE Agent` (green), or `Investigated, self-resolved` (blue).
  - A time window, and a one-line title.
  - One action row per fix: `HH:MM  what the agent did, recovered HH:MM`, plus a link to that episode's SRE Agent thread.
  - `Prevent recurrence` plus the GitHub issue link, then **1–2 bullets copied from that issue's prevention / code-fix section**.

## Page 2 — Recommendations (security + cost)
- Two columns, `Security` and `Cost`, each with a header KPI and up to 3 rows.
- Each row has: a chip (`P1` / `Validated` / `Review` / `Trend`), a one-line action, a one-line why with evidence numbers, the owner, and an issue link.
- Cost must keep these labels separate: `Validated` savings (annualized only when validated), `Review` (allocation/governance, not savings), and `Trend` suggestions.

## Truthfulness rules
- **Use `Mitigated by SRE Agent` only when all three hold:**
  - the action ran under an explicit `allow` rule in `config/permissions.json`;
  - its thread shows guardrails passed;
  - fresh telemetry shows recovery.
- Otherwise use `Investigated`.
- **Never** present an action that ran outside policy as a success.
- **Do not hide failures in the trend window.** Explain them in the caption (for example, "upstream outage outside Azure").
- **CVE claims** require the running image digest to match the scan digest, and the scan must be 7 days old or newer.
- **Savings** are labeled `annualized opportunity`, never "saved".

## How to gather the data
1. **Trend:** query App Insights `AppRequests` for the gateway (`AppRoleInstance startswith "coldova-pharmacy-gateway-prod"`).
   - Keep `Name in ("POST /api/payments/process","GET /api/orders")`.
   - Group with `summarize total=count(), failed=countif(Success==false) by Name, t=tostring(bin(TimeGenerated,30m))`.
   - Wrap any datetime aggregate in `tostring()`; the query tool rejects raw datetime aggregates.
2. **Handled issues:** list the comments on the open incident issues (`GET repos/<owner>/<repo>/issues/<n>/comments`).
   - Keep the ones whose `Mitigation` section says the guarded action ran.
   - Take each episode's `views/thread/<id>` link from the comment footer.
   - Take the prevention bullets from the postmortem issue (e.g. `## Code suggestions to prevent recurrence`).
3. **Security / cost:** use the daily review evidence and the `caldova-fp:` fingerprinted issues (CVE digest check, network posture, FinOps plugin cores).

## Build
```bash
python3 build_digest.py digest.json caldova-morning-digest-YYYY-MM-DD.pdf
python3 qc_digest.py caldova-morning-digest-YYYY-MM-DD.pdf   # page size, min font >= 8pt, bounds, banned words
pdftoppm -r 80 -png caldova-morning-digest-YYYY-MM-DD.pdf pages/p   # then open and inspect every page image
```
- `example-digest.json` is the 2026-11-06 digest. Copy it and replace the values.
- `height` per incident card: about 2.33 in with two action rows, about 2.04 in with one. Both cards together must fit between y=0.8 and y=5.32.
- Fix any overflow by shortening the copy, not by shrinking fonts below 9 pt.

## Deliver
1. Persist the PDF in the thread (`SaveFileToBlob`).
2. Upload it to the user's OneDrive:
   - dataset `https://microsoft-my.sharepoint.com/personal/dchelupati_microsoft_com`, folder `/Documents/Caldova Reviews`;
   - verify it with `GetFileMetadataByPath`.
3. Send exactly one `teams_teams_PostMessageToSelf` message with:
   - the OneDrive link;
   - the one-line takeaway;
   - the handled incidents with thread and issue links;
   - the top security and cost actions.
4. Never post to group chats or channels unless asked.
