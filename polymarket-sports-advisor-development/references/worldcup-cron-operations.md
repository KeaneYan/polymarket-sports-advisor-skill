# World Cup Polymarket Cron Operations

Use this reference when operationalizing a read-only Polymarket sports advisor with Hermes cron jobs.

## Cron Pattern

Prefer script-only `no_agent=True` cron jobs for deterministic reports:

- `scanner`: runs frequently, records BUY snapshots to the paper DB.
- `closing`: captures CLV; fixed-time daily capture is a baseline, but kickoff-relative capture is better.
- `settlement`: runs after matches, attempts conservative auto-settlement from Polymarket resolved prices.
- `market-backtest`: runs after settlement and reports BUY totals, CLV, settled P&L, staked fraction, and ROI.
- `overview`: human-readable summary of upcoming matches and paper-trading state.
- `elo-updater`: refreshes Elo ratings + team form from eloratings.net before scanner/overview runs (daily 14:03). See below.

Use `deliver=origin` when the report should return to the current conversation. Keep outputs short enough to arrive as message text, not attachments.

## Verification Sequence

After creating or changing a job:

1. Run the underlying script locally from the project workdir.
2. Create/update the cron job with `enabled_toolsets=["terminal"]`, `no_agent=True`, and the project `workdir`.
3. Trigger it once with `cronjob(action="run", job_id=...)`.
4. List jobs and verify `last_status=ok`, `last_delivery_error=null`, and a sensible `next_run_at`.

`cronjob(action="run")` schedules execution on the next scheduler tick; it may not be synchronous. Wait briefly and list jobs again before claiming it ran.

## Data-Quality Priorities

Once the baseline cron pipeline is running, improve data quality before adding model complexity:

- Capture CLV relative to each match kickoff, ideally 30–90 minutes before start, not just one fixed daily time.
- Deduplicate scanner records so the same match/outcome is not recorded every scan unless edge or market quality changes materially.
- Alert only on changes: new BUY, BUY disappearing, edge moving by more than a threshold, spread/liquidity worsening.
- Add a cron health report that checks scanner/CLV/settlement/backtest last-run status and paper DB deltas.

## Elo/Form Auto-Update Pattern

**Problem:** Elo ratings (`team_elo.json`) and team form (`team_form.json`) are static seed files. During an active tournament they go stale — matches played every day but ratings don't update.

**Solution:** Daily cron job that re-fetches from eloratings.net and overwrites both files in-place.

**Key design decision:** eloratings.net is already walk-forward (updates ratings after each match). We re-fetch the latest `World.tsv` + recent match results rather than computing Elo updates ourselves with `DynamicEloTracker.apply_result()`. The `DynamicEloTracker` code is retained as fallback for when eloratings isn't updated in real-time.

**Implementation:**
- Script: `scripts/update_live_ratings.py` — fetches World.tsv → `refresh_elo_table()` → overwrites `team_elo.json`; fetches recent WC/WQ/F matches → `build_team_form()` → overwrites `team_form.json`.
- Supports `--dry-run`, `--skip-form`, `--skip-elo`, `--form-start-year`.
- Cron: `no_agent=True`, `deliver=weixin`, daily 14:03 (before settlement at 15:00 and scanner runs).
- Shell wrapper: `~/.hermes/scripts/wc_poly_elo_updater.sh`.
- Tests: `tests/test_update_ratings.py` (6 tests for team-code → name mapping).

**Verification:** Run `--dry-run` first to see top movers without writing files. Back up `team_elo.json` / `team_form.json` before first production run.

**xG data auto-update pattern (2026-06-27):** xgscore.io renders match tables client-side via Angular, but the underlying data comes from an internal REST API:
- **API URL:** `https://api.xgscore.io/games/xg?tournamentId=wc&seasonId=2026&gameweek={N}&lng=en`
- Returns per-match JSON with `xG.h`, `xG.a` (expected goals for home/away). Paginated by gameweek (GW1-3 for group stage, more for knockouts).
- **Discovery method:** Open browser DevTools → Network tab → filter `fetch` → look for `api.xgscore.io` calls. The API is not documented but returns clean JSON.
- **Aggregation:** Iterate played matches, accumulate `xg_for` / `xg_against` per team, compute per-match averages.
- **Team aliases needed:** API uses `USA`, `Côte d'Ivoire`, `Bosnia and Herz.`, `Saudi A.`, `Czech`, `Curaçao`, `Congo DR`, `Türkiye` — must map to your project's canonical names (`United States`, `Ivory Coast`, `Bosnia`, `Saudi Arabia`, `Czechia`, `Curaçao`, `DR Congo`, `Turkey`).
- Script: `scripts/update_xg_data.py`. Cron: daily 14:07, `deliver=local`, `no_agent=True`.

**Still manual:** `schedule.json` (knockout TBD slots — fill after group stage resolves), `squad_market_values.json` (Transfermarkt, update after squads announced), `model_params.json` (Optuna re-tune after structural changes).

**Hidden API discovery technique (generalizable):** When a data site renders tables client-side (Angular/React) and curl returns only HTML scaffolding: (1) open the page with `browser_navigate`; (2) run `browser_console` with `performance.getEntriesByType('resource')` filtered to `fetch` initiator type; (3) look for `api.*` domain calls — the hidden REST endpoint will be listed; (4) test with curl + browser User-Agent header; (5) paginate by gameweek/round parameter. This worked for xgscore.io and generalizes to most SPA sports data sites.

## Pitfalls

- A market-level report with `settled=0` is not breakeven; it is insufficient evidence.
- CLV and ROI use different sample sets: open BUY rows can count toward CLV if closing prices exist, but only settled BUY rows should count toward P&L/ROI.
- Fixed-time CLV capture can miss the true closing line when matches start at different local times.
- **Scanner dedup × delivery failure = permanent silent loss.** In `--record` mode, the scanner writes a snapshot to `paper.sqlite` before delivery. `should_alert()` suppresses subsequent alerts when edge hasn't moved >3% since the last snapshot. If the first alert's **delivery fails** (WeChat rate limit, etc.), subsequent scanner runs see the existing DB snapshot and suppress — the report is permanently lost. Symptom: cron output files are all 162-byte `[SILENT]` templates, but running without `--record` shows real BUY signals. Mitigation: temporarily drop `--record` to force output, lower `edge_change_alert` to 1%, or add a first-seen flag so initial BUY always alerts.
- **Feature flag synchronization (2026-06-27).** Every time you add a new `--flag` to `report_cli.py` (e.g. `--bookmaker-odds`, `--market-values`, `--xg-data`), you MUST propagate it to ALL cron shell scripts that call the CLI: `~/.hermes/scripts/wc_poly_match_scanner.sh`, `wc_poly_daily_overview.sh`, `wc_poly_postmatch_settlement.sh`. Otherwise features are built, tested, and committed but never run in production — a silent integration gap that can persist for the entire tournament. **Verification step:** after any CLI flag change, grep all cron shell scripts for the new flag name. Closing/CLV and backtest modes don't use prediction-affecting flags (they read from paper DB), so they don't need them.
- **Team name consistency across data files (2026-06-27).** When adding new matches to `schedule.json` (e.g. knockout stage), ensure team names match the canonical names used in `team_elo.json`, `wc2026_xg.json`, and `squad_market_values.json`. A mismatch (`USA` in schedule vs `United States` in elo) silently produces `elo=0.0`, degrading predictions to noise. **Verification step:** after schedule edits, run a cross-file consistency check — for every non-TBD team in schedule, assert it exists in the elo dict with non-zero value, exists in xG data, and the xG updater's alias map covers any external API naming variants.
