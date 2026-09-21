#!/usr/bin/env bash
# check-10 — АДРЕС ПРАВИЛА И СКИЛА-ПРИВЯЗКИ РЕЗОЛВИТСЯ ТАМ, ГДЕ ОН НАПИСАН.
#
# Существо, разборщик и объявленный долг — в соседних файлах: `rule-address-refs.py`
# (шапка объясняет, чем это отличается от check-07 и почему одного не хватило) и
# `rule-address-baseline.txt` (откуда взялся остаток и какой исход у каждого имени).
#
# Корень и база переопределяются средой: инъекция гоняет проверку на КОПИИ дерева,
# и без обоих швов ось «запись базы пережила свой предмет» была бы недоказуема.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${RULES_GATE_ROOT:-$(git rev-parse --show-toplevel)}"
exec python3 "$SELF_DIR/rule-address-refs.py" \
    --root "$root" \
    --baseline "${RULES_GATE_RULE_ADDRESS_BASELINE:-$SELF_DIR/rule-address-baseline.txt}"
