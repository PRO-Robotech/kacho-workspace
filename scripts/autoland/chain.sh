#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# chain.sh — посадки одной базы строго по очереди: догон, тело PR, демон вливания (ws#1289 (б)).
#
# ЗАЧЕМ. Цепочка жила копией tmp/autoland/chains/chain.sh вне дерева и отстала от уроков
# 2026-10-20…24: тело PR — генератором копии PR, а не ствола; код pr-body.sh ≠ 0 давал «тело
# не тронуто», и PR вливался со старым телом; без догона тело не переписывалось вовсе; номер
# задачи в отсоединённой копии терялся (remote-reader 64); срок службы короче демона;
# копии догона оставались на отказе; решение «Refs» диспетчера — отдельным скриптом руками.
# Шаблон в дереве — один, его судит scripts/autoland/chain-inject.sh.
#
# ФОРМА
#   chain.sh <владелец/имя> <клон> <база> <спека> [--after <файл .rc>]
#   строка спеки (через «|»): PR|задача|тема слияния|допуск|флаги|Refs
#     флаги — rerun (перезапуск отменённых прогонов головы), stop (отказ — конец цепочки);
#     Refs — номера через пробел: их «Closes #N» тела становятся «Refs #N» (решение диспетчера).
#   Запуск — отсоединённо, сроком не короче нужного (ниже):
#     scripts/detach.sh start <каталог> --deadline <с> -- bash scripts/autoland/chain.sh …
#
# ЧТО ДЕЛАЕТ НА КАЖДОЙ СТРОКЕ:
#   1. PR открыт; голова отстаёт от origin/<база> — догон слиянием в копии tmp/land-<имя>-<PR>,
#      отправка `env KACHO_TASK=<задача> heavy-slot.sh --wait 300 ci-local -- git push` (номер
#      задачи — явно: копия отсоединена, из ветки его не вывести);
#   2. ТЕЛО — только когда голова на origin (`git ls-remote` = голова; три чтения), генератором
#      ствола `$WS/scripts/pr-body.sh` (на машине он сам уходит remote-reader.sh) с
#      `env KACHO_TASK=<задача>`, затем Refs строки спеки, затем `gh pr edit --body-file`;
#      код генератора либо правки ≠ 0 — PR НЕ вливается (строка журнала, к следующей строке);
#   3. демон вливания `autoland.sh run` с KACHO_TASK; исход 4/5 — повтор с догоном, 0 — копия снята.
#   Копии догона снимаются при ЛЮБОМ исходе (ловушка выхода).
#
# СРОК. Перед первой строкой: KACHO_DETACHED_UNTIL (его ставит `detach.sh start --deadline`)
# обязан покрыть строки × (предел демона + предел гейта + 600 с снятия и догона); короче — 64
# до первого действия с нужным сроком в тексте отказа. Нет KACHO_DETACHED_UNTIL — запуск не
# отсоединён: 64.
# ПРЕДШЕСТВЕННИК. --after <.rc>: цепочка начинается лишь по коду 0 `detach.sh status` этого
# шага (отправки, догона); идёт (3) — ждёт с паузой 30 с в пределах срока; иной код — 3, ничего
# не сделано.
#
# Швы пробы (scripts/autoland/chain-inject.sh): CHAIN_WS, CHAIN_GH, CHAIN_PUSH, CHAIN_PR_BODY,
# CHAIN_AUTOLAND, CHAIN_DETACH, CHAIN_TIMEOUT (предел демона, с; по умолчанию его 10800),
# CHAIN_GATE_TIMEOUT (900), CHAIN_AFTER_POLL (30), CHAIN_LS_PAUSE (5).
# Коды: 0 — цепочка пройдена (исходы строк — в журнале); 3 — предшественник не 0; 64 — вызов
# либо срок не тот; код демона — при флаге stop.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -n "${CHAIN_WS:-}" ]; then WS="$CHAIN_WS"
else WS="$(dirname "$(git -C "$SELF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")"; fi
GH="${CHAIN_GH:-gh}"
PR_BODY="${CHAIN_PR_BODY:-$WS/scripts/pr-body.sh}"
AUTOLAND="${CHAIN_AUTOLAND:-$WS/scripts/autoland/autoland.sh}"
DETACH="${CHAIN_DETACH:-$WS/scripts/detach.sh}"
read -r -a PUSH <<< "${CHAIN_PUSH:-$WS/scripts/heavy-slot.sh --wait 300 ci-local --}"
TIMEOUT="${CHAIN_TIMEOUT:-10800}"; GATE_TIMEOUT="${CHAIN_GATE_TIMEOUT:-900}"
AFTER_POLL="${CHAIN_AFTER_POLL:-30}"; LS_PAUSE="${CHAIN_LS_PAUSE:-5}"
RUN_DIR="$WS/tmp/autoland"
export GH_PROMPT_DISABLED=1 GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=30 -o ServerAliveCountMax=40"

