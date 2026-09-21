#!/usr/bin/env bash
# Инъекция для check-15 — на СИНТЕТИКЕ, обе стороны у каждой оси.
#
#   A    в копии НЕТ поля канона (ровно тот дефект, ради которого заведено) -> 1
#   A'   поле дотянуто                                                       -> 0
#   B    в копии ЛИШНЕЕ поле                                                 -> 1
#   C    состав тот же, ПОРЯДОК другой                                       -> 1
#   D    значения полей РАЗНЫЕ при том же составе — законно                  -> 0
#   VOID1 канона нет                                                         -> 2
#   VOID2 копий ноль                                                         -> 2
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF_DIR/check-15-contract-copies-agree.sh"
PASS=0; FAIL=0

mk() { # <dir> <файл> <поля...>
  local f="$1/$2"; shift 2; mkdir -p "$(dirname "$f")"
  { echo '```'; echo '### ВОЗВРАТ'; for x in "$@"; do echo "- $x"; done; echo '```'; } >> "$f"; }
sandbox() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/probe-c15-XXXXXX")"
  mkdir -p "$d/.claude/agents" "$d/scripts/tooling-gate"; cp "$CHECK" "$d/scripts/tooling-gate/"; echo "$d"; }
run() { KACHO_WS="$1" bash "$1/scripts/tooling-gate/check-15-contract-copies-agree.sh" >/dev/null 2>&1; echo $?; }
assert() { if [ "$1" = "$2" ]; then echo "  ✔ $3 (код $2)"; PASS=$((PASS+1)); else echo "  ✘ $3 — ждали $1, получили $2"; FAIL=$((FAIL+1)); fi; }

echo "инъекция check-15-contract-copies-agree:"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово' 'факты: <…>' 'несостоявшаяся загрузка: —'
mk "$d" .claude/agents/a.md 'статус: готово' 'факты: <…>'
assert 1 "$(run "$d")" "ДЕФЕКТ: в копии нет поля канона"; rm -rf "$d"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово' 'факты: <…>' 'несостоявшаяся загрузка: —'
mk "$d" .claude/agents/a.md 'статус: готово' 'факты: <…>' 'несостоявшаяся загрузка: —'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: поле дотянуто — молчит"; rm -rf "$d"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово' 'факты: <…>'
mk "$d" .claude/agents/a.md 'статус: готово' 'факты: <…>' 'своё поле: —'
assert 1 "$(run "$d")" "ДЕФЕКТ: в копии лишнее поле"; rm -rf "$d"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово' 'факты: <…>'
mk "$d" .claude/agents/a.md 'факты: <…>' 'статус: готово'
assert 1 "$(run "$d")" "ДЕФЕКТ: состав тот же, порядок другой"; rm -rf "$d"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово | блокер | не-выполнилось' 'вердикт: — | ✅ | ⛔'
mk "$d" .claude/agents/a.md 'статус: готово' 'вердикт: — | ⟳ прогон недействителен'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: ЗНАЧЕНИЯ разные при том же составе — законно"; rm -rf "$d"

d="$(sandbox)"; mk "$d" .claude/agents/a.md 'статус: готово'
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: канона нет — код 2"; rm -rf "$d"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово'
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: копий ноль — код 2, не зелёное"; rm -rf "$d"

echo "инъекция: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ]
