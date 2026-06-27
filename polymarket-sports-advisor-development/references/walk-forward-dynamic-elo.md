# Walk-Forward Dynamic Elo Implementation (2026-06-23)

Implementation notes for `DynamicEloTracker` and the walk-forward backtest
in `dynamic_elo.py` / `dynamic_elo_cli.py`.

## What Was Built

### `dynamic_elo.py` — Core module
- `DynamicEloTracker`: mutable rating table with World Football Elo updates.
  - `apply_result(home, away, hg, ag, tournament)` — updates ratings and returns `EloUpdate` record.
  - `apply_tournament_results(results)` — batch apply from a list of dicts.
  - `predict_match(home, away, ...)` — predicts using current dynamic ratings.
  - `from_json(path)` — seeds from `team_elo.json`.
  - `export_ratings(path)` — writes current ratings as JSON for live use.
  - `summary()` — human-readable summary of updates and top teams.

- K-factor table (`_K_FACTOR_TABLE`):
  - WC=60, continental cups (EC/AC/CA/CCH/CNL/OC)=50, qualifiers (WQ/ECQ/etc)=40, friendlies=18.
  - Unknown tournament defaults to 30.

- `goal_diff_multiplier(gd)`: |gd|≤1→1.0, |gd|=2→1.5, |gd|≥3→(11+|gd|)/8.
  Mirrors eloratings.net's World Football Elo formula.

- `walk_forward_backtest(matches, ...)`: replays historical data chronologically.
  For each match, predicts TWO ways:
  1. **Static**: using the match's `home_elo`/`away_elo` from eloratings.net data.
  2. **Dynamic**: using the tracker's current rating, then updating tracker after.
  Returns `WalkForwardResult` with log-loss, Brier, RPS, accuracy for both.

### `dynamic_elo_cli.py` — CLI (`wc-poly-dynamic-elo`)
- `--show` — display top 20 ratings.
- `--home X --away Y --home-goals A --away-goals B --tournament WC` — apply a result.
- `--predict HOME AWAY` — predict a match using live ratings.
- `--apply-results FILE.json` — batch apply from JSON.
- `--walk-forward --start-year YYYY --end-year YYYY` — run backtest.
- `--export PATH` — write updated ratings to file.
- Auto-uses `data/team_elo_live.json` if it exists, falls back to `data/team_elo.json`.

### `tests/test_dynamic_elo.py` — 11 tests
- K-factor lookup, goal-diff multiplier, expected score symmetry.
- Tracker apply_result (upset larger delta, friendly low K).
- Predict match, export ratings, from_json round-trip.
- Walk-forward backtest runs and returns all metrics.
- Dynamic tracker tracks form changes.

## Critical Finding: eloratings.net Data IS Already Walk-Forward

**This is the most important lesson from this implementation.**

When we ran the walk-forward backtest on 2316 real matches (2022-2026), the
dynamic tracker performed WORSE than static:

```
Metric      Static    Dynamic     Delta
Log-loss    0.7685    0.9080    +0.1395
Brier       0.4515    0.5218    +0.0703
RPS         0.1395    0.1700    +0.0305
Accuracy     64.4%     59.5%    -4.9%
```

**Why:** The `home_elo` and `away_elo` fields in eloratings.net's yearly results
TSV files are already the pre-match ratings that eloratings.net computes using
their own walk-forward Elo system. Our tracker tries to replicate this with
different K-factors and produces inferior ratings.

**Implication:** The walk-forward backtest is NOT a valid way to improve
prediction quality when using eloratings.net data. The tracker's value is
exclusively for **LIVE tournament use** — when eloratings.net hasn't yet updated
ratings after a match that just finished, and you need ratings for the next
match's prediction.

## Live Tournament Usage Pattern

```bash
# Before tournament: ensure seed ratings are fresh
wc-poly-import-elo

# After each real match (e.g., Brazil 2-1 Argentina in WC):
wc-poly-dynamic-elo \
  --home Brazil --away Argentina \
  --home-goals 2 --away-goals 1 \
  --tournament WC \
  --export data/team_elo_live.json

# Predict next match using live ratings:
wc-poly-dynamic-elo --predict "Brazil" "Switzerland"
# → automatically reads team_elo_live.json if it exists
```

The CLI auto-detects `data/team_elo_live.json` and prefers it over
`data/team_elo.json`. This means `wc-poly-advisor` and `wc-poly-report`
should be configured to read from the live file during tournament play.

## Team Code vs Team Name Gotcha

eloratings.net match data uses **short codes** (BR, AR, SD, US) but
`team_elo.json` uses **full names** (Brazil, Argentina, Sudan, United States).

The `walk_forward_backtest` function handles this by self-seeding from match
data when `seed_is_full_names=True` or `seed_ratings=None`. The tracker
operates on whatever keys the match data uses (codes), so predictions during
backtest also use codes.

For live use, `team_elo.json` already has full names (from `import_elo.py`
which maps codes → names via `en.teams.tsv`). The live CLI works with full
names since that's what the advisor CLI uses.

## K-Factor Calibration Notes

Our K-factors differ slightly from Hicruben's implementation:
- We use WC=60 (they use 55), qualifiers=40 (same), friendlies=18 (same).
- We don't implement recency decay on the K-factor (they use 18-month half-life).
- We don't blend seed+calibrated (they use 70/30 blend).

These differences explain why our dynamic ratings diverge from eloratings.net's
ratings even when starting from the same seed. For live use, this divergence
is acceptable since we're filling a gap (no real-time updates from eloratings.net).
