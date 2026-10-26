#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# node-reach.sh <узел> — матрица «root на узле → чьи полномочия достижимы» ДО выдачи исключения
# privileged на общем кластере (ws#1418; уроки 2a3dbd9d, 9b2c1704, 0cafde3e и диспетчера
# 2026-10-26: остаточный риск «root на узле» назван без замера, `get nodes/proxy` у SA подов узла
# не увиден). Root на узле читает токены всех SA подов этого узла — значит, достаёт их полномочия.
#
# Как спрашивает: по каждой SA подов узла — SubjectAccessReview API-сервера через
# `kubectl auth can-i <вопрос> --as=system:serviceaccount:<ns>:<sa>`. НЕ `auth can-i --list`:
# SelfSubjectRulesReview не показывает подресурсы, выданные вебхук-авторизатором.
#
# Вопросы — закрытый перечень (имя|аргументы can-i):
#   secrets-all  list secrets -A                                  — секреты всего кластера
#   nodes-proxy  get nodes --subresource=proxy                    — kubelet любого узла (node-read-admin)
#   nodes-log    get nodes --subresource=log                      — журналы узлов
#   pods-exec    create pods --subresource=exec -A                — исполнение в чужих подах
#   sa-token     create serviceaccounts --subresource=token -A    — выпуск токенов чужих SA
#
# Вывод: строка `REACH <ns>/<sa> <вопрос>` на каждое «да», затем `[CENSUS]` — узел, подов, SA,
# вопросов, «да». Значения env и токены не читаются и не печатаются: только решение API-сервера.
# Коды: 0 — ни одна SA узла не может ничего из перечня; 1 — может (строки REACH);
#   2 — не судимо: нет kubectl, узла, подов на узле (это не «доступа нет»), права имперсонации,
#   ответ can-i не «yes»/«no»; 64 — довод не тот.
# Шов пробы: KUBECTL — исполняемый файл вместо `kubectl` (scripts/node-reach-inject.sh).
set -uo pipefail
case "${1:-}" in
    -h | --help) sed -n '5,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[ $# -eq 1 ] && [ -n "$1" ] || { echo "node-reach: usage: node-reach.sh <узел>" >&2; exit 64; }
NODE="$1"
K="${KUBECTL:-kubectl}"
void() { echo "node-reach: VOID — $*" >&2; exit 2; }

command -v "$K" > /dev/null 2>&1 || void "нет $K"
"$K" get node "$NODE" -o name > /dev/null 2>&1 || void "узла «$NODE» нет либо API-сервер не ответил"
pairs="$("$K" get pods -A --field-selector "spec.nodeName=$NODE" \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.spec.serviceAccountName}{"\n"}{end}')" ||
    void "поды узла «$NODE» не прочитаны"
pods="$(printf '%s\n' "$pairs" | grep -c .)"
# SA пода без имени — default своего пространства (так её монтирует kubelet).
sas="$(printf '%s\n' "$pairs" | awk -F'\t' '$1 != "" { print $1 "\t" ($2 == "" ? "default" : $2) }' | sort -u)"
[ -n "$sas" ] || void "на узле «$NODE» подов 0 — матрицы нет, это не «доступа нет»"

QUESTIONS='secrets-all|list secrets -A
nodes-proxy|get nodes --subresource=proxy
nodes-log|get nodes --subresource=log
pods-exec|create pods --subresource=exec -A
sa-token|create serviceaccounts --subresource=token -A'

reach=0 n_sa=0 n_q=0
while IFS=$'\t' read -r ns sa; do
    n_sa=$((n_sa + 1))
    while IFS='|' read -r name q; do
        n_q=$((n_q + 1))
        read -ra qa <<< "$q"
        ans="$("$K" auth can-i "${qa[@]}" --as="system:serviceaccount:$ns:$sa" 2> /dev/null)"
        rc=$?
        case "$ans" in
            yes | "yes - "*) reach=$((reach + 1)); printf 'REACH\t%s/%s\t%s\n' "$ns" "$sa" "$name" ;;
            no | "no - "*) ;;
            *) void "can-i «$name» для $ns/$sa: ответ «$ans» (код $rc) — нет права имперсонации либо API-сервер не ответил" ;;
        esac
    done <<< "$QUESTIONS"
done <<< "$sas"
echo "[CENSUS] node-reach: узел $NODE, подов $pods, SA $n_sa, вопросов $n_q, «да» $reach"
[ "$reach" -eq 0 ]
