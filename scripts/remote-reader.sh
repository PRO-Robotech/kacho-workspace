#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# remote-reader.sh — python-читатель воркспейса с машины владельца исполняется Job-ом внешнего
# кластера (ws#1365, вариант (б) решения диспетчера; владелец 2026-10-22: машина — не для прогонов).
#
# ФОРМА
#   remote-reader.sh scripts/stand-report.sh <доводы…>   check и ступени import-candidate,
#                                                          register-import, report
#   remote-reader.sh scripts/pr-body.sh <репо> <база> <голова>   (RITUAL_REPO_DIR — как у pr-body.sh)
# Зовут его сами входы, руками — незачем. Вход идёт ЗДЕСЬ, а не сюда, лишь там, где машины
# владельца нет либо маршрут уже пройден: pod внешнего кластера (KUBERNETES_SERVICE_HOST ставит
# kubelet), ранер конвейера (GITHUB_ACTIONS=true), сторона pod драйвера (KACHO_REMOTE_READER_POD=1 —
# ставит pod.sh; с ней же слот исполняет pod.sh на машине при недоступном кластере, как владелец
# разрешил). ГРАНИЦА: эти переменные, выставленные на машине руками, маршрут обходят — держится
# вниманием, как и прямой `python3 kaname-stand.py` (в строке команды его отказывает heavy-guard ws#1301).
#
# КАК. Job исполняет КОММИТ (scripts/remote-heavy/run.sh, профиль ws), а входы читателя — файлы
# машины, ответы GitHub (токена в pod нет) и реестр принятых импортов. Поэтому:
#   1. копия: связанный worktree того же коммита, что у копии входа (правки scripts/ вне
#      коммита — отказ 64: Job исполнил бы не их);
#   2. входы: каждый довод — существующий файл — копируется в rr/in, довод заменяется путём
#      от rr; в JSON-входе строка — абсолютный путь к файлу — тоже (пакет импорта, отзывы);
#      каталог доводом — 64. Реестр tmp/operator-stand-registry машины — в tmp/ копии;
#   3. GitHub: ответы снимает здесь `gh` (на машине он разрешён), pod отдаёт их читателю
#      через STAND_REPORT_GH и RITUAL_GH (scripts/remote-reader/replay-gh.sh). Снимается
#      надмножество по плану читателя: hosted kaname — workflow, коммит, прогоны, задания,
#      журналы заданий; pr-body — задачи с номерами из сообщений диапазона и комментарии.
#      Чего нет в снятом — промах: читатель отказывает, pod называет вызов, здесь он
#      снимается (только GET) и прогон повторяется, всего не больше ROUNDS раз;
#   4. коммит копии (локальный, не публикуется), `heavy-slot.sh suite -- bash
#      ../scripts/remote-reader/pod.sh …` из rr — ведомость PORTABLE слота;
#   5. вывод: pod печатает stdout, stderr, промахи и новые файлы реестра base64 строками
#      с номером; повтор строк при переподключении потока снимается по номеру, пропуск
#      номера либо размер не тот — 70. Новые файлы реестра ложатся в реестр машины, уже
#      существующий иной — 70 (save_new судьи не перезаписывает).
# КОДЫ: код читателя; 64 — вызов неверен; 70 — поток вывода либо реестр не сходятся;
# прочие коды слота (69, 74, 75, 77) — его, «не выполнилось»: строки кода читателя нет.
# Копия и её каталог снимаются при любом исходе; журнал Job — tmp/remote-reader/<метка>.log
# основного клона — остаётся лишь на отказе.
# ГРАНИЦА: expect не идёт (его копия головы ещё не опубликована — доставки каталога нет) —
# решение диспетчера ws#1365 его не называет; ступени операторов — тоже.
set -uo pipefail
ROUNDS=3
say() { printf 'remote-reader: %s\n' "$*" >&2; }
die() { local c="$1"; shift; say "$*"; exit "$c"; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || die 64 "$HERE — не копия git воркспейса"
ENTRY="${1:-}"; [ $# -gt 0 ] && shift
case "$ENTRY" in scripts/stand-report.sh|scripts/pr-body.sh) ;; *) die 64 "вход «$ENTRY» вне перечня (scripts/stand-report.sh, scripts/pr-body.sh)" ;; esac
[ -z "$(git -C "$TOP" status --porcelain --untracked-files=no -- scripts)" ] ||
    die 64 "в $TOP правки scripts/ вне коммита — Job исполнил бы коммит, а не их: закоммить и повтори"