[ $# -ge 4 ] || { echo "chain: форма — chain.sh <владелец/имя> <клон> <база> <спека> [--after <файл .rc>]" >&2; exit 64; }
REPO="$1"; CLONE="$2"; BASE="$3"; SPEC="$4"; shift 4; AFTER=""
if [ "${1:-}" = --after ]; then AFTER="${2:-}"; [ -n "$AFTER" ] || { echo "chain: --after без файла" >&2; exit 64; }; fi
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "chain: репозиторий «$REPO» не по форме" >&2; exit 64; }
[ -r "$SPEC" ] && git -C "$CLONE" rev-parse --git-dir > /dev/null 2>&1 || { echo "chain: спеки $SPEC либо клона $CLONE нет" >&2; exit 64; }
SHORT="${REPO#*/}"
log() { printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "$SHORT" "$*"; }

lines="$(grep -c '^[0-9]' "$SPEC")"
[ "$lines" -gt 0 ] || { echo "chain: в спеке $SPEC строк PR ноль" >&2; exit 64; }
need=$(( lines * (TIMEOUT + GATE_TIMEOUT + 600) ))
[[ "${KACHO_DETACHED_UNTIL:-}" =~ ^[0-9]+$ ]] || { echo "chain: запуск не отсоединён (KACHO_DETACHED_UNTIL нет) — detach.sh start <каталог> --deadline $need -- bash $0 …" >&2; exit 64; }
left=$(( KACHO_DETACHED_UNTIL - $(date +%s) ))
[ "$left" -ge "$need" ] || { echo "chain: срок службы $left с короче нужного $need с (строк $lines × (демон $TIMEOUT + гейт $GATE_TIMEOUT + снятие 600)) — detach.sh start … --deadline $need" >&2; exit 64; }

WTS=()
cleanup() { local w; for w in "${WTS[@]+"${WTS[@]}"}"; do [ -e "$w" ] && git -C "$CLONE" worktree remove --force "$w" > /dev/null 2>&1; done; git -C "$CLONE" worktree prune > /dev/null 2>&1; }
trap cleanup EXIT

if [ -n "$AFTER" ]; then
    while :; do
        bash "$DETACH" status "$AFTER" > /dev/null 2>&1; arc=$?
        [ "$arc" -eq 3 ] || break
        [ $(( KACHO_DETACHED_UNTIL - $(date +%s) )) -gt "$need" ] || { log "предшественник $AFTER идёт, а срок на исходе — стоп"; exit 3; }
        sleep "$AFTER_POLL"
    done
    [ "$arc" -eq 0 ] || { log "СТОП: предшественник $AFTER — код status $arc, не 0: цепочка не начата"; exit 3; }
    log "предшественник $AFTER — код 0"
fi

