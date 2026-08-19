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
mksandbox() {
    local drop="${1:-}"
    local dir
    dir="$(mktemp -d "$TMP/sXXXXXX")"
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

# run <ожидаемый-код> <песочница> <имя-пробы> <скрипт>
#
# `TOOLING_GATE_REQUIRED_CONTEXTS` пробрасывается из окружения вызова: сетевую
# половину check-05 доказываем ОФЛАЙН, задав перечень контекстов извне. Ходить за
# ним в сеть из доказательства нельзя — у токена ранера нет права читать защиту
# ветки, и проба стала бы «не выполнилось», поданным как зелёное.
run() {
    local want="$1" box="$2" name="$3" script="$4" got out
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
