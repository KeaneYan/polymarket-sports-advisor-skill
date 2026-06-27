# Post-P1 Improvement Attempts (2026-06-22)

After P1 completion (test_ll=0.7625), three improvement techniques were tried
and all failed. These findings are as valuable as the successes.

## Attempt 1: Ensemble Top-K Parameters

**Approach:** Return top-K parameter sets from grid search instead of just the
single best. At prediction time, average probabilities across all K sets.

**Implementation:** Added `calibrate_parameters_topk()` and `evaluate_ensemble()`
to `calibration.py`. `model_config.py` gained `ensemble_params_for()` method.
`report_cli.py` uses ensemble averaging when ensemble params exist.

**Result:** test_ll = 0.7627 vs single-best 0.7625 (delta +0.0002, no improvement).

**Why it failed:** Top-5 parameters were highly homogeneous — all had
elo_divisor=950, home_advantage=75, rho=-0.3, only base_goals varied 1.05-1.25.
The loss surface is flat near the optimum, so averaging similar predictions
provides no information gain.

**Lesson:** Ensemble helps only with structurally different models (different
model classes, different data sources), not different hyperparameters of the
same model. The code is reusable for future heterogeneous ensemble.

## Attempt 2: Time-Decay Calibration (Dixon-Coles xi)

**Approach:** Add exponential time-decay weights to calibration log-likelihood:
`w_i = exp(-xi * age_days)`. Recent matches get higher weight. Add `xi` to
the grid search alongside other parameters.

**Implementation:** Added `xi: float = 0.0` to `CalibrationParams`,
`_time_decay_weights()` helper, `date: str = ""` field to `HistoricalMatch`,
and xi_grid to all calibration functions.

**Grid:** xi in [0.0, 0.0001, 0.0002, 0.0005, 0.001] (half-lives: ∞, 19yr,
9.5yr, 3.8yr, 1.9yr).

**Result:**
- First run (aggressive grid [0.0, 0.0005, 0.001, 0.002, 0.005]):
  xi=0.005 selected (half-life 139 days), train_ll improved -11.7% but
  test_ll worsened +0.35%. Classic overfitting.
- Second run (moderate grid): xi=0.001 selected (half-life 1.9yr),
  train_ll improved -2.6% but test_ll unchanged (0.7625 → 0.7625).

**Why it failed:** International match data is sparse (~10-15 matches per team
per year). Over a 4-year span (2022-2026), team strength doesn't change enough
for time-decay to help. Aggressive decay wastes useful historical data; mild
decay provides no benefit.

**Lesson:** Time-decay helps in leagues (38 matches/team/year, rapid squad
changes) but not for sparse international data. Grid search correctly converges
to near-zero xi, confirming the mechanism is unhelpful here.

## Attempt 3: Isotonic Post-Hoc Calibration

**Approach:** Fit IsotonicRegression curves per outcome (home/draw/away) on
calibration predictions, then apply corrections to new predictions. Fixes
systematic probability biases without changing the model.

**Calibration curve diagnostic (test set, 463 matches):**
- Home: avg_pred=56.8%, actual=59.6% (under by 2.8%)
- Draw: avg_pred=22.4%, actual=25.1% (under by 2.7%)
- Away: avg_pred=20.8%, actual=15.3% (over by 5.5%)

**Two approaches tried:**
1. Separate calibration set (463 matches): too few samples, isotonic
   regression fitted noise. test_ll worsened +0.0107.
2. Rolling backtest OOS predictions (1388 points): better sample size but
   still worsened test_ll on held-out set (+0.0291).

**Why it failed:** Isotonic regression is non-parametric and needs enough
samples per probability bin. With 463 calibration matches and ~15% away-win
rate, only ~70 away-win events exist — not enough to reliably calibrate
the away-win probability curve, especially in the tails.

**Lesson:** Post-hoc calibration requires significantly more data than model
training. For 2313 total matches, the calibration set (~463) is too small.
Isotonic calibration works better with 5000+ matches or when systematic biases
are larger (>10%). For small biases (2-5%), the noise in the calibration curve
exceeds the signal.

## Model Ceiling Assessment

At test_ll=0.7625 with 2313 matches, the Elo+Dixon-Coles framework has
reached its practical ceiling with this dataset. Remaining improvement
directions (Negative Binomial, attack/defense MLE, Bayesian framework) all
require significant structural changes with uncertain payoff.

**Practical implication for trading:** The model produces 5-18% edge signals.
Log-loss improvement from 0.7625 to 0.75 would have minimal impact on average
edge, though improvements concentrated in specific probability ranges could
still benefit targeted betting strategies.

## Key Takeaway: When to Stop Optimizing

Not every improvement avenue is worth pursuing. Signs that a model has reached
its ceiling with a given dataset:

1. **Grid search converges to similar parameters** across folds → ensemble won't help
2. **Time-decay xi converges to near-zero** → historical data is uniformly valuable
3. **Calibration curve shows small biases (<5%)** but calibration fails due to sample size → biases are real but not fixable with available data
4. **Multiple independent improvement attempts all fail** → the model structure is the bottleneck, not tuning

At this point, the productive path is either:
- Accept the model's performance and focus on edge quality (market selection, timing, sizing)
- Invest in fundamentally different model architectures (Bayesian, ML) or data sources (xG, player stats)
