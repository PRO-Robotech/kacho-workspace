#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Прогон набора cla-gate — ведомость соглашения о вкладе воркспейса и суждение по
# ней. Три исхода: 0 — исполнено N, находок 0; 1 — находка либо пустой обход;
# 2 — без предмета. Находка объявляется первой: беспредметная проверка рядом с
# находкой её не маскирует.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ok=0; bad=0; void=0; ran=0
for check in "$here"/check-*.sh; do
    [ -f "$check" ] || continue
    ran=$((ran + 1))
    bash "$check" </dev/null
    case $? in
        0) ok=$((ok + 1)) ;;
        2) void=$((void + 1)) ;;
        *) bad=$((bad + 1)) ;;
    esac
done
if [ "$ran" -eq 0 ]; then
    echo "[FAIL] cla-gate — ни одной проверки не найдено в $here" >&2
    exit 1
fi
echo "cla-gate: рассмотрено проверок $ran; пройдено $ok, провалено $bad, без предмета $void"
[ "$bad" -gt 0 ] && { echo "[FAIL] cla-gate — набор красный: находок $bad" >&2; exit 1; }
[ "$void" -gt 0 ] && { echo "[VOID] cla-gate — без предмета $void из $ran" >&2; exit 2; }
echo "[PASS] cla-gate — исполнено $ran, все зелёные"
