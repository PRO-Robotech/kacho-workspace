#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-01 — каждый вклад в судимой истории воркспейса подтверждён ведомостью
# `contribution-ledger.yaml`, и у каждой записи-послабления есть предмет (ws#731).
#
# Суждение целиком в `cla.py tree` — здесь только вызов на ЭТОМ дереве: второй
# реализации суждения рядом с первой не заводится. Исходы проходят насквозь:
# 0 — подтверждено, объём напечатан; 1 — находка либо негодная ведомость;
# 2 — условие не создано (история не несёт границы — срез глубины).
set -uo pipefail
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v python3 >/dev/null || { echo "[VOID] check-01-ledger-covers-the-judged-history — python3 не найден" >&2; exit 2; }
python3 "$WS/scripts/cla-gate/cla.py" tree --root "$WS"
