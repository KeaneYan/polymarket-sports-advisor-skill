# Neutral-Venue Home Advantage Correction (2026-06-25)

## Problem

The calibrated `home_advantage_elo=148` (from Optuna) was inflated by
qualifiers in the training data. World Cup matches are on neutral ground,
but applying 148 Elo points of "home advantage" gave the listed "home"
team a massive phantom edge.

**Before:** USA(1780) vs Mexico(1720) → home=58.5% (the +20.1% home edge
was pure artifact).

## Solution

Added `neutral_venue: bool = False` to `estimate_match_probabilities()`.
When True, zeroes out `home_advantage_elo` entirely. Host-nation effects
can be added explicitly via `team_adjustments.json` (`elo_delta`).

### Design decision: zero, not shrink

Initially tried shrinking to 25% of calibrated value. But even 25 Elo
points at neutral venue created a 9% home-away gap for equal-Elo teams.
Zero is correct: any residual host effect is better modeled explicitly
via team adjustments so it's auditable.

## Files Changed (6 files)

1. **`model.py`** — Added `neutral_venue` param + `_effective_home_advantage()`
   helper. The helper is the single point where venue logic lives.
2. **`reports.py`** — Added `neutral_venue` field to `MatchScheduleItem`.
   Added `_is_neutral_tournament()` helper + `_NEUTRAL_TOURNAMENT_CODES`
   constant (currently `{"WC"}`). `load_schedule()` auto-detects from
   tournament code, with per-match JSON override.
3. **`calibration.py`** — Duplicated `_is_neutral_tournament()` (kept local
   to avoid circular import). `_match_probabilities()` now passes
   `neutral_venue` based on match.tournament. This means re-running Optuna
   automatically accounts for neutral venues in WC folds.
4. **`report_cli.py`** — All 4 prediction call sites pass
   `neutral_venue=getattr(match, "neutral_venue", False)`. Knockout report
   uses `neutral_venue=True` unconditionally (knockout matches are always
   neutral).
5. **`cli.py`** — Added `--neutral-venue` flag.
6. **`tests/test_model.py`** — 4 new tests.

## Pitfalls Encountered

1. **Shrink vs zero:** First attempt used `home_adv * 0.25` → tests failed
   because even 25 Elo still creates visible asymmetry for equal teams.
   Switched to `0.0` — the clean solution.

2. **Circular import risk:** `calibration.py` cannot import from
   `reports.py` (reports imports calibration). Solution: duplicate the
   `_is_neutral_tournament` helper in both files. They share the same
   constant set `{"WC"}` — if you add continental tournaments (EC, AC, CA,
   CCH), update BOTH copies.

3. **Optuna inherits the fix for free:** Because Optuna imports
   `_match_probabilities` from calibration.py, and that function now applies
   neutral-venue logic, re-running Optuna automatically evaluates WC folds
   with neutral venues. No optuna_optimizer.py changes needed.

4. **Knockout is always neutral:** Don't rely on tournament auto-detection
   for knockout matches — hardcode `neutral_venue=True` in the knockout
   report builder. Tournament codes for knockout rounds may vary.

5. **Not a "pure config" change:** The roadmap initially estimated this as
   "no code change, just adjust params." In reality it required touching 6
   files and adding a new parameter to the core prediction function. The
   code change was necessary because the neutral-venue decision is
   per-match, not per-parameter-set.

## Testing Pattern

```python
# Equal-Elo teams at neutral venue → perfectly symmetric
probs = estimate_match_probabilities(
    TeamStrength("A", 1800), TeamStrength("B", 1800),
    home_advantage_elo=100, neutral_venue=True,
)
assert round(probs.home, 4) == round(probs.away, 4)

# Neutral venue reduces home-away gap vs regular
neutral_gap = abs(neutral.home - neutral.away)
regular_gap = abs(regular.home - regular.away)
assert neutral_gap < regular_gap
```

## Extending to Other Tournaments

To add more neutral-venue tournaments (e.g., Euro, Copa America), update
`_NEUTRAL_TOURNAMENT_CODES` in BOTH `reports.py` and `calibration.py`:

```python
_NEUTRAL_TOURNAMENT_CODES = frozenset({"WC", "EC", "AC", "CA", "CCH"})
```

Then re-run Optuna calibration so parameters adjust for the new venue logic.
