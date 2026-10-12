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
#   G  KACHO_HOME_* / KACHO_MONOREPO / GIT_DIR вызывающего → молчание близнеца A'
#   H  `project/` нет, стволы названы KACHO_MONOREPO и лежат рядом с ним
#      (соседи опознаны по origin)                 → находка оси A, не VOID
#   H' тот же мир, у соседа `origin` чужой         → VOID, называет соседа
#
# Мир — только синтетические стволы (ws#815): `KACHO_HOME_<РЕПО>` и
# `KACHO_MONOREPO` у check-01 сильнее `<корень>/project/<имя>`, `GIT_*` сильнее
# `git -C`. Снимаются по префиксу, а не перечнем, — для сборки мира и при каждом
# прогоне check-01; ось H ставит `KACHO_MONOREPO` сама, на своём вызове.
set -uo pipefail

foreign() { compgen -e | command grep -E '^(KACHO_HOME_|KACHO_MONOREPO$|GIT_)'; }
for v in $(foreign); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Окружение — своё: унаследованный `KACHO_HOME_<РЕПО>` сильнее синтетических стволов
# ниже, и проверка судила бы настоящие пары (scripts/lib/proofs.sh).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$here/../lib/proofs.sh"
proof_own_environment
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

# Подпись стволов — HOME песочницы со своим `.gitconfig` (ws#785), без переопределения.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$here/../lib/sandbox-git-home.sh"
sandbox_git_home "$box/home" || { echo "инъекция crossrepo-gate: НЕ ВЫПОЛНИЛОСЬ — корневой подписи нет" >&2; exit 2; }

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
  git -C "$dir" add -A
  sandbox_git -C "$dir" commit -q -m inj
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

run() {
  local strip=() v
  for v in $(foreign); do strip+=(-u "$v"); done
  ( cd "$1" && env "${strip[@]}" DOCS_GATE_ROOT="$1" \
      python3 "$here/check-01-paired-files-are-declared.py" 2>&1 )
}

# run_mono <корень> <KACHO_MONOREPO> — тот же прогон, указатель ставит ось сама.
run_mono() {
  local strip=() v
  for v in $(foreign); do strip+=(-u "$v"); done
  ( cd "$1" && env "${strip[@]}" DOCS_GATE_ROOT="$1" KACHO_MONOREPO="$2" \
      python3 "$here/check-01-paired-files-are-declared.py" 2>&1 )
}

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

# ── G / G' : окружение вызывающего в мир не входит (ws#815) ──────────────────
# Приманка несёт пути всех трёх стволов: какой бы ствол она ни подменила, пара
# появится, и молчание близнеца оси A' сменится находкой.
decoy="$box/decoy"
repo decoy 'own-a.txt=чужое' 'own-b.txt=чужое' 'own-c.txt=чужое'
mv "$box/ws/project/decoy" "$decoy"
ws="$(world 'pairs: []')"
repo kacho  'own-a.txt=своё'
repo kaname 'own-b.txt=своё'
repo corelib 'own-c.txt=своё'
out="$(KACHO_HOME_KACHO="$decoy" KACHO_HOME_KANAME="$decoy" KACHO_HOME_CORELIB="$decoy" run "$ws")"; rc=$?
assert "G  KACHO_HOME_* вызывающего не подменяет стволы" 0 "все 0 пар объявлены" "$out" "$rc"
out="$(KACHO_MONOREPO="$decoy" run "$ws")"; rc=$?
assert "G\" KACHO_MONOREPO вызывающего не подменяет стволы" 0 "все 0 пар объявлены" "$out" "$rc"
out="$(GIT_DIR="$decoy/.git" run "$ws")"; rc=$?
assert "G' GIT_DIR вызывающего не подменяет стволы" 0 "все 0 пар объявлены" "$out" "$rc"

# ── H / H' : project/ нет, стволы названы KACHO_MONOREPO (хук отправки) ──────
# Корень мира — без `project/`: так судит хук, у которого вершина во временной
# копии. Без чтения KACHO_MONOREPO исход был бы VOID (ось F), с ним — находка
# оси A: пара прочитана из стволов рядом с указателем.
far="$box/far"
mono_world() { # <origin соседа kaname>
  rm -rf "$far"; mkdir -p "$far"
  ws="$(world 'pairs: []')"
  repo kacho  'tools/shared.py=одно' 'own-a.txt=своё'
  repo kaname 'tools/shared.py=другое' 'own-b.txt=своё'
  repo corelib 'own-c.txt=своё'
  git -C "$box/ws/project/kaname" remote add origin "$1"
  git -C "$box/ws/project/corelib" remote add origin "git@github.com:PRO-Robotech/corelib.git"
  mv "$box/ws/project/kacho" "$box/ws/project/kaname" "$box/ws/project/corelib" "$far/"
  rmdir "$box/ws/project"
}
mono_world "https://github.com/PRO-Robotech/kaname.git"
out="$(run_mono "$ws" "$far/kacho")"; rc=$?
assert "H  стволы рядом с KACHO_MONOREPO прочитаны — находка, не VOID" 1 "kacho+kaname" "$out" "$rc"

mono_world "https://example.invalid/someone/kaname.git"
out="$(run_mono "$ws" "$far/kacho")"; rc=$?
assert "H' сосед без опознанного origin — VOID, назван" 2 "[VOID]" "$out" "$rc"
assert "H' VOID называет неопознанного соседа" 2 "kaname" "$out" "$rc"

echo "инъекция crossrepo-gate: утверждений $((pass+fail)), пройдено $pass, провалено $fail"
[[ $((pass+fail)) -gt 0 && "$fail" == 0 ]]
