#!/usr/bin/env bash
# check-10 — хук отправки судит ТО, ЧТО ОТПРАВЛЯЕТСЯ, а не рабочую копию.
#
# git подаёт хуку на stdin по строке на ссылку: `<local ref> <local sha>
# <remote ref> <remote sha>`. До ws#810 хук вход не читал, и исход решала копия:
# `git push origin --delete <ветка>` исполнял все наборы над ней и отказывал на
# незакоммиченной правке, хотя ревизий в отправке нет ни одной.
#
# ЧТО ТРЕБУЕТСЯ ОТ ХУКА (песочница: свой репозиторий, набор-заглушка пишет факт
# вызова и краснеет, когда в судимом дереве `state.txt` = `red`):
#
#   вход — одна строка удаления, копия красная → 0, заглушка НЕ вызвана, и
#                          завершающая строка ОТЛИЧНА от строки чистого прогона;
#   близнец: удаление и красная вершина → заглушка вызвана, отправка остановлена;
#   пустой вход            → заглушка вызвана (пустое — не «только удаления»);
#   копия красная, уезжает зелёная вершина → 0; близнец: копия зелёная, уезжает
#                          красная → отказ с именем ссылки (ws#811: судится дерево
#                          вершины, незакоммиченное в исход не входит);
#   HEAD = wip/x, уезжает красная не-черновая → отказ; близнец: уезжает `wip/y` —
#                          заглушка не вызвана (черновик — по отправляемой ссылке).
#
# ПРЕДПОСЫЛКА (исход VOID): вызывающий есть, и на чистой копии с зелёной вершиной
# он отвечает 0, вызвав заглушку. Иначе остальные пробы на нём недоказательны.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-10-push-hook-judges-what-is-pushed"
CALLER="scripts/hooks/pre-push"
Z="0000000000000000000000000000000000000000"

