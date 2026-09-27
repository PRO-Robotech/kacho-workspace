#!/usr/bin/env bash
# check-06 — ОБЪЁМ И ФОРМА КОРПУСА. Потолок 200 000 символов (решение владельца
# 2026-09-19) и форма строки-нормы. Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка,
# 2 отказ по беспредметному обходу.
#
# Разборщик берётся РЯДОМ С СОБОЙ, а дерево — из корня: инъекция гоняет проверку
# на КОПИИ дерева, куда `scripts/` не копируется.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(python3 "$SELF_DIR/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
exec python3 "$SELF_DIR/corpus_ceiling.py"
