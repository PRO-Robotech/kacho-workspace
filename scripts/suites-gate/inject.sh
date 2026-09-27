#!/usr/bin/env bash
# Доказательство набора suites-gate: каждая проверка СПОСОБНА упасть на настоящем
# дефекте и СПОСОБНА смолчать на его законном близнеце той же формы.
#
# УСТРОЙСТВО. Каждая проба строит песочницу — отдельный git-репозиторий с копией
# `scripts/lib/` и наборами, чьи ИМЕНА выведены из настоящего дерева (перепись
# `scripts/lib/suites.py`): набор, заведённый завтра, получит свою инъекцию сам.
# Проверку направляют на песочницу переменной `SUITES_GATE_ROOT` и читают исход —
# код выхода И текст находки: покраснеть не по той причине — не доказательство.
#
# Исходы: 0 — все пробы сошлись; 1 — есть несошедшаяся; 2 — проб не исполнено.
# Шаблоны проб ниже — ТЕКСТ исполняемого кода, который пишется в файл песочницы;
# подстановка в них на этапе записи была бы дефектом, а не намерением.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mapfile -t SUITES < <(python3 "$WS/scripts/lib/suites.py" suites "$WS")
if [ "${#SUITES[@]}" -eq 0 ] || [ -z "${SUITES[0]}" ]; then
    echo "[VOID] inject — перепись наборов настоящего дерева пуста: инъекции не во что вносить" >&2
    exit 2
fi

probes=0; failed=0

# mkbox — пустая песочница: git-репозиторий с копией общей библиотеки наборов.
mkbox() {
    local b
    b="$(mktemp -d "$TMP/box.XXXXXX")"
    git -C "$b" init -q
    mkdir -p "$b/scripts"
    cp -R "$WS/scripts/lib" "$b/scripts/lib"
    printf '%s' "$b"
}

# suite <песочница> <набор> — набор в песочнице: одного run-all.sh достаточно,
# чтобы перепись признала каталог набором.
suite() {
    mkdir -p "$1/scripts/$2"
    printf '#!/usr/bin/env bash\necho "осмотрено 0"\n' > "$1/scripts/$2/run-all.sh"
    chmod +x "$1/scripts/$2/run-all.sh"
}

commit() { git -C "$1" add -A -f >/dev/null 2>&1; }

# proof <песочница> <набор> — доказательство набора (для конвейерных проб).
proof() { printf '#!/usr/bin/env bash\necho "проб 1"\n' > "$1/scripts/$2/inject.sh"; }

# expect <код> <песочница> <заголовок> <проверка> [<обязательная подстрока>…]
expect() {
    local want="$1" box="$2" title="$3" check="$4" out got s miss=""
    shift 4
    probes=$((probes + 1))
    out="$(cd "$TMP" && env -u GATE_ROOT SUITES_GATE_ROOT="$box" python3 "$HERE/$check" 2>&1)"; got=$?
    for s in "$@"; do
        grep -qF -- "$s" <<<"$out" || miss="$miss «$s»"
    done
    if [ "$got" -eq "$want" ] && [ -z "$miss" ]; then
        echo "  ok   $title (код $got)"
    else
        echo "  ПРОВАЛ $title — ждали код $want, получили $got${miss:+; в выводе нет:$miss}" >&2
        printf '         %s\n' "${out//$'\n'/$'\n'         }" >&2
        failed=$((failed + 1))
    fi
}

# ── check-01: корень из рабочего каталога ────────────────────────────────────
#
# Дефект — проверка ПРАВИЛЬНОЙ во всём остальном формы: печатает перепись, на
# пустом дереве отвечает VOID. Отличается от близнеца РОВНО строкой получения
# корня: `git rev-parse --show-toplevel` (рабочий каталог) против
# `scripts/lib/gate_root.py` (расположение).
C01="check-01-check-root-is-not-the-working-directory.py"
CWD_CHECK='ws="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "[VOID] корня нет" >&2; exit 2; }'
LOC_CHECK='ws="$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/gate_root.py" - "${BASH_SOURCE[0]}")" || exit 2'

