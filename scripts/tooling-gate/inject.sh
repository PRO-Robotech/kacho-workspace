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
# Каждая проба получает СВОЮ свежую песочницу, и на диске живёт ОДНА песочница за
# раз: следующая `mksandbox` снимает предыдущую, последнюю снимает перепись в
# конце. Восстановление мутаций через git в песочнице без единого коммита
# требовало бы заводить в ней личность коммиттера, а личность в этом проекте не
# переопределяют, — поэтому песочница именно новая, а не восстановленная.
#
# Песочница — КОПИЯ ОБРАЗЦА, собранного один раз, а не новая выкладка дерева.
# Цена пробы до ws#865 была пропорциональна размеру дерева (tar всех файлов,
# `git init`, `git add -A -f` — хеширование каждого файла заново: бо́льшая часть
# цены пробы), а число проб растёт с каждой проверкой; уборка ловушкой в конце
# снимала ВСЕ песочницы разом и на ранере заняла 2:49 на полутора сотнях проб.
# Задание `tooling-gate` тогдашнего `ci.yaml` дошло до своего предела и снималось
# без вердикта (замер — в коммите 17f97991).
#
# Перепись проб печатается в конце: «все зелёные» без числа проб — то же
# «ноль находок против ноль прочитанного», от которого набор и защищает.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/../.." && pwd)"

# Окружение — своё (scripts/lib/proofs.sh, ws#757): унаследованный указатель на
# дерево (`KACHO_HOME_*`, `GATE_ROOT`, `<НАБОР>_GATE_ROOT`) сильнее песочницы, и
# вердикт зависел бы от того, кто запустил доказательство. Корень пробы задаёт
# `run` на своём вызове (`TOOLING_GATE_ROOT`).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$HERE/../lib/proofs.sh"
proof_own_environment

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ОБРАЗЕЦ ПЕСОЧНИЦ. Рабочие файлы — `$TPL`, индекс и объекты — `$TPL_GIT`
# отдельно от них: копия образца не несёт чужого `.git`, а объекты песочница
# читает через `objects/info/alternates`, не копируя их. Индекс копируется
# файлом — он и есть результат `git add -A -f`, который прежде считался заново
# в каждой пробе. Содержимое индекса песочницы то же, что давал её собственный
# `git add -A -f` (сверено `git ls-files -s` по всем выбрасываемым путям этого
# файла); иные у него только сведения `stat` — копия получает свои inode и ctime.
# Фарфоровые команды (`status`, `diff`, `add`) освежают их сами ценой
# хеширования; плюмбинг без освежения (`diff-files`) увидел бы в песочнице
# изменённым КАЖДЫЙ файл. Таких потребителей в пробируемых проверках нет, а
# появившийся не пройдёт незамеченным: у каждой проверки есть проба чистого
# дерева, и она покраснеет. Освежать индекс заранее — 0,16 с на песочницу за
# свойство, которого никто не читает.
TPL="$TMP/template"
TPL_GIT="$TMP/template.git"
tplgit() { git --no-optional-locks --git-dir="$TPL_GIT" --work-tree="$TPL" "$@"; }

# Причина, по которой песочницы судили бы не то дерево, пишется в
# `$TMP/INCOMPLETE`; `run` читает её ДО пробы и отвечает VOID. Файл общий потому,
# что `mksandbox` исполняется в подоболочке и переменную наружу не вернёт.
premise_broken() { [ -e "$TMP/INCOMPLETE" ] || printf '%s\n' "$1" > "$TMP/INCOMPLETE"; }

# mktemplate — собирает образец один раз, до первой пробы.
#
# Состав берётся ровно тем же предикатом, что и у самих проверок:
# `--cached --others --exclude-standard`. Ещё не закоммиченный, но и не
# игнорируемый файл обязан попасть в песочницу — иначе проба доказывала бы
# свойство дерева, которого в момент правки не существует.
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
# неполноты не зависит (место на диске, отказ tar или cp, новое дробление):
# сколько файлов запрошено, столько обязано доехать — и в образец, и в КАЖДУЮ
# его копию.
# Способность этого стража заговорить доказывается СНАРУЖИ, без ручек в коде —
# подменой tar на урезающий:
#     d=$(mktemp -d); printf '%s\n' '#!/bin/sh' \
#       'case "$1" in cf) shift; exec /usr/bin/tar --exclude=README.md -c -f "$@";; esac' \
#       'exec /usr/bin/tar "$@"' > "$d/tar"; chmod +x "$d/tar"
#     PATH="$d:$PATH" bash scripts/tooling-gate/inject.sh   # ждём код 2 и [VOID]
mktemplate() {
    local got
    mkdir -p "$TPL"
    ( cd "$WS" && git ls-files --cached --others --exclude-standard -z \
        | tar cf - --null --files-from=- ) \
        | ( cd "$TPL" && tar xf - )
    SANDBOX_FILES="$( cd "$WS" && git ls-files --cached --others --exclude-standard | wc -l )"
    got="$( cd "$TPL" && find . \( -type f -o -type l \) | wc -l )"
    if [ "$SANDBOX_FILES" -ne "$got" ]; then
        premise_broken "песочница неполна: запрошено файлов $SANDBOX_FILES, доехало $got"
    fi
    if ! { tplgit init -q && tplgit add -A -f >/dev/null 2>&1; }; then
        premise_broken "индекс образца песочниц не собран: git init/add над образцом отказали"
    fi
    TPL_DIRS="$( find "$TPL" -type d | wc -l )"
}

# ОБРАЗЕЦ НЕПРИКОСНОВЕНЕН, и это проверяется перед каждой копией: проба, чья
# запись дошла до образца (копия ссылками вместо файлов, ошибка в пути), отдала
# бы свою мутацию ВСЕМ следующим пробам — тот же класс, что песочница `s1` на
# всех (2026-08-19), только тише. Изменённый или удалённый отслеживаемый файл
# видит `diff-files` — по сведениям `stat` и без освежения, поэтому находка уже
# сама ссылка на файл образца (она меняет его ctime), до первой записи через неё;
# новый файл — `ls-files --others` (в образце всё внесено `-f`, поэтому
# неотслеживаемого в нём не бывает), новый каталог — счёт каталогов. Чтение
# образца копией его `stat` не меняет — ни одного срабатывания на исправном
# прогоне. Страж доказывается снаружи подменой cp на копирующий ссылками:
#     d=$(mktemp -d); printf '%s\n' '#!/bin/sh' 'exec /usr/bin/cp -l "$@"' > "$d/cp"
#     chmod +x "$d/cp"; PATH="$d:$PATH" bash scripts/tooling-gate/inject.sh   # код 2, [VOID]
template_intact() {
    tplgit diff-files --quiet >/dev/null 2>&1 || return 1
    [ -z "$(tplgit ls-files --others)" ] || return 1
    [ "$( find "$TPL" -type d | wc -l )" -eq "$TPL_DIRS" ]
}

# live_mark — сколько песочниц на диске СЕЙЧАС; максимум за прогон — в $TMP/MAXLIVE.
live_mark() {
    local live max
    live="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name 's*' | wc -l)"
    max="$(cat "$TMP/MAXLIVE" 2>/dev/null || echo 0)"
    [ "$live" -gt "$max" ] && printf '%s' "$live" > "$TMP/MAXLIVE"
    return 0
}

# drop_current — снимает песочницу, выданную последней.
drop_current() {
    local prev
    prev="$(cat "$TMP/CURRENT" 2>/dev/null || true)"
    [ -n "$prev" ] && rm -rf "$prev"
    rm -f "$TMP/CURRENT"
}

# mksandbox [путь-который-выбросить] — печатает путь свежей песочницы.
#
# Каталог берётся `mktemp`, а НЕ счётчиком: `b="$(mksandbox)"` исполняет функцию в
# ПОДОБОЛОЧКЕ, поэтому счётчик в ней увеличивался и терялся — все пробы получали
# одну и ту же песочницу `s1`. Разворачивание архива поверх чинило только
# ОТСЛЕЖИВАЕМЫЕ файлы, а внесённый пробой НОВЫЙ файл переживал её и приезжал в
# следующую. Обнаружено 2026-08-19 первой же пробой, которая вносит дефект новым
# файлом (check-05): она получала находку предыдущей пробы и падала на исправном
# дереве. Шапка при этом обещала обратное — «каждая проба получает СВОЮ свежую
# песочницу»: комментарий против кода, и верным был комментарий.
#
# ПРЕДЫДУЩАЯ ПЕСОЧНИЦА СНИМАЕТСЯ ЗДЕСЬ, а не в `run`: одну песочницу судят
# несколькими пробами подряд (сосед на той же инъекции), и `run` не знает,
# последняя ли она. Песочницы в этом файле живут строго по одной: проба, которой
# понадобились бы две сразу, получит снятую первую и покраснеет, а не пройдёт.
mksandbox() {
    local drop="${1:-}"
    local dir got
    drop_current
    template_intact || premise_broken "образец песочниц изменён после пробы №$probes: следующие пробы получили бы её мутацию"
    dir="$(mktemp -d "$TMP/sXXXXXX")"
    printf '%s' "$dir" > "$TMP/CURRENT"
    live_mark
    cp -a "$TPL/." "$dir/" || premise_broken "копия образца песочниц не собрана: cp отказал"
    # Счёт снимается ДО `drop` и ДО `git init`: первый выбрасывает путь намеренно,
    # второй заводит собственные файлы, и оба сделали бы сверку бессмысленной.
    got="$( cd "$dir" && find . \( -type f -o -type l \) | wc -l )"
    if [ "$SANDBOX_FILES" -ne "$got" ]; then
        premise_broken "песочница неполна: запрошено файлов $SANDBOX_FILES, доехало $got"
    fi
    { git -C "$dir" init -q \
        && cp "$TPL_GIT/index" "$dir/.git/index" \
        && printf '%s\n' "$TPL_GIT/objects" > "$dir/.git/objects/info/alternates"; } \
        || premise_broken "индекс песочницы не собран: git init, копия индекса или alternates отказали"
    # Выброшенный путь уходит и с диска, и из индекса: прежде индекс собирался
    # ПОСЛЕ удаления и выброшенного не знал — ровно так и сейчас.
    if [ -n "$drop" ]; then
        rm -rf "${dir:?}/$drop"
        git -C "$dir" --literal-pathspecs rm -r -q --cached --ignore-unmatch -- "$drop" \
            >/dev/null 2>&1 \
            || premise_broken "выброшенный путь '$drop' остался в индексе песочницы"
    fi
    printf '%s' "$dir"
}

mktemplate

probes=0
failed=0

# run <ожидаемый-код> <песочница> <имя-пробы> <скрипт>
#
# `TOOLING_GATE_REQUIRED_CONTEXTS` пробрасывается из окружения вызова: сетевую
# половину check-05 доказываем ОФЛАЙН, задав перечень контекстов извне. Ходить за
# ним в сеть из доказательства нельзя — у токена ранера нет права читать защиту
# ветки, и проба стала бы «не выполнилось», поданным как зелёное.
premise_or_void() {
    if [ -e "$TMP/INCOMPLETE" ]; then
        echo "[VOID] inject — $(cat "$TMP/INCOMPLETE")" >&2
        echo "       вердикта нет НИ У ОДНОЙ пробы: они судили бы не то дерево." >&2
        echo "[CENSUS] inject: проб исполнено $probes, до срыва предпосылки" >&2
        exit 2
    fi
}

