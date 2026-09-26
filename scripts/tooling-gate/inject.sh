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

# Фикстура САМА заводит сужённый триггер: с решения владельца 2026-09-20 автозапуска
# в дереве нет, и без этой строки проба доказывала бы не «контексты производятся», а
# «их некому производить» — то есть свою же соседнюю ось.
b="$(mksandbox)"
python3 - "$b/.github/workflows/ci.yaml" <<'PYWF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace("on:\n  workflow_dispatch:", "on:\n  pull_request:\n    branches: [main]\n  workflow_dispatch:", 1)
open(p, 'w', encoding='utf-8').write(s)
PYWF
TOOLING_GATE_REQUIRED_CONTEXTS='bats-and-shellcheck
документы объявляют то, чем их измеряют' \
    run 0 "$b" "близнец: триггер сужен, все требуемые контексты производятся — молчит" check-05-workflow-triggers-narrowed.sh

# ОПАСНАЯ СТОРОНА ОБЪЯВЛЕННОГО «АВТОЗАПУСКА НЕТ»: контекст, которого никто не
# начинает, остаётся «ожидается» и блокирует слияние НАВСЕГДА. Дерево здесь как
# есть (триггеров нет), извне задан непустой перечень обязательных контекстов.
b="$(mksandbox)"
TOOLING_GATE_REQUIRED_CONTEXTS='bats-and-shellcheck' \
    run 1 "$b" "инъекция: автозапуска нет, а защита требует контексты — краснеет" check-05-workflow-triggers-narrowed.sh

b="$(mksandbox .github/workflows)"
run 2 "$b" "предпосылка: файлов конвейера нет — VOID, а не успех" check-05-workflow-triggers-narrowed.sh

# Триггеров ПО ВЕТКЕ ноль — с решения владельца 2026-09-20 это ОБЪЯВЛЕННОЕ
# состояние, а не потерянный предмет: задания описаны и поднимаются вручную. Прежде
# здесь ждали VOID; вечный отказ снимают не глядя, вместе со всеми осями проверки.
# Законность этого состояния держит соседняя ось: она краснеет, если защита при том
# же дереве требует контексты.
b="$(mksandbox .github/workflows)"
mkdir -p "$b/.github/workflows"
mkwf "$b" "name: injected
on:
  schedule:
    - cron: \"0 3 * * *\"
$WF_JOB"
run 0 "$b" "близнец: автозапуска нет и контекстов не требуют — молчит" check-05-workflow-triggers-narrowed.sh

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

echo "== check-09: merge-readiness перестал различать три исхода =="
MR_REL="scripts/merge-readiness.sh"

# ЗАМЕР СРЕДЫ ПЕЧАТАЕТСЯ ВСЕГДА — и это не оформление.
#
# Первая редакция этого блока вносила дефект, СНИМАЯ `LC_ALL=C` и полагаясь на
# локаль среды. На машине разработчика (ru_RU.UTF-8) он воспроизводился, в
# конвейере — нет: там локаль байтовая, снятие пина дефектом не является, и обе
# пробы молча зеленели. Инъекция, не внёсшая дефекта, неотличима от гейта,
# потерявшего падучесть: оба дают зелёное. Поэтому среда теперь МЕРЯЕТСЯ и
# печатается — вопрос «а какая локаль у ранера» получает ответ в журнале
# прогона, а не в чьей-то догадке.
mr_env_note() {
    local amb byte ru
    amb="$(printf 'проба — раз\nпроба - раз\n' | sort -u | wc -l)"
    byte="$(printf 'проба — раз\nпроба - раз\n' | LC_ALL=C sort -u | wc -l)"
    ru="$(locale -a 2>/dev/null | grep -ci '^ru_RU' || true)"
    echo "  [CENSUS] среда: LANG=${LANG:-<пусто>} LC_ALL=${LC_ALL:-<пусто>}; локалей ru_RU в системе $ru"
    echo "  [CENSUS] на пробном входе локаль оставляет строк $amb, байтовый порядок — $byte"
    if [ "$amb" -eq "$byte" ]; then
        echo "  [CENSUS] различия локаль/байты здесь НЕТ — инъекции ниже намеренно на него не опираются"
    fi
}
mr_env_note

# mr_patch <файл> <выражение perl> <что вносим> — вносит дефект и ДОКАЗЫВАЕТ, что
# он внесён. Без этой проверки образец, переставший совпадать (другая версия
# инструмента, переписанная строка, иные переводы строк), давал бы «дефект внесён,
# гейт молчит» — то есть обвинял бы живой гейт в смерти.
mr_patch() {
    local file="$1" expr="$2" what="$3" before after
    before="$(md5sum < "$file")"
    perl -0pi -e "$expr" "$file"
    after="$(md5sum < "$file")"
    if [ "$before" = "$after" ]; then
        probes=$((probes + 1))
        failed=$((failed + 1))
        echo "  ПРОВАЛ инъекция НЕ ВНЕСЕНА ($what) — образец не совпал ни с одной строкой;" >&2
        echo "         вердикта у этой пробы нет, и зелёное здесь означало бы обратное" >&2
        return 1
    fi
}

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" \
    check-09-merge-readiness-tells-three-outcomes-apart.sh

# ИНЪЕКЦИЯ ПОРЯДКА, НЕ ЗАВИСЯЩАЯ ОТ СРЕДЫ. Дефект вносится ЯВНО — перечень
# обязательных подаётся сверке в обратном порядке, — а не через настройку,
# действие которой зависит от локали машины. Свойство, которое стережёт проба,
# то же самое: вход сверки обязан быть в том порядке, которого сверка ждёт.
# Исходный дефект (сортировка по локали при байтовой сверке) — частный случай
# этого; воспроизводить именно его значило бы требовать от ранера русской локали.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(required=\$\(jq .*?)\| LC_ALL=C sort -u\)$/$1| LC_ALL=C sort -u -r)/m' \
    "обратный порядок перечня обязательных"; then
    run 1 "$b" "инъекция: перечень обязательных подан сверке не в том порядке — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# Инъекция ПРЕДМЕТА ЗАДАЧИ: отказ разбора выходит единицей. Скрипт при этом
