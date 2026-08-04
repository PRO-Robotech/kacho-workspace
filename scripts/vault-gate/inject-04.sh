#!/usr/bin/env bash
# Доказательство того, что check-04 (свежесть указателя) СПОСОБЕН упасть и
# СПОСОБЕН смолчать.
#
# Контроли:
#   1. в дерево добавлена записка, указатель не пересобран → код 1 (гейт ловит
#      именно расхождение перечня с файлами);
#   2. законный близнец: та же записка, но указатель пересобран → код 0. Без
#      этого контроля гейт было бы не отличить от «всегда красный»;
#   3. правка РУКОПИСНОЙ части указателя не считается расхождением → код 0:
#      генератор владеет только областью между маркерами, и краснеть на чужой
#      части значило бы запрещать писать вводный текст;
#   4. маркеров нет → код 2 (VOID), не 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-04-index-fresh.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ok=0; bad=0

setup_tree() {
    local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q
    (cd "$WS_REAL" && git ls-files --cached --others --exclude-standard 'obsidian/kacho/*' 'scripts/vault-index/*') | while read -r f; do
        install -D "$WS_REAL/$f" "$d/$f"
    done
    git -C "$d" add -A >/dev/null 2>&1
    printf '%s' "$d"
}
expect_code() {
    local name="$1" want="$2" got="$3" out="$4"
    if [ "$got" = "$want" ]; then echo "[inject OK]   $name (ожидали код $want, получили $got)"; ok=$((ok+1))
    else echo "[inject FAIL] $name (ожидали код $want, получили $got)" >&2; printf '%s\n' "$out" | sed 's/^/    /' >&2; bad=$((bad+1)); fi
}
run_on() { VAULT_GATE_ROOT="$1" bash "$CHECK" 2>&1; }

# --- (1) записка заведена, указатель не пересобран
d="$(setup_tree stale)"
cat > "$d/obsidian/kacho/resources/zz-inject-new-note.md" <<'EOF'
---
title: "инъекция: новая записка"
category: resource
status: stable
---
# инъекция
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; expect_code "новая записка без пересборки указателя поймана" 1 "$?" "$out"

# --- (2) законный близнец: указатель пересобран
VAULT_GATE_ROOT="$d" python3 "$d/scripts/vault-index/generate.py" >/dev/null
out="$(run_on "$d")"; expect_code "законный близнец: после пересборки — чисто" 0 "$?" "$out"

# --- (3) законный близнец: правка рукописной части
printf '\nдописанный вручную абзац\n' >> "$d/obsidian/kacho/INDEX.md"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/obsidian/kacho/INDEX.md"
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("# INDEX", "# INDEX (правка рукописной части)", 1))
PY
out="$(run_on "$d")"; expect_code "законный близнец: рукописная часть — не расхождение" 0 "$?" "$out"

# --- (4) маркеров нет → VOID
d2="$(setup_tree nomarkers)"
python3 - "$d2" <<'PY'
import sys, re
p = sys.argv[1] + "/obsidian/kacho/INDEX.md"
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"<!-- GENERATED:vault-index.*", "", t, flags=re.S))
PY
out="$(run_on "$d2")"; expect_code "без маркеров — VOID, а не PASS" 2 "$?" "$out"

echo
echo "inject-04: контролей пройдено $ok, провалено $bad"
[ "$bad" -eq 0 ]