refs_filter() {  # <тело> <задача>… — «Closes #N» названных → «Refs #N» перед закрывающими
    local f="$1"; shift
    [ "$#" -gt 0 ] || return 0
    awk -v set=" $* " '
      { n++; L[n]=$0 }
      END {
        for (i=1;i<=n;i++) if (match(L[i],/^Closes #[0-9]+$/)) { t=substr(L[i],9); if (index(set," " t " ")) { R[++r]="Refs #" t; L[i]="\001" } }
        d=0
        for (i=1;i<=n;i++) {
          if (L[i]=="\001") continue
          if (!d && L[i] ~ /^Closes #[0-9]+$/) { for (k=1;k<=r;k++) print R[k]; d=1 }
          print L[i]
        }
        if (!d) for (k=1;k<=r;k++) print R[k]
      }' "$f" > "$f.refs" && mv "$f.refs" "$f"
}

on_origin() {  # <ветка> <голова> — голова ветки на origin = голова (три чтения ls-remote)
    local br="$1" head="$2" i lr lrc=1
    for i in 1 2 3; do
        lr="$(timeout 45 git -C "$CLONE" ls-remote --heads origin "refs/heads/$br" 2>&1)"; lrc=$?
        [ "$lrc" -eq 0 ] && break
        log "ls-remote попытка $i: код $lrc; $(printf '%s' "$lr" | tail -n1 | cut -c1-200)"
        [ "$i" -lt 3 ] && sleep "$LS_PAUSE"
    done
    [ "$lrc" -eq 0 ] || { log "сверка головы не выполнилась (ls-remote код $lrc)"; return 1; }
    [ "$(printf '%s\n' "$lr" | cut -f1)" = "$head" ] || { log "ls-remote: голова $(printf '%s\n' "$lr" | cut -f1 | cut -c1-12), ждали ${head:0:12}"; return 1; }
}

body() {  # <PR> <задача> <ветка> <голова> — тело генератором ствола; 0 — переписано
    local pr="$1" task="$2" br="$3" head="$4" b rc
    on_origin "$br" "$head" || { log "PR#$pr: голова не на origin — тело не собирается, PR не вливается"; return 1; }
    timeout 60 git -C "$CLONE" fetch -q origin "$BASE" "$br" 2> /dev/null
    b="$RUN_DIR/body-$SHORT-$pr-${head:0:12}.md"
    env KACHO_TASK="$task" RITUAL_REPO_DIR="$CLONE" bash "$PR_BODY" "$REPO" "origin/$BASE" "$head" > "$b" 2> "$b.err"; rc=$?
    [ "$rc" -eq 0 ] || { log "PR#$pr: pr-body.sh код $rc — PR не вливается: $(head -c 300 "$b.err" | tr '\n' ' ')"; return 1; }
    # shellcheck disable=SC2086  # номера Refs — словами
    refs_filter "$b" $REFS
    timeout 45 "$GH" pr edit "$pr" -R "$REPO" --body-file "$b" > /dev/null 2>&1 || { log "PR#$pr: gh pr edit не прошёл — PR не вливается"; return 1; }
    log "PR#$pr: тело переписано pr-body.sh${REFS:+ (Refs: $REFS)}"
}

catchup() {  # <PR> <задача> <ветка> <голова> → 0 и NEWHEAD, иначе 1
    local pr="$1" task="$2" br="$3" head="$4" wt="$WS/tmp/land-$SHORT-$1" i rc mref="$BASE" cf
    [ -e "$wt" ] && git -C "$CLONE" worktree remove --force "$wt" 2> /dev/null
    git -C "$CLONE" worktree add -q --detach "$wt" "$head" || { log "копия $wt не заведена"; return 1; }
    WTS+=("$wt")
    [[ "$BASE" =~ ^[0-9]+$ ]] && mref="#$BASE"  # хук commit-msg kaname: «#<N> merge #<M>: …»
    if ! git -C "$wt" merge --no-ff -q -m "#$task merge $mref: догон базы" "origin/$BASE" > "$wt.merge.out" 2>&1; then
        cf="$(git -C "$wt" diff --name-only --diff-filter=U | tr '\n' ' ')"
        if [ -n "${cf// /}" ]; then log "КОНФЛИКТ догона: $cf — merge --abort"; else log "слияние отклонено: $(tail -n5 "$wt.merge.out" | tr '\n' ' ')"; fi
        git -C "$wt" merge --abort 2> /dev/null; return 1
    fi
    git -C "$wt" merge-base --is-ancestor "origin/$BASE" HEAD || { log "догон: база не предок"; return 1; }
    [ "$(git -C "$wt" rev-list --parents -n1 HEAD | wc -w)" = 3 ] || { log "догон: у слияния не два родителя"; return 1; }
    NEWHEAD="$(git -C "$wt" rev-parse HEAD)"
    for i in 1 2 3 4 5 6; do
        (cd "$wt" && env KACHO_TASK="$task" "${PUSH[@]}" git push origin "HEAD:refs/heads/$br") > "$wt.push.out" 2>&1; rc=$?
        log "отправка догона PR#$pr попытка $i: код $rc; $(tail -n1 "$wt.push.out" | cut -c1-200)"
        [ "$rc" -eq 0 ] && break
        case "$rc" in 74|75) ;; *) return 1 ;; esac
    done
    [ "$rc" -eq 0 ]
}

while IFS="|" read -r -u 3 PR TASK SUBJ ALLOW FLAGS REFS; do
    [[ "${PR:-}" =~ ^[0-9]+$ ]] || continue
    [[ "$TASK" =~ ^[1-9][0-9]*$ ]] || { log "PR#$PR: задача «$TASK» не номер — строка пропущена"; continue; }
    REFS="${REFS:-}"; rc=1
    for attempt in 1 2 3; do
        info="$(timeout 45 "$GH" pr view "$PR" -R "$REPO" --json state,headRefOid,headRefName --jq '[.state,.headRefOid,.headRefName]|@tsv')" || { log "PR#$PR: gh pr view не прошёл"; continue; }
        IFS=$'\t' read -r st head br <<< "$info"
        [ "$st" = OPEN ] || { log "PR#$PR: состояние $st — пропуск"; rc=0; break; }
        timeout 45 git -C "$CLONE" fetch -q origin 2> /dev/null
        behind="$(git -C "$CLONE" rev-list --count "$head..origin/$BASE" 2>&1)"
        log "PR#$PR попытка $attempt: голова ${head:0:12} ветка $br отставание $behind"
        if [ "$behind" != 0 ]; then
            catchup "$PR" "$TASK" "$br" "$head" || { log "PR#$PR: догон не удался — к следующему"; rc=1; break; }
            head="$NEWHEAD"
        elif [[ "${FLAGS:-}" == *rerun* ]]; then
            for rid in $(timeout 45 "$GH" run list -R "$REPO" --commit "$head" --json databaseId,conclusion --jq '.[]|select(.conclusion=="cancelled")|.databaseId'); do
                log "rerun --failed run $rid"; timeout 45 "$GH" run rerun "$rid" -R "$REPO" --failed 2>&1 | tail -1
            done
        fi
        # генератор тела — ствола воркспейса: основной клон догоняется до origin/main (только ff)
        timeout 45 git -C "$WS" fetch -q origin main 2> /dev/null; git -C "$WS" merge --ff-only -q origin/main > /dev/null 2>&1
        body "$PR" "$TASK" "$br" "$head" || { rc=1; break; }
        NAME="${REPO%%/*}__${REPO#*/}__${PR}__${head:0:12}"
        STATE="$RUN_DIR/$NAME.state"; rm -f "$STATE" "$RUN_DIR/$NAME.pid"
        cp "$AUTOLAND" "$RUN_DIR/$NAME.autoland.sh"
        log "PR#$PR: демон run, допуск «${ALLOW:--}», тема «$SUBJ»"
        AUTOLAND_WS="$WS" AUTOLAND_HEAD_SYNC=180 KACHO_TASK="$TASK" KACHO_DETACHED_UNTIL="$(( $(date +%s) + TIMEOUT + GATE_TIMEOUT ))" \
            bash "$RUN_DIR/$NAME.autoland.sh" run --repo "$REPO" --pr "$PR" --head "$head" --subject "$SUBJ" ${ALLOW:+--allow "$ALLOW"} \
            >> "$RUN_DIR/$NAME.log" 2>&1
        rc=$?
        log "PR#$PR: демон код $rc; state: $(head -n1 "$STATE" 2> /dev/null | cut -c1-400)"
        case "$rc" in 4|5) continue ;; *) break ;; esac
    done
    if [ "$rc" -ne 0 ] && [[ "${FLAGS:-}" == *stop* ]]; then log "СТОП цепочки: PR#$PR код $rc"; exit "$rc"; fi
done 3< "$SPEC"
log "цепочка закончена"