run() {
    local want="$1" box="$2" name="$3" script="$4" got out
    # Песочница — предпосылка пробы, а не её предмет. Собралась неполно —
    # исход у прогона ТРЕТИЙ: вердикта нет ни у одной пробы, включая прошедшие,
    # и объявлять это находкой о дереве значит послать читателя искать дефект
    # там, где его нет (`testing.md` §«Чтение вердикта», п.2).
    premise_or_void
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

# Форма, которую разбор ОБРЕЗАЕТ, прежде чем судить: хвостовая пунктуация прозы и
# экранирующая косая бэктика внутри двойных кавычек шага. Разбор переписан без
# запуска процесса на слово (ws#865), и обрезка стала встроенной — пробы держат её
# независимо от того, есть ли такая форма в живом `ci.yaml` сегодня. Близнец и
# инъекция отличаются ровно существованием пути, пунктуация у них одна.
b="$(mksandbox)"
printf '        run: echo "\\`./bootstrap.sh\\` и ./sync-all.sh.:\\"\n' >> "$b/$WF_REL"
run 0 "$b" "близнец: существующий путь в хвостовой пунктуации и экранированных бэктиках — молчит" \
    check-01-workflow-paths.sh

b="$(mksandbox)"
printf '        run: echo "\\`./bootstrap.sh\\` и ./no-such-file.sh.:\\"\n' >> "$b/$WF_REL"
run 1 "$b" "инъекция: отсутствующий путь в той же пунктуации — краснеет" check-01-workflow-paths.sh

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

# wf_set_on <песочница> <новый блок on> — заменяет ЦЕЛИКОМ объявление `on:`
# живого ci.yaml в песочнице. Целиком, а не вставкой перед известной строкой:
# вставка, чей образец перестал совпадать, была бы пустой операцией, и проба
# судила бы дерево как есть (так было с `on:\n  workflow_dispatch:` после
# решения владельца 2026-10-01). Не нашёлся блок — провал пробы, а не тишина.
wf_set_on() {
    local box="$1" block="$2"
    if ! WF_ON="$block" python3 - "$box/.github/workflows/ci.yaml" <<'PYWF'
import os
import re
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s, n = re.subn(r"^on:\n(?:[ \t]+\S.*\n)+", os.environ["WF_ON"], s, count=1, flags=re.M)
if n != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s)
PYWF
    then
        probes=$((probes + 1)); failed=$((failed + 1))
        echo "  ПРОВАЛ фикстура НЕ ВНЕСЕНА: блок on: в ci.yaml песочницы не найден" >&2
        return 1
    fi
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

# Фикстура САМА задаёт сужённый триггер, а не полагается на то, что стоит в дереве:
# объявление менялось решениями владельца (2026-09-20 снято, 2026-10-01 возвращено),
# и проба, зависящая от него, доказывала бы то одну ось, то соседнюю.
b="$(mksandbox)"
# Требуемые контексты ВЫВЕДЕНЫ из процесса песочницы, а не выписаны: выписанное
# имя задания стареет при первой правке конвейера, и близнец краснел бы от
# переименования, а не от предмета (так и случилось, когда задания наборов
# свели в одно — ws#753). Триггер же задаёт сама фикстура — заменой блока `on:`
# целиком (`wf_set_on`), а не вставкой перед известной строкой: такая вставка
# стала пустой операцией, когда триггеры вернулись в дерево (2026-10-01).
ctx="$(python3 -c 'import sys,yaml; j=yaml.safe_load(open(sys.argv[1]))["jobs"]; print("\n".join((v.get("name") or k) for k, v in list(j.items())[:2]))' "$b/.github/workflows/ci.yaml")"
wf_set_on "$b" $'on:\n  pull_request:\n    branches: [main]\n  workflow_dispatch:\n' &&
TOOLING_GATE_REQUIRED_CONTEXTS="$ctx" \
    run 0 "$b" "близнец: триггер сужен, все требуемые контексты производятся — молчит" check-05-workflow-triggers-narrowed.sh

# ОПАСНАЯ СТОРОНА «АВТОЗАПУСКА НЕТ»: контекст, которого никто не начинает,
# остаётся «ожидается» и блокирует слияние НАВСЕГДА. Фикстура сама снимает
# триггеры до ручного (с 2026-10-01 в дереве они есть), извне задан непустой
# перечень обязательных контекстов.
b="$(mksandbox)"
wf_set_on "$b" $'on:\n  workflow_dispatch:\n' &&
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

# ── ось ws#464: ВТОРАЯ установка перебивает пин ─────────────────────────────
#
# Дефект — дословно шаг, стоявший в задании vault-gate: пин поставлен, а шаг
# линта начинается с `apt-get install shellcheck`, то есть ставит версию
# дистрибутива в /usr/bin. Пин действует только потому, что /usr/local/bin
# раньше в PATH, — это не свойство, которое кто-то решал. Близнецы: одна
# пиннутая установка; установка «только при отсутствии» (под `command -v`),
# которая рядом с пином не срабатывает никогда. Исход читается вместе с ТЕКСТОМ:
# покраснеть по чужой причине — не доказательство.
run6t() { # run6t <код> <песочница> <имя пробы> <обязательная подстрока>
    local want="$1" box="$2" name="$3" needle="$4" got out
    probes=$((probes + 1))
    out="$(TOOLING_GATE_ROOT="$box" bash "$HERE/check-06-shellcheck-version-pinned.sh" 2>&1)"; got=$?
    if [ "$got" -eq "$want" ] && grep -qF -- "$needle" <<<"$out"; then
        echo "  ok   $name (код $got)"
    else
        echo "  ПРОВАЛ $name — ждали код $want и «$needle», получили $got" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
    fi
}

run6t 0 "$(mk6 "$WF_PINNED")" "близнец: одна пиннутая установка — молчит, установки сочтены" \
    "установок осмотрено 1 (пиннутых 1, прочих 0"

run6t 1 "$(mk6 "env:
  SHELLCHECK_VERSION: \"0.11.0\"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
$PIN_STEP
      - name: shellcheck vault-gate (strict)
        run: sudo apt-get update -qq && sudo apt-get install -y shellcheck && shellcheck -x -- a.sh
")" "инъекция: пин плюс apt-get install shellcheck в шаге линта — находка" \
    "ставит анализатор ВТОРЫМ способом"

run6t 0 "$(mk6 "env:
  SHELLCHECK_VERSION: \"0.11.0\"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
$PIN_STEP
      - name: install shellcheck
        run: |
          if command -v shellcheck > /dev/null; then
            exit 0
          fi
          sudo apt-get update -qq && sudo apt-get install -y shellcheck
      - run: shellcheck -x a.sh
")" "близнец: установка только при отсутствии рядом с пином — молчит" \
    "условных 1"


# Круг 1: вторая установка в двух формах проходила молча — многострочная с
# `\`-переносом (обычная форма блока `run: |`) и через npm (менеджера не было в
# перечне). Близнец многострочной — перенос, после которого стоит ДРУГОЙ пакет,
# а анализатор только зовётся следующей командой.
run6t 1 "$(mk6 "env:
  SHELLCHECK_VERSION: \"0.11.0\"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
$PIN_STEP
      - name: зависимости линта
        run: |
          sudo apt-get install -y \\
            shellcheck
      - run: shellcheck -x a.sh
")" "инъекция: пин плюс многострочная apt-get install … \\ shellcheck — находка" \
    "ставит анализатор ВТОРЫМ способом"

run6t 1 "$(mk6 "env:
  SHELLCHECK_VERSION: \"0.11.0\"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
$PIN_STEP
      - run: npm install -g shellcheck && shellcheck -x a.sh
")" "инъекция: пин плюс npm install -g shellcheck — находка" \
    "ставит анализатор ВТОРЫМ способом"

run6t 0 "$(mk6 "env:
  SHELLCHECK_VERSION: \"0.11.0\"
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
$PIN_STEP
      - name: зависимости линта
        run: |
          sudo apt-get install -y \\
            bats
          shellcheck -x a.sh
")" "близнец: многострочная установка другого пакета, анализатор только зовётся — молчит" \
    "прочих 0"

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
# Распознаватель доказательства DoD — общий файл, который подключают и
# merge-readiness, и cascade-census (ws#930): порча маркера вносится в него.
DOD_REL="scripts/lib/dod_proof.jq"

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

C09=check-09-merge-readiness-tells-three-outcomes-apart.sh
C09_NAME="${C09%.sh}"

# run_c09_red <песочница> <имя-пробы> <метка>... — код 1 набора И покраснение
# ИМЕННО держащей пробы. Код 1 сам по себе говорит лишь «что-то покраснело»:
# порча одного решения, пойманная соседней пробой по случайному совпадению,
# оставила бы само решение без держателя, и следующая правка соседа сняла бы
# защиту молча. Метка — `[<случай>]` в начале имени пробы check-09.
run_c09_red() {
    local box="$1" name="$2"; shift 2
    local out got tag missing=""
    if [ -e "$TMP/INCOMPLETE" ]; then
        run 1 "$box" "$name" "$C09"   # тот же срыв предпосылки, тем же путём
        return
    fi
    probes=$((probes + 1))
    out="$(TOOLING_GATE_ROOT="$box" bash "$HERE/$C09" 2>&1)"; got=$?
    for tag in "$@"; do
        # Не труба в `grep -q`: под pipefail он, выйдя на первом совпадении,
        # роняет пишущий printf по SIGPIPE, когда вывод больше буфера трубы, —
        # и найденная метка читалась как ненайденная (замерено 2026-09-30: [E]
        # [F] [U] [V] «не покраснели» при их строках [FAIL] в выводе).
        grep -qF -- "[FAIL] $C09_NAME — [$tag] " <<<"$out" || missing="$missing [$tag]"
    done
    if [ "$got" -eq 1 ] && [ -z "$missing" ]; then
        echo "  ok   $name (код 1; покраснели:$(printf ' [%s]' "$@"))"
    else
        echo "  ПРОВАЛ $name — ждали код 1 и красное у$(printf ' [%s]' "$@"); код $got, не покраснели:${missing:- —}" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
    fi
}

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C09"

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
    run_c09_red "$b" "инъекция: перечень обязательных подан сверке не в том порядке — краснеет" A
fi

# Инъекция ПРЕДМЕТА ЗАДАЧИ: отказ разбора выходит единицей. Скрипт при этом
# исправен во всём остальном — меняется ровно один факт, код на выходе из
# `parse_broken`, — и краснеют пробы, где разбор ломается.
# Образец привязан к ТЕЛУ `parse_broken`, а не к первой строке «вердикта нет»:
# эти слова стоят и в шапке инструмента, и в подсказке об использовании, и
# прежний якорь совпал с шапкой, когда её текст сменился (ws#884), — инъекция
# вносила `exit 1` в разбор аргументов: дефект внесён, но не тот.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/(^parse_broken\(\) \{\n(?:(?!^\}).*\n)*?)  exit 2\n/$1  exit 1\n/m' \
    "код выхода parse_broken"; then
    run_c09_red "$b" "инъекция: отказ разбора выходит кодом находки — краснеет" E F
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
    run_c09_red "$b" "инъекция: различные имена схлопнуты в одно — краснеет" H
fi

# СНЯТИЕ САМОГО ПИНА `LC_ALL=C` — исходный дефект ws#530. check-09 исполняет
# инструмент под локалью, замеренной как расходящаяся с байтовым порядком
# (возврат check-verifier @5f3080335: под C.UTF-8 снятие пина проходило молча).
# Представимо лишь там, где такая локаль есть; где её нет — это сказано строкой
# переписи, проба НЕ засчитана ни зелёной, ни исполненной, а держат две
# инъекции выше, от среды не зависящие.
mr_locale_differs() {
    local sample byte cand
    sample="$(printf '%s\n' "bats-and-shellcheck" "доказательства хуков" "authz — lint" "проба — раз" "проба - раз")"
    byte="$(printf '%s\n' "$sample" | LC_ALL=C sort -u)"
    for cand in $(locale -a 2>/dev/null | grep -iv '^\(c\|posix\)\(\..*\)\?$'); do
        [ "$(printf '%s\n' "$sample" | LC_ALL="$cand" sort -u 2>/dev/null)" != "$byte" ] && { printf '%s' "$cand"; return 0; }
    done
    return 1
}
if mr_loc="$(mr_locale_differs)"; then
    b="$(mksandbox)"
    if mr_patch "$b/$MR_REL" 's/^(required=\$\(jq .*?)\| LC_ALL=C sort -u\)$/$1| sort -u)/m' \
        "пин LC_ALL=C снят с сортировки обязательных"; then
        run_c09_red "$b" "инъекция: сортировка обязательных по локали ($mr_loc) — краснеет" A H
    fi
    b="$(mksandbox)"
    if mr_patch "$b/$MR_REL" 's/^(green=\$\(jq .*?)\| LC_ALL=C sort -u\)$/$1| sort -u)/m' \
        "пин LC_ALL=C снят с сортировки зелёных"; then
        run_c09_red "$b" "инъекция: сортировка зелёных по локали ($mr_loc) — краснеет" A
    fi
else
    echo "  [CENSUS] снятие пина LC_ALL=C НЕ ИСПОЛНЕНО: локали, расходящейся с байтовым порядком, в системе нет — держат две инъекции выше"
fi

# Законный близнец: то же свойство (байтовый порядок плюс дедупликация),
# записанное иначе. Без него проверка ловила бы строку `LC_ALL=C sort -u`, а не
# исход, и запрещала бы автору любую другую запись сверки.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/LC_ALL=C sort -u/LC_ALL=C sort | LC_ALL=C uniq/g' \
    "та же сортировка другой формой"; then
    run 0 "$b" "близнец: та же сортировка другой формой — молчит" "$C09"
fi

# ── КЛАСС «ЛОЖНОЕ „МОЖНО“ (КОД 0)» ПОРЕШЕННО ─────────────────────────────────
# Каждое решение, ведущее к коду 0, портится ОДНИМ фактом, и порча обязана
# покраснеть держащей его пробой: состояние слияния, выбор пути, исход контекста.

# Удерживающее состояние слияния объявлено «можно». По одному на каждое.
for ms in BLOCKED DIRTY BEHIND DRAFT UNKNOWN; do
    b="$(mksandbox)"
    if mr_patch "$b/$MR_REL" "s/CLEAN\\|UNSTABLE\\|HAS_HOOKS\\)/CLEAN|UNSTABLE|HAS_HOOKS|$ms)/" \
        "состояние $ms объявлено «можно»"; then
        run_c09_red "$b" "инъекция: состояние слияния $ms засчитано как «можно» — краснеет" "A-$ms"
    fi
done

# Выбор пути: PR не открыт — а вердикт всё равно выносится.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/if \[ "\$state" != "OPEN" \]; then/if false; then/' \
    "состояние PR не сверяется"; then
    run_c09_red "$b" "инъекция: закрытый PR получает вердикт — краснеет" I
fi

# Выбор пути: у защиты ноль обязательных контекстов — а ответ «можно». Слияние
# сервером ничем не гейтится; «можно» здесь — ложное зелёное, вердикта нет.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/(ничем не гейтится\. Это находка, а не норма\."\n  )exit 2\n/${1}exit 0\n/' \
    "ноль обязательных контекстов отвечает «можно»"; then
    run_c09_red "$b" "инъекция: ноль обязательных контекстов засчитан как «можно» — краснеет" G
fi

# ── ПУТЬ С ОБЯЗАТЕЛЬНЫМИ КОНТЕКСТАМИ: КАЖДОЕ РЕШЕНИЕ, ВЕДУЩЕЕ К КОДУ 0 ─────────
# Возврат check-verifier @4a02d37a9: фильтр `conclusion=="SUCCESS"` в строке
# `green=` снимался до `select(true)` при зелёном check-09 — фикстуры знали
# одни SUCCESS. Держат его пробы RC-*.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(green=\$\(jq -r .\.statusCheckRollup\[\]\? \| )select\(\.conclusion=="SUCCESS"\)/${1}select(true)/m' \
    "фильтр зелёного исхода контекста снят"; then
    run_c09_red "$b" "инъекция: любой исход контекста засчитан зелёным — краснеет" \
        RC-running RC-FAILURE RC-CANCELLED RC-TIMED_OUT RC-ACTION_REQUIRED
fi

# Ослабление, а не снятие: зелёным считается всё, кроме FAILURE. Проба
# RC-FAILURE на нём законно молчит, остальные обязаны покраснеть.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(green=\$\(jq -r .\.statusCheckRollup\[\]\? \| )select\(\.conclusion=="SUCCESS"\)/${1}select(.conclusion!="FAILURE")/m' \
    "зелёным считается всё, кроме FAILURE"; then
    run_c09_red "$b" "инъекция: зелёным считается всё, кроме FAILURE — краснеет" \
        RC-running RC-CANCELLED RC-TIMED_OUT RC-ACTION_REQUIRED
fi

# Возврат check-verifier @5f3080335: зелёный, заданный ДОПОЛНЕНИЕМ к перечню
# красных, проходил все пробы — перечень RC-* повторял перечень `red=`. Теперь
# пробы RC-* — все исходы, кроме SUCCESS. Порча дополнением — ровно та строка,
# что предъявил check-verifier (перечень красных без STARTUP_FAILURE).
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(green=\$\(jq -r .\.statusCheckRollup\[\]\? \| )select\(\.conclusion=="SUCCESS"\)/${1}select((.conclusion \/\/ "") as \$c | \$c != "" and (["FAILURE","TIMED_OUT","CANCELLED","ACTION_REQUIRED"] | index(\$c) | not))/m' \
    "зелёный задан дополнением к перечню красных"; then
    run_c09_red "$b" "инъекция: зелёный — всё, что не красное и не идёт, — краснеет" \
        RC-STARTUP_FAILURE RC-STALE RC-NEUTRAL RC-SKIPPED
fi

# Одиночное расширение зелёного: SUCCESS «или <исход>» — по каждому незелёному
# исходу, включая «идёт» (null). Каждая порча обязана покраснеть своей пробой.
for oc in null FAILURE CANCELLED TIMED_OUT ACTION_REQUIRED STARTUP_FAILURE STALE NEUTRAL SKIPPED; do
    if [ "$oc" = null ]; then lit="null"; tag="RC-running"; else lit="\"$oc\""; tag="RC-$oc"; fi
    b="$(mksandbox)"
    if mr_patch "$b/$MR_REL" \
        "s/^(green=\\\$\\(jq -r .\\.statusCheckRollup\\[\\]\\? \\| )select\\(\\.conclusion==\"SUCCESS\"\\)/\${1}select(.conclusion==\"SUCCESS\" or .conclusion==$lit)/m" \
        "зелёным засчитан и исход $oc"; then
        run_c09_red "$b" "инъекция: зелёным засчитан исход $oc — краснеет" "$tag"
    fi
done

# Разность множеств взята не в ту сторону.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^missing=\$\(set_diff -23\)$/missing=\$(set_diff -13)/m' \
    "разность множеств взята не в ту сторону"; then
    run_c09_red "$b" "инъекция: недостающие обязательные считаются не с той стороны — краснеет" \
        B H RC-running RC-FAILURE RC-CANCELLED RC-TIMED_OUT RC-ACTION_REQUIRED
fi

# Один недостающий обязательный прощён.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/if \[ "\$missing_count" -gt 0 \]; then/if [ "\$missing_count" -gt 1 ]; then/' \
    "один недостающий обязательный прощён"; then
    run_c09_red "$b" "инъекция: один недостающий обязательный прощён — краснеет" \
        B H RC-running RC-FAILURE RC-CANCELLED RC-TIMED_OUT RC-ACTION_REQUIRED
fi

# Путь контекстов выходит нулём мимо состояния слияния. Суд состояния слияния —
# общий конец обоих путей (`merge_state_verdict`), поэтому порча ставится в ВЫЗОВ
# пути контекстов, а не в саму функцию: ручной путь при этом остаётся нетронутым.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(merge_state_verdict "каждый обязательный контекст)/echo "merge-readiness: можно сливать"; exit 0\n$1/m' \
    "путь контекстов минует состояние слияния"; then
    run_c09_red "$b" "инъекция: путь контекстов минует состояние слияния — краснеет" \
        A-BLOCKED A-DIRTY A-BEHIND A-DRAFT A-UNKNOWN
fi

# ── ПОСЛЕДНИЙ ИСХОД ПРОВЕРКИ, А НЕ «ЕСТЬ SUCCESS» (находка kaname#673) ───────
# Каждое решение свёртки rollup к последним исходам портится одним фактом и
# обязано покраснеть держащей его пробой SUP-*.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(green=\$\(jq -r .*?)<<<"\$rollup_json"/${1}<<<"\$pr_json"/m' \
    "зелёные взяты из несвёрнутого rollup"; then
    run_c09_red "$b" "инъекция: зелёный — имя, у которого ЕСТЬ success (прежнее правило) — краснеет" \
        SUP-LATE-RED SUP-LATE-RUN SUP-WF SUP-NOSTART
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/\(map\(\.startedAt\) \| max\)/(map(.startedAt) | min)/' \
    "последним взят самый ранний исход"; then
    run_c09_red "$b" "инъекция: последним взят самый ранний исход — краснеет" SUP-GREEN SUP-LATE-RED SUP-LATE-RUN
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/if length > 1 and all\(\.\[\]; \(\.startedAt \/\/ ""\) != ""\)/if length > 1/' \
    "запись без startedAt вытесняется"; then
    run_c09_red "$b" "инъекция: порядок без startedAt считается установленным — краснеет" SUP-NOSTART
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/group_by\(\[\(\.name \/\/ \.context\), \(\.workflowName \/\/ ""\)\]\)/group_by(.name \/\/ .context)/' \
    "проверка — одно имя, без workflow"; then
    run_c09_red "$b" "инъекция: одноимённые задания разных workflow вытесняют друг друга — краснеет" SUP-WF
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/then \[\.\[\]\] else map\(select\(\.conclusion != "SUCCESS"\)\) end/then [.[]] else [.[]] end/' \
    "незелёная проверка прикрыта зелёной одноимённой"; then
    run_c09_red "$b" "инъекция: красная проверка прикрыта зелёной одноимённой — краснеет" SUP-WF SUP-NOSTART
fi

# Законный близнец фильтра: тот же «только SUCCESS», записанный иначе.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(green=\$\(jq -r .\.statusCheckRollup\[\]\? \| )select\(\.conclusion=="SUCCESS"\)/${1}select(.conclusion | . == "SUCCESS")/m' \
    "фильтр зелёного исхода другой формой"; then
    run 0 "$b" "близнец: фильтр зелёного исхода контекста другой формой — молчит" "$C09"
fi

# ── ВЫБОР ИСТОЧНИКА ВОРКСПЕЙСА ПО ЗАЩИТЕ БАЗЫ (ws#886) ─────────────────────────
# База требует контекстов — путь контекстов, и зелёный ручной прогон их не
# заменяет. Порча выбора в одну сторону уводит такую базу в ручной путь: P
# (контекста нет, прогон зелёный) отвечает «можно», WA и пробы с контекстами
# воркспейса упираются в отсутствие фикстуры прогонов.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^  if \[ "\$\{own_count:-0\}" -gt 0 \]; then$/  if false; then/m' \
    "база с контекстами уходит в ручной прогон"; then
    run_c09_red "$b" "инъекция: база воркспейса с контекстами судится ручным прогоном — краснеет" P WA
fi
# Порча в другую сторону: воркспейс без требования контекстов не получает
# ручного пути — база `main` без контекстов судилась бы «ноль контекстов», а
# ветка линии воркспейса — набором ствола, чьих контекстов на её PR не бывает.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^(\s*)manual_workflow="ci\.yaml"$/$1manual_workflow=""/m' \
    "ручной путь воркспейса снят"; then
    run_c09_red "$b" "инъекция: база без требования контекстов не судится ручным прогоном — краснеет" J U
fi
# Законный близнец выбора: то же условие другой записью — молчит.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^  if \[ "\$\{own_count:-0\}" -gt 0 \]; then$/  if [ "\${own_count:-0}" -ge 1 ]; then/m' \
    "выбор источника другой записью"; then
    run 0 "$b" "близнец: выбор источника по защите базы другой записью — молчит" "$C09"
fi
# Сведение ws#788 с ws#844: путь воркспейса выбирается ТЕМ ЖЕ чтением защиты,
# что судит путь контекстов. Прежняя запись выбора (`$(gh api … || true)`, пустой
# ответ — «защиты нет») уводила непрочитанную защиту в ручной прогон, и зелёный
# прогон отвечал «можно» там, где вердикта нет. Порча возвращает ровно её — и
# только для воркспейса: пробы C-* продукта она не задевает.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(  echo "merge-readiness: защита ветки .\$branch. НЕ ПРОЧИТАНА)/  [ "\$\{REPO,,\}" = "pro-robotech\/kacho-workspace" ] \&\& { prot_state=unprotected; return 0; }\n$1/m' \
    "отказ чтения защиты воркспейса засчитан незащищённой базой"; then
    run_c09_red "$b" "инъекция: непрочитанная защита воркспейса уводит в ручной прогон — краснеет" U-EMPTY U-403
fi

# ── ИСТОЧНИК ВОРКСПЕЙСА (ws#788): каждая инъекция роняет ровно одно условие ──
# Красный ручной прогон на голове перестаёт быть отказом.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/if \[ "\$red_count" -gt 0 \] \|\| \[ "\$run_red" -eq 1 \]; then/if false; then/' \
    "красное ручного прогона не судится"; then
    run 1 "$b" "инъекция: красный ручной прогон на голове не отказ — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# Прогона на голове нет — а инструмент отвечает «можно».
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/(ручного прогона на голове нет;.*?\n.*?\n)    exit 2\n/$1    exit 0\n/s' \
    "нет прогона — зелёное"; then
    run 1 "$b" "инъекция: прогона на голове нет, а ответ «можно» — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# Прогон берётся не по голове: засчитан прогон прежней sha.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/select\(\.head_sha == \$sha and \.event == "workflow_dispatch"\)/select(.event == "workflow_dispatch")/' \
    "фильтр по голове снят"; then
    run 1 "$b" "инъекция: засчитан прогон прежней головы — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# Судит первый прогон головы, а не последний.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/sort_by\(\.created_at, \.id\) \| last/sort_by(.created_at, .id) | first/' \
    "первый прогон вместо последнего"; then
    run 1 "$b" "инъекция: судит первый прогон головы — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# check-runs чужого прогона той же sha идут в счёт.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/select\(\.check_suite\.id == \$s\)/select(true)/' \
    "фильтр по прогону снят"; then
    run 1 "$b" "инъекция: check-runs чужого прогона в счёте — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# Порядок прогонов перед `last` не держался ничем (ws#862, находка M4
# check-verifier): фикстуры O и S кладут прежний прогон первым, и без сортировки
# `last` брал верный прогон случайно. Сосед отдаёт новый прогон ПЕРВЫМ, и на таком
# порядке `last` без сортировки судит прежний. Инъекция снимает только сортировку
# и обязана уронить РОВНО пробу в порядке соседа: красное от чужой пробы значило
# бы, что держит не она.
#
# mr_run_only_probe <песочница> <имя-пробы> <заголовок пробы, обязанной покраснеть>
# Код 1, проба с находкой ОДНА, и это названная. Число берётся из итога check-09
# («проб с находкой: N из M»), заголовок — из её строки [FAIL].
mr_run_only_probe() {
    local box="$1" name="$2" title="$3" out got
    local c9=check-09-merge-readiness-tells-three-outcomes-apart
    premise_or_void
    probes=$((probes + 1))
    out="$(TOOLING_GATE_ROOT="$box" bash "$HERE/$c9.sh" 2>&1)"; got=$?
    if [ "$got" -eq 1 ] && grep -qF -- "проб с находкой: 1 из" <<<"$out" \
        && grep -qF -- "[FAIL] $c9 — $title — " <<<"$out"; then
        echo "  ok   $name (код $got, проба с находкой одна — «$title»)"
    else
        echo "  ПРОВАЛ $name — ждали код 1 и одну пробу с находкой «$title», получили код $got" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
    fi
}

b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/\| sort_by\(\.created_at, \.id\) \| last \/\/ empty/| last \/\/ empty/' \
    "сортировка прогонов перед last снята"; then
    mr_run_only_probe "$b" "инъекция: сортировка прогонов снята — краснеет ровно проба в порядке соседа" \
        "[Y] воркспейс: сосед отдал новый прогон первым — судит последний, а не прежний зелёный"
fi

# Законный близнец: «последний» другой записью, тем же ключом. Проба судит
# исход, а не текст: `max_by` по тому же ключу выбирает тот же прогон.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/sort_by\(\.created_at, \.id\) \| last \/\/ empty/max_by(.created_at, .id) \/\/ empty/' \
    "последний прогон другой записью"; then
    run 0 "$b" "близнец: последний прогон головы другой записью (max_by тем же ключом) — молчит" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# Три охраны, чьё снятие набор до ws#788 (возврат check-verifier, опыты M1–M3) не
# замечал. Каждая инъекция роняет РОВНО одно условие строки, а близнец пишет ту же
# охрану другой формой: проба судит исход, а не написание.

# M1: «прогон идёт» судится только по check-runs — прогон, чьи задания ещё не
# поднялись, при зелёном перечне отвечает «можно».
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/if \[ "\$running_count" -gt 0 \] \|\| \[ "\$run_status" != "completed" \]; then/if [ "\$running_count" -gt 0 ]; then/' \
    "состояние прогона не судится"; then
    run 1 "$b" "инъекция: идущий прогон при зелёных check-runs — «можно» — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/\|\| \[ "\$run_status" != "completed" \]; then/|| ! [ "\$run_status" = "completed" ]; then/' \
    "состояние прогона другой записью"; then
    run 0 "$b" "близнец: состояние прогона судится другой записью — молчит" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# M2: усечённый ответ о check-runs читается как полный.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/jq -e \x27\(\.total_count \/\/ 0\) <= \(\.check_runs \| length\)\x27/jq -e \x27true\x27/' \
    "усечение check-runs не судится"; then
    run 1 "$b" "инъекция: усечённый ответ о check-runs принят за полный — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/jq -e \x27\(\.total_count \/\/ 0\) <= \(\.check_runs \| length\)\x27/jq -e \x27(.check_runs | length) >= (.total_count \/\/ 0)\x27/' \
    "усечение другой записью"; then
    run 0 "$b" "близнец: усечение судится другой записью — молчит" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# M3: исход прогона целиком не судится — прогон без заданий уходит в «не выполнилось».
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/if \[ "\$red_count" -gt 0 \] \|\| \[ "\$run_red" -eq 1 \]; then/if [ "\$red_count" -gt 0 ]; then/' \
    "исход прогона целиком не судится"; then
    run 1 "$b" "инъекция: startup_failure без check-runs — «не выполнилось» — краснеет" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/if \(\$r \| index\(\$c\)\) != null then 1 else 0 end/if any(\$r[]; . == \$c) then 1 else 0 end/' \
    "исход прогона другой записью"; then
    run 0 "$b" "близнец: исход прогона судится другой записью — молчит" \
        check-09-merge-readiness-tells-three-outcomes-apart.sh
fi

# ── ЧТЕНИЕ ЗАЩИТЫ: КОД `gh api` СУДИТСЯ (ws#844) ──────────────────────────────
# Исходный дефект: тело отказа gh (404 «Branch not protected» в stdout, код 1)
# бралось за ответ о защите. Возвращается ровно он — код соседа проглочен.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/(gh api "repos\/\$REPO\/branches\/\$branch\/protection" >"\$file" 2>"\$workdir\/api\.err") && rc=0 \|\| rc=\$\?/$1 || true; rc=0/' \
    "код gh api проглочен — тело отказа читается как защита"; then
    run_c09_red "$b" "инъекция: тело отказа gh api взято за ответ о защите — краснеет" \
        C C-403 C-404NF EP-GREEN EP-BARE
fi

# Любой 404 — «не защищена»: 404 «Not Found» (нет права читать) выдан за состояние.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/type == "object" and \.message == "Branch not protected"\n\s*and /type == "object" and /' \
    "любой 404 читается как «не защищена»"; then
    run_c09_red "$b" "инъекция: 404 без «Branch not protected» засчитан незащищённой веткой — краснеет" C-404NF
fi

# Любой отказ — «не защищена»: непрочитанное выдано за состояние.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/if jq -e .type == "object" and \.message == "Branch not protected"\n[^\n]*\n/if true; then\n/' \
    "любой отказ чтения читается как «не защищена»"; then
    run_c09_red "$b" "инъекция: любой отказ чтения засчитан незащищённой веткой — краснеет" C-EMPTY C-403 C-404NF
fi

# Близнец: тот же предикат 404 другой записью.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/\.message == "Branch not protected"/(.message | test("^Branch not protected\$"))/' \
    "предикат «Branch not protected» другой формой"; then
    run 0 "$b" "близнец: предикат незащищённой ветки другой формой — молчит" "$C09"
fi

# ── БАЗА — ВЕТКА ЛИНИИ: НАБОР СТВОЛА (решение диспетчера 2026-10-01) ─────────
# Форма ветки линии не узнаётся вовсе — каскад «волна → эпик» снова стоит.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^LINE_BRANCH_RE=\x27.*\x27$/LINE_BRANCH_RE=\x27^\$\x27/m' \
    "ветка линии не узнаётся"; then
    run_c09_red "$b" "инъекция: ветка линии не узнана — краснеет" \
        EP-GREEN EP-RED EP-MISSING EP-WAVE EP-ZERO EP-BARE
fi

# Узнаётся только форма эпика, волна голым номером потеряна.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^LINE_BRANCH_RE=\x27.*\x27$/LINE_BRANCH_RE=\x27^[0-9]+-[^\/]*\$\x27/m' \
    "волна голым номером не узнаётся"; then
    run_c09_red "$b" "инъекция: волна голым номером не узнана — краснеет" EP-WAVE
fi

# Форма расширена до любой ветки — незащищённая не-линия судится набором ствола.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^LINE_BRANCH_RE=\x27.*\x27$/LINE_BRANCH_RE=\x27.*\x27/m' \
    "любая ветка — ветка линии"; then
    run_c09_red "$b" "инъекция: любая база судится набором ствола — краснеет" \
        NE-notify-2914 NE-v2914-notify NE-release
fi

# Форма без якорей — номер в середине имени принят за ветку линии.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^LINE_BRANCH_RE=\x27\^(.*)\$\x27$/LINE_BRANCH_RE=\x27$1\x27/m' \
    "форма ветки линии без якорей"; then
    run_c09_red "$b" "инъекция: форма ветки линии без якорей — краснеет" NE-notify-2914 NE-v2914-notify
fi

# Набор ствола берётся только при 404, а не при защите без контекстов.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^if \[ "\$\{own_count:-0\}" -eq 0 \] && \[\[/if [ "\$own_state" = unprotected ] \&\& [[/m' \
    "набор ствола только при незащищённой базе"; then
    run_c09_red "$b" "инъекция: эпик с защитой без контекстов не получает набор ствола — краснеет" EP-ZERO
fi

# Набор ствола берётся и там, где у ветки линии свой набор есть.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^if \[ "\$\{own_count:-0\}" -eq 0 \] && \[\[/if [[/m' \
    "собственный набор ветки линии игнорируется"; then
    run_c09_red "$b" "инъекция: собственный набор ветки линии подменён набором ствола — краснеет" EP-OWN
fi

# Ствол не защищён — а ответ «можно».
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/(судить нечем\. Это находка, а не норма\."\n    )exit 2\n/${1}exit 0\n/' \
    "незащищённый ствол отвечает «можно»"; then
    run_c09_red "$b" "инъекция: ветка линии при незащищённом стволе — «можно» — краснеет" EP-BARE
fi

# Отказ чтения СТВОЛА засчитан незащищённым стволом: непрочитанное выдано за
# состояние только на пути набора ствола. Флаг ставится лишь на чтение ствола,
# поэтому собственное чтение базы `main` (пробы C-*) порча не задевает.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(  read_protection) ("\$TRUNK" "\$trunk_file")$/$1_trunk $2/m; s/^(read_protection\(\) \{)/read_protection_trunk() { TRUNK_READ=1 read_protection "\$@"; }\n$1/m; s/^(  echo "merge-readiness: защита ветки .\$branch. НЕ ПРОЧИТАНА)/  [ -n "\$\{TRUNK_READ:-\}" ] \&\& { prot_state=unprotected; return 0; }\n$1/m' \
    "отказ чтения ствола засчитан незащищённым"; then
    run_c09_red "$b" "инъекция: отказ чтения ствола засчитан незащищённым стволом — краснеет" \
        EP-TRUNK-403 EP-TRUNK-EMPTY
fi

# Набор ствола подменён пустым, и пустой набор проходит. Краснеют шесть проб:
# EP-RED, EP-MISSING и G — кодом (0 вместо 1 и 2); EP-GREEN, EP-WAVE и EP-ZERO,
# где ствол зелен целиком и код совпадает, — строкой «обязательных контекстов: N».
# Замер 2026-10-01: ровно эти шесть, и ни одной сверх.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^  set_file="\$trunk_file"$/  set_file="\$own_file"/m; s/^if \[ "\$\{req_count:-0\}" -eq 0 \]; then$/if false; then/m' \
    "пустой набор проходит"; then
    run_c09_red "$b" "инъекция: набор ствола подменён пустым и пустой набор проходит — краснеет" \
        EP-GREEN EP-WAVE EP-ZERO EP-RED EP-MISSING G
fi

# Близнец: та же форма ветки линии другой записью.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" 's/^LINE_BRANCH_RE=\x27.*\x27$/LINE_BRANCH_RE=\x27^[[:digit:]]{1,}(-[^\/]*)?\$\x27/m' \
    "форма ветки линии другой записью"; then
    run 0 "$b" "близнец: форма ветки линии другой записью — молчит" "$C09"
fi

# ── ГОЛОВА PR — УРОВЕНЬ КАСКАДА (ws#909) ───────────────────────────────────────
# Предмет — PR синхронизации вниз, чья голова — ветка эпика или волны: вливание её
# снимает (kaname#576). Каждая порча роняет одно решение и обязана покраснить
# держащую его пробу CL-*; близнец пишет то же решение другой формой и молчит.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(        echo "merge-readiness: СЛИВАТЬ НЕЛЬЗЯ — голова PR будет снята вливанием"\n)        exit 1\n/$1/m' \
    "вниз пропускается к проверкам"; then
    run_c09_red "$b" "инъекция: голова-уровень вниз пропущена к проверкам — краснеет" \
        CL-DOWN CL-WAVE-DOWN CL-EPIC-LABEL CL-CROSS-PARENT
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(  head_epic=\$\(jq -r ).*$/$1\x27 0\x27 <"\$issue_file")/m' \
    "метка epic не судится"; then
    run_c09_red "$b" "инъекция: метка epic не делает уровнем — краснеет" CL-EPIC-LABEL
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/if \[ "\$\{parent_url,,\}" = "https:\/\/github\.com\/\$\{REPO,,\}\/issues\/\$\{base%%-\*\}" \]; then/if [ "\${parent_url##*\/}" = "\${base%%-*}" ]; then/' \
    "родитель сверяется только номером"; then
    run_c09_red "$b" "инъекция: родитель из чужого репозитория с номером базы — вверх — краснеет" CL-CROSS-PARENT
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(  \[ "\$rc" -eq 0 \] \|\| )cascade_unknown "задача .*$/$1printf \x27{}\x27 >"\$issue_file"/m' \
    "непрочитанная задача — не уровень"; then
    run_c09_red "$b" "инъекция: непрочитанная задача головы засчитана «не уровнем» — краснеет" CL-ISSUE-403
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/elif ! jq -e \x27\.message == "No parent issue found"\x27 >\/dev\/null 2>&1 <"\$parent_file"; then/elif false; then/' \
    "непрочитанный родитель — «родителя нет»"; then
    run_c09_red "$b" "инъекция: отказ чтения родителя засчитан «родителя нет» — краснеет" CL-PARENT-403
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/if \[ "\$head_subs" -eq 0 \] && \[ "\$head_epic" -eq 0 \]; then/if [ \$(( head_subs + head_epic )) -eq 0 ]; then/' \
    "признак уровня другой записью"; then
    run 0 "$b" "близнец: признак уровня каскада другой записью — молчит" "$C09"
fi
# Подсказка исполнима в репозитории PR (ws#910): kaname отвергает голову `tmp/*` и
# `<N>-<суть>` — ветка там голый номер задачи. Порча снимает kaname-форму, подсказка
# kaname уходит в общую — краснеет CL-DOWN-KANAME; порча общей формы в `tmp/sync-…`
# — CL-DOWN. Близнец пишет выбор репозитория другим образцом и молчит.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^    pro-robotech\/kaname\) printf .*\n//m' \
    "kaname-форма ветки синхронизации снята"; then
    run_c09_red "$b" "инъекция: kaname получает форму <N>-sync-…, которую отвергает его правило ветки — краснеет" CL-DOWN-KANAME
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(    \*\) printf \x27)<N>-sync-%s-into-%s(\x27)/$1tmp\/sync-%s-into-%s$2/m' \
    "общая форма — tmp/sync-…"; then
    run_c09_red "$b" "инъекция: общая форма ветки синхронизации — tmp/sync-…, черновик без проверок — краснеет" CL-DOWN
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^    pro-robotech\/kaname\) printf/    *\/kaname) printf/m' \
    "выбор репозитория другим образцом"; then
    run 0 "$b" "близнец: kaname узнаётся образцом */kaname — молчит" "$C09"