branch_task() { local b; b="$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null)" && [[ "$b" =~ ^([1-9][0-9]*) ]] && printf '%s' "${BASH_REMATCH[1]}"; }
TASK="${KACHO_TASK:-}"
[ -n "$TASK" ] || TASK="$(branch_task "$PWD")" || TASK=""
[ -n "$TASK" ] || TASK="$(branch_task "$TOP")" || TASK=""
[ -n "$TASK" ] || TASK="$(branch_task "${RITUAL_REPO_DIR:-/nonexistent}")" || TASK=""
[[ "$TASK" =~ ^[1-9][0-9]*$ ]] || die 64 "номер задачи для ns Job не установить: KACHO_TASK=<N> либо ветка <N>-… (каталог, копия входа, RITUAL_REPO_DIR)"

COMMON="$(git -C "$TOP" rev-parse --path-format=absolute --git-common-dir)"
WSROOT="$(dirname "$COMMON")"
# Реестр — тот, что открыл бы судья на машине (operator-stand.py registry()).
RSRC="${LANDING_PRECHECK_WS:-$HERE}"
RROOT="$(git -C "$RSRC" rev-parse --show-toplevel 2>/dev/null)" || die 64 "привязка реестра «$RSRC» — не копия git"
REG="$(dirname "$(git -C "$RROOT" rev-parse --path-format=absolute --git-common-dir)")/tmp/operator-stand-registry"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
BOX="$WSROOT/tmp/remote-reader/$STAMP"
WT="$BOX/wt"; RR="$WT/rr"; LOG="$WSROOT/tmp/remote-reader/$STAMP.log"
mkdir -p "$BOX" || die 69 "каталог $BOX не создан"
cleanup() {
    git -C "$TOP" worktree remove --force "$WT" >/dev/null 2>&1
    rm -rf -- "$BOX"
}
trap cleanup EXIT
git -C "$TOP" worktree add -q --detach "$WT" HEAD 2>/dev/null || die 69 "копия $WT не создана"
mkdir -p "$RR/in" "$RR/gh" && : > "$RR/gh/index.jsonl"

N=0
ship_plain() {  # ship_plain <файл> — копия в rr/in, печатает путь от rr
    N=$(( N + 1 ))
    local dst="in/$N-$(basename -- "$1")"
    cp -- "$1" "$RR/$dst" || return 1
    printf '%s' "$dst"
}
ship() {  # ship <файл> — то же, и в JSON-входе абсолютные пути к файлам машины — путями от rr
    local dst p q tmp
    dst="$(ship_plain "$1")" || return 1
    if jq -e . "$RR/$dst" > /dev/null 2>&1; then
        while IFS= read -r p; do
            [ -f "$p" ] || continue
            q="$(ship_plain "$p")" || return 1
            tmp="$RR/$dst.tmp"
            jq --arg a "$p" --arg b "$q" 'walk(if type == "string" and . == $a then $b else . end)' "$RR/$dst" > "$tmp" &&
                mv -- "$tmp" "$RR/$dst" || return 1
        done < <(jq -r '[.. | strings | select(startswith("/"))] | unique[]' "$RR/$dst")
    fi
    printf '%s' "$dst"
}

