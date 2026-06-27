# External Model Comparison & Improvement Roadmap (2026-06-23)

Competitive analysis of 6 GitHub open-source WC 2026 prediction projects vs
our model. Conducted to find techniques we're missing after the post-P1
plateau (test_ll=0.7625).

## Reference Projects Analyzed

| Project | Core Approach | Key Differentiator |
|---------|--------------|-------------------|
| Hicruben/world-cup-2026-prediction-model | Elo + DC + 50k Monte Carlo | Walk-forward Elo, live track record, RPS/ECE metrics |
| josemqu/fifa-world-cup-2026 | Next.js simulator + API-Football | Monte Carlo, live sync |
| CupCast 2026 (dev.to) | XGBoost + Optuna | Daily retraining, prediction freezing |
| javierruanohdez/world-cup-2026-prediction | Gradient Boosting | Penalty shootout model, round-variance scaling |
| Leitner/Zeileis/Hornik (2010) academic | Hybrid RF + bookmaker consensus | Player ratings + market values + odds |
| Towards Data Science 11-model comparison | Multi-paradigm ensemble | Elo, Colley, PageRank, classifiers, betting market |

## Head-to-Head: Our Model vs Hicruben

| Dimension | Our Model | Hicruben |
|-----------|-----------|----------|
| Data volume | 2314 matches | 913 matches |
| Test log-loss | 0.7625 | 0.8856 |
| Brier | 0.4437 | 0.5204 |
| RPS | ✅ implemented | 0.1746 |
| ECE | ✅ implemented | 2.3% |
| Walk-forward Elo | ❌ static ratings | ✅ per-match K-factor updates |
| K-factor by tournament | ❌ uniform | ✅ WC=55, qualifier=40, friendly=18 |
| Goal-difference multiplier | ❌ | ✅ `gMult(gd)` |
| Calibration | ✅ Isotonic | ✅ 10-bin reliability histogram |
| Ensemble | ✅ 5-member | ❌ single model |
| Team form | ✅ goals-based | ❌ |
| DC rho | -0.3 | -0.13 |
| Poisson max_goals | 10 | 8 |

**Warning:** Cannot directly compare log-loss — different datasets, time ranges,
tournament filters, and match counts. Our model uses more data and per-tournament
calibration, which inflates apparent performance vs their simpler approach.

## Techniques We're Missing (Ranked by Priority)

### P0 — Highest Leverage

**1. ~~RPS (Ranked Probability Score) metric~~ — ✅ DONE (2026-06-23)**
- Implemented `rps_for_matches()` and `ece_for_matches()` in `calibration.py`.
- `CalibrationResult` dataclass extended with `rps` and `ece` fields.
- `evaluate_parameters()` and `evaluate_ensemble()` compute both metrics automatically.
- All `calibrate_model.py` output sections emit them: train/test, ensemble, rolling folds, by-tournament.
- Verification: uniform prediction RPS ≈ 0.274 (theory: 5/18 ≈ 0.278); near-perfect prediction RPS = 0.0002.
- 6 new tests added (`test_rps_*`, `test_ece_*`, `test_evaluate_parameters_includes_rps_and_ece`). All 86 tests pass.
- See `references/rps-ece-implementation.md` for implementation details.

**2. ~~Walk-forward Elo dynamic updates~~ — ✅ DONE (2026-06-23)**
- Implemented `DynamicEloTracker` class in `dynamic_elo.py` with:
  - K-factor by tournament: WC=60, continental=50, qualifier=40, friendly=18.
  - Goal-diff multiplier: |gd|≤1→1.0, |gd|=2→1.5, |gd|≥3→(11+|gd|)/8.
  - `walk_forward_backtest()` comparing dynamic vs static Elo.
  - CLI `wc-poly-dynamic-elo` for live tournament use.
  - 11 tests, all 97 pass.
- **Critical finding:** eloratings.net match data Elo fields are ALREADY
  walk-forward — their system updates after every match. Our tracker with
  different K-factors produces WORSE ratings (log-loss 0.908 vs 0.769 static).
  **The tracker is for LIVE tournament use only** (when eloratings.net hasn't
  updated yet between matches), NOT for backtest improvement.
- See `references/walk-forward-dynamic-elo.md` for full implementation details
  and the live-tournament usage pattern.

**3. Bookmaker odds consensus feature**
- What: Strip overround from N bookmakers, average on logit scale, use as
  team-strength signal alongside Elo.
