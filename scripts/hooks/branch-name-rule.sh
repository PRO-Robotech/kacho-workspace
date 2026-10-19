#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# branch-name-rule.sh — предикат имени ветки воркспейса (`git-issues.md` §«Имя ветки»).
# Source-only. Потребители — хук отправки scripts/hooks/pre-push (имя на удалённом при
# создании) и предпроверка задания `scripts/lane-precheck.sh --premise` (вид branchname,
# ws#1226: имя судится ДО раздачи, а не отказом хука после 20 минут). Своей копии предиката
# нет ни у одного. Поведение держит scripts/tooling-gate/check-18-push-refuses-unlawful-branch-name.sh.
#
# Законно: `main`; `<N>-<суффикс>` по `^[0-9]+-[a-z0-9][a-z0-9-]*$` с суффиксом
# не длиннее 40 символов; личные черновики `wip/*`, `tmp/*` (не вливаются).
branch_name_lawful() {
    local name="$1" re='^[0-9]+-[a-z0-9][a-z0-9-]*$'
    case "$name" in
        main | wip/* | tmp/*) return 0 ;;
    esac
    [[ "$name" =~ $re ]] || return 1
    local suffix="${name#*-}"
    [ "${#suffix}" -le 40 ]
}

branch_name_reason() {
    local name="$1"
    case "$name" in
        issue-* | epic-* | ntf/* | release/*)
            echo "прежняя форма «${name%%[-/]*}…» снята решением 2026-09-30" ;;
        *)
            if [[ "$name" =~ ^[0-9]+$ ]]; then
                echo "голый номер — прежняя форма, заводить новую нельзя (существующие на удалённом дописываются до вливания); нужна суть задачи: $name-<суть>"
            elif ! [[ "$name" =~ ^[0-9]+- ]]; then
                echo "не начинается с номера задачи"
            elif ! [[ "$name" =~ ^[0-9]+-[a-z0-9][a-z0-9-]*$ ]]; then
                echo "суффикс не латиница kebab-case [a-z0-9-] либо начинается с дефиса"
            else
                echo "суффикс длиннее 40 символов"
            fi ;;
    esac
}