fi

# ── CLOSES — ТОЛЬКО ПО ДОКАЗАТЕЛЬСТВУ (ws#918) ─────────────────────────────────
# Каждая порча роняет одно решение и обязана покраснить держащую его пробу PF-*;
# близнецы пишут то же решение другой формой и молчат.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(    echo "merge-readiness: СЛИВАТЬ НЕЛЬЗЯ — Closes без доказательства DoD"\n)    exit 1\n/$1/m' \
    "Closes без доказательства пропущен к проверкам"; then
    run_c09_red "$b" "инъекция: Closes без доказательства пропущен к проверкам — краснеет" \
        PF-MISSING PF-MIDLINE PF-FORMS PF-MULTI
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/\(close\[sd\]\?\|fix\(e\[sd\]\)\?\|resolve\[sd\]\?\)/(closes)/' \
    "строка закрытия — только Closes"; then
    run_c09_red "$b" "инъекция: Fixes и Resolves не считаются строкой закрытия — краснеет" PF-FORMS
fi
b="$(mksandbox)"
if mr_patch "$b/$DOD_REL" \
    's/\(\^\|\\n\)DoD-proof/DoD-proof/' \
    "маркер в любом месте строки"; then
    run_c09_red "$b" "инъекция: маркер в середине строки засчитан доказательством — краснеет" PF-MIDLINE
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/proof_unread\+=\("\$ref_repo#\$ref_num"\)/proof_ok=\$((proof_ok + 1))/' \
    "непрочитанные комментарии — доказательство"; then
    run_c09_red "$b" "инъекция: непрочитанные комментарии засчитаны доказательством — краснеет" PF-UNREAD
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/^(      proof_ok=\$\(\(proof_ok \+ 1\)\)\n)/$1      break\n/m' \
    "судится только первая строка закрытия"; then
    run_c09_red "$b" "инъекция: после первой доказанной строки закрытия прочие не судятся — краснеет" PF-MULTI
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/s\|\^#\|\$REPO#\|/s|^.*#|\$REPO#|/' \
    "чужой репозиторий строки закрытия подменён репозиторием PR"; then
    run_c09_red "$b" "инъекция: задача чужого репозитория ищется в репозитории PR — краснеет" PF-FORMS