- Source: Leitner, Zeileis & Hornik (2010). Market odds encode injury/tactical/
  squad info that pure stats miss.
- **Risk:** International odds (especially friendlies, small-nation qualifiers)
  are inconsistently available. Data acquisition is the main challenge.
- **Overfitting risk:** Any added feature increases dimensionality. Use strict
  walk-forward CV to validate.
- Effort: Medium. Needs odds data pipeline.

### P1 — Medium Leverage

**4. Optuna hyperparameter optimization**
- What: Replace grid search with Optuna TPE sampler, 75 trials × 3-fold CV.
- CupCast 2026 discipline: run on-demand when structural changes happen, NOT
  daily. Commit best_params.json to git.
- **Overfitting risk:** More hyperparameters + small dataset (2314 matches) =
  easy to overfit. Always validate with walk-forward, not random k-fold.
- Effort: ~half day to set up.

**5. Penalty shootout model for knockout rounds**
- What: Our `simulate_knockout_bracket` picks the higher-prob team on draws.
  Hicruben uses Elo win expectancy to decide penalty winner — stronger teams
  win penalties more often than 50/50.
- Effort: ~2 hours. Simple logistic on Elo differential.

**6. DC rho = -0.3 may be too aggressive**
- Dixon & Coles (1997) estimated ρ ≈ -0.13 on English Premier League data.
- Subsequent implementations typically find -0.1 to -0.2.
- Our -0.3 was selected by grid search on international data, but may over-
  correct for low-score draws. International football has lower scoring than
  domestic leagues, which could justify more negative rho — but -0.3 is at
  the edge of plausibility.
- Action: Re-verify with narrower grid [-0.20, -0.15, -0.10] and compare
  RPS/log-loss on held-out set.

### P2 — Quick Wins

**7. Tournament K-factor for Elo import**
- Our `import_elo.py` doesn't distinguish friendly vs WC matches. Different
  information content per match type. Even without full walk-forward, adding
  K-factor weighting to the import step would improve rating quality.

**8. Round-variance scaling in Monte Carlo**
- What: Increase simulated variance as tournament progresses. Group stage is
  more predictable; finals are near coin-flips.
- javierruanohdez uses: group=18, R32=30, QF=55, SF=70, Final=85 (Elo noise).
- Effort: ~1 hour. One dict parameter per stage.

### P3 — Longer Term / Higher Effort

**9. xG-based team form** (replace raw goals)
- xG reduces finishing luck. But international xG data is sparse (FBref/
  StatsBomb coverage limited for non-elite international teams).
- Expected improvement is real but may be small due to data sparsity.

**10. Alternative calibration: Platt scaling / Beta calibration**
- Isotonic may overfit on small samples. Platt (sigmoid) and Beta calibration
  have fewer parameters, may generalize better.
- Note: our `post-p1-improvement-attempts.md` documented isotonic failing
  due to sample size. Platt/Beta were not tried.

**11. Player-level features (market values, plus-minus ratings)**
- Transfermarkt squad values aggregated per team. Captures squad depth and
  injury impact that team-level Elo misses.
- Source: Leitner et al. (2010).

**12. Colley Matrix / PageRank alternative ratings**
- Low correlation with Elo → useful as ensemble diversifier.
- Minimal individual improvement but adds model diversity.

**13. Travel distance / rest days features**
- WC 2026 spans USA/Mexico/Canada — significant travel. May affect late-
  tournament fatigue.

## Recommended Implementation Order

1. **~~RPS + ECE~~** ✅ DONE (2026-06-23)
2. **~~Walk-forward Elo~~** ✅ DONE (2026-06-23)
3. **~~Optuna~~** ✅ DONE — 75 trials × 5-fold walk-forward CV, test_ll 0.7486
4. **~~Penalty shootout~~** ✅ DONE — stochastic Elo-shrunk draw resolution
5. **~~Neutral-venue correction~~** ✅ DONE (2026-06-25) — see `references/neutral-venue-implementation.md`
6. **~~Negative Binomial goal model~~** ✅ DONE (2026-06-25) — dispersion parameter in model.py
7. **~~Multi-objective ensemble~~** ✅ DONE (2026-06-26) — negative result
8. **Daily retrain + prediction freeze** (CupCast pattern) — engineering value

## 2026-06-25 Second-Pass Competitive Analysis

