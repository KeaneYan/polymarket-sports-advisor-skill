# Paper-Trading SQLite Notes

Session learning from extending a read-only Polymarket sports advisor with paper-trading persistence.

## Scope

Use a SQLite paper-trading store before any real wallet/order placement. It should persist each recommendation snapshot with enough data to later evaluate whether the model and market-price logic were actually useful.

## Minimum Snapshot Fields

- Match identity: title, slug, home team, away team.
- Sources: probability/model source and price source (`gamma_outcome_prices` vs `clob_orderbook`).
- Full 1X2 model probabilities, not only the BUY leg.
- Per-outcome recommendation rows: action, model probability, buy price, edge, EV-per-dollar, stake fraction, reason, token/condition/market IDs.
- Settlement: actual outcome and settled timestamp.

## Metrics

- Paper profit for BUY rows only:
  - Win: `stake_fraction * (1 / buy_price - 1)`.
  - Loss: `-stake_fraction`.
- Brier/log loss should evaluate all settled outcome rows, including WATCH/SKIP, to measure full model calibration rather than only bet selection.
- Be precise with wording: cumulative bankroll-fraction profit is `paper_profit`; ROI is profit divided by amount staked/invested and should be calculated separately if claimed.

## Integrity Pitfalls

- Do not silently settle a missing snapshot. Check existence and fail loudly.
- Do not allow double settlement to overwrite `actual_outcome` or `settled_at` unless an explicit correction workflow exists.
- A CLI message like `Settled snapshot #999` must only print after verifying a row was actually updated.
- For CLI smoke tests, use a temp DB path such as `/tmp/worldcup-paper.sqlite` to avoid polluting real paper logs.

## Recommended CLI Shape

- `--record-db PATH`: save the current recommendation snapshot.
- `--settle-db PATH --snapshot-id ID --actual-outcome home|draw|away`: settle exactly one snapshot.
- `--summary-db PATH --json`: print paper-trading metrics for settled rows.
