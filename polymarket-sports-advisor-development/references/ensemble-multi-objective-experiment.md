# Multi-Objective Ensemble Experiment (2026-06-26)

**Result: NEGATIVE** — ensemble underperforms single best model.

## Hypothesis

Running Optuna with three different objectives (log_loss, RPS, Brier)
produces three parameter sets that are each individually strong on their
target metric. Equal-weight averaging them should produce a more robust
prediction that doesn't over-optimize any single metric.

## Setup

- Dataset: 2335 matches (WC/WQ/F, 2022-2026), train/test 80/20 split
- Optimizer: Optuna TPE sampler, MedianPruner, 75 trials, 5-fold walk-forward CV
- Search space: base_goals [0.5, 2.5], elo_divisor [400, 1800],
  home_adv [0, 150], rho [-0.40, 0.10], xi [0, 0.02], dispersion [0.0, 1.0]
- Seed: 42 (same for all three runs)

## Results

### Individual members

| Member | CV objective | CV score | test_ll | test_RPS | test_brier | test_ECE |
|--------|-------------|----------|---------|----------|------------|----------|
| log_loss | log_loss | 0.7418 | 0.7703 | 0.1352 | 0.4473 | 2.63% |
| rps | rps | 0.1372 | 0.7721 | 0.1357 | 0.4499 | 2.98% |
| brier | brier | 0.4460 | 0.7783 | 0.1356 | 0.4489 | 2.91% |

### Ensemble vs current

| Model | test_ll | test_RPS |
|-------|---------|----------|
| **Current single (Optuna log_loss)** | **0.7666** | **0.1343** |
| 3-member ensemble | 0.7702 | 0.1354 |
| Delta | +0.0036 (worse) | +0.0011 (worse) |

### Optimized parameters

| Parameter | log_loss member | rps member | brier member | Current model |
|-----------|----------------|------------|--------------|---------------|
| base_goals | 1.000 | 0.764 | 0.836 | 1.184 |
| elo_divisor | 875.9 | 743.3 | 749.6 | 927.4 |
| home_adv | 129.1 | 144.7 | 145.5 | 96.0 |
| rho | -0.316 | +0.043 | -0.308 | -0.247 |
| xi | 0.01692 | 0.00217 | 0.00839 | 0.01303 |
| dispersion | 0.1096 | 0.1688 | 0.1428 | 0.0999 |

## Why it failed

1. **Generalization gap (CV → test):** All three members had better CV
   scores than the current model's CV (0.7506), but worse test scores.
   The walk-forward CV is optimistic — 75 trials on ~2300 matches with
   6 parameters overfits the CV folds despite chronological splitting.

2. **RPS/Brier members sacrifice log_loss:** The rps-optimized member
   (rho=+0.043!) and brier-optimized member diverge sharply from the
   log_loss optimum, pulling the average away from the best region.

3. **Parameter diversity ≠ model diversity:** All three members share the
   same Elo+DC+Poisson architecture. Averaging hyperparameter variations
   of the same model provides little additional information — it's closer
   to regularization than genuine diversification.

## Lessons

1. **When CV < test for all members, the optimizer is overfitting the CV.**
   This is a red flag — do not trust CV improvements that don't transfer
   to the held-out test set.

2. **Multi-objective ensemble within one architecture is not worth it**
   when the single model is already well-tuned. The complexity of
   maintaining three parameter sets and the ensemble framework adds no value.

3. **If ensemble is revisited, it must be multi-architecture** — different
   rating systems (Colley, PageRank), different goal models (Poisson vs
   Bivariate Poisson), or different feature sets. Only architectural
   diversity produces uncorrelated errors worth averaging.

4. **Always evaluate on the SAME held-out test set** when comparing
   ensemble vs single model. The comparison above uses the same 80/20
   split as the original Optuna calibration, making it apples-to-apples.

## What was done with the result

- The `ensemble` field was written to `model_params.json` during the
  experiment, then immediately reverted since the result was negative.
- The optimization script was kept at
  `scripts/run_ensemble_optimization.py` for future reference.
- All 137 tests pass after reverting.