# plant <песочница> <набор> <строка корня>
plant() {
    {
        printf '#!/usr/bin/env bash\nset -uo pipefail\n%s\n' "$3"
        printf 'n="$(git -C "$ws" ls-files "scripts/*/run-all.sh" | wc -l)"\n'
        printf '[ "$n" -gt 0 ] || { echo "[VOID] наборов 0" >&2; exit 2; }\n'
        printf 'echo "[CENSUS] наборов осмотрено $n"\n'
    } > "$1/scripts/$2/check-01-probe.sh"
    chmod +x "$1/scripts/$2/check-01-probe.sh"
}

echo "== check-01: проверка берёт корень из рабочего каталога =="

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; plant "$b" "$s" "$LOC_CHECK"; done
commit "$b"
expect 0 "$b" "близнец: во всех ${#SUITES[@]} наборах корень из расположения — молчит" "$C01" \
    "проверок ${#SUITES[@]}"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"
        if [ "$t" = "$s" ]; then plant "$b" "$t" "$CWD_CHECK"; else plant "$b" "$t" "$LOC_CHECK"; fi
    done
    commit "$b"
    expect 1 "$b" "инъекция в $s: корень из рабочего каталога — краснеет с координатой" "$C01" \
        "scripts/$s/check-01-probe.sh — исход зависит от рабочего каталога" \
        "scripts/$s/check-01-probe.sh:3" "находок 1"
done

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID, а не «находок 0»" "$C01" "наборов scripts/*/run-all.sh"

b="$(mkbox)"; suite "$b" "${SUITES[0]}"; commit "$b"
expect 2 "$b" "предпосылка: набор есть, проверок в нём нет — VOID" "$C01" "проверок check-* в них 0"

# ── check-02: пустое дерево выдано за чистое ─────────────────────────────────
#
# Дефекты — две формы одного исхода «ноль на пустом дереве»: проверка, которая
# ноль прочитанного объявляет чистотой, и проверка, которая не читает общее
# переопределение корня и судит своё расположение. Близнец — та же проверка,
# отвечающая на пустом дереве VOID.
C02="check-02-empty-tree-is-not-a-clean-verdict.py"
VACUOUS='echo "[CENSUS] наборов осмотрено $n"; exit 0'
HONEST='[ "$n" -gt 0 ] || { echo "[VOID] наборов 0" >&2; exit 2; }; echo "[CENSUS] наборов осмотрено $n"'
LOC_ONLY='ws="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'

# plant2 <песочница> <набор> <строка корня> <строка исхода>
plant2() {
    {
        printf '#!/usr/bin/env bash\nset -uo pipefail\n%s\n' "$3"
        printf 'n="$(git -C "$ws" ls-files "scripts/*/run-all.sh" | wc -l)"\n'
        printf '%s\n' "$4"
    } > "$1/scripts/$2/check-01-probe.sh"
    chmod +x "$1/scripts/$2/check-01-probe.sh"
}

echo "== check-02: пустое дерево выдано за чистое =="

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; plant2 "$b" "$s" "$LOC_CHECK" "$HONEST"; done
commit "$b"
expect 0 "$b" "близнец: во всех ${#SUITES[@]} наборах пустое дерево — VOID — молчит" "$C02" \
    "проверок ${#SUITES[@]}"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"
        if [ "$t" = "$s" ]; then plant2 "$b" "$t" "$LOC_CHECK" "$VACUOUS"
        else plant2 "$b" "$t" "$LOC_CHECK" "$HONEST"; fi
    done
    commit "$b"
    expect 1 "$b" "инъекция в $s: ноль осмотренного выдан за чистоту — краснеет с координатой" "$C02" \
        "scripts/$s/check-01-probe.sh — направлена на пустое дерево и вышла нулём" "находок 1"
done

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    if [ "$s" = "${SUITES[0]}" ]; then plant2 "$b" "$s" "$LOC_ONLY" "$HONEST"
    else plant2 "$b" "$s" "$LOC_CHECK" "$HONEST"; fi
