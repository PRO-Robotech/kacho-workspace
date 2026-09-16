#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: Apache-2.0
#
# inject-05.sh — доказательство способности check-05 упасть И СМОЛЧАТЬ.
#
# Инъекция меняет ОДИН факт против законного близнеца: объявленный в ведомости
# вердикт. Дерево продукта синтетическое — своё, одноразовое, со своим `origin/main`:
# судить чужую рабочую копию проверка не вправе, а здесь она ещё и должна быть
# управляемой.
#
# Оси:
#   A  объявленный вердикт НЕ воспроизводится шапкой  → код 1, запись названа
#   A' законный близнец: воспроизводится              → код 0
#   B  ревизии приёмки в этом дереве нет              → «не выполнилось», не находка
#   C  ведомость пуста                                → код 0 (цель, а не поломка)
#   D  дерева продукта нет вовсе                      → код 2 (VOID)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$here/../.." && pwd)"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

pass=0
fail=0

# Ревизия и приёмка берутся ЖИВЫЕ — из этого же дерева: синтетическая шапка
# доказывала бы, что распознаватель читает синтетику, а не наши документы.
acc="$(git -C "$ws_root" ls-tree -r --name-only HEAD docs/specs \
        | grep -E 'acceptance\.md$' | head -1 | sed 's|docs/specs/||')"
rev="$(git -C "$ws_root" rev-parse --short HEAD)"
real="$(git -C "$ws_root" show "HEAD:docs/specs/$acc" \
        | python3 "$here/verdict.py" - 2>/dev/null)"
if [[ -z "$acc" || -z "$real" ]]; then
  echo "НЕ ВЫПОЛНИЛОСЬ: живой приёмки с читаемым вердиктом не нашлось — инъекции не на чем" >&2
  exit 3
fi
echo "предмет инъекции: $acc @ $rev, вердикт шапки $real"

# ledger_repo <вердикт-в-ведомости> <ревизия> — синтетическое дерево продукта.
ledger_repo() {
  local verdict=$1 revision=$2 dir="$box/prod-$RANDOM"
  mkdir -p "$dir/docs"
  if [[ "$verdict" == "ПУСТО" ]]; then
    printf 'entries: []\n' > "$dir/docs/acceptance-ledger.yaml"
  else
    cat > "$dir/docs/acceptance-ledger.yaml" <<YAML
entries:
  - acceptance: $acc
    prefix: INJ
    verdict: $verdict
    verdict_dated: "2026-09-16"
    workspace_revision: $revision
YAML
  fi
  git -C "$dir" init -q
  git -C "$dir" -c user.email=inj@example.invalid -c user.name=inj add -A
  git -C "$dir" -c user.email=inj@example.invalid -c user.name=inj commit -q -m inj
  git -C "$dir" update-ref refs/remotes/origin/main "$(git -C "$dir" rev-parse HEAD)"
  echo "$dir"
}

run() { KACHO_MONOREPO="$1" python3 "$here/check-05-ledger-verdict-reproduces.py" 2>&1; }

assert() { # <ось> <ожидаемый код> <ожидаемая подстрока> <вывод> <код>
  local axis=$1 want=$2 needle=$3 out=$4 rc=$5
  if [[ "$rc" == "$want" ]] && grep -qF -- "$needle" <<<"$out"; then
    echo "  ok   $axis"; pass=$((pass+1))
  else
    echo "  FAIL $axis: код $rc (ожидался $want); искали «$needle»"
    printf '%s\n' "       | ${out//$'\n'/$'\n'       | }"
    fail=$((fail+1))
  fi
}

# A — дефект: ведомость объявляет не то, что стоит в шапке.
other=APPROVED; [[ "$real" == "APPROVED" ]] && other=DRAFT
out="$(run "$(ledger_repo "$other" "$rev")")"; rc=$?
assert "A  объявленный вердикт не воспроизводится" 1 "не воспроизводит вердикт" "$out" "$rc"
assert "A  находка называет запись" 1 "$acc" "$out" "$rc"

# A' — законный близнец: тот же файл, вердикт объявлен верно.
out="$(run "$(ledger_repo "$real" "$rev")")"; rc=$?
assert "A' законный близнец молчит" 0 "вердикт воспроизведён у всех" "$out" "$rc"

# B — ревизии нет: третья категория, не находка.
out="$(run "$(ledger_repo "$real" 0000000000000000000000000000000000000000)")"; rc=$?
assert "B  ревизии нет — не выполнилось" 2 "НЕ ВЫПОЛНИЛОСЬ" "$out" "$rc"
assert "B  третья категория не находка" 2 "не выполнилось у 1" "$out" "$rc"

# C — пустая ведомость: цель, а не поломка.
out="$(run "$(ledger_repo ПУСТО "$rev")")"; rc=$?
assert "C  пустая ведомость проходит" 0 "записей ведомости нет" "$out" "$rc"

# D — дерева продукта нет вовсе.
out="$(KACHO_MONOREPO=/nonexistent-tree-for-injection python3 "$here/check-05-ledger-verdict-reproduces.py" 2>&1)"; rc=$?
assert "D  дерева продукта нет — VOID" 2 "[VOID]" "$out" "$rc"

echo "инъекция check-05: утверждений $((pass+fail)), пройдено $pass, провалено $fail"
[[ "$fail" == 0 ]]
