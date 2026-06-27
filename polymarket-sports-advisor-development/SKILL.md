---
name: polymarket-sports-advisor-development
description: Build and iterate read-only Polymarket sports betting advisor tools with TDD, market mapping, CLOB pricing, and paper-trading safety.
version: 1.2.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [polymarket, sports, betting-advisor, prediction-markets, tdd]
---

# Polymarket Sports Advisor Development

Use this when building, extending, or operating a read-only Polymarket sports recommendation tool, especially for match-level markets such as World Cup 1X2 outcomes.

## Runnable Reference Implementation

- Tool repository: `https://github.com/KeaneYan/worldcup-polymarket-advisor`
- CLI commands: `wc-poly-advisor` for one-match recommendations; `wc-poly-report` for schedule reports, paper snapshots, CLV, settlement, backtests, and simulations.
- This skill is the workflow/playbook layer. Do not copy the full tool source into the skill; install or clone the tool repo and keep code changes there.
- Quick install from a skill checkout: `bash polymarket-sports-advisor-development/scripts/install_worldcup_advisor.sh`.
- Repo + skill update operations: when syncing the runnable advisor and this skill repo together, use the two-repo checklist in `references/repo-and-skill-update-ops.md` so local skill patches are not lost or misreported as remote-aligned.

## Safety Boundaries

- Start read-only: no private keys, no wallet config, no order placement.
- Treat outputs as recommendations, not automatic trades.
- Add automatic betting only after paper-trading logs, calibration metrics, limits, and manual confirmation are in place.
- Always flag principal-loss risk, liquidity, slippage, market-quality swings, and jurisdictional / compliance risk.

## Implementation Pattern

1. Use strict TDD for each behavior.
2. Map Polymarket Gamma events to sports outcomes first.
   - For World Cup match markets, Polymarket may represent 1X2 as three binary markets: home win, draw, away win.
   - Parse Gamma's double-encoded `outcomePrices` and `clobTokenIds` with `json.loads`.
