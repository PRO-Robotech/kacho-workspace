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

# mksandbox [путь-который-выбросить] — печатает путь СВЕЖЕЙ песочницы.
# Состав берётся ровно тем же предикатом, что и у самих проверок:
# `--cached --others --exclude-standard`.
#
# Имя даёт `mktemp`, а НЕ счётчик. Прежняя редакция наращивала переменную внутри
# функции, а функция зовётся подстановкой команды — то есть в ПОДОБОЛОЧКЕ, где
# приращение не переживает возврата. Счётчик оставался нулём, и КАЖДЫЙ вызов
# отдавал один и тот же каталог: песочницы не были изолированы друг от друга, и
# проба, взявшая свою переменную после чужого `mksandbox`, молча читала ЧУЖОЙ
# вход. Класс поймался собой же — так упала проба запасного пути ниже. Форма
# `mktemp -d -p` — та же, что у соседнего `inject-04.sh`.
mksandbox() {
    local drop="${1:-}" dir
    dir="$(mktemp -d -p "$TMP" s.XXXXXX)"
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

# spec <состояние-строки> — приёмка с одним сценарием и одной строкой таблицы.
#
# Объявлена НА ВЕРХНЕМ УРОВНЕ, а не в ветви «монорепо найдено», где жила прежде:
# ею пользуются пробы полосы ствола, которые своё дерево продукта ПРОИЗВОДЯТ САМИ
# и от наличия лежащей рядом копии не зависят. Функция, объявленная в ветви,
# существует ровно тогда, когда ветвь исполнилась, — и это ломается молча.
# Вход полностью под контролем пробы: каталог приёмок выброшен, поэтому вердикт
# читается как «эта строка отнесена к этой корзине», а не как заложник корпуса.
spec() {
    printf '# Инъекция\n\n> **Статус:** DRAFT\n\n## §4 Сценарии\n\n'
    printf '**XC-99-01 — проба инъекции**\n- **Then** наблюдаемо\n\n'
    printf '#### Состояние исполнения\n\n| кейс | состояние | чем держится |\n|---|---|---|\n'
    printf '%s\n' "$1"
}


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

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$REAL_FILE\` :: \`$REAL_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 0 "$b" "близнец: файл и имя проверки резолвятся — молчит" check-03-holding-claim-resolves.py

b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`internal/repohygiene/nosuchgate_test.go\` :: \`$REAL_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
run 1 "$b" "инъекция: файла нет на стволе продукта — краснеет и называет путь" \
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

# ── ВЕРДИКТ НЕ ЕСТЬ ФУНКЦИЯ ТОГО, НА ЧТО ПЕРЕКЛЮЧЕНА КОПИЯ (ws#543) ──────────
#
# Копия продукта ОБЩАЯ, и её ревизию переключает соседняя сессия. Проверка,
# читавшая её индекс, объявляла несуществующими координаты, которые в стволе
# ЕСТЬ: копия стояла на релизной линии, где каталог службы переименован. Отправка
# блокировалась работой, к которой отправляющий не причастен.
#
# Доказывается это ПАРОЙ ПРОГОНОВ НА ОДНОМ ДЕРЕВЕ В ДВУХ СОСТОЯНИЯХ, а не одним:
# «молчит на стволе» отдельно ничего не утверждает — молчала бы и проверка,
# читающая копию, если копия и есть ствол. Свойство здесь — РАВЕНСТВО ИСХОДОВ.
#
# Дерево синтетическое и строится здесь же: зависеть от того, куда сегодня
# переключена настоящая копия, эта проба не вправе — иначе её вход есть то самое
# состояние, независимость от которого она доказывает.
mkprod() { # → путь к синтетическому дереву продукта, выписанному на ЛИНИИ
    local dir
    dir="$(mktemp -d -p "$TMP" prod.XXXXXX)"
    git -C "$dir" init -q
    mkdir -p "$dir/internal/repohygiene"
    printf 'package repohygiene\n\nfunc TestSyntheticTrunkProbe(t *testing.T) {}\n' \
        > "$dir/internal/repohygiene/probe_test.go"
    git -C "$dir" add -A -f >/dev/null 2>&1
    git -C "$dir" -c user.email=probe@invalid -c user.name=probe \
        commit -qm 'синтетический ствол продукта' >/dev/null 2>&1
    git -C "$dir" update-ref refs/remotes/origin/main HEAD
    # Линия: каталог переименован — ровно то, что дала линия выноса службы, — и
    # рядом заведён файл, которого в стволе нет вовсе.
    git -C "$dir" checkout -q -b line
    git -C "$dir" mv internal/repohygiene/probe_test.go \
                     internal/repohygiene/renamed_test.go
    printf 'package repohygiene\n\nfunc TestSyntheticLineOnly(t *testing.T) {}\n' \
        > "$dir/internal/repohygiene/lineonly_test.go"
    git -C "$dir" add -A -f >/dev/null 2>&1
    git -C "$dir" -c user.email=probe@invalid -c user.name=probe \
        commit -qm 'линия: каталог переименован' >/dev/null 2>&1
    printf '%s' "$dir"
}

# runm <монорепо> <ожидаемый-код> <песочница> <имя> <скрипт> [подстрока]
runm() {
    local mono="$1" saved="${KACHO_MONOREPO:-}"
    shift
    export KACHO_MONOREPO="$mono"
    run "$@"
    export KACHO_MONOREPO="$saved"
}

PROD="$(mkprod)"
TRUNK_FILE="internal/repohygiene/probe_test.go"
TRUNK_TEST="TestSyntheticTrunkProbe"
LINE_FILE="internal/repohygiene/lineonly_test.go"
LINE_TEST="TestSyntheticLineOnly"

# Вход обеих решающих проб один и тот же — координата ствола.
b_trunk="$(mksandbox docs/specs)"; mkdir -p "$b_trunk/docs/specs"
spec "| XC-99-01 | держится | \`$TRUNK_FILE\` :: \`$TRUNK_TEST\` |" > "$b_trunk/$SPEC"
git -C "$b_trunk" add -A -f >/dev/null 2>&1

runm "$PROD" 0 "$b_trunk" \
    "решающая (1/2): копия НА ЛИНИИ, координата ствола — молчит" \
    check-03-holding-claim-resolves.py "копия ОПЕРЕЖАЕТ его"

git -C "$PROD" checkout -q --detach refs/remotes/origin/main
runm "$PROD" 0 "$b_trunk" \
    "решающая (2/2): та же копия НА СТВОЛЕ, тот же вход — тот же исход" \
    check-03-holding-claim-resolves.py "копия вровень с ним"
git -C "$PROD" checkout -q line

# Обратная сторона: координата, живая ТОЛЬКО в рабочей копии. Без этой пробы
# «исходы равны» доказывалось бы и проверкой, которая не смотрит никуда.
b_line="$(mksandbox docs/specs)"; mkdir -p "$b_line/docs/specs"
spec "| XC-99-01 | держится | \`$LINE_FILE\` :: \`$LINE_TEST\` |" > "$b_line/$SPEC"
git -C "$b_line" add -A -f >/dev/null 2>&1

runm "$PROD" 1 "$b_line" \
    "обратная (1/2): координата есть В КОПИИ и нет в стволе — краснеет и называет путь" \
    check-03-holding-claim-resolves.py "$LINE_FILE"
git -C "$PROD" checkout -q --detach refs/remotes/origin/main
runm "$PROD" 1 "$b_line" \
    "обратная (2/2): та же копия на стволе — тот же красный исход" \
    check-03-holding-claim-resolves.py "$LINE_FILE"
git -C "$PROD" checkout -q line

# Содержимое ФАЙЛА тоже берётся со ствола, а не с диска. Файл в копии на линии
# переименован, то есть по этому пути его на диске НЕТ; проверка, читавшая диск,
# сказала бы «файлов .go не названо» — диагностика, посылающая искать не там.
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$TRUNK_FILE\` :: \`TestNoSuchNameInTrunkFile\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runm "$PROD" 1 "$b" \
    "содержимое: файл ствола есть, проверки в нём нет — краснеет и называет ИМЯ" \
    check-03-holding-claim-resolves.py "TestNoSuchNameInTrunkFile"

# Зеркало против вакуумного молчания: координаты нет НИ в стволе, НИ в копии.
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`internal/repohygiene/nowhere_test.go\` :: \`$TRUNK_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runm "$PROD" 1 "$b" \
    "зеркало: координаты нет нигде — краснеет" \
    check-03-holding-claim-resolves.py "nowhere_test.go"

# Ствола в клоне нет вовсе — судится индекс копии, и перепись ГОВОРИТ это, а не
# подставляет молча. Без этой пробы запасной путь был бы невидим.
NOTRUNK="$(mktemp -d -p "$TMP" notrunk.XXXXXX)"
git -C "$NOTRUNK" init -q
mkdir -p "$NOTRUNK/internal/repohygiene"
printf 'package repohygiene\n\nfunc %s(t *testing.T) {}\n' "$TRUNK_TEST" \
    > "$NOTRUNK/$TRUNK_FILE"
git -C "$NOTRUNK" add -A -f >/dev/null 2>&1
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$TRUNK_FILE\` :: \`$TRUNK_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runm "$NOTRUNK" 0 "$b" \
    "запасной путь: ствол не резолвится — судится индекс копии, и это НАЗВАНО" \
    check-03-holding-claim-resolves.py "НЕ РЕЗОЛВИТСЯ"

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

# ── check-03-scope-row-scenario ─────────────────────────────────
#
# Проверка требует: у каждой строки состава `| F<N> |` есть сценарий (When+Then)
# либо передача в дочернюю приёмку, у которой такой раздел со сценарием есть.
#
# Пробы кладутся в ПУСТОЙ каталог приёмок (`mksandbox docs/specs`): на живых 154
# документах вход не детерминирован, и проба судила бы дерево, а не проверку.
mkspec() { # mkspec <песочница> <имя> <тело>
    mkdir -p "$1/docs/specs"
    printf '%s\n' "$3" > "$1/docs/specs/$2"
    git -C "$1" add -A -f >/dev/null 2>&1
}

b="$(mksandbox docs/specs)"
mkspec "$b" "sub-phase-P1-probe-acceptance.md" '# Приёмка P1

| ID | Фича |
|---|---|
| F1 | предмет без сценария |

## F1 — предмет
Раздел есть, а сценария в нём нет.'
run 1 "$b" "инъекция: строка состава без сценария — краснеет" \
    check-03-scope-row-scenario.py "F1"

b="$(mksandbox docs/specs)"
mkspec "$b" "sub-phase-P1-probe-acceptance.md" '# Приёмка P1

| ID | Фича |
|---|---|
| F1 | предмет со сценарием |

## F1 — предмет
**Given** дерево продукта
**When** вызывающий делает шаг
**Then** ответ таков, как объявлено'
run 0 "$b" "близнец: у строки состава есть сценарий — молчит" \
    check-03-scope-row-scenario.py

# Передача в дочернюю приёмку — законный второй способ, и без этой пробы
# проверка ловила бы «сценарий в ЭТОМ файле», а не «сценарий существует».
b="$(mksandbox docs/specs)"
mkspec "$b" "sub-phase-P1-probe-acceptance.md" '# Приёмка P1

| ID | Фича |
|---|---|
| F1 | предмет передан дочерней |

## F1 — предмет
Сценарий живёт в sub-phase-P1b-child-acceptance.md — здесь он не повторяется.'
mkspec "$b" "sub-phase-P1b-child-acceptance.md" '# Приёмка P1b

## F1 — тот же предмет
**When** вызывающий делает шаг
**Then** ответ таков, как объявлено'
run 0 "$b" "близнец: передача в дочернюю приёмку со сценарием — молчит" \
    check-03-scope-row-scenario.py

# Передача, которая НЕ резолвится, обязана остаться находкой: иначе ссылка на
# несуществующий документ становится способом закрыть любую строку состава.
b="$(mksandbox docs/specs)"
mkspec "$b" "sub-phase-P1-probe-acceptance.md" '# Приёмка P1

| ID | Фича |
|---|---|
| F1 | предмет передан в никуда |

## F1 — предмет
Сценарий живёт в sub-phase-P9Z-missing-acceptance.md.'
run 1 "$b" "инъекция: передача не резолвится — краснеет" \
    check-03-scope-row-scenario.py "F1"

# Обе предпосылки: приёмок нет вовсе и приёмки есть, но состав объявлен иначе.
# «Ноль находок» на них означало бы «ноль прочитанного».
b="$(mksandbox docs/specs)"
run 2 "$b" "предпосылка: приёмок нет — VOID, а не успех" \
    check-03-scope-row-scenario.py

b="$(mksandbox docs/specs)"
mkspec "$b" "sub-phase-P1-probe-acceptance.md" '# Приёмка P1

Состав объявлен прозой, строк `| F<N> |` в документе нет.

## Раздел
**When** шаг
**Then** ответ'
run 2 "$b" "предпосылка: состав объявлен не строками — VOID, а не успех" \
    check-03-scope-row-scenario.py

# ── ПОЛОСА ЧТЕНИЯ ДЕРЕВА ПРОДУКТА: СТВОЛ, А НЕ ИНДЕКС КОПИИ (ws#621) ─────────
#
# Проверка судит ЧУЖОЕ дерево, и судить его можно двумя полосами, дающими РАЗНЫЕ
# ответы: индекс рабочей копии отвечает о том, на чём копия стоит СЕЙЧАС, ствол —
# о том, что у продукта есть. Копия общая, парковку её никто не объявляет.
#
# Вход эти пробы ПРОИЗВОДЯТ САМИ — крохотным деревом продукта, где на стволе лежит
# одно, а в припаркованной вершине другое (`scripts/lib/product-fixture.sh`). Взять
# вход у лежащей рядом копии было бы нельзя: он зависел бы от того, куда её сегодня
# переставили, и полоса доказывалась бы ровно до дня, когда копию вернут на ствол.
#
# ПРОГОНОВ ТРИ, А НЕ ДВА. Контроль (молчат оба утверждения) · инъекция НОВОГО
# свойства (краснеет полоса ствола, прежнее утверждение молчит) · инъекция
# СУЩЕСТВУЮЩЕГО утверждения (краснеет оно, полоса ствола молчит). Без третьего
# молчание прежнего утверждения неотличимо от молчания мёртвого, и новая полоса
# могла бы оказаться вакуумной, не показав этого ничем.
#
# Оба утверждения живут в ОДНОЙ проверке, поэтому «краснеет только одно» судится по
# ТЕКСТУ находки, а не по коду выхода: код у них общий, и различить их им нельзя.
# Две директивы дают линтеру ПОЙТИ за источником: путь собран из переменной, и без
# них `shellcheck -x` отвечает SC1091 «не следую», то есть разбирает файл без
# объявлений помощника. `source-path=SCRIPTDIR` несущая: конвейер зовёт линтер из
# РАЗНЫХ рабочих каталогов (docs-gate — от корня, skills-gate — из своего), и
# одиночный относительный путь резолвился бы ровно у одного из двух.
#
# ЧЕГО ЭТИ ДИРЕКТИВЫ НЕ ДЕЛАЮТ — и говорится это прямо, потому что обратное легко
# предположить: сам помощник ими НЕ линтуется. Замер (shellcheck 0.11.0, дефект
# внесён в помощника): названный в командной строке файл даёт 2 находки, тот же
# дефект через `source` — 0. Источник читается ради объявлений, а не ради вердикта.
# Помощник линтуется только тем, кто назовёт его сам; ни один шаг конвейера
# `scripts/lib/**` сегодня не покрывает.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/product-fixture.sh
source "$WS/scripts/lib/product-fixture.sh"

# Однофактные входы. `TRUNK_ONLY` есть на стволе и нет в припаркованной вершине;
# `PARKED_ONLY` — наоборот. Это ровно то различие, которое прежняя полоса читала
# наизнанку: она объявляла непроверяемым первое и засчитывала второе.
TRUNK_ONLY_FILE="pkg/servicecontract/axis_test.go"
TRUNK_ONLY_TEST="TestValueOfEmptySliceIsStillADeclaration"
PARKED_ONLY_FILE="internal/repohygiene/catalogsplicewiring_test.go"
PARKED_ONLY_TEST="TestCatalogSpliceGateIsCalledByThePipeline"

# mkprod_lane — дерево продукта, где ствол и припаркованная вершина расходятся
# ОДНИМ фактом на каждой оси. Печатает путь.
#
# ИМЯ ОТЛИЧАЕТСЯ ОТ `mkprod` ВЫШЕ НАМЕРЕННО. При сведении линий ws#622 обе работы
# принесли в ЭТОТ файл функцию с именем `mkprod`, и git не сказал ничего: куски не
# перекрывались, конфликта не было, каждая линия по отдельности исполнялась верно.
# Работало это лишь порядком объявлений — bash определяет функции по ходу, поэтому
# вызов до второго `mkprod()` получал первое определение, а после — второе. Одно
# имя с двумя смыслами в одном файле; читатель различить их не может, а первая
# перестановка блоков сломала бы пробы молча (`multi-agent-flow.md` §14,
# «столкновение имён»).
mkprod_lane() {
    sandbox_seq=$((sandbox_seq + 1))
    local dir="$TMP/p$sandbox_seq"
    product_fixture_init "$dir"
    mkdir -p "$dir/$(dirname "$TRUNK_ONLY_FILE")"
    printf 'package servicecontract\n\nfunc %s(t *testing.T) {}\n' "$TRUNK_ONLY_TEST" \
        > "$dir/$TRUNK_ONLY_FILE"
    product_fixture_seal_trunk "$dir"
    rm -f "$dir/$TRUNK_ONLY_FILE"
    mkdir -p "$dir/$(dirname "$PARKED_ONLY_FILE")"
    printf 'package repohygiene\n\nfunc %s(t *testing.T) {}\n' "$PARKED_ONLY_TEST" \
        > "$dir/$PARKED_ONLY_FILE"
    product_fixture_seal_parked "$dir"
    printf '%s' "$dir"
}

# runp <код> <песочница> <дерево-продукта> <имя> [нужная-подстрока] [ЗАПРЕЩЁННАЯ]
#
# Шестой аргумент несущий: он и делает прогон различающим. Находка обязана назвать
# СВОЮ полосу и не назвать чужую — иначе «покраснело» не говорит, ЧТО покраснело, а
# вакуумная полоса выглядела бы доказанной соседней находкой.
runp() {
    local want="$1" box="$2" prod="$3" name="$4" need="${5:-}" forbid="${6:-}" got out
    probes=$((probes + 1))
    out="$(DOCS_GATE_ROOT="$box" KACHO_MONOREPO="$prod" \
           "$HERE/check-03-holding-claim-resolves.py" 2>&1)"; got=$?
    if [ "$got" -ne "$want" ]; then
        echo "  ПРОВАЛ $name — ждали код $want, получили $got" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
        return
    fi
    if [ -n "$need" ] && [[ "$out" != *"$need"* ]]; then
        echo "  ПРОВАЛ $name — код верен, но в выводе нет «$need»" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
        return
    fi
    if [ -n "$forbid" ] && [[ "$out" == *"$forbid"* ]]; then
        echo "  ПРОВАЛ $name — в выводе есть ЗАПРЕЩЁННОЕ «$forbid»: покраснело не то" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
        return
    fi
    echo "  ok   $name (код $got)"
}

# Текст полосы ствола и текст прежнего утверждения — каждый обязан приходить
# ТОЛЬКО от своего дефекта.
SAY_TRUNK="на стволе дерева продукта нет"
SAY_OLD="не называет ПРОВЕРКУ"

echo "== check-03: полоса чтения дерева продукта — ствол, а не индекс копии =="

# ПРОГОН 1 — КОНТРОЛЬ. Претензия называет координату, которая есть НА СТВОЛЕ.
# Копия при этом припаркована в стороне, и в её индексе этого файла нет вовсе:
# прежняя полоса объявляла такую претензию непроверяемой (ровно 11 претензий
# приёмки XC-11), новая — молчит.
prod="$(mkprod_lane)"
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$TRUNK_ONLY_FILE\` :: \`$TRUNK_ONLY_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runp 0 "$b" "$prod" "контроль: координата есть на стволе, копия припаркована — молчит"

# ПРОГОН 1б — ТО ЖЕ, копия ВЕРНУТА НА СТВОЛ. Отличие от предыдущего ОДНОФАКТНОЕ:
# положение HEAD, и только оно. Вердикт обязан совпасть — это и есть свойство,
# которое проба заводит: вердикт перестал зависеть от состояния копии.
product_fixture_park_on_trunk "$prod"
runp 0 "$b" "$prod" "то же на копии, ВЕРНУТОЙ на ствол — тот же вердикт"

# ПРОГОН 2 — ИНЪЕКЦИЯ НОВОГО СВОЙСТВА. Координата есть В ИНДЕКСЕ припаркованной
# копии и НЕТ на стволе. Прежняя полоса молчала (файл на диске лежит), новая —
# находка, и находка называет СВОЮ полосу, а прежнее утверждение молчит.
prod="$(mkprod_lane)"
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$PARKED_ONLY_FILE\` :: \`$PARKED_ONLY_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runp 1 "$b" "$prod" "инъекция НОВОГО: координата только в индексе копии — находка" \
    "$SAY_TRUNK" "$SAY_OLD"

# ПРОГОН 3 — ИНЪЕКЦИЯ СУЩЕСТВУЮЩЕГО утверждения. Файл на стволе есть, имени
# проверки строка не называет. Краснеет ПРЕЖНЕЕ утверждение, полоса ствола молчит:
# без этого прогона её молчание было бы неотличимо от молчания мёртвой.
prod="$(mkprod_lane)"
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$TRUNK_ONLY_FILE\` — участник назван поимённо |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runp 1 "$b" "$prod" "инъекция СТАРОГО: файл на стволе есть, проверки не назвал — находка" \
    "$SAY_OLD" "$SAY_TRUNK"

# Ось, названная отдельно: координата ВЫДУМАННАЯ — её нет ни на стволе, ни в
# индексе. Полоса обязана остаться находкой и после выравнивания: иначе «судим по
# стволу» стало бы способом не судить вовсе.
prod="$(mkprod_lane)"
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`pkg/vydumannyy/net_takogo_test.go\` :: \`TestNetTakogo\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runp 1 "$b" "$prod" "выдуманная координата — находка, названная путём" \
    "net_takogo_test.go"

# ТРЕТЬЯ КАТЕГОРИЯ: ствола нет вовсе. Проверять координату не по чему, и это НЕ
# находка — объявить претензии непроверяемыми потому, что мы не нашли, у чего
# спросить, значит выдать «не выполнилось» за вердикт. Индекс копии при этом на
# месте и координату бы «подтвердил» — тем ценнее, что отката на него нет.
prod="$(mkprod_lane)"
product_fixture_drop_trunk "$prod"
b="$(mksandbox docs/specs)"; mkdir -p "$b/docs/specs"
spec "| XC-99-01 | держится | \`$PARKED_ONLY_FILE\` :: \`$PARKED_ONLY_TEST\` |" > "$b/$SPEC"
git -C "$b" add -A -f >/dev/null 2>&1
runp 2 "$b" "$prod" "ствол не разрешён — ТРЕТЬЯ КАТЕГОРИЯ со своим текстом" \
    "ствол дерева продукта"

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