done
commit "$b"
expect 1 "$b" "инъекция: проверка не читает GATE_ROOT и судит своё расположение — краснеет" "$C02" \
    "scripts/${SUITES[0]}/check-01-probe.sh — направлена на пустое дерево и вышла нулём"

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID" "$C02" "наборов scripts/*/run-all.sh"

# ── check-03: прогонщик набора засчитывает молчаливый ноль ─────────────────────
#
# Близнец — общий прогонщик в каждом наборе (так устроены все наборы дерева).
# Дефект — прогонщик ПРЕЖНЕЙ формы, дословно той, что была у наборов до ws#762:
# тот же глоб, те же три кода, но исход — из одного канала, проверка
# исполняется из каталога вызывающего, строки переписи нет.
C03="check-03-runner-demands-a-printed-volume.py"
SHIM="$WS/scripts/suites-gate/run-all.sh"

old_runner() {
    {
        printf '#!/usr/bin/env bash\nset -uo pipefail\n'
        printf 'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        printf 'ok=0; bad=0; void=0; count=0\n'
        printf 'for c in "$here"/check-*.sh; do\n'
        printf '    [ -f "$c" ] || continue\n    count=$((count + 1))\n    bash "$c"\n'
        printf '    case $? in 0) ok=$((ok+1));; 2) void=$((void+1));; *) bad=$((bad+1));; esac\n'
        printf 'done\n'
        printf 'echo "рассмотрено проверок $count; пройдено $ok, провалено $bad, без предмета $void"\n'
        printf '[ "$count" -gt 0 ] || exit 1\n[ "$bad" -eq 0 ] || exit 1\n[ "$void" -eq 0 ] || exit 2\nexit 0\n'
    } > "$1/scripts/$2/run-all.sh"
    chmod +x "$1/scripts/$2/run-all.sh"
}

shim() { mkdir -p "$1/scripts/$2"; cp "$SHIM" "$1/scripts/$2/run-all.sh"; chmod +x "$1/scripts/$2/run-all.sh"; }

echo "== check-03: прогонщик засчитывает молчаливый ноль и отдаёт проверке свой каталог =="

b="$(mkbox)"
for s in "${SUITES[@]}"; do shim "$b" "$s"; done
commit "$b"
expect 0 "$b" "близнец: во всех ${#SUITES[@]} наборах общий прогонщик — молчит" "$C03" \
    "прогонщиков осмотрено ${#SUITES[@]}"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"
    for t in "${SUITES[@]}"; do
        if [ "$t" = "$s" ]; then mkdir -p "$b/scripts/$t"; old_runner "$b" "$t"; else shim "$b" "$t"; fi
    done
    commit "$b"
    expect 1 "$b" "инъекция в $s: прогонщик прежней формы — краснеет по трём свойствам" "$C03" \
        "scripts/$s/run-all.sh — проверка вышла нулём, не напечатав ни одного числа" \
        "scripts/$s/run-all.sh — проверка исполнена из рабочего каталога вызывающего" \
        "scripts/$s/run-all.sh — не записал машинную строку переписи" "находок 3"
done

b="$(mkbox)"
for s in "${SUITES[@]}"; do shim "$b" "$s"; done
printf '#!/usr/bin/env bash\nexit 1\n' > "$b/scripts/${SUITES[0]}/run-all.sh"
commit "$b"
expect 2 "$b" "положительный контроль сорван — VOID, а не «доказано»" "$C03" \
    "scripts/${SUITES[0]}/run-all.sh — на единственной проверке, напечатавшей объём, вернул 1"

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: прогонщиков нет — VOID" "$C03" "прогонщиков scripts/*/run-all.sh"

# ── check-04: конвейер не зовёт набор дерева ─────────────────────────────────
#
# Процесс — отдельный файл песочницы. Дефект — перечень наборов, выписанный от
# руки без одного набора (так конвейер и был устроен до ws#753); близнецы — тот
# же перечень полностью и вывод перечня `scripts/lib/run-suites.sh`. Второй
# дефект — вывод перечня, стоящий только в КОММЕНТАРИИ: читается код, не текст.
C04="check-04-ci-calls-every-suite.py"

