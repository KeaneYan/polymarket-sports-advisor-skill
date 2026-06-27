# World Cup model parameter validation: rho, xi, home advantage

Session: World Cup Polymarket advisor model improvement work.
Dataset: 2,316 eloratings.net international matches, years 2022-2026, tournaments `WC,WQ,F`.
Split: chronological 80/20 via `split_train_test()`; test set = 463 matches.

## Why this matters

After adding RPS/ECE metrics, walk-forward dynamic Elo, and Optuna optimization, the optimizer found parameters far from the old grid-search defaults. The session validated whether those parameters were plausible before changing runtime defaults.

## Main findings

### Dixon-Coles rho

Old grid default: `dixon_coles_rho=-0.30`.
Optuna wide 75-trial result: `-0.145`.

Sweep conclusion:

- Useful region on the 463-match test split: roughly `-0.18` to `-0.10`.
- `-0.30` over-corrects low-score outcomes for this dataset.
- `-0.145` is reasonable and close to the ~`-0.13` value often seen in later Dixon-Coles implementations, but do not claim the original paper fixes a universal rho; rho is dataset-dependent.

Representative rho sweep with other params fixed at Optuna wide values (`base_goals=0.833`, `elo_divisor=907.1`, `home_advantage_elo=148`):

| rho | test log-loss | test RPS | test ECE | test Brier |
|---:|---:|---:|---:|---:|
| -0.30 | 0.7496 | 0.1303 | 0.0146 | 0.4326 |
| -0.25 | 0.7494 | 0.1303 | 0.0151 | 0.4326 |
| -0.20 | 0.7487 | 0.1303 | 0.0182 | 0.4329 |
| -0.15 | 0.7486 | 0.1304 | 0.0188 | 0.4334 |
| -0.13 | 0.7488 | 0.1304 | 0.0193 | 0.4336 |
| -0.10 | 0.7492 | 0.1305 | 0.0228 | 0.4341 |
| 0.00 | 0.7526 | 0.1309 | 0.0235 | 0.4362 |

### xi

`xi` is not a runtime prediction knob in the current code path.

- `_time_decay_weights()` uses `xi` during calibration/optimization.
- `evaluate_parameters(..., weights=None)` uses uniform weights, so changing `xi` alone leaves direct evaluation unchanged.
- Runtime `ModelConfig` does not contain `xi`; reports/predictions use only `base_goals`, `elo_divisor`, `home_advantage_elo`, and `dixon_coles_rho`.

Therefore, `xi=0.019` means “calibration/Optuna should heavily weight recent matches,” not “predictions dynamically decay old matches.” If future code adds runtime data aggregation based on historical matches, re-evaluate this assumption.

### Home advantage

Old grid default: `home_advantage_elo=75`.
Optuna wide result: `148`, with search upper bound `150`.

Sweep conclusion:

- On this dataset/test split, the best region was roughly `120-150` Elo.
- Since 148 is near the upper bound, treat it as suspicious/high and include overfitting caveats.
- A conservative candidate around `120` can be used for sanity checks; do not hand-pick it as production default without another walk-forward CV run.

Representative sweep:

| home_advantage_elo | test log-loss | test RPS | test ECE | test Brier |
|---:|---:|---:|---:|---:|
| 75 | 0.7597 | 0.1350 | 0.0233 | 0.4435 |
| 100 | 0.7514 | 0.1323 | 0.0298 | 0.4375 |
| 120 | 0.7482 | 0.1310 | 0.0167 | 0.4346 |
| 148 | 0.7486 | 0.1304 | 0.0191 | 0.4334 |
| 160 | 0.7505 | 0.1305 | 0.0200 | 0.4339 |
| 200 | 0.7635 | 0.1326 | 0.0353 | 0.4395 |

### base_goals

Old grid default: `1.15`.
Optuna wide result: `0.833`.

Sweep conclusion:

- Useful region on this split: roughly `0.7-0.85`.
- Old value `1.15` was high.

Representative sweep:

| base_goals | test log-loss | test RPS | test ECE | test Brier |
|---:|---:|---:|---:|---:|
| 0.7 | 0.7448 | 0.1306 | 0.0278 | 0.4333 |
| 0.8 | 0.7472 | 0.1303 | 0.0179 | 0.4330 |
| 0.833 | 0.7486 | 0.1304 | 0.0191 | 0.4334 |
| 1.15 | 0.7711 | 0.1328 | 0.0450 | 0.4447 |

## Same test split comparison

| Metric | Grid params | Optuna wide 75t | Delta |
|---|---:|---:|---:|
| log-loss | 0.7621 | 0.7486 | -0.0135 |
| Brier | 0.4435 | 0.4334 | -0.0100 |
| RPS | 0.1346 | 0.1304 | -0.0042 |
| ECE | 0.0334 | 0.0191 | -0.0143 |

Optuna wide improved all four metrics on the same 463-match test split.

## Adoption pitfall

Do not only patch top-level fields in `data/model_params.json` if an old `ensemble.params` section remains. The runtime report path may use ensemble members first, so top-level-only changes are mostly cosmetic. Adopt parameter changes by either:

1. Removing the old grid ensemble and using the Optuna single model; or
2. Extending Optuna export to produce top-K trials and replacing the old grid ensemble with an Optuna ensemble.

This should be done after completing related model-structure changes (e.g. penalty shootout modeling), then regenerated and tested end-to-end.
