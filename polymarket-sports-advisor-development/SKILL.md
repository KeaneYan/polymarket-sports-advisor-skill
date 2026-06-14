---
name: polymarket-sports-advisor-development
description: Build and iterate read-only Polymarket sports betting advisor tools with TDD, market mapping, CLOB pricing, and paper-trading safety.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [polymarket, sports, betting-advisor, prediction-markets, tdd]
---

# Polymarket Sports Advisor Development

Use this when building or extending a Polymarket sports recommendation tool, especially for match-level markets such as World Cup 1X2 outcomes.

## Safety Boundaries

- Start read-only: no private keys, no wallet config, no order placement.
- Treat outputs as recommendations, not automatic trades.
- Add automatic betting only after paper-trading logs, calibration metrics, limits, and manual confirmation are in place.
- Always flag本金亏损、流动性、滑点、盘口瞬变、地域/合规风险.

## Implementation Pattern

1. Use strict TDD for each behavior.
2. Map Polymarket Gamma events to sports outcomes first.
   - For World Cup match markets, Polymarket may represent 1X2 as three binary markets: home win, draw, away win.
   - Parse Gamma's double-encoded `outcomePrices` and `clobTokenIds` with `json.loads`.
3. Keep probability model separate from market pricing.
   - First model can be Elo + Poisson/Dixon-Coles: output home/draw/away probabilities that sum to 1.
   - Use `dixon_coles_rho` to correct low-score dependence; keep `rho=0.0` as the independent-Poisson fallback and calibrate `rho` only with held-out/rolling tests.
   - Use a separate team-form layer for data-derived attack/defense multipliers before manual injury/lineup adjustments. A pragmatic first version can derive `attack_multiplier` and `defense_multiplier` from recent historical goals for/against relative to the global average, with hard clamps and minimum-match filters; note that defense multiplier lower means stronger defense.
   - Treat team form and manual injury/lineup adjustments as separate deliverables; see `references/model-optimization-and-reporting.md` for the layered model and report UX checklist.
   - Do not call `model_prob - market_price` EV; that is edge. Compute EV separately.
   - Optional market shrinkage should be explicit and conservative: `final_prob = model_weight * model_prob + (1 - model_weight) * market_buy_price`, with `model_weight=1.0` preserving raw model output.
   - Injuries/lineups should enter as auditable team adjustments (`elo_delta`, `attack_multiplier`, `defense_multiplier`, notes) before any external API automation.
4. Prefer CLOB orderbook for actionable prices.
   - Use token ID from `clobTokenIds[0]` for the Yes side.
   - Best ask is immediate buy price for tiny size.
   - For target size, compute depth-weighted average ask price.
   - Spread is best ask minus best bid; keep it separate from slippage.
5. Recommendation gates:
   - Skip resolved/untradeable 0/1 prices before liquidity checks.
   - Skip high spread and low liquidity.
   - BUY only when edge exceeds threshold after using actionable buy price.
   - Gate BUY by model loss probability (`1 - model_probability`) as well as edge; high-edge longshots can be WATCH if the user does not accept high principal-loss frequency.
   - Cap Kelly sizing hard, e.g. 2% bankroll.
6. Provide JSON output for paper trading and future database ingestion.
7. Add paper-trading persistence before any real-money flow.
   - Record each recommendation snapshot with model source, price source, probabilities, actionable prices, actions, stake fractions, token IDs, and market IDs.
   - Settle snapshots exactly once; reject missing snapshot IDs and double-settlement overwrites.
   - Evaluate paper profit for BUY rows and calibration metrics (Brier/log loss) across all settled outcomes.
   - Keep `paper_profit` wording distinct from ROI unless profit/staked capital is explicitly computed.
   - See `references/paper-trading-sqlite.md` for schema/CLI pitfalls.
8. Add schedule-driven cron reports without coupling cron to live fixture sources.
   - Keep scheduled report jobs reading a local `data/schedule.json`.
   - Refresh that file via an importer CLI from open fixture data, then verify generated schedule counts and scanner smoke output.
   - Skip knockout placeholders (`1A`, `W73`, `L101`, `Winner Group A`, etc.) until concrete teams are known.
   - Refresh team Elo from eloratings.net static TSV files rather than scraping rendered pages: `World.tsv` contains current ratings (team code in column 3, rating in column 4), and `en.teams.tsv` maps codes to primary English team names.
   - Keep fixture/team aliases explicit (`USA` -> `United States`, `Bosnia and Herzegovina` -> `Bosnia`) and fail on missing Elo rather than silently defaulting.
   - For a concrete World Cup implementation pattern, see `references/worldcup-schedule-cron-reports.md`.
