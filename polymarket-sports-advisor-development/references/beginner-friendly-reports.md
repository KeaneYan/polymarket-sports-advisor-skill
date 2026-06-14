# Beginner-Friendly Sports Advisor Reports

Use this reference when shaping scheduled or preview reports for users who are not familiar with betting, prediction markets, or sports-market jargon.

## Report Shape

- Report every scheduled match in the window, not only BUY opportunities.
- For each match, choose one headline outcome to explain:
  - Prefer BUY if any outcome qualifies.
  - Otherwise show the highest-edge WATCH/SKIP outcome.
  - If no usable market is found, include a `NO MARKET` card instead of silently dropping the match.
- Translate market labels into plain language:
  - `home` -> `主队 <team> 赢`
  - `draw` -> `平局`
  - `away` -> `客队 <team> 赢`
- Include full 1X2 model probabilities on every priced match card:
  - `模型概率：主胜 <home> 18.5% / 平局 26.3% / 客胜 <away> 55.2%`
- Keep the selected-outcome rationale separate from the full probability context:
  - `为什么：模型估 X%，市场买入价 Y%，差值 Z%`

## Noise Control

- Manual/preview reports should show all matches so the user can see the full slate.
- Scheduled delivery can remain change-only while manual reports stay complete.
- Write paper snapshots only for alert rows; do not let repeated scans inflate the ledger.

## Field Glossary

Always include a short glossary after the match cards:

- `model`: model-estimated probability.
- `buy`: current buy price / market-implied probability.
- `edge`: `model - buy`; positive edge is a hypothesis, not proof.
- `spread`: bid/ask trading cost; smaller is better.
- `liq`: liquidity/depth; larger generally means lower slippage.
- `stake`: capped paper position size, not an instruction to place real money.

## Risk Copy

Include a blunt risk line: this is read-only paper recommendation; model edge may be noise; even high-probability single matches can lose; watch slippage, depth, settlement, and regulatory risk.
