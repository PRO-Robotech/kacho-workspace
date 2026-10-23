#!/usr/bin/env bash
# Архивная проба запускается штатным внешним маршрутом workspace.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -I "$HERE/operator-archive-inject.py"
