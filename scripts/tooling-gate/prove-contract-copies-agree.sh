#!/usr/bin/env bash
# Инъекция для check-15 — на СИНТЕТИКЕ, обе стороны у каждой оси.
#
# Миры — настоящие git-репозитории: обход берёт `git ls-files`, и мир без индекса
# проверял бы не то, что дерево.
#
#   A    в копии НЕТ поля канона                                          -> 1
#   A'   поле дотянуто                                                    -> 0
#   B    в копии ЛИШНЕЕ поле                                              -> 1
#   C    состав тот же, ПОРЯДОК другой                                    -> 1
#   D    значения полей РАЗНЫЕ при том же составе — законно               -> 0
#   E    копия в ПРАВИЛЕ корпуса расходится (грузится предзагрузкой)      -> 1
#   E'   та же копия в правиле совпадает                                  -> 0
#   F    ПРЕДПОСЫЛКА: блок ВНЕ области                                    -> 1
#   VOID1 канона нет                                                      -> 2
#   VOID2 копий ноль                                                      -> 2
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF_DIR/check-15-contract-copies-agree.sh"
PASS=0; FAIL=0

mk() { local f="$1/$2"; shift 2; mkdir -p "$(dirname "$f")"
  { echo '```'; echo '### ВОЗВРАТ'; for x in "$@"; do echo "- $x"; done; echo '```'; } >> "$f"; }
sandbox() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/probe-c15-XXXXXX")"
  mkdir -p "$d/.claude/agents" "$d/.claude/rules" "$d/scripts/tooling-gate"
  cp "$CHECK" "$d/scripts/tooling-gate/"; git -C "$d" init -q; echo "$d"; }
seal() { git -C "$1" add -A >/dev/null 2>&1; }
run() { seal "$1"; KACHO_WS="$1" bash "$1/scripts/tooling-gate/check-15-contract-copies-agree.sh" >/dev/null 2>&1; echo $?; }
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

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово | блокер' 'вердикт: — | ✅ | ⛔'
mk "$d" .claude/agents/a.md 'статус: готово' 'вердикт: — | ⟳ прогон недействителен'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: ЗНАЧЕНИЯ разные при том же составе — законно"; rm -rf "$d"

# ── ось E: копия в ПРАВИЛЕ. Правило грузится целиком по предзагрузке, значит
# для своих агентов оно тоже контракт. Прежняя редакция обходила только тела.
d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово' 'несостоявшаяся загрузка: —'
mk "$d" .claude/rules/testing.md 'статус: готово'
assert 1 "$(run "$d")" "ДЕФЕКТ: копия в ПРАВИЛЕ корпуса расходится"; rm -rf "$d"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово' 'несостоявшаяся загрузка: —'
mk "$d" .claude/rules/testing.md 'статус: готово' 'несостоявшаяся загрузка: —'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: та же копия в правиле совпадает — молчит"; rm -rf "$d"

# ── ось F: ПРЕДПОСЫЛКА. «Копий вне области ноль» обязано проверяться, иначе
# станет ложью молча — ровно так и пряталась копия в правиле.
d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово'
mk "$d" .claude/agents/a.md 'статус: готово'
mk "$d" docs/rules-copy.md 'статус: готово'
assert 1 "$(run "$d")" "ПРЕДПОСЫЛКА: блок ВНЕ области — находка, а не молчание"; rm -rf "$d"

d="$(sandbox)"; mk "$d" .claude/agents/a.md 'статус: готово'
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: канона нет — код 2"; rm -rf "$d"

d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово'
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: копий ноль — код 2, не зелёное"; rm -rf "$d"

# ── ось C-текст: находка оси ПОРЯДКА обязана говорить про порядок ──────────
# Прежний текст вырождался в «отвечал бы по N полям, считая, что по N».
d="$(sandbox)"; mk "$d" CLAUDE.md 'статус: готово' 'факты: <…>'
mk "$d" .claude/agents/a.md 'факты: <…>' 'статус: готово'
seal "$d"
_out="$(KACHO_WS="$d" bash "$d/scripts/tooling-gate/check-15-contract-copies-agree.sh" 2>&1 || true)"
case "$_out" in
  *"ПОРЯДОК разошёлся"*)
    echo "  ✔ ТЕКСТ: находка оси порядка называет ПОРЯДОК, а не число полей"; PASS=$((PASS+1)) ;;
  *)
    echo "  ✘ ТЕКСТ: находка оси порядка не называет порядок; напечатано:"
    printf '        %s\n' "$_out" | tail -3; FAIL=$((FAIL+1)) ;;
esac
rm -rf "$d"

echo "инъекция: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ]
