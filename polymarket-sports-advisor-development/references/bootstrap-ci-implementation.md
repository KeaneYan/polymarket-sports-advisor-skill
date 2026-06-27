# Bootstrap Confidence Intervals — Implementation (2026-06-27)

## Two-Phase Architecture

### Phase 1: Pre-compute (slow, once)

`scripts/precompute_bootstrap.py` → `data/bootstrap_params.json`

- Subsamples historical matches to 500 (full 2335 is too slow)
- Runs 50 bootstrap iterations, each:
  1. Resample with replacement
  2. Grid-search calibrate → one parameter set
  3. Save `{base_goals, elo_divisor, home_advantage_elo, dixon_coles_rho}`
- Runtime: ~76 seconds for 50 iterations × 500 matches × 18-cell grid
- Grid: `[1.05, 1.20, 1.35]` × `[750, 950]` × `[0, 50]` × `[-0.15, 0.0]`

### Phase 2: Fast CI at prediction time (< 50ms)

`fast_bootstrap_ci(bootstrap_params, home_elo, away_elo, ...)`

- Loads pre-computed params from JSON
- For each param set: one `estimate_match_probabilities()` call
- 50 predictions → percentiles → 90% CI (5th/95th)

## Performance Pitfall (CRITICAL)

Full bootstrap with 2335 matches × 100 iterations × 18-grid = **4.2M model
evaluations** → timed out at 5 minutes. Always pre-compute and cache.

The slow path (`bootstrap_match_probabilities()`) is for ad-hoc analysis only,
never for scanner reports.

## Kelly CI Bug (fixed)

Original implementation computed Kelly using `probs.home` regardless of which
outcome the BUY was on. When the BUY is on away/draw, this produced 0% Kelly
(home was the underdog). Fix: `buy_outcome` parameter selects which outcome's
probability feeds the Kelly formula.

```python
# WRONG (always uses home):
kelly = _kelly_fraction(probs.home, buy_price, ...)

# CORRECT (uses the actual BUY outcome):
outcome_prob = {"home": probs.home, "draw": probs.draw, "away": probs.away}[buy_outcome]
kelly = _kelly_fraction(outcome_prob, buy_price, ...)
```

## CI vs Point Estimate

Bootstrap params lack dispersion (NegBinom), so bootstrap mean ≠ production
point estimate. Do NOT show absolute CI range next to the point estimate —
it looks like a bug when 41% sits outside [43%-46%]. Show `CI±1%` (half-width)
instead.

## Report Integration

- `_compute_ci_for_report()` in `report_cli.py` computes CI for the top
  recommendation's outcome, passes `buy_outcome=top.outcome`.
- `reports.py` `_ci_width()` extracts the BUY outcome's CI width.
- Only displayed when width > 1% (narrow CIs add noise without value).
- `--bootstrap-params data/bootstrap_params.json` flag enables CI on `wc-poly-report`.
