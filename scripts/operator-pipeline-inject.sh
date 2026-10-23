#!/usr/bin/env bash
# Проверка native pipeline на сохранённых настоящих результатах.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -I scripts/operator-pipeline-inject.py
