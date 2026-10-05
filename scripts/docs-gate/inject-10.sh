#!/usr/bin/env bash
# ЧАСТЬ доказательства набора docs-gate: страж «каталог фикстуры продукта лежит
# ВНЕ рабочей копии git» (`scripts/lib/product-fixture.sh`, ws#924).
#
# ЗАЧЕМ. Синтетическое дерево продукта (`h.*`, `p.*`, `prod.*` в `inject.sh`) —
# это целый репозиторий. Положенный внутрь чужой рабочей копии, он становится её
# неотслеживаемым каталогом: `git status` общего клона перестаёт быть признаком
# чистоты, гейты состава дерева дают находку на исправном дереве, а соседняя
# полоса судит чужой файл. Так и вышло в общем клоне kaname: три каталога
# `h.XXXXXX` с коммитом «ствол» от подписи фикстуры (ws#924, бывшая kaname#350).
# Каталог задаёт `mktemp -p "$TMP"`, и куда он встанет, решает `TMPDIR`
# вызывающего — то есть свойство держалось вниманием того, кто запускал.
#
# Пробы, по одному факту на ось:
#   W1  каталог в неотслеживаемом подкаталоге рабочей копии  → 2, состав копии не изменился;
#   W2  каталог в ИГНОРИРУЕМОМ подкаталоге (форма `tmp/` воркспейса) → 2;
#   W3  каталог — корень существующего репозитория (сам общий клон) → 2, его HEAD цел;
#   W4  путь ещё не существует и лежит внутри рабочей копии  → 2, каталог не создан;
#   W5  ЗАКОННЫЙ БЛИЗНЕЦ: свежий каталог под временным корнем  → 0, маркер на месте;
#   W6  перепись места: корень фикстур вне копии → 0 и строка с путём;
#                       корень внутри копии      → 2 и `[VOID]`.
# Предпосылка: временный корень самой пробы лежит вне рабочей копии — иначе
# W5 и W6 судили бы не то, и проба отвечает `[VOID]`, а не успехом.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$HERE/../lib/proofs.sh"
proof_own_environment

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

if env -u GIT_DIR -u GIT_WORK_TREE -u GIT_CEILING_DIRECTORIES \
        git -C "$TMP" rev-parse --git-dir >/dev/null 2>&1; then
    echo "[VOID] inject-10 — временный корень пробы $TMP сам лежит в рабочей копии git: TMPDIR вызывающего указывает в дерево" >&2
    exit 2
fi

# Подпись синтетических деревьев — HOME песочницы (ws#785).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$HERE/../lib/sandbox-git-home.sh"
sandbox_git_home "$TMP/home" || { echo "[VOID] inject-10 — корневой подписи нет" >&2; exit 2; }
# shellcheck source=../lib/product-fixture.sh
. "$HERE/../lib/product-fixture.sh"

ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  ПРОВАЛ $1" >&2; [ -n "${2:-}" ] && printf '         %s\n' "${2//$'\n'/$'\n'         }" >&2; }

# outer <имя> — синтетическая «общая рабочая копия» с веткой main и одним файлом.
outer() {
    local o="$TMP/$1"
    mkdir -p "$o"
    git -C "$o" init -q
    git -C "$o" symbolic-ref HEAD refs/heads/main
    printf 'x\n' > "$o/README"
    printf '%s' "$o"
}

# refused <ось> <каталог> <копия> — init обязан отказать кодом 2, назвать копию
# и не изменить её состав.
refused() {
    local axis="$1" dir="$2" o="$3" before after out rc
    before="$(git -C "$o" status --porcelain --ignored)"
    out="$(product_fixture_init "$dir" 2>&1)"; rc=$?
    after="$(git -C "$o" status --porcelain --ignored)"
    if [ "$rc" -eq 2 ] && [ "$before" = "$after" ] && grep -qF -- "$o" <<<"$out"; then
        ok "$axis (код $rc, состав копии цел, копия названа)"
    else
        bad "$axis — ждали код 2, неизменный состав и имя копии; код $rc" \
            "вывод: $out"$'\n'"до: $before"$'\n'"после: $after"
    fi
}

echo "== product_fixture_init: каталог вне рабочей копии git =="

o1="$(outer w1)"; mkdir -p "$o1/h.w1"
refused W1 "$o1/h.w1" "$o1"

o2="$(outer w2)"; printf 'tmp/\n' > "$o2/.gitignore"; mkdir -p "$o2/tmp/h.w2"
refused W2 "$o2/tmp/h.w2" "$o2"

o3="$(outer w3)"
refused W3 "$o3" "$o3"
head3="$(git -C "$o3" symbolic-ref HEAD 2>&1)"
if [ "$head3" = refs/heads/main ] && [ ! -e "$o3/$_PRODUCT_FIXTURE_MARK" ]; then
    ok "W3 HEAD общей копии цел ($head3), маркера фикстуры нет"
else
    bad "W3 — init тронул общую копию: HEAD $head3"
fi

o4="$(outer w4)"
refused W4 "$o4/deep/h.w4" "$o4"
if [ ! -e "$o4/deep" ]; then ok "W4 каталог внутри копии не создан"; else bad "W4 — каталог $o4/deep создан"; fi

d5="$(mktemp -d -p "$TMP" h.XXXXXX)"
out="$(product_fixture_init "$d5" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -e "$d5/$_PRODUCT_FIXTURE_MARK" ]; then
    ok "W5 законный близнец: каталог вне копии принят (код 0, маркер на месте)"
else
    bad "W5 — законный каталог отвергнут: код $rc" "$out"
fi

echo "== product_fixture_root_census: перепись места фикстур =="
out="$(product_fixture_root_census "$TMP" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF -- "$TMP" <<<"$out" && grep -qF 'вне рабочей копии git' <<<"$out"; then
    ok "W6 корень вне копии: код 0, путь напечатан"
else
    bad "W6 — корень вне копии: код $rc" "$out"
fi
o6="$(outer w6)"
out="$(product_fixture_root_census "$o6" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF '[VOID]' <<<"$out" && grep -qF -- "$o6" <<<"$out"; then
    ok "W6' корень внутри копии: код 2, [VOID], копия названа"
else
    bad "W6' — корень внутри копии: код $rc" "$out"
fi

echo "[CENSUS] inject-10: утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$((pass + fail))" -gt 0 ] || { echo "[VOID] inject-10 — ни одной пробы не исполнено" >&2; exit 2; }
[ "$fail" -eq 0 ] || { echo "[FAIL] inject-10 — страж места фикстуры не доказан: разошлось $fail" >&2; exit 1; }
echo "[PASS] inject-10 — страж места фикстуры доказан: проб $pass, разошлось 0"