# wf <песочница> <тело шага run: построчно>…
wf() {
    local box="$1" line; shift
    mkdir -p "$box/.github/workflows"
    {
        printf 'name: injected\non:\n  workflow_dispatch:\njobs:\n  suites:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n'
        for line in "$@"; do printf '          %s\n' "$line"; done
    } > "$box/.github/workflows/ci.yaml"
}

echo "== check-04: конвейер не зовёт набор дерева =="

b="$(mkbox)"; calls=()
for s in "${SUITES[@]}"; do suite "$b" "$s"; proof "$b" "$s"; calls+=("bash scripts/$s/inject.sh" "bash scripts/$s/run-all.sh"); done
wf "$b" "${calls[@]}"; commit "$b"
expect 0 "$b" "близнец: все ${#SUITES[@]} наборов вписаны поимённо — молчит" "$C04" \
    "наборов в дереве ${#SUITES[@]}; вызвано конвейером ${#SUITES[@]}; не вызвано 0"

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; proof "$b" "$s"; done
wf "$b" "bash scripts/lib/run-suites.sh --proofs --void-is-failure"; commit "$b"
expect 0 "$b" "близнец: вывод перечня — все наборы вызваны без выписанного списка — молчит" "$C04" \
    "вывод перечня: .github/workflows/ci.yaml/suites"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"; calls=()
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"; proof "$b" "$t"; calls+=("bash scripts/$t/inject.sh")
        [ "$t" = "$s" ] || calls+=("bash scripts/$t/run-all.sh")
    done
    wf "$b" "${calls[@]}"; commit "$b"
    expect 1 "$b" "инъекция: перечень от руки без $s — краснеет с именем набора" "$C04" \
        "набор $s есть в дереве (scripts/$s/run-all.sh), а конвейер его не зовёт" "не вызвано 1"
done

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; done
wf "$b" "# bash scripts/lib/run-suites.sh — только в комментарии" "true"; commit "$b"
expect 1 "$b" "инъекция: вывод перечня только в комментарии — читается код, краснеет" "$C04" \
    "не вызвано ${#SUITES[@]}"

b="$(mkbox)"; suite "$b" "${SUITES[0]}"; commit "$b"
expect 2 "$b" "предпосылка: процессов конвейера нет — VOID" "$C04" "файлов конвейера"

