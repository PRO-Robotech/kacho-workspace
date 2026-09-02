#!/usr/bin/env bash
# shellcheck disable=SC2016
#   Вносимые строки — markdown; бэктики в них разметка, а не подстановка команды,
#   поэтому одинарные кавычки здесь намеренны на весь файл.
# Доказательство набора tooling-gate инъекцией — на ВРЕМЕННОЙ копии дерева.
# Рабочее дерево не трогается.
#
# У каждой инъекции дефекта стоит ЗАКОННЫЙ БЛИЗНЕЦ той же формы, на котором гейт
# обязан молчать, и отдельная проба на ПРЕДПОСЫЛКУ: оставшись без предмета, гейт
# обязан ответить VOID, а не успехом. Гейт, доказанный только красной половиной,
# ловит форму, а не существо, и отключается первым же ложным срабатыванием
# (`gate-authoring` §Инъекция; `testing.md` §«Гейт на класс», п.2).
#
# Каждая проба получает СВОЮ свежую песочницу и после себя ничего не оставляет:
# восстановление мутаций через git в песочнице без единого коммита требовало бы
# заводить в ней личность коммиттера, а личность в этом проекте не переопределяют.
#
# Перепись проб печатается в конце: «все зелёные» без числа проб — то же
# «ноль находок против ноль прочитанного», от которого набор и защищает.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# mksandbox [путь-который-выбросить] — печатает путь свежей песочницы.
#
# Состав берётся ровно тем же предикатом, что и у самих проверок:
# `--cached --others --exclude-standard`. Ещё не закоммиченный, но и не
# игнорируемый файл обязан попасть в песочницу — иначе проба доказывала бы
# свойство дерева, которого в момент правки не существует.
# Каталог берётся `mktemp`, а НЕ счётчиком: `b="$(mksandbox)"` исполняет функцию в
# ПОДОБОЛОЧКЕ, поэтому счётчик в ней увеличивался и терялся — все пробы получали
# одну и ту же песочницу `s1`. Разворачивание архива поверх чинило только
# ОТСЛЕЖИВАЕМЫЕ файлы, а внесённый пробой НОВЫЙ файл переживал её и приезжал в
# следующую. Обнаружено 2026-08-19 первой же пробой, которая вносит дефект новым
# файлом (check-05): она получала находку предыдущей пробы и падала на исправном
# дереве. Шапка при этом обещала обратное — «каждая проба получает СВОЮ свежую
# песочницу»: комментарий против кода, и верным был комментарий.
#
# СПИСОК ОТДАЁТСЯ tar ОДНИМ ВЫЗОВОМ (`--null --files-from=-`), и это не вкус.
# Прежняя редакция гнала его через `xargs -0 tar cf -`: xargs дробит список по
# своему буферу (здесь 131072 байта — `xargs --show-limits`), КАЖДАЯ порция
# пишет СВОЙ архив, а принимающий `tar xf -` останавливается на метке конца
# ПЕРВОГО и выходит; второй `tar cf -` получает SIGPIPE и печатает
# `xargs: tar: terminated by signal 13` — единственный след, ничего не меняющий
# в вердикте.
# Замер на этом дереве: список 145021 байт → две порции → в песочницу доезжало
# 2328 файлов из 2547, и не доезжали ровно `scripts/docs-gate`, `scripts/hooks`,
# `scripts/skills-gate`, `scripts/tooling-gate`, `scripts/vault-gate`,
# `scripts/hook-proofs.sh`. Пробы судили НЕ ТО ДЕРЕВО: check-01 честно называл
# 33 «несуществующих пути», которые в репозитории есть, а check-08 не находил
# вызывающего. На базе линии (`1202e3c`) список был 63074 байта — одна порция, —
# поэтому дефект жил скрытно с рождения и проявился на первом дереве,
# перешагнувшем буфер.
#
# ПОЛНОТА ПЕСОЧНИЦЫ — ПРЕДПОСЫЛКА КАЖДОЙ ПРОБЫ, поэтому она проверяется, а не
# предполагается: неполная песочница даёт не находку, а «не выполнилось», и
# вердикта в ней нет НИ У ОДНОЙ пробы, включая прошедшие. Предикат от причины
# неполноты не зависит (место на диске, отказ tar, новое дробление): сколько
# файлов запрошено, столько обязано доехать.
# Способность этого стража заговорить доказывается СНАРУЖИ, без ручек в коде —
# подменой tar на урезающий:
#     d=$(mktemp -d); printf '%s\n' '#!/bin/sh' \
#       'case "$1" in cf) shift; exec /usr/bin/tar --exclude=README.md -c -f "$@";; esac' \
#       'exec /usr/bin/tar "$@"' > "$d/tar"; chmod +x "$d/tar"
#     PATH="$d:$PATH" bash scripts/tooling-gate/inject.sh   # ждём код 2 и [VOID]
mksandbox() {
    local drop="${1:-}"
    local dir want got
    dir="$(mktemp -d "$TMP/sXXXXXX")"
    ( cd "$WS" && git ls-files --cached --others --exclude-standard -z \
        | tar cf - --null --files-from=- ) \
        | ( cd "$dir" && tar xf - )
    # Счёт снимается ДО `drop` и ДО `git init`: первый выбрасывает путь намеренно,
    # второй заводит собственные файлы, и оба сделали бы сверку бессмысленной.
    want="$( cd "$WS" && git ls-files --cached --others --exclude-standard | wc -l )"
    got="$( cd "$dir" && find . \( -type f -o -type l \) | wc -l )"
    if [ "$want" -ne "$got" ]; then
        printf 'песочница неполна: запрошено файлов %s, доехало %s\n' "$want" "$got" \
            > "$TMP/INCOMPLETE"
    fi
    [ -n "$drop" ] && rm -rf "${dir:?}/$drop"
    git -C "$dir" init -q
    git -C "$dir" add -A -f >/dev/null 2>&1
    printf '%s' "$dir"
}

probes=0
failed=0

# run <ожидаемый-код> <песочница> <имя-пробы> <скрипт>
#
# `TOOLING_GATE_REQUIRED_CONTEXTS` пробрасывается из окружения вызова: сетевую
# половину check-05 доказываем ОФЛАЙН, задав перечень контекстов извне. Ходить за
# ним в сеть из доказательства нельзя — у токена ранера нет права читать защиту
# ветки, и проба стала бы «не выполнилось», поданным как зелёное.
run() {
    local want="$1" box="$2" name="$3" script="$4" got out
    # Песочница — предпосылка пробы, а не её предмет. Собралась неполно —
    # исход у прогона ТРЕТИЙ: вердикта нет ни у одной пробы, включая прошедшие,
    # и объявлять это находкой о дереве значит послать читателя искать дефект
    # там, где его нет (`testing.md` §«Чтение вердикта», п.2).
    if [ -e "$TMP/INCOMPLETE" ]; then
        echo "[VOID] inject — $(cat "$TMP/INCOMPLETE")" >&2
        echo "       вердикта нет НИ У ОДНОЙ пробы: они судили бы не то дерево." >&2
        echo "[CENSUS] inject: проб исполнено $probes, до срыва предпосылки" >&2
        exit 2
    fi
    probes=$((probes + 1))
    out="$(TOOLING_GATE_ROOT="$box" bash "$HERE/$script" 2>&1)"; got=$?
    if [ "$got" -eq "$want" ]; then
        echo "  ok   $name (код $got)"
    else
        echo "  ПРОВАЛ $name — ждали код $want, получили $got" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
    fi
}

WF_REL=".github/workflows/ci.yaml"
AG_REL=".claude/agents/acceptance-reviewer.md"

echo "== check-01: конвейер называет несуществующий путь =="
b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-01-workflow-paths.sh

b="$(mksandbox)"
printf '        run: bash ./no-such-file.sh\n' >> "$b/$WF_REL"
run 1 "$b" "инъекция: шаг зовёт ./no-such-file.sh — краснеет" check-01-workflow-paths.sh

# Законный близнец ТОЙ ЖЕ формы: такой же токен-путь в такой же позиции, но файл
# в дереве есть. Без него гейт ловил бы «упоминание пути», а не «отсутствие».
b="$(mksandbox)"
printf '        run: bash ./bootstrap.sh --help\n' >> "$b/$WF_REL"
run 0 "$b" "близнец: та же форма ссылки на СУЩЕСТВУЮЩИЙ файл — молчит" check-01-workflow-paths.sh

b="$(mksandbox .github/workflows)"
run 2 "$b" "предпосылка: файлов конвейера нет — VOID, а не успех" check-01-workflow-paths.sh

echo "== check-02: агент переписывает нормативную карту =="
b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-02-agents-no-restated-map.sh

# Инъекция намеренно несёт ВЕРНОЕ отношение: запрещена копия карты как таковая,
# а не её ошибочное значение. Копия с верным значением сегодня — это ровно та,
# что молча разойдётся завтра.
b="$(mksandbox)"
printf -- '- [ ] Zone → kacho-geo\n' >> "$b/$AG_REL"
run 1 "$b" "инъекция: стрелочная карта (пусть и верная) — краснеет" check-02-agents-no-restated-map.sh

b="$(mksandbox)"
printf -- '- [ ] Владельца смотри в `data-integrity.md` §«Cross-domain ссылки», п.5 (там же kacho-iam и прочие).\n' >> "$b/$AG_REL"
run 0 "$b" "близнец: ссылка на норму, имена сервисов без стрелки — молчит" check-02-agents-no-restated-map.sh

b="$(mksandbox .claude/agents)"
run 2 "$b" "предпосылка: агентов нет — VOID, а не успех" check-02-agents-no-restated-map.sh

echo "== check-03: агент выписывает подмену модулей =="
b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-03-agents-no-module-substitution.sh

b="$(mksandbox)"
printf -- '- go.mod держит `replace ../kacho-proto`.\n' >> "$b/$AG_REL"
run 1 "$b" "инъекция: выписанная подмена — краснеет" check-03-agents-no-module-substitution.sh

b="$(mksandbox)"
printf -- '- Подмена модулей — `polyrepo.md` §«Правило зависимостей при полирепо-топологии»; здесь не переписывается.\n' >> "$b/$AG_REL"
run 0 "$b" "близнец: ссылка на норму без выписанной конструкции — молчит" check-03-agents-no-module-substitution.sh

b="$(mksandbox .claude/agents)"
run 2 "$b" "предпосылка: агентов нет — VOID, а не успех" check-03-agents-no-module-substitution.sh

echo "== check-04: «не проверено» засчитано прогонщиком за «пройдено» =="
b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-04-runner-void-is-not-pass.sh

# Инъекция — НАСТОЯЩИЙ прогонщик той же формы, что и живые: тот же глоб
# `check-*.sh`, тот же разбор кодов; отличается ровно тем, что «проверить не
# удалось» не участвует в предикате выхода. Это дословно та конструкция, что
# держала ежедневный прогон зелёным при нуле пройденных проверок.
mkrunner() {
    local box="$1" name="$2" verdict="$3"
    mkdir -p "$box/scripts/$name"
    {
        printf '#!/usr/bin/env bash\nset -uo pipefail\n'
        printf 'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        printf 'ok=0; bad=0; void=0\n'
        printf 'for c in "$here"/check-*.sh; do\n'
        printf '    [ -f "$c" ] || continue\n'
        printf '    bash "$c"\n'
        printf '    case $? in 0) ok=$((ok+1));; 2) void=$((void+1));; *) bad=$((bad+1));; esac\n'
        printf 'done\n'
        printf 'echo "%s: пройдено $ok, провалено $bad, без предмета $void"\n' "$name"
        printf '%s\n' "$verdict"
    } > "$box/scripts/$name/run-all.sh"
    chmod +x "$box/scripts/$name/run-all.sh"
    git -C "$box" add -A -f >/dev/null 2>&1
}

b="$(mksandbox)"
mkrunner "$b" "injected-gate" '[ "$bad" -eq 0 ]'
run 1 "$b" "инъекция: прогонщик судит только по провалам — краснеет" check-04-runner-void-is-not-pass.sh

# Законный близнец ТОЙ ЖЕ формы: тот же глоб, тот же разбор, та же печать —
# отличается только тем, что «не удалось» входит в предикат выхода. Без него
# проверка ловила бы «в дереве появился ещё один прогонщик», а не существо.
b="$(mksandbox)"
mkrunner "$b" "injected-gate" '[ "$bad" -eq 0 ] && [ "$void" -eq 0 ]'
run 0 "$b" "близнец: тот же прогонщик, «не удалось» в предикате выхода — молчит" check-04-runner-void-is-not-pass.sh

# Прогонщик, который не отвечает нулём даже на единственной ПРОЙДЕННОЙ проверке,
# к отрицательной пробе непригоден: она прошла бы на нём тождественно. Такой
# исход обязан быть VOID, а не «доказано».
b="$(mksandbox)"
mkrunner "$b" "injected-gate" 'false'
run 2 "$b" "положительный контроль сорван — VOID, а не «доказано»" check-04-runner-void-is-not-pass.sh

b="$(mksandbox scripts)"
run 2 "$b" "предпосылка: прогонщиков нет — VOID, а не успех" check-04-runner-void-is-not-pass.sh

echo "== check-05: триггер не сужен по ветке / контекст ствола перестал производиться =="
INJ_REL=".github/workflows/injected.yaml"

# Дефект вносится ОТДЕЛЬНЫМ процессом той же формы, а не правкой ci.yaml: так
# дефект и его законный близнец отличаются РОВНО объявлением триггера, а не
# соседним текстом.
mkwf() {
    local box="$1" body="$2"
    printf '%s' "$body" > "$box/$INJ_REL"
    git -C "$box" add -A -f >/dev/null 2>&1
}

WF_JOB='jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - run: "true"
'

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-05-workflow-triggers-narrowed.sh

# Дословно та форма, что стояла здесь до 2026-08-19 и стоила 142 прогонов из 200.
b="$(mksandbox)"
mkwf "$b" "name: injected
on: [push, pull_request]
$WF_JOB"
run 1 "$b" "инъекция: on: [push, pull_request] без сужения — краснеет" check-05-workflow-triggers-narrowed.sh

# ЗАКОННЫЙ БЛИЗНЕЦ: тот же процесс, те же два события, та же позиция —
# отличается ровно сужением по ветке. Без него гейт ловил бы «в дереве появился
# ещё один процесс», а не отсутствие сужения.
b="$(mksandbox)"
mkwf "$b" "name: injected
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
$WF_JOB"
run 0 "$b" "близнец: те же два события, сужены по main — молчит" check-05-workflow-triggers-narrowed.sh

# Второй близнец — про ИСПОЛНЯЕМОЕ против ТЕКСТА: слова `on: [push, pull_request]`
# стоят в комментарии, триггеров по ветке у процесса нет вовсе. Текстовый предикат
# покраснел бы здесь — и покраснел бы на комментарии самого ci.yaml.
b="$(mksandbox)"
mkwf "$b" "name: injected
# Здесь когда-то стояло on: [push, pull_request] — теперь только расписание.
on:
  schedule:
    - cron: \"0 3 * * *\"
  workflow_dispatch:
$WF_JOB"
run 0 "$b" "близнец: та же строка в КОММЕНТАРИИ, триггер — расписание — молчит" check-05-workflow-triggers-narrowed.sh