# исправен во всём остальном — меняется ровно один факт, код на выходе из
# `parse_broken`, — и краснеют ровно две пробы, где разбор ломается.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/(вердикта нет.*?\n)  exit 2\n/$1  exit 1\n/s' \
    "код выхода parse_broken"; then
    run 1 "$b" "инъекция: отказ разбора выходит кодом находки — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# ИНЪЕКЦИЯ СХЛОПЫВАНИЯ, НЕ ЗАВИСЯЩАЯ ОТ СРЕДЫ. Дедупликация по первому полю
# считает одним «проба — раз» и «проба - раз» — ровно то, что делает локальная
# сортировка, но детерминированно и на любой машине. Порядок при этом остаётся
# байтовым, поэтому сверка не ломается: краснеет РОВНО одна проба, та, ради
# которой инъекция и написана. Прежняя редакция задавала здесь `LC_ALL=ru_RU.UTF-8`
# и молчала там, где этой локали в системе нет.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(required=\$\(jq .*?)\| LC_ALL=C sort -u\)$/$1| LC_ALL=C sort -u -k1,1)/m' \
    "схлопывание имён при дедупликации"; then
    run 1 "$b" "инъекция: различные имена схлопнуты в одно — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# Законный близнец: то же свойство (байтовый порядок плюс дедупликация),
# записанное иначе. Без него проверка ловила бы строку `LC_ALL=C sort -u`, а не
# исход, и запрещала бы автору любую другую запись сверки.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/LC_ALL=C sort -u/LC_ALL=C sort | LC_ALL=C uniq/g' \
    "та же сортировка другой формой"; then
    run 0 "$b" "близнец: та же сортировка другой формой — молчит" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

b="$(mksandbox scripts/merge-readiness.sh)"
run 2 "$b" "предпосылка: инструмента нет — VOID, а не успех" \
    check-09-merge-readiness-tells-three-outcomes-apart.sh

echo "== check-10: хук отправки судит то, что отправляется, а не копию =="
HK_REL="scripts/hooks/pre-push"
C10=check-10-push-hook-judges-what-is-pushed.sh

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C10"

# Каждая инъекция роняет в ЖИВОМ хуке ровно одно условие короткого выхода.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/\[ "\$n_removed" -gt 0 \] && \[ "\$n_pushed" -eq 0 \]/false/' \
    "короткий выход удаления снят"; then
    run 1 "$b" "инъекция: удаление судит копию (ws#810) — краснеет" "$C10"
    run 0 "$b" "та же инъекция у соседа check-08 — молчит, красное принадлежит check-10" \
        check-08-caller-reads-the-three-outcomes.sh
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/только удаление, прогона не было/локальные проверки воркспейса зелёные/' \
    "удаление рапортует строкой чистого"; then
    run 1 "$b" "инъекция: удаление без прогона названо «зелёным» — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/\[ "\$n_removed" -gt 0 \] && //' "пустой вход принят за удаление"; then
    run 1 "$b" "инъекция: пустой вход без прогона — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/ && \[ "\$n_pushed" -eq 0 \]//' "удаление маскирует вершину"; then
    run 1 "$b" "инъекция: удаление рядом с вершиной снимает прогон — краснеет" "$C10"
fi

