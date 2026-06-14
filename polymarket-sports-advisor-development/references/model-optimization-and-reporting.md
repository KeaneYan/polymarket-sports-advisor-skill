# Model Optimization and Report UX Notes

Use this reference when extending a read-only Polymarket sports advisor beyond a simple Elo/Poisson baseline.

## Model Layers

Keep the model explainable and layered rather than turning it into an opaque feature pile:

1. **Base strength**: Elo ratings feed expected goals.
2. **Team form**: derive `attack_multiplier` and `defense_multiplier` from recent historical goals for/against relative to the global average. Clamp outputs and require a minimum match count. In this codebase lower `defense_multiplier` means stronger defense.
3. **Manual context**: apply injury, lineup, travel, motivation, or tactical adjustments after team form. Keep notes auditable and show them in reports.
4. **Score model**: use Poisson with optional Dixon-Coles `rho` for low-score dependence. Keep `rho=0.0` as the independent-Poisson fallback.
5. **Market comparison**: compute `edge = model_probability - market_buy_price`; optional market shrinkage uses `final_prob = model_weight * model_prob + (1 - model_weight) * market_buy_price`.
6. **Simulation**: Monte Carlo can summarize selected known matches, but do not call it full bracket/champion odds unless knockout fixtures and advancement logic are actually implemented.

## P1 Split Pitfall

When asked for P1 model improvements, treat it as two separate deliverables:

- data-derived attack/defense form multipliers (`team_form`)
- manual injury/lineup/context adjustments (`team_adjustments`)

Doing only one is incomplete.

## Scanner Report UX

For beginner-friendly match scanner reports:

- Default report window should be the next 24 hours unless the user asks otherwise.
- Sort cards by kickoff time from soonest to latest; do not reorder by BUY/edge because it breaks the match-day timeline.
- Show kickoff time in the user's expected timezone; for this World Cup workflow use Beijing time.
- Report every scheduled match in the window, including `NO MARKET` rows.
- Each priced card should show full home/draw/away model probabilities plus the selected headline recommendation.
- Keep scheduled delivery change-only if needed, but manual previews should remain complete.

## Verification Checklist

- Add report tests for time-zone formatting and kickoff sorting.
- Run full tests after changing model/report code.
- Run at least one scanner smoke with fixed `--now` and inspect the first cards for title, Beijing kickoff time, and chronological ordering.
- If a cron wrapper calls the scanner, update its `--hours` argument and run `bash -n` on the wrapper.