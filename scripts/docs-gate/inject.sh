#!/usr/bin/env bash
# shellcheck disable=SC2016
#   Вносимые строки — markdown; бэктики в них разметка, а не подстановка команды,
#   поэтому одинарные кавычки здесь намеренны на весь файл.
# Доказательство набора docs-gate инъекцией — на ВРЕМЕННОЙ копии дерева.
# Рабочее дерево не трогается.
#
# У каждой инъекции дефекта стоит ЗАКОННЫЙ БЛИЗНЕЦ той же формы, на котором гейт
# обязан молчать, и отдельная проба на ПРЕДПОСЫЛКУ: оставшись без предмета, гейт
# обязан ответить VOID, а не успехом (`gate-authoring` §Инъекция; `testing.md`
# §«Гейт на класс», п.2).
#
# Сверх этого здесь есть пробы на СОДЕРЖАНИЕ вердикта, а не только на код выхода.
# Обе прежние ошибки этого места были ошибками содержания при верном коде:
# «DRAFT — awaiting APPROVED» засчитывалось за APPROVED, а канонически объявленное
# состояние записки — за отсутствующее. Гейт, доказанный одними кодами выхода, обе
# эти ошибки пропустил бы.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sandbox_seq=0

# mksandbox [путь-который-выбросить] — печатает путь свежей песочницы.
# Состав берётся ровно тем же предикатом, что и у самих проверок:
# `--cached --others --exclude-standard`.
mksandbox() {
    local drop="${1:-}"
    sandbox_seq=$((sandbox_seq + 1))
    local dir="$TMP/s$sandbox_seq"
    mkdir -p "$dir"
    ( cd "$WS" && git ls-files --cached --others --exclude-standard -z ) \
        | ( cd "$WS" && xargs -0 tar cf - ) \
        | ( cd "$dir" && tar xf - )
    [ -n "$drop" ] && rm -rf "${dir:?}/$drop"
    git -C "$dir" init -q
    git -C "$dir" add -A -f >/dev/null 2>&1
    printf '%s' "$dir"
}

probes=0
failed=0

# run <ожидаемый-код> <песочница> <имя-пробы> <скрипт> [обязательная-подстрока]
run() {
    local want="$1" box="$2" name="$3" script="$4" need="${5:-}" got out
    probes=$((probes + 1))
    out="$(DOCS_GATE_ROOT="$box" "$HERE/$script" 2>&1)"; got=$?
    if [ "$got" -ne "$want" ]; then
        echo "  ПРОВАЛ $name — ждали код $want, получили $got" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
        return
    fi
    if [ -n "$need" ] && [[ "$out" != *"$need"* ]]; then
        echo "  ПРОВАЛ $name — код $got верен, но в выводе нет «$need»" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
        return
    fi
    echo "  ok   $name (код $got)"
}

SPEC="docs/specs/sub-phase-injected-acceptance.md"
NOTE="obsidian/kacho/KAC/KAC-999999.md"

echo "== check-01: вердикт приёмки не читается машинно =="
b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-01-acceptance-verdict.py

b="$(mksandbox)"
printf '# Приёмка без объявления вердикта\n\nЗдесь про APPROVED сказано прозой.\n' > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: приёмка без строки состояния — краснеет" check-01-acceptance-verdict.py

# Законный близнец ТОЙ ЖЕ формы: тот же файл, то же слово APPROVED в шапке —
# отличается только тем, что состояние объявлено. Без него гейт ловил бы
# «в docs/specs появился файл», а не отсутствие вердикта.
b="$(mksandbox)"
{
    printf '# Приёмка с объявленным вердиктом\n\n'
    printf '> **Статус:** DRAFT v1 — awaiting `acceptance-reviewer` APPROVED\n'
} > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "близнец: состояние объявлено — молчит" check-01-acceptance-verdict.py

