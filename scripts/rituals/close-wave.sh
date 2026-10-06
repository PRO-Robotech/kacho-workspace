#!/usr/bin/env bash
# close-wave.sh — вход ритуала «close-wave»; логика, исходы и обёртка трекера (RITUAL_GH) — в rituals.py рядом.
set -uo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/rituals.py" close-wave "$@"