# Сужение есть, но ствол в него не попадает: контексты на MR в main не появятся,
# а защита ветки требует их поимённо — слияние встанет навсегда.
b="$(mksandbox)"
mkwf "$b" "name: injected
on:
  pull_request:
    branches: [\"release/**\"]
$WF_JOB"
run 1 "$b" "инъекция: pull_request мимо main — краснеет" check-05-workflow-triggers-narrowed.sh

# Сужение по путям: контекст не начинается, поэтому он не зелёный и не красный —
# он «ожидается», и это блокирует слияние, а не сообщает о дефекте.
b="$(mksandbox)"
mkwf "$b" "name: injected
on:
  pull_request:
    branches: [main]
    paths: [\"docs/**\"]
$WF_JOB"
run 1 "$b" "инъекция: pull_request сужен по paths — краснеет" check-05-workflow-triggers-narrowed.sh

# Контроль в обратную сторону, обе половины — офлайн, перечень задан извне.
b="$(mksandbox)"
TOOLING_GATE_REQUIRED_CONTEXTS='bats-and-shellcheck
такого job'"'"'а ни один процесс не производит' \
    run 1 "$b" "инъекция: защита требует контекст, которого нет — краснеет" check-05-workflow-triggers-narrowed.sh

b="$(mksandbox)"
TOOLING_GATE_REQUIRED_CONTEXTS='bats-and-shellcheck
документы объявляют то, чем их измеряют' \
    run 0 "$b" "близнец: все требуемые контексты производятся — молчит" check-05-workflow-triggers-narrowed.sh

b="$(mksandbox .github/workflows)"
run 2 "$b" "предпосылка: файлов конвейера нет — VOID, а не успех" check-05-workflow-triggers-narrowed.sh

# Предпосылка второго рода: файлы есть, а триггеров ПО ВЕТКЕ в них ноль. Тогда
# предикат остался без предмета, и это тоже VOID, а не «находок 0».
b="$(mksandbox .github/workflows)"
mkdir -p "$b/.github/workflows"
mkwf "$b" "name: injected
on:
  schedule:
    - cron: \"0 3 * * *\"
$WF_JOB"
run 2 "$b" "предпосылка: ни одного триггера по ветке — VOID, а не «находок 0»" check-05-workflow-triggers-narrowed.sh

echo "== check-06: версия анализатора не пиннится / объявлена дважды =="

# Настоящий процесс из песочницы ВЫБРАСЫВАЕТСЯ: проверка читает весь каталог, и
# без изоляции проба судила бы сумму «внедрённый + живой», то есть отвечала бы на
# другой вопрос. Ровно этот промах и дал три ложных провала при первом заходе.
mk6() { # mk6 <тело процесса> → путь песочницы, где ЕДИНСТВЕННЫЙ процесс — он
    local box; box="$(mksandbox .github/workflows)"
    mkdir -p "$box/.github/workflows"
    printf '%s' "$1" > "$box/$INJ_REL"
    git -C "$box" add -A -f >/dev/null 2>&1
    printf '%s' "$box"
}

PIN_STEP='      - name: shellcheck пиннутой версии
        run: |
          sudo install "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck
          shellcheck --version'

WF_PINNED="env:
  SHELLCHECK_VERSION: \"0.11.0\"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
$PIN_STEP
      - run: shellcheck -x a.sh
"

# (−) законный близнец: пин поставлен, версия напечатана
run 0 "$(mk6 "$WF_PINNED")" "близнец: пин поставлен и версия напечатана — молчит" \
    check-06-shellcheck-version-pinned.sh

# (+) зовёт анализатор, не поставив пин — исполнится версия образа ранера
run 1 "$(mk6 'env:
  SHELLCHECK_VERSION: "0.11.0"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: shellcheck -x a.sh
')" "зовёт анализатор без пина — находка" check-06-shellcheck-version-pinned.sh

# (+) значение объявлено ДВАЖДЫ — задания разойдутся молча
run 1 "$(mk6 "$WF_PINNED  env:
      SHELLCHECK_VERSION: \"0.9.0\"
")" "два объявления версии — находка" check-06-shellcheck-version-pinned.sh

# (+) пин ставится, но версия не печатается: вердикт не несёт с собой, чем получен
run 1 "$(mk6 'env:
  SHELLCHECK_VERSION: "0.11.0"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: sudo install "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck
      - run: shellcheck -x a.sh
')" "пин без печати версии — находка" check-06-shellcheck-version-pinned.sh

# (−) процессов нет вовсе — проверять нечего, и это НЕ успех
run 2 "$(mksandbox .github/workflows)" "предпосылка: процессов нет — VOID, а не успех" \
    check-06-shellcheck-version-pinned.sh


echo "== check-07: «без предмета» приходит тем же кодом, что находка =="
b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-07-runner-void-distinct-from-finding.sh

# Инъекция — ДОСЛОВНО тот вердикт, что стоял во всех четырёх прогонщиках до
# ws#458: «без предмета» и «находка» схлопнуты в единицу. Вызывающий на нём не
# может решить, чинить дерево или создавать условие.
#
# ВАЖНО, что эта инъекция НЕ роняет соседа `check-04`: тому довольно любого
# ненулевого кода, и единица его устраивает. Красное приходит от нового гейта, а
# не от существующего контроля, — иначе новый мог бы оказаться вакуумным и не
# показать этого ничем (`testing.md` §«Гейт на класс», п. 2в).
b="$(mksandbox)"
mkrunner "$b" "injected-gate" '[ "$bad" -eq 0 ] && [ "$void" -eq 0 ]'
run 1 "$b" "инъекция: без предмета отдаётся кодом находки — краснеет" \
    check-07-runner-void-distinct-from-finding.sh
run 0 "$b" "та же инъекция у соседа check-04 — молчит, красное принадлежит check-07" \
    check-04-runner-void-is-not-pass.sh

# Законный близнец ТОЙ ЖЕ формы: тот же глоб, тот же разбор, та же печать —
# отличается только тем, что у трёх исходов три кода. Без него гейт ловил бы
# «в дереве появился ещё один прогонщик», а не существо.
b="$(mksandbox)"
mkrunner "$b" "injected-gate" 'if [ "$bad" -gt 0 ]; then exit 1; fi; if [ "$void" -gt 0 ]; then exit 2; fi; exit 0'
run 0 "$b" "близнец: три исхода — три кода — молчит" \
    check-07-runner-void-distinct-from-finding.sh

# АНТИМАСКА — проба, ради которой check-07 и заведён отдельно от check-04.
# Вердикт отличается от близнеца ровно ПОРЯДКОМ: беспредметность объявляется
# раньше находки. На единственной проверке любого вида такой прогонщик
# неотличим от правильного — он отвечает 1 на находку и 2 на беспредметность.
# Расходятся они только ВМЕСТЕ: набор с находкой И беспредметной проверкой
# отдаёт 2, то есть настоящее нарушение перестаёт блокировать отправку.
# Ровно эту дыру правка ws#458 могла бы открыть, закрывая шум.
b="$(mksandbox)"
mkrunner "$b" "injected-gate" 'if [ "$void" -gt 0 ]; then exit 2; fi; if [ "$bad" -gt 0 ]; then exit 1; fi; exit 0'
run 1 "$b" "инъекция: беспредметность объявлена раньше находки — маска, краснеет" \
    check-07-runner-void-distinct-from-finding.sh
run 0 "$b" "та же инъекция у соседа check-04 — молчит: там «не проверено» ненулевое" \
    check-04-runner-void-is-not-pass.sh

# Прогонщик, не отвечающий нулём даже на единственной ПРОЙДЕННОЙ проверке, к
# остальным пробам непригоден: они прошли бы на нём тождественно.
b="$(mksandbox)"
mkrunner "$b" "injected-gate" 'false'
run 2 "$b" "положительный контроль сорван — VOID, а не «доказано»" \
    check-07-runner-void-distinct-from-finding.sh

b="$(mksandbox scripts)"
run 2 "$b" "предпосылка: прогонщиков нет — VOID, а не успех" \
    check-07-runner-void-distinct-from-finding.sh

echo "== check-08: вызывающий читает три исхода набора, а не два =="

# mkcaller <песочница> <хвост> — подменяет вызывающего в песочнице хуком ТОЙ ЖЕ
# формы, что живой: те же снятые переменные окружения git, тот же вывод перечня
# наборов из индекса, тот же обход с разбором кодов. Отличается ровно ХВОСТОМ —
# тем, что вызывающий делает с посчитанными исходами. Без общей формы проверка
# ловила бы «хук переписали», а не существо.
mkcaller() {
    local box="$1" tail="$2"
    mkdir -p "$box/scripts/hooks"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE\n'
        printf 'set -uo pipefail\n'
        printf 'ROOT="$(git rev-parse --show-toplevel)" || exit 1\n'
        printf 'cd "$ROOT" || exit 1\n'
        printf 'gates=()\n'
        printf 'while IFS= read -r rel; do gates+=("$rel"); done < <(git ls-files "scripts/*/run-all.sh" | sort)\n'
        printf '[ "${#gates[@]}" -eq 0 ] && { echo "наборов нет" >&2; exit 1; }\n'
        printf 'failed=0; void=0\n'
        printf 'for g in "${gates[@]}"; do\n'
        printf '    bash "$ROOT/$g" >&2\n'
        printf '    case $? in 0) ;; 2) void=$((void + 1)) ;; *) failed=$((failed + 1)) ;; esac\n'
        printf 'done\n'
        printf '%s\n' "$tail"
    } > "$box/scripts/hooks/pre-push"
    chmod +x "$box/scripts/hooks/pre-push"
    git -C "$box" add -A -f >/dev/null 2>&1
}

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-08-caller-reads-the-three-outcomes.sh

# Инъекция А — ДОСЛОВНО поведение вызывающего до ws#458: любой ненулевой код
# набора останавливает отправку. Из копии без клона продукта это блокировало
# КАЖДУЮ отправку по причине, к дереву не относящейся.
b="$(mksandbox)"
mkcaller "$b" 'if [ $((failed + void)) -gt 0 ]; then echo "ОТКАЗ: отправка остановлена" >&2; exit 1; fi
echo "локальные проверки зелёные" >&2; exit 0'
run 1 "$b" "инъекция А: беспредметность блокирует отправку наравне с находкой — краснеет" \
    check-08-caller-reads-the-three-outcomes.sh
# п. 2в: красное обязано принадлежать НОВОМУ гейту, а не существующему контролю.
# Соседи судят прогонщики, а инъекция подменяет вызывающего — они обязаны молчать.
run 0 "$b" "та же инъекция у соседа check-04 — молчит, красное принадлежит check-08" \
    check-04-runner-void-is-not-pass.sh
run 0 "$b" "та же инъекция у соседа check-07 — молчит, красное принадлежит check-08" \
    check-07-runner-void-distinct-from-finding.sh

# Инъекция Б — обратная крайность и потому опаснее: беспредметность НЕ блокирует,
# но и не названа. Завершающая строка у чистого и у беспредметного прогона одна,
# то есть «не выполнилось» отрапортовано успехом. Кода выхода тут мало —
# различает только то, что читает человек.
b="$(mksandbox)"
mkcaller "$b" 'if [ "$failed" -gt 0 ]; then echo "ОТКАЗ: отправка остановлена" >&2; exit 1; fi
echo "локальные проверки зелёные" >&2; exit 0'
run 1 "$b" "инъекция Б: беспредметный прогон закончился строкой чистого — краснеет" \
    check-08-caller-reads-the-three-outcomes.sh

# Инъекция В — АНТИМАСКА, и она здесь главная. Вызывающий объявляет
# беспредметность РАНЬШЕ находки. На наборах одного вида он неотличим от верного:
# 1 на находке, 0 на беспредметности, строки разные. Расходятся они только
# ВМЕСТЕ — набор с находкой рядом с беспредметным перестаёт останавливать
# отправку. Ровно эту дыру правка ws#458 могла бы открыть, закрывая шум.
b="$(mksandbox)"
mkcaller "$b" 'if [ "$void" -gt 0 ]; then echo "часть наборов без предмета" >&2; exit 0; fi
if [ "$failed" -gt 0 ]; then echo "ОТКАЗ: отправка остановлена" >&2; exit 1; fi
echo "локальные проверки зелёные" >&2; exit 0'
run 1 "$b" "инъекция В: беспредметность объявлена раньше находки — маска, краснеет" \
    check-08-caller-reads-the-three-outcomes.sh

# Законный близнец ТОЙ ЖЕ формы: тот же обход, тот же разбор, другая запись
# вердикта и другие слова. Без него гейт ловил бы формулировку живого хука, а не
# свойство, и первая же переписка текста сделала бы его ложным срабатыванием.
b="$(mksandbox)"
mkcaller "$b" 'case "$failed:$void" in
    0:0) echo "всё проверено, находок нет" >&2; exit 0 ;;
    0:*) echo "часть наборов не с чем сверять — отправка идёт, но проверено не всё" >&2; exit 0 ;;
    *)   echo "ОТКАЗ: отправка остановлена" >&2; exit 1 ;;
