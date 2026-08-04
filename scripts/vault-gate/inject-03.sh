#!/usr/bin/env bash
# Доказательство того, что check-03 (оболочка записки) СПОСОБЕН упасть и
# СПОСОБЕН смолчать.
#
# Контроли, и почему именно они:
#   1. записка без состояния в категории, где оно обязательно → код 1 и названа
#      координата;
#   2. состояние вне словаря (`status: живо` вместо канонического значения) →
#      код 1: неизвестное значение проходит фильтры срезов молча, и это опаснее
#      отсутствующего;
#   3. законный близнец A: полная оболочка → молчание про этот файл. Без него
#      гейт ловил бы форму, а не существо, и первый ложный срабат его отключил бы;
#   4. законный близнец B: витрина категории (`README.md`) без состояния → тоже
#      молчание: её предмет — перечень, а не сущность продукта;
#   5. предпосылка исчезла: в контракте хранилища нет таблицы словаря состояний
#      → код 2 (VOID), не 0. Словарь выводится из контракта, и без него судить
#      не по чему.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-03-note-shell.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0
bad=0

setup_tree() {
    local d="$TMP/$1"
    rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q
    (cd "$WS_REAL" && git ls-files --cached --others --exclude-standard 'obsidian/kacho/*') | while read -r f; do
        install -D "$WS_REAL/$f" "$d/$f"
    done
    git -C "$d" add -A >/dev/null 2>&1
    printf '%s' "$d"
}

run_on() { VAULT_GATE_ROOT="$1" bash "$CHECK" 2>&1; }

expect_code() {
    local name="$1" want="$2" got="$3" out="$4"
    if [ "$got" = "$want" ]; then echo "[inject OK]   $name (ожидали код $want, получили $got)"; ok=$((ok + 1))
    else echo "[inject FAIL] $name (ожидали код $want, получили $got)" >&2; printf '%s\n' "$out" | sed 's/^/    /' >&2; bad=$((bad + 1)); fi
}
expect_names() {
    local name="$1" needle="$2" out="$3"
    case "$out" in *"$needle"*) echo "[inject OK]   $name (гейт назвал $needle)"; ok=$((ok + 1)) ;;
        *) echo "[inject FAIL] $name (гейт не назвал $needle)" >&2; bad=$((bad + 1)) ;; esac
}
expect_silent_about() {
    local name="$1" needle="$2" out="$3"
    case "$out" in *"$needle"*) echo "[inject FAIL] $name (гейт назвал $needle, а не должен был)" >&2; bad=$((bad + 1)) ;;
        *) echo "[inject OK]   $name (про $needle гейт молчит)"; ok=$((ok + 1)) ;; esac
}

# --- (1) Записка ресурса без состояния.
d="$(setup_tree no_status)"
cat > "$d/obsidian/kacho/resources/zz-inject-no-status.md" <<'EOF'
---
title: "инъекция: ресурс без состояния"
category: resource
---
# инъекция
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "записка без состояния поймана" 1 "$code" "$out"
expect_names "гейт назвал координату" "zz-inject-no-status.md" "$out"

# --- (2) Состояние вне словаря.
d="$(setup_tree bad_status)"
cat > "$d/obsidian/kacho/resources/zz-inject-bad-status.md" <<'EOF'
---
title: "инъекция: состояние вне словаря"
category: resource
status: живо
---
# инъекция
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "состояние вне словаря поймано" 1 "$code" "$out"
expect_names "гейт назвал координату" "zz-inject-bad-status.md" "$out"

# --- (3) Законный близнец A: полная оболочка.
d="$(setup_tree twin_full)"
cat > "$d/obsidian/kacho/resources/zz-inject-twin-full.md" <<'EOF'
---
title: "инъекция: полная оболочка"
category: resource
status: stable
verified_against: "инъекция"
---
# инъекция
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "законный близнец: полная оболочка проходит" 0 "$code" "$out"
expect_silent_about "законный близнец: гейт про него молчит" "zz-inject-twin-full.md" "$out"

# --- (4) Законный близнец B: витрина категории без состояния.
d="$(setup_tree twin_showcase)"
mkdir -p "$d/obsidian/kacho/zzcat"
cat > "$d/obsidian/kacho/resources/all-zz-inject.md" <<'EOF'
---
title: "инъекция: витрина без состояния"
category: hub
---
# инъекция
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "законный близнец: витрина без состояния проходит" 0 "$code" "$out"
expect_silent_about "законный близнец: гейт про витрину молчит" "all-zz-inject.md" "$out"

# --- (5) Предпосылки нет: в контракте хранилища нет таблицы словаря.
d="$(setup_tree void_vocab)"
python3 - "$d" <<'PY'
import sys, re
p = sys.argv[1] + "/obsidian/kacho/CLAUDE.md"
text = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"^\|\s*Ведро\s*\|.*?(?=\n\n)", "(таблица снята инъекцией)", text, flags=re.S | re.M))
PY
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "без словаря состояний — VOID, а не PASS" 2 "$code" "$out"

echo
echo "inject-03: контролей пройдено $ok, провалено $bad"
[ "$bad" -eq 0 ]
