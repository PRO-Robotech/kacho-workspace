#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# push-hook.sh [опции git перед push …] — есть ли у отправки из этого каталога хук отправки.
# Единственный признак тяжести `git push` для стража heavy-guard (.claude/hooks/heavy-guard/guard.py)
# и слота (scripts/heavy-slot.sh): второго нет (ws#1335).
#
# Решение диспетчера 2026-10-22 (ws#1335, вариант б): `git push` в клоне БЕЗ хука отправки —
# лёгкая команда, слота не берёт; хук есть, когда выполнено ЛЮБОЕ из трёх:
#   · непуст core.hooksPath (любой слой настроек и `-c core.hooksPath=…` перед push) — git
#     берёт хуки оттуда, а не из своего каталога;
#   · исполняемый <общий каталог git>/hooks/pre-push (у связанной копии — каталог основного
#     клона: git зовёт хук оттуда; неисполняемый git не зовёт);
#   · scripts/hooks/pre-push в дереве копии (источник хука, `make install-hooks`).
# Признак — то, что git ИСПОЛНИТ, а не текст хука: страж прежде читал текст
# scripts/hooks/pre-push (ci-local.sh, run-all.sh) и пропускал без слота отправку kaname, чей хук
# гонит go test, и копию с core.hooksPath на каталог с pre-push.
#
# Аргументы — слова команды между `git` и `push`. Судятся -C, --git-dir, --work-tree и
# `-c core.hooksPath=…`: прочие `-c` не подаются git — значение чужой настройки страж,
# судящий команду ДО её разрешения, исполнять не вправе.
#
# Вывод — одна строка `PUSH-HOOK<TAB>present|absent|none<TAB>основание`. Коды: 0 — хук есть;
# 1 — хука нет (лёгкая отправка); 2 — не репозиторий git либо git не ответил (отправка
# откажет сама); 64 — вызов неверен.
set -u

opts=() hp_cli=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -C|--git-dir|--work-tree)
            [ "$#" -ge 2 ] || { printf 'PUSH-HOOK\tnone\tу опции %s нет значения\n' "$1"; exit 64; }
            opts+=("$1" "$2"); shift 2 ;;
        --git-dir=*|--work-tree=*) opts+=("$1"); shift ;;
        -c)
            [ "$#" -ge 2 ] || { printf 'PUSH-HOOK\tnone\tу опции -c нет значения\n'; exit 64; }
            case "${2,,}" in core.hookspath=*) hp_cli="${2#*=}"; opts+=(-c "$2") ;; esac
            shift 2 ;;
        *) shift ;;
    esac
done

gd="$(git "${opts[@]}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || gd=""
if [ -z "$gd" ]; then
    printf 'PUSH-HOOK\tnone\tне репозиторий git (%s%s) — отправка откажет сама\n' "$PWD" "${opts[*]:+, ${opts[*]}}"
    exit 2
fi
hp="$(git "${opts[@]}" config core.hooksPath 2>/dev/null)" || hp=""
[ -n "$hp" ] || hp="$hp_cli"
if [ -n "$hp" ]; then
    printf 'PUSH-HOOK\tpresent\tcore.hooksPath=%s — хуки git берёт оттуда\n' "$hp"
    exit 0
fi
if [ -x "$gd/hooks/pre-push" ] && [ -f "$gd/hooks/pre-push" ]; then
    printf 'PUSH-HOOK\tpresent\tисполняемый %s/hooks/pre-push\n' "$gd"
    exit 0
fi
top="$(git "${opts[@]}" rev-parse --show-toplevel 2>/dev/null)" || top=""
if [ -n "$top" ] && [ -e "$top/scripts/hooks/pre-push" ]; then
    printf 'PUSH-HOOK\tpresent\tв дереве %s/scripts/hooks/pre-push\n' "$top"
    exit 0
fi
printf 'PUSH-HOOK\tabsent\tхука отправки нет: core.hooksPath пуст, исполняемого %s/hooks/pre-push нет, scripts/hooks/pre-push в дереве %s нет\n' "$gd" "${top:-—}"
exit 1