mapfile -t CALLERS < <(tooling_gate_files "$WS" "$CALLER")
if [ "${#CALLERS[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "вызывающего $CALLER в дереве нет — проверять нечего"
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pgit() { git -c user.email=probe@invalid -c user.name=probe -c core.hooksPath=/dev/null "$@"; }

# mkbox <вызывающий> — печатает путь песочницы: `main` = G (state.txt green),
# `red-lane` = R (red), HEAD = main, копия чистая. Факт вызова заглушки пишется
# в `<песочница>.calls` — вне дерева, чтобы не попасть ни в одну ревизию.
mkbox() {
    local dir
    dir="$(mktemp -d "$TMP/b.XXXXXX")"
    mkdir -p "$dir/scripts/hooks" "$dir/scripts/probe"
    cp "$WS/$1" "$dir/scripts/hooks/pre-push"
    chmod +x "$dir/scripts/hooks/pre-push"
    # shellcheck disable=SC2016  # тело заглушки раскрывается при её вызове
    printf '#!/usr/bin/env bash\nr="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"\necho "$r" >> %q\n[ "$(cat "$r/state.txt")" = red ] && { echo "probe: красное"; exit 1; }\nexit 0\n' \
        "$dir.calls" > "$dir/scripts/probe/run-all.sh"
    : > "$dir.calls"
    echo green > "$dir/state.txt"
    pgit -C "$dir" init -q -b main
    pgit -C "$dir" add -A
    pgit -C "$dir" commit -q -m G
    pgit -C "$dir" checkout -q -b red-lane
    echo red > "$dir/state.txt"
    pgit -C "$dir" commit -q -am R
    pgit -C "$dir" checkout -q main
    printf '%s' "$dir"
}

# push <песочница> <вход> — «<код>|<вызовов заглушки>|<завершающая строка>»;
# полный вывод — в `<песочница>.out`.
push() {
    local dir="$1" input="$2" code
    : > "$dir.calls"
    (
        cd "$dir" || exit 111
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
              KACHO_MONOREPO KACHO_SKIP_PREPUSH
        printf '%s' "$input" | bash ./scripts/hooks/pre-push origin "$dir.remote"
    ) > "$dir.out" 2>&1 && code=0 || code=$?
    printf '%s|%s|%s\n' "$code" "$(grep -c . "$dir.calls" || true)" \
        "$(grep -v '^[[:space:]]*$' "$dir.out" | tail -1)"
}

rc()    { printf '%s' "${1%%|*}"; }
calls() { local r="${1#*|}"; printf '%s' "${r%%|*}"; }
tail_of() { local r="${1#*|}"; printf '%s' "${r#*|}"; }

findings=0
probes=0
examined=0
bad() { tooling_gate_fail "$NAME" "$1"; findings=$((findings + 1)); }

for caller in "${CALLERS[@]}"; do
    box="$(mkbox "$caller")"
    G="$(git -C "$box" rev-parse main)"
    R="$(git -C "$box" rev-parse red-lane)"

    green="$(push "$box" "refs/heads/main $G refs/heads/main $Z"$'\n')"
    probes=$((probes + 1))
    if [ "$(rc "$green")" != 0 ] || [ "$(calls "$green")" -eq 0 ]; then
        tooling_gate_void "$NAME" \
            "$caller — чистая копия, зелёная вершина: код $(rc "$green"), вызовов $(calls "$green"); остальные пробы на нём недоказательны"
        exit 2
    fi
    examined=$((examined + 1))

    echo red > "$box/state.txt"   # копия красная НЕЗАКОММИЧЕННОЙ правкой

    r="$(push "$box" "(delete) $Z refs/heads/gone $G"$'\n')"; probes=$((probes + 1))
    if [ "$(calls "$r")" -ne 0 ] || [ "$(rc "$r")" != 0 ]; then
        bad "$caller — вход из одной строки удаления: код $(rc "$r"), вызовов набора $(calls "$r") вместо 0/0 — судилась копия, а не отправка"
    elif [ "$(tail_of "$r")" = "$(tail_of "$green")" ]; then
        bad "$caller — удаление без прогона закончилось строкой чистого («$(tail_of "$green")»): «не проверялось» подано как «зелено»"
    fi

    r="$(push "$box" "(delete) $Z refs/heads/gone $G"$'\n'"refs/heads/red-lane $R refs/heads/red-lane $Z"$'\n')"
    probes=$((probes + 1))
    if [ "$(calls "$r")" -eq 0 ] || [ "$(rc "$r")" != 1 ]; then
        bad "$caller — удаление рядом с красной вершиной: код $(rc "$r"), вызовов $(calls "$r") — удаление стало маской для отправки"
    fi

    r="$(push "$box" "")"; probes=$((probes + 1))
    if [ "$(calls "$r")" -eq 0 ]; then
        bad "$caller — пустой вход: наборы не вызваны — пустое принято за «только удаления»"
    fi

    r="$(push "$box" "refs/heads/main $G refs/heads/green-lane $Z"$'\n')"; probes=$((probes + 1))
    if [ "$(rc "$r")" != 0 ]; then
        bad "$caller — копия красная незакоммиченным, уезжает зелёная вершина: код $(rc "$r") вместо 0 — судилась копия"
    fi

    pgit -C "$box" checkout -q -- state.txt   # копия снова чистая и зелёная
    r="$(push "$box" "refs/heads/red-lane $R refs/heads/red-lane $Z"$'\n')"; probes=$((probes + 1))
    if [ "$(rc "$r")" != 1 ]; then
        bad "$caller — копия зелёная, уезжает красная вершина: код $(rc "$r") вместо 1 — красное уехало как зелёное"
    elif ! grep -q 'red-lane' "$box.out"; then
        bad "$caller — отказ по красной вершине не назвал ссылку refs/heads/red-lane"
    fi

    r="$(push "$box" "refs/heads/red-lane $R refs/heads/wip/y $Z"$'\n')"; probes=$((probes + 1))
    if [ "$(calls "$r")" -ne 0 ] || [ "$(rc "$r")" != 0 ]; then
        bad "$caller — уезжает черновик wip/y: код $(rc "$r"), вызовов $(calls "$r") вместо 0/0 — черновик взят не по отправляемой ссылке"
    fi

    pgit -C "$box" checkout -q -b wip/x
    r="$(push "$box" "refs/heads/red-lane $R refs/heads/red-lane $Z"$'\n')"; probes=$((probes + 1))
    if [ "$(rc "$r")" != 1 ]; then
        bad "$caller — HEAD = wip/x, уезжает красная не-черновая вершина: код $(rc "$r") вместо 1 — черновик взят по HEAD"
    fi
done

tooling_gate_census "$NAME: вызывающих осмотрено $examined, проб $probes"

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings"
    exit 1
fi

tooling_gate_pass "$NAME" "у всех $examined вызывающих исход решает вход отправки: удаление не судит копию, судится дерево вершины, черновик — по отправляемой ссылке"
