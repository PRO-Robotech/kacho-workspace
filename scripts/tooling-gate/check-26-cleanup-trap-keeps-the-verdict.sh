#!/usr/bin/env bash
# check-26 — ловушка снятия временного каталога не решает исход проверки (ws#1189).
#
# Признак: check-25 напечатал `[PASS]` и вышел кодом 1 — его ловушка
# `trap 'rm -rf "$TMP"' EXIT` под `set -e` отдала код неудавшегося `rm`
# (`rm: cannot remove …/box/.git: Directory not empty`, пока фоновое `git gc`
# писало в песочницу). Исход проверки — её вердикт; уборка за собой вердикта не
# выносит: ни красного там, где проверка зелёна, ни зелёного там, где она красна.
#
# ПРЕДМЕТ — каждая строка `trap '…rm -rf "$ПЕРЕМЕННАЯ"…' EXIT` в начале строки
# проверок набора (`scripts/tooling-gate/*.sh`) и проб (`scripts/*-inject.sh`).
# Перечень выводится из индекса git обходом, не выписывается. Строка в комментарии
# или в строковом литерале (не первая на строке) не ловушка и не судится.
#
# ПОВЕДЕНЧЕСКАЯ: сама строка ловушки — как написана в файле — исполняется в
# `bash -c` под `set -euo pipefail` (худший из режимов проверок) на каталоге,
# который снять нельзя (функция `rm` отказывает, как отказал настоящий), и на
# каталоге, который снимается. Требуется:
#   • снять не удалось, проверка вышла 0 → код 0 и предупреждение с именем
#     каталога в стандартной ошибке;
#   • снять не удалось, проверка вышла N → код N (не 1 от `rm`);
#   • снять удалось, проверка вышла 0 и N → код сохранён, каталога нет, молчание.
#
# Вторая половина: песочница git проб гасит фоновое обслуживание (`gc.auto`,
# `gc.autoDetach`, `maintenance.auto`, `receive.autogc`) — иначе снимаемый `.git`
# растёт под `rm -rf`, ради чего ловушка и осталась без права решать исход.
#
# ПРЕДПОСЫЛКА (VOID): ловушек в объёме ноль — судить нечего; голая форма
# `trap 'rm -rf "$TMP"' EXIT` в том же стенде вышла 1 — иначе стенд не слышит
# класс, и «зелёное» на настоящих строках ничего бы не значило.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-26-cleanup-trap-keeps-the-verdict"

TMP="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$TMP" 2>/dev/null || rm -rf "$TMP" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $TMP не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT

# scenario <тело ловушки> <переменная> <снимается: yes|no> <код проверки> — печатает
# «код|стандартная ошибка» (стандартная ошибка в одну строку); каталог — свой.
scenario() {
    local body="$1" var="$2" removable="$3" want="$4" victim script rc err
    victim="$(mktemp -d "$TMP/victim.XXXXXX")"
    mkdir -p "$victim/.git"; : > "$victim/.git/f"
    script="set -euo pipefail"$'\n'
    if [ "$removable" = no ]; then
        script+="rm() { echo \"rm: cannot remove '\${2:-}/.git': Directory not empty\" >&2; return 1; }"$'\n'
    fi
    script+="$var='$victim'"$'\n'"trap '$body' EXIT"$'\n'"exit $want"
    rc=0; err="$(bash -c "$script" 2>&1 >/dev/null)" || rc=$?
    printf '%s|%s|%s' "$rc" "${err//$'\n'/ }" "$([ -e "$victim" ] && echo present || echo gone)"
    command rm -rf "$victim"
}

# Голая форма — контроль стенда: под `set -e` обязана выйти 1, а не 0.
bare_out="$(scenario "rm -rf \"\$V\"" V no 0)"
bare_rc="${bare_out%%|*}"
if [ "$bare_rc" != 1 ]; then
    tooling_gate_void "$NAME" "стенд не слышит класс: голая ловушка rm -rf при неснимаемом каталоге вышла $bare_rc вместо 1 — судить настоящие строки нечем"
    exit 2
fi

sites=0
scenarios=0
findings=0
fail() { findings=$((findings + 1)); tooling_gate_fail "$NAME" "$1"; }

# Вторая половина класса: причина сбоя снятия — фоновое обслуживание git
# (`gc --auto`, `maintenance run --auto`, приёмник отправки), пишущее в `.git`
# песочницы, пока её снимают. Песочница проб (`scripts/lib/sandbox-git-home.sh`)
# обязана его гасить; читается библиотека СУДИМОГО дерева, не этого скрипта.
LIB="$WS/scripts/lib/sandbox-git-home.sh"
if [ ! -f "$LIB" ]; then
    tooling_gate_void "$NAME" "библиотеки песочницы git нет в дереве ($LIB) — гасить обслуживание нечему"
    exit 2
