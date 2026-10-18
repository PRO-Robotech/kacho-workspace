#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# push-chain.sh — ОБЩАЯ цепочка сдачи полосы: отправка полным хуком через слот →
# сверка головы на origin → голова PR → DoD-proof → демон вливания → .rc (ws#1185).
#
# ЗАЧЕМ. До неё каждая полоса писала свою цепочку в tmp/ (1189-chain.sh, kn-891-chain.sh,
# gate-after-894.sh …), и одни и те же уроки повторялись по полосам (ws#1185):
#   (в) DoD-proof публиковался итогом при коде 75 — «не выполнилось» выдавалось за итог;
#   (к) на 74/75 цепочка не повторяла отправку и кончалась «не выполнилось»;
#   повтор локально (`--local`) — обход внешнего кластера: «занят — 74/75, локально не идёт;
#   77 — во внешний кластер» (testing-verdict.md#external-cluster-first), поэтому повтор — по
#   внешнему маршруту, а `--local` — лишь доводом вызывающего;
#   (м) обёртка `bash -c "cd … && git push"` давала 77 и читалась как красное;
#   (н) `autoland start` сразу после отправки видел старую голову PR — head-moved (5);
#   (з) пачка отправок вставала в занятые чужими слоты вслепую;
#   SIGHUP kaname#882/#894 — `nohup` глушит сигнал завершения у детей (ws#1046); тот же игнор
#   наследуется и от вызывающего с `trap '' HUP` — отсоединение сбрасывает ВСЕ сигналы.
# Здесь каждый из них — код, а не фраза в задании.
#
# ИСПОЛЬЗОВАНИЕ
#   push-chain.sh --copy <копия> --branch <ветка> --sha <sha40> [--detach]
#                 [--issue <N | владелец/имя#N>]… [--evidence <файл>]
#                 [--pr <N> [--subject "#M merge #N: …" [--land-arg <довод>]…]]
#                 [--task <N>] [--lane-base <ревизия>] [--out <каталог>] [--head-wait <с>]
#                 [--local "<причина>"]
#   --detach — сам уходит в отсоединённый прогон (setsid, env --default-signal — все сигналы
#     по умолчанию, в том числе HUP, проигнорированный вызывающим; БЕЗ nohup) и сразу печатает «идёт: pid …, журнал …, .rc …, срок …»; .rc снят до старта,
#     имена уникальны (ветка, sha, pid). Без --detach — в переднем плане (так зовут пробы
#     и уже отсоединённый вызывающий).
#   --issue — задачи, в которые идёт комментарий `DoD-proof @<sha>`; без репозитория —
#     репозиторий origin копии. --evidence — файл, дописываемый к телу (опыт, перепись).
#   --pr — запрос этой ветки: цепочка ждёт, пока его headRefOid станет --sha (не дольше
#     --head-wait, по умолчанию 180 с), и лишь затем зовёт `autoland.sh start` (при
#     --subject). --land-arg — довод autoland дословно (--stand-report, --allow …).
#   --out — каталог журналов ВНЕ рабочего дерева (по умолчанию ~/.cache/push-chain).
#   --lane-base — база полосы для статики шага 0б (по умолчанию origin/main).
#   --local — обход внешнего кластера на КАЖДОЙ попытке, причина ≥ 12 знаков — довод
#     диспетчера (например «Job не несёт соседний клон kacho», ws#1196). Сама цепочка его
#     не выводит: недоступный кластер слот узнаёт сам и идёт локально с доказательством
#     (proof=), а 74/75/77/69 — «занят» или «не опознано», не «недоступен».
#
# ШАГИ
#   0. Предусловия: голова копии = --sha, отслеживаемые файлы не правлены (кластер судит
#      коммит), ветка — не первичная копия воркспейса в чужую ветку (это судит слот).
#   0б. Статика до хука (урок (о)): копия с `internal/repohygiene/` (kacho), чей дифф от
#      базы трогает `deploy/` либо `.github/workflows/ci.yaml`, — сперва `go test -short
#      ./internal/repohygiene/` (секунды против минут хука); красное — код 1 без отправки.
#   1. `heavy-slot.sh --status` — первая строка и занятые слоты в журнал, счёт занятых — в
#      .rc (`slots=`): размер пачки отправок — по свободным (урок (з)).
#   2. Отправка СЛОВАМИ argv из каталога копии: `heavy-slot.sh ci-local -- git push origin
#      HEAD:refs/heads/<ветка>` с явными KACHO_HOME_KACHO/KANAME/CORELIB (клоны project/*
#      основного клона воркспейса; ws#1183) и KACHO_TASK. Слова, а не `bash -c`: строку
#      оболочки слот не разбирает и судит каталог вызова (урок (л), (м)).
#   3. Код 74, 75, 77 или 69 — «не выполнилось», не красное; повтор ОДИН и по внешнему
#      маршруту (без `--local`, если его не дал вызывающий):
#      74/75 — `--enqueue <каталог журналов вне копии>` (и `--resume <билет>`, если слот его
#        назвал): ожидающий билет идёт во внешний кластер по одному; цепочка дочитывает его
#        .rc (предел PUSH_CHAIN_ENQ_WAIT_S, по умолчанию 7800 с — срок билета слота 2 ч);
#      77 и 69 — тот же вызов словами argv ещё раз.
#      Код — хук отказал: красное, повтора нет, возврат автору. 141 после хука — ssh,
#      снятый простоем: исход решает сверка шага 4.
#   4. `git ls-remote origin refs/heads/<ветка>` = --sha — иначе «не выполнилось».
#   5. С --pr: headRefOid запроса = --sha (опрос раз в 5 с, предел --head-wait); не
#      совпал — «не выполнилось: голова PR не совпала», демон не зовётся.
#   6. DoD-proof — ТОЛЬКО при исходе отправки 0 и совпавшей голове (урок (в)): команда,
#      сырой итог хука (строки сводов, без адресов), код возврата.
#   7. С --pr и --subject: `autoland.sh start` — его строки pid/журнал/state в журнал.
#
# ИСХОД — код и .rc (первая строка — код, вторая — поля `ключ=значение`):
#   0 сдано · 1 красное (хук отказал — автору) · 2 не выполнилось (слот, сверка, голова
#   PR, трекер, демон) · 64 вызов либо предусловие.
#
# ВХОД ПОДМЕНЯЕМ ради доказательства (scripts/push-chain-inject.sh): PUSH_CHAIN_SLOT,
# PUSH_CHAIN_GH, PUSH_CHAIN_AUTOLAND, PUSH_CHAIN_POLL_S, PUSH_CHAIN_GO, PUSH_CHAIN_ENQ_WAIT_S. Ручки не снимают ни слота, ни
# хука: подменённый слот — та же отправка без слота, что и прямой вызов git.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
SLOT="${PUSH_CHAIN_SLOT:-$HERE/heavy-slot.sh}"
GH="${PUSH_CHAIN_GH:-gh}"
AUTOLAND="${PUSH_CHAIN_AUTOLAND:-$HERE/autoland/autoland.sh}"
POLL_S="${PUSH_CHAIN_POLL_S:-5}"
ENQ_WAIT_S="${PUSH_CHAIN_ENQ_WAIT_S:-7800}"

