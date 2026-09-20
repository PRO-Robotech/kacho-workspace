#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-08: гейт СПОСОБЕН дать красное на каждой из трёх осей,
# и молчит на целом дереве. Проба, не умеющая покраснеть, ничего не судит.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/check-08-rule-frontmatter.sh
T=.claude/rules/00-kacho-core.md
ORIG="$(mktemp)"
cp "$T" "$ORIG"
trap 'cp "$ORIG" "$T"; rm -f "$ORIG"' EXIT
fail=0
# ВЫВОД СНИМАЕТСЯ ДО ГРЕПА. Гейт по построению выходит с 1, и под `pipefail`
# конвейер `"$G" | grep` неуспешен даже когда grep НАШЁЛ строку — проба обвиняла
# бы гейт в своей собственной ошибке. Тот же класс уже ловили в skills-gate.
probe() {
  local out
  out="$("$G" 2>&1 || true)"
  if grep -q "$2" <<< "$out"; then
    printf 'ось %s: красное — OK\n' "$1"
  else
    printf 'ось %s: МОЛЧИТ — доказательство не прошло\n' "$1"
    fail=1
  fi
}
sed -i '1,4d' "$T"
probe A 'нет frontmatter'
cp "$ORIG" "$T"
sed -i '2s/.*/name: rule-wrong/' "$T"
probe B 'нет строки'
cp "$ORIG" "$T"
sed -i '3s/.*/description:/' "$T"
probe C 'description пуст'
cp "$ORIG" "$T"
if "$G" > /dev/null 2>&1; then
  printf 'ось Z: на целом дереве зелено — OK\n'
else
  printf 'ось Z: КРАСНОЕ — гейт шумит\n'
  fail=1
fi
exit "$fail"
