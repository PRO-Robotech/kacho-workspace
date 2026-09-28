#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-03 — хук отправки ВЫВОДИТ соседние дома из канонического клона, и
# вердикт из рабочей копии совпадает с вердиктом из канонического клона ПО
# ЧИСЛУ исполненного, а не только по коду (ws#747).
#
# ЗАЧЕМ. Из копии `tmp/<полоса>` часть наборов оставалась БЕЗ ПРЕДМЕТА при
# каждой отправке: соседние клоны лежат у канонического клона, а выводилось
# только дерево продукта. «Без предмета» не блокирует отправку и печатается
# числом, которое легко прочесть как зелёное. Код возврата предикатом не
# является: два прогона совпадут кодом и при двух недосуженных наборах.
#
# ЧТО ТРЕБУЕТСЯ — поведением, на ОДНОМ содержимом дерева:
#   канонический клон с `project/alpha` и `project/beta` (рабочие копии git) и
#   его worktree на той же ревизии; в дереве — набор-заглушка, который отвечает
#   2 (VOID), если хотя бы одного дома ему не подали (переменной либо рядом с
#   собой), и 0, если оба есть — ровно как настоящие наборы;
#   A  из канонического клона — без предмета 0;
#   B  из копии — без предмета 0, и каждый выведенный дом напечатан строкой;
#   C  строки «исполнено наборов» обеих половин СОВПАДАЮТ;
#   D  у канонического клона дома beta нет — из копии честное «без предмета 1»:
#      вывод не выдумывает дом, которого нет;
#   E  дом, заданный снаружи, не перебивается.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
NAME="check-03-neighbour-homes-are-derived"

[ -f "$PG_SUBJECT/scripts/hooks/pre-push" ] || { pg_void "$NAME — хука scripts/hooks/pre-push нет"; exit 2; }

pg_hermetic
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

probes=0; failed=0
probe() {
    probes=$((probes + 1))
    if [ "$1" = да ]; then pg_pass "$NAME — $2"; else failed=$((failed + 1)); pg_fail "$NAME — $2${3:+: $3}"; fi
}

box="$TMP/box"
ws="$(pg_sandbox "$box")" || { pg_void "$NAME — песочница не собралась"; exit 2; }
cat > "$ws/scripts/stub-gate/run-all.sh" <<'STUB'
#!/usr/bin/env bash
# Заглушка набора, которому нужны соседние дома, — как настоящие: переменная,
# иначе `project/<имя>` рядом с корнем дерева; нет хотя бы одного — VOID.
root="$(git rev-parse --show-toplevel)"
for n in alpha beta; do
    v="KACHO_HOME_${n^^}"; h="${!v:-$root/project/$n}"
    [ -e "$h/.git" ] || { echo "[VOID] stub-gate — дома $n нет ($h)"; exit 2; }
done
echo "stub-gate: рассмотрено проверок 1; пройдено 1"
exit 0
STUB
git -C "$ws" add -A && git -C "$ws" commit -q -m "набор, которому нужны дома"
HOMES=(alpha beta)
for n in "${HOMES[@]}"; do git init -q "$ws/project/$n" || { pg_void "$NAME — дом $n не завёлся"; exit 2; }; done
git -C "$ws" worktree add -q "$box/lane" -b lane HEAD 2>/dev/null ||
    { pg_void "$NAME — рабочая копия-worktree не завелась"; exit 2; }

wsp="$(cd "$ws" && pwd -P)"  # хук печатает путь канонического клона разрешённым
run_from() { ( cd "$1" && bash scripts/hooks/pre-push </dev/null 2>&1 ); }
tally() { printf '%s\n' "$1" | grep -E '^pre-push: исполнено наборов' || true; }

out_c="$(run_from "$ws")"
probe "$(pg_has "$out_c" "без предмета 0" && echo да || echo нет)" "A из канонического клона — без предмета 0" "вывод: $out_c"
out_l="$(run_from "$box/lane")"
probe "$(pg_has "$out_l" "без предмета 0" && echo да || echo нет)" "B из копии — без предмета 0" "вывод: $out_l"
probe "$(pg_has "$out_l" "дом alpha выведен — $wsp/project/alpha" "дом beta выведен — $wsp/project/beta" && echo да || echo нет)" \
    "B выведенные дома напечатаны строкой" "вывод: $out_l"
t_c="$(tally "$out_c")"; t_l="$(tally "$out_l")"
probe "$( [ -n "$t_c" ] && [ "$t_c" = "$t_l" ] && echo да || echo нет)" \
    "C обе половины совпадают по числу исполненного: «$t_c»" "канонический «$t_c», копия «$t_l»"

rm -rf "$ws/project/beta"
out_l="$(run_from "$box/lane")"
probe "$(pg_has "$out_l" "без предмета 1" && ! pg_has "$out_l" "дом beta выведен" && echo да || echo нет)" \
    "D дома beta у канонического клона нет — из копии честное «без предмета 1», дом не выдуман" "вывод: $out_l"

out_l="$( cd "$box/lane" && KACHO_HOME_ALPHA=/elsewhere/alpha bash scripts/hooks/pre-push </dev/null 2>&1 )"
probe "$(pg_has "$out_l" "дом alpha задан снаружи — KACHO_HOME_ALPHA=/elsewhere/alpha" && echo да || echo нет)" \
    "E дом, заданный снаружи, не перебит" "вывод: $out_l"

pg_census "$NAME: песочниц $(pg_sandboxes "$TMP"), рабочих копий-worktree $(git -C "$ws" worktree list --porcelain | grep -c '^worktree ' ) (с каноническим), домов ${#HOMES[@]}; проб исполнено $probes, провалено $failed"
if [ "$failed" -gt 0 ]; then
    pg_fail "$NAME — проб с находкой: $failed"
    exit 1
fi
pg_pass "$NAME — дома выводятся из канонического клона; вердикт копии равен вердикту канонического по числу исполненного"
