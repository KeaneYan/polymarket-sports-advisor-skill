# World Cup Polymarket CLV Tracking

Use this pattern after paper snapshot recording exists and before considering any real-money workflow.

## Purpose

CLV (closing line value) checks whether a BUY recommendation moved in the same direction as the market before kickoff. It is not profit and does not prove the model is correct, but it is a useful early filter for fake edges.

Definition used in the advisor:

```text
CLV = closing_buy_price - entry_buy_price
```

Positive CLV means the Yes price rose after the recommendation. Negative CLV means the market moved against the recommendation.

## Storage Pattern

Add a separate table rather than mutating recommendations:

```sql
CREATE TABLE IF NOT EXISTS closing_prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  snapshot_id INTEGER NOT NULL REFERENCES snapshots(id),
  outcome TEXT NOT NULL,
  closing_buy_price REAL NOT NULL,
  captured_at TEXT NOT NULL,
  UNIQUE(snapshot_id, outcome)
);
```

Use an upsert on `(snapshot_id, outcome)` so repeated pre-match captures update the latest closing price instead of double-counting.

Only track BUY rows with a valid CLOB `token_id`. Skip rows without token IDs rather than trying to rediscover the market from text.

## CLI Pattern

Add a report mode like:

```bash
PYTHONPATH=src python3 -m worldcup_poly_advisor.report_cli --mode closing
```

Implementation steps:

1. Query open, unsettled BUY recommendations with token IDs.
2. Fetch CLOB orderbooks by token ID.
3. Compute actionable buy price with the same target-share logic used at entry time.
4. Upsert closing prices by snapshot/outcome.
5. Report `tracked_buy_count`, `average_clv`, `positive_clv_count`, and stake-weighted CLV if available.

## Report Wording

Always include the caveat:

```text
CLV 为正只说明买入后盘口朝我们方向走，不等于最终盈利。
```

Avoid saying CLV proves the model is profitable. Use CLV as a diagnostic gate before paper ROI or real-money steps.

## Cron Pattern

For no-agent cron jobs, make the wrapper silent when nothing is actionable:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /path/to/project
output="$(PYTHONPATH=src python3 -m worldcup_poly_advisor.report_cli --mode closing)"
if ! grep -q "累计 BUY 跟踪：0" <<<"$output"; then
  printf '%s\n' "$output"
fi
```

Empty stdout means no delivery, which is preferable to sending daily zero-value reports.

## Verification

- Unit test snapshot -> closing price -> CLV summary.
- Test missing snapshot rejection.
- Test open BUY listing filters only unsettled BUY rows with token IDs.
- Run full test suite.
- Smoke with a temp DB: scanner `--record`, then closing mode, and confirm it updates at least one closing price when BUY rows exist.
