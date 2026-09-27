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
