# Compact Scanner Report Format (2026-06-27, rev 2)

User feedback progression:
1. "报告内容太多太乱" → 13 lines/match down to 2 lines BUY / 1 line others
2. "把止盈止损，spread，风险都拿掉，没啥用" → killed entire risk/exit line
3. "把仓位也拿掉，ci放到第一行" → stake removed, CI merged inline to line 1

**Current state: every match is exactly 1 line.** No exceptions.

## Design Principles

1. **One screen, all matches** — the report must fit in a WeChat message
   without scrolling fatigue. Target: 1 line per match.
2. **Three-way probs are mandatory** — `主21% 平38% 客41%` on the action line.
   Omitting draw probability misleads the reader about the risk profile.
3. **CI shows width, not absolute values** — `CI±1%` not `CI(90%) [43%-46%]`.
   Reason: bootstrap CI is computed from a different parameter family (no
   dispersion) so the absolute range may not bracket the point estimate,
   which looks like a bug to the reader. Width conveys uncertainty without
   the contradiction.
4. **CI is inline at end of line 1** — appended after edge with `｜CI±X%`,
   only for BUY when CI info is available and width > 1%.
5. **Kill the glossary** — field速读 was useful for the first few pushes but
   became noise. The compact format is self-explanatory.

## BUY Card (1 line)

```
1. Egypt vs Iran  06/27 11:00
✅ BUY 客队 Iran 赢｜主21% 平38% 客41%｜买价 28%｜edge +12.8%｜CI±1%
```

Title line: index + match title + kickoff (MM/DD HH:MM Beijing)
Action line: emoji + action + outcome + three-way probs + buy price + edge + CI width (if available)

## WATCH/SKIP Card (1 line)

```
2. New Zealand vs Belgium  06/27 11:00
👀 WATCH 客队 Belgium 赢｜主1% 平12% 客87%｜买价 83%｜edge +3.7%
```

## NO MARKET Card (1 line)

```
5. I vs J  06/19 03:00
⏭ NO MARKET｜无可用盘口
```

## Header & Footer

```
**未来 24 小时 Polymarket 机会扫描**
6场｜BUY 4场｜纸面观察不等于下单
...
⚠️ edge 可能是噪声，单场也会翻车，注意滑点/流动性/监管风险
```

One-line header (match count + BUY count + disclaimer). One-line footer (risk warning). No glossary.

## Fields Removed (and why)

| Removed field | Why it's OK to cut |
|---|---|
| 模型调整 (form multipliers) | Model input, not a decision criterion for the reader |
| 持仓计划 full text | Not actionable in a push notification context |
| 净EV/每$1 | Redundant with edge when buy price is shown |
| 模型概率 verbose (主胜 Egypt 20.7%) | Compact 主21% is sufficient |
| 字段速读 glossary | Self-explanatory in compact format |
| 流动性 absolute number | Not useful for quick scan decisions |
| 仓位 CI [2.0%-2.0%] | When Kelly is capped, range carries no info |
| **仓位 (stake fraction)** | User: "把仓位也拿掉" — not useful in scanner card |
| **止盈/止损 (exit triggers)** | User: "没啥用" — adds noise without actionable value |
| **spread** | User: "没啥用" — quality gate already filters bad spreads |
| **风险档位 + 亏本金概率** | User: "没啥用" — loss prob is inferable from three-way probs |

## Implementation

All formatting lives in `reports.py`:
- `_format_opportunity_card()` — main card builder, single-line output
- `_format_model_probabilities_compact()` — `主21% 平38% 客41%`
- `_ci_width()` — computes CI width for inline display
- `_format_unavailable_match_card()` — NO MARKET
- `_format_beijing_kickoff_short()` — `MM/DD HH:MM` format

### Key code shape (rev 2)

```python
# Line 1: action + probs + price + edge + CI (all inline)
line1 = f"{emoji} {action} {outcome}｜{probs}｜买价 {buy_price:.0%}｜edge {edge:+.1%}"
if action == "BUY" and ci_info:
    ci_width = _ci_width(ci_info)
    if ci_width > 0.01:
        line1 += f"｜CI±{ci_width/2:.0%}"
lines.append(line1)
# No line 2 — everything is on line 1
```

## Pitfall: CI vs Point Estimate Contradiction

Bootstrap params are calibrated without dispersion (NegBinom), so the
bootstrap mean probability can differ from the production point estimate.
Showing `CI [43%-46%]` next to `概率 41%` looks like a bug. Solution:
show `CI±1%` (half-width) which conveys uncertainty without implying the
CI should bracket the point estimate.
