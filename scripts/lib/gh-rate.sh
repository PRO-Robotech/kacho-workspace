#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# gh-rate.sh — остаток лимита GitHub ДО чтения гейтов (урок 2026-10-16, ws#1110).
#
# ЗАЧЕМ. Лимит REST (5000 в час) и GraphQL — общие на все сессии учётки и кончались
# посреди посадки: чтение гейта получало 403 «rate limit exceeded», и вердикт
# читался красным либо тайм-аутом. Исчерпанный лимит — «не выполнилось» со временем
# сброса, а не находка о PR. `gh api rate_limit` сам в лимит не засчитывается.
#
# gh_rate_short <gh> <порог> — 0: остаток core и graphql ≥ порога либо ответа нет
# (не прочитанный лимит не вердикт: судят сами чтения гейта); 1: остаток ниже порога,
# в stdout — «лимит <ресурс>: остаток R из L < порога P, сброс в HH:MM».
gh_rate_short() {
    local gh="$1" min="$2" j line res rem lim reset
    j="$("$gh" api rate_limit 2>/dev/null)" || return 0
    line="$(jq -r '[.resources.core, .resources.graphql] | map(select(type == "object"))
        | min_by(.remaining) // empty | "\(.remaining) \(.limit) \(.reset)"' <<< "$j" 2>/dev/null)" || return 0
    read -r rem lim reset <<< "$line"
    [[ "$rem" =~ ^[0-9]+$ && "$reset" =~ ^[0-9]+$ ]] || return 0
    [ "$rem" -lt "$min" ] || return 0
    res="$(jq -r 'if (.resources.core.remaining // 1e9) <= (.resources.graphql.remaining // 1e9) then "REST" else "GraphQL" end' <<< "$j" 2>/dev/null)"
    printf 'лимит %s: остаток %s из %s < порога %s, сброс в %s' "${res:-REST}" "$rem" "$lim" "$min" "$(date -d "@$reset" +%H:%M)"
    return 1
}