fi
# Опыт check-verifier (ws#920): комментарии читаются из репозитория PR, а номер
# печатается прежний. Фикстура по одному номеру это пропускала; держит PF-XREPO.
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/gh api "repos\/\$ref_repo\/issues\/\$ref_num\/comments/gh api "repos\/\$REPO\/issues\/\$ref_num\/comments/' \
    "комментарии читаются из репозитория PR"; then
    run_c09_red "$b" "инъекция: комментарии задачи читаются из репозитория PR, номер напечатан прежний — краснеет" \
        PF-XREPO PF-FORMS
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/\.closingIssuesReferences\[\] \|/.closingIssuesReferences[0:0][] |/' \
    "ответ хостинга о закрываемых задачах не читается"; then
    run_c09_red "$b" "инъекция: закрытие, объявленное хостингом, не судится — краснеет" PF-HOST
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/\(https\?:\/\/github\\\.com\/\[\[:alnum:\]_\.-\]\+\/\[\[:alnum:\]_\.-\]\+\/issues\/\[0-9\]\+\|/(/' \
    "форма-адрес в теле не разбирается"; then
    run_c09_red "$b" "инъекция: Closes формой-адресом не видна разбору тела — краснеет" PF-URL
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/jq -e \x27\.closingIssuesReferences \| type == "array"\x27/true/' \
    "поле хостинга не массивом принято за пустое"; then
    run_c09_red "$b" "инъекция: поле хостинга не массивом прочитано как «закрывать нечего» — краснеет" PF-HOSTBROKEN
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/LC_ALL=C sort -u \|\| true\)\nif \[ -z "\$closes_refs" \]/LC_ALL=C sort \|\| true)\nif [ -z "\$closes_refs" ]/' \
    "задача хостинга и тела судится дважды"; then
    run_c09_red "$b" "инъекция: задача из обоих источников посчитана дважды — краснеет" PF-HOSTPROOF
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/\.closingIssuesReferences\[\] \| "\\\(\.repository\.owner\.login\)\/\\\(\.repository\.name\)#\\\(\.number\)"/.closingIssuesReferences | map(.repository.owner.login + "\/" + .repository.name + "#" + (.number | tostring)) | .[]/' \
    "ссылки хостинга собраны иной записью"; then
    run 0 "$b" "близнец: ссылки хостинга собраны map и сложением строк — молчит" "$C09"
