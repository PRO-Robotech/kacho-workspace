#!/usr/bin/env bash
# check-13 — СТАРТОВОЕ ОКНО АГЕНТА не выше своего потолка (ws#1084, решение владельца
# 2026-10-14). Заменяет совокупный потолок корпуса, снятый с check-06: токенами
# платится старт агента (CLAUDE.md + файл агента + skills:), а не корпус.
# Подгрузка по триггеру печатается, но не ограничивается. Потолки — ведомость
# `agent-window-budget.tsv` рядом (шов инъекции — RULES_GATE_WINDOW_BUDGET).
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 отказ по беспредметному обходу.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(python3 "$SELF_DIR/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
cd "$root" 2>/dev/null || {
    echo "[VOID] check-13-agent-window-budget — корень «$root» не открывается; обходить нечего" >&2
    exit 2
}
exec python3 "$SELF_DIR/agent_window.py" "$root"