say() { printf 'push-chain: %s\n' "$*" >&2; }
usage() { say "$1"; say "форма: push-chain.sh --copy <копия> --branch <ветка> --sha <sha40> [--detach] [--issue N]… [--pr N [--subject …]] (шапка)"; exit 64; }

COPY="" BRANCH="" SHA="" DETACH=0 PR="" SUBJECT="" EVIDENCE="" TASK="" BASE="" LANE_BASE="origin/main" LOCAL_WHY=""
OUT="${XDG_CACHE_HOME:-$HOME/.cache}/push-chain" HEAD_WAIT=180
ISSUES=() LAND=() ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --detach) DETACH=1; shift; continue ;;
        --base) BASE="${2:-}"; shift 2; continue ;;
    esac
    [ "$#" -ge 2 ] || usage "довод «$1» без значения"
    ARGS+=("$1" "$2")
    case "$1" in
        --copy) COPY="$2" ;;
        --branch) BRANCH="$2" ;;
        --sha) SHA="$2" ;;
        --issue) ISSUES+=("$2") ;;
        --evidence) EVIDENCE="$2" ;;
        --pr) PR="$2" ;;
        --subject) SUBJECT="$2" ;;
        --land-arg) LAND+=("$2") ;;
        --task) TASK="$2" ;;
        --out) OUT="$2" ;;
        --head-wait) HEAD_WAIT="$2" ;;
        --lane-base) LANE_BASE="$2" ;;
        --local) LOCAL_WHY="$2" ;;
        *) usage "неизвестный довод «$1»" ;;
    esac
    shift 2