fi
b="$(mksandbox)"
if mr_patch "$b/$DOD_REL" \
    's/capture\("\(\^\|\\n\)DoD-proof @\(\?<rev>\[0-9a-f\]\{7,40\}\)"; "g"\)/split("\\n")[] | capture("^DoD-proof @(?<rev>[0-9a-f]{7,40})")/' \
    "маркер построчным разбором"; then
    run 0 "$b" "близнец: маркер ищется построчным разбором — молчит" "$C09"
fi
b="$(mksandbox)"
if mr_patch "$b/$MR_REL" \
    's/\(close\[sd\]\?\|fix\(e\[sd\]\)\?\|resolve\[sd\]\?\)/(resolve[sd]?|fix(e[sd])?|close[sd]?)/' \
    "ключевые слова закрытия в ином порядке"; then
    run 0 "$b" "близнец: ключевые слова закрытия в ином порядке — молчит" "$C09"
fi

b="$(mksandbox scripts/merge-readiness.sh)"
run 2 "$b" "предпосылка: инструмента нет — VOID, а не успех" "$C09"

echo "== check-18: хук отправки отвергает имя ветки не по форме «<N>-<суффикс>» =="
HK_REL="scripts/hooks/pre-push"
C18=check-18-push-refuses-unlawful-branch-name.sh

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C18"

# Инъекция — настоящий хук, у которого предикат формы ослаблен до «законно
# всё»: ровно тот хук, что стоял до 2026-09-30 и пропускал `issue-880`.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/^branch_name_lawful\(\) \{$/branch_name_lawful() { return 0;/m' \
    "предикат формы ослаблен до «законно всё»"; then
    run 1 "$b" "инъекция: предикат формы пропускает всё — краснеет" "$C18"
    # Красное принадлежит check-18: сосед, судящий тот же хук, молчит.
    run 0 "$b" "та же инъекция у соседа check-08 — молчит" \
        check-08-caller-reads-the-three-outcomes.sh
fi

# Вторая сторона: послабление для существующих веток снято — хук отвергает
# ДОПИСЫВАНИЕ уже заведённой ветки прежней формы, то есть останавливает работу,
# начатую до решения. Отказ законен только на СОЗДАНИИ.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" \
    's/if \[ -n "\$\{remote_sha:-\}" \] && \[ "\$remote_sha" != "\$zero_sha" \]; then/if false; then/' \
    "дописывание существующей ветки прежней формы отвергается"; then
    run 1 "$b" "инъекция: отказ на дописывании существующей ветки — краснеет" "$C18"
fi

# Переходное условие релиза (gi-branch-bare-number-release), сторона первая:
# хук отвергает ДОПИСЫВАНИЕ существующей ветки с голым номером — то есть
# останавливает релиз, идущий в `26`. Прочие прежние формы при этом по-прежнему
# дописываются, поэтому красное обязано прийти от пробы «26», а не от соседей.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" \
    's/^(    branch_name_lawful "\$name" && continue)$/    [[ "\$name" =~ ^[0-9]+\$ ]] && { bad_names+=("\$name"); continue; }\n$1/m' \
    "дописывание существующей ветки с голым номером отвергается"; then
    run 1 "$b" "инъекция: отказ на дописывании существующей «26» — краснеет" "$C18"
fi

# Сторона вторая: предикат формы принимает голый номер — новая «27» уехала бы.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" \
    "s/local name=\"\\\$1\" re='\\^\\[0-9\\]\\+-\\[a-z0-9\\]\\[a-z0-9-\\]\\*\\\$'/local name=\"\\\$1\" re='^[0-9]+(-[a-z0-9][a-z0-9-]*)?\\\$'/" \
    "голый номер принят законной формой"; then
    run 1 "$b" "инъекция: создание новой «27» пропущено — краснеет" "$C18"
fi

# Инъекции «удаление не пропущено» здесь НЕТ, и это замер, а не пропуск: у
# удаления `<remote_sha>` всегда ненулевой (удалять можно только то, что есть),
# поэтому, сняв строку пропуска удаления, хук пропускает его путём дописывания —
# исход тот же, меняется лишь строка предупреждения. Инъекция была написана и
# осталась зелёной (2026-09-30); заявлять держателем то, что не краснеет, нельзя.

# Законный близнец: тот же хук, отказ сформулирован иначе. Проверка обязана
# судить исход и называние имени, а не формулировку.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/ОТКАЗ — имя ветки не по форме/отказ: ветка названа не по форме/' \
    "текст отказа переписан"; then
    run 0 "$b" "близнец: иной текст отказа, то же поведение — молчит" "$C18"