esac'
run 0 "$b" "близнец: три исхода различимы, слова другие — молчит" \
    check-08-caller-reads-the-three-outcomes.sh

# Вызывающий, красный даже там, где все наборы зелены, к остальным пробам
# непригоден: они прошли бы на нём тождественно.
b="$(mksandbox)"
mkcaller "$b" 'exit 3'
run 2 "$b" "положительный контроль сорван — VOID, а не «доказано»" \
    check-08-caller-reads-the-three-outcomes.sh

b="$(mksandbox scripts/hooks)"
run 2 "$b" "предпосылка: вызывающего нет — VOID, а не успех" \
    check-08-caller-reads-the-three-outcomes.sh

echo
# Объём осмотренного печатается вместе с числом проб: «проб 49, провалов 0» без
# размера песочницы не отличимо от того же числа проб на четверти дерева.
echo "[CENSUS] inject: проб исполнено $probes, провалов $failed; в каждой песочнице файлов $( cd "$WS" && git ls-files --cached --others --exclude-standard | wc -l )"
if [ "$probes" -eq 0 ]; then
    echo "[VOID] inject — ни одной пробы не исполнено" >&2
    exit 2
fi
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] inject — гейт не доказан: провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] inject — гейт доказан в обе стороны: проб $probes, провалов 0"
