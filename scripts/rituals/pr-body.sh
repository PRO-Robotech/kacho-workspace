#!/usr/bin/env bash
# pr-body.sh — вход ритуала «pr-body»; логика, исходы и обёртка трекера (RITUAL_GH) — в rituals.py рядом.
set -uo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/rituals.py" pr-body "$@"
