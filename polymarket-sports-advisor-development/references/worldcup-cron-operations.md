# World Cup Polymarket Cron Operations

Use this reference when operationalizing a read-only Polymarket sports advisor with scheduled jobs jobs.

## Cron Pattern

Prefer script-only `no_agent=True` cron jobs for deterministic reports:

- `scanner`: runs frequently, records BUY snapshots to the paper DB.
- `closing`: captures CLV; fixed-time daily capture is a baseline, but kickoff-relative capture is better.
- `settlement`: runs after matches, attempts conservative auto-settlement from Polymarket resolved prices.
- `market-backtest`: runs after settlement and reports BUY totals, CLV, settled P&L, staked fraction, and ROI.
- `overview`: human-readable summary of upcoming matches and paper-trading state.

Use `deliver=origin` when the report should return to the current conversation. Keep outputs short enough to arrive as message text, not attachments.

## Verification Sequence

After creating or changing a job:

1. Run the underlying script locally from the project workdir.
2. Create/update the cron job with `enabled_toolsets=["terminal"]`, `no_agent=True`, and the project `workdir`.
3. Trigger it once with `cronjob(action="run", job_id=...)`.
4. List jobs and verify `last_status=ok`, `last_delivery_error=null`, and a sensible `next_run_at`.

`cronjob(action="run")` schedules execution on the next scheduler tick; it may not be synchronous. Wait briefly and list jobs again before claiming it ran.

## Data-Quality Priorities

Once the baseline cron pipeline is running, improve data quality before adding model complexity:

- Capture CLV relative to each match kickoff, ideally 30–90 minutes before start, not just one fixed daily time.
- Deduplicate scanner records so the same match/outcome is not recorded every scan unless edge or market quality changes materially.
- Alert only on changes: new BUY, BUY disappearing, edge moving by more than a threshold, spread/liquidity worsening.
- Add a cron health report that checks scanner/CLV/settlement/backtest last-run status and paper DB deltas.

## Pitfalls

- A market-level report with `settled=0` is not breakeven; it is insufficient evidence.
- CLV and ROI use different sample sets: open BUY rows can count toward CLV if closing prices exist, but only settled BUY rows should count toward P&L/ROI.
- Fixed-time CLV capture can miss the true closing line when matches start at different local times.
