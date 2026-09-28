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
# Окружение — своё: проверки набора читают указатели на деревья
# (scripts/lib/proofs.sh).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$HERE/../lib/proofs.sh"
proof_own_environment
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

# mutate <файл> <было> <стало> — однофактный мутант КОПИИ настоящего файла в
# песочнице. «Было» обязано встречаться ровно один раз: мутант, который не внёсся,
# сделал бы пробу тождественно зелёной, и это провал пробы, а не её успех.
mutate() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:4]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
n = text.count(old)
if n != 1:
    print("мутант не внесён: «%s» встречается в %s %d раз(а), ждали 1" % (old, path, n),
          file=sys.stderr)
    sys.exit(1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text.replace(old, new))
PY
}

# unplanted <заголовок> — мутант не внёсся: проба засчитывается провалом.
unplanted() {
    probes=$((probes + 1)); failed=$((failed + 1))
    echo "  ПРОВАЛ $1 — мутант не внесён, проба недоказательна" >&2
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

# Форма «переопределение, иначе рабочий каталог» (круг 1): пару A/B она проходит —
# там переопределение задано, и запасная ветка не исполняется ни разу; пару C/D
# (без переопределений, копия проверки в другом дереве) — нет.
DEFAULT_CHECK='ws="${GATE_ROOT:-$(git rev-parse --show-toplevel)}"'
for s in "${SUITES[@]}"; do
    b="$(mkbox)"
    for t in "${SUITES[@]}"; do
        suite "$b" "$t"
        if [ "$t" = "$s" ]; then plant "$b" "$t" "$DEFAULT_CHECK"; else plant "$b" "$t" "$LOC_CHECK"; fi
    done
    commit "$b"
    expect 1 "$b" "инъекция в $s: переопределение, иначе рабочий каталог — краснеет с координатой" "$C01" \
        "scripts/$s/check-01-probe.sh — без переопределения исход зависит от рабочего каталога" \
        "scripts/$s/check-01-probe.sh:3" "находок 1"
done

# Мутант ОБЩЕЙ ветки расположения: `scripts/lib/gate_root.py` при отсутствии
# переопределения отдаёт рабочий каталог. Им пользуется каждая проверка, и находка
# обязана назвать каждую — с координатой, а не массовым отказом полного прогона.
b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; plant "$b" "$s" "$LOC_CHECK"; done
commit "$b"
if mutate "$b/scripts/lib/gate_root.py" '    here = os.path.dirname(os.path.abspath(file))' \
        "$(printf '    return os.getcwd()\n    here = os.path.dirname(os.path.abspath(file))')"; then
    expect 1 "$b" "мутант: gate_root.py без переопределения отдаёт рабочий каталог — краснеет у каждой проверки" "$C01" \
        "scripts/${SUITES[0]}/check-01-probe.sh — без переопределения исход зависит от рабочего каталога" \
        "находок ${#SUITES[@]}"
else
    unplanted "мутант gate_root.py"
fi

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

# Исход на пустом дереве — ТОЛЬКО «без предмета» с причиной (решение диспетчера
# 2026-09-28). Три дефекта той же формы, что близнец, — отличаются строкой исхода:
# находка вместо «без предмета», «без предмета» молча, код вне трёх исходов.
FINDS='[ "$n" -gt 0 ] || { echo "[FAIL] наборов 0 — обход пуст" >&2; exit 1; }; echo "[CENSUS] наборов осмотрено $n"'
MUTE='[ "$n" -gt 0 ] || exit 2; echo "[CENSUS] наборов осмотрено $n"'
ODD='[ "$n" -gt 0 ] || { echo "[VOID] наборов 0" >&2; exit 3; }; echo "[CENSUS] наборов осмотрено $n"'

# one02 <исход в первом наборе> — первый набор несёт дефект, прочие — близнеца.
one02() {
    local b s
    b="$(mkbox)"
    for s in "${SUITES[@]}"; do
        suite "$b" "$s"
        if [ "$s" = "${SUITES[0]}" ]; then plant2 "$b" "$s" "$LOC_CHECK" "$1"
        else plant2 "$b" "$s" "$LOC_CHECK" "$HONEST"; fi
    done
    commit "$b"
    printf '%s' "$b"
}

b="$(one02 "$FINDS")"
expect 1 "$b" "инъекция: на пустом дереве код находки (1) вместо «без предмета» — краснеет" "$C02" \
    "scripts/${SUITES[0]}/check-01-probe.sh — на пустом дереве вышла кодом находки (1)" "находок 1"

b="$(one02 "$MUTE")"
expect 1 "$b" "инъекция: «без предмета» без единого слова причины — краснеет" "$C02" \
    "scripts/${SUITES[0]}/check-01-probe.sh — на пустом дереве код 2 без единого слова" "находок 1"

b="$(one02 "$ODD")"
expect 1 "$b" "инъекция: код вне трёх исходов — краснеет" "$C02" \
    "scripts/${SUITES[0]}/check-01-probe.sh — на пустом дереве код 3: вне трёх исходов"

# Код 2 от ИНТЕРПРЕТАТОРА: `if` без `fi` — bash выходит двойкой и печатает
# «syntax error». Текст есть, строки [VOID] нет: это поломка, а не «без предмета».
# Близнец — HONEST выше: та же двойка со строкой [VOID] и причиной.
BROKEN='if [ "$n" -gt 0 ]; then echo "[CENSUS] наборов осмотрено $n"'
b="$(one02 "$BROKEN")"
expect 1 "$b" "инъекция: синтаксическая ошибка — код 2 без строки [VOID] — краснеет" "$C02" \
    "scripts/${SUITES[0]}/check-01-probe.sh — на пустом дереве код 2 без строки «[VOID] <причина>»" \
    "находок 1"

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID" "$C02" "наборов scripts/*/run-all.sh"

# ── check-03: прогонщик набора засчитывает молчаливый ноль ─────────────────────
#
# Близнец — общий прогонщик в каждом наборе (так устроены все наборы дерева).
# Дефект — прогонщик ПРЕЖНЕЙ формы, дословно той, что была у наборов до ws#762:
# тот же глоб, те же три кода, но исход — из одного канала (ноль без объёма и
# двойка интерпретатора засчитаны), проверка исполняется из каталога
# вызывающего, строки переписи нет.
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
    expect 1 "$b" "инъекция в $s: прогонщик прежней формы — краснеет по пяти свойствам" "$C03" \
        "scripts/$s/run-all.sh — проверка вышла нулём, не напечатав ни одного числа" \
        "scripts/$s/run-all.sh — проверка вышла нулём, напечатав только свой адрес" \
        "scripts/$s/run-all.sh — проверка с синтаксической ошибкой оболочки" \
        "scripts/$s/run-all.sh — проверка исполнена внутри рабочей копии вызывающего" \
        "scripts/$s/run-all.sh — не записал машинную строку переписи" "находок 5"
done

# Однофактные мутанты НАСТОЯЩЕГО общего прогонщика (копия в песочнице): каждое
# свойство, которое обещает check-03, снимается отдельно, и находка обязана назвать
# именно его — у всех наборов сразу, прогонщик у них один.
# runner_mutant <заголовок> <было> <стало> <подстрока находки>
runner_mutant() {
    local b s
    b="$(mkbox)"
    for s in "${SUITES[@]}"; do shim "$b" "$s"; done
    commit "$b"
    if mutate "$b/scripts/lib/suite-runner.sh" "$2" "$3"; then
        expect 1 "$b" "$1" "$C03" "$4" "находок ${#SUITES[@]}"
    else
        unplanted "$1"
    fi
}

runner_mutant "мутант: пустой набор выходит нулём — краснеет" \
    '[ "$count" -gt 0 ] || return 1' '[ "$count" -gt 0 ] || return 0' \
    "в наборе нет ни одной проверки, а прогонщик вернул 0 вместо 1"
runner_mutant "мутант: рабочий каталог проверок без git init (TMPDIR внутри рабочей копии) — краснеет" \
    'if ! git -C "$neutral" init -q; then' 'if ! true; then' \
    "проверка исполнена внутри рабочей копии вызывающего"
runner_mutant "мутант: объём — любая цифра, в том числе номер в адресе проверки — краснеет" \
    "LC_ALL=C.UTF-8 grep -Eq -- '(^|[^[:alnum:]_#-])[0-9]+([^[:alnum:]_#-]|\$)' \"\$1\"" \
    "grep -q '[0-9]' \"\$1\"" \
    "напечатав только свой адрес"
runner_mutant "мутант: код 2 засчитан за «без предмета» без строки [VOID] — краснеет" \
    'if _suite_void_declared "$log"; then' 'if true; then' \
    "проверка с синтаксической ошибкой оболочки"

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
#
# Песочницы этой проверки — ГОЛЫЕ (`barebox`, без копии `scripts/lib/`): её обход —
# все файлы оболочки под `scripts/`, и чужие файлы в песочнице сдвигали бы перепись.
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

barebox() {
    local b
    b="$(mktemp -d "$TMP/bare.XXXXXX")"
    git -C "$b" init -q
    mkdir -p "$b/scripts"
    printf '%s' "$b"
}

# pipescript <песочница> <путь от scripts/> <строки кода>… — скрипт под pipefail;
# первая строка кода — четвёртая строка файла.
pipescript() {
    local box="$1" rel="$2" line; shift 2
    mkdir -p "$(dirname "$box/scripts/$rel")"
    {
        printf '#!/usr/bin/env bash\nset -uo pipefail\nout="$(cat)"\n'
        for line in "$@"; do printf '%s\n' "$line"; done
    } > "$box/scripts/$rel"
}

# plainscript <песочница> <путь от scripts/> <строки кода>… — скрипт БЕЗ pipefail;
# первая строка кода — третья строка файла.
plainscript() {
    local box="$1" rel="$2" line; shift 2
    mkdir -p "$(dirname "$box/scripts/$rel")"
    {
        printf '#!/usr/bin/env bash\n# pipefail здесь не включается\n'
        for line in "$@"; do printf '%s\n' "$line"; done
    } > "$box/scripts/$rel"
}

LAWFUL='if grep -qF -- "находка" <<<"$out"; then exit 1; fi'
PIPED='if printf "%s\n" "$out" | grep -qF -- "находка"; then exit 1; fi'
SHELLS_TWIN=$((2 * ${#SUITES[@]} + 2))

# world7 <песочница> [<куда вносится> <строка кода>…] — проба в каждом наборе
# дерева, файл вне наборов и файл хука без расширения; всё законно, кроме
# внесённого. Место — имя набора, `tool.sh` либо `hooks/pre-push`.
world7() {
    local box="$1" target="${2:-}" s
    local -a code=()
    [ "$#" -gt 2 ] && code=("${@:3}")
    for s in "${SUITES[@]}"; do
        suite "$box" "$s"
        if [ "$s" = "$target" ]; then pipescript "$box" "$s/check-01-probe.sh" "${code[@]}"
        else pipescript "$box" "$s/check-01-probe.sh" "$LAWFUL" \
                '# форма в комментарии — не код: printf "%s" "$out" | grep -q x' \
                'echo "printf | grep -q — в строке, а не в трубе"'; fi
    done
    if [ "$target" = "tool.sh" ]; then pipescript "$box" tool.sh "${code[@]}"
    else pipescript "$box" tool.sh "$LAWFUL"; fi
    if [ "$target" = "hooks/pre-push" ]; then pipescript "$box" hooks/pre-push "${code[@]}"
    else pipescript "$box" hooks/pre-push "$LAWFUL"; fi
}

b="$(barebox)"; world7 "$b"; commit "$b"
expect 0 "$b" "близнец: чтение и поиск разведены в наборах, вне наборов и в файле без расширения; форма в комментарии и в строке — молчит" "$C07" \
    "оболочки $SHELLS_TWIN (*.sh $((SHELLS_TWIN - 1)), по шебангу 1)" "форм «труба в grep -q» 0"

for s in "${SUITES[@]}"; do
    b="$(barebox)"; world7 "$b" "$s" "$PIPED"; commit "$b"
    expect 1 "$b" "инъекция в $s: труба в grep -q под pipefail — краснеет с координатой" "$C07" \
        "scripts/$s/check-01-probe.sh:4 — вердикт из трубы в grep" "находок 1"
done

b="$(barebox)"; world7 "$b" tool.sh "$PIPED"; commit "$b"
expect 1 "$b" "инъекция вне наборов (scripts/tool.sh) — обход шире наборов, краснеет" "$C07" \
    "scripts/tool.sh:4 — вердикт из трубы в grep" "находок 1"

b="$(barebox)"; world7 "$b" hooks/pre-push "$PIPED"; commit "$b"
expect 1 "$b" "инъекция в файл оболочки без расширения (шебанг) — краснеет" "$C07" \
    "scripts/hooks/pre-push:4 — вердикт из трубы в grep" "находок 1"

b="$(barebox)"
world7 "$b" "${SUITES[0]}" 'if printf "%s\n" "$out" |' '     grep -qF -- "находка"; then exit 1; fi'
commit "$b"
expect 1 "$b" "инъекция: труба продолжена на следующую строку — краснеет координатой читателя" "$C07" \
    "scripts/${SUITES[0]}/check-01-probe.sh:5 — вердикт из трубы в grep" "многострочных 1"

b="$(barebox)"
world7 "$b" "${SUITES[0]}" 'n="$(printf "%s\n" "$out" |' '     grep -c -- "находка")"; [ "$n" -eq 0 ] || exit 1'
commit "$b"
expect 0 "$b" "близнец: многострочная труба в grep, читающий до конца (-c), — молчит" "$C07" \
    "форм «труба в grep -q» 0"

b="$(barebox)"; world7 "$b" "${SUITES[0]}" 'if printf "%s\n" "$out" | grep -lF -- "находка"; then exit 1; fi'; commit "$b"
expect 1 "$b" "инъекция: труба в grep -l (тоже выходит на первом совпадении) — краснеет" "$C07" \
    "scripts/${SUITES[0]}/check-01-probe.sh:4 — вердикт из трубы в grep"

b="$(barebox)"; world7 "$b" "${SUITES[0]}" 'x="$(printf "%s\n" "$out" | grep -m1 -- "находка")"'; commit "$b"
expect 1 "$b" "инъекция: труба в grep -m1 внутри подстановки в двойных кавычках — это код, краснеет" "$C07" \
    "scripts/${SUITES[0]}/check-01-probe.sh:4 — вердикт из трубы в grep"

b="$(barebox)"; world7 "$b" "${SUITES[0]}" 'x="$(grep -m1 -- "находка" <<<"$out")"'; commit "$b"
expect 0 "$b" "близнец: та же подстановка, чтение и поиск разведены — молчит" "$C07" \
    "форм «труба в grep -q» 0"

# Подключение: библиотека без своего pipefail исполняется в оболочке подключившего.
# Имя библиотеки — без `_`: признак выводится из подключения, а не из имени.
b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/helpers.sh" "$PIPED"
pipescript "$b" "${SUITES[0]}/check-02-probe.sh" '. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"'
commit "$b"
expect 1 "$b" "инъекция: библиотека без своего pipefail, подключённая файлом под pipefail, — краснеет в библиотеке" "$C07" \
    "scripts/${SUITES[0]}/helpers.sh:3 — вердикт из трубы в grep" "подключением 1"

b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/helpers.sh" "$PIPED"
plainscript "$b" "${SUITES[0]}/plain.sh" '. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"'
commit "$b"
expect 0 "$b" "близнец: та же библиотека, подключённая только файлом без pipefail, — молчит" "$C07" \
    "подключением 0" "форм «труба в grep -q» 0"

b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/part-1.sh" "$PIPED"
pipescript "$b" "${SUITES[0]}/parts.sh" 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
    'for part in "$HERE"/part-*.sh; do' '    . "$part"' 'done'
commit "$b"
expect 1 "$b" "инъекция: часть, подключаемая циклом по глобу, — наследует pipefail и краснеет" "$C07" \
    "scripts/${SUITES[0]}/part-1.sh:3 — вердикт из трубы в grep"

b="$(barebox)"; world7 "$b"
pipescript "$b" "${SUITES[0]}/check-02-probe.sh" '. "$ELSEWHERE/absent.sh"'
commit "$b"
expect 1 "$b" "инъекция: подключение, не разрешённое в файл дерева, — находка, а не молчаливый пропуск" "$C07" \
    "scripts/${SUITES[0]}/check-02-probe.sh:4 — подключение" "подключений не разрешено 1"

b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/helpers.sh" "$LAWFUL"
pipescript "$b" "${SUITES[0]}/check-02-probe.sh" '. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"'
commit "$b"
expect 0 "$b" "близнец: подключение разрешено, библиотека законна — молчит" "$C07" \
    "подключением 1" "подключений не разрешено 0"

b="$(barebox)"; world7 "$b" "${SUITES[0]}" "$LAWFUL  # pipe-safe: писатель доживает до конца"; commit "$b"
expect 1 "$b" "инъекция: пометка pipe-safe там, где трубы нет — послабление без предмета" "$C07" \
    "пометка \`pipe-safe\` на строке, где трубы в grep нет"

b="$(barebox)"; world7 "$b" "${SUITES[0]}" "$PIPED  # pipe-safe: вход — одна строка, писатель доживает до конца"; commit "$b"
expect 0 "$b" "близнец: труба, помеченная pipe-safe с причиной, — молчит и сочтена" "$C07" \
    "помечено pipe-safe 1"

b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/loose.sh" "$PIPED"
commit "$b"
expect 0 "$b" "близнец: та же труба в файле БЕЗ pipefail, никем не подключённом, — исход равен исходу grep, молчит" "$C07" \
    "без pipefail $((${#SUITES[@]} + 1))"

b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/loose.sh" "$PIPED  # pipe-safe: здесь нечего прощать"
commit "$b"
expect 1 "$b" "инъекция: пометка pipe-safe в файле без pipefail — послабление без предмета" "$C07" \
    "пометка \`pipe-safe\` в файле без pipefail"

# Формы звена, слепые в круге 1: каждая — тот же дефект (писатель, труба, grep с
# выходом на первом совпадении, pipefail), другая запись. Каждая исполнена отдельно
# на входе с совпадением и дала 141 — класс, а не стиль.
FORMS7=(
    'if printf "%s\n" "$out" | /usr/bin/grep -qF -- "находка"; then exit 1; fi'
    'if printf "%s\n" "$out" | env grep -qF -- "находка"; then exit 1; fi'
    'if printf "%s\n" "$out" | timeout 5 grep -qF -- "находка"; then exit 1; fi'
    'if printf "%s\n" "$out" | { grep -qF -- "находка"; }; then exit 1; fi'
    'if printf "%s\n" "$out" | ( grep -qF -- "находка" ); then exit 1; fi'
    'if printf "%s\n" "$out" | grep --quie -F -- "находка"; then exit 1; fi'
    'if printf "%s\n" "$out" | LC_ALL=C nice -n 5 stdbuf -oL grep -m1 -- "находка"; then exit 1; fi'
)
for form in "${FORMS7[@]}"; do
    b="$(barebox)"; world7 "$b" "${SUITES[0]}" "$form"; commit "$b"
    expect 1 "$b" "инъекция: форма звена «${form:30:40}…» — краснеет с координатой" "$C07" \
        "scripts/${SUITES[0]}/check-01-probe.sh:4 — вердикт из трубы в grep" "находок 1"
done

b="$(barebox)"
world7 "$b" "${SUITES[0]}" 'if printf "%s\n" "$out" | /usr/bin/grep -cF -- "находка" >/dev/null; then exit 1; fi' \
    'if printf "%s\n" "$out" | env grep -cF -- "находка" >/dev/null; then exit 1; fi' \
    'if printf "%s\n" "$out" | timeout 5 grep -cF -- "находка" >/dev/null; then exit 1; fi' \
    'if printf "%s\n" "$out" | grep -e -q -- "находка" >/dev/null; then exit 1; fi' \
    'if printf "%s\n" "$out" | xargs grep -qF -- "находка"; then exit 1; fi'
commit "$b"
expect 0 "$b" "близнецы: те же обёртки и путь с grep, читающим до конца (-c), -e -q (образец «-q»), xargs — молчат" "$C07" \
    "форм «труба в grep -q» 0"

b="$(barebox)"
world7 "$b" "${SUITES[0]}" 'if printf "%s\n" "$out" |' '    # почему труба: причина в комментарии между звеньями' \
    '    grep -qF -- "находка"; then exit 1; fi'
commit "$b"
expect 1 "$b" "инъекция: строка-комментарий внутри многострочной трубы — краснеет координатой читателя" "$C07" \
    "scripts/${SUITES[0]}/check-01-probe.sh:6 — вердикт из трубы в grep" "многострочных 1"

b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/shopt-probe.sh" 'shopt -so pipefail' "$PIPED"
commit "$b"
expect 1 "$b" "инъекция: pipefail включён через shopt -so — краснеет" "$C07" \
    "scripts/${SUITES[0]}/shopt-probe.sh:4 — вердикт из трубы в grep"

b="$(barebox)"; world7 "$b"
plainscript "$b" "${SUITES[0]}/off-probe.sh" 'set +o pipefail' "$PIPED"
pipescript "$b" "${SUITES[0]}/region-probe.sh" 'set +o pipefail' "$PIPED" 'set -o pipefail'
commit "$b"
expect 0 "$b" "близнецы: set +o pipefail — выключение, а не упоминание; область после него не судится" "$C07" \
    "форм «труба в grep -q» 0"

b="$(barebox)"; world7 "$b"
pipescript "$b" "${SUITES[0]}/region-probe.sh" 'set +o pipefail' 'set -o pipefail' "$PIPED"
commit "$b"
expect 1 "$b" "инъекция: pipefail выключен и снова включён — звено после включения судится" "$C07" \
    "scripts/${SUITES[0]}/region-probe.sh:6 — вердикт из трубы в grep"

# Вне обхода: форма в файле вне scripts/ не судится, но СЧИТАЕТСЯ отдельной строкой
# переписи с каталогом; тот же файл, подключённый из обхода, — судится.
b="$(barebox)"; world7 "$b"
mkdir -p "$b/tools"
printf '#!/usr/bin/env bash\nset -uo pipefail\nout="$(cat)"\n%s\n' "$PIPED" > "$b/tools/probe.sh"
commit "$b"
expect 0 "$b" "вне обхода: форма в tools/probe.sh не судится, но названа числом в переписи" "$C07" \
    "форм «труба в grep -q» без пометки 1 (tools 1)"

b="$(barebox)"; world7 "$b"
mkdir -p "$b/tools"
printf '#!/usr/bin/env bash\nout="$(cat)"\n%s\n' "$PIPED" > "$b/tools/probe.sh"
pipescript "$b" "${SUITES[0]}/check-02-probe.sh" '. "$(dirname "${BASH_SOURCE[0]}")/../../tools/probe.sh"'
commit "$b"
expect 1 "$b" "инъекция: файл вне scripts/, подключённый из обхода под pipefail, — судится" "$C07" \
    "tools/probe.sh:3 — вердикт из трубы в grep" "вне scripts/, подключённых обходом, 1"

b="$(barebox)"; commit "$b"
expect 2 "$b" "предпосылка: файлов оболочки под scripts/ нет — VOID, а не «находок 0»" "$C07" \
    "оболочки среди них 0"

# ── check-08: доказательство зависит от унаследованного дома ──────────────────
#
# Сначала — проба-пара на МЕХАНИЗМЕ, без неё статическая проверка ловила бы
# форму, а не свойство. Доказательство-двойник зовёт проверку, читающую один
# указатель на дерево, дважды: под унаследованным указателем и без него. Со
# снятием окружения (`proof_own_environment` из настоящей `scripts/lib/proofs.sh`)
# исходы обязаны совпасть; без снятия — разойтись: иначе пара не чувствительна, и
# её «совпали» ничего не значит.
#
# Указателей ТРИ рода, и пара пробует каждый: дом продукта (`KACHO_HOME_*`), общее
# переопределение корня (`GATE_ROOT`) и переопределение набора (`<НАБОР>_GATE_ROOT`).
# Круг 1: пара пробовала только первый, и мутант, снявший из функции два других,
# выжил, хотя без них вердикт доказательства docs-gate зависел от вызывающего.
C08="check-08-proof-owns-its-environment.py"
echo "== check-08: вердикт доказательства зависит от унаследованного дома =="

OWN_PROOF='#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/proofs.sh"
proof_own_environment
python3 "$here/check-01-home.py"'
BARE_PROOF='#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$here/check-01-home.py"'
# @VAR@ — имя указателя, который читает проверка-двойник.
HOME_CHECK='import os
import sys
home = os.environ.get("@VAR@")
print("осмотрено 1; указатель %s" % (home or "—"))
sys.exit(1 if home else 0)'
POINTERS=(KACHO_HOME_PROBE GATE_ROOT PAIR_GATE_ROOT)
FILTER='KACHO_HOME_*|GATE_ROOT|*_GATE_ROOT)'

# pair <заголовок> <тело доказательства> <ждём: same|differ> <указатель> [<было> <стало>]
# — последние два: однофактный мутант копии proofs.sh в песочнице.
pair() {
    local title="$1" body="$2" want="$3" var="$4" b ra rb
    probes=$((probes + 1))
    b="$(mkbox)"; mkdir -p "$b/scripts/pair-gate"
    if [ "$#" -gt 4 ] && ! mutate "$b/scripts/lib/proofs.sh" "$5" "$6"; then
        echo "  ПРОВАЛ $title — мутант не внесён, проба недоказательна" >&2
        failed=$((failed + 1))
        return
    fi
    printf '%s\n' "${HOME_CHECK//@VAR@/$var}" > "$b/scripts/pair-gate/check-01-home.py"
    printf '%s\n' "$body" > "$b/scripts/pair-gate/inject.sh"
    ( cd "$TMP" && env -u "$var" bash "$b/scripts/pair-gate/inject.sh" >/dev/null 2>&1 ); ra=$?
    ( cd "$TMP" && env "$var=$TMP/чужой-дом" bash "$b/scripts/pair-gate/inject.sh" >/dev/null 2>&1 ); rb=$?
    if { [ "$want" = same ] && [ "$ra" -eq "$rb" ] && [ "$ra" -eq 0 ]; } ||
       { [ "$want" = differ ] && [ "$ra" -ne "$rb" ]; }; then
        echo "  ok   $title (без указателя $ra, с указателем $rb)"
    else
        echo "  ПРОВАЛ $title — ждали $want, получили: без указателя $ra, с указателем $rb" >&2
        failed=$((failed + 1))
    fi
}

for v in "${POINTERS[@]}"; do
    pair "проба-пара $v: доказательство снимает окружение — исход один при любом унаследованном указателе" \
        "$OWN_PROOF" same "$v"
    pair "проба-пара $v: то же доказательство без снятия — исход зависит от вызывающего (пара чувствительна)" \
        "$BARE_PROOF" differ "$v"
done
# Мутанты функции: из перечня снимаемых выпадает один род указателей — пара по
# этому роду обязана увидеть зависимость от вызывающего.
pair "мутант proofs.sh без GATE_ROOT и *_GATE_ROOT: пара GATE_ROOT видит зависимость" \
    "$OWN_PROOF" differ GATE_ROOT "$FILTER" 'KACHO_HOME_*)'
pair "мутант proofs.sh без *_GATE_ROOT: пара PAIR_GATE_ROOT видит зависимость" \
    "$OWN_PROOF" differ PAIR_GATE_ROOT "$FILTER" 'KACHO_HOME_*|GATE_ROOT)'
pair "мутант proofs.sh без KACHO_HOME_*: пара KACHO_HOME_PROBE видит зависимость" \
    "$OWN_PROOF" differ KACHO_HOME_PROBE "$FILTER" 'GATE_ROOT|*_GATE_ROOT)'

# Статическая ось: набор, чей код читает указатель, и форма его доказательства.
READS_PY='import os
print("осмотрено 1; дом %s" % os.environ.get("KACHO_HOME_PROBE"))'
DOC_ONLY='"""Упоминает KACHO_HOME_PROBE только в строке документации."""
print("осмотрено 1")'
QUIET_PY='print("осмотрено 1")'
P_OWN='#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/proofs.sh"
proof_own_environment
echo "проб 1"'
P_NOCALL='#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/proofs.sh"
echo "проб 1"'
P_NOSRC='#!/usr/bin/env bash
proof_own_environment
echo "проб 1"'
P_COMMENT='#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/proofs.sh"
# proof_own_environment — только в комментарии
echo "проб 1"'

# world8 <песочница> [<набор> <код проверки> <доказательство>] — во всех наборах
# проверка читает указатель и доказательство владеет окружением; в названном —
# внесённое.
world8() {
    local box="$1" target="${2:-}" body="${3:-}" prf="${4:-}" s
    for s in "${SUITES[@]}"; do
        suite "$box" "$s"
        if [ "$s" = "$target" ]; then
            printf '%s\n' "$body" > "$box/scripts/$s/check-01-reads.py"
            printf '%s\n' "$prf" > "$box/scripts/$s/inject.sh"
        else
            printf '%s\n' "$READS_PY" > "$box/scripts/$s/check-01-reads.py"
            printf '%s\n' "$P_OWN" > "$box/scripts/$s/inject.sh"
        fi
    done
}

b="$(mkbox)"; world8 "$b"; commit "$b"
expect 0 "$b" "близнец: во всех ${#SUITES[@]} наборах проверка читает дом, доказательство снимает окружение — молчит" "$C08" \
    "читают KACHO_HOME_*: ${#SUITES[@]}" "владеет окружением ${#SUITES[@]}"

for s in "${SUITES[@]}"; do
    b="$(mkbox)"; world8 "$b" "$s" "$READS_PY" "$P_NOCALL"; commit "$b"
    expect 1 "$b" "инъекция в $s: доказательство не снимает окружение — краснеет с координатой" "$C08" \
        "scripts/$s/inject.sh — код набора $s читает KACHO_HOME_*" "находок 1"
done

b="$(mkbox)"; world8 "$b" "${SUITES[0]}" "$READS_PY" "$P_NOSRC"; commit "$b"
expect 1 "$b" "инъекция: вызов есть, библиотека не подключена — функции нет, краснеет" "$C08" \
    "scripts/${SUITES[0]}/inject.sh:2 — proof_own_environment зовётся, но scripts/lib/proofs.sh не подключён"

b="$(mkbox)"; world8 "$b" "${SUITES[0]}" "$READS_PY" "$P_COMMENT"; commit "$b"
expect 1 "$b" "инъекция: вызов только в комментарии — читается код, краснеет" "$C08" \
    "scripts/${SUITES[0]}/inject.sh — код набора ${SUITES[0]} читает KACHO_HOME_*"

b="$(mkbox)"; world8 "$b" "${SUITES[0]}" "$DOC_ONLY" "$P_NOCALL"; commit "$b"
expect 0 "$b" "близнец: указатель только в строке документации — не читатель, молчит" "$C08" \
    "читают KACHO_HOME_*: $((${#SUITES[@]} - 1))"

b="$(mkbox)"; world8 "$b" "${SUITES[0]}" "$QUIET_PY" "$P_NOCALL"; commit "$b"
expect 0 "$b" "близнец: набор не читает дом, доказательство без снятия — молчит" "$C08" \
    "владеет окружением $((${#SUITES[@]} - 1))"

b="$(mkbox)"; world8 "$b" "${SUITES[0]}" "$QUIET_PY" "$P_NOCALL"
printf '#!/usr/bin/env bash\necho "${KACHO_HOME_PROBE:-—}"\n' > "$b/scripts/${SUITES[0]}/check-02-reads.sh"
commit "$b"
expect 1 "$b" "инъекция: указатель читает скрипт оболочки набора — тоже читатель, краснеет" "$C08" \
    "scripts/${SUITES[0]}/check-02-reads.sh"

b="$(mkbox)"
for s in "${SUITES[@]}"; do suite "$b" "$s"; printf '%s\n' "$QUIET_PY" > "$b/scripts/$s/check-01-reads.py"; done
commit "$b"
expect 2 "$b" "предпосылка: ни один набор не читает дом — VOID, а не «находок 0»" "$C08" "не читает KACHO_HOME_*"

b="$(mkbox)"; commit "$b"
expect 2 "$b" "предпосылка: наборов нет — VOID" "$C08" "наборов scripts/*/run-all.sh"

# ── check-09: вывод перечня не читает свои каналы ────────────────────────────
#
# Близнец — копия НАСТОЯЩЕГО `scripts/lib/run-suites.sh`. Дефекты — однофактные
# мутанты этой копии, по одному на канал, который вывод обязан читать; вместе
# четыре первых — составной мутант, выживший в круге 1 во всех самопроверках.
C09="check-09-derived-run-reads-every-channel.py"
echo "== check-09: вывод перечня наборов проглатывает канал =="

b="$(mkbox)"; commit "$b"
expect 0 "$b" "близнец: настоящий run-suites.sh — молчит" "$C09" "находок 0"

# derived_mutant <заголовок> <было> <стало> <подстрока находки>
derived_mutant() {
    local b
    b="$(mkbox)"; commit "$b"
    if mutate "$b/scripts/lib/run-suites.sh" "$2" "$3"; then
        expect 1 "$b" "$1" "$C09" "$4"
    else
        unplanted "$1"
    fi
}

derived_mutant "мутант: «без предмета» не краснит при --void-is-failure — краснеет" \
    '2) voided+=("$s") ;;' '2) ;;' \
    "bbb-gate без предмета, вызов с --void-is-failure (--proofs --void-is-failure): вернул 0 вместо 1"
derived_mutant "мутант: неотчитавшийся набор не находка — краснеет" \
    'unreported+=("$s")' ':' \
    "bbb-gate не отчитался строкой переписи"
derived_mutant "мутант: пустая перепись выходит нулём — краснеет" \
    "$(printf 'при снятых проверках" >&2\n    exit 1')" "$(printf 'при снятых проверках" >&2\n    exit 0')" \
    "перепись наборов пуста (--proofs --void-is-failure): вернул 0 вместо 1"
derived_mutant "мутант: красное доказательство не находка — краснеет" \
    '[ "$prc" -eq 0 ] || proof_red+=("$s (код $prc)")' ':' \
    "доказательство bbb-gate красное, вызов с --proofs"
derived_mutant "мутант: отсутствующее доказательство не находка — краснеет" \
    'proof_red+=("$s (доказательства inject.sh нет)")' ':' \
    "у bbb-gate нет доказательства"
derived_mutant "мутант: строка переписи не сверяется с кодом (исполнено 0, провалы при нуле) — краснеет" \
    '[ -z "$why" ] || disagree+=("$s ($why)")' ':' \
    "bbb-gate вышел нулём над строкой «исполнено 0»"
derived_mutant "мутант: красный набор не находка — краснеет" \
    '*) red+=("$s") ;;' '*) ;;' \
    "bbb-gate красный"

b="$(mkbox)"; rm -f "$b/scripts/lib/run-suites.sh"; commit "$b"
expect 2 "$b" "предпосылка: вывода перечня нет — VOID" "$C09" "вывода перечня scripts/lib/run-suites.sh"

b="$(mkbox)"; commit "$b"
mutate "$b/scripts/lib/run-suites.sh" '[ "$fail" -eq 0 ] || exit 1' 'exit 1' >/dev/null 2>&1 \
    || unplanted "положительный контроль сорван"
expect 2 "$b" "положительный контроль сорван: вывод краснеет на исправных наборах — VOID, а не «доказано»" \
    "$C09" "на двух исправных наборах с исправными доказательствами вернул 1"

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
