#!/usr/bin/env bash
# Инъекция для check-10 — в обе стороны, на СИНТЕТИКЕ.
#
#   A     потолок подняли, ведомость не тронули                 -> 1
#   A'    подняли И ведомость, запас остался                    -> 0
#   B     запас МЕНЬШЕ медианного абзаца                        -> 1
#   B'    запас РОВНО в медианный абзац                         -> 0
#   C     строка ведомости без предмета                         -> 1
#   D     строка ведомости, которой нечего обосновывать         -> 1
#   VOID1 в check-02 нет BUDGET                                 -> 2
#   VOID2 ведомости нет                                         -> 2
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF_DIR/check-10-ceiling-raise-carries-its-basis.sh"
PASS=0; FAIL=0

# Мир: цель из 10 абзацев по 100 Б -> тело 1010 Б, медианный абзац 100 Б.
sandbox() { # <потолок> <строка ведомости или пусто> [--no-budget|--no-ledger]
  local dir; dir="$(mktemp -d "${TMPDIR:-/tmp}/probe-c10-XXXXXX")"
  mkdir -p "$dir/scripts/rules-gate" "$dir/.claude/agents"
  cp "$CHECK" "$dir/scripts/rules-gate/"
  python3 -c "
import sys
p=['а'*50 for _ in range(10)]
open(sys.argv[1],'w',encoding='utf-8').write('\n\n'.join(p))" "$dir/CLAUDE.md"
  if [ "${3:-}" != "--no-budget" ]; then
    printf 'CLAUDE_REL = "CLAUDE.md"\nBUDGET = {CLAUDE_REL: %s}\n' "$1" \
      > "$dir/scripts/rules-gate/check-02-nothing-lost.sh"
  else
    printf 'CLAUDE_REL = "CLAUDE.md"\n' > "$dir/scripts/rules-gate/check-02-nothing-lost.sh"
  fi
  if [ "${3:-}" != "--no-ledger" ]; then
    { echo "# проба"; [ -n "$2" ] && echo "$2"; } > "$dir/scripts/rules-gate/ceiling-basis.txt"
  fi
  echo "$dir"
}
run() { KACHO_WS="$1" bash "$1/scripts/rules-gate/check-10-ceiling-raise-carries-its-basis.sh" >/dev/null 2>&1; echo $?; }
assert() { if [ "$1" = "$2" ]; then echo "  ✔ $3 (код $2)"; PASS=$((PASS+1)); else echo "  ✘ $3 — ждали $1, получили $2"; FAIL=$((FAIL+1)); fi; }

# Тело и медиана ИЗМЕРЯЮТСЯ на самом мире, а не выписываются: кириллический знак
# двухбайтовый, разделители абзацев тоже считаются, и выписанное число уже раз солгало:
# ось B' падала не от дефекта, а от ошибки самой пробы.
_m="$(sandbox 99999 "")"
BODY=$(wc -c < "$_m/CLAUDE.md")
MED=$(python3 -c "
import sys
d=open(sys.argv[1],'rb').read()
p=sorted(len(x) for x in d.split(b'\n\n') if x.strip())
print(p[len(p)//2])" "$_m/CLAUDE.md")
rm -rf "$_m"
echo "инъекция check-10-ceiling-raise-carries-its-basis (тело $BODY Б, медианный абзац $MED Б):"

d="$(sandbox $((BODY+300)) "CLAUDE.md | $((BODY+150)) | 2026-09-18 | установка | предмет назван | без него невозможно")"
assert 1 "$(run "$d")" "ДЕФЕКТ: потолок подняли, ведомость не тронули"; rm -rf "$d"

d="$(sandbox $((BODY+300)) "CLAUDE.md | $((BODY+300)) | 2026-09-21 | подъём | предмет назван | без него невозможно")"
assert 0 "$(run "$d")" "БЛИЗНЕЦ: подняли И ведомость, запас остался — молчит"; rm -rf "$d"

d="$(sandbox $((BODY+MED-1)) "CLAUDE.md | $((BODY+MED-1)) | 2026-09-21 | подъём | предмет назван | без него невозможно")"
assert 1 "$(run "$d")" "ДЕФЕКТ: запас на байт МЕНЬШЕ медианного абзаца"; rm -rf "$d"

d="$(sandbox $((BODY+MED)) "CLAUDE.md | $((BODY+MED)) | 2026-09-21 | подъём | предмет назван | без него невозможно")"
assert 0 "$(run "$d")" "БЛИЗНЕЦ: запас РОВНО в медианный абзац — молчит"; rm -rf "$d"

d="$(sandbox $((BODY+300)) "CLAUDE.md | $((BODY+300)) | 2026-09-21 | подъём |  | без него невозможно")"
assert 1 "$(run "$d")" "ДЕФЕКТ: подъём без названного предмета"; rm -rf "$d"

d="$(sandbox $((BODY+300)) "CLAUDE.md | $((BODY+300)) | 2026-09-21 | подъём | предмет назван | без него невозможно
.claude/agents/dispatcher.md | 96000 | 2026-09-18 | установка | предмет | без него")"
assert 1 "$(run "$d")" "ДЕФЕКТ: основание, которому нечего обосновывать"; rm -rf "$d"

d="$(sandbox $((BODY+300)) "" --no-budget)"
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: в check-02 нет BUDGET — код 2"; rm -rf "$d"

d="$(sandbox $((BODY+300)) "" --no-ledger)"
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: ведомости нет — код 2"; rm -rf "$d"

echo "инъекция: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ]
