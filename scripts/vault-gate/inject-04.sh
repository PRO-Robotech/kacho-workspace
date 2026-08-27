#!/usr/bin/env bash
# Доказательство того, что check-04 (свежесть перечня) СПОСОБЕН упасть и
# СПОСОБЕН смолчать.
#
# Контроли:
#   1. в дерево добавлена записка, перечень не пересобран → код 1 (гейт ловит
#      именно расхождение перечня с файлами);
#   2. законный близнец: та же записка, но перечень пересобран → код 0. Без
#      этого контроля гейт было бы не отличить от «всегда красный»;
#   3. законный близнец разделения: правка ПРОЗАИЧЕСКОЙ половины указателя
#      (`INDEX.md`) расхождением не является → код 0. Это и есть контракт,
#      ради которого указатель разделён: человеческий текст живёт своей жизнью,
#      машинный перечень — своей;
#   4. машинная половина удалена целиком → код 1, а НЕ 0 и не VOID. Предмет
#      (записки) прочитан, значит отсутствие перечня — расхождение, а не
#      отсутствие предмета. Молчание здесь зеленело бы ровно на удалении;
#   5. записок не прочитано ни одной → код 2 (VOID). Пустая перепись сходится
#      тривиально: пустой перечень совпал бы с пустым файлом, и вердикт был бы
#      зелёным — «ноль находок», неотличимый от «ноль прочитанного».
#
# Окружение git снимается по той же причине, что и в inject-05: проба, заводящая
# свой репозиторий при выставленном `GIT_DIR`, пишет в РАБОЧУЮ копию.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-04-index-fresh.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ok=0; bad=0

NOTES="obsidian/kacho/INDEX-notes.md"
PROSE="obsidian/kacho/INDEX.md"

setup_tree() {
    local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q
    (cd "$WS_REAL" && git ls-files --cached --others --exclude-standard \
        'obsidian/kacho/*' 'scripts/vault-index/*') | while read -r f; do
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

# --- (1) записка заведена, перечень не пересобран
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
out="$(run_on "$d")"; expect_code "новая записка без пересборки перечня поймана" 1 "$?" "$out"

# --- (2) законный близнец: перечень пересобран
VAULT_GATE_ROOT="$d" python3 "$d/scripts/vault-index/generate.py" >/dev/null
out="$(run_on "$d")"; expect_code "законный близнец: после пересборки — чисто" 0 "$?" "$out"

# --- (3) законный близнец разделения: правка ПРОЗЫ — не расхождение
printf '\nдописанный вручную абзац\n' >> "$d/$PROSE"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/obsidian/kacho/INDEX.md"
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("# INDEX", "# INDEX (правка прозаической половины)", 1))
PY
out="$(run_on "$d")"; expect_code "законный близнец: правка прозы — не расхождение" 0 "$?" "$out"

# --- (4) машинная половина удалена целиком → FAIL, не VOID и не PASS
d2="$(setup_tree deleted)"
rm -f "$d2/$NOTES"
out="$(run_on "$d2")"; code=$?
expect_code "перечень удалён целиком — расхождение, а не «нечего проверять»" 1 "$code" "$out"
if printf '%s' "$out" | grep -qF "$NOTES"; then
    echo "[inject OK]   удаление названо координатой ($NOTES)"; ok=$((ok+1))
else
    echo "[inject FAIL] в выводе нет координаты $NOTES" >&2; bad=$((bad+1))
fi

# --- (5) записок не прочитано ни одной → VOID
d3="$TMP/emptyvault"; mkdir -p "$d3/obsidian/kacho"; git -C "$d3" init -q
install -D "$WS_REAL/scripts/vault-index/generate.py" "$d3/scripts/vault-index/generate.py"
: > "$d3/$NOTES"
out="$(run_on "$d3")"; expect_code "ни одной записки не прочитано — VOID, а не «совпадает»" 2 "$?" "$out"

echo
echo "inject-04: контролей пройдено $ok, провалено $bad"
[ "$bad" -eq 0 ]
