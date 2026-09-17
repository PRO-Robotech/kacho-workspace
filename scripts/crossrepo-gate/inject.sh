#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: Apache-2.0
#
# inject.sh — доказательство способности check-01 упасть И СМОЛЧАТЬ.
#
# Деревья СИНТЕТИЧЕСКИЕ: судить чужие рабочие копии проверка не вправе, а инъекции
# нужен управляемый мир. Каждая ось меняет ОДИН факт против законного близнеца.
#
#   A  пара есть, записи нет                       → находка с координатой
#   A' та же пара объявлена `debt` с задачей       → молчание (он же близнец оси D)
#   B  запись есть, пары нет                       → находка (самоистечение)
#   C  решение вне словаря                         → находка
#   D  `debt` без задачи                           → находка
#   E  `own` на побайтово совпадающей паре         → находка
#   E' `own` на РАЗНОЙ паре                        → молчание
#   F  клона нет                                   → VOID (код 2), не «находок 0»
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

pass=0; fail=0

# repo <имя> <файл>=<содержимое> … — синтетический ствол.
repo() {
  local name=$1; shift
  local dir="$box/ws/project/$name"
  mkdir -p "$dir"
  local kv
  for kv in "$@"; do
    local path="${kv%%=*}" body="${kv#*=}"
    mkdir -p "$dir/$(dirname "$path")"
    printf '%s\n' "$body" > "$dir/$path"
  done
  git -C "$dir" init -q
  git -C "$dir" -c user.email=i@x.invalid -c user.name=i add -A
  git -C "$dir" -c user.email=i@x.invalid -c user.name=i commit -q -m inj
  git -C "$dir" update-ref refs/remotes/origin/main "$(git -C "$dir" rev-parse HEAD)"
}

# world <ведомость> — собрать мир заново и вернуть корень воркспейса.
world() {
  rm -rf "$box/ws"
  mkdir -p "$box/ws/docs"
  git -C "$box/ws" init -q 2>/dev/null || true
  printf '%s\n' "$1" > "$box/ws/docs/crossrepo-pairs.yaml"
  echo "$box/ws"
}

run() { ( cd "$1" && DOCS_GATE_ROOT="$1" python3 "$here/check-01-paired-files-are-declared.py" 2>&1 ); }

assert() { # <ось> <код> <подстрока> <вывод> <rc>
  local axis=$1 want=$2 needle=$3 out=$4 rc=$5
  if [[ "$rc" == "$want" ]] && grep -qF -- "$needle" <<<"$out"; then
    echo "  ok   $axis"; pass=$((pass+1))
  else
    echo "  FAIL $axis: код $rc (ожидался $want); искали «$needle»"
    sed 's/^/       | /' <<<"$out"; fail=$((fail+1))
  fi
}

# ── A / A' : пара без записи и с записью ────────────────────────────────────
ws="$(world 'pairs: []')"
repo kacho  'tools/shared.py=одно' 'own-a.txt=своё'
repo kaname 'tools/shared.py=другое' 'own-b.txt=своё'
repo corelib 'own-c.txt=своё'
out="$(run "$ws")"; rc=$?
assert "A  пара без записи — находка" 1 "tools/shared.py" "$out" "$rc"
assert "A  находка называет держателей" 1 "kacho+kaname" "$out" "$rc"

ws="$(world 'pairs:
  - path: tools/shared.py
    decision: debt
    issue: PRO-Robotech/kacho#1')"
repo kacho  'tools/shared.py=одно' 'own-a.txt=своё'
repo kaname 'tools/shared.py=другое' 'own-b.txt=своё'
repo corelib 'own-c.txt=своё'
out="$(run "$ws")"; rc=$?
assert "A' объявленная пара молчит" 0 "все 1 пар объявлены" "$out" "$rc"

# ── B : запись без предмета ─────────────────────────────────────────────────
ws="$(world 'pairs:
  - path: tools/gone.py
    decision: debt
    issue: PRO-Robotech/kacho#1')"
repo kacho  'own-a.txt=своё'
repo kaname 'own-b.txt=своё'
repo corelib 'own-c.txt=своё'
out="$(run "$ws")"; rc=$?
assert "B  запись без пары — самоистечение" 1 "самоистечение" "$out" "$rc"

# ── C : решение вне словаря ─────────────────────────────────────────────────
ws="$(world 'pairs:
  - path: tools/shared.py
    decision: потом')"
repo kacho  'tools/shared.py=одно'
repo kaname 'tools/shared.py=другое'
repo corelib 'own-c.txt=своё'
out="$(run "$ws")"; rc=$?
assert "C  решение вне словаря — находка" 1 "вне словаря" "$out" "$rc"

# ── D / D' : долг без задачи и с задачей ────────────────────────────────────
ws="$(world 'pairs:
  - path: tools/shared.py
    decision: debt')"
repo kacho  'tools/shared.py=одно'
repo kaname 'tools/shared.py=другое'
repo corelib 'own-c.txt=своё'
out="$(run "$ws")"; rc=$?
assert "D  долг без задачи — находка" 1 "не называет задачи" "$out" "$rc"

# ── E / E' : own на совпадающем и на разном ─────────────────────────────────
ws="$(world 'pairs:
  - path: Makefile
    decision: own')"
repo kacho  'Makefile=одно и то же'
repo kaname 'Makefile=одно и то же'
repo corelib 'own-c.txt=своё'
out="$(run "$ws")"; rc=$?
assert "E  own на совпадающей паре — находка" 1 "ПОБАЙТОВО совпадает" "$out" "$rc"

ws="$(world 'pairs:
  - path: Makefile
    decision: own')"
repo kacho  'Makefile=цели платформы'
repo kaname 'Makefile=цели службы'
repo corelib 'own-c.txt=своё'
out="$(run "$ws")"; rc=$?
assert "E' own на разной паре молчит" 0 "все 1 пар объявлены" "$out" "$rc"

# ── F : клона нет ───────────────────────────────────────────────────────────
ws="$(world 'pairs: []')"
repo kacho 'own-a.txt=своё'
out="$(run "$ws")"; rc=$?
assert "F  клона нет — VOID" 2 "[VOID]" "$out" "$rc"

echo "инъекция crossrepo-gate: утверждений $((pass+fail)), пройдено $pass, провалено $fail"
[[ "$fail" == 0 ]]
