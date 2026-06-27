# RPS & ECE Implementation (2026-06-23)

Implementation notes for Ranked Probability Score and Expected Calibration
Error in the worldcup-polymarket-advisor calibration pipeline.

## What Changed

### `calibration.py`
- `CalibrationResult` dataclass: added `rps: float = 0.0` and `ece: float = 0.0`.
- New `rps_for_matches(matches, params, weights)` — weighted average RPS.
- New `ece_for_matches(matches, params, bins=10)` — pooled 3-outcome ECE.
- New `_match_rps(match, params)` — single-match RPS helper.
- `evaluate_parameters()` now computes rps + ece alongside log_loss + brier.
- `evaluate_ensemble()` now computes rps + ece for averaged predictions.

### `calibrate_model.py`
- All output sections emit `train_rps`, `test_rps`, `train_ece`, `test_ece`:
  train/test split, ensemble, rolling folds, by-tournament.
- Final stdout summary prints all four metrics.

### `tests/test_calibration.py`
- 6 new tests: `test_rps_rewards_probabilities_matching_results`,
  `test_rps_perfect_prediction_near_zero`, `test_rps_ordered_penalty`,
  `test_ece_returns_valid_range`, `test_ece_decreases_with_better_calibration`,
  `test_evaluate_parameters_includes_rps_and_ece`.

## Formulas

### RPS (single match)
```
RPS = 0.5 * [ (P_home - Y_home)² + ((P_home + P_draw) - (Y_home + Y_draw))² ]
```
- `Y_home = 1` if actual outcome is home, else 0.
- `Y_home_draw = 1` if actual is home or draw, else 0.
- This is the 3-outcome RPS. The second term uses cumulative probabilities
  to respect the home > draw > away ordering.
- Range: [0, 0.5]. Lower is better. Perfect prediction → 0.
- Uniform prediction (1/3 each) with actual = home → RPS = 5/18 ≈ 0.278.

### ECE (dataset-level)
```
ECE = Σ_bins (n_bin / N_total) * |avg_predicted_bin - avg_observed_bin|
```
- Pool all 3 outcome probabilities (home, draw, away) across all matches.
- Bin each probability into one of 10 equal-width bins [0,0.1), [0.1,0.2), ...
- For each bin, compute the average predicted probability and the average
  observed frequency (fraction of outcomes that actually occurred).
- ECE is the sample-weighted average of the absolute differences.
- Range: [0, 1]. Lower is better. Well-calibrated model → < 0.05.
- Note: ECE is NOT weighted by calibration `xi` time-decay; it always uses
  uniform weights because it measures calibration quality, not fit quality.

## Verification

Sanity-checked with synthetic data:
- Uniform prediction (elo_divisor=100000, equal Elo): RPS ≈ 0.274 (theory: 0.278).
  Small discrepancy because Dixon-Coles rho=0 still doesn't produce exactly 1/3.
- Near-perfect prediction (Elo 2200 vs 1400, divisor=200, home wins 5-0):
  RPS = 0.0002. Probs were 98% / 1.7% / 0.2%.
- ECE is always in [0, 1].
- Better-calibrated parameter sets produce lower ECE.

## Implementation Pitfalls

1. **Don't use `P_home + P_draw` as a variable name in code.** Python will
   parse `P_home+draw` as `P_home + draw` (adding a variable named `draw`).
   Always parenthesize: `(P_home + P_draw)`.

2. **ECE bin index must be clamped.** `int(1.0 * 10) = 10` but valid indices
   are 0-9. Use `min(bins - 1, max(0, int(p * bins)))`.

3. **RPS is NOT Brier/3.** RPS uses cumulative probabilities and has a
   different range. Don't add sanity checks assuming RPS ≈ Brier/3.

4. **ECE pools all 3 outcomes.** Unlike per-outcome calibration curves, the
   ECE implementation pools home, draw, and away probabilities into the same
   set of bins. This gives a single calibration number for the whole model.

5. **Weighted RPS uses calibration weights; ECE does not.** RPS for_matches
   accepts `weights` (from time-decay). ECE does not, because time-decay
   weighting on a calibration metric would conflate fit quality with
   calibration quality.
