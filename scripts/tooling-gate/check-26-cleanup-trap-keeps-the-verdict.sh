#!/usr/bin/env bash
# check-26 — ловушка снятия временного каталога не решает исход проверки (ws#1189).
#
# Признак: check-25 напечатал `[PASS]` и вышел кодом 1 — его ловушка
# `trap 'rm -rf "$TMP"' EXIT` под `set -e` отдала код неудавшегося `rm`
# (`rm: cannot remove …/box/.git: Directory not empty`, пока фоновое `git gc`
# писало в песочницу). Исход проверки — её вердикт; уборка за собой вердикта не
# выносит: ни красного там, где проверка зелёна, ни зелёного там, где она красна.
#
# ПРЕДМЕТ — каждая строка `trap` в начале строки проверок набора
# (`scripts/tooling-gate/*.sh`) и проб (`scripts/*-inject.sh`), вне heredoc и
# комментария. Перечень файлов выводится из индекса git обходом. Единица разбора —
# ОПЕРАТОР (`cleanup_trap_statements.py`): многострочная `trap '…' EXIT` видна по
# открывающей строке, `trap имя EXIT` разбирается через функцию `имя` из файла,
# `EXIT INT TERM` — та же ловушка. Ловушка на EXIT с `rm`, форму которой нельзя
# вывести (нет `rm -rf "$ПЕРЕМЕННАЯ"`, функции нет в файле), — находка «не в форме»,
# а не молчание; EXIT-ловушка без `rm`, ловушка не на EXIT и сброс — не уборка и
# только считаются. Строка в комментарии, в heredoc-фикстуре и в строковом литерале
# не первая на строке ловушкой не является.
#
# ПОВЕДЕНЧЕСКАЯ: текст оператора — как написан в файле — исполняется в `bash -c`
# под `set -euo pipefail` (худший из режимов проверок) на каталоге, который снять
# нельзя (функция `rm` отказывает, как отказал настоящий, и о пути молчит), и на
# каталоге, который снимается. Требуется:
#   • снять не удалось, проверка вышла 0 → код 0, а в стандартной ошибке — ПУТЬ
#     каталога (`grep -F`); слово «предупреждение» само по себе не довод;
#   • снять не удалось, проверка вышла N → код N (не 1 от `rm`), путь назван;
#   • снять удалось, проверка вышла 0 и N → код сохранён, каталога нет, молчание.
#
# Вторая половина: песочница git проб (`gc.auto`, `gc.autoDetach`,
# `maintenance.auto`, `receive.autogc`) гасит фоновое обслуживание — иначе
# снимаемый `.git` растёт под `rm -rf`, ради чего ловушка и осталась без права
# решать исход.
#
# ПРЕДПОСЫЛКА (VOID): судимых ловушек в объёме ноль; голая форма
# `trap 'rm -rf "$TMP"' EXIT` в том же стенде вышла 1 — иначе стенд не слышит
# класс, и «зелёное» на настоящих строках ничего бы не значило.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-26-cleanup-trap-keeps-the-verdict"
FORMS="$(dirname "${BASH_SOURCE[0]}")/cleanup_trap_statements.py"

TMP="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$TMP" 2>/dev/null || rm -rf "$TMP" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $TMP не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT

# scenario <файл оператора> <переменные через запятую> <снимается: yes|no> <код проверки>
# — печатает «код|стандартная ошибка в одну строку|путь первой жертвы|след»;
# жертвы — свои каталоги с непустым `.git`, имена переменных задают переменные.
scenario() {
    local stmt="$1" vars="$2" removable="$3" want="$4" script v first="" victim rc err state
    script="set -euo pipefail"$'\n'
    if [ "$removable" = no ]; then
        script+="rm() { echo \"rm: cannot remove: Directory not empty\" >&2; return 1; }"$'\n'
    fi
    local IFS=,
    for v in $vars; do
        victim="$(mktemp -d "$TMP/victim.XXXXXX")"
        mkdir -p "$victim/.git"; : > "$victim/.git/f"
        [ -n "$first" ] || first="$victim"
        script+="$v='$victim'"$'\n'
    done
    script+="$(cat "$stmt")"$'\n'"exit $want"
    rc=0; err="$(bash -c "$script" 2>&1 >/dev/null)" || rc=$?
    state="$([ -e "$first" ] && echo present || echo gone)"
    printf '%s|%s|%s|%s' "$rc" "${err//$'\n'/ }" "$first" "$state"
    command rm -rf "$TMP"/victim.*
}

