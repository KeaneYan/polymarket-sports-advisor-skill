#!/usr/bin/env bash
set -euo pipefail
cd /Users/keaneyan/work/worldcup-polymarket-advisor
cron_output="$(hermes cron list --all)"
jobs=(
  wc-polymarket-daily-overview
  wc-polymarket-match-scanner
  wc-polymarket-closing-clv
  wc-polymarket-postmatch-settlement
  wc-polymarket-market-backtest
  wc-polymarket-elo-updater
  wc-polymarket-xg-updater
  wc-polymarket-cron-health
)

issues=()

for job in "${jobs[@]}"; do
  block="$(awk -v name="$job" '
    $0 ~ "Name:[[:space:]]+" name {capture=1}
    capture {print; if (++count >= 10) exit}
  ' <<<"$cron_output")"

  if [[ -z "$block" ]]; then
    issues+=("- $job: ❌ MISSING")
    continue
  fi

  # Check status (active vs paused/disabled)
  if grep -q '\[paused\]\|\[disabled\]' <<<"$block"; then
    issues+=("- $job: ⏸ NOT ACTIVE")
    continue
  fi

  # Check last run status
  last_line="$(grep 'Last run:' <<<"$block" | sed 's/^[[:space:]]*//' || true)"
  if [[ -n "$last_line" ]]; then
    # Extract status word after the timestamp
    if echo "$last_line" | grep -q 'error\|failed\|timeout'; then
      issues+=("- $job: ⚠️ $last_line")
    fi
  fi
done

# If any issues found, print alert header + issues + backtest summary
if [[ ${#issues[@]} -gt 0 ]]; then
  printf '🚨 **世界杯管道异常 (%s)**\n\n' "$(date '+%m-%d %H:%M')"
  for line in "${issues[@]}"; do
    printf '%s\n' "$line"
  done
  # Include backtest only when there are issues
  backtest="$(PYTHONPATH=src python3 -m worldcup_poly_advisor.report_cli --mode backtest 2>&1 || echo 'backtest: unavailable')"
  printf '\n%s\n' "$backtest"
fi
# If no issues, output nothing (silent = healthy)
