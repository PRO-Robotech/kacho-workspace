#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-07 по четырём осям: новый висячий заголовок, новый висячий
# id, дубль id внутри файла, и зажившая база. Последняя — самоистечение: база не
# может пережить свой предмет.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/address-refs.py
T=.claude/rules/testing-load.md
B=scripts/rules-gate/address-baseline.txt
TO="$(mktemp)"
BO="$(mktemp)"
cp "$T" "$TO"
cp "$B" "$BO"
trap 'cp "$TO" "$T"; cp "$BO" "$B"; rm -f "$TO" "$BO"' EXIT
# Адрес для оси D берётся ИЗ ВЫВОДА САМОГО ГЕЙТА: он обязан УЖЕ резолвиться в
# дереве, иначе проба доказывала бы не «база зажила», а «база тоже висит».
# Одной записи в базе недостаточно: предмет оси — адрес, который И стоит в дереве,
# И резолвится, а в базе числится висячим.
RESOLVABLE="$(python3 "$G" --list 2>/dev/null | awk -F'\t' '$3=="OK"{print $2; exit}')"
fail=0
probe() {
  local out
  out="$(python3 "$G" 2>&1 || true)"
  if grep -qE "$2" <<< "$out"; then
    printf 'ось %s: красное — OK\n' "$1"
  else
    printf 'ось %s: МОЛЧИТ — доказательство не прошло\n' "$1"
    fail=1
  fi
}
printf '\ntesting-load.md §«Раздела с таким именем нет ни в корпусе, ни в архиве»\n' >> "$T"
probe A 'новая поломка адреса'
cp "$TO" "$T"
printf '\ntesting-load.md#no-such-id-exists-anywhere\n' >> "$T"
probe B 'новая поломка адреса'
cp "$TO" "$T"
printf '\ndup-id-probe · императив · ЗАВЕСТИ x · red: признак\ndup-id-probe · императив · ЗАВЕСТИ x · red: признак\n' >> "$T"
probe C 'дубль id'
cp "$TO" "$T"
# ЗАЖИВШАЯ БАЗА: адрес, который резолвится, обязан быть убран из базы.
if [ -z "$RESOLVABLE" ]; then
  printf 'ось D: НЕ ВЫПОЛНЕНА — в дереве нет ни одного резолвящегося адреса, входа нет\n'
else
  printf '%s\n' "$RESOLVABLE" >> "$B"
fi
[ -z "$RESOLVABLE" ] || probe D 'зажил'
cp "$BO" "$B"
if python3 "$G" > /dev/null 2>&1; then
  printf 'ось Z: на целом дереве зелено — OK\n'
else
  printf 'ось Z: КРАСНОЕ — гейт шумит\n'
  fail=1
fi
exit "$fail"