ORIG=("$@")
ARGS=(); prev=""
for a in "$@"; do
    [ -d "$a" ] && die 64 "довод «$a» — каталог: Job-у он не переносится"
    if [ -f "$a" ]; then
        # Пути внутри JSON переносятся лишь у пакета импорта и перечня отзывов: ожидаемое и
        # отчёт судья сверяет отпечатком содержимого, и правка их строк сменила бы его.
        case "$prev" in --packet|--hosted-reviews) a="$(ship "$a")" ;; *) a="$(ship_plain "$a")" ;; esac ||
            die 69 "вход «$a» не скопирован"
    fi
    ARGS+=("$a"); prev="$a"
done
[ -d "$REG" ] && { mkdir -p "$WT/tmp/operator-stand-registry" && cp -R -- "$REG/." "$WT/tmp/operator-stand-registry/"; }

declare -A GOT=()
LAST=""
gh_fetch() {  # gh_fetch <доводы gh> — ответ и код в rr/gh, строка указателя; повтор не снимается
    local key rc
    key="$(jq -cn '$ARGS.positional' --args "$@")"
    if [ -n "${GOT[$key]:-}" ]; then LAST="${GOT[$key]#* }"; return "${GOT[$key]%% *}"; fi
    LAST="gh/$(( ${#GOT[@]} + 1 ))"
    gh "$@" > "$RR/$LAST" 2> /dev/null; rc=$?
    GOT[$key]="$rc $LAST"
    jq -cn --argjson argv "$key" --arg out "$LAST" --argjson rc "$rc" '{argv: $argv, rc: $rc, out: $out}' >> "$RR/gh/index.jsonl"
    return "$rc"
}
gh_pages() {  # gh_pages <поле|-> <путь без per_page> <доводы gh перед путём…> — страницы до неполной
    local field="$1" path="$2" sep='?' page=1 n
    case "$path" in *\?*) sep='&' ;; esac
    while [ "$page" -le 100 ]; do
        gh_fetch "${@:3}" "$path${sep}per_page=100&page=$page" || return 1
        n="$(jq -r --arg f "$field" 'if $f == "-" then length else (.[$f] // [] | length) end' "$RR/$LAST" 2>/dev/null)" || return 1
        [ "${n:-0}" -ge 100 ] || return 0
        page=$(( page + 1 ))
    done
}

opt() {  # opt <имя> — значение довода --имя из исходных доводов
    local want="$1" prev="" a
    for a in "${ORIG[@]}"; do [ "$prev" = "$want" ] && { printf '%s' "$a"; return 0; }; prev="$a"; done
    return 1
}

