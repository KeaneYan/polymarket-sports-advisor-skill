# Venue Altitude + Market Signals (2026-06-27)

Two new feature modules added to reduce prediction error from sources
the base Elo+DC+NegBinom model doesn't capture.

## venue.py — Altitude/Climate Features

### What it does
- 16 WC 2026 venue registry with altitude (m) and climate classification
- Adjusts team `attack` strength for high-altitude matches
- Flags extreme heat/humidity venues (display only, no rate adjustment)

### Key design decisions
- **Penalty formula**: 5% per 1000m above 1200m, capped at 15%
  - Mexico City (2240m): −5.2% → attack × 0.948
  - Guadalajara (1566m): −1.8% → attack × 0.982
  - Sea level: no effect
- **Acclimatised teams**: Mexico, Colombia, Ecuador, Bolivia, Peru
  - Costa Rica was initially included but removed — San José (1170m) is below
    the 1200m threshold. This was caught by adversary review.
  - Simplification: many players from these countries play in European leagues
    at sea level. Full squad-level analysis would be more accurate.
- **Only attack is adjusted**, not defense. Altitude affects aerobic capacity
  which impacts both scoring and pressing, but modeling only attack is a
  deliberate simplification to avoid over-tuning.
- **Climate is flag-only** — Houston/Miami/Monterrey get a note in
  `adjustment_notes` but no goal-rate adjustment. Insufficient data to
  quantify heat impact reliably.

### Integration point
In `report_cli.py`, after `apply_team_form` and `apply_team_adjustments`,
before `estimate_match_probabilities`:
```python
venue_info = get_venue(getattr(match, "venue", None))
if venue_info is not None:
    h_alt, a_alt = altitude_goal_adjustment(venue_info, match.home, match.away)
    if h_alt != 1.0 or a_alt != 1.0:
        home_strength = replace(home_strength, attack=home_strength.attack * h_alt)
        away_strength = replace(away_strength, attack=away_strength.attack * a_alt)
    adjustment_notes += venue_adjustment_summary(venue_info, match.home, match.away)
```

### Schedule data requirement
`schedule.json` matches must have a `"venue"` field. `MatchScheduleItem`
has `venue: str | None = None` (added 2026-06-27). `load_schedule` parses
it from JSON. The field is optional — if missing, no venue adjustment.

### Tests
14 tests in `tests/test_venue.py`: venue lookup, altitude penalty math,
acclimatisation exemption, Guadalajara < Mexico City ordering, 15% cap,
summary notes for altitude/heat/sea-level/none.

## market_signals.py — Dynamic Model Weight

### What it does
- Computes `model_weight` (0.70–1.0) from Polymarket volume/spread/liquidity
- Overrides the default `model_weight=1.0` when market is sharp
- Weight shrinks model probabilities toward market price via existing
  `_shrink_probability()` in `advisor.py`

### Threshold table
| Signal | Condition | Trust reduction |
|--------|-----------|-----------------|
| Volume | ≥5M | −15% |
| Volume | ≥2M | −10% |
| Spread | <1% | −10% |
| Spread | <2% | −5% |
| Liquidity | ≥500K | −5% |

Floor: 0.70 (configurable via `min_weight` parameter).

### Integration point
In `report_cli.py`, after quotes are extracted, before `recommend_bets`:
```python
best_quote = max(quotes.values(), key=lambda q: q.volume) if quotes else None
if best_quote is not None and config.model_weight >= 1.0:
    signals = MarketSignals(
        volume=best_quote.volume,
        liquidity=best_quote.liquidity,
        spread=best_quote.spread,
        price=best_quote.buy_price,
    )
    dyn_weight = compute_market_weight(signals)
    if dyn_weight < 1.0:
        config = replace(config, model_weight=dyn_weight)
```

Only fires when `config.model_weight >= 1.0` (the default). If user passes
`--model-weight 0.9` explicitly, dynamic weighting is skipped.

### Known limitations (from adversary review)
1. **Step function, not smooth** — thresholds create discontinuities. A market
   at $2.01M gets −10%; at $1.99M gets 0%. Linear interpolation would be smoother
   but harder to reason about.
2. **Per-outcome volume** — `best_quote.volume` is the volume of the single
   highest-volume outcome (home/draw/away), not the total match market volume.
   Thresholds may need recalibration.
3. **Selection bias risk** — dynamic weight reduces model trust on sharp markets,
   leaving the model's biggest edges on thin markets where execution is hardest.

### Tests
12 tests in `tests/test_market_signals.py`: low/thin market = 1.0, high volume
reduces, very high reduces more, tight spread reduces, floor behavior,
configurable floor, summary text generation.
