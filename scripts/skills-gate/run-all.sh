#!/usr/bin/env bash
# Прогоняет все проверки набора и выносит ОДИН вердикт из числа, а не из печати.
#
# «Проверять нечего» (код 2) НЕ засчитывается за успех и печатается отдельной
# строкой: один и тот же ноль иначе означал бы и чистое дерево, и неоткрытое
# (`gate-authoring` §Гейт заявляет предпосылку).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ok=0; bad=0; void=0
for c in "$SCRIPT_DIR"/check-*.sh; do
    bash "$c"
    case $? in
        0) ok=$((ok + 1)) ;;
        2) void=$((void + 1)) ;;
        *) bad=$((bad + 1)) ;;
    esac
done

echo
echo "skills-gate: пройдено $ok, провалено $bad, без предмета $void"
# Вердикт стоит в предикате выхода, а не в печати выше.
[ "$bad" -eq 0 ] && [ "$void" -eq 0 ]
