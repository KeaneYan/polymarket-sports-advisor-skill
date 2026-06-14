# World Cup Auto Settlement

Use this reference when extending the read-only World Cup Polymarket advisor from paper snapshots to automated paper settlement.

## Goal

Close the paper-trading loop without touching private keys or placing orders:

`scan markets -> record BUY snapshots -> record CLV -> infer resolved outcome -> settle snapshot -> report Brier/log loss/paper_profit`

## Preferred Settlement Source

Prefer Polymarket's own market-resolution prices before adding a third-party sports-results feed.

Why:
- Paper accounting should match the market's actual resolution, not only the sporting result.
- It avoids team-name and competition-round mismatches from external APIs.
- It naturally handles void/cancelled/ambiguous cases by refusing to settle until prices are decisive.

Tradeoff:
- Settlement may lag until Polymarket/Gamma exposes decisive resolved prices.
- Search failures or event mismatch should skip rather than force a result.

## Conservative Inference Rule

For a 1X2 match split across three binary markets (`home`, `draw`, `away`):

1. Extract all three outcome quotes from the matched Gamma event.
2. Require all three outcomes to be present.
3. Infer an outcome only when exactly one Yes price is near 1 and at least two are near 0.
4. Suggested thresholds: winner `>= 0.99`, losers `<= 0.01`.
5. If unresolved, missing, or ambiguous, return `None` and do not settle.

Wrong settlement is worse than delayed settlement.

## Storage Pattern

Add a store method like `list_unsettled_snapshots()` returning only snapshots where `actual_outcome IS NULL`.

Settlement writes should reuse the existing `settle_snapshot(snapshot_id, actual_outcome=...)` path so double-settlement checks remain centralized.

## CLI/Cron Pattern

Make `report_cli --mode settlement` do two things in order:

1. Attempt automatic settlement for all unsettled snapshots.
2. Print performance summary and CLV summary.

This lets the existing post-match cron keep the same schedule and wrapper while upgrading behavior.

Cron should not be rebuilt if it already runs the same script/mode; updating the script logic is enough.

## Verification

Minimum tests:
- Inference returns `home/draw/away` only for decisive 1/0/0-like prices.
- Inference returns `None` for normal trading prices and ambiguous multi-winner prices.
- Store lists unsettled snapshots and excludes them after settlement.
- Full suite passes.

Minimum smoke:
- Record a future unresolved market into a temporary paper DB.
- Run `--mode settlement` against that DB.
- Verify `本次自动结算：0`; this proves unresolved markets are not falsely settled.