plan_kaname_hosted() {  # ответы GitHub для hosted-ступени kaname (report без --external-only, check полного)
    local exp events repo head branch file event key id attempt
    exp="$(opt --expected || opt --expect)" || return 0
    [ "$(jq -r '.repo // empty' "$exp" 2>/dev/null)" = PRO-Robotech/kaname ] || return 0
    printf '%s\n' "${ORIG[@]}" | grep -qx -- --external-only && return 0
    case "${ORIG[0]:-}" in
        report) events="$(opt --events)" || return 0; events="$(cat -- "$events")" ;;
        import-candidate|register-import|expect) return 0 ;;
        check) events="$(jq -c '.events // {}' "${ORIG[1]}" 2>/dev/null)" || return 0 ;;
        *) events="$(jq -c '.events // {}' "${ORIG[0]}" 2>/dev/null)" || return 0 ;;
    esac
    repo=PRO-Robotech/kaname; head="$(jq -r .head "$exp")"; branch="$(jq -r '.ref | ltrimstr("refs/heads/") | @uri' "$exp")"
    while IFS=$'\t' read -r file event; do
        gh_fetch api "repos/$repo/contents/.github/workflows/$file?ref=$head"
        gh_fetch api "repos/$repo/git/commits/$head"
        gh_pages workflow_runs "repos/$repo/actions/workflows/$file/runs?event=$event&head_sha=$head&branch=$branch" api || continue
        while IFS=$'\t' read -r id attempt; do
            gh_pages jobs "repos/$repo/actions/runs/$id/attempts/$attempt/jobs" api || continue
            while IFS= read -r key; do
                gh_fetch api --allow-escape-sequences "repos/$repo/actions/jobs/$key/logs"
            done < <(jq -r --arg p "repos/$repo/actions/runs/$id/attempts/$attempt/jobs?" \
                        'select(.argv[1] | startswith($p)) | .out' "$RR/gh/index.jsonl" |
                     while IFS= read -r o; do jq -r '.jobs[]?.id' "$RR/$o" 2> /dev/null; done)
        done < <(jq -r --arg p "repos/$repo/actions/workflows/$file/runs?" \
                    'select(.argv[1] | startswith($p)) | .out' "$RR/gh/index.jsonl" |
                 while IFS= read -r o; do
                     jq -r --arg h "$head" '.workflow_runs[]? | select(.head_sha == $h) | "\(.id)\t\(.run_attempt)"' "$RR/$o" 2> /dev/null
                 done | sort -u)
    done < <(jq -r --argjson ev "$events" '.definitions | to_entries[] | select(.value.executor == "github-hosted")
                | [(.value.workflow_job | split(":")[0]), ($ev[.key] // empty)] | select(length == 2) | @tsv' "$exp" | sort -u)
}

plan_pr_body() {  # задачи номеров из сообщений диапазона (надмножество) и комментарии задач репозитория запроса
    local repo="${ORIG[0]:-}" base="${ORIG[1]:-}" head="${ORIG[2]:-}" rrd="${RITUAL_REPO_DIR:-$PWD}" n r trunks
    trunks="$(awk -F'\t' '!/^[[:space:]]*#/ && NF {print $1}' "$TOP/scripts/ci-read-expected.tsv" 2>/dev/null | sort -u)"
    while IFS= read -r n; do
        if gh_fetch api --method GET "repos/$repo/issues/$n"; then
            gh_pages - "repos/$repo/issues/$n/comments" api --method GET
        else
            for r in $trunks; do [ "$r" = "$repo" ] || gh_fetch api --method GET "repos/$r/issues/$n"; done
        fi
    done < <(git -C "$rrd" log --format=%B "$base..$head" 2>/dev/null | grep -oE '#[0-9]+' | tr -d '#' | sort -un)
}

# Копия pr-body: ws — сам клон Job, продукт — project/<имя> его клонов; голова — на origin.
if [ "$ENTRY" = scripts/pr-body.sh ]; then
    RRD="${RITUAL_REPO_DIR:-$PWD}"
    url="$(git -C "$RRD" remote get-url origin 2>/dev/null)" || die 64 "RITUAL_REPO_DIR «$RRD» — не копия git с origin"
    name="${url%.git}"; name="${name##*/}"
    case "$name" in
        kacho-workspace) printf '.\n' > "$RR/env" ;;
        kacho|kaname|corelib) printf 'project/%s\n' "$name" > "$RR/env" ;;
        *) die 64 "копия «$name»: клона его в Job нет (kacho-workspace, kacho, kaname, corelib)" ;;
    esac
    [ -n "$(git -C "$RRD" branch -r --contains "${3:-}" 2>/dev/null)" ] ||
        die 64 "голова «${3:-}» не на origin копии $RRD — клон Job её не увидит: отправь ветку и повтори"
fi
[ "$ENTRY" = scripts/pr-body.sh ] && plan_pr_body
[ "$ENTRY" = scripts/stand-report.sh ] && plan_kaname_hosted

decode() {  # decode <вид> — поток вида из журнала: номера без пропуска, размер — объявленный
    local kind="$1" want got
    want="$(awk -v k="remote-reader-size" -v t="$kind" '$1 == k && $2 == t {print $3; exit}' "$LOG")"
    [ -n "$want" ] || return 1
    awk -v k="remote-reader-$kind" '$1 == k && !seen[$2]++ {print $2 "\t" $3}' "$LOG" | sort -n -k1,1 |
        awk -F'\t' 'BEGIN {e = 1} $1 != e {exit 3} {print $2; e++}' > "$BOX/$kind.b64" || return 1
    base64 -d < "$BOX/$kind.b64" > "$BOX/$kind" 2> /dev/null || return 1
    got="$(wc -c < "$BOX/$kind")"
    [ "$got" = "$want" ]
}

