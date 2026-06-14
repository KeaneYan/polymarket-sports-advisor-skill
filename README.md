# Polymarket Sports Advisor Skill

A Hermes Agent skill for building **read-only Polymarket sports advisor tools**: match mapping, model probabilities, CLOB pricing, paper trading, CLV tracking, model calibration, and scheduled reports.

This is not a betting bot. It is a workflow for building and evaluating a paper-trading advisor before anyone even talks about real orders.

## What This Skill Helps Build

- Map sports fixtures to Polymarket match markets, including 1X2-style markets split into home win / draw / away win binaries.
- Estimate match outcome probabilities with a transparent Elo + Poisson model.
- Compare model probability against actionable Polymarket buy prices from Gamma/CLOB.
- Produce beginner-friendly reports that show every match, not just BUY candidates.
- Track paper trades, CLV, settlement, and market-level backtest metrics.
- Keep scheduled scanner/CLV/settlement jobs quiet unless something actually changes.

## Prediction Model

The default model is intentionally boring and explainable:

1. **Team strength from Elo**
   - Each team starts with an Elo-style rating.
   - Rating differences estimate relative strength.
   - A home-advantage parameter can be included when appropriate.

2. **Expected goals from strength**
   - Elo difference is converted into expected attacking advantage.
   - A base-goals parameter controls how high-scoring the model expects the match environment to be.

3. **Poisson score distribution**
   - The model enumerates plausible scorelines using Poisson goal distributions.
   - Scorelines are aggregated into three probabilities:
     - home win
     - draw
     - away win

4. **Market comparison**
   - Polymarket prices are treated as buy prices / implied market probabilities.
   - `edge = model_probability - buy_price`.
   - A BUY candidate only appears after liquidity, spread, and edge gates pass.

Example report line:

```text
1. Ghana vs Panama
建议：BUY
买什么：客队 Panama 赢
模型概率：主胜 Ghana 18.5% / 平局 26.3% / 客胜 Panama 55.2%
为什么：模型估 55.2%，市场买入价 28.0%，差值 +27.2%
交易质量：spread 1.0%，流动性 214537
纸面仓位：2.00%（有硬上限，先记录不真买）
```

The important part is the full probability line. Even when the report highlights one result, it should still show the model's full view of the match.

## What The Model Is Not

- It is not an oracle.
- It does not know team news, injuries, motivation, travel fatigue, lineups, or tactical context unless you explicitly add those inputs.
- A large edge can mean the market is wrong, but it can also mean your model is missing something or the market mapping is off.
- Early paper-trading samples are not proof of profitability. Use Brier score, log loss, CLV, settled paper ROI, and market-level backtests before trusting it.

## Report Philosophy

Reports should be readable by someone who has never bet on football:

- Show every scheduled match in the report window.
- Translate `home / draw / away` into plain language.
- Show model probabilities for home win / draw / away.
- Show what the market price is and why the model thinks there is or is not an edge.
- Include `NO MARKET` rows when a match cannot be matched to a usable Polymarket market.
- Keep cron notifications change-only so the user does not get spammed every hour.

## Safety Boundaries

- Read-only by default.
- No private keys.
- No wallet configuration.
- No automatic order placement.
- Paper trading first.
- Real-money flow should require explicit manual confirmation, position limits, and enough settled evidence.

## Install

```bash
hermes skills tap add KeaneYan/polymarket-sports-advisor-skill
hermes skills install polymarket-sports-advisor-development
```

Or inspect with the cross-agent Skills CLI:

```bash
npx --yes skills add KeaneYan/polymarket-sports-advisor-skill --list
```

## Included Skill

- `polymarket-sports-advisor-development` — implementation workflow for read-only Polymarket sports advisor tooling.

## References

The skill includes references for:

- SQLite paper trading schema and pitfalls
- World Cup schedule import and scheduled reports
- CLV tracking
- conservative automatic settlement
- cron-style operations
- beginner-friendly report copy

## Disclaimer

This is engineering workflow documentation, not financial advice. Prediction markets and sports betting can lose money. Treat every recommendation as a hypothesis to test, not a command to trade.
