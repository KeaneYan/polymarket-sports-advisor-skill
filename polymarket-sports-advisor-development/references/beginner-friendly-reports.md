# Beginner-Friendly Sports Advisor Reports

Use this reference when shaping scheduled or preview reports.

## Current Format: Compact (2026-06-27)

User feedback: "报告内容太多太乱" — reports were too long and cluttered for
WeChat delivery. Redesigned from 13 lines/match to 2 lines (BUY) or 1 line
(WATCH/SKIP). **See `references/compact-report-format.md` for the full spec.**

Key design rules:
- **Three-way probs on every priced card**: `主21% 平38% 客41%` — omitting
  draw probability misleads about risk.
- **Only BUY gets a second line** with CI width + risk + exit triggers.
- **CI shows width (`CI±1%`), not absolute range** — bootstrap CI may not
  bracket the point estimate (different param family), which looks like a bug.
- **No glossary, no verbose field labels** — the compact format is
  self-explanatory.
- **One-line header** (count + BUY count + disclaimer), **one-line footer**
  (risk warning).

## Noise Control

- Manual/preview reports should show all matches so the user sees the full slate.
- Scheduled delivery can remain change-only.
- Write paper snapshots only for alert rows; do not let repeated scans inflate the ledger.
- **Critical pitfall:** if the first alert's delivery fails (WeChat rate limit),
  subsequent scanner runs suppress the alert because the DB snapshot already
  exists — the report is permanently lost. See `references/worldcup-cron-operations.md`.

## Action Labels

| Emoji | Label | Meaning |
|-------|-------|---------|
| ✅ | BUY | Edge above threshold, loss prob acceptable — paper position |
| 👀 | WATCH | Edge exists but below threshold or loss prob too high |
| ⏭ | SKIP | Resolved market, spread too wide, or liquidity too low |
| ⏭ | NO MARKET | No Polymarket 1X2 event found |

## Risk Copy

One-line footer: `⚠️ edge 可能是噪声，单场也会翻车，注意滑点/流动性/监管风险`
