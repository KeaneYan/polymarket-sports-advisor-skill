#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${WCPOLY_REPO_URL:-https://github.com/KeaneYan/worldcup-polymarket-advisor.git}"
INSTALL_DIR="${WCPOLY_INSTALL_DIR:-$HOME/worldcup-polymarket-advisor}"
PYTHON_BIN="${PYTHON:-python3}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "$PYTHON_BIN is required" >&2
  exit 1
fi

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Updating $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only
else
  if [ -e "$INSTALL_DIR" ]; then
    echo "$INSTALL_DIR exists but is not a git checkout" >&2
    exit 1
  fi
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
"$PYTHON_BIN" -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e .
python -m pytest -q

cat <<MSG

Installed World Cup Polymarket Advisor at:
  $INSTALL_DIR

Try:
  cd "$INSTALL_DIR"
  . .venv/bin/activate
  cp data/schedule.example.json data/schedule.json
  wc-poly-report --mode scanner --hours 24
MSG
