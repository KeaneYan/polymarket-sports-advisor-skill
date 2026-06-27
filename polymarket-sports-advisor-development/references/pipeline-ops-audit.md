# Pipeline Ops Audit Methodology

Use this when reviewing a running advisor system for integration gaps, stale data,
and silent failures. Best run after major feature additions and before a tournament phase transition
(e.g. group stage → knockout).

## Audit Procedure

### 1. Feature flag propagation check
For every `--flag` added to `report_cli.py` or equivalent CLI:
- Grep ALL cron shell scripts under `~/.hermes/scripts/` for the flag name
- Any script running a prediction-generating mode (scanner, overview, settlement) MUST have ALL feature flags
- Closing/CLV and backtest modes read from paper DB, not predictions — flags not needed there
- **Smoke test:** run each script's exact CLI command locally with `--hours 48` to confirm no crash and expected output format

### 2. Data file freshness
| File | Auto-updated? | By what? | Frequency |
|------|--------------|----------|-----------|
| `team_elo.json` | ✅ | `update_live_ratings.py` cron 14:03 | Daily |
| `team_form.json` | ✅ | `update_live_ratings.py` cron 14:03 | Daily |
| `wc2026_xg.json` | ✅ | `update_xg_data.py` cron 14:07 | Daily |
| `bootstrap_params.json` | ❌ | `scripts/precompute_bootstrap.py` (manual) | After structural model changes |
| `schedule.json` | ❌ | Manual (knockout TBDs filled after group stage) | Per phase transition |
| `squad_market_values.json` | ❌ | Manual (Transfermarkt) | After squads announced |
| `model_params.json` | ❌ | `wc-poly-calibrate-model --optuna` | After structural changes |
| `isotonic_calibrator.json` | ❌ | Calibration pipeline | After model param changes |
| `wc2026.xlsx` | ❌ | Manual (football-data.co.uk) | As available |

### 3. Team name consistency
Run a cross-file consistency check:
```python
# For every non-TBD team in schedule.json, assert:
# - Exists in team_elo.json with non-zero value
# - Exists in wc2026_xg.json teams list
# - xG updater alias map covers any external API naming variants
```
Common mismatches:
- `USA` vs `United States` (schedule/elo)
- `Cape Verde` vs `Cabo Verde` (elo/xG API)
- `Ivory Coast` vs `Côte d'Ivoire` (elo/xG API)
- `Bosnia` vs `Bosnia and Herzegovina` (elo/xG API)
- `Curacao` vs `Curaçao` (xG API)

### 4. Schedule completeness
- Check match_number continuity (1..N, no gaps)
- Count by stage (group + R32 + R16 + QF + SF + 3rd + Final = expected total)
- Verify all non-TBD teams have Elo ≠ 0.0
- Verify knockout bracket references (W73, W74...) are consistent with Wikipedia/FIFA bracket

### 5. Cron timing dependency chain
Verify data-update crons run BEFORE report crons:
```
14:03 elo-updater (deliver=local)
14:07 xg-updater (deliver=local)
   ↓ fresh data available
15:00 settlement
16:30 backtest
17:00 health
09:30 overview (next day — uses yesterday's elo/xG)
```

### 6. Temporary file hygiene
- Never leave data files in `/tmp` — move to `data/`
- Grep all scripts for `/tmp` paths
- The `/tmp` directory is cleared on reboot

### 7. Knockout schedule construction
When building `schedule.json` for knockout stages:
- **Data sources:** Wikipedia bracket page (has team matchups, dates, venues in a large bracket table) + FIFA.com match schedule page (has times in viewer's local timezone)
- **FIFA page structure:** The match list page renders client-side but data is visible in the accessibility tree / innerText. Extract with `browser_console` + `document.body.innerText` parsing
- **Time conversion:** FIFA page shows times in viewer's timezone (detected via IP). If viewing from China (UTC+8), subtract 8 hours for UTC
- **Bracket structure:** Use `Winner Match N` / `Loser Match N` as home/away for unresolved knockout rounds. Elo = 0.0 for these (resolved at prediction time or manually)
- **Wikipedia data extraction:** The bracket table (table index 2) has date + venue interleaved with team names in row order. Individual match result tables (index 3+) have `TeamA Match N TeamB` format
- **R32 bracket assignments** depend on which third-placed teams qualify — verify against the actual FIFA bracket, not just Wikipedia's group-stage-ordered bracket

### 8. Full-pipeline smoke test
After any pipeline change:
1. Run `python3 -m pytest tests/ -x -q` — all tests must pass
2. Run scanner mode with all flags: `PYTHONPATH=src python3 -m worldcup_poly_advisor.report_cli --mode scanner --hours 48 --bootstrap-params data/bootstrap_params.json --bookmaker-odds data/wc2026.xlsx --market-values data/squad_market_values.json --xg-data data/wc2026_xg.json --xg-form-weight 0.3`
3. Verify output shows: CI±N%, bookmaker divergence (if any), xG form influence, correct team names
4. Run overview mode similarly — should show BUY count and backtest summary