9. Calibrate Elo/Poisson parameters before trusting edge magnitude.
   - Prefer yearly eloratings result files (`YYYY_results.tsv`) over `latest.tsv` once available; `latest.tsv` is too thin for calibration. Support `--start-year/--end-year`, record the source range in `model_params.json`, and still keep runtime readers using only the core parameter fields.
   - Optimize log loss on train matches with a small grid, then report held-out test log loss/Brier score and sample counts before changing production defaults; avoid trusting in-sample improvements alone.
   - Persist chosen parameters to a local JSON (`data/model_params.json`) and have both ad-hoc CLI and scheduled reports load it, while falling back to safe defaults if the file is absent.
   - Add rolling backtests once the simple split exists: repeatedly fit on a fixed train window and evaluate the next test window. Report fold count, per-fold params, average test log loss/Brier, and unstable folds; parameter instability is a warning that model edge may be noise.
10. Add conservative automatic settlement after CLV tracking.
   - Prefer Polymarket's own resolved market prices for paper settlement before introducing third-party sports-result feeds; this keeps paper accounting aligned with actual market resolution.
   - Infer outcomes only when all three 1X2 quotes are present and exactly one Yes price is near 1 while the other two are near 0 (for example `>=0.99` / `<=0.01`). If the event is missing, ambiguous, or still trading normally, skip settlement.
   - Keep settlement idempotent: list only unsettled snapshots, reject double-settlement writes, and run settlement before reporting performance summaries.
   - Treat skipped rows as a safety feature, not a failure; wrong settlement is worse than delayed settlement.
   - For the World Cup implementation pattern, see `references/worldcup-auto-settlement.md`.

11. Add market-level paper backtest reporting before considering real orders.
   - Summarize only BUY rows for market-edge validation: total/open/settled BUY, average edge, CLV tracked/positive/average, settled paper profit, staked fraction, and ROI.
   - Keep unsettled BUY out of ROI/P&L but include them in CLV if closing prices exist.
   - Treat “no settled BUY” as insufficient evidence, not breakeven.

12. Operationalize the paper-trading loop with Hermes cron before considering real orders.
   - Use deterministic script-only cron jobs (`no_agent=True`) for scanner, CLV capture, settlement, market backtest, and overview reports.
   - After creating/updating cron, run the script locally, trigger the cron once, then re-list jobs to verify `last_status=ok` and `last_delivery_error=null`; `cronjob(action="run")` executes on the next scheduler tick, not necessarily synchronously.
   - Improve data quality before adding model complexity: kickoff-relative CLV capture, scanner deduplication, change-only alerts, and cron health reporting.
   - See `references/worldcup-cron-operations.md` for the operational checklist and pitfalls.

13. Harden cron data quality before trusting paper results.
   - Scanner jobs should alert/record only on new BUY, BUY disappearance, material edge change, or material market-quality deterioration (spread widening / liquidity drop); repeated identical scans should stay silent and not create duplicate snapshots.
   - Scanner report copy should be beginner-friendly and cover every scheduled match in the report window, not only BUY opportunities: default to the next 24 hours, sort cards by kickoff time from soonest to latest, show kickoff time in Beijing time, show each match as a card with “recommendation / what to buy / model home-draw-away probabilities / loss probability / risk bucket / why / trading quality / paper stake,” translate `home/away/draw`, include `NO MARKET` rows when no usable Polymarket market is found, and keep a compact field glossary for `model`, `buy`, `edge`, `loss probability`, `risk`, `spread`, `liq`, and `stake`.
   - See `references/beginner-friendly-reports.md` for the report UX pattern and copy checklist.
   - Separate report completeness from notification noise: manual/preview reports should include every match in the window, but scheduled delivery can remain change-only. In record mode, collect all match cards for the outgoing report only when at least one material alert fires; write paper snapshots only for alert rows so duplicate scans do not inflate the ledger.
   - Capture CLV relative to kickoff, not a single fixed time of day. A practical default is polling every 15 minutes but recording only matches inside a kickoff-relative window such as 30-120 minutes before start.
   - Add a no-agent cron health report that checks Polymarket job schedules/status and appends market-level backtest summary; this catches broken scripts or delivery before the tournament starts.

## Useful Polymarket Endpoints

- Gamma search: `https://gamma-api.polymarket.com/public-search?q=QUERY`
- CLOB book: `https://clob.polymarket.com/book?token_id=TOKEN_ID`

## Verification

- Run full tests after each feature: `python3 -m pytest -q`.
- Run at least one real active/unresolved market query.
- Also test a resolved market; 0/1 prices should be marked SKIP/resolved, not low-liquidity opportunity.