# Пробы на СОДЕРЖАНИЕ вердикта. Вход у них ПОЛНОСТЬЮ под контролем пробы:
# каталог приёмок выброшен и заменён одним документом, поэтому утверждение
# читается как «этот документ отнесён к этой корзине», а не как заложник
# сегодняшнего состава корпуса (`gate-authoring` §Детерминизм входа).
#
# Первая проба — предмет всей проверки: строка, где слово APPROVED стоит ПОСЛЕ
# DRAFT, обязана считаться черновиком. Счёт по упоминанию слова закрывал такие
# строки как одобренные — их в корпусе двадцать две.
b="$(mksandbox docs/specs)"
mkdir -p "$b/docs/specs"
{
    printf '# Приёмка, ожидающая одобрения\n\n'
    printf '> **Статус:** DRAFT v1 — awaiting `acceptance-reviewer` APPROVED\n'
} > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "содержание: «DRAFT — awaiting APPROVED» отнесено к DRAFT, не к APPROVED" \
    check-01-acceptance-verdict.py "вердикты — DRAFT 1"

# Зеркальная проба: без неё проверка, всегда отвечающая «DRAFT», прошла бы
# предыдущую (`gate-authoring` §Отрицание только в паре с положительным).
b="$(mksandbox docs/specs)"
mkdir -p "$b/docs/specs"
{
    printf '# Одобренная приёмка\n\n'
    printf '> **Статус:** ✅ APPROVED (`acceptance-reviewer`, проба)\n'
} > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "зеркало: объявленный APPROVED отнесён к APPROVED" \
    check-01-acceptance-verdict.py "вердикты — APPROVED 1"

b="$(mksandbox docs/specs)"
run 2 "$b" "предпосылка: приёмок нет — VOID, а не успех" check-01-acceptance-verdict.py

echo "== check-02: записка журнала не объявляет состояния =="
b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-02-kac-trail-status.py

b="$(mksandbox)"
printf '# KAC-999999 — записка без состояния\n\nТекст.\n' > "$b/$NOTE"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: записка без состояния — краснеет" check-02-kac-trail-status.py

# Близнец 1 — КАНОНИЧЕСКАЯ форма (шапка YAML). Ровно её прежняя проверка не
# читала, объявляя шестнадцать записок «без состояния».
b="$(mksandbox)"
printf -- '---\nticket_id: KAC-999999\nstatus: done\n---\n\n# KAC-999999\n\nТекст.\n' > "$b/$NOTE"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "близнец: состояние в шапке YAML — молчит" check-02-kac-trail-status.py

# Близнец 2 — форма тела. Обе формы законны, и проверка обязана принимать обе.
b="$(mksandbox)"
printf '# KAC-999999\n\n**Status**: done\n\nТекст.\n' > "$b/$NOTE"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "близнец: состояние строкой тела — молчит" check-02-kac-trail-status.py

# Слепая зона прежнего предиката №1 — имя. Тикеты со слагом вместо номера
# (`SEC-A-…`, `GEO-1`, `IAM-INT-1-…`) под глоб `KAC-*.md` не подходили и не
# читались вовсе.
b="$(mksandbox)"
printf '# SEC-ZZ — записка со слагом вместо номера\n\nТекст.\n' \
    > "$b/obsidian/kacho/KAC/SEC-ZZ-injected.md"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "слепая зона имени: записка со слагом без состояния — краснеет" \
    check-02-kac-trail-status.py

# Слепая зона прежнего предиката №2 — глубина. `find -maxdepth 1` не открывал бы
# вложенную записку, сколько бы их там ни завели.
b="$(mksandbox)"
mkdir -p "$b/obsidian/kacho/KAC/sub"
printf '# KAC-999998 — вложенная записка без состояния\n\nТекст.\n' \
    > "$b/obsidian/kacho/KAC/sub/KAC-999998.md"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "слепая зона глубины: вложенная записка без состояния — краснеет" \
    check-02-kac-trail-status.py

b="$(mksandbox obsidian/kacho/KAC)"
run 2 "$b" "предпосылка: записок нет — VOID, а не успех" check-02-kac-trail-status.py

echo
echo "[CENSUS] inject: проб исполнено $probes, провалов $failed"
if [ "$probes" -eq 0 ]; then
    echo "[VOID] inject — ни одной пробы не исполнено" >&2
    exit 2
fi
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] inject — гейт не доказан: провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] inject — гейт доказан в обе стороны: проб $probes, провалов 0"