done
[ -n "$COPY" ] && [ -n "$BRANCH" ] && [ -n "$SHA" ] || usage "нужны --copy, --branch и --sha"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage "--sha «$SHA» — полная ревизия (40 знаков)"
[[ "$HEAD_WAIT" =~ ^[0-9]+$ ]] || usage "--head-wait «$HEAD_WAIT» — секунды (целое)"
[ -z "$PR" ] || [[ "$PR" =~ ^[0-9]+$ ]] || usage "--pr «$PR» — номер запроса"
[ -z "$SUBJECT" ] || [ -n "$PR" ] || usage "--subject без --pr: демону вливания нечего вливать"
[ -z "$EVIDENCE" ] || [ -r "$EVIDENCE" ] || usage "--evidence «$EVIDENCE» не читается"
[[ "$ENQ_WAIT_S" =~ ^[0-9]+$ ]] || usage "PUSH_CHAIN_ENQ_WAIT_S «$ENQ_WAIT_S» — секунды (целое)"
COPY="$(cd "$COPY" 2>/dev/null && pwd)" || usage "копии «$COPY» нет"

if [ -z "$BASE" ]; then
    mkdir -p "$OUT" 2>/dev/null && [ -w "$OUT" ] || usage "каталог журналов «$OUT» не доступен на запись"
    OUT="$(cd "$OUT" && pwd)"
    if git -C "$OUT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git -C "$OUT" check-ignore -q "$OUT/x.log" 2>/dev/null; then
        usage "каталог журналов «$OUT» — в рабочем дереве git и не игнорируется: файлы цепочки сделали бы копию грязной"
    fi
    BASE="$OUT/push-chain-$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' '_')-${SHA:0:10}-$$"
fi
LOG="$BASE.log" RCF="$BASE.rc"

if [ "$DETACH" = 1 ]; then
    rm -f "$RCF" "$BASE.pid"
    # Без nohup (ws#1046, kaname#882/#894): игнор SIGHUP наследуют дети, и пробы сигналов
    # краснеют ложно. setsid уводит из сеанса вызывающего; env --default-signal без списка
    # возвращает по умолчанию ВСЕ сигналы — и HUP, проигнорированный вызывающим (`trap ''
    # HUP`): `=PIPE` сбрасывал лишь PIPE (ребёнок с SigIgn 0x5, приёмка ws#1185).
    # shellcheck disable=SC2016  # строка дочерней оболочки, $1… раскрывает она
    setsid -f env --default-signal bash -c 'echo $$ > "$1.pid"; exec bash "$2" --base "$1" "${@:3}"' _ "$BASE" "$SELF" "${ARGS[@]}" > "$LOG" 2>&1 < /dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BASE.pid" ] && break; sleep 0.2; done
    printf 'идёт: pid %s, журнал %s, .rc %s, срок — до %s (хук ≤ 20 мин, голова PR ≤ %s с)\n' \
        "$(cat "$BASE.pid" 2>/dev/null || echo '?')" "$LOG" "$RCF" "$(date -d "+$(( 25 + HEAD_WAIT / 60 )) min" +%H:%M)" "$HEAD_WAIT"
    exit 0
fi

rm -f "$RCF"
F_STATIC="—" F_SLOTS="?" F_PUSH="—" F_TRIES=0 F_REMOTE="—" F_PRHEAD="skip" F_DOD="skip" F_LAND="skip" F_WHY=""
finish() {
    local rc="$1"
    printf '%s\nrc=%s static=%s push=%s tries=%s slots=%s ls_remote=%s pr_head=%s dod=%s land=%s log=%s%s\n' \
        "$rc" "$rc" "$F_STATIC" "$F_PUSH" "$F_TRIES" "$F_SLOTS" "$F_REMOTE" "$F_PRHEAD" "$F_DOD" "$F_LAND" "$LOG" "${F_WHY:+ why=$F_WHY}" > "$RCF"
    case "$rc" in
        0) say "сдано: $SHA → $BRANCH (попыток $F_TRIES)" ;;
        1) say "красное: ${F_WHY:-хук отправки отказал} — возврат автору; DoD-proof не публиковался" ;;
        2) say "не выполнилось: $F_WHY; DoD-proof не публиковался итогом" ;;
        *) say "вызов либо предусловие: $F_WHY" ;;
    esac
    exit "$rc"
}

