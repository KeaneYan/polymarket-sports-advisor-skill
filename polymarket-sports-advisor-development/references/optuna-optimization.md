# Optuna Hyperparameter Optimization

## Overview

Replaces grid search with Bayesian optimization (TPE sampler) for finding optimal Elo/Poisson/Dixon-Coles parameters. Uses **walk-forward cross-validation** (chronological folds) to prevent overfitting.

## Implementation

- **File:** `src/worldcup_poly_advisor/optuna_optimizer.py`
- **CLI:** `wc-poly-calibrate-model --optuna` (grid search remains the default)
- **Dependency:** `optuna>=3.0` (optional: `pip install -e ".[optuna]"`)

## Search Space

The search space was widened after initial 50-trial results showed boundary-touching params.

| Parameter | Initial Range (narrow) | Widened Range | Grid Search Values |
|-----------|----------------------|---------------|-------------------|
| base_goals | [0.8, 2.0] | [0.5, 2.5] | {1.05, 1.15, 1.25, 1.35, 1.45, 1.55} |
| elo_divisor | [500, 1500] | [400, 1800] | {650, 750, 850, 950, 1100, 1300} |
| home_advantage_elo | [0, 120] | [0, 150] | {0, 20, 35, 50, 75} |
| dixon_coles_rho | [-0.35, 0.05] | [-0.40, 0.10] | {-0.30, -0.20, -0.15, -0.10, -0.05, 0.0} |
| xi (time-decay) | [0, 0.01] | [0, 0.02] | {0, 0.0001, 0.0002, 0.0005, 0.001} |
| dispersion (NegBinom) | — | [0.0, 1.0] | — (added 2026-06-25) |

The current code uses the widened ranges. See below for the improvement from widening.

## Walk-Forward CV

Matches are split chronologically into `n_folds` (default 5). For fold i:
- Train conceptually on matches[0 : i × fold_size]
- Evaluate on matches[i × fold_size : (i+1) × fold_size]
- Objective = average metric across all folds

This is NOT random K-fold. Time-ordered splitting is essential because recent matches inform future predictions.

## Median Pruner

Per-fold scores are reported via `trial.report(running_avg, step=fold_index)`. The MedianPruner can then prune underperforming trials after 3 warmup steps, saving computation on clearly bad parameter regions.

**Critical pitfall:** Without `trial.report()` calls, the MedianPruner is a complete no-op — all trials run to completion with zero pruning.

## Real-Data Results (2316 matches, 50 trials, 5-fold CV)

| Metric | Grid Search | Optuna |
|--------|------------|--------|
| Test log-loss | 0.7625 | 0.7533 |
| Test RPS | — | 0.1314 |
| Test ECE | — | 2.3% |
| CV log-loss (5-fold) | — | 0.7372 |

**Best params from Optuna:**
- base_goals=0.80, elo_divisor=823, home_adv=111, rho=-0.22, xi=0.009

## Key Findings

### 1. xi=0.009 contradicts earlier "time-decay doesn't help" conclusion
Grid search only tried xi up to 0.001 and concluded time-decay provides no benefit. Optuna explored up to 0.01 and found xi=0.009 significantly better. **Lesson:** grid search with too-narrow ranges can produce false-negative conclusions about feature usefulness.

### 2. Boundary-touching params
base_goals=0.80 and xi=0.009 both hit search-space boundaries, meaning the true optimum may be outside the range. Recommended next step: widen to base_goals [0.5, 2.5] and xi [0, 0.02] and re-run.

### 3. CV vs test split comparison
Optuna's CV log-loss (0.7372) is not directly comparable to grid search's test log-loss (0.7625) because they use different evaluation methods. On the same train/test split, Optuna's params give test_log_loss=0.7533 — an improvement of 0.009 over grid search.

## Pitfalls Summary

1. **MedianPruner no-op:** Must call `trial.report()` per fold for pruning to work.
2. **Boundary params:** Check if best params touch search-space edges; widen if so.
3. **Grid search false negatives:** Optuna can find useful parameter regions that grid search missed if grid ranges were too narrow.
4. **Do NOT auto-rerun daily:** Run on-demand when model structure changes. Commit best_params.json. Daily reruns risk overfitting to recent data.
5. **Reproducibility:** Use fixed `--optuna-seed 42` for reproducible results.