fi

b="$(mksandbox "$HK_REL")"
run 2 "$b" "предпосылка: хука нет — VOID, а не успех" "$C18"

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
echo "== check-13: норма 2026-09-20 выпала из базы / отменённый маршрут стоит без пометки =="
#
# ПРЕДМЕТ ПРОБ — ДВЕ РАЗНЫЕ ОСИ ОДНОЙ ПРОВЕРКИ, и близнец есть у каждой. У оси
# «отменённый маршрут» близнец самый острый в наборе: дефект и близнец несут ОДНУ
# И ТУ ЖЕ формулировку отменённого маршрута, и отличает их ровно пометка отмены в
# той же строке. Без этого близнеца проверка запрещала бы корпусу вообще называть
# снятое решение — то есть запрещала бы раздел «противоречия, разрешённые в базе».
C13=check-13-landing-route-is-one-mr-per-wave.sh
BASE_REL=".claude/agents/dispatcher.md"
GIR_REL=".claude/rules/git-issues.md"

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C13"

# ось A: дословная цитата владельца выпала из базы маршрутизации
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/не забывай агрегировать мр = волна/порядок посадки описан выше/g' \
    "цитата «мр = волна» снята из базы"; then
    run 1 "$b" "инъекция: норма «МР равен волне» выпала из базы — краснеет" "$C13"
fi

# ось A': норма о сроке заведения задачи о безопасности выпала из правила
b="$(mksandbox)"
if mr_patch "$b/$GIR_REL" 's/gi-security-finding-issue-now/gi-security-finding-later/g' \
    "id нормы о немедленной задаче переименован"; then
    run 1 "$b" "инъекция: нормы «задача о безопасности немедленно» в правиле нет — краснеет" "$C13"
fi

# ось B: отменённый маршрут внесён как действующее основание
b="$(mksandbox)"
printf '%s\n' '- Посадка: PR прямо в `main` без накопительной ветки, слияние сразу по зелёному CI.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: отменённый маршрут стоит без пометки отмены — краснеет" "$C13"

# близнец оси B: ТА ЖЕ формулировка, но названная отменённой
b="$(mksandbox)"
printf '%s\n' '- Прежний маршрут «PR прямо в `main` без накопительной ветки» ОТМЕНЁН решением владельца 2026-09-20.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: тот же маршрут с пометкой отмены — молчит" "$C13"

# ось B': ТОТ ЖЕ отменённый порядок, записанный ДРУГИМИ СЛОВАМИ. Первая редакция
# распознавателя знала три формы записи и на этой молчала: восстановление снятого
# маршрута не давало ни красного, ни зелёного. Проба заведена перемером 2026-09-20.
b="$(mksandbox)"
printf '%s\n' '- Посадка: каждая полоса открывает свой PR в ствол и сливается сразу по зелёному CI.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: отменённый порядок пересказан («сразу по зелёному CI») — краснеет" "$C13"

b="$(mksandbox)"
printf '%s\n' '- Прежний порядок «каждая полоса открывает свой PR в ствол, слияние сразу по зелёному CI» ОТМЕНЁН 2026-09-20.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: тот же пересказ с пометкой отмены — молчит" "$C13"

# ось B'': ИМЯ снятого решения, поданное действующим. Дословная цитата — самый
# живучий носитель отменённого маршрута: переписать её нельзя, не потеряв ссылку
# на решение, поэтому она и взята литералом.
b="$(mksandbox)"
printf '%s\n' '- Маршрут посадки: заливай сразу в мастер — решение владельца 2026-09-17, действует.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: имя снятого решения подано действующим — краснеет" "$C13"

b="$(mksandbox)"
printf '%s\n' '- Решение 2026-09-17 «заливай сразу в мастер» ОТМЕНЕНО 2026-09-20 и основанием не служит.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: имя снятого решения с пометкой отмены — молчит" "$C13"

# ось B''': пометка отмены, стоящая в ОТРИЦАНИИ. Дефект и близнец отличаются
# ровно частицей «не»: первая редакция засчитывала «никто не отменял» за отмену и
# зеленела на строке, ПОДТВЕРЖДАЮЩЕЙ снятый маршрут.
b="$(mksandbox)"
printf '%s\n' '- Посадка: PR прямо в `main` без накопительной ветки — этого решения никто не отменял.' >> "$b/$BASE_REL"
run 1 "$b" "инъекция: пометка отмены стоит в отрицании — краснеет" "$C13"

b="$(mksandbox)"
printf '%s\n' '- Посадка: PR прямо в `main` без накопительной ветки — этот порядок ОТМЕНЁН 2026-09-20.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: та же строка, пометка в утверждении — молчит" "$C13"

# предпосылка оси B: арма распознавателя осталась без предмета. Дефект вносится
# НЕ в распознаватель, а в корпус: литерал перестаёт встречаться, и перечень
# молча становится уже своей шапки — ровно так в первой редакции жила арма
# `прямой PR`, не совпадавшая ни с одной строкой корпуса.
b="$(mksandbox)"
while IFS= read -r f; do
    mr_patch "$f" 's/без накопительной ветки/без ветки-сборки/g' "литерал выведен из корпуса" >/dev/null
done < <(grep -rlF 'без накопительной ветки' "$b/.claude" 2>/dev/null)
run 1 "$b" "предпосылка: литерал распознавателя без предмета в корпусе — краснеет" "$C13"

# близнец оси A: база правлена, но мимо предмета проверки
b="$(mksandbox)"
printf '%s\n' '- Посторонняя строка базы, предмета проверки не касающаяся.' >> "$b/$BASE_REL"
run 0 "$b" "близнец: правка базы мимо предмета — молчит" "$C13"

# предпосылка: базы маршрутизации в дереве нет — VOID, а не «находок 0»
b="$(mksandbox .claude/agents/dispatcher.md)"
run 2 "$b" "предпосылка: базы маршрутизации нет — VOID, а не успех" "$C13"

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
# С 2026-09-26 (ws#780) соседнее предложение — сама ссылка на эту норму ядра:
# три исхода из протокола сняты как повтор, ограничитель остался.
b="$(mksandbox)"
if mr_patch "$b/$PROTO_REL" 's/Обход ищут СРЕДИ.*?не повторяется\.//s' \
    "ограничитель «обход СРЕДИ безопасных способов» снят из протокола"; then
    run 1 "$b" "инъекция: клаузула давления осталась без своего ограничителя — краснеет" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$PROTO_REL" 's/Встретив отказ, ищи ОБХОД;.*?не исход\. //s' \
    "из того же абзаца снято соседнее предложение, ограничитель оставлен"; then
    run 0 "$b" "близнец: из того же абзаца снято соседнее предложение, ограничитель на месте — молчит" "$C11"
fi

# ось A: ЦИТАТА СВЕРЯЕТСЯ С ТОЧНОСТЬЮ ДО МЯГКОГО ПЕРЕНОСА (ws#855). Протокол
# свёрстан в сто колонок, и законный перенос строки внутри цитаты давал код 1 с
# текстом «нормы нет» — находка ложная. ПАРА ОДНОФАКТНАЯ: обе стороны переносят
# ограничитель через строку одним и тем же продолжением пункта списка с
# отступом и отличаются ровно одним словом цитаты.
b="$(mksandbox)"
if mr_patch "$b/$PROTO_REL" 's/Обход ищут СРЕДИ безопасных способов, а не вместо безопасности/Обход ищут СРЕДИ безопасных способов,\n  а не вместо безопасности/' \
    "ограничитель перенесён через строку продолжением пункта списка"; then
    run 0 "$b" "близнец: цитата перенесена через строку внутри пункта списка — молчит" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$PROTO_REL" 's/Обход ищут СРЕДИ безопасных способов, а не вместо безопасности/Обход ищут ВНЕ безопасных способов,\n  а не вместо безопасности/' \
    "ограничитель перенесён через строку, одно слово сменено"; then
    run 1 "$b" "инъекция: та же перенесённая цитата со сменой одного слова — краснеет" "$C11"
fi

# Две другие законные формы переноса — каждая своей пробой: абзац без отступа и
# продолжение цитаты разметки `>`. И ГРАНИЦА: цитата, разнесённая по двум
# абзацам, — уже не перенос, а два предложения; склейка через пустую строку
# сделала бы нормализацию шире переноса, и пара ниже это ловит.
b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/(следи что бы волны планировались) (согласно расходу)/$1\n$2/' \
    "цитата требования 5 перенесена внутри абзаца без отступа"; then
    run 0 "$b" "близнец: цитата перенесена внутри абзаца без отступа — молчит" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/^(Ширина и окно — .*?)(следи что бы волны планировались) (согласно расходу)/> $1$2\n> $3/m' \
    "абзац с цитатой требования 5 стал цитатой разметки, перенос внутри неё"; then
    run 0 "$b" "близнец: цитата перенесена внутри цитаты разметки «>» — молчит" "$C11"
fi

b="$(mksandbox)"
if mr_patch "$b/$BASE_REL" 's/(следи что бы волны планировались) (согласно расходу)/$1\n\n$2/' \
    "цитата требования 5 разнесена по двум абзацам"; then
    run 1 "$b" "инъекция: цитата разнесена по двум абзацам — не перенос, краснеет" "$C11"
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

# предпосылка: РАЗБОРЩИК БЛОКОВ не отработал (ws#855). Цитату сверяет python3, и
# его отказ выходит тем же кодом 1, что и «не найдено»; без слова «да»/«нет» на
# выводе гейт объявлял бы «нормы нет» на всех якорях разом. Отказ подменяется
# СНАРУЖИ — интерпретатором, который выходит единицей и молчит.
d="$(mktemp -d "$TMP/pyXXXXXX")"
printf '#!/bin/sh\nexit 1\n' > "$d/python3"
chmod +x "$d/python3"
b="$(mksandbox)"
PATH="$d:$PATH" run 2 "$b" "предпосылка: разборщик блоков вышел единицей молча — VOID, а не «нормы нет»" "$C11"

echo "== check-14: перепись каскада читает одно отношение из двух =="
CC_REL="scripts/cascade-census.sh"
C14=check-14-cascade-census-reads-both-relations.sh

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C14"

# Каждая инъекция роняет в инструменте ровно одно свойство — то, ради которого
# предикат каскада переписан (возврат wave-reviewer к ws#845).
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/next unless \//next; next unless \//' "перечень тела не читается"; then
    run 1 "$b" "инъекция: читается только sub-issue (kacho#2794 проходит) — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/void "дочерних ноль/true || void "дочерних ноль/' "пустой уровень зелёный"; then
    run 1 "$b" "инъекция: дочерних ноль выдано за «открытых ноль» — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/\[ "\$state" = closed \] && \[ "\$open_n" -gt 0 \]/false/' \
    "закрытый уровень с открытыми не находка"; then
    run 1 "$b" "инъекция: волна закрыта при открытой задаче, находки нет — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/gh api --paginate /gh api /' "sub-issue без страниц"; then
    run 1 "$b" "инъекция: sub-issue читаются одной страницей — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/next if \$fence;/1;/' "блок кода читается перечнем"; then
    run 1 "$b" "инъекция: пример в блоке кода принят за дочерний — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/m\{\^#\(\\d\+\)\\b\}/m{#(\\d+)\\b}/' "ссылка дальше по строке — дочерний"; then
    run 1 "$b" "инъекция: упоминание дальше по строке принято за дочерний — краснеет" "$C14"
fi
# Ключ посадки эпика принят, но не исполняется: открытый эпик с открытой волной
# снова выходит кодом 0 (возврат wave-reviewer к ws#845, круг 2).
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/elif \[ "\$WANT_CLOSED" = 1 \] && \[ "\$open_n" -gt 0 \]/elif false/' \
    "--children-closed не исполняется"; then
    run 1 "$b" "инъекция: --children-closed принят и не судит открытых — краснеет" "$C14"
fi