Re-ran competitive analysis after Optuna calibration improvements (test_ll
0.7625→0.7486, RPS 0.130, ECE 1.9%). Key new findings:

### Updated project landscape

| Project | Stars | Method | Our edge |
|---------|-------|--------|----------|
| Hicruben/world-cup-2026 | 66⭐ | Elo+DC+MC, JS | RPS 0.175 vs our 0.130 — we're better |
| CupCast 2026 (dev.to) | — | XGBoost + Optuna, daily retrain | Prediction freezing = auditability we lack |
| opisthokonta/goalmodel | — | R package: Poisson/NegBinom/CMP/DC | **Multi-distribution support we don't have** |
| penaltyblog (Python) | — | DC + implied prob/goals | Production Python pkg, similar coverage |
| TowardsDataScience 11-model | — | Elo/Colley/PageRank + XGBoost/NN | Multi-model ensemble: different champions |
| Frontiers 2026 (academic) | — | Bayesian outcome-specific ensemble | Per-outcome hierarchical sub-models |

### Three new optimization targets (by ROI)

**A. ~~Neutral-venue home_advantage correction~~ — ✅ DONE (2026-06-25)**
- Implemented `neutral_venue` parameter on `estimate_match_probabilities()`.
- When `neutral_venue=True`, zeroes out `home_advantage_elo` entirely (not
  shrunk — the calibrated value is inflated by qualifiers so any residual
  is already captured in Elo ratings).
- Auto-detection: WC tournament code → neutral; WQ/F → normal home/away.
- `MatchScheduleItem` gains `neutral_venue` field (auto-detected from
  tournament, overridable in schedule.json per-match).
- Calibration `_match_probabilities()` applies neutral for WC matches, so
  re-running Optuna now correctly accounts for the venue effect.
- Knockout stage matches always use `neutral_venue=True`.
- CLI gains `--neutral-venue` flag.
- 4 new tests, all 127 pass.
- **Impact:** USA(1780) vs Mexico(1720) home win dropped from 58.5% to 38.4%
  — the +20.1% phantom home edge is eliminated.
- **Lesson:** This was NOT a pure config change as initially predicted. It
  required touching model.py, reports.py, calibration.py, cli.py, and
  report_cli.py. See `references/neutral-venue-implementation.md` for the
  full implementation pattern.

**B. ~~Negative Binomial goal model~~ — ✅ DONE (2026-06-25)**
- Implemented `_negbinom_probability()` in `model.py` using Gamma-Poisson
  mixture form: `r = 1/dispersion`, `mu = goal_rate`.
- `dispersion` parameter (0.0=Poisson, >0=NegBinom) threaded through
  entire stack: `model.py` → `ModelConfig` → `CalibrationParams` →
  Optuna search space [0.0, 1.0] → all prediction call sites.
- Log-space computation (`lgamma`, `log`) for numerical stability.
- **Numerical pitfall:** For dispersion < 1e-6, `(r/(r+mu))^r` underflows
  to 0. Falls back to Poisson at dispersion < 1e-6 to avoid this.
- 5 new tests: Poisson equivalence at dispersion=0, dispersion changes
  probabilities, draw-vs-decisive shift, validity across dispersion/Elo
  combinations. All 131 tests pass.
- **Key insight:** Higher dispersion shifts mass from draws into decisive
  results (fatter tails = more extreme scorelines). This is the OPPOSITE
  of the initial intuition that "more variance = more draws".

**C. ~~Multi-objective ensemble~~ — ✅ DONE (2026-06-26), NEGATIVE RESULT**
- Ran 3× Optuna (log_loss/RPS/Brier, 75 trials each) and equal-weight averaged.
- Ensemble test_ll=0.7702 vs single-model test_ll=0.7666 — ensemble is worse.
- Root cause: same-architecture hyperparameter diversity provides no genuine
  model diversity. CV→test generalization gap means all three members overfit.
- **Lesson:** if ensemble is revisited, must be multi-architecture (Colley/
  PageRank + Elo) to create uncorrelated errors.
- See `references/ensemble-multi-objective-experiment.md` for full data.

**F. ~~Bivariate Poisson~~ — ✅ DONE (2026-06-27), NEGATIVE RESULT**
- Implemented full Bivariate Poisson (`bivariate_poisson.py`): shared
  component λ₁₂ introduces goal-scoring covariance across ALL scorelines,
  not just 4 low-score cells like Dixon-Coles.