# Голая форма — контроль стенда: под `set -e` обязана выйти 1, а не 0.
printf '%s\n' "trap 'rm -rf \"\$V\"' EXIT" > "$TMP/bare.sh"
bare_out="$(scenario "$TMP/bare.sh" V no 0)"
bare_rc="${bare_out%%|*}"
if [ "$bare_rc" != 1 ]; then
    tooling_gate_void "$NAME" "стенд не слышит класс: голая ловушка rm -rf при неснимаемом каталоге вышла $bare_rc вместо 1 — судить настоящие строки нечем"
    exit 2
fi

judged=0
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

files=()
while IFS= read -r f; do
    [[ "$f" =~ ^scripts/tooling-gate/[^/]+\.sh$ || "$f" =~ ^scripts/[^/]+-inject\.sh$ ]] || continue
    [ -f "$WS/$f" ] || continue
    files+=("$f")
done < <(tooling_gate_files "$WS" 'scripts/*.sh')
if [ "${#files[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "в индексе нет ни проверок набора, ни проб scripts/*-inject.sh — судить нечего"
    exit 2
fi
if ! python3 "$FORMS" "$WS" "$TMP/stmts" "${files[@]}"; then
    tooling_gate_void "$NAME" "перепись ловушек не выполнилась (cleanup_trap_statements.py вышел с отказом)"
    exit 2
fi

starts=0; others=0; n_single=0; n_multi=0; n_func=0
while IFS=$'\t' read -r n f ln kind form detail; do
    starts=$((starts + 1))
    case "$kind" in
        other) others=$((others + 1)); continue ;;
        unknown) fail "$f:$ln — ловушка снятия не в форме: $detail"; continue ;;
    esac
    judged=$((judged + 1))
    case "$form" in single) n_single=$((n_single + 1)) ;; multi) n_multi=$((n_multi + 1)) ;; func) n_func=$((n_func + 1)) ;; esac
    at="$f:$ln"
    stmt="$TMP/stmts/$n.sh"
    # 1. снять нельзя, проверка зелёна.
    scenarios=$((scenarios + 1)); res="$(scenario "$stmt" "$detail" no 0)"
    rc="${res%%|*}"; rest="${res#*|}"; err="${rest%%|*}"; rest="${rest#*|}"; victim="${rest%%|*}"
    [ "$rc" = 0 ] || fail "$at — снять каталог нельзя, проверка вышла 0, ловушка отдала код $rc: исход зависит от уборки"
    grep -qF -- "$victim" <<<"$err" || fail "$at — снять каталог нельзя, а предупреждения с путём каталога в стандартной ошибке нет: сбой снятия молчит либо не называет каталог"
    # 2. снять нельзя, проверка красна кодом 3.
    scenarios=$((scenarios + 1)); res="$(scenario "$stmt" "$detail" no 3)"; rc="${res%%|*}"
    [ "$rc" = 3 ] || fail "$at — снять каталог нельзя, проверка вышла 3, ловушка отдала код $rc: код проверки потерян"
    # 3. снять можно: код сохранён, каталога нет, тихо.
    for want in 0 5; do
        scenarios=$((scenarios + 1)); res="$(scenario "$stmt" "$detail" yes "$want")"
        rc="${res%%|*}"; rest="${res#*|}"; err="${rest%%|*}"; state="${res##*|}"
        [ "$rc" = "$want" ] || fail "$at — каталог снимается, проверка вышла $want, ловушка отдала код $rc"
        [ "$state" = gone ] || fail "$at — проверка вышла $want, а каталог остался: ловушка не снимает"
        [ -z "$err" ] || fail "$at — каталог снят, а в стандартной ошибке «$err»: лишний шум на штатном исходе"
    done
done < "$TMP/stmts/index.tsv"

if [ "$judged" -eq 0 ]; then
    tooling_gate_void "$NAME" "судимых ловушек снятия в проверках набора и пробах нет — судить нечего"
    exit 2
fi
tooling_gate_census "$NAME: строк trap осмотрено $starts, ловушек снятия судимо $judged (однострочных $n_single, многострочных $n_multi, через функцию $n_func), не уборка и только считаются $others; сценариев исполнено $scenarios; настроек обслуживания песочницы git осмотрено $cfg"
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "находок: $findings"
    exit 1
fi
tooling_gate_pass "$NAME" "исход проверки не зависит от снятия её временного каталога: сбой снятия называет каталог, код сохранён; судимо ловушек $judged"