# Ключ закрытия задач влитой волны: доказательство DoD (возврат check-verifier,
# ws#920). Каждая порча роняет одно решение режима --proof.
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/if \[ -n "\$proof_missing" \]; then/if false; then/' \
    "--proof не исполняется"; then
    run 1 "$b" "инъекция: --proof принят, задача без доказательства не находка — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/"repos\/\$r\/issues\/\$n\/comments"/"repos\/\$REPO\/issues\/\$n\/comments"/' \
    "комментарии читаются из репозитория волны"; then
    run 1 "$b" "инъекция: комментарии задачи читаются из репозитория волны — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/gh api --paginate "repos\/\$r\/issues/gh api "repos\/\$r\/issues/' \
    "комментарии одной страницей"; then
    run 1 "$b" "инъекция: комментарии задачи читаются одной страницей — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$DOD_REL" 's/\(\^\|\\n\)DoD-proof/DoD-proof/' \
    "маркер в любом месте строки"; then
    run 1 "$b" "инъекция: маркер в середине строки засчитан доказательством — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/proof_unread="\$proof_unread \$ref"/proof_ok=\$((proof_ok + 1))/' \
    "непрочитанные комментарии — доказательство"; then
    run 1 "$b" "инъекция: непрочитанные комментарии засчитаны доказательством — краснеет" "$C14"
fi
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/\[\.\[\] \| \(\.body \/\/ ""\) \| dod_proof\] \| any/any(.[]; (.body \/\/ "") | dod_proof)/' \
    "маркер ищется any с генератором"; then
    run 0 "$b" "близнец: доказательство ищется any(генератор; условие) — молчит" "$C14"
fi

# Близнец: тот же набор маркеров списка, записанный иначе. Проверка судит
# исход над фикстурой, а не написание выражения.
b="$(mksandbox)"
if mr_patch "$b/$CC_REL" 's/\[-\*\+\]\\s\+\\\[/[+*-]\\s+\\[/' "маркеры списка другой записью"; then
    run 0 "$b" "близнец: те же маркеры списка другой записью — молчит" "$C14"
fi

b="$(mksandbox scripts/cascade-census.sh)"
run 2 "$b" "предпосылка: инструмента нет — VOID, а не успех" "$C14"

echo "== check-15: хуки коммита и отправки отказывают трейлеру атрибуции (ws#861) =="
C15=check-15-attribution-hooks-refuse-the-trailer.sh
AR_REL="scripts/hooks/attribution-rule.sh"

b="$(mksandbox)"; run 0 "$b" "чистое дерево — молчит" "$C15"

# Инъекция А — ДОСЛОВНО прежний предикат стражей линий: Co-Authored-By судится,
# только когда в значении имя модели. Соавтор-человек проходил бы.
b="$(mksandbox)"
if mr_patch "$b/$AR_REL" 's/co-authored-by: \]\]/co-authored-by:.*(claude|anthropic) ]]/' \
    "Co-Authored-By со значением-фильтром"; then
    run 1 "$b" "инъекция А: Co-Authored-By судится по значению — краснеет" "$C15"
    run 0 "$b" "та же инъекция у соседа check-10 — молчит, красное принадлежит check-15" "$C10"
fi
# Инъекция Б — слепой предикат: ни одна строка атрибуцией не признаётся.
b="$(mksandbox)"
printf '\nattribution_line() { return 1; }\n' >> "$b/$AR_REL"
run 1 "$b" "инъекция Б: слепой предикат — краснеет" "$C15"
# Инъекция В — хук отправки зовёт стража, но его код не читает.
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/^attribution_rc=\$\?$/attribution_rc=0/m' "код стража не читается"; then
    run 1 "$b" "инъекция В: pre-push не читает код стража — краснеет" "$C15"
fi
# Близнец: правка предиката, смысла не меняющая (комментарий в конце файла).
b="$(mksandbox)"
printf '\n# комментарий пробы: предикат не меняется\n' >> "$b/$AR_REL"
run 0 "$b" "близнец: безобидная правка предиката — молчит" "$C15"

b="$(mksandbox scripts/hooks/commit-msg)"
run 1 "$b" "хука коммита нет — находка, а не VOID: предмет проверки и есть его существование" "$C15"

# Подпись песочницы check-15 — корневая учётная запись вызывающего (ws#785, сведение
# в ws#873). Корневой подписи нет — у песочницы нет предмета: третий исход, а не
# зелёное на подписи, выдуманной самой проверкой. Каталог назван не на `s`.
b="$(mksandbox)"; h21="$TMP/h21"; mkdir -p "$h21"
premise_or_void
probes=$((probes + 1))
out="$(HOME="$h21" XDG_CONFIG_HOME="$h21/.config" GIT_CONFIG_NOSYSTEM=1 TOOLING_GATE_ROOT="$b" bash "$HERE/$C15" 2>&1)"; got=$?
if [ "$got" -eq 2 ] && grep -qF -- "корневой подписи нет" <<<"$out"; then
    echo "  ok   корневой подписи нет — VOID, песочница подписи не выдумывает (код $got)"
else
    echo "  ПРОВАЛ корневой подписи нет — ждали код 2 и «корневой подписи нет», получили $got" >&2
    printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
    failed=$((failed + 1))
fi
rm -rf "$h21"

echo "== check-16: подпись переопределена мимо корневого gitconfig =="
C16=check-16-signature-from-root-gitconfig-only.sh
# Вносимые формы собираются из частей при исполнении: литерал в исходнике этого
# файла был бы находкой самого стража — и был бы ею по праву, потому что строка
# исполнялась бы. Ключ и имя переменной подписи в тексте файла не встречаются.
K_NAME="$(printf '%s.%s' user name)"
K_EMAIL="$(printf '%s.%s' user email)"
K_MIXED="$(printf '%s.%s' User Name)"
E_NAME="$(printf 'GIT_%s_%s' AUTHOR NAME)"
E_CMAIL="$(printf 'GIT_%s_%s' COMMITTER EMAIL)"

# run22 <код> <песочница> <имя> [подстрока] — как `run`, и находка обязана НАЗВАТЬ
# координату: покраснеть «где-то» мало, вывод — часть свойства.
run22() {
    local want="$1" box="$2" name="$3" needle="${4:-}" got out
    premise_or_void
    probes=$((probes + 1))
    out="$(TOOLING_GATE_ROOT="$box" bash "$HERE/$C16" 2>&1)"; got=$?
    if [ "$got" -eq "$want" ] && { [ -z "$needle" ] || grep -qF -- "$needle" <<<"$out"; }; then
        echo "  ok   $name (код $got)"
    else
        echo "  ПРОВАЛ $name — ждали код $want${needle:+ и «$needle»}, получили $got" >&2
        printf '%s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
    fi
}
# add22 <песочница> <путь> <строка…> — дописать строки в файл (новый или живой).
add22() { local box="$1" rel="$2"; shift 2; mkdir -p "$(dirname "$box/$rel")"; printf '%s\n' "$@" >> "$box/$rel"; }
PROBE22="scripts/probe-gate/inject.sh"
SANDBOX22='TMP="$(mktemp -d)"; trap '"'"'rm -rf "$TMP"'"'"' EXIT; git init -q "$TMP/r"'

b="$(mksandbox)"; run22 0 "$b" "чистое дерево — молчит" "находок 0"

# Рабочий клон и песочница пробы судятся одинаково — решение 2026-09-27 (ws#785):
# оговорки для песочниц нет.
b="$(mksandbox)"; n="$(( $(wc -l < "$b/bootstrap.sh") + 1 ))"
add22 "$b" bootstrap.sh "git -c $K_EMAIL=x@example.invalid commit -qm x"
run22 1 "$b" "инъекция: -c подписи в скрипте рабочего клона — краснеет и называет строку" "bootstrap.sh:$n: подпись на команду"

b="$(mksandbox)"
add22 "$b" "$PROBE22" "$SANDBOX22" "git -C \"\$TMP/r\" config $K_NAME probe"
run22 1 "$b" "инъекция: подпись в конфиге одноразового репозитория пробы — краснеет" "$PROBE22:2: подпись на репозиторий"

b="$(mksandbox)"
add22 "$b" "$PROBE22" "$SANDBOX22" '. "$WS/scripts/lib/sandbox-git-home.sh"; sandbox_git_home "$TMP/home" || exit 2' \
    'sandbox_git -C "$TMP/r" commit -q --allow-empty -m x'
run22 0 "$b" "близнец: та же песочница с подписью из своего HOME — молчит"

b="$(mksandbox)"; add22 "$b" "$PROBE22" "git config --local $K_EMAIL p@example.invalid"
run22 1 "$b" "инъекция: config --local — краснеет" "подпись на репозиторий"
b="$(mksandbox)"; add22 "$b" "$PROBE22" "git config --worktree $K_NAME p"
run22 1 "$b" "инъекция: config --worktree — краснеет" "подпись на репозиторий"
b="$(mksandbox)"; add22 "$b" "$PROBE22" "git config --file .git/config $K_NAME p"
run22 1 "$b" "инъекция: config --file мимо корня — краснеет" "подпись на репозиторий"
b="$(mksandbox)"; add22 "$b" "$PROBE22" "n=\"\$(git config $K_NAME)\"" "e=\"\$(git config --global --get $K_EMAIL 2>/dev/null)\""
run22 0 "$b" "близнец: чтение подписи без значения и с --get — молчит"

b="$(mksandbox)"; add22 "$b" "$PROBE22" "git config --global $K_NAME probe"
run22 1 "$b" "инъекция: литерал подписи в корневой gitconfig — краснеет" "литерал подписи"
b="$(mksandbox)"; add22 "$b" "$PROBE22" "HOME=\"\$TMP/home\" git config --global $K_NAME \"\$name\""
run22 0 "$b" "близнец: корневая подпись переносится подстановкой в HOME песочницы — молчит"

b="$(mksandbox)"; add22 "$b" "$PROBE22" "export $E_NAME=probe"
run22 1 "$b" "инъекция: имя автора окружением — краснеет" "подпись окружением"
b="$(mksandbox)"; add22 "$b" "$PROBE22" "$E_CMAIL=p@example.invalid git commit -qm x"
run22 1 "$b" "инъекция: почта коммиттера префиксом команды — краснеет" "подпись окружением"
b="$(mksandbox)"; add22 "$b" "$PROBE22" "GIT_AUTHOR_DATE=2020-01-01T00:00:00Z GIT_COMMITTER_DATE=2020-01-01T00:00:00Z git commit -qm x" "unset $E_NAME $E_CMAIL"
run22 0 "$b" "близнец: время коммита и снятие переменных подписи — молчит"

b="$(mksandbox)"; add22 "$b" "$PROBE22" 'git commit --author="a <a@example.invalid>" -qm x'
run22 1 "$b" "инъекция: --author у commit — краснеет" "флагом --author"
b="$(mksandbox)"; add22 "$b" "$PROBE22" 'git log --author=a --format=%h'
run22 0 "$b" "близнец: --author как фильтр чтения — молчит"

b="$(mksandbox)"; add22 "$b" "$PROBE22" "git -c $K_MIXED=x commit -qm x"
run22 1 "$b" "инъекция: ключ подписи в другом регистре — краснеет" "подпись на команду"
b="$(mksandbox)"; add22 "$b" "$PROBE22" "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=$K_NAME GIT_CONFIG_VALUE_0=x git commit -qm x"
run22 1 "$b" "инъекция: -c окружением GIT_CONFIG_KEY — краснеет" "подпись на команду"
b="$(mksandbox)"; add22 "$b" "$PROBE22" 'git -c core.hooksPath=/dev/null commit -qm x' "# git -c $K_EMAIL=x commit — так нельзя"
run22 0 "$b" "близнец: -c другого ключа и форма в комментарии — молчит"

b="$(mksandbox)"
add22 "$b" scripts/probe-gate/probe.py 'import subprocess' "subprocess.run([\"git\", \"config\", \"$K_NAME\", \"probe\"])"
run22 1 "$b" "инъекция: Python — config подписи в репозиторий — краснеет" "probe.py:2: подпись на репозиторий"
b="$(mksandbox)"
add22 "$b" scripts/probe-gate/probe.py 'import os, subprocess' "subprocess.run([\"git\", \"commit\"], env={**os.environ, \"$E_NAME\": \"x\"})"
run22 1 "$b" "инъекция: Python — имя автора в окружении вызова — краснеет" "подпись окружением"
b="$(mksandbox)"
add22 "$b" scripts/probe-gate/probe.py 'import os, subprocess' "os.environ.pop(\"$E_NAME\", None)" \
    "subprocess.run([\"git\", \"config\", \"--get\", \"$K_NAME\"])" "\"\"\"пример: git -c $K_EMAIL=x commit\"\"\""
run22 0 "$b" "близнец: Python — снятие переменной, чтение, форма в строке документации — молчит"
b="$(mksandbox)"; add22 "$b" scripts/probe-gate/broken.py 'def f(:'
run22 2 "$b" "предпосылка: Python-файл не разобран — VOID, а не успех" "не разобраны"