- Grid-searched λ₁₂ ∈ [0..0.20] on same train set (2022-2026 WC/WQ/F).
- BivarP test_ll=0.7983 vs current model test_ll=0.7740 — BivarP loses by
  +0.0243 log_loss. Also worse on RPS (+0.0014) and Brier (+0.0073).
- **Root cause:** BivarP uses Poisson marginals, which lack the NegBinom
  overdispersion (dispersion=0.0999) that is the dominant improvement lever.
  DC rho=-0.247 already corrects the critical low-score cells. BivarP's
  full-matrix correlation doesn't add value beyond DC's 4-cell correction.
  λ₁₂ hit grid max (0.20) but couldn't go higher due to rate positivity
  constraints.
- **Conclusion:** Same architecture ceiling as ensemble experiment. The
  current single model (Elo + NegBinom + DC + Optuna) is at its ceiling.
  Future improvements need different architectures or additional features.
- Code kept in `bivariate_poisson.py` for reference; not wired into production.
- See `docs/bivariate-poisson-experiment.md` for full data.

### Engineering improvements

**D. Daily retrain + prediction freeze (CupCast pattern)**
- CupCast re-fits on fresh data every morning and records predictions in an
  append-only log that cannot be edited after kickoff.
- Our paper SQLite records snapshots but has no time-lock / immutability
  guarantee. Adding append-only prediction freezing makes backtest results
  uncontested.

**E. RPS as Optuna objective**
- Current objective is log-loss. RPS respects home>draw>away ordering and is
  more relevant for betting edge. `calibration.py` already has RPS — just
  switch `--optuna-objective rps` and re-run.

## 2026-06-27 Third-Pass: External Model Research + Internal Audit

Two parallel subagents: (1) external research across GitHub/academic/Kaggle,
(2) internal code+data audit. Findings condensed into `wc-polymarket-optimization`
skill (data-science category). Key new findings beyond second-pass:

### Already implemented (not previously documented in this roadmap)
- Training data is actually 2,327 matches (not 137 as some session summaries claimed)
- Time-decay xi=0.013 already in production (Optuna-optimized)
- Dixon-Coles rho=-0.247 (not -0.3 as earlier grid search found)
- Bootstrap CI pipeline fully operational with precomputed params

### New optimization opportunities identified (ranked)

**Completed this session:**
- **Venue altitude/climate** → `venue.py`, 16 venues, altitude penalty on attack.
  See `references/venue-and-market-signals.md`.
- **Market signals dynamic weight** → `market_signals.py`, volume/spread/liquidity
  → model_weight. See `references/venue-and-market-signals.md`.

**Remaining future targets:**
1. **Betting odds as features** — Pinnacle closing odds are strongest public
   predictor. football-data.co.uk for leagues; international odds scarce.
2. **Player-level data** — Transfermarkt market values, EA FC ratings. Paper
   "From Players to Champions" (arxiv 2505.01902, 2025) shows player-level
   features outperform team-level for WC prediction.
3. **xG-based form** — FBref free xG. Replaces raw goals in form calculation.
   Sparse for international matches.
4. **Pi-Rating** — Dynamic rating by surprise factor. 2023 Soccer Prediction
   Challenge top-16 used CatBoost + Pi-Rating (RPS 0.2195).
5. **Bayesian hierarchical** — PyMC/Stan partial pooling for small samples.
6. **Sarmanov family DC extension** — Generalizes DC beyond 4 low-score cells.
   Low expected value given DC rho is already effective.

### Adversary review findings on venue/market implementation
- Costa Rica altitude acclimatisation was incorrect (San José 1170m < 1200m
  threshold) → removed.
- Altitude only adjusts attack, not defense — deliberate simplification.
- Market signal thresholds are step functions, not smooth — creates
  discontinuities at boundaries.
- Per-outcome volume used instead of per-match total — thresholds may need
  recalibration against actual Polymarket WC data.
- Dynamic weight only activates at default model_weight=1.0.

## Relationship to Post-P1 Findings

The `post-p1-improvement-attempts.md` documented that ensemble, time-decay,
and isotonic all failed **within the existing Elo+DC framework** under grid
search. Optuna later disproved the time-decay conclusion (xi=0.019, 10× grid
max). The remaining ceiling is structural: NegBinom, multi-architecture
ensemble, and neutral-venue correction are the three paths most likely to
yield further improvement.
