#!/usr/bin/env bash
# approval-event.sh — вход ритуала «approval-event»; логика, исходы и обёртка трекера (RITUAL_GH) — в rituals.py рядом.
set -uo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/rituals.py" approval-event "$@"