# ── 0. предусловия ───────────────────────────────────────────────────────────
head_now="$(git -C "$COPY" rev-parse HEAD 2>/dev/null)"
[ "$head_now" = "$SHA" ] || { F_WHY="голова копии ${head_now:0:12} ≠ --sha ${SHA:0:12}"; finish 64; }
if [ -n "$(git -C "$COPY" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    F_WHY="в копии правлены отслеживаемые файлы — закоммить: судится коммит"; finish 64
fi
url="$(git -C "$COPY" config --get remote.origin.url 2>/dev/null)"
REPO="$(printf '%s' "${url%.git}" | sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#')"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { F_WHY="origin копии не разобран в владелец/имя"; finish 64; }
[ -n "$TASK" ] || TASK="$(printf '%s' "$BRANCH" | sed -nE 's/^([0-9]+).*/\1/p')"
# Клоны соседних домов — основного клона воркспейса, а не копии (в копии project/ нет).
WS_MAIN="$(dirname "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")"
HOMES=()
for n in kacho kaname corelib; do
    v="KACHO_HOME_$(printf '%s' "$n" | tr '[:lower:]' '[:upper:]')"
    if [ -n "${!v:-}" ]; then HOMES+=("$v=${!v}")
    elif [ -d "$WS_MAIN/project/$n/.git" ] || [ -f "$WS_MAIN/project/$n/.git" ]; then HOMES+=("$v=$WS_MAIN/project/$n"); fi
done
say "копия $COPY · ветка $BRANCH · голова ${SHA:0:12} · репозиторий $REPO · задача ${TASK:-—} · ${HOMES[*]:-KACHO_HOME_* не заданы}"

# ── 0б. статика до хука: правка deploy/ или ci.yaml kacho → repohygiene ─────
if [ -d "$COPY/internal/repohygiene" ]; then
    mb="$(git -C "$COPY" merge-base "$LANE_BASE" HEAD 2>/dev/null)"
    # Без трубы в grep -q: под pipefail ранний выход grep даёт git SIGPIPE (141), и правка
    # deploy/ на большом диффе читалась «не тронуто» (приёмка ws#1185). diff --quiet: 0 — не
    # тронуто, 1 — тронуто, иное — не судилось.
    drc=128; [ -z "$mb" ] || { git -C "$COPY" diff --quiet "$mb" HEAD -- deploy/ .github/workflows/ci.yaml; drc=$?; }
    if [ -z "$mb" ]; then
        F_STATIC="void:база $LANE_BASE не выведена"; say "статика repohygiene не судилась: база «$LANE_BASE» не найдена (--lane-base)"
    elif [ "$drc" = 1 ]; then
        say "дифф трогает deploy/ либо ci.yaml — go test -short ./internal/repohygiene/ до хука"
        (cd "$COPY" && "${PUSH_CHAIN_GO:-go}" test -short -count=1 ./internal/repohygiene/) > "$BASE.static.log" 2>&1
        src=$?
        F_STATIC="repohygiene:$src"
        [ "$src" = 0 ] || { tail -n 20 "$BASE.static.log" >&2; F_WHY="статика: go test -short ./internal/repohygiene/ — код $src до отправки ($BASE.static.log)"; finish 1; }
    elif [ "$drc" = 0 ]; then
        F_STATIC="skip:deploy/ci.yaml не тронуты"
    else
        F_STATIC="void:git diff — код $drc"; say "статика repohygiene не судилась: git diff — код $drc"
    fi
fi

# ── 1. занятость слотов ─────────────────────────────────────────────────────
st="$(bash "$SLOT" --status 2>&1 | sed -n '1p;/^  [a-z-]* *бюджет/p;/^  ждёт:/p;/^  внешний вход:/p')"
printf '%s\n' "$st" | sed 's/^/push-chain: --status: /' >&2
F_SLOTS="$(printf '%s\n' "$st" | sed -nE '1s/.*: ([0-9]+) из ([0-9]+),.*/\1\/\2/p')"
[ -n "$F_SLOTS" ] || F_SLOTS="?"

# ── 2–3. отправка словами argv, один повтор ─────────────────────────────────
PUSH_LOG="$BASE.push.log"; : > "$PUSH_LOG"
LOCAL_ARGS=(); [ -z "$LOCAL_WHY" ] || LOCAL_ARGS=(--local "$LOCAL_WHY")
push_once() {
    F_TRIES=$(( F_TRIES + 1 ))
    printf '== попытка %s %s: %s\n' "$F_TRIES" "$(date -Is)" "$*" >> "$PUSH_LOG"
    (cd "$COPY" && env "${HOMES[@]}" ${TASK:+KACHO_TASK="$TASK"} bash "$SLOT" "$@" "${LOCAL_ARGS[@]}" ci-local -- git push origin "HEAD:refs/heads/$BRANCH") >> "$PUSH_LOG" 2>&1
    local rc=$?
    printf '== попытка %s код %s\n' "$F_TRIES" "$rc" >> "$PUSH_LOG"
    return "$rc"
}
# enqueue_once [--resume N] — повтор после 74/75: ОДИН раз --enqueue в каталог вне копии,
# исход — код из .rc билета (строка ENQUEUED слота), его журнал — в журнал отправки.
enqueue_once() {
    local eq="$BASE.enq" line erc elog t0
    mkdir -p "$eq" || { echo "== каталог $eq не создан" >> "$PUSH_LOG"; return 69; }
    push_once --enqueue "$eq" "$@"; local qrc=$?
    [ "$qrc" = 0 ] || return "$qrc"
    line="$(grep -E $'^ENQUEUED\t' "$PUSH_LOG" | tail -n 1)"
    erc="$(printf '%s' "$line" | tr '\t' '\n' | sed -n 's/^rc=//p')"
    elog="$(printf '%s' "$line" | tr '\t' '\n' | sed -n 's/^log=//p')"
    [ -n "$erc" ] || { echo "== строки ENQUEUED нет — билет не поставлен" >> "$PUSH_LOG"; return 69; }
    say "отправка: билет в очереди, исход — $erc (не дольше $ENQ_WAIT_S с)"
    t0="$(date +%s)"
    until [ -s "$erc" ]; do
        [ $(( $(date +%s) - t0 )) -ge "$ENQ_WAIT_S" ] && { echo "== .rc билета нет за $ENQ_WAIT_S с: $erc" >> "$PUSH_LOG"; return 75; }
        sleep "$POLL_S"
    done
    [ -r "$elog" ] && { echo "== журнал билета $elog"; cat "$elog"; } >> "$PUSH_LOG"
    qrc="$(head -n 1 "$erc")"; [[ "$qrc" =~ ^[0-9]+$ ]] || qrc=69
    printf '== билет: код %s\n' "$qrc" >> "$PUSH_LOG"
    return "$qrc"
}
push_once; prc=$?
case "$prc" in
    74|75)
        tk="$(grep -oE -- '--resume [0-9]+' "$PUSH_LOG" | tail -n 1 | cut -d' ' -f2)"
        say "отправка: код $prc — слот занят (не выполнилось); ОДИН повтор --enqueue по внешнему маршруту${tk:+ --resume $tk}"
        enqueue_once ${tk:+--resume "$tk"}; prc=$?
        ;;
    77|69)
        say "отправка: код $prc — не выполнилось; ОДИН повтор словами argv по внешнему маршруту"
        push_once; prc=$?
        ;;
