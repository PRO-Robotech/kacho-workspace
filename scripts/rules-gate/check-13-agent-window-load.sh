#!/usr/bin/env bash
# check-13 — СКОЛЬКО ТЕКСТА ПРИХОДИТ В ОКНО ОДНОМУ АГЕНТУ.
# Предмет, довод и обе формы нуля — в шапке разборщика рядом.
#
# ПОРОГ НЕ ЗАШИТ: он включается средой `RULES_GATE_AGENT_WINDOW_MAX`. Пока он не
# назначен, проверка считает и печатает, но не блокирует — число, притворяющееся
# выведенным, дороже честно отсутствующего.
#
# Корень — из `RULES_GATE_ROOT` либо из git: инъекция гоняет на КОПИИ дерева.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${RULES_GATE_ROOT:-$(git rev-parse --show-toplevel)}"
exec python3 "$SELF_DIR/agent_window_load.py"
