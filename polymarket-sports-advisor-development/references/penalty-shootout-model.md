# Penalty shootout model for World Cup knockout simulation

Session context: implemented after external model comparison identified deterministic knockout draw handling as a gap.

## Problem

Old `simulate_knockout_bracket()` resolved a knockout draw deterministically:

```python
winner = home if probs.home >= probs.away else away
```

This over-favored whichever side had the larger regulation-time win probability and made draw-heavy knockout simulations brittle. Example: if probabilities were home 35%, draw 40%, away 25%, every simulated draw went to the home team.

## Implemented pattern

Add a separate penalty model and call it only when a knockout match outcome samples as `draw`:

- `penalty_model.py`
  - `penalty_win_probability(home_elo, away_elo, elo_shrinkage=0.15, elo_divisor=400)`
  - `resolve_penalty_shootout(home_elo, away_elo, rng)`
- `simulate_knockout_bracket(..., elo_lookup=None)`
  - if both teams have Elo ratings: resolve draw with Elo-shrunk penalty probability
  - if Elo is missing: fall back to 50/50 coin flip

Default `elo_shrinkage=0.15` means the shootout keeps only ~15% of the Elo gap signal. This keeps penalties much closer to random than full-match win expectancy.

Example penalty probabilities:

| Elo gap | Shootout win probability |
|---:|---:|
| 0 | 50.0% |
| 100 | 52.2% |
| 200 | 54.3% |
| 400 | 58.5% |
| 800 | 66.6% |

## Verification pattern

Use TDD with fixed RNG seeds and statistical bands:

- equal Elo → roughly 50/50 over 10k trials
- higher Elo → wins more than 50%, but not extreme
- symmetry: `P(A beats B) + P(B beats A) == 1`
- bracket integration: both teams should advance sometimes when draw probability is high
- missing `elo_lookup` falls back to coin flip

Run:

```bash
python -m pytest tests/test_penalty_model.py -v
python -m pytest -q
```

Known verified result from implementation:

```text
Underdog home 35%, draw 40%, Favorite away 25%, Elo 1600 vs 2000
Old logic: Favorite advances only via regulation away win = 25%
New logic: Favorite advances ≈ 25% + 40% * 58.5% = 48.4%
```

## Adoption caveat

Adding the model function is not enough. Reports/CLI must pass `elo_lookup` from `team_elo.json` into `simulate_knockout_bracket()`; otherwise the code deliberately falls back to 50/50 for draws.
