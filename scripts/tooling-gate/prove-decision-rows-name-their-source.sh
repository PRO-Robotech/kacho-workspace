#!/usr/bin/env bash
# Инъекция для check-13 — в обе стороны, на СИНТЕТИКЕ.
#
#   A     новая строка §12 без источника, в ведомости её нет           -> 1
#   A'    та же строка С ДАТОЙ                                          -> 0
#   A''   та же строка С КООРДИНАТОЙ правила                            -> 0
#   B     строка ведомости, которая теперь источник называет (зажила)   -> 1
#   C     ссылка на СОСЕДНИЙ РАЗДЕЛ (§7) источником не считается        -> 1
#   VOID1 раздела 12 нет                                                -> 2
#   VOID2 раздел 12 пуст                                                -> 2
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF_DIR/check-13-decision-rows-name-their-source.sh"
PASS=0; FAIL=0

sandbox() { # печатает каталог с базой, содержащей переданные строки §12
  local dir; dir="$(mktemp -d "${TMPDIR:-/tmp}/probe-c13-XXXXXX")"
  mkdir -p "$dir/.claude/agents" "$dir/scripts/tooling-gate"
  cp "$CHECK" "$dir/scripts/tooling-gate/"
  { echo "# База"; echo; echo "## 11. Прежний раздел"; echo; echo "текст"; echo;
    echo "## 12. Противоречия, разрешённые в базе"; echo;
    echo "По более позднему решению, с источником."; echo; } > "$dir/.claude/agents/dispatcher.md"
  local l; for l in "$@"; do echo "- $l" >> "$dir/.claude/agents/dispatcher.md"; done
  echo "$dir"
}
ledger() { printf '%s\n' "$2" > "$1/scripts/tooling-gate/decision-source-baseline.txt"; }
run() { KACHO_WS="$1" bash "$1/scripts/tooling-gate/check-13-decision-rows-name-their-source.sh" >/dev/null 2>&1; echo $?; }
assert() { if [ "$1" = "$2" ]; then echo "  ✔ $3 (код $2)"; PASS=$((PASS+1)); else echo "  ✘ $3 — ждали $1, получили $2"; FAIL=$((FAIL+1)); fi; }

echo "инъекция check-13-decision-rows-name-their-source:"

d="$(sandbox "Старое чтение → новое чтение без всякого источника.")"; ledger "$d" ""
assert 1 "$(run "$d")" "ДЕФЕКТ: строка без источника, в ведомости её нет"; rm -rf "$d"

d="$(sandbox "Старое чтение → новое чтение, решение владельца 2026-09-17.")"; ledger "$d" ""
assert 0 "$(run "$d")" "БЛИЗНЕЦ: та же строка С ДАТОЙ — молчит"; rm -rf "$d"

d="$(sandbox "Старое чтение → новое чтение (\`testing.md\` §«Раздел»).")"; ledger "$d" ""
assert 0 "$(run "$d")" "БЛИЗНЕЦ: та же строка С КООРДИНАТОЙ — молчит"; rm -rf "$d"

d="$(sandbox "Старое чтение → новое чтение, решение владельца 2026-09-17.")"
ledger "$d" "Старое чтение"
assert 1 "$(run "$d")" "ЗАЖИЛА: строка ведомости назвала источник — ведомость обязана сократиться"; rm -rf "$d"

d="$(sandbox "Старое чтение → новое чтение, исключение §7 базы.")"; ledger "$d" ""
assert 1 "$(run "$d")" "СОСЕД: ссылка на §7 источником НЕ считается"; rm -rf "$d"

d="$(mktemp -d "${TMPDIR:-/tmp}/probe-c13-XXXXXX")"; mkdir -p "$d/.claude/agents" "$d/scripts/tooling-gate"
cp "$CHECK" "$d/scripts/tooling-gate/"; printf '# База\n\n## 11. Раздел\n\nтекст\n' > "$d/.claude/agents/dispatcher.md"
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: раздела 12 нет — код 2, не зелёное"; rm -rf "$d"

d="$(sandbox)"; ledger "$d" ""
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: раздел 12 пуст — код 2, не зелёное"; rm -rf "$d"

echo "инъекция: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ]