3. Keep probability model separate from market pricing.
   - First model can be Elo + Poisson/Dixon-Coles: output home/draw/away probabilities that sum to 1.
   - Use `dixon_coles_rho` to correct low-score dependence; keep `rho=0.0` as the independent-Poisson fallback and calibrate `rho` only with held-out/rolling tests.
   - Use a separate team-form layer for data-derived attack/defense multipliers before manual injury/lineup adjustments. A pragmatic first version can derive `attack_multiplier` and `defense_multiplier` from recent historical goals for/against relative to the global average, with hard clamps and minimum-match filters; note that defense multiplier lower means stronger defense.
   - Team-form importer pitfalls: eloratings yearly results store teams as short codes (`US`, `JP`, etc.), so map through `en.teams.tsv` and project aliases before writing `team_form.json`; otherwise schedule/CLI names like `United States` will never match. Also keep `min_matches` based on actual sample count, not decayed/weighted count — using weighted count with short half-life can silently output zero rows.
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
   - **Pitfall: `dixon_coles_rho` silently disabled.** If `model_params.json` lacks the `dixon_coles_rho` field, it was generated by old calibration code that never searched rho — you are running plain independent Poisson, not Dixon-Coles. Always include `rho` in the grid search (`[-0.30, -0.20, -0.15, -0.10, -0.05, 0.0]`) and verify the calibrated value appears in the output JSON. In practice, expanding rho from `[0.0]` to `[-0.30..0.0]` improved test log_loss by 3.0% and test brier by 2.4% — a material gain for zero code change.
   - **Tournament-code bug pitfall:** eloratings.net uses `WQ` for World Cup Qualifiers — **not** `WQT`. If `--tournaments` includes `WQT`, zero qualifier matches are matched and the entire qualifier dataset (872+ matches, ~38% of available data) is silently dropped. Always verify tournament codes by inspecting the raw TSV `fields[7]` values before relying on a filter set.
   - **Per-tournament calibration:** different tournament types have systematically different goal expectations and Elo sensitivity. Run `--by-tournament` to produce separate parameter sets per tournament code (WC, WQ, F). The `model_params.json` gains a `by_tournament` dict; `model_config.params_for(tournament)` selects the active set at prediction time with graceful fallback to global defaults. World Cup matches have lower base_goals (~1.05 vs ~1.25 for friendlies) and tighter elo_divisor (~850-950 vs ~1100).
   - **Mixed-venue calibration pitfall:** `home_advantage_elo` calibrated from combined qualifier + tournament data will be inflated by qualifiers (which have real home/away). Per-tournament calibration (above) partially addresses this, but `home_advantage_elo` still tends to hit the grid maximum because even WC-group-stage matches have host-nation home advantage. **Solution: neutral-venue flag (implemented 2026-06-25).** `estimate_match_probabilities()` now accepts `neutral_venue=True` which zeroes out home advantage entirely. WC tournament code is auto-detected as neutral in calibration and schedule loading; knockout matches always use `neutral_venue=True`. Host-nation effects go in `team_adjustments.json` explicitly. Re-run Optuna after enabling so parameters account for the venue correction. See `references/neutral-venue-implementation.md` for the full pattern.
   - Persist chosen parameters to a local JSON (`data/model_params.json`) and have both ad-hoc CLI and scheduled reports load it, while falling back to safe defaults if the file is absent.
   - Add rolling backtests once the simple split exists: repeatedly fit on a fixed train window and evaluate the next test window. Report fold count, per-fold params, average test log loss/Brier, and unstable folds; parameter instability is a warning that model edge may be noise.
   - **Model ceiling pitfall:** After P1 calibration improvements plateau with grid search, three common "next steps" were tried and all appeared to fail under grid search: (a) ensemble top-K parameters (parameters too similar), (b) time-decay xi calibration (grid only tried xi up to 0.001 — too narrow), (c) isotonic post-hoc calibration (too few samples). **However**, Optuna Bayesian optimization later found xi=0.009 (10× the grid max) significantly improved CV score, disproving the "time-decay doesn't help" conclusion. Lesson: grid search false negatives are real — use Optuna with wide ranges before declaring a feature useless. See `references/post-p1-improvement-attempts.md` for detailed grid-search findings and `references/optuna-optimization.md` for the Optuna correction.
   - **RPS and ECE metrics now implemented:** `CalibrationResult` carries `rps` and `ece` fields alongside `log_loss` and `brier_score`. RPS (Ranked Probability Score) respects the home>draw>away ordering and is the standard metric for football 1X2 evaluation: `RPS = 0.5 * [(P_home - Y_home)² + ((P_home + P_draw) - (Y_home + Y_draw))²]`. ECE (Expected Calibration Error) pools all 3 outcome probabilities into 10 bins and measures |avg_predicted - avg_observed|. All calibration output sections (train/test, ensemble, rolling folds, by-tournament) include these. See `references/rps-ece-implementation.md` for the formulas, verification approach, and implementation pitfalls.
   - **Beyond in-framework tuning:** The ceiling above applies to grid-search tuning of the existing Elo+DC+Poisson framework. An external competitive analysis against 6+ GitHub open-source WC 2026 prediction projects (2026-06-23, refreshed 2026-06-25) identified techniques outside this framework: ~~RPS/ECE evaluation metrics~~ (✅ done), ~~walk-forward Elo with tournament-weighted K-factors~~ (✅ done — live tournament tracker only; eloratings.net data is already walk-forward so this does NOT improve backtest metrics), ~~Optuna hyperparameter optimization~~ (✅ done — test_ll 0.7486, RPS 0.130), ~~penalty shootout modeling~~ (✅ done — stochastic Elo-shrunk draw resolution; reports must pass `elo_lookup` or it falls back to 50/50), bookmaker odds consensus features, and round-variance scaling in Monte Carlo. **Four structural improvement targets from the 2026-06-25/26 analysis (see `references/external-model-comparison-and-improvement-roadmap.md` → "2026-06-25 Second-Pass"):** (1) **~~Neutral-venue correction~~** ✅ DONE (2026-06-25); (2) **~~Negative Binomial goal model~~** ✅ DONE (2026-06-25) — dispersion=0.0999, ECE 2.94%→2.33%, log_loss unchanged; (3) **~~Isotonic post-hoc calibration pipeline~~** ✅ DONE (2026-06-26) — see below; (4) **~~Multi-objective ensemble~~** ✅ DONE (2026-06-26) — **negative result**. Ran 3× Optuna (log_loss/RPS/Brier, 75 trials each, 5-fold walk-forward CV) and equal-weight averaged the three parameter sets. Ensemble test_ll=0.7702 vs current single-model test_ll=0.7666 — ensemble is WORSE by +0.0036 log_loss. Root cause: current model already well-tuned; optimizing different objectives degrades individual models, and averaging cannot recover. **Lesson:** same-architecture multi-objective ensemble is not worth the complexity for this dataset/model. See `references/ensemble-multi-objective-experiment.md`. Also identified: Bivariate Poisson for goal correlation, bootstrap confidence intervals for sizing, and CupCast's daily-retrain + prediction-freeze pattern.
   - **Multi-objective ensemble experiment (2026-06-26, NEGATIVE RESULT):** Ran 3× Optuna (log_loss/RPS/Brier, 75 trials each, 5-fold walk-forward CV) and equal-weight averaged the three parameter sets. Ensemble test_ll=0.7702, RPS=0.1354 vs current single-model test_ll=0.7666, RPS=0.1343 — ensemble is **worse** on both metrics. Each individual member optimized for a single objective also underperformed on the held-out test set despite better CV scores (CV-test generalization gap). **Conclusion:** same-architecture multi-objective ensemble is not worth the complexity. The current single model (Optuna log_loss, 75 trials) is already at the framework's ceiling. If ensemble is revisited, it should be **multi-architecture** (e.g. Colley/PageRank + Elo) to create genuine model diversity, not just hyperparameter diversity within the same Elo+DC+Poisson framework. See `references/ensemble-multi-objective-experiment.md` for full data.
   - **Bivariate Poisson experiment (2026-06-27, NEGATIVE RESULT):** Implemented full Bivariate Poisson model (`bivariate_poisson.py`) with shared component λ₁₂ introducing goal-scoring covariance across ALL scorelines (vs DC's 4 low-score cells only). Grid-searched λ₁₂ on same train set. BivarP test_ll=0.7983 vs current model test_ll=0.7740 — BivarP loses by +0.0243 on all metrics (ll, RPS, Brier). **Root cause:** BivarP uses Poisson marginals lacking NegBinom overdispersion (dispersion=0.0999), which is the dominant lever. DC rho already corrects critical low-score cells. λ₁₂ hit grid max but structural rate-positivity constraint caps covariance. **Conclusion:** current single-model architecture is at its ceiling; structural changes within the same goal-model family don't help. See `docs/bivariate-poisson-experiment.md` for full data.
   - **Bootstrap confidence intervals (2026-06-27, implemented + wired into scanner):** `bootstrap_ci.py` provides parameter bootstrap CIs on match predictions. Resamples historical matches N times, re-calibrates each resample, predicts target match → N probability triples → 90% CI (5th/95th percentiles). Also outputs Kelly stake fraction range when given a buy price. Directly informs sizing: wide CI on edge → lower confidence → smaller stake. **Pre-computed params pattern (critical for performance):** full bootstrap re-calibration is O(n_matches × grid_size) per iteration — 100 bootstrap × 2335 matches × 18-grid took >5 minutes and timed out. Solution: pre-compute N parameter sets once (`scripts/precompute_bootstrap.py`, subsamples to 500 matches, ~76s for 50 sets), save to `data/bootstrap_params.json`, then `fast_bootstrap_ci()` loads the cached params and runs N predictions (<50ms per match). The `--bootstrap-params PATH` flag on `wc-poly-report` enables a `概率CI(90%)` field in scanner cards showing home/draw/away CIs and Kelly stake range. 8 tests (5 slow + 3 fast-path). See `references/bootstrap-ci-implementation.md` for the two-phase architecture, performance pitfalls, and the Kelly `buy_outcome` bug fix.
   - **Venue altitude + market signals (implemented 2026-06-27):** Two new feature modules that capture information outside the Elo+DC framework:
     (1) **`venue.py`** — 16 WC 2026 venues with altitude/climate data. Non-acclimatised teams get attack penalty at high altitude (5%/1000m above 1200m, capped 15%). Mexico City (2240m) → −5% goal rate for non-acclimatised teams. Acclimatised: Mexico, Colombia, Ecuador, Bolivia, Peru (Costa Rica removed after adversary review — below threshold). Heat/humidity flag-only for Houston/Miami/Monterrey. Applied via `altitude_goal_adjustment()` on `attack` strength in `report_cli.py` before `estimate_match_probabilities`. `MatchScheduleItem` gains `venue: str | None` field; `load_schedule` parses `"venue"` from schedule JSON.
     (2) **`market_signals.py`** — Dynamic `model_weight` (0.70–1.0) from Polymarket volume/spread/liquidity. High volume (2M+), tight spread (<2%), high liquidity (500K+) each reduce model trust, shrinking probabilities toward market price. Floor at 0.70. Only fires when default `model_weight=1.0`; explicit `--model-weight` overrides skip dynamic weighting. Known limitations: step-function thresholds (not smooth), per-outcome volume (not per-match total), selection bias risk (biggest edges on thin markets). See `references/venue-and-market-signals.md` for full design decisions, integration points, and adversary-review findings.
   - **Isotonic calibration pipeline (implemented 2026-06-26, commit `cee837d`):**
     The `isotonic_calibrator.json` (fitted from historical predictions vs actuals,
     200-point lookup table per outcome) is now wired into **all** prediction paths:
     single-match CLI (`cli.py _maybe_calibrate`), scanner/simulation/knockout
     (`report_cli.py _calibrate_probs`). Applied after `estimate_match_probabilities()`
     and before `recommend_bets()`. Controlled by `--calibrator PATH` (default:
     `data/isotonic_calibrator.json`) and `--no-calibrate` flag. Falls through
     silently if calibrator file is missing or unfitted. 6 integration tests added.
     **Why it matters:** post-hoc calibration corrects systematic probability bias
     (e.g. model says 60% but historical hit rate at 60% is only 56%), improving
     Kelly sizing accuracy without changing the underlying model. The `IsotonicCalibrator`
     uses `sklearn.isotonic.IsotonicRegression` per outcome with `y_min=0.01, y_max=0.99,
     out_of_bounds="clip"`.
   - **Optuna hyperparameter optimization (implemented):** `optuna_optimizer.py` uses TPE sampler + median pruner with **walk-forward CV** (chronological folds, not random K-fold) to prevent overfitting. Supports log_loss / RPS / Brier objectives. Initial search space was base_goals [0.8, 2.0], elo_divisor [500, 1500], home_adv [0, 120], rho [-0.35, 0.05], xi [0, 0.01]; a later boundary check widened this to base_goals [0.5, 2.5], elo_divisor [400, 1800], home_adv [0, 150], rho [-0.40, 0.10], xi [0, 0.02]; dispersion [0.0, 1.0] was added with the NegBinom goal model (2026-06-25). CLI: `wc-poly-calibrate-model --optuna --optuna-trials 75 --optuna-folds 5`. **Pitfalls:** (1) MedianPruner requires per-fold `trial.report()` calls to actually prune — without them it's a no-op. (2) If best params touch search-space boundaries, widen and re-run; in one run, widening improved 5-fold CV log_loss from 0.7372 to 0.7263 and test log_loss from 0.7533 to 0.7486. (3) Optuna found xi far above grid's 0.001, contradicting the earlier "time-decay doesn't help" conclusion from grid search — this is because grid search only tried xi up to 0.001. (4) Run on-demand when structure changes; commit best_params.json, do NOT auto-rerun daily (overfitting risk). See `references/optuna-optimization.md` for full details and real-data comparison.
   - **Parameter validation after Optuna:** Validate surprising parameters with holdout sweeps before adopting them. In the 2022-2026 WC/WQ/F dataset, rho `-0.30` was too aggressive; useful range was roughly `-0.18` to `-0.10`, with Optuna's `-0.145` sensible. `xi` is a calibration weighting parameter only (runtime `ModelConfig` does not use it), so report it as "recent matches dominate fitting," not as a prediction-time knob. Home advantage `120-150` performed best on the split but values near the search upper bound need overfitting caveats. Do not patch only top-level `data/model_params.json` when an old `ensemble.params` block remains, because runtime reports may still use the old ensemble; regenerate or replace the ensemble explicitly. See `references/parameter-validation-rho-xi.md`.
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
  - **Pipeline ops audit:** after major feature additions or before a tournament phase transition (e.g. group → knockout), run the systematic 8-point audit in `references/pipeline-ops-audit.md`. This catches silent integration gaps (feature flags not wired into cron scripts, stale data files, team name mismatches across data sources, incomplete schedules, /tmp file cleanup).
   - Scanner jobs should alert/record only on new BUY, BUY disappearance, material edge change, or material market-quality deterioration (spread widening / liquidity drop); repeated identical scans should stay silent and not create duplicate snapshots.
   - **Scanner reports must be ultra-compact** (user feedback 2026-06-27, three rounds: "太多太乱" → "止盈止损spread风险都拿掉" → "仓位也拿掉，ci放到第一行"). **Every match is exactly 1 line.** See `references/compact-report-format.md` for the full spec. Key rules: (1) three-way probs on action line (`主21% 平38% 客41%`) — never omit draw prob; (2) CI inline at end of line 1 (`｜CI±1%`), only for BUY when available — shows width not absolute range; (3) no glossary, no verbose labels; (4) one-line header + one-line footer only. Emojis: ✅ BUY / 👀 WATCH / ⏭ SKIP / ⏭ NO MARKET. Kill list: 模型调整明细, 持仓计划全文, 净EV, 字段速读术语表, 流动性绝对值, 仓位CI when Kelly capped, **仓位 stake fraction, 止盈止损 exit triggers, spread, 风险档位 risk bucket, 亏本金概率 loss probability** — all removed per user feedback as "没啥用".
   - Cover every scheduled match in the report window, not only BUY opportunities: default to the next 24 hours, sort cards by kickoff time from soonest to latest, show kickoff in Beijing time (`MM/DD HH:MM`), include `NO MARKET` rows when no usable Polymarket market is found.
   - Recommendation reports must distinguish valuation from execution: compute edge/EV as hold-to-resolution economics, but display compact exit triggers (`止盈 X%｜止损 Y%`) so BUY/WATCH/SKIP is not a half-finished recommendation. If liquidity is thin or spread is wide, do not imply easy exit; mention slippage constraints.
   - See `references/beginner-friendly-reports.md` for the report UX pattern and `references/compact-report-format.md` for the current compact card spec (1 line per match, all actions).
   - Separate report completeness from notification noise: manual/preview reports should include every match in the window, but scheduled delivery can remain change-only. In record mode, collect all match cards for the outgoing report only when at least one material alert fires; write paper snapshots only for alert rows so duplicate scans do not inflate the ledger. **Critical pitfall:** if the first alert's delivery fails (WeChat rate limit, etc.), subsequent scanner runs suppress the alert because the DB snapshot already exists — the report is permanently lost. See `references/worldcup-cron-operations.md` → "Scanner dedup × delivery failure".
   - Capture CLV relative to kickoff, not a single fixed time of day. A practical default is polling every 15 minutes but recording only matches inside a kickoff-relative window such as 30-120 minutes before start.
   - Add a no-agent cron health report that checks Polymarket job schedules/status and appends market-level backtest summary; this catches broken scripts or delivery before the tournament starts.

## Useful Polymarket Endpoints

- Gamma search: `https://gamma-api.polymarket.com/public-search?q=QUERY`
- CLOB book: `https://clob.polymarket.com/book?token_id=TOKEN_ID`


## CLI Quick Reference

Key parameters for `wc-poly-advisor` (one-match) and `wc-poly-report` (schedule reports):

- `wc-poly-advisor --home TEAM --away TEAM --home-elo N --away-elo N` — Elo-based probabilities.
- `wc-poly-advisor --home-prob P --draw-prob P --away-prob P` — manual probabilities.
- `--use-clob` — use CLOB orderbook depth-weighted buy price instead of Gamma outcome price.
- `--target-shares N` — shares to simulate for CLOB depth-weighted fill.
- `--min-edge P` — minimum edge (model − buy) for BUY (default 0.04).
- `--max-spread P` — maximum accepted bid/ask spread (default 0.08).
- `--min-liquidity N` — minimum market liquidity (default 500).
- `--model-weight P` — shrink model probability toward market price (1.0 = pure model).
- `--max-loss-probability P` — gate BUY by model loss probability (default 0.60).
- `--record-db PATH` — record this recommendation as a SQLite paper snapshot.
- `--json` — emit machine-readable JSON.
- `--neutral-venue` — zero out home advantage (World Cup matches).
- `--calibrator PATH` — isotonic calibrator JSON (default: `data/isotonic_calibrator.json`).
- `--no-calibrate` — disable isotonic post-hoc calibration.
- `wc-poly-report --mode scanner|overview|settlement|closing|backtest|health|simulation|knockout` — report modes.
- `--hours N` — report window in hours (default 24).
- `--record` — record BUY snapshots during scanner runs.
- `--closing-minutes-before N` / `--closing-window-minutes N` — kickoff-relative CLV capture window.
- `--bootstrap-params PATH` — pre-computed bootstrap params JSON for CI display in scanner cards (default: off). Pre-compute with `scripts/precompute_bootstrap.py`. See `references/bootstrap-ci-implementation.md`.
- `--bookmaker-odds PATH` — football-data.co.uk XLSX with bookmaker closing odds for divergence display.
- `--market-values PATH` — squad market values JSON for Elo blending (Transfermarkt data).
- `--market-blend-alpha P` — Elo blend weight (1.0=pure Elo, 0.0=pure market values, default 0.5).
- `--xg-data PATH` — WC xG data JSON for xG-based form adjustment.
- `--xg-form-weight P` — weight of xG form vs existing goal form (0-1, default 0.3).

Calibration and import CLIs:

- `wc-poly-calibrate-model --start-year YYYY --end-year YYYY --test-fraction 0.2 --rolling --by-tournament` — calibrate + rolling backtest + per-tournament params.
- `wc-poly-import-schedule --refresh-elo` — import fixtures and refresh Elo seed.
- `wc-poly-import-elo` — refresh team Elo ratings from eloratings.net.
- `wc-poly-import-form --start-year YYYY --end-year YYYY --limit N` — build team-form multipliers.
- `wc-poly-dynamic-elo --show|--predict|--walk-forward` — dynamic Elo tracker for live tournament updates.
- `wc-poly-calibrate-model --optuna --optuna-trials N --optuna-folds K --optuna-objective log_loss|rps|brier` — Optuna hyperparameter optimization (alternative to grid search).

## Verification

- Run full tests after each feature: `python3 -m pytest -q`.
- Run at least one real active/unresolved market query.
- Also test a resolved market; 0/1 prices should be marked SKIP/resolved, not low-liquidity opportunity.
