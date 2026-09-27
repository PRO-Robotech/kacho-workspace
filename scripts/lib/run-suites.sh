#!/usr/bin/env bash
# run-suites — исполнить КАЖДЫЙ набор проверок дерева: перечень выводится, а не
# выписывается.
#
# ЗАЧЕМ. Конвейер звал наборы поимённо, и набор, заведённый в дереве, но не
# вписанный в конвейер, не исполнялся на стволе — молча (ws#753: в дереве наборов
# было больше, чем вызовов; ws#817 — у одного из них не было задания вовсе).
# Выписанный перечень — второй носитель факта «какие наборы есть», и отстаёт он в
# ту сторону, где «не выполнено» читается как «зелено». Здесь перечень выводит
# перепись `scripts/lib/suites.py` из индекса git, и второго дома у него нет. Что
# конвейер зовёт ИМЕННО вывод, а не перечень, держит
# `scripts/suites-gate/check-04-ci-calls-every-suite.py`.
#
# ИСХОД НЕ ИЗ ОДНОГО КАНАЛА. Код набора сверяется с его машинной строкой
# переписи (`SUITE_SUMMARY`, её пишет общий прогонщик): набор, вернувший код, но
# не отчитавшийся о числе рассмотренных проверок, — находка, а не зелёное.
# Расхождение «наборов в дереве × исполнено» печатается числом и краснит.
#
# ИСПОЛЬЗОВАНИЕ:
#   bash scripts/lib/run-suites.sh [--proofs] [--void-is-failure]
#     --proofs           перед прогоном набора исполнить его доказательство
#                        (`inject.sh`) — так делает конвейер;
#     --void-is-failure  «без предмета» роняет прогон: в конвейере предпосылки
#                        создаёт само задание, и их отсутствие — поломка, а не факт
#                        расписания. Локально (хук отправки) код 2 остаётся своим.
#
# Исходы: 0 — все наборы исполнены и зелены; 1 — находка у набора или его
# доказательства, либо набор не отчитался; 2 — без предмета (без --void-is-failure).
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LIB/../.." && pwd)"

proofs=0; void_fails=0
for a in "$@"; do
    case "$a" in
        --proofs) proofs=1 ;;
        --void-is-failure) void_fails=1 ;;
        *) echo "run-suites: неизвестный ключ $a" >&2; exit 2 ;;
    esac
done

if ! mapfile -t SUITES < <(python3 "$LIB/suites.py" suites "$ROOT"); then
    echo "[VOID] run-suites — перепись наборов не снята" >&2
    exit 2
fi
# `mapfile` из пустого вывода даёт массив из одной пустой строки не всегда —
# отсекаем пустые имена явно.
names=()
for s in "${SUITES[@]}"; do [ -n "$s" ] && names+=("$s"); done
if [ "${#names[@]}" -eq 0 ]; then
    echo "[FAIL] run-suites — в дереве нет ни одного scripts/*/run-all.sh: пустой обход здесь был бы зелёным при снятых проверках" >&2
    exit 1
fi

summary="$(mktemp)"
trap 'rm -f "$summary"' EXIT

red=(); voided=(); unreported=(); proof_red=(); lines=()
ran=0
for s in "${names[@]}"; do
    echo "══ $s"
    prc="—"
    if [ "$proofs" -eq 1 ]; then
        if [ -f "$ROOT/scripts/$s/inject.sh" ]; then
            bash "$ROOT/scripts/$s/inject.sh"; prc=$?
            [ "$prc" -eq 0 ] || proof_red+=("$s (код $prc)")
        else
            prc="нет"
            proof_red+=("$s (доказательства inject.sh нет)")
        fi
    fi
    SUITE_SUMMARY="$summary" bash "$ROOT/scripts/$s/run-all.sh"; rc=$?
    ran=$((ran + 1))
    # Строка набора — ПОСЛЕДНЯЯ с его именем: прогон набора пишет её, закончив
    # все свои проверки.
    row="$(awk -F'\t' -v s="$s" '$1 == s {r = $0} END {print r}' "$summary")"
    if [ -z "$row" ]; then
        unreported+=("$s")
        lines+=("$s · исполнено ? · красных ? · не выполнилось ? · код $rc · доказательство $prc — набор не отчитался о переписи")
        continue
    fi
    IFS=$'\t' read -r _ n _ b v <<<"$row"
    lines+=("$s · исполнено $n · красных $b · не выполнилось $v · код $rc · доказательство $prc")
    case "$rc" in
        0) ;;
        2) voided+=("$s") ;;
        *) red+=("$s") ;;
    esac
done

echo
echo "── наборы: в дереве ${#names[@]} · исполнено $ran"
printf '   %s\n' "${lines[@]}"

fail=0
if [ "$ran" -ne "${#names[@]}" ]; then
    echo "[FAIL] run-suites — наборов в дереве ${#names[@]}, исполнено $ran" >&2; fail=1
fi
if [ "${#unreported[@]}" -gt 0 ]; then
    echo "[FAIL] run-suites — не отчитались о переписи: ${unreported[*]} (прогонщик набора не общий либо оборвался)" >&2; fail=1
fi
if [ "${#proof_red[@]}" -gt 0 ]; then
    echo "[FAIL] run-suites — доказательство не сошлось: ${proof_red[*]}" >&2; fail=1
fi
if [ "${#red[@]}" -gt 0 ]; then
    echo "[FAIL] run-suites — красные наборы: ${red[*]}" >&2; fail=1
fi
[ "$fail" -eq 0 ] || exit 1
if [ "${#voided[@]}" -gt 0 ]; then
    if [ "$void_fails" -eq 1 ]; then
        echo "[FAIL] run-suites — без предмета: ${voided[*]}; предпосылки здесь создаёт само задание, их отсутствие — поломка" >&2
        exit 1
    fi
    echo "[VOID] run-suites — без предмета: ${voided[*]}; находок нет, но эти наборы не выполнились целиком" >&2
    exit 2
fi
echo "[PASS] run-suites — наборов ${#names[@]}, все исполнены и зелены"
