# Polymarket Sports Advisor Skill

A Hermes Agent skill for building and operating **read-only Polymarket sports advisor tools**. The runnable World Cup CLI lives in [`KeaneYan/worldcup-polymarket-advisor`](https://github.com/KeaneYan/worldcup-polymarket-advisor); this repository is the agent workflow/skill layer around it.

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

## Install Skill

```bash
hermes skills tap add KeaneYan/polymarket-sports-advisor-skill
hermes skills install polymarket-sports-advisor-development
```

## Install Runnable Tool

**macOS / Linux:**

```bash
# From this skill repo checkout
bash polymarket-sports-advisor-development/scripts/install_worldcup_advisor.sh

# Or manually
git clone https://github.com/KeaneYan/worldcup-polymarket-advisor.git
cd worldcup-polymarket-advisor
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e .
python -m pytest -q
```

After install, use `wc-poly-advisor` for one-match analysis and `wc-poly-report` for schedule-driven scanner/CLV/backtest reports.
