#!/usr/bin/env bash
# Прогон набора tooling-gate. Вердикт стоит в КОДЕ ВЫХОДА, а не в печати.
#
# Три исхода, а не два: 0 — осмотрено N, находок 0; 1 — находки, каждая названа
# координатой; 2 (VOID) — проверять нечего, предпосылка проверки не выполнена.
# VOID считается провалом набора: «ноль находок» и «ноль прочитанного» — разные
# вещи, и неразличение этих двух исходов уже держало один механизм этого репо
# невыполненным и ненаблюдаемым (см. `.claude/rules/ai-tooling.md`).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rc=0
ran=0
for check in "$here"/check-*.sh; do
    ran=$((ran + 1))
    bash "$check" || rc=1
done

if [ "$ran" -eq 0 ]; then
    echo "[VOID] run-all — ни одной проверки не найдено" >&2
    exit 2
fi

echo "[CENSUS] run-all: исполнено проверок $ran"
if [ "$rc" -ne 0 ]; then
    echo "[FAIL] run-all — набор красный" >&2
    exit 1
fi
echo "[PASS] run-all — исполнено $ran, все зелёные"
