#!/bin/sh
# Launches the desktop configurator using the local venv (see README.md).
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
    echo "Setting up venv (first run)…"
    python3 -m venv .venv
    ./.venv/bin/pip install --quiet -r requirements.txt
fi
exec ./.venv/bin/python app.py