b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/\(cd "\$wt" && bash "\$g"/(cd "\$ROOT" && bash "\$g"/' \
    "наборы исполняются в копии"; then
    run 1 "$b" "инъекция: вершина судится по рабочей копии (ws#811) — краснеет" "$C10"
    run 0 "$b" "та же инъекция у соседа check-08 — молчит, красное принадлежит check-10" \
        check-08-caller-reads-the-three-outcomes.sh
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/--detach "\$wt" "\$c"/--detach "\$wt" HEAD/' "судится HEAD вместо вершины"; then
    run 1 "$b" "инъекция: судится HEAD, а не отправляемая вершина — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/name="\$\{rref#refs\/heads\/\}"/name="\$(git rev-parse --abbrev-ref HEAD)"/' \
    "черновик по HEAD"; then
    run 1 "$b" "инъекция: черновик взят по HEAD, а не по ссылке — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/mktemp -d "\$wt_base\/pre-push.XXXXXX"/mktemp -d/' "копия вершины в TMPDIR"; then
    run 0 "$b" "близнец: копия вершины в другом месте — молчит" "$C10"
fi

# Возврат check-verifier к ws#811: перечень наборов и условия вне дерева.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/git -C "\$wt" ls-files/git -C "\$ROOT" ls-files/' \
    "перечень наборов из копии"; then
    run 1 "$b" "инъекция: перечень наборов взят из копии, а не из вершины — краснеет" "$C10"
    run 0 "$b" "та же инъекция у соседа check-08 — молчит, красное принадлежит check-10" \
        check-08-caller-reads-the-three-outcomes.sh
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" "s/'!!' \\| '\\?\\?'\\) outside\\+=\\(\"\\\$\\{rec:3\\}\"\\) ;;/'!!' | '??') : ;;/" \
    "условия вне дерева не переносятся"; then
    run 1 "$b" "инъекция: игнорируемое копии (project/) в копию вершины не едет — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/git -C "\$wt" check-ignore -q -- "\$rel\/"/git -C "\$ROOT" check-ignore -q -- "\$rel\/"/' \
    "условие по правилам копии"; then
    run 1 "$b" "инъекция: игнорируемое судится правилами копии, а не вершины — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/            case "\$src\/" in "\$wt_base"\/\*\) continue ;; esac\n//' \
    "дом копий переносится"; then
    run 1 "$b" "инъекция: в копию вершины едет дом копий — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/        case "\/\$rel" in \*\/__pycache__ \| \*\.py\[co\]\) continue ;; esac\n//' \
    "байткод переносится"; then
    run 1 "$b" "инъекция: в копию вершины едет байткод копии — краснеет" "$C10"
fi

# Возврат wave-reviewer к ws#811: копия полосы сама лежит в доме копий `tmp/`.
# Переключатель роняется в обе стороны: полоса судится как канонический и
# канонический — как полоса; близнец пишет ту же принадлежность другой формой.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/"\$wt_base"\/\*\) root_in_base=1 ;;/"\$wt_base"\/*) root_in_base=0 ;;/' \
    "копия полосы под tmp/ судится как канонический"; then
    run 1 "$b" "инъекция: из копии полосы под tmp/ условие вне дерева не едет — краснеет" "$C10"
    run 0 "$b" "та же инъекция у соседа check-08 — молчит, красное принадлежит check-10" \
        check-08-caller-reads-the-three-outcomes.sh
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/\*\) root_in_base=0 ;; esac/*) root_in_base=1 ;; esac/' \
    "канонический судится как копия полосы"; then
    run 1 "$b" "инъекция: из канонического в копию вершины едет дом копий — краснеет" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/^case "\$ROOT\/" in "\$wt_base"\/\*\) root_in_base=1 ;; \*\) root_in_base=0 ;; esac$/root_in_base=0; [[ "\$ROOT\/" == "\$wt_base"\/* ]] \&\& root_in_base=1/m' \
    "принадлежность дому копий другой формой"; then
    run 0 "$b" "близнец: принадлежность копии дому копий другой формой — молчит" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/--untracked-files=normal/--untracked-files=all/' \
    "кандидаты поштучно"; then
    run 0 "$b" "близнец: кандидаты перечислены поштучно, а не каталогом — молчит" "$C10"
fi
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" "s/git -C \"\\\$wt\" ls-files 'scripts\\/\\*\\/run-all.sh'/(cd \"\\\$wt\" \\&\\& git ls-files -- 'scripts\\/*\\/run-all.sh')/" \
    "перечень из вершины другой формой"; then
    run 0 "$b" "близнец: перечень наборов из вершины другой формой — молчит" "$C10"
fi

# Близнец: та же форма, другие слова — проверка судит исход, а не формулировку.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/только удаление, прогона не было/уезжает лишь снятие ссылок, наборы не исполнялись/' \
    "другие слова строки удаления"; then
    run 0 "$b" "близнец: строка удаления другими словами — молчит" "$C10"
fi

b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/^set -uo pipefail\n/set -uo pipefail\nexit 3\n/m' "хук непригоден"; then
    run 2 "$b" "положительный контроль сорван — VOID, а не «доказано»" "$C10"
fi
b="$(mksandbox scripts/hooks)"
run 2 "$b" "предпосылка: вызывающего нет — VOID, а не успех" "$C10"

echo "== check-12: выписанный предикат на форме, где два движка расходятся =="

# ПРЕДПОСЫЛКА ЗАПРЕТА — ОТДЕЛЬНАЯ ПРОБА, И ОНА НЕ ПРО ДЕРЕВО.
# Запрет держится не вкусом, а измеримым фактом: в этом воркспейсе есть ВТОРОЙ
# движок grep, и на запрещённой форме он расходится с GNU. Факт обязан
# проверяться, а не помниться: починят ugrep — запрет станет суеверием, и
# узнать об этом надо здесь, а не через год. Где второго движка нет (конвейер),
# проба отвечает третьим исходом, а не зелёным: «не с чем сверять» и «сверили,
# сошлось» — разные вещи.
CC_BIN="${CLAUDE_CODE_EXECPATH:-}"
[ -x "$CC_BIN" ] || CC_BIN="$HOME/.local/bin/claude"
PROBE_LINE='x-7777-z'
if [ -x "$CC_BIN" ]; then
    probes=$((probes + 1))
    ug_out="$( printf '%s\n' "$PROBE_LINE" | ( exec -a ugrep "$CC_BIN" -G -oE '(^|[^0-9])7777' ) 2>/dev/null || true )"
    gnu_out="$( printf '%s\n' "$PROBE_LINE" | command grep -oE '(^|[^0-9])7777' 2>/dev/null || true )"
    if [ -z "$ug_out" ] && [ -n "$gnu_out" ]; then
        echo "  ok   предпосылка: движки расходятся — обёртка отдала пусто, GNU нашёл [$gnu_out]"
    else
        echo "  ПРОВАЛ предпосылка check-12 — движки БОЛЬШЕ НЕ расходятся" >&2
        echo "         обёртка=[$ug_out] GNU=[$gnu_out]; запрет потерял предмет и обязан быть снят вместе с проверкой" >&2
        failed=$((failed + 1))
    fi
else
    echo "  VOID предпосылка check-12 — второго движка нет ($CC_BIN), расхождение здесь не проверяемо"
fi

C12_REL=".claude/hooks/README-inject-probe.md"

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" check-12-handrun-predicate-survives-both-greps.sh

# Дефект вносится НОВЫМ файлом области: правка существующего смешала бы находку
# с чужой строкой, и красное пришло бы неизвестно от чего.
b="$(mksandbox)"
printf 'Перепись задач: `git ls-files | grep -E %s(^|[^0-9])1282([^0-9]|$)%s`\n' "'" "'" > "$b/$C12_REL"
run 1 "$b" "инъекция: захватывающая скобка с якорем — краснеет" check-12-handrun-predicate-survives-both-greps.sh

# Вторая ЗАКОННАЯ ЗАПИСЬ той же формы. Распознаватель, знающий только первую,
# молчит на второй — ни красного, ни зелёного, — и это слепая зона, а не успех.
b="$(mksandbox)"
printf 'Перепись файлов: `git ls-files | grep -E %s(?:^|/)run\\.sh$%s`\n' "'" "'" > "$b/$C12_REL"
run 1 "$b" "инъекция: НЕЗАХВАТЫВАЮЩАЯ скобка с якорем — тоже краснеет" check-12-handrun-predicate-survives-both-greps.sh

# Близнец 1: та же форма на ИСПОЛНЯЕМОЙ строке скрипта. Её исполняет дочерний
# bash, то есть настоящий GNU grep, и запись там верна. Гейт, краснеющий и
# здесь, запрещал бы правильное.
b="$(mksandbox)"
{ printf '#!/usr/bin/env bash\n'; printf 'git ls-files | grep -E %s(^|/)run\\.sh$%s\n' "'" "'"; } > "$b/.claude/hooks/inject-probe-twin.sh"
run 0 "$b" "близнец: та же форма на исполняемой строке скрипта — молчит" check-12-handrun-predicate-survives-both-greps.sh

# Близнец 2: тот же ВОПРОС к дереву, заданный формой, которая сошлась в обоих
# движках. Без него гейт ловил бы «вызов grep в тексте», а не форму границы.
b="$(mksandbox)"
printf 'Перепись задач: `git ls-files | grep -P %s(?<![0-9])1282(?![0-9])%s`\n' "'" "'" > "$b/$C12_REL"
run 0 "$b" "близнец: та же граница просмотром назад — молчит" check-12-handrun-predicate-survives-both-greps.sh

# Близнец 3: запрещённая форма БЕЗ вызова grep на строке. Это не предикат, а
# текст о регулярном выражении, и судить его нечем.
b="$(mksandbox)"
printf 'Форма `(^|[^0-9])N([^0-9]|$)` в этом воркспейсе непригодна.\n' > "$b/$C12_REL"
run 0 "$b" "близнец: та же форма без вызова grep на строке — молчит" check-12-handrun-predicate-survives-both-greps.sh

b="$(mksandbox .claude)"
rm -rf "$b/scripts" "$b/CLAUDE.md"
run 2 "$b" "предпосылка: файлов области нет — VOID, а не успех" check-12-handrun-predicate-survives-both-greps.sh
# ═════════════════════════════════════════════════════════════════════════════
echo "== check-19: норма 2026-09-20 выпала из базы / отменённый маршрут стоит без пометки =="
#
# ПРЕДМЕТ ПРОБ — ДВЕ РАЗНЫЕ ОСИ ОДНОЙ ПРОВЕРКИ, и близнец есть у каждой. У оси
# «отменённый маршрут» близнец самый острый в наборе: дефект и близнец несут ОДНУ
# И ТУ ЖЕ формулировку отменённого маршрута, и отличает их ровно пометка отмены в
# той же строке. Без этого близнеца проверка запрещала бы корпусу вообще называть
# снятое решение — то есть запрещала бы раздел «противоречия, разрешённые в базе».
C19=check-19-landing-route-is-one-mr-per-wave.sh
BASE_REL=".claude/agents/dispatcher.md"
GIR_REL=".claude/rules/git-issues.md"

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C19"

# ось A: дословная цитата владельца выпала из базы маршрутизации
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/не забывай агрегировать мр = волна/порядок посадки описан выше/g' \
    "цитата «мр = волна» снята из базы"; then
    run 1 "$b" "инъекция: норма «МР равен волне» выпала из базы — краснеет" "$C19"
fi

# ось A': норма о сроке заведения задачи о безопасности выпала из правила
b="$(mksandbox)"
if mr_patch "$b/$GIR_REL" 's/gi-security-finding-issue-now/gi-security-finding-later/g' \
    "id нормы о немедленной задаче переименован"; then
    run 1 "$b" "инъекция: нормы «задача о безопасности немедленно» в правиле нет — краснеет" "$C19"
fi

# ось B: отменённый маршрут внесён как действующее основание
b="$(mksandbox)"
printf '%s\n' '- Посадка: PR прямо в `main` без накопительной ветки, слияние сразу по зелёному CI.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: отменённый маршрут стоит без пометки отмены — краснеет" "$C19"

# близнец оси B: ТА ЖЕ формулировка, но названная отменённой
b="$(mksandbox)"
printf '%s\n' '- Прежний маршрут «PR прямо в `main` без накопительной ветки» ОТМЕНЁН решением владельца 2026-09-20.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: тот же маршрут с пометкой отмены — молчит" "$C19"

# ось B': ТОТ ЖЕ отменённый порядок, записанный ДРУГИМИ СЛОВАМИ. Первая редакция
# распознавателя знала три формы записи и на этой молчала: восстановление снятого
# маршрута не давало ни красного, ни зелёного. Проба заведена перемером 2026-09-20.
b="$(mksandbox)"
printf '%s\n' '- Посадка: каждая полоса открывает свой PR в ствол и сливается сразу по зелёному CI.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: отменённый порядок пересказан («сразу по зелёному CI») — краснеет" "$C19"

b="$(mksandbox)"
printf '%s\n' '- Прежний порядок «каждая полоса открывает свой PR в ствол, слияние сразу по зелёному CI» ОТМЕНЁН 2026-09-20.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: тот же пересказ с пометкой отмены — молчит" "$C19"

# ось B'': ИМЯ снятого решения, поданное действующим. Дословная цитата — самый
# живучий носитель отменённого маршрута: переписать её нельзя, не потеряв ссылку
# на решение, поэтому она и взята литералом.
b="$(mksandbox)"
printf '%s\n' '- Маршрут посадки: заливай сразу в мастер — решение владельца 2026-09-17, действует.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: имя снятого решения подано действующим — краснеет" "$C19"

b="$(mksandbox)"
printf '%s\n' '- Решение 2026-09-17 «заливай сразу в мастер» ОТМЕНЕНО 2026-09-20 и основанием не служит.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: имя снятого решения с пометкой отмены — молчит" "$C19"

# ось B''': пометка отмены, стоящая в ОТРИЦАНИИ. Дефект и близнец отличаются
# ровно частицей «не»: первая редакция засчитывала «никто не отменял» за отмену и
# зеленела на строке, ПОДТВЕРЖДАЮЩЕЙ снятый маршрут.
b="$(mksandbox)"
printf '%s\n' '- Посадка: PR прямо в `main` без накопительной ветки — этого решения никто не отменял.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: пометка отмены стоит в отрицании — краснеет" "$C19"

b="$(mksandbox)"
printf '%s\n' '- Посадка: PR прямо в `main` без накопительной ветки — этот порядок ОТМЕНЁН 2026-09-20.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: та же строка, пометка в утверждении — молчит" "$C19"

# предпосылка оси B: арма распознавателя осталась без предмета. Дефект вносится
# НЕ в распознаватель, а в корпус: литерал перестаёт встречаться, и перечень
# молча становится уже своей шапки — ровно так в первой редакции жила арма
# `прямой PR`, не совпадавшая ни с одной строкой корпуса.
b="$(mksandbox)"
while IFS= read -r f; do
    mr_patch "$f" 's/без накопительной ветки/без ветки-сборки/g' "литерал выведен из корпуса" >/dev/null
done < <(grep -rlF 'без накопительной ветки' "$b/.claude" 2>/dev/null)
run 1 "$b" "предпосылка: литерал распознавателя без предмета в корпусе — краснеет" "$C19"

# близнец оси A: база правлена, но мимо предмета проверки
b="$(mksandbox)"
printf '%s\n' '- Посторонняя строка базы, предмета проверки не касающаяся.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: правка базы мимо предмета — молчит" "$C19"

# предпосылка: базы маршрутизации в дереве нет — VOID, а не «находок 0»
b="$(mksandbox .claude/agents/dispatcher.md)"
run 2 "$b" "предпосылка: базы маршрутизации нет — VOID, а не успех" "$C19"

echo "== check-11: решения за диспетчером, перечень владельцу закрыт тремя пунктами =="
#
# ПРЕДМЕТ ПРОБ — ДВЕ ОСИ. У оси «перечень закрыт» близнец несущий: дописанный
# АБЗАЦ внутри §11 законен (раздел объясняет форму сообщения), дописанный
# НУМЕРОВАННЫЙ ПУНКТ — нет, потому что именно им перечень исполнимо-невозможного
# превращают в лазейку. Без такого близнеца проверка запрещала бы §11 расти
# вообще, то есть запрещала бы объяснять норму.
C11=check-11-owner-escalation-list-is-closed.sh
CORE_REL=".claude/rules/00-kacho-core.md"
PROTO_REL="CLAUDE.md"
LEDGER11_REL="scripts/tooling-gate/owner-escalation-fingerprint.txt"

# ── ОСНАСТКА ОСИ D (отпечаток §11) ──────────────────────────────────────────
#
# d11_weaken — ОСЛАБЛЯЮЩАЯ ВСТАВКА В ЧИСТОМ ВИДЕ: абзац дописывается в конец
# §11, не трогая ни одной существующей буквы и не заводя нумерованного пункта.
# Именно поэтому оси A, B и C на ней молчат — и это не предположение, а то, что
# читает `d11_only_axis_d` из переписи самого гейта.
d11_weaken() {   # <песочница>
    python3 - "$1/$BASE_REL" <<'PY'
import re
import sys

p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if re.match(r"^## 11\.", l))
end = next((j for j in range(start + 1, len(lines)) if lines[j].startswith("## ")),
           len(lines))
last = max(i for i in range(start, end) if lines[i].strip())
lines[last + 1:last + 1] = [
    "",
    "Перечень выше — ориентир, а не закрытый список: при сомнении диспетчер "
    "спрашивает владельца.",
]
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}

# d11_paste — вписывает в песочницу ведомость ИЗ ВЫВОДА САМОГО ГЕЙТА, как есть,
# вместе с угловыми скобками. Своя реализация того же sha256 была бы ВТОРЫМ
# представлением предиката: разойдясь с гейтом, она доказывала бы собственную
# арифметику, а не его. Побочно проверяется, что напечатанные гейтом строки
# ГОДНЫ к вставке — находка, чей текст нельзя применить, посылает не туда.
d11_paste() {   # <песочница>
    local box="$1" out
    # 2>&1 — НЕ небрежность: готовые строки ведомости печатает ось D, а её вывод
    # при находке уходит в stderr вместе с самой находкой. Захват одного stdout
    # давал пустую ведомость и «узаконивание НЕ ИСПОЛНЕНО» на всех пробах разом.
    out="$(TOOLING_GATE_ROOT="$box" bash "$HERE/$C11" 2>&1 || true)"
    printf '%s\n' "$out" \
        | awk '/── ожидаемая ведомость целиком ──/ { f = 1; next } /^\[/ { f = 0 } f' \
        | sed 's/^  //' > "$box/$LEDGER11_REL"
    grep -q '^ИТОГО' "$box/$LEDGER11_REL"
}

# d11_legalize — УЗАКОНИВАНИЕ правки: вставленная ведомость плюс дата и
# основание вместо угловых скобок. Ровно тот поступок, который в дереве делает
# рецензент, и ровно он отличает дефект от законного близнеца оси D.
d11_legalize() {   # <песочница> <основание без косой черты>
    local box="$1" why="$2"
    if ! d11_paste "$box"; then
        probes=$((probes + 1))
        failed=$((failed + 1))
        echo "  ПРОВАЛ узаконивание НЕ ИСПОЛНЕНО ($why) — гейт не напечатал годной ведомости;" >&2
        echo "         вердикта у этой пробы нет, и зелёное здесь означало бы обратное" >&2
        return 1
    fi
    sed -i "s/<дата>/2026-09-21/; s/<основание>/$why/" "$box/$LEDGER11_REL"
}

# d11_only_axis_d — ОСТРИЁ пробы читается из ПЕРЕПИСИ гейта, а не предполагается:
# при сработавшей оси D перепись обязана показать все прочие якоря найденными
# (27 из 28 — не найден ровно отпечаток) и перечень целым (пунктов 3). Иначе
# красное пришло бы от соседней оси, и пара доказывала бы не тот предикат.
d11_only_axis_d() {   # <песочница> <что внесено>
    local box="$1" what="$2" out
    probes=$((probes + 1))
    out="$(TOOLING_GATE_ROOT="$box" bash "$HERE/$C11" 2>&1 || true)"
    case "$out" in
        *"нумерованных пунктов 3 при закрытом перечне 3"*"найдено 27"*)
            echo "  ok   остриё: $what — оси A, B, C молчат (якорей 27 из 28, пунктов 3), красное пришло от оси D"
            ;;
        *)
            echo "  ПРОВАЛ остриё: $what — перепись гейта не подтвердила, что сработала ТОЛЬКО ось D" >&2
            printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
            failed=$((failed + 1))
            ;;
    esac
}

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C11"

# ось A: дословная цитата требования 3 выпала из базы
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/Все решения принимаешь сам меня не спрашиваешь/решения принимаются по базе/g' \
    "цитата требования 3 снята из базы"; then
    run 1 "$b" "инъекция: цитата «Все решения принимаешь сам» выпала из базы — краснеет" "$C11"
fi

# ось A: ТЕЛО нормы ядра вывернуто при СОХРАНЁННОМ ключе.
#
# ПОЧЕМУ НЕ ПЕРЕИМЕНОВАНИЕ КЛЮЧА. Прежняя редакция этой пробы правила
# `s/ban18-criteria/ban18-questions/` и звала это «норма снята». Роняла она
# строку, которую сама же и вписывала в предикат: гейт искал ключ, проба ключ
# убирала — тавтология на собственной строке, а не проба класса. Настоящий класс
# другой и он ИЗМЕРЕН на этом дереве: ключ остаётся, тело переписывается на
# обратное по смыслу — и прежний гейт выходил НУЛЁМ, печатая «якорей 12 из 12».
#
# ПАРА ОДНОФАКТНАЯ. Дефект и близнец — оба ПОЛНАЯ переписка той же строки нормы
# с тем же ключом; отличаются ровно одним фактом: стоит ли на строке дословный
# фрагмент императива. Полярность утверждения в этот факт не входит — предикат
# гейта частицы «не» не ищет и о смысле строки не судит вовсе.
b="$(mksandbox)"
if mr_patch "$b/$CORE_REL" \
    's/^ban18-criteria · .*$/ban18-criteria · критерии продукта — ориентир; «нет» по одному из них поводом к отказу не служит и снимается обсуждением · вниманием · red: обсуждение не проведено/m' \
    "тело ban18-criteria вывернуто, ключ оставлен"; then
    run 1 "$b" "инъекция: тело нормы критериев вывернуто при сохранённом ключе — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$CORE_REL" \
    's/^ban18-criteria · .*$/ban18-criteria · всякое решение проходит критерии продукта, названные владельцем 2026-09-20. «Нет» на любом одном — ОТКАЗ; отказ снимается переделкой объёма, и решает это диспетчер · вниманием: предмет критерия — ЗАМЫСЕЛ · red: критерии не названы/m' \
    "строка ban18-criteria переписана, существо императива сохранено"; then
    run 0 "$b" "близнец: та же строка переписана, дословное существо на месте — молчит" "$C11"
fi

# ось A: дословная цитата требования 7 выпала из общего протокола. Она живёт в
# `CLAUDE.md`, а не в базе, потому что база упёрлась в свой потолок; адресата
# требование достаёт всё равно — протокол видят ОБА конца.
b="$(mksandbox)"
if mr_patch "$b/$PROTO_REL" 's/решения принимаешь ты на человеке не блокируемся/препятствие можно объявить исходом/g' \
    "цитата требования 7 снята из общего протокола"; then
    run 1 "$b" "инъекция: цитата «на человеке не блокируемся» выпала из протокола — краснеет" "$C11"
fi

# ось A: снята норма, удерживающая ОБХОД в границах безопасности. Без неё
# требование 7 читается как разрешение обходить защиту — и это не редакционная
# потеря, а ровно тот дефект, ради которого норма писалась отдельной строкой.
# Дефект — ДОСЛОВНО тот, которым находка была доказана 2026-09-20: тело нормы
# заменено текстом, прямо разрешающим снятие защиты ствола и отправку без хука,
# ключ оставлен нетронутым. Прежний гейт на нём молчал.
b="$(mksandbox)"
if mr_patch "$b/$CORE_REL" \
    's/^ban18-workaround-is-not-a-breach · .*$/ban18-workaround-is-not-a-breach · обход защиты ствола допустим, отправка без хука допустима, утверждение ослабляется ради зелёного · вниманием · red: полоса встала/m' \
    "тело ban18-workaround-is-not-a-breach вывернуто, ключ оставлен"; then
    run 1 "$b" "инъекция: тело нормы «обход среди БЕЗОПАСНЫХ способов» вывернуто при сохранённом ключе — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$CORE_REL" \
    's/^ban18-workaround-is-not-a-breach · .*$/ban18-workaround-is-not-a-breach · обход ищется СРЕДИ безопасных способов, а не вместо безопасности: отклонённый средой способ обходом НЕ считается и не повторяется · вниманием · red: тот же отклонённый способ повторён/m' \
    "строка ban18-workaround-is-not-a-breach сокращена, существо императива сохранено"; then
    run 0 "$b" "близнец: та же строка сокращена, дословное существо на месте — молчит" "$C11"
fi

# ось A': ОГРАНИЧИТЕЛЬ клаузулы давления снят из общего протокола, сама клаузула
# оставлена. Ровно этот разрыв и был находкой: до правки обе половины набора
# оставались зелёными (код 0), а `CLAUDE.md` стоял в 17 Б от своего потолка —
# то есть оговорка была первым кандидатом на снятие «как дублирующая ядро».
# Близнец однофактный: из ТОГО ЖЕ абзаца убрано СОСЕДНЕЕ предложение, удержанное
# ядром (`ban18-three-outcomes-at-obstacle`), а литерал ограничителя оставлен.
b="$(mksandbox)"
if mr_patch "$b/$PROTO_REL" 's/Обход ищут СРЕДИ.*?не повторяется\.//s' \
    "ограничитель «обход СРЕДИ безопасных способов» снят из протокола"; then
    run 1 "$b" "инъекция: клаузула давления осталась без своего ограничителя — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$PROTO_REL" 's/Одна попытка перебором не является;.*?исход\. //s' \
    "из того же абзаца снято соседнее предложение, ограничитель оставлен"; then
    run 0 "$b" "близнец: из того же абзаца снято соседнее предложение, ограничитель на месте — молчит" "$C11"
fi

# ось A, близнец ТОЙ ЖЕ формы: протокол правлен мимо предмета проверки. Без него
# проверка запрещала бы `CLAUDE.md` расти вообще.
b="$(mksandbox)"
printf '%s\n' '- Посторонняя строка протокола, предмета проверки не касающаяся.' >> "$b/$PROTO_REL"
run 0 "$b" "близнец: протокол правлен мимо предмета — молчит" "$C11"

# ось A: число ёмкости снято — «планируй по расходу» без расхода остаётся лозунгом
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/300–500 тысяч токенов, измерено по одиннадцати полосам и семи воркфлоу одной сессии/столько токенов, сколько нужно/g' \
    "число расхода на полосу снято из базы"; then
    run 1 "$b" "инъекция: расход полосы назван без числа и без объёма замера — краснеет" "$C11"
fi

# ось A, близнец: база правлена мимо предмета проверки
b="$(mksandbox)"
printf '%s\n' '- Посторонняя строка базы, предмета проверки не касающаяся.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: правка базы мимо предмета — молчит" "$C11"

# ── ось C: постулаты владельца ──────────────────────────────────────────────
#
# ПАРЫ ОДНОФАКТНЫЕ, И ФАКТ НАЗВАН У КАЖДОЙ. Полярность утверждения ни в один из
# этих фактов не входит: предикат частиц не ищет и о смысле строки не судит.
#
# Пара 1 — факт: стоит ли постулат 4 ДОСЛОВНО, с орфографией владельца. Дефект
# выправляет две буквы («приритет», «разглогольствование») и не трогает ничего
# больше; близнец правит ТУ ЖЕ строку тем же объёмом — переписывает пояснение
# рядом с цитатой, — а саму цитату оставляет. Выправленная орфография и есть
# подмена решения: постулат — цитата, а не наш текст.
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/4-й постулат приритет на фичи а не разглогольствование!/4-й постулат приоритет на фичи, а не разглагольствование!/' \
    "орфография постулата 4 выправлена, смысл сохранён"; then
    run 1 "$b" "инъекция: постулат 4 процитирован с выправленной орфографией — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/Слова владельца 2026-09-20, ДОСЛОВНО и без правки орфографии — это цитаты РЕШЕНИЙ, а не наш текст; правка буквы здесь равна подмене решения:/Четыре постулата ниже — слова владельца, записанные 2026-09-20 как есть:/' \
    "пояснение над постулатами переписано, сами цитаты не тронуты"; then
    run 0 "$b" "близнец: переписано пояснение над постулатами, цитаты дословны — молчит" "$C11"
fi

# Пара 2 — факт: объявлено ли СТАРШИНСТВО. Дефект снимает одно предложение из
# абзаца «СТАРШИНСТВО ОБЪЯВЛЕНО»; близнец снимает из ТОГО ЖЕ абзаца СОСЕДНЕЕ
# предложение той же длины, объявление оставляя. Оба — удаление предложения из
# одного абзаца; различие ровно одно.
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/При расхождении текста с постулатом действует ПОСТУЛАТ, а расходящийся текст подлежит ПРАВКЕ, а не толкованию: //' \
    "объявление старшинства снято, абзац оставлен"; then
    run 1 "$b" "инъекция: старшинство постулатов не объявлено — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/Расхождение — находка: предмет отдаётся `tooling-maintainer` отдельной полосой ПО ХОДУ, а не копится к концу волны\.//' \
    "из того же абзаца снято соседнее предложение, объявление старшинства оставлено"; then
    run 0 "$b" "близнец: из того же абзаца снято соседнее предложение, старшинство объявлено — молчит" "$C11"
fi

# Пара 3 — факт: стоит ли блок ПЕРВЫМ разделом. Дефект переносит §0 целиком вниз,
# за §1, не меняя в нём ни байта: все пять литералов оси C остаются на месте, и
# ловит его ТОЛЬКО обход заголовков. Близнец переносит тот же блок тем же приёмом
# внутрь самого себя — абзацы §0 переставлены местами, — и §0 остаётся первым.
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/(## 0\. ПОСТУЛАТЫ.*?)(\n## 1\. .*?)(\n## 2\. )/$2\n$1$3/s' \
    "блок постулатов перенесён за §1, текст блока не тронут"; then
    run 1 "$b" "инъекция: постулаты стоят не первыми при дословном тексте — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/(## 0\. ПОСТУЛАТЫ ВЛАДЕЛЬЦА[^\n]*\n\n)(Слова владельца[^\n]*\n\n)((?:\d\. «[^\n]*\n)+)/$1$3\n$2/s' \
    "внутри §0 переставлены абзацы, блок остался первым"; then
    run 0 "$b" "близнец: абзацы внутри §0 переставлены, блок первый — молчит" "$C11"
fi

# Пара 4 — факт: стоит ли ОГРАНИЧИТЕЛЬ четвёртого постулата. Дефект снимает
# оговорку целиком, клаузулу давления («выигрывает полоса, меняющая продукт»)
# оставляя: ровно тот разрыв, ради которого заведена ось A'. Близнец снимает
# СОСЕДНЕЕ предложение того же абзаца — второе, про сокращение разговора, — а
# литерал оговорки оставляет.
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/«приоритет на фичи» НЕ отменяет приёмку до кода, честный красный, пробы в том же изменении и запрет заглушек\. //' \
    "оговорка четвёртого постулата снята, клаузула давления оставлена"; then
    run 1 "$b" "инъекция: «приоритет на фичи» остался без своего ограничителя — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/Скорость достигается сокращением РАЗГОВОРА, а не сокращением доказательств; «быстрее к фиче» основанием для заглушки, happy-path и отложенной пробы не является\.//' \
    "из того же абзаца снято соседнее предложение, оговорка оставлена"; then
    run 0 "$b" "близнец: из того же абзаца снято соседнее предложение, оговорка на месте — молчит" "$C11"
fi

# ось B: ЧЕТВЁРТЫЙ пункт перечня — та самая лазейка
b="$(mksandbox)"
# Отпечаток §11 (ось D) узаконивается ТЕМ ЖЕ изменением — иначе красное пришло
# бы от него, и пара судила бы не счёт пунктов, а сам факт правки раздела.
if mr_patch "$b/$BASE_REL" 's/(3\. действие, отклонённое ограничением среды)/4. решение, которое дорого принять неверно: стратегический выбор, спорный вердикт, снятие гейта;\n$1/' \
    "в §11 дописан четвёртый пункт перечня"; then
    if d11_legalize "$b" "проба инъекции: правка §11 узаконена в том же изменении"; then
        run 1 "$b" "инъекция: перечень вырос до четырёх пунктов при УЗАКОНЕННОМ отпечатке — краснеет осью B" "$C11"
    fi
fi

# ось B, близнец ТОЙ ЖЕ формы: тот же текст, но абзацем, а не пунктом перечня.
# Раздел вправе расти объяснением; закрыт именно ПЕРЕЧЕНЬ.
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/(3\. действие, отклонённое ограничением среды)/Решение, которое дорого принять неверно, поводом обратиться НЕ является: его принимает диспетчер.\n\n$1/' \
    "в §11 дописан абзац той же темы"; then
    if d11_legalize "$b" "проба инъекции: правка §11 узаконена в том же изменении"; then
        run 0 "$b" "близнец: та же тема абзацем, а не пунктом перечня, отпечаток узаконен — молчит" "$C11"
    fi
fi

# ось B: пункт перечня ВЫПАЛ — обратная порча, ловится тем же предикатом
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/^1\. доступ или учётные данные[^\n]*\n//m' \
    "первый пункт перечня снят"; then
    if d11_legalize "$b" "проба инъекции: правка §11 узаконена в том же изменении"; then
        run 1 "$b" "инъекция: пункт перечня выпал при УЗАКОНЕННОМ отпечатке — краснеет осью B" "$C11"
    fi
fi

# предпосылка: базы маршрутизации в дереве нет — VOID, а не «находок 0»
b="$(mksandbox .claude/agents/dispatcher.md)"
run 2 "$b" "предпосылка: базы маршрутизации нет — VOID, а не успех" "$C11"

# ── ОСЬ D: ОТПЕЧАТОК §11 ────────────────────────────────────────────────────
#
# ОСТРИЁ ПАРЫ. Дефект и близнец вносят В §11 ОДНУ И ТУ ЖЕ ослабляющую строку и
# отличаются ровно одним фактом: узаконен ли новый отпечаток тем же изменением.
# Класс тот, ради которого ось заведена: ослабление есть ДОБАВЛЕНИЕ текста, и
# предикат на присутствии подстроки к нему слеп by construction.
b="$(mksandbox)"
d11_weaken "$b"
d11_only_axis_d "$b" "в §11 дописан абзац «перечень — ориентир»"
run 1 "$b" "инъекция: §11 ослаблен дописанным абзацем, отпечаток НЕ узаконен — краснеет" "$C11"

# Близнец. «Молчит» здесь значит «правку УЗАКОНИЛИ», а не «правка безопасна»:
# ослабление от усиления машина не отличает, вердикт о существе выносит
# рецензент, и узаконивание — его поступок, видимый в диффе строкой ведомости.
b="$(mksandbox)"
d11_weaken "$b"
if d11_legalize "$b" "проба инъекции: ослабляющий абзац узаконен рецензентом"; then
    run 0 "$b" "близнец: та же вставка, отпечаток узаконен тем же изменением — молчит" "$C11"
fi

# ГРАНИЦА УЗАКОНИВАНИЯ. Новый отпечаток со СТАРЫМ основанием — находка. Дефект
# измерен на снятом `scripts/rules-gate/check-10`: там основание судилось НА
# ПРИСУТСТВИЕ, и ведомость начинала нести утверждение, пережившее свой предмет,
# — узаконивание превращалось в ритуал. Старая строка берётся ИЗ ПЕСОЧНИЦЫ, а не
# выписывается литералом: литерал устарел бы вместе с деревом.
b="$(mksandbox)"
sanction_old="$(grep -m1 '^# узаконено:' "$b/$LEDGER11_REL")"
d11_weaken "$b"
if [ -n "$sanction_old" ] && d11_legalize "$b" "проба инъекции: основание будет оставлено прежним"; then
    python3 - "$b/$LEDGER11_REL" "$sanction_old" <<'PY'
import sys

p, old = sys.argv[1], sys.argv[2]
kept = [l for l in open(p, encoding="utf-8").read().split("\n")
        if not l.startswith("# узаконено:")]
open(p, "w", encoding="utf-8").write("\n".join([old] + kept))
PY
    run 1 "$b" "инъекция: отпечаток обновлён, основание оставлено прежним — краснеет" "$C11"
elif [ -z "$sanction_old" ]; then
    probes=$((probes + 1))
    failed=$((failed + 1))
    echo "  ПРОВАЛ инъекция НЕ ВНЕСЕНА (старое основание) — в ведомости песочницы нет строки «# узаконено:»" >&2
fi

# ВЕДОМОСТЬ ВСТАВЛЕНА НЕ ГЛЯДЯ: угловые скобки остались на месте. Гейт печатает
# готовые строки хешей — и обязан отказать тому, кто скопировал их целиком, не
# вписав ни даты, ни основания. Иначе поступок снова стал бы побочным эффектом.
b="$(mksandbox)"
d11_weaken "$b"
if d11_paste "$b"; then
    run 1 "$b" "инъекция: ведомость скопирована как есть, с угловыми скобками — краснеет" "$C11"
else
    probes=$((probes + 1))
    failed=$((failed + 1))
    echo "  ПРОВАЛ инъекция НЕ ВНЕСЕНА (вставка не глядя) — гейт не напечатал ведомости" >&2
fi

# НОСИТЕЛЬ ГЕЙТА СНИМАЮТ ВМЕСТЕ С ГЕЙТОМ, А НЕ ОТДЕЛЬНО: ведомости нет — находка,
# а не тишина. Самый дешёвый способ погасить ось иначе — удалить её ожидание.
b="$(mksandbox "$LEDGER11_REL")"
run 1 "$b" "инъекция: ведомость отпечатка удалена — краснеет, а не молчит" "$C11"

# Близнец ТОЙ ЖЕ формы: правка ведомости МИМО ожидания — комментарий в шапке.
# Без него ось запрещала бы ведомости нести пояснение вообще.
b="$(mksandbox)"
printf '%s\n' '# Посторонняя строка ведомости, ожидания не меняющая.' >> "$b/$LEDGER11_REL"
run 0 "$b" "близнец: в ведомость дописан комментарий, ожидание то же — молчит" "$C11"


# предпосылка: общего протокола в дереве нет — тоже VOID. Он стал ТРЕТЬИМ
# прочитанным файлом, и его отсутствие обязано давать «читать не в чем», а не
# «якорь не найден»: иначе дерево без `CLAUDE.md` выдало бы находку о норме,
# которой негде быть.
b="$(mksandbox CLAUDE.md)"
run 2 "$b" "предпосылка: общего протокола нет — VOID, а не находка" "$C11"

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