esac
F_PUSH="$prc"
case "$prc" in
    0|141) ;;
    1) F_WHY="хук отправки отказал"; finish 1 ;;
    *) F_WHY="отправка — код $prc после $F_TRIES попыток (журнал $PUSH_LOG)"; finish 2 ;;
esac

# ── 4. голова на origin ─────────────────────────────────────────────────────
remote="$(git -C "$COPY" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | cut -f1)"
if [ "$remote" != "$SHA" ]; then
    F_REMOTE="${remote:0:12}"; F_REMOTE="${F_REMOTE:-нет}"
    F_WHY="origin/$BRANCH = ${F_REMOTE} ≠ ${SHA:0:12} после отправки с кодом $prc"; finish 2
fi
F_REMOTE=ok
[ "$prc" = 141 ] && { say "код 141 после хука (ssh снят простоем), голова на origin совпала — сдано"; F_PUSH="141→ok"; }

# ── 5. голова PR ────────────────────────────────────────────────────────────
if [ -n "$PR" ]; then
    t0="$(date +%s)" got=""
    while :; do
        got="$("$GH" pr view "$PR" -R "$REPO" --json headRefOid -q .headRefOid 2>/dev/null)"
        [ "$got" = "$SHA" ] && break
        [ $(( $(date +%s) - t0 )) -ge "$HEAD_WAIT" ] && break
        sleep "$POLL_S"
    done
    if [ "$got" != "$SHA" ]; then
        F_PRHEAD="не совпало:${got:0:12}"
        F_WHY="голова PR #$PR — ${got:0:12} ≠ ${SHA:0:12} за $HEAD_WAIT с; демон вливания не звался (head-moved не наступил)"; finish 2
    fi
    F_PRHEAD="ok:$(( $(date +%s) - t0 ))s"
