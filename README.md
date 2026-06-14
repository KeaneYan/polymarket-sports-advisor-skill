# Polymarket Sports Advisor Skill

A Hermes Agent skill for building **read-only Polymarket sports advisor tools**: match mapping, model probabilities, CLOB pricing, paper trading, CLV tracking, model calibration, team-form adjustments, injury/lineup notes, Monte Carlo simulation, and scheduled reporting.

## What It Builds

- Maps a match to Polymarket 1X2-style binary markets: home win, draw, away win.
- Estimates model probabilities with Elo + Poisson / Dixon-Coles.
- Supports data-derived team-form multipliers and manual injury/lineup adjustments.
- Compares model probability against actionable CLOB buy prices.
- Produces beginner-friendly scanner reports for the next 24 hours, sorted by kickoff time with Beijing kickoff timestamps.
- Records paper-trading snapshots, CLV, settlement, and market-level backtests before any real-money flow.

## Prediction Model

The model is deliberately explainable rather than a black box:

1. **Team strength from Elo** — converts team Elo ratings into expected scoring strength.
2. **Team form layer** — optional `attack_multiplier` / `defense_multiplier` from recent historical goals for/against; lower defense multiplier means stronger defense.
3. **Manual context layer** — optional injury, lineup, travel, motivation, or tactical notes can adjust Elo/attack/defense explicitly.
4. **Poisson score distribution** — enumerates scorelines and aggregates them into home/draw/away probabilities.
5. **Dixon-Coles correction** — optional `dixon_coles_rho` adjusts low-score dependence such as 0-0, 1-0, 0-1, and 1-1.
6. **Market comparison** — `edge = model_probability - buy_price`; optional market shrinkage can blend model probability toward market price.

The model does **not** magically know late injury news or confirmed lineups unless those inputs are supplied. Large edge can still be model error.

## Report Philosophy

Scanner reports should cover every scheduled match in the report window, not only BUY opportunities. Each card should show:

- kickoff time in Beijing time
- recommendation: BUY / WATCH / SKIP / NO MARKET
- translated outcome: home win / draw / away win
- model home-draw-away probabilities
- market buy price, edge, spread, liquidity, and paper stake
- adjustment notes when team form or injury/lineup inputs affected the model

Manual previews can be complete; scheduled delivery can remain change-only to avoid notification spam.

## Safety Boundaries

- Read-only first: no private keys, wallet config, or order placement.
- Treat output as paper-trading recommendations, not financial advice.
- Use paper ROI, Brier/log loss, CLV, and settled-market backtests before considering real orders.
- Flag bankroll loss, liquidity, slippage, market resolution, and jurisdiction risks.

## Install

```bash
hermes skills tap add KeaneYan/polymarket-sports-advisor-skill
hermes skills install polymarket-sports-advisor-development
```

Or inspect with the cross-agent Skills CLI:

```bash
npx --yes skills add KeaneYan/polymarket-sports-advisor-skill --list
```
