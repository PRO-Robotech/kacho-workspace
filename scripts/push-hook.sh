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
# Аргументы — присваивания окружения команды (`ИМЯ=значение`, что стоят перед git либо в `env`)
# и слова между `git` и `push`. Судятся -C, --git-dir, --work-tree и `-c core.hooksPath=…`:
# прочие `-c` не подаются git — значение чужой настройки страж, судящий команду ДО её
# разрешения, исполнять не вправе. Присваивание судится по ИМЕНИ и git не подаётся: GIT_*
# (GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR, GIT_CONFIG_*, …), HOME и XDG_CONFIG_HOME меняют
# то, что git исполнит, — отправка с ними считается отправкой с хуком; закрытый перечень
# безвредных — транспорт и запрос учётных данных: GIT_TERMINAL_PROMPT, GIT_SSH_COMMAND, GIT_SSH,
# GIT_ASKPASS. Окружение самого вызова признак наследует — его git и судит.
#
# Вывод — одна строка `PUSH-HOOK<TAB>present|absent|none<TAB>основание`. Коды: 0 — хук есть;
# 1 — хука нет (лёгкая отправка); 2 — не репозиторий git либо git не ответил (отправка
# откажет сама); 64 — вызов неверен.
set -u

opts=() gdir="" wtree="" cdir="$PWD"
while [ "$#" -gt 0 ]; do
    if [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        name="${1%%=*}"
        case "$name" in
            GIT_TERMINAL_PROMPT|GIT_SSH_COMMAND|GIT_SSH|GIT_ASKPASS) ;;
            GIT_*) printf 'PUSH-HOOK\tpresent\tпеременная %s меняет то, что исполнит git (каталог, дерево, настройки) — отправка судится как с хуком\n' "$name"; exit 0 ;;
            HOME|XDG_CONFIG_HOME) printf 'PUSH-HOOK\tpresent\tпеременная %s меняет глобальный слой настроек git — отправка судится как с хуком\n' "$name"; exit 0 ;;
        esac
        shift; continue
    fi
    case "$1" in
        -C|--git-dir|--work-tree)
            [ "$#" -ge 2 ] || { printf 'PUSH-HOOK\tnone\tу опции %s нет значения\n' "$1"; exit 64; }
            case "$1" in
                --git-dir) gdir="$2" ;;
                --work-tree) wtree="$2" ;;
                -C) cdir="$(cd "$cdir" 2>/dev/null && cd "$2" 2>/dev/null && pwd)" || cdir="" ;;
            esac
            opts+=("$1" "$2"); shift 2 ;;
        --git-dir=*|--work-tree=*)
            case "$1" in --git-dir=*) gdir="${1#*=}" ;; *) wtree="${1#*=}" ;; esac
            opts+=("$1"); shift ;;
        -c)
            [ "$#" -ge 2 ] || { printf 'PUSH-HOOK\tnone\tу опции -c нет значения\n'; exit 64; }
            case "${2,,}" in core.hookspath=*) opts+=(-c "$2") ;; esac
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
if [ -n "$hp" ]; then
    printf 'PUSH-HOOK\tpresent\tcore.hooksPath=%s — хуки git берёт оттуда\n' "$hp"
    exit 0
fi
if [ -x "$gd/hooks/pre-push" ] && [ -f "$gd/hooks/pre-push" ]; then
    printf 'PUSH-HOOK\tpresent\tисполняемый %s/hooks/pre-push\n' "$gd"
    exit 0
fi
# Дерево копии — то, откуда `make install-hooks` ставит хук. С --git-dir без --work-tree git
# считает деревом каталог КОМАНДЫ, а не клон: дерево клона — родитель его «.git» либо core.worktree.
if [ -n "$gdir" ] && [ -z "$wtree" ]; then
    top="$(git "${opts[@]}" config core.worktree 2>/dev/null)" || top=""
    if [ -z "$top" ] && [ "$(basename -- "$gdir")" = .git ]; then top="$(cd "$cdir" 2>/dev/null && cd "$(dirname -- "$gdir")" 2>/dev/null && pwd)" || top=""; fi
else
    top="$(git "${opts[@]}" rev-parse --show-toplevel 2>/dev/null)" || top=""
fi
if [ -n "$top" ] && [ -e "$top/scripts/hooks/pre-push" ]; then
    printf 'PUSH-HOOK\tpresent\tв дереве %s/scripts/hooks/pre-push\n' "$top"
    exit 0
fi
printf 'PUSH-HOOK\tabsent\tхука отправки нет: core.hooksPath пуст, исполняемого %s/hooks/pre-push нет, scripts/hooks/pre-push в дереве %s нет\n' "$gd" "${top:-—}"
exit 1
