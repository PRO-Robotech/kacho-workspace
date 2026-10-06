#!/usr/bin/env bash
# vault-trails.sh — вход ритуала «vault-trails»; логика, исходы и обёртка трекера (RITUAL_GH) — в rituals.py рядом.
set -uo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/rituals.py" vault-trails "$@"