fi

# ── 6. DoD-proof — только на исходе 0 ───────────────────────────────────────
# dod_body <код отправки> — тело комментария; при коде, отличном от 0, НЕ печатает
# строку `DoD-proof @…`: «не выполнилось» итогом не выдаётся (урок (в)).
dod_body() {
    if [ "$1" != 0 ] && [ "$1" != "141→ok" ]; then
        printf 'не выполнилось: отправка %s — код %s; итога хука нет\n' "${SHA:0:12}" "$1"; return 1
    fi
    printf 'DoD-proof @%s\n\n' "$SHA"
    # shellcheck disable=SC2016  # обратные кавычки — разметка комментария, не подстановка
    printf 'Ветка `%s`. Команда: `heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/%s` из копии `%s` (push-chain.sh); попыток %s, код возврата %s.\n' \
        "$BRANCH" "$BRANCH" "$(basename "$COPY")" "$F_TRIES" "$1"
    echo '```'
    grep -E '^(pre-push: |prepush-[a-z-]+: |[A-Za-z0-9_.-]+: рассмотрено |heavy-slot: класс)' "$PUSH_LOG" \
        | grep -vE '://|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{ print substr($0, 1, 260) }'
    echo '```'
    [ -n "$EVIDENCE" ] && { echo; cat "$EVIDENCE"; }
    return 0
}
if [ "${#ISSUES[@]}" -gt 0 ]; then
    body="$BASE.dod.md"
    if ! dod_body "$F_PUSH" > "$body"; then F_DOD="skip"; F_WHY="$(cat "$body")"; finish 2; fi
    posted=0 failed=""
    for it in "${ISSUES[@]}"; do
        if [[ "$it" =~ ^([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)#([0-9]+)$ ]]; then r="${BASH_REMATCH[1]}" n="${BASH_REMATCH[2]}"
        elif [[ "$it" =~ ^#?([0-9]+)$ ]]; then r="$REPO" n="${BASH_REMATCH[1]}"
        else failed+=" $it(форма)"; continue; fi
        if "$GH" issue comment "$n" -R "$r" --body-file "$body" >> "$BASE.dod.out" 2>&1; then posted=$(( posted + 1 )); else failed+=" $r#$n"; fi
    done
    F_DOD="$posted/${#ISSUES[@]}"
    [ -z "$failed" ] || { F_WHY="DoD-proof не опубликован:$failed"; finish 2; }
fi

# ── 7. демон вливания ───────────────────────────────────────────────────────
if [ -n "$SUBJECT" ]; then
    bash "$AUTOLAND" start --repo "$REPO" --pr "$PR" --head "$SHA" --subject "$SUBJECT" "${LAND[@]}" > "$BASE.land.out" 2>&1
    F_LAND=$?
    sed 's/^/push-chain: autoland: /' "$BASE.land.out" >&2
    [ "$F_LAND" = 0 ] || { F_WHY="autoland start — код $F_LAND ($BASE.land.out)"; finish 2; }
fi
finish 0