b="$(mkbox)"; wf "$b" "true"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID" "$C04" "наборов scripts/*/run-all.sh"

# ── check-04, вторая ось: конвейер не зовёт доказательство набора (ws#817) ─
#
# Дефект — дословно форма ствола до ws#753: прогоны всех наборов вписаны, а
# `inject.sh` одного набора — нет (так было у crossrepo-gate). Второй дефект —
# вывод перечня без `--proofs`: наборы исполняются, доказательства — нет.
# Близнецы — тот же список с доказательством и вывод перечня с `--proofs`.
echo "== check-04: конвейер не зовёт доказательство набора =="

b="$(mkbox)"; calls=()
for s in "${SUITES[@]}"; do suite "$b" "$s"; proof "$b" "$s"; calls+=("bash scripts/$s/inject.sh" "bash scripts/$s/run-all.sh"); done
wf "$b" "${calls[@]}"; commit "$b"
expect 0 "$b" "близнец: прогон и доказательство каждого набора вписаны — молчит" "$C04" \
    "доказательств вызвано ${#SUITES[@]} из ${#SUITES[@]}"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"; calls=()
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"; proof "$b" "$t"
        calls+=("bash scripts/$t/run-all.sh")
        [ "$t" = "$s" ] || calls+=("bash scripts/$t/inject.sh")
    done
    wf "$b" "${calls[@]}"; commit "$b"
    expect 1 "$b" "инъекция: доказательство $s не вызвано — краснеет с именем набора" "$C04" \
        "доказательство набора $s (scripts/$s/inject.sh) конвейер не зовёт"
done

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; proof "$b" "$s"; done
wf "$b" "bash scripts/lib/run-suites.sh --void-is-failure"; commit "$b"
expect 1 "$b" "инъекция: вывод перечня без --proofs — доказательства не исполняются" "$C04" \
    "доказательств вызвано 0 из ${#SUITES[@]}"

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; proof "$b" "$s"; done
wf "$b" "bash scripts/lib/run-suites.sh --proofs --void-is-failure"; commit "$b"
expect 0 "$b" "близнец: вывод перечня с --proofs — молчит" "$C04" \
    "доказательств вызвано ${#SUITES[@]} из ${#SUITES[@]}"

b="$(mkbox)"; calls=()
for s in "${SUITES[@]}"; do
    suite "$b" "$s"; calls+=("bash scripts/$s/run-all.sh")
    if [ "$s" != "${SUITES[0]}" ]; then proof "$b" "$s"; calls+=("bash scripts/$s/inject.sh"); fi
done
wf "$b" "${calls[@]}"; commit "$b"
expect 1 "$b" "инъекция: у набора нет доказательства вовсе — краснеет" "$C04" \
    "у набора ${SUITES[0]} нет доказательства scripts/${SUITES[0]}/inject.sh"

# ── check-05: номер проверки — неоднозначный адрес ───────────────────────────
#
# Дефект — дословно форма docs-gate до ws#754: второй файл с уже занятым номером.
# Законный близнец — тот же файл со СЛЕДУЮЩИМ свободным номером. Отдельно —
# разрыв (снятая проверка, чей номер остался дырой) и имя без номера.
C05="check-05-check-numbers-are-unique-and-gapless.py"

# numbered <песочница> <набор> <имя проверки>…
numbered() {
    local box="$1" s="$2" n; shift 2
    for n in "$@"; do printf '#!/usr/bin/env bash\necho "осмотрено 1"\n' > "$box/scripts/$s/$n"; done
}

echo "== check-05: номер проверки — неоднозначный адрес =="

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; numbered "$b" "$s" check-01-a.sh check-02-b.py check-03-c.sh; done
commit "$b"
expect 0 "$b" "близнец: в каждом наборе 01…03 без повторов и разрывов — молчит" "$C05" \
    "проверок $((3 * ${#SUITES[@]}))"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"; numbered "$b" "$t" check-01-a.sh check-02-b.py check-03-c.sh
        [ "$t" = "$s" ] && numbered "$b" "$t" check-03-second-carrier.py
    done
    commit "$b"
    expect 1 "$b" "инъекция в $s: второй носитель номера 03 — краснеет, названы оба" "$C05" \
        "$s: номер 03 несут 2 проверки — scripts/$s/check-03-c.sh, scripts/$s/check-03-second-carrier.py" \
        "находок 1"
done

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"; numbered "$b" "$s" check-01-a.sh check-02-b.py check-03-c.sh
    [ "$s" = "${SUITES[0]}" ] && numbered "$b" "$s" check-04-next-free.py
done
commit "$b"
expect 0 "$b" "близнец: тот же новый файл со следующим свободным номером — молчит" "$C05"

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    if [ "$s" = "${SUITES[0]}" ]; then numbered "$b" "$s" check-01-a.sh check-03-c.sh
    else numbered "$b" "$s" check-01-a.sh check-02-b.py check-03-c.sh; fi
done
commit "$b"
expect 1 "$b" "инъекция: разрыв — номера 02 нет, а 03 есть — краснеет" "$C05" \
    "${SUITES[0]}: номера check-02 нет, а старшие есть"

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"; numbered "$b" "$s" check-01-a.sh
    [ "$s" = "${SUITES[0]}" ] && numbered "$b" "$s" check-unnumbered.sh
done
commit "$b"
expect 1 "$b" "инъекция: имя проверки без номера — краснеет" "$C05" \
    "scripts/${SUITES[0]}/check-unnumbered.sh — имя проверки без номера"

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID, а не «повторов 0»" "$C05" "наборов scripts/*/run-all.sh"

