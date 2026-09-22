#!/usr/bin/env bash
# check-10 — КООРДИНАТА ПРАВИЛА, НАПИСАННАЯ В ДЕРЕВЕ, РЕЗОЛВИТСЯ, И ЕЁ ТРОЙКА ПОЛНА.
# Предмет и признак фикстуры — в шапке разборщика рядом.
#
# РАЗБОРЩИК БЕРЁТСЯ РЯДОМ С СОБОЙ, а корень — из `RULES_GATE_ROOT` либо из git:
# инъекция гоняет проверку на КОПИИ дерева, куда `scripts/` не копируется.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${RULES_GATE_ROOT:-$(git rev-parse --show-toplevel)}"
exec python3 "$SELF_DIR/rule_coordinates.py"
