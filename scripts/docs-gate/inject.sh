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

echo "== check-03: «этот кейс держится» без проверяемой координаты =="

# Монорепо для check-03 берётся ОТДЕЛЬНО от песочницы: песочница подменяет
# документ, а судьёй остаётся настоящее дерево продукта. Иначе инъекция
# доказывала бы разбор markdown, а не сверку с деревом.
REPO="${KACHO_MONOREPO:-$WS/project/kacho}"
# `.git` признаётся и каталогом, и файлом: у рабочего дерева (`git worktree`) это
# файл-указатель. Предикат тот же, что у самой проверки и у vault-gate; иначе пробы
# check-03 молча не исполнялись бы ровно там, где ведётся работа.
if [ ! -d "$REPO/.git" ] && [ ! -f "$REPO/.git" ]; then
    echo "  ПРОПУСК check-03 — монорепо не найдено; пробы этой проверки НЕ исполнены" >&2
    echo "  (это не «ноль находок»: непрогнанные пробы в число исполненных не входят, и итог" >&2
    echo "   ниже назовёт меньшее число — «провалов 0» на них ничего не утверждает)" >&2
else
# Путь к дереву ПЕРЕДАЁТСЯ проверке явно: она запускается с рабочим каталогом
# песочницы, где `project/kacho` не лежит и лежать не может. Без передачи проверка
# честно отвечает «без предмета» (код 2), а проба ждёт отказа (код 1) — и десять
# сценариев проваливаются по причине, к предмету не относящейся.
export KACHO_MONOREPO="$REPO"

# Реальные координаты дерева продукта. Они обязаны существовать — иначе законный
# близнец краснел бы по причине, к предмету не относящейся.
REAL_FILE="internal/repohygiene/participationconformance_test.go"
REAL_TEST="TestEveryCarrierParticipantIsRaisedByAProbe"

# spec <состояние-строки> — приёмка с одним сценарием и одной строкой таблицы.
# Вход полностью под контролем пробы: каталог приёмок выброшен, поэтому вердикт
# читается как «эта строка отнесена к этой корзине», а не как заложник корпуса.
spec() {
    printf '# Инъекция\n\n> **Статус:** DRAFT\n\n## §4 Сценарии\n\n'
    printf '**XC-99-01 — проба инъекции**\n- **Then** наблюдаемо\n\n'
    printf '#### Состояние исполнения\n\n| кейс | состояние | чем держится |\n|---|---|---|\n'
    printf '%s\n' "$1"
}

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$REAL_FILE\` :: \`$REAL_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "близнец: файл и имя проверки резолвятся — молчит" check-03-holding-claim-resolves.py

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`internal/repohygiene/nosuchgate_test.go\` :: \`$REAL_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: файла нет в индексе монорепо — краснеет и называет путь" \
    check-03-holding-claim-resolves.py "nosuchgate_test.go"

# Предмет всей проверки: файл СУЩЕСТВУЕТ, а названной в нём проверки нет. Именно
# так выглядела строка, объявлявшая кейс держащимся файлом, в котором требуемого
# утверждения не было. Проба на существование файла эту строку пропускает.
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$REAL_FILE\` :: \`TestNoSuchProbeInThatFile\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: файл есть, проверки в нём нет — краснеет и называет имя" \
    check-03-holding-claim-resolves.py "TestNoSuchProbeInThatFile"

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$REAL_FILE\` — участник без пробы назван поимённо |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: назван только файл, без имени проверки — краснеет" \
    check-03-holding-claim-resolves.py "не называет ПРОВЕРКУ"

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | не начат | \`$REAL_FILE\` :: \`$REAL_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: «не начат» с координатой — строка противоречит себе" \
    check-03-holding-claim-resolves.py "противоречит себе"

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | не начат | предмет Ф2 |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "близнец: «не начат» без координаты — молчит" check-03-holding-claim-resolves.py

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | почти готов | \`$REAL_FILE\` :: \`$REAL_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: состояние вне закрытого набора — краснеет" \
    check-03-holding-claim-resolves.py "вне закрытого набора"

# Обе стороны перечня. Сценарий без строки уходит из счёта молча — ровно это и
# дало «восемь исполнено» там, где кейсов пятнадцать.
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
{
    spec "| XC-99-01 | держится | \`$REAL_FILE\` :: \`$REAL_TEST\` |"
    printf '\n**XC-99-02 — сценарий без строки**\n- **Then** наблюдаемо\n'
} > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: сценарий без строки таблицы — краснеет" \
    check-03-holding-claim-resolves.py "XC-99-02"

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
{
    spec "| XC-99-01 | держится | \`$REAL_FILE\` :: \`$REAL_TEST\` |"
    printf '| XC-99-07 | не начат | предмет Ф2 |\n'
} > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: строка таблицы без сценария — краснеет" \
    check-03-holding-claim-resolves.py "XC-99-07"

# Законный близнец ЧУЖОЙ формы: таблица с колонкой «чем держится», где речь о
# механизме, а не о кейсе. Такие в корпусе есть (слои, цена плана), и проверка
# обязана на них молчать — иначе она ловит форму, а не существо.
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
{
    printf '# Инъекция\n\n> **Статус:** DRAFT\n\n'
    printf '| Слой | Предмет | Чем держится |\n|---|---|---|\n'
    printf '| C1 | входящий запрос | компилятор и отказ старта |\n'
} > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 2 "$b" "близнец: таблица о механизме, а не о кейсе — предметом не является (VOID)" \
    check-03-holding-claim-resolves.py "предмет не найден"

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
printf '# Приёмка без таблицы состояния\n\n> **Статус:** DRAFT\n' > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 2 "$b" "предпосылка: таблиц состояния нет — VOID, а не успех" \
    check-03-holding-claim-resolves.py

# Предпосылка второго рода: без дерева продукта координату проверять не по чему.
probes=$((probes + 1))
out="$(DOCS_GATE_ROOT="$b" KACHO_MONOREPO="$TMP/нет-такого" "$HERE/check-03-holding-claim-resolves.py" 2>&1)"
if [ $? -eq 2 ]; then
    echo "  ok   предпосылка: монорепо не найдено — VOID, а не успех (код 2)"
else
    echo "  ПРОВАЛ предпосылка: монорепо не найдено — ждали код 2" >&2
    printf '%s\n' "$out" >&2
    failed=$((failed + 1))
fi
fi

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
