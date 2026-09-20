#!/usr/bin/env bash
# check-07 — АДРЕС НОРМЫ РЕЗОЛВИТСЯ, id УНИКАЛЕН.
# Предмет: перенос текста между файлами рвёт ссылку молча. Область ШИРЕ, чем у
# `skills-gate/check-01`: агенты, правила, `CLAUDE.md` и гейты продукта.
#
# РАЗБОРЩИК И БАЗА БЕРУТСЯ РЯДОМ С СОБОЙ, а дерево — из корня. Инъекция гоняет
# проверку на КОПИИ дерева, куда `scripts/` не копируется: путь от корня дал бы
# «нет такого файла» и код 2, а харнесс ждёт 0 на нетронутой копии.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git rev-parse --show-toplevel)"
exec python3 "$SELF_DIR/address-refs.py" --baseline "$SELF_DIR/address-baseline.txt"
