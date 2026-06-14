# World Cup Schedule Imports and Cron Reports

## Durable pattern

- Keep scheduled reports reading from a local `data/schedule.json`; do not make cron depend directly on FIFA pages or third-party APIs at run time.
- Use an importer CLI to refresh `data/schedule.json` from an open fixture source, then verify the generated file before scheduled jobs consume it.
- For 2026 World Cup data, openfootball's `worldcup.json` raw GitHub file is a usable source for concrete fixtures; some commercial/free fixture pages may return HTTP 403 to direct scripts even when their marketing page says JSON/CSV is free.
- Parse and skip knockout placeholders until real teams are known. Common placeholder forms include `1A`, `2B`, `3C/D/F/G/H`, `W73`, `L101`, `Winner Group A`, and `Runner-up Group B`.
- Merge fixtures with a local `team_elo.json` seed table, but label it as a seed/model input, not live or official Elo. Fail on missing Elo rather than silently defaulting.

## Cron report implementation

- Prefer `no_agent=True` cron jobs for deterministic report scripts whose stdout is already the exact WeChat body.
- Put cron scripts under `~/.hermes/scripts/` and make them thin wrappers that `cd` into the project and run the module entry point with `PYTHONPATH=src`.
- Keep reports short enough for message-body delivery; avoid attachments for this user's scheduled reports.
- Three useful jobs for sports advisors:
  - Daily overview: upcoming concrete fixtures and high-level state.
  - Match-window scanner: future window scan with real CLOB prices and paper-recording enabled.
  - Postmatch settlement: paper-trading summary/settlement status.

## Verification checklist

- Run focused importer tests for timezone normalization, placeholder skipping, alias normalization, and missing Elo failures.
- Run full test suite after touching report/import code.
- Verify generated schedule count and first/last fixtures.
- Run a short current-window scanner smoke to ensure no crash.
- Run a fixed future-time scanner smoke to prove BUY/WATCH formatting and CLOB lookup still work.
- Confirm existing cron jobs remain enabled and read the refreshed local schedule; do not rebuild cron unless script names/schedules changed.