b="$(mkbox)"; suite "$b" "${SUITES[0]}"; commit "$b"
expect 2 "$b" "предпосылка: проверок нет — VOID" "$C05" "проверок check-* в них 0"

# ── check-06: число в шапке без команды воспроизведения ──────────────────────
#
# Дефект — дословно шапка inject-06-corpus-ceiling.sh, на которой класс найден:
# «по семи осям» без команды (разметка секций давала три, полоса насчитала
# одиннадцать). Близнецы — то же число со своей командой, цифрой и словом, и
# формы, которые числом-утверждением не являются: легенда кода, номер задачи,
# номер проверки, координата строки.
C06="check-06-header-numbers-carry-their-predicate.py"

# script6 <песочница> <набор> <шапка построчно>… — скрипт верхнего уровня набора
# с заданной шапкой и тремя размеченными секциями «── ось» в теле.
script6() {
    local box="$1" s="$2" line; shift 2
    {
        printf '#!/usr/bin/env bash\n'
        for line in "$@"; do printf '# %s\n' "$line"; done
        printf 'set -uo pipefail\n'
        printf '# ── ось A\n# ── ось B\n# ── ось C\n'
    } > "$box/scripts/$s/inject-06-axes.sh"
}

echo "== check-06: число в шапке без команды воспроизведения =="

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    script6 "$b" "$s" "ЧАСТЬ инъекции: доказательство по осям; осей — 3" \
        "(предикат: \`grep -c '^# ── ось' scripts/$s/inject-06-axes.sh\`)." "" \
        "Исходы: 2 — без предмета; задача #760; соседняя check-03; координата :124."
done
commit "$b"
expect 0 "$b" "близнец: число с командой, чей вывод совпадает, и нечисловые формы — молчит" "$C06" \
    "воспроизведено командой ${#SUITES[@]}"

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    script6 "$b" "$s" "три оси разобраны (\`grep -c '^# ── ось' scripts/$s/inject-06-axes.sh\`)."
done
commit "$b"
expect 0 "$b" "близнец: число словом, команда совпадает — молчит" "$C06" \
    "воспроизведено командой ${#SUITES[@]}"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"
        if [ "$t" = "$s" ]; then
            script6 "$b" "$t" "ЧАСТЬ инъекции набора: доказательство check-06 по семи" \
                "осям — перевес потолка, строка без red:, нечётный backtick."
        else
            script6 "$b" "$t" "три оси разобраны (\`grep -c '^# ── ось' scripts/$t/inject-06-axes.sh\`)."
        fi
    done
    commit "$b"
    expect 1 "$b" "инъекция в $s: «по семи осям» без команды — краснеет с координатой" "$C06" \
        "scripts/$s/inject-06-axes.sh:2 — «семи" "находок 1"
done

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    if [ "$s" = "${SUITES[0]}" ]; then
        script6 "$b" "$s" "семь осей (\`grep -c '^# ── ось' scripts/$s/inject-06-axes.sh\`)."
    else
        script6 "$b" "$s" "три оси разобраны (\`grep -c '^# ── ось' scripts/$s/inject-06-axes.sh\`)."
    fi
