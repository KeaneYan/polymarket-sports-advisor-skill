# Repo + Skill Update Operations

Use this when updating the runnable World Cup Polymarket advisor together with its Hermes skill/playbook repo.

## Two Repositories, Two Purposes

- Tool repo: `KeaneYan/worldcup-polymarket-advisor` contains runnable code, tests, package metadata, CLI entry points, example data, and CI.
- Skill repo: `KeaneYan/polymarket-sports-advisor-skill` contains the Hermes workflow/playbook (`SKILL.md`, references, scripts). It should not duplicate the full tool source.
- Local installed skill path is an installation target, not necessarily a git checkout. Do not assume it can be pushed directly.

## Update Sequence

1. Identify both remotes and compare local/remote SHAs before changing anything.
2. For the tool repo, fast-forward only when the working tree is clean. If local commits exist, inspect `git rev-list --left-right --count HEAD...origin/main` and do not force-push over remote history.
3. Install the tool from its own checkout using a Python version that satisfies `pyproject.toml` (`requires-python`). Prefer a project `.venv` and editable install over system Python or PATH shims.
4. Run full tests inside the same environment used for installation, then run at least one CLI smoke command that exercises report generation.
5. For the skill repo, clone a clean copy of the remote, copy in the local installed skill changes intentionally, review `git diff`, commit only the intended skill files, push, then verify the raw GitHub content.
6. After editable installs, remove generated build artifacts such as `*.egg-info/` if they appear in the working tree.

## Verification Checklist

- Tool repo: `local_head == origin/main`, `ahead_behind=0 0`, and `git status --short` is empty after cleanup.
- Tool install: console scripts such as `wc-poly-report` resolve from the intended `.venv` and a smoke report includes expected fields.
- Skill repo: remote HEAD matches the pushed commit, raw `SKILL.md` contains the new guidance, and the installed skill still loads via `skill_view`.
- If normal HTTPS push fails because local credentials are stale, use a one-shot authenticated git push without printing secrets; do not modify global credentials just to finish one push.

## Pitfalls

- A local installed skill can be newer than its GitHub source after `skill_manage` patches. Always compare against a clean remote clone before saying local and remote are aligned.
- Updating from the remote can overwrite locally learned skill guidance. If the local patch is still valuable, push it upstream or re-apply it immediately after installation.
- Network retries and transient API SSL failures are not install failures if tests and local smoke commands pass; report them as runtime/network caveats, not broken setup.
- **"N scripts" vs "N modes of 1 CLI"**: When summarizing changes to `wc-poly-report`, do NOT say "3 cron scripts (scanner/overview/settlement)". These are 3 modes of ONE CLI entry point (`report_cli.py --mode scanner|overview|settlement`), not 3 separate scripts. The flags (`--bookmaker-odds`, `--market-values`, `--xg-data`, `--xg-form-weight`) are arguments to `report_cli.py`, not to separate scripts. This distinction matters for push confirmations and release notes.
- **"Moved" vs "Copied"**: When adding a data file to version control (e.g., `wc2026.xlsx` into `data/`), verify whether the old location (e.g., `/tmp/`) was actually cleaned up. Saying "moved from /tmp to data/" is misleading if the /tmp copy still exists — it was "copied" or "added to data/".
- **"Updated" vs "Created"**: When a data file like `schedule.json` is committed for the first time, it's a new file — not an update from a previous version. `git show START_SHA:<path>` will fail if the file didn't exist before. Don't say "from X to Y" implying incremental change when X was never in the repo.
