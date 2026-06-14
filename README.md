# Polymarket Sports Advisor Skill

A Hermes Agent skill for building **read-only Polymarket sports advisor tools**: match mapping, model probabilities, CLOB pricing, paper trading, CLV tracking, model calibration, team-form adjustments, injury/lineup notes, Monte Carlo simulation, and scheduled reporting.

## What It Builds

- Maps a match to Polymarket 1X2-style binary markets: home win, draw, away win.
- Estimates model probabilities with Elo + Poisson / Dixon-Coles.
- Supports data-derived team-form multipliers and manual injury/lineup adjustments.
- Compares model probability against actionable CLOB buy prices.
- Shows both value and risk: edge, model loss probability, risk bucket, spread, liquidity, and capped paper stake.
- Produces beginner-friendly scanner reports for the next 24 hours, sorted by kickoff time with Beijing kickoff timestamps.
- Records paper-trading snapshots, CLV, settlement, and market-level backtests before any real-money flow.

## Safety Boundaries

- Read-only first: no private keys, wallet config, or order placement.
- Treat output as paper-trading recommendations, not financial advice.
- High edge is not low risk; low loss probability is not automatically good value.
- Use paper ROI, Brier/log loss, CLV, and settled-market backtests before considering real orders.

## Install

```bash
hermes skills tap add KeaneYan/polymarket-sports-advisor-skill
hermes skills install polymarket-sports-advisor-development
```

Or inspect with the cross-agent Skills CLI:

```bash
npx --yes skills add KeaneYan/polymarket-sports-advisor-skill --list
```
