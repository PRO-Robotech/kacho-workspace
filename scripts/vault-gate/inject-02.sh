#!/usr/bin/env bash
# Доказательство того, что check-02 (висячие ссылки) СПОСОБЕН упасть и СПОСОБЕН
# смолчать — на настоящих записках, а не на синтетике.
#
# Контроли, и почему именно они:
#   1. внесена ссылка в никуда → код 1 и названа цель (гейт ловит рост);
#   2. законный близнец: ссылка той же формы на СУЩЕСТВУЮЩУЮ записку — в трёх
#      формах сразу (от корня, короткая по имени, относительная `../`), потому
#      что резолв Obsidian трёхправильный и проверка, знающая одно правило,
#      объявляет висячими полторы тысячи живых ссылок. Ожидание — молчание;
#   3. основание отстало ВНИЗ (висячих стало меньше) → тоже код 1: послабление,
#      которому больше нечего прощать, обязано истечь, а не тихо переживать свой
#      предмет;
#   4. предпосылка исчезла (хранилище пусто) → код 2 (VOID), не 0. Гейт, который
#      тем зеленее, чем меньше видит, — худший из возможных.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-02-dangling-wikilinks.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0
bad=0

# Рабочая копия хранилища: инъекция не трогает настоящее дерево.
setup_tree() {
    local d="$TMP/$1"
    rm -rf "$d"
    mkdir -p "$d"
    git -C "$d" init -q 2>/dev/null || { mkdir -p "$d"; git -C "$d" init -q; }
    (cd "$WS_REAL" && git ls-files --cached --others --exclude-standard 'obsidian/kacho/*') | while read -r f; do
        install -D "$WS_REAL/$f" "$d/$f"
    done
    git -C "$d" add -A >/dev/null 2>&1
    printf '%s' "$d"
}

run_on() { VAULT_GATE_ROOT="$1" bash "$CHECK" 2>&1; }

expect_code() {
    local name="$1" want="$2" got="$3" out="$4"
    if [ "$got" = "$want" ]; then
        echo "[inject OK]   $name (ожидали код $want, получили $got)"
        ok=$((ok + 1))
    else
        echo "[inject FAIL] $name (ожидали код $want, получили $got)" >&2
        printf '%s\n' "$out" | sed 's/^/    /' >&2
        bad=$((bad + 1))
    fi
}

expect_names() {
    local name="$1" needle="$2" out="$3"
    case "$out" in
        *"$needle"*) echo "[inject OK]   $name (гейт назвал $needle)"; ok=$((ok + 1)) ;;
        *) echo "[inject FAIL] $name (гейт не назвал $needle)" >&2; bad=$((bad + 1)) ;;
    esac
}

expect_silent_about() {
    local name="$1" needle="$2" out="$3"
    case "$out" in
        *"$needle"*) echo "[inject FAIL] $name (гейт назвал $needle, а не должен был)" >&2; bad=$((bad + 1)) ;;
        *) echo "[inject OK]   $name (про $needle гейт молчит)"; ok=$((ok + 1)) ;;
    esac
}

# --- (1) Внесённый дефект: ссылка на записку, которой нет.
d="$(setup_tree defect)"
cat > "$d/obsidian/kacho/edges/zz-inject-dangling.md" <<'EOF'
---
title: "инъекция: ссылка в никуда"
category: edge
status: active
---
# инъекция
Ссылка на [[resources/zz-nonexistent-resource]] — такой записки в дереве нет.
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "внесённая висячая ссылка поймана" 1 "$code" "$out"
expect_names "гейт назвал цель" "zz-nonexistent-resource" "$out"

# --- (2) Законный близнец: три живые формы ссылки. Гейт обязан смолчать про них.
d="$(setup_tree twin)"
cat > "$d/obsidian/kacho/edges/zz-inject-live-links.md" <<'EOF'
---
title: "инъекция: живые ссылки трёх форм"
category: edge
status: active
---
# инъекция
От корня: [[resources/vpc-subnet]]. Короткая: [[vpc-subnet]]. Относительная: [[../resources/vpc-subnet]].
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "законный близнец: три живые формы не считаются висячими" 0 "$code" "$out"
expect_silent_about "законный близнец: гейт не называет живую цель" "vpc-subnet" "$out"

# --- (3) Основание отстало вниз: цель из основания больше не висит.
d="$(setup_tree stale_baseline)"
# Основание = настоящее плюс ОДНА лишняя цель: рост исключён by construction,
# поэтому контроль спрашивает ровно про устаревание, а не про смесь двух причин.
cat "$SCRIPT_DIR/dangling-baseline.txt" > "$TMP/stale-baseline.txt"
printf '1\tzz-target-that-no-longer-dangles\n' >> "$TMP/stale-baseline.txt"
out="$(VAULT_GATE_ROOT="$d" VAULT_GATE_BASELINE="$TMP/stale-baseline.txt" bash "$CHECK" 2>&1)"; code=$?
expect_code "устаревшее основание (цель больше не висит) — тоже находка" 1 "$code" "$out"
expect_names "гейт объяснил, что основание переписать" "УСТАРЕЛО" "$out"

# --- (4) Предпосылки нет: хранилище пусто → VOID, не PASS.
d="$TMP/void"
rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q
out="$(run_on "$d")"; code=$?
expect_code "пустое хранилище даёт VOID, а не PASS" 2 "$code" "$out"

echo
echo "inject-02: контролей пройдено $ok, провалено $bad"
[ "$bad" -eq 0 ]
