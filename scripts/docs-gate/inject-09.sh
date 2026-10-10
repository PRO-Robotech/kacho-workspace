#!/usr/bin/env bash
# shellcheck disable=SC2016
#   Тела проб — markdown с цитатой в обратных кавычках; в двойных кавычках
#   оболочка исполнила бы её как подстановку команды, поэтому одинарные — на весь файл.
# ЧАСТЬ доказательства набора docs-gate: `check-09-quoted-make-commands-resolve.sh`
# — место гейта цитат `make` в наборе (ws#816).
#
# Доказательство самого гейта — `scripts/check-doc-commands-inject.sh`, и оно
# исполняется отсюда, а не переписывается: второй экземпляр тех же проб разошёлся
# бы с первым молча. Здесь — только то, что добавляет МЕСТО В НАБОРЕ: проверка
# набора судит дерево, на которое её направил набор, и отдаёт исходы гейта без
# перевода. Пробы, по одному факту на ось:
#
#   N1  цитата цели без каталога (`make e2e-test`) в docs/**/*.md → 1, файл и строка;
#   N1' та же копия с `make -C deploy e2e-test`                   → 0, цитата сосчитана;
#   N2  судимое дерево пусто (`GATE_ROOT` на пустой репозиторий)   → код 2, строка `[VOID]`;
#   N3  в судимом дереве нет дерева продукта                      → код 2, строка `[VOID]`.
#
# Ось N1 — дословно находка, на которой задача заведена: ветка волны несла
# `make e2e-test`, а цель объявлена только в `deploy/Makefile`.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/check-09-quoted-make-commands-resolve.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$HERE/../lib/proofs.sh"
proof_own_environment

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# world <корень> <тело документа> [без-продукта] — судимое дерево: документ
# `docs/guide.md` и, если не сказано иначе, дерево продукта `project/kacho` с
# корневым Makefile без цели и `deploy/Makefile`, где цель объявлена.
world() {
    mkdir -p "$1/docs"
    printf '%s\n' "$2" > "$1/docs/guide.md"
    if [ "${3:-}" != без-продукта ]; then
        mkdir -p "$1/project/kacho/deploy"
        git -C "$1/project/kacho" init -q
        printf 'lint:\n\t@true\n' > "$1/project/kacho/Makefile"
        printf 'e2e-test:\n\t@true\n' > "$1/project/kacho/deploy/Makefile"
    fi
    git -C "$1" init -q
}

# expect <ось> <код> <корень|-> <образец…> — исход проверки набора на судимом дереве.
# Корень «-» — проверка направлена общим `GATE_ROOT` на пустой репозиторий.
expect() {
    local axis="$1" want="$2" root="$3" out got p miss=""
    shift 3
    if [ "$root" = - ]; then
        local empty="$TMP/empty-$axis"
        mkdir -p "$empty" && git -C "$empty" init -q
        out="$(cd "$TMP" && env -u KACHO_MONOREPO -u DOCS_GATE_ROOT GATE_ROOT="$empty" bash "$CHECK" 2>&1)"; got=$?
    else
        out="$(cd "$TMP" && env -u KACHO_MONOREPO -u GATE_ROOT DOCS_GATE_ROOT="$root" bash "$CHECK" 2>&1)"; got=$?
    fi
    for p in "$@"; do grep -qF -- "$p" <<<"$out" || miss="$miss «$p»"; done
    if [ "$got" -eq "$want" ] && [ -z "$miss" ]; then
        pass=$((pass + 1)); echo "  ok   $axis (код $got)"
    else
        fail=$((fail + 1))
        echo "  ПРОВАЛ $axis — ждали код $want, получили $got${miss:+; в выводе нет:$miss}" >&2
        printf '         %s\n' "${out//$'\n'/$'\n'         }" >&2
    fi
}

echo "== check-09: гейт цитат как проверка набора =="
world "$TMP/n1" 'Сквозной прогон — `make e2e-test`.'
expect N1 1 "$TMP/n1" "docs/guide.md:1" "e2e-test"
world "$TMP/n1t" 'Сквозной прогон — `make -C deploy e2e-test`.'
expect "N1'" 0 "$TMP/n1t" "all 1 make citations"
expect N2 2 - "[VOID]"
world "$TMP/n3" 'Сквозной прогон — `make -C deploy e2e-test`.' без-продукта
expect N3 2 "$TMP/n3" "[VOID]" "дерево продукта не найдено"

echo "== доказательство самого гейта: scripts/check-doc-commands-inject.sh =="
if bash "$HERE/../check-doc-commands-inject.sh"; then
    pass=$((pass + 1)); echo "  ok   доказательство гейта сошлось"
else
    fail=$((fail + 1)); echo "  ПРОВАЛ доказательство гейта не сошлось" >&2
fi

echo "[CENSUS] inject-09: утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$((pass + fail))" -gt 0 ] || { echo "[VOID] inject-09 — ни одной пробы не исполнено" >&2; exit 2; }
[ "$fail" -eq 0 ] || { echo "[FAIL] inject-09 — check-09 не доказан: разошлось $fail" >&2; exit 1; }
echo "[PASS] inject-09 — check-09 доказан: проб $pass, разошлось 0"