fi
# Библиотека читается подоболочкой: судимое дерево — не то, что подключил бы этот
# скрипт по своему пути, а подключение по переменной набор suites-gate не разрешает.
sbx() { bash -c '. "$1"; shift; "$@"' _ "$LIB" "$@"; }
rc=0; sbx sandbox_git_home "$TMP/home" 2>/dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
    tooling_gate_void "$NAME" "песочница git не родилась (код $rc: корневой подписи нет либо библиотека отказала) — настройки обслуживания судить не на чем"
    exit 2
fi
cfg=0
for pair in gc.auto=0 gc.autoDetach=false maintenance.auto=false receive.autogc=false; do
    cfg=$((cfg + 1))
    got="$(bash -c '. "$1"; SANDBOX_GIT_HOME="$2"; sandbox_git config --global --get "$3"' _ "$LIB" "$TMP/home" "${pair%%=*}" 2>/dev/null || true)"
    [ "$got" = "${pair#*=}" ] || fail "scripts/lib/sandbox-git-home.sh — песочница git не гасит фоновое обслуживание: ${pair%%=*} = «$got», ждали «${pair#*=}»"
done

while IFS= read -r f; do
    [[ "$f" =~ ^scripts/tooling-gate/[^/]+\.sh$ || "$f" =~ ^scripts/[^/]+-inject\.sh$ ]] || continue
    [ -f "$WS/$f" ] || continue
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        ln="${hit%%:*}"; line="${hit#*:}"
        sites=$((sites + 1))
        if ! [[ "$line" =~ ^[[:space:]]*trap\ \'(.*)\'\ EXIT[[:space:]]*$ ]]; then
            fail "$f:$ln — ловушка снятия не в форме trap '…' EXIT: судить нечем"
            continue
        fi
        body="${BASH_REMATCH[1]}"
        if ! [[ "$body" =~ rm\ -rf\ \"\$\{?([A-Za-z_][A-Za-z_0-9]*)\}?\" ]]; then
            fail "$f:$ln — в ловушке нет rm -rf \"\$ПЕРЕМЕННАЯ\": каталог для проверки не выводится"
            continue
        fi
        var="${BASH_REMATCH[1]}"
        victim_name="$f:$ln"
        # 1. снять нельзя, проверка зелёна.
        scenarios=$((scenarios + 1)); res="$(scenario "$body" "$var" no 0)"
        rc="${res%%|*}"; rest="${res#*|}"; err="${rest%|*}"
        [ "$rc" = 0 ] || fail "$victim_name — снять каталог нельзя, проверка вышла 0, ловушка отдала код $rc: исход зависит от уборки"
        grep -qF 'ПРЕДУПРЕЖДЕНИЕ' <<<"$err" || fail "$victim_name — снять каталог нельзя, а предупреждения нет: сбой снятия молчит"
        # 2. снять нельзя, проверка красна кодом 3.
        scenarios=$((scenarios + 1)); res="$(scenario "$body" "$var" no 3)"; rc="${res%%|*}"
        [ "$rc" = 3 ] || fail "$victim_name — снять каталог нельзя, проверка вышла 3, ловушка отдала код $rc: код проверки потерян"
        # 3. снять можно: код сохранён, каталога нет, тихо.
        for want in 0 5; do
            scenarios=$((scenarios + 1)); res="$(scenario "$body" "$var" yes "$want")"
            rc="${res%%|*}"; rest="${res#*|}"; err="${rest%|*}"; state="${res##*|}"
            [ "$rc" = "$want" ] || fail "$victim_name — каталог снимается, проверка вышла $want, ловушка отдала код $rc"
            [ "$state" = gone ] || fail "$victim_name — проверка вышла $want, а каталог остался: ловушка не снимает"
            [ -z "$err" ] || fail "$victim_name — каталог снят, а в стандартной ошибке «$err»: лишний шум на штатном исходе"
        done
    done < <(grep -nE '^[[:space:]]*trap .*rm -rf' "$WS/$f" || true)
done < <(tooling_gate_files "$WS" 'scripts/*.sh')

if [ "$sites" -eq 0 ]; then
    tooling_gate_void "$NAME" "ловушек снятия в проверках набора и пробах нет — судить нечего"
    exit 2
fi
tooling_gate_census "$NAME: ловушек снятия осмотрено $sites, сценариев исполнено $scenarios (снять нельзя — код 0 и N; снять можно — 0 и N); настроек обслуживания песочницы git осмотрено $cfg"
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "находок: $findings"
    exit 1
fi
tooling_gate_pass "$NAME" "исход проверки не зависит от снятия её временного каталога: сбой снятия — предупреждение, код сохранён; ловушек $sites"