done
commit "$b"
expect 1 "$b" "инъекция: команда есть, но её вывод разошёлся с числом — краснеет" "$C06" \
    "объявлено семь, команды абзаца дают другое" "→ 3"

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID" "$C06" "наборов scripts/*/run-all.sh"

# ── check-07: вердикт из трубы в grep -q под pipefail ───────────────────────
#
# Сначала — что класс НАСТОЯЩИЙ, а не теоретический: сама форма, исполненная на
# входе, где искомое ЕСТЬ (первой строкой), под pipefail отвечает «не найдено»,
# а законная форма — «найдено». Без этой пробы гейт ловил бы стиль, а не дефект.
C07="check-07-no-verdict-from-a-pipe.py"
echo "== check-07: вердикт из трубы в grep -q под pipefail =="
probes=$((probes + 1))
premise="$(bash -c 'set -o pipefail; big="$(seq 1 300000)"; if printf "%s\n" "$big" | grep -q "^1$"; then echo pipe:found; else echo pipe:lost; fi; if grep -q "^1$" <<<"$big"; then echo herestring:found; else echo herestring:lost; fi')"
if grep -qx 'pipe:lost' <<<"$premise" && grep -qx 'herestring:found' <<<"$premise"; then
    echo "  ok   предпосылка класса: труба в grep -q под pipefail объявила найденное ненайденным, here-string — нашёл"
else
    echo "  ПРОВАЛ предпосылка класса не воспроизвелась: ${premise//$'\n'/, }" >&2
    failed=$((failed + 1))
fi

# pipescript <песочница> <набор> <имя> <строки кода>… — скрипт набора под pipefail
pipescript() {
    local box="$1" s="$2" name="$3" line; shift 3
    {
        printf '#!/usr/bin/env bash\nset -uo pipefail\nout="$(cat)"\n'
        for line in "$@"; do printf '%s\n' "$line"; done
    } > "$box/scripts/$s/$name"
}

LAWFUL='if grep -qF -- "находка" <<<"$out"; then exit 1; fi'
PIPED='if printf "%s\n" "$out" | grep -qF -- "находка"; then exit 1; fi'

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    pipescript "$b" "$s" check-01-probe.sh "$LAWFUL" \
        '# форма в комментарии — не код: printf "%s" "$out" | grep -q x' \
        'echo "printf | grep -q — в строке, а не в трубе"'
done
commit "$b"
expect 0 "$b" "близнец: чтение и поиск разведены; форма в комментарии и в строке — молчит" "$C07" \
    "форм «труба в grep -q» 0"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"
        if [ "$t" = "$s" ]; then pipescript "$b" "$t" check-01-probe.sh "$PIPED"
        else pipescript "$b" "$t" check-01-probe.sh "$LAWFUL"; fi
    done
    commit "$b"
    expect 1 "$b" "инъекция в $s: труба в grep -q под pipefail — краснеет с координатой" "$C07" \
        "scripts/$s/check-01-probe.sh:4 — вердикт из трубы в grep" "находок 1"
done

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    if [ "$s" = "${SUITES[0]}" ]; then
        pipescript "$b" "$s" check-01-probe.sh "$LAWFUL  # pipe-safe: писатель доживает до конца"
    else pipescript "$b" "$s" check-01-probe.sh "$LAWFUL"; fi
done
commit "$b"
expect 1 "$b" "инъекция: пометка pipe-safe там, где трубы нет — послабление без предмета" "$C07" \
    "пометка \`pipe-safe\` на строке, где трубы в grep нет"

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    if [ "$s" = "${SUITES[0]}" ]; then
        pipescript "$b" "$s" check-01-probe.sh "$PIPED  # pipe-safe: вход — одна строка, писатель доживает до конца"
    else pipescript "$b" "$s" check-01-probe.sh "$LAWFUL"; fi
done
commit "$b"
expect 0 "$b" "близнец: труба, помеченная pipe-safe с причиной, — молчит и сочтена" "$C07" \
    "помечено pipe-safe 1"

b="$(mkbox)"
for s in "${SUITES[@]}"; do
    suite "$b" "$s"
    printf '#!/usr/bin/env bash\nout="$(cat)"\n%s\n' "$PIPED" > "$b/scripts/$s/check-01-probe.sh"
done
commit "$b"
expect 0 "$b" "близнец: та же труба БЕЗ pipefail — исход равен исходу grep, молчит" "$C07" \
    "без pipefail $((2 * ${#SUITES[@]}))"

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID" "$C07" "наборов scripts/*/run-all.sh"

echo
echo "[CENSUS] inject: наборов в переписи ${#SUITES[@]}; проб исполнено $probes, провалов $failed"
if [ "$probes" -eq 0 ]; then
    echo "[VOID] inject — ни одной пробы не исполнено" >&2
    exit 2
fi
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] inject — набор не доказан: провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] inject — набор доказан в обе стороны: проб $probes, провалов 0"