b="$(mksandbox)"; add22 "$b" .github/workflows/ci.yaml "        env:" "          $E_NAME: probe"
run22 1 "$b" "инъекция: конвейер задаёт имя автора ключом env — краснеет" "ci.yaml"

# Запись файла конфигурации git мимо `git config` (ws#873). Сведение #785 с #861
# принесло в дерево песочницу check-15, чей HOME получал литерал подписи строкой
# printf в `.gitconfig`, — форму, которую распознаватель объявлял своей границей.
# Первая инъекция — та же форма, что стояла в check-15 до сведения. Заголовок
# секции и имя файла собираются из частей по той же причине, что ключи выше.
GC_USER="$(printf '[%s]' user)"
GC_FILE="$(printf '.%s' gitconfig)"
GC_REPO="$(printf '.git/%s' config)"
b="$(mksandbox)"
add22 "$b" "$PROBE22" "printf '$GC_USER\n\tname = probe\n\temail = probe@example.invalid\n[init]\n\tdefaultBranch = main\n' > \"\$HOME/$GC_FILE\""
run22 1 "$b" "инъекция: литерал подписи строкой printf в gitconfig HOME песочницы — краснеет" "$PROBE22:1: литерал подписи"
b="$(mksandbox)"
add22 "$b" "$PROBE22" "cat > \"\$TMP/home/$GC_FILE\" <<'CFG'" "$GC_USER" "	email = probe@example.invalid" "CFG"
run22 1 "$b" "инъекция: литерал подписи в heredoc в gitconfig — краснеет и называет строку тела" "$PROBE22:3: литерал подписи"
b="$(mksandbox)"
add22 "$b" "$PROBE22" "printf '$GC_USER\n\tname = probe\n' | tee -a \"\$TMP/r/$GC_REPO\" > /dev/null"
run22 1 "$b" "инъекция: литерал подписи через tee в конфиг репозитория — краснеет" "$PROBE22:1: подпись на репозиторий"
b="$(mksandbox)"
add22 "$b" "$PROBE22" "echo \"$GC_USER\" >> \"\$HOME/$GC_FILE\"" "echo \"	name = probe\" >> \"\$HOME/$GC_FILE\""
run22 1 "$b" "инъекция: секция и ключ подписи двумя echo подряд — краснеет на строке ключа" "$PROBE22:2: литерал подписи"
# Близнец обязан быть ОСМОТРЕН, а не пропущен: записей файла конфигурации в
# переписи становится ровно на три больше, чем на чистом дереве той же песочницы.
b="$(mksandbox)"
w22="$(TOOLING_GATE_ROOT="$b" bash "$HERE/$C16" 2>&1 | sed -n 's/.*записей файла конфигурации git \([0-9][0-9]*\);.*/\1/p')"
add22 "$b" "$PROBE22" "printf '[init]\n\tdefaultBranch = main\n' >> \"\$HOME/$GC_FILE\"" \
    "printf '$GC_USER\n\tname = %s\n\temail = %s\n' \"\$name\" \"\$email\" > \"\$HOME/$GC_FILE\"" \
    "cat > \"\$TMP/home/$GC_FILE\" <<CFG" "$GC_USER" "	name = \$name" "CFG" \
    "printf '$GC_USER\n\tname = probe\n' > \"\$TMP/notes.txt\""
run22 0 "$b" "близнец: секция без подписи, подпись подстановкой, heredoc с подстановкой, тот же текст не в gitconfig — осмотрен и молчит" \
    "записей файла конфигурации git $(( ${w22:-0} + 3 ));"

# Пустой обход: дерево без единого файла судимых видов. Каталог назван не на `s`,
# чтобы счёт одновременно живущих песочниц его не считал; снимается сразу.
e="$TMP/e22"; mkdir -p "$e" && git -C "$e" init -q && printf 'x\n' > "$e/README.md"
run22 2 "$e" "предпосылка: файлов оболочки, Python и конвейера нет — VOID, а не успех" "судить нечего"
rm -rf "$e"

echo "== check-17: хук отправки судит ветку гейтом цитат с тремя его исходами (ws#816) =="
C17=check-17-push-hook-runs-the-quote-gate.sh
DG09="scripts/docs-gate/check-09-quoted-make-commands-resolve.sh"

b="$(mksandbox)"
run 0 "$b" "чистое дерево — неисполнимую цитату хук останавливает, исполнимую пропускает, без дерева продукта называет «без предмета»" "$C17"
# Инъекция А — ДОСЛОВНО состояние до ws#816: гейт цитат не входит ни в один
# набор, и перечень хука его не выводит.
b="$(mksandbox "$DG09")"
run 1 "$b" "инъекция А: гейт цитат вне наборов — краснеет" "$C17"
# Инъекция Б — гейт в наборе, но вызов СПРЯТАН в комментарий: носителя нет.
b="$(mksandbox)"
if mr_patch "$b/$DG09" 's/^exec python3 /# exec python3 /m' "вызов гейта закомментирован"; then
    run 1 "$b" "инъекция Б: вызов гейта лишь в комментарии — краснеет" "$C17"
fi
# Инъекция В — хук читает «без предмета» как находку: копия без дерева продукта
# остановила бы отправку (класс ws#458).
b="$(mksandbox)"
if mr_patch "$b/$HK_REL" 's/^            2\) void\+=\("\$rref: \$g"\) ;;$/            2) failed+=("\$rref: \$g") ;;/m' \
    "двойка набора записана в провалы"; then
    run 1 "$b" "инъекция В: хук останавливает отправку на «без предмета» — краснеет" "$C17"
fi
# Близнец — безобидная правка носителя (комментарий в конце файла).
b="$(mksandbox)"
printf '\n# комментарий пробы: вызов гейта не меняется\n' >> "$b/$DG09"
run 0 "$b" "близнец: безобидная правка носителя — молчит" "$C17"
b="$(mksandbox "$HK_REL")"
run 2 "$b" "предпосылка: хука отправки нет — VOID" "$C17"

echo "== check-19: норма «Не жди» у исполнителей, застой провязан диспетчеру (ws#1001) =="
C19=check-19-no-idle-norm-is-wired.sh
b="$(mksandbox)"
run 0 "$b" "чистое дерево — молчит" "$C19"
b="$(mksandbox)"
python3 - "$b/.claude/agents/scout.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); open(p, 'w').write(s.replace('`CLAUDE.md` «Не жди»', '`CLAUDE.md`'))
PY
run 1 "$b" "инъекция: у scout снята ссылка на норму — краснеет" "$C19"
b="$(mksandbox)"
python3 - "$b/.claude/agents/scout.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); open(p, 'w').write(s.replace('`CLAUDE.md` «Не жди»', '`CLAUDE.md`\n«Не жди»'))
PY
run 0 "$b" "близнец: перенос строки внутри ссылки на норму — та же норма, молчит" "$C19"
b="$(mksandbox)"
python3 - "$b/CLAUDE.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); open(p, 'w').write(s.replace('Ни один вызов не держит ожидание дольше 10\n  минут', 'Вызов держит ожидание сколько нужно'))
PY
run 1 "$b" "инъекция: норма в протоколе вывернута — краснеет" "$C19"
b="$(mksandbox)"
python3 - "$b/.claude/settings.json" <<'PY'
import json, sys; p = sys.argv[1]; d = json.load(open(p))
for g in d['hooks']['Stop']: g['hooks'] = [h for h in g['hooks'] if 'stall-signal' not in h.get('command', '')]
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
PY
run 1 "$b" "инъекция: хук застоя снят со Stop — краснеет" "$C19"
b="$(mksandbox "scripts/stall-census.sh")"
run 1 "$b" "инъекция: прибора застоя нет — краснеет" "$C19"
b="$(mksandbox)"
printf '\n# комментарий пробы\n' >> "$b/.claude/hooks/stall-signal.sh"
run 0 "$b" "близнец: безобидная правка хука — молчит" "$C19"
# ws#1004: отказ ожиданию провязан в PreToolUse Bash, правило о чужих файлах — в базе.
b="$(mksandbox)"
python3 - "$b/.claude/settings.json" <<'PY'
import json, sys; p = sys.argv[1]; d = json.load(open(p))
for g in d['hooks']['PreToolUse']: g['hooks'] = [h for h in g['hooks'] if 'no-wait-guard' not in h.get('command', '')]
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
PY
run 1 "$b" "инъекция: no-wait-guard снят с PreToolUse — краснеет" "$C19"
b="$(mksandbox)"
python3 - "$b/.claude/settings.json" <<'PY'
import json, sys; p = sys.argv[1]; d = json.load(open(p))
for g in d['hooks']['PreToolUse']:
    if any('no-wait-guard' in h.get('command', '') for h in g['hooks']): g['matcher'] = 'Monitor'
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
PY
run 1 "$b" "инъекция: no-wait-guard под матчером Monitor (Bash мимо) — краснеет" "$C19"
b="$(mksandbox)"
python3 - "$b/.claude/settings.json" <<'PY'
import json, sys; p = sys.argv[1]; d = json.load(open(p))
for g in d['hooks']['PreToolUse']:
    if any('no-wait-guard' in h.get('command', '') for h in g['hooks']): g['matcher'] = 'Bash|Monitor'
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
PY
run 0 "$b" "близнец: матчер Bash|Monitor — Bash под ним, молчит" "$C19"
b="$(mksandbox ".claude/hooks/no-wait-guard/guard.py")"
run 1 "$b" "инъекция: разбора no-wait-guard нет — краснеет" "$C19"
# Провязка судится по ФАЙЛУ, который исполнит команда, а не по подстроке имени:
# неверный путь и выключенная копия дают хуку код 127 — страж выключен молча.
nwg_cmd() {
    python3 - "$1/.claude/settings.json" "$2" <<'PY'
import json, sys; p = sys.argv[1]; d = json.load(open(p))
for g in d['hooks']['PreToolUse']:
    for h in g['hooks']:
        if 'no-wait-guard' in h.get('command', ''): h['command'] = sys.argv[2]
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
PY
}
b="$(mksandbox)"
nwg_cmd "$b" 'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/no-wait-guard/no-wait-guard.sh"'
run 1 "$b" "инъекция: PreToolUse зовёт несуществующий путь (имя хука в подкаталоге) — краснеет" "$C19"
b="$(mksandbox)"
nwg_cmd "$b" 'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/no-wait-guard.sh.off"'
run 1 "$b" "инъекция: PreToolUse зовёт выключенную копию «.off» — краснеет" "$C19"
b="$(mksandbox)"
chmod -x "$b/.claude/hooks/no-wait-guard.sh"
run 1 "$b" "инъекция: канонический хук не исполним — краснеет" "$C19"
b="$(mksandbox)"
nwg_cmd "$b" 'bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/no-wait-guard.sh"'
run 0 "$b" "близнец: канонический путь в форме \${CLAUDE_PROJECT_DIR} — молчит" "$C19"
b="$(mksandbox)"
python3 - "$b/.claude/agents/dispatcher.md" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); open(p, 'w').write(s.replace('`blocked` — лишь за файлом соседа', '`blocked` — по усмотрению'))
PY
run 1 "$b" "инъекция: правило о чужих файлах снято из базы — краснеет" "$C19"

echo
# Мутация образца последней пробой вердиктов уже не меняет, но это запись вне
# своей песочницы — та же поломка, что у любой предыдущей пробы.
drop_current
template_intact || premise_broken "образец песочниц изменён после пробы №$probes: следующие пробы получили бы её мутацию"
premise_or_void
# Объём осмотренного печатается вместе с числом проб: «проб 49, провалов 0» без
# размера песочницы не отличимо от того же числа проб на четверти дерева.
echo "[CENSUS] inject: проб исполнено $probes, провалов $failed; в каждой песочнице файлов $SANDBOX_FILES"
if [ "$probes" -eq 0 ]; then
    echo "[VOID] inject — ни одной пробы не исполнено" >&2
    exit 2
fi
maxlive="$(cat "$TMP/MAXLIVE" 2>/dev/null || echo 0)"
echo "[CENSUS] inject: песочниц на диске одновременно не больше $maxlive"
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] inject — гейт не доказан: провалов $failed из $probes" >&2
    exit 1
fi
if [ "$maxlive" -gt 1 ]; then
    echo "[FAIL] inject — песочниц одновременно жило $maxlive: проба не снимает свою" >&2
    exit 1
fi
echo "[PASS] inject — гейт доказан в обе стороны: проб $probes, провалов 0"