round=1
while :; do
    git -C "$WT" add -A -f rr && { [ ! -d "$WT/tmp/operator-stand-registry" ] || git -C "$WT" add -A -f tmp/operator-stand-registry; } ||
        die 69 "входы читателя в $WT не добавлены"
    git -C "$WT" commit -q --allow-empty -m "#$TASK remote-reader: входы читателя (не публикуется)" ||
        die 69 "коммит входов в $WT не записан"
    ( cd "$RR" && KACHO_TASK="$TASK" bash "$WT/scripts/heavy-slot.sh" --wait 120 suite -- \
        bash ../scripts/remote-reader/pod.sh "$ENTRY" "${ARGS[@]}" ) > "$LOG" 2>&1
    hrc=$?
    rc="$(awk '$1 == "remote-reader-rc" {print $2}' "$LOG" | tail -n 1)"
    if ! [[ "$rc" =~ ^[0-9]+$ ]]; then
        say "строки кода читателя нет — Job не дошёл до читателя (код слота $hrc); журнал $LOG:"
        grep -v '^remote-reader-' "$LOG" | tail -n 20 >&2
        [ "$hrc" -ne 0 ] && exit "$hrc"; exit 69
    fi
    for k in out err miss tar; do
        : > "$BOX/$k"
        if grep -q "^remote-reader-size $k " "$LOG"; then
            decode "$k" || { say "поток «$k» вывода Job неполон либо не сходится по размеру — журнал $LOG"; exit 70; }
        fi
    done
    if [ "$rc" -ne 0 ] && [ -s "$BOX/miss" ] && [ "$round" -lt "$ROUNDS" ]; then
        fetched=0
        while IFS= read -r key; do
            if jq -e 'index("--input") or (index("--method") as $i | $i != null and .[$i + 1] != "GET")' <<< "$key" > /dev/null; then
                say "промах записи в GitHub не снимается: $key"; continue
            fi
            mapfile -t argv < <(jq -r '.[]' <<< "$key")
            gh_fetch "${argv[@]}"; fetched=$(( fetched + 1 ))
        done < "$BOX/miss"
        if [ "$fetched" -gt 0 ]; then
            say "промахов GitHub $fetched — сняты, прогон $(( round + 1 )) из $ROUNDS"
            round=$(( round + 1 )); continue
        fi
    fi
    break
done
cat -- "$BOX/err" >&2
cat -- "$BOX/out"
if [ -s "$BOX/tar" ]; then
    mkdir -p "$REG"
    tar -tf "$BOX/tar" | grep -qv '^\(\./\)\?kaname-imports/[0-9a-f]\{64\}\.json$\|^\(\./\)\?kaname-imports/\?$\|^\./$' &&
        { say "файлы реестра вне kaname-imports/<64 hex>.json — не приняты; журнал $LOG"; exit 70; }
    mkdir -p "$BOX/reg" && tar -xf "$BOX/tar" -C "$BOX/reg" ||
        { say "файлы реестра из Job не распакованы"; exit 70; }
    while IFS= read -r f; do
        rel="${f#"$BOX/reg/"}"
        if [ -e "$REG/$rel" ]; then
            cmp -s -- "$f" "$REG/$rel" || { say "реестр: $rel уже есть и другой — не перезаписан"; exit 70; }
        else
            mkdir -p "$(dirname -- "$REG/$rel")" && cp -- "$f" "$REG/$rel" || { say "реестр: $rel не записан"; exit 70; }
        fi
    done < <(find "$BOX/reg" -type f)
fi
[ "$rc" -eq 0 ] && rm -f -- "$LOG" || say "код читателя $rc; журнал Job — $LOG"
exit "$rc"
