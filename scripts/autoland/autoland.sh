#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# autoland.sh — отсоединённый демон вливания одного запроса (ws#1147).
#
# ЗАЧЕМ. Решение владельца 2026-10-17: новый флоу, часть 1 — детерминированное ядро
# вместо агентов-ожидателей. Замер 17.10: git-operator и ci-watcher тратят десятки
# заходов на ожидание CI (no-wait-guard запрещает паузу ≥ 300 с, метка ci-watcher —
# 9 мин), а вливание по правилу «ci-read 0 → merge-readiness 0 → landing-precheck 0 →
# gh pr merge --merge --match-head-commit» механическое: суждения в нём нет. Здесь
# это правило — код, а ждёт процесс вне агента; агент читает исход одним шагом.
#
# ИСПОЛЬЗОВАНИЕ
#   autoland.sh start --repo <владелец/имя> --pr <N> --head <sha40>
#                     --subject "#<M> merge #<N>: <суть>"
#                     [--stand-report <отчёт JSON> --stand-expect <ожидаемое JSON>]
#                     [--reviews <вердикты JSON>] [--allow <КОД,КОД…>]
#                     [--timeout <с | Nm | Nh>] [--poll <с>] [--void-limit <N>]
#       — проверяет доводы, отсоединяет демон (setsid, новый сеанс) и СРАЗУ печатает
#         строки «pid», «журнал», «state»; код 0 — демон запущен, 2 — довод не тот,
#         3 — этот PR уже ведёт другой демон (замок), 4 — копия демона старше ствола
#         либо это не установлено (ниже «КОПИЯ ДЕМОНА»), демон не запущен.
#   autoland.sh status <файл .state>
#       — печатает исход; код: 0 merged · 1 red · 2 void или демон умер · 3 идёт ·
#         4 stale-base · 5 head-moved · 6 timeout. Идущий в очереди — второй строкой
#         «очередь: позиция K из M (впереди: <репо>#<N>…)», счёт по живым билетам.
#   autoland.sh run …  — тело демона (те же доводы), его зовёт start; пробы зовут его
#         в переднем плане.
#
# --subject — заголовок коммита слияния формы правила ветки `#<M> merge #<N>: <суть>`
# (N — этот PR; ws#1029: без --subject хостинг берёт заголовок PR, и правило ветки краснит).
# --allow — коды причин landing-precheck (строки REASON<TAB><код>), которые выдал
# диспетчер: код 1 landing-precheck, все причины которого в списке, вливанию не мешает.
# На ci-read и merge-readiness допуск не действует. --timeout — предел ожидания,
# по умолчанию 3 ч; --poll — пауза между чтениями CI, по умолчанию 180 с;
# --void-limit — сколько раз подряд гейт может не вынести вердикта (код 2, кроме
# лимита площадки), по умолчанию 3.
#
# ОЧЕРЕДЬ НА БАЗУ (ws#1263). Замер 2026-10-18..19: 26 stale-base на 22 PR (34 % запусков) —
# демоны одной базы шли параллельно, посадка первого делала базу второго устаревшей.
# Теперь демон после первого чтения запроса встаёт в очередь (репозиторий без учёта
# регистра, база без приставки refs/heads/): билет $DIR/queue/<владелец>__<имя>__<sha1 базы
# 12>/<номер>.<имя .state>.t — «pid starttime <репо>#<N> <голова 12>», номер — счётчик под
# flock. Черёд — ни одного живого билета впереди и flock на .turn.lock очереди; держится
# до исхода. Живой билет — pid есть И его starttime (/proc/<pid>/stat, поле 22) тот же:
# мёртвый либо переиспользованный pid — билет снимается тем, кто его увидел, строкой в
# журнал. Пока ждёт: локально раз в AUTOLAND_QUEUE_POLL с (5), запрос и ci-read — раз в
# --poll: влит, закрыт, голова ушла, CI красный — исход сразу, не дожидаясь черёда.
# ГРАНИЦА: демон прежней версии (без билета) очереди не виден — он доживает свой
# --timeout; смена базы запроса после постановки очередь не меняет; SIGKILL демона посреди
# гейта либо отправки догона ловушек не исполняет — осиротевший дочерний процесс (timeout
# гейта, обёртка отправки) держит унаследованные дескрипторы замка запроса и .turn.lock, и
# следующий демон той же базы ждёт черёда до его конца: не дольше AUTOLAND_GATE_TIMEOUT
# (900 с) либо AUTOLAND_PUSH_TIMEOUT (3600 с); билет мёртвого pid снимается как обычно.
# ДОГОН БАЗЫ — ТОЛЬКО при запуске без --reviews, --stand-report и --stand-expect (так демон
# зовёт цепочка посадок, tmp/autoland/chains/chain.sh). С любым из них вердикты привязаны к
# голове — REVIEW-STALE у landing-precheck.sh, STAND-REPORT-STALE и STAND-EXPECT-STALE у
# stand-report.sh: догон сдвинул бы голову, снял бы их и потратил бы круг CI (опыт cv
# ws#1263: догон отправлен, затем red REVIEW-STALE). Потому с ними базу демон не догоняет:
# ci-read 4 — в очереди и в черёд — исход stale-base, как до ws#1263; ветка не трогается.
# Без этих доводов — с получением черёда и на ci-read 4: в первом клоне репозитория (как у снятия)
# fetch базы и ветки, `git rev-list --count <голова>..origin/<база>`; 0 — дальше; иначе в
# копии очереди (worktree $DIR/queue/…/wt, отделённая голова) `git merge --no-ff` базы с заголовком
# «#<задача ветки> merge <база>: догон базы перед вливанием #<N>», отправка
# `git push origin HEAD:refs/heads/<ветка>` через `heavy-slot.sh --wait 300 ci-local --` — полный
# хук отправки, без форсирующих флагов; удалась — когда голова ветки на origin стала новой
# (код отправки — лишь при отказе: 141 после хука и есть снятый простоем ssh). Новая голова —
# --head дальше: окно головы заново, CI ждётся на ней. Не более AUTOLAND_CATCHUP_LIMIT (2)
# догонов. Исходы: конфликт слияния — stale-base «конфликт: <файлы>» (слияние снято, копия
# снята); клона нет — stale-base с причиной ci-read и «клона нет»; ветка ушла во время
# догона — head-moved; хук отказал — red; слот занят (74, 75) — ожидание без счёта VOID;
# fetch, 69, 76, 77, 124 и «код 0, а голова не новая» — «не выполнилось» счётом.
#
# ЧТО ДЕЛАЕТ — по кругу, пока не наступит исход или предел:
#   1. запрос (`gh api repos/<репо>/pulls/<N>`, GET): закрыт без вливания — red
#      PR-NOT-OPEN; влит этой головой — merged; голова ≠ --head — head-moved; до ПЕРВОГО
#      совпадения в пределах AUTOLAND_HEAD_SYNC с от старта (по умолчанию 30) — повтор
#      чтения раз в AUTOLAND_HEAD_SYNC_POLL с (3): сразу после push площадка ещё отдаёт
#      прежнюю голову (урок c33f9e84, ws#1227); после совпадения расхождение — сразу;
#   2. CI — `ci-read.sh <репо> <N> --head <sha> --from-state`: ответ из снимка демона
#      состояния ws#1113 (scripts/ci-state/ci-stated.py) без вызовов gh, иначе ci-read
#      читает живьём сам. 0 — дальше; 1 — red; 4 — stale-base; 3 (идёт) и 5 (черновик,
#      целевой зелёный) — ждать; 2 — «не выполнилось», повтор. Между чтениями демон
#      ждёт строки демона состояния в его FIFO (wait/<владелец>__<имя>__<N>.fifo) не
#      дольше --poll: смена кода будит сразу, без опроса;
#   3. `merge-readiness.sh <репо> <N>`: 0 — дальше; 1 — red; 2 — повтор;
#   4. `landing-precheck.sh <репо> <N> [--reviews] [--stand-report --stand-expect]`:
#      судимая им голова (строка CENSUS «<репо>#<N> голова <12 hex>») ≠ --head —
#      head-moved, строки нет — «не выполнилось»; 0 — дальше; 1 — причины вне --allow
#      дают red, причина с пустым кодом не допускается никогда, только допущенные —
#      дальше; 2 — повтор;
#   ГОЛОВА. --head принимает лишь ci-read; landing-precheck сверяется по своей строке
#      CENSUS (первые 12 знаков), merge-readiness голову на основном пути не печатает —
#      его голова сверяется только чтением запроса до ci-read и после landing-precheck;
#      последняя граница — --match-head-commit хостинга;
#   5. запрос снова: голова та же — вливание ОДНОЙ командой
#      `gh pr merge <N> -R <репо> --merge --match-head-commit <sha> --subject <…>
#      --body "" --delete-branch` (способ — с сервера, сквош и rebase там выключены);
#      хостинг отказал, а голова ушла — head-moved;
#   6. снятие влитой ветки коммитным предикатом (git-operator.md §«Вливание и снятие»,
#      `git-issues.md#gi-prune-commit-predicate`): во всех клонах репозитория запроса
#      (воркспейс и project/*, чей origin — этот репозиторий) — fetch --prune; ветка
#      снимается, только если её голова РАВНА влитой либо её предок, а влитая — предок
#      origin/<база>; копия (worktree) — `git worktree remove` лишь при пустом
#      `status --porcelain` и без процессов в ней: cwd либо открытый файл внутри копии (/proc,
#      свои процессы учётки) — копия и ветка остаются, в .state «оставлено: процессы <pid…>»
#      (ws#1244: снята копия, где шли 6 процессов integration); origin — `--delete-branch`, оставшуюся — `git push origin
#      --delete` под замком interim; перепись `branch-audit.sh` до и после — в журнал;
#   7. догон основного клона (ws#1200): запрос в `main` репозитория, чей origin у
#      основного клона воркспейса (каталог, чей `.git` = `git rev-parse --git-common-dir`),
#      влит — `git fetch origin main` (предел AUTOLAND_FF_FETCH_TIMEOUT, без запросов
#      пароля и ssh) и `git merge --ff-only -q origin/main` в нём;
#      исполнители берут $WS/scripts оттуда. Отказ ff (пересечение с локальной правкой —
#      перечнем файлов, свои коммиты, выписана не main) — строкой в журнал и в исход
#      merged, ошибкой вливания не считается; ни stash, ни reset.
# КОПИЯ ДЕМОНА (ws#1228). Демон исполняет копию скрипта, снятую при start из дерева, где
# скрипт лежит. 2026-10-18 основной клон 8 ч стоял до ws#1200, и все демоны тех часов
# исполняли копию без догона клона — механизм не сработал ни разу, даже на вливании себя.
# Поэтому start сверяет дерево скрипта со стволом: `main-clone-lag.sh --own <дерево> --
# scripts/autoland/ scripts/main-clone-lag.sh`; отставание либо «не установлено» — код 4
# с N и командой догона, демон не запущен. Отказ, а не копия из origin/main: start и демон
# одной версии, и правка в копии судится своей же пробой (inject.sh, сцена start-stale).
# Гейты — рецептом «ЗАПУСК» шапки landing-precheck.sh, вырезанным по меткам из
# origin/main воркспейса (тем же способом, что у шаблона волны): каталог scripts/ —
# целиком из origin/main, не из рабочей копии; сбой подготовки — код 2.
#
# ИСХОД — первая строка .state, первое слово — исход:
#   running <фаза> — идёт;
#   merged <sha коммита слияния> снятие: …[; основной клон: <было> → <стало> | ff отказ — …];
#   red <гейт> код <n>: <строки REASON дословно через « | »>;
#   stale-base <строки REASON ci-read дословно либо причина догона> — базу догнать не вышло
#        либо догон не положен (вердикты привязаны к голове: «догона нет: …»);
#   head-moved <ожидалась> <стала>;
#   timeout <предел>; последнее: <последний вердикт>;
#   void <гейт> код <n> <k> раз подряд: <строки VOID дословно> — «не выполнилось»
#        (тем же счётом — запрос, который площадка не отдала --void-limit раз подряд)
#        (testing-verdict: не зелёное и не красное), а также остановка сигналом и
#        занятый замок.
#
# ЧЕГО НЕ ДЕЛАЕТ. Не чинит, не разрешает конфликт догона (stale-base — наружу), не
# переводит черновик в готовый, не применяет форсирующих флагов ни к вливанию, ни
# к отправке, ни к снятию копии, и не обходит хуки (держит scripts/autoland/inject.sh,
# раздел «статика»). Ожидание живёт в отсоединённом процессе: в вызове агента цикла
# нет, и no-wait-guard команду старта пропускает (там же, раздел «страж»).
#
# ВХОД ПОДМЕНЯЕМ — ради доказательства (scripts/autoland/inject.sh):
#   AUTOLAND_GH      — вместо `gh`;
#   AUTOLAND_GATES   — каталог с ci-read.sh, merge-readiness.sh, landing-precheck.sh,
#                      branch-audit.sh вместо рецепта «ЗАПУСК» из origin/main;
#   AUTOLAND_WS      — воркспейс (по умолчанию — основной клон того, где лежит скрипт);
#   AUTOLAND_TOOLING_TREE — дерево, чья выписка сверяется со стволом при start (по
#                      умолчанию — каталог скрипта); AUTOLAND_LAG — main-clone-lag.sh;
#   AUTOLAND_DIR     — каталог .state, журналов и замков (по умолчанию $WS/tmp/autoland);
#   AUTOLAND_CLONES  — клоны для снятия и догона через «:» (заданная пустой — ни одного);
#   AUTOLAND_PUSH    — вместо `heavy-slot.sh --wait 300 ci-local --` перед `git push` догона;
#   AUTOLAND_PUSH_TIMEOUT — предел отправки догона, с (по умолчанию 3600);
#   AUTOLAND_QUEUE_POLL — пауза локальной сверки очереди, с (по умолчанию 5);
#   AUTOLAND_CATCHUP_LIMIT — догонов базы за жизнь демона (по умолчанию 2);
#   AUTOLAND_GATE_TIMEOUT — предел одного гейта, с (по умолчанию 900);
#   AUTOLAND_FF_FETCH_TIMEOUT — предел fetch догона основного клона, с (по умолчанию 8);
#   AUTOLAND_INTERIM_LOCK — замок отправок (по умолчанию ~/.cache/heavy-slots/interim.lock);
#   CI_STATE_DIR     — каталог демона состояния (его FIFO), как у ci-read.sh.
set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
GH="${AUTOLAND_GH:-gh}"
GATE_TIMEOUT="${AUTOLAND_GATE_TIMEOUT:-900}"
HEAD_SYNC="${AUTOLAND_HEAD_SYNC:-30}"; HEAD_SYNC_POLL="${AUTOLAND_HEAD_SYNC_POLL:-3}"
FF_FETCH_TIMEOUT="${AUTOLAND_FF_FETCH_TIMEOUT:-8}"
INTERIM_LOCK="${AUTOLAND_INTERIM_LOCK:-$HOME/.cache/heavy-slots/interim.lock}"
QUEUE_POLL="${AUTOLAND_QUEUE_POLL:-5}"; CATCHUP_LIMIT="${AUTOLAND_CATCHUP_LIMIT:-2}"
PUSH_TIMEOUT="${AUTOLAND_PUSH_TIMEOUT:-3600}"

die() { printf 'autoland: ОТКАЗ — %s\n' "$1" >&2; exit "${2:-2}"; }

ws_root() {
    if [ -n "${AUTOLAND_WS:-}" ]; then (cd "$AUTOLAND_WS" && pwd); return; fi
    local common
    common="$(git -C "$(dirname "$SELF")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    dirname "$common"
}

seconds() {  # <с | Nm | Nh> → секунды; иначе пусто
    case "$1" in
        *[!0-9hm]* | '' | h | m) return 1 ;;
        *h) [[ "${1%h}" =~ ^[0-9]+$ ]] && echo $(( ${1%h} * 3600 )) ;;
        *m) [[ "${1%m}" =~ ^[0-9]+$ ]] && echo $(( ${1%m} * 60 )) ;;
        *) [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" ;;
    esac
}

REPO=""; PR=""; HEAD=""; SUBJECT=""; STAND_REPORT=""; STAND_EXPECT=""; REVIEWS=""
ALLOW=""; TIMEOUT=10800; POLL=180; VOID_LIMIT=3
parse_args() {
    local v
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) REPO="${2:-}"; shift 2 ;;
            --pr) PR="${2:-}"; shift 2 ;;
            --head) HEAD="${2:-}"; shift 2 ;;
            --subject) SUBJECT="${2:-}"; shift 2 ;;
            --stand-report) STAND_REPORT="${2:-}"; shift 2 ;;
            --stand-expect) STAND_EXPECT="${2:-}"; shift 2 ;;
            --reviews) REVIEWS="${2:-}"; shift 2 ;;
            --allow) ALLOW="${2:-}"; shift 2 ;;
            --timeout) v="$(seconds "${2:-}")" || die "--timeout «${2:-}» не секунды, Nm или Nh"; TIMEOUT="$v"; shift 2 ;;
            --poll) POLL="${2:-}"; shift 2 ;;
            --void-limit) VOID_LIMIT="${2:-}"; shift 2 ;;
            *) die "неизвестный довод «$1»" ;;
        esac
    done
    [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo «$REPO» не формы <владелец>/<имя>"
    [[ "$PR" =~ ^[0-9]+$ ]] || die "--pr «$PR» не номер"
    [[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || die "--head «$HEAD» не sha40"
    [[ "$SUBJECT" =~ ^#[0-9]+\ merge\ #${PR}:\ [^[:space:]] ]] \
        || die "--subject «$SUBJECT» не формы «#<M> merge #$PR: <суть>» (правило ветки, ws#1029)"
    if [ -n "$STAND_REPORT$STAND_EXPECT" ]; then
        [ -n "$STAND_REPORT" ] && [ -n "$STAND_EXPECT" ] || die "--stand-report и --stand-expect — только вместе"
        [ -r "$STAND_REPORT" ] || die "отчёт стенда «$STAND_REPORT» не читается"
        [ -r "$STAND_EXPECT" ] || die "ожидаемое стенда «$STAND_EXPECT» не читается"
        STAND_REPORT="$(readlink -f "$STAND_REPORT")"; STAND_EXPECT="$(readlink -f "$STAND_EXPECT")"
    fi
    if [ -n "$REVIEWS" ]; then
        [ -r "$REVIEWS" ] || die "вердикты ревью «$REVIEWS» не читаются"
        REVIEWS="$(readlink -f "$REVIEWS")"
    fi
    [ -z "$ALLOW" ] || [[ "$ALLOW" =~ ^[A-Z][A-Z0-9-]*(,[A-Z][A-Z0-9-]*)*$ ]] \
        || die "--allow «$ALLOW» не перечень кодов причин через запятую"
    [ "$TIMEOUT" -gt 0 ] 2>/dev/null || die "--timeout должен быть больше нуля"
    [[ "$POLL" =~ ^[0-9]+$ ]] && [ "$POLL" -ge 1 ] && [ "$POLL" -le 290 ] \
        || die "--poll «$POLL» не от 1 до 290 с"
    [[ "$VOID_LIMIT" =~ ^[0-9]+$ ]] && [ "$VOID_LIMIT" -ge 1 ] || die "--void-limit «$VOID_LIMIT» не число ≥ 1"
    [[ "$HEAD_SYNC" =~ ^[0-9]+$ ]] && [[ "$HEAD_SYNC_POLL" =~ ^[1-9][0-9]*$ ]] \
        || die "AUTOLAND_HEAD_SYNC «$HEAD_SYNC» / AUTOLAND_HEAD_SYNC_POLL «$HEAD_SYNC_POLL» не секунды"
    [[ "$QUEUE_POLL" =~ ^[1-9][0-9]*$ ]] && [[ "$CATCHUP_LIMIT" =~ ^[0-9]+$ ]] && [[ "$PUSH_TIMEOUT" =~ ^[1-9][0-9]*$ ]] \
        || die "AUTOLAND_QUEUE_POLL «$QUEUE_POLL», AUTOLAND_CATCHUP_LIMIT «$CATCHUP_LIMIT», AUTOLAND_PUSH_TIMEOUT «$PUSH_TIMEOUT» не числа"
}

paths() {
    WS="$(ws_root)" || die "воркспейс не найден (AUTOLAND_WS не задан, скрипт не в клоне)"
    RUN_DIR="${AUTOLAND_DIR:-$WS/tmp/autoland}"
    local key="${REPO%%/*}__${REPO#*/}__${PR}"
    NAME="${key}__${HEAD:0:12}"
    STATE="$RUN_DIR/$NAME.state"; LOG="$RUN_DIR/$NAME.log"; PIDF="$RUN_DIR/$NAME.pid"
    LOCK="$RUN_DIR/$key.lock"; FIFO_NAME="$key.fifo"
}

# ── очередь на базу (ws#1263) ──────────────────────────────────────────────────
norm_base() { printf '%s' "${1#refs/heads/}"; }
queue_dir() {  # <репо> <база> → каталог очереди; репозиторий — без учёта регистра
    local r="${1,,}" b; b="$(norm_base "$2")"
    printf '%s/queue/%s__%s__%s' "$RUN_DIR" "${r%%/*}" "${r#*/}" "$(printf '%s' "$b" | sha1sum | cut -c1-12)"
}
proc_start() {  # <pid> → starttime процесса (поле 22 /proc/<pid>/stat); нет процесса — код 1
    local s; s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
    s="${s##*) }"; read -r -a s <<< "$s"
    [ -n "${s[19]:-}" ] && printf '%s' "${s[19]}"
}
ticket_live() {  # <билет> — pid жив и это тот же процесс (starttime совпал)
    local pid st cur
    read -r pid st _ < "$1" 2>/dev/null || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    cur="$(proc_start "$pid")" || return 1
    [ "$cur" = "$st" ]
}
Q_POS=0; Q_LEN=0; Q_AHEAD=""; Q_PRUNED=""
queue_scan() {  # <каталог> <свой билет> <снимать мёртвые: 1|0> → Q_POS (0 — своего нет), Q_LEN, Q_AHEAD, Q_PRUNED
    local qd="$1" mine="$2" prune="$3" f who
    Q_POS=0; Q_LEN=0; Q_AHEAD=""; Q_PRUNED=""
    for f in "$qd"/[0-9]*.t; do
        [ -e "$f" ] || continue
        who="$(cut -d' ' -f3 "$f" 2>/dev/null)"
        if [ "$f" != "$mine" ] && ! ticket_live "$f"; then
            if [ "$prune" = 1 ] && rm -f "$f"; then Q_PRUNED+="${Q_PRUNED:+, }${who:-?} ($(basename "$f"))"; fi
            continue
        fi
        Q_LEN=$((Q_LEN + 1))
        if [ "$f" = "$mine" ]; then Q_POS=$Q_LEN
        elif [ "$Q_POS" -eq 0 ]; then Q_AHEAD+="${Q_AHEAD:+ }${who:-?}"; fi
    done
}

# ── status ─────────────────────────────────────────────────────────────────────
if [ "${1:-}" = status ]; then
    f="${2:-}"
    [ -r "$f" ] || { echo "autoland: .state «$f» не читается — не-выполнилось"; exit 2; }
    line="$(head -n1 "$f")"; printf '%s\n' "$line"
    case "${line%% *}" in
        merged) exit 0 ;; red) exit 1 ;; void) exit 2 ;; stale-base) exit 4 ;;
        head-moved) exit 5 ;; timeout) exit 6 ;;
        running)
            pid="$(cat "${f%.state}.pid" 2>/dev/null)"
            if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
                tf="$(cat "${f%.state}.ticket" 2>/dev/null)"
                if [ -n "$tf" ] && [ -e "$tf" ]; then
                    queue_scan "$(dirname "$tf")" "$tf" 0
                    [ "$Q_POS" -eq 0 ] || printf 'очередь: позиция %s из %s (впереди: %s)\n' "$Q_POS" "$Q_LEN" "${Q_AHEAD:-—}"
                fi
                exit 3
            fi
            echo "autoland: демон pid «${pid:-—}» не жив, а исход не записан — не-выполнилось; журнал ${f%.state}.log"
            exit 2 ;;
        *) echo "autoland: исход «${line%% *}» не из перечня — не-выполнилось"; exit 2 ;;
    esac
fi

# ── start ──────────────────────────────────────────────────────────────────────
if [ "${1:-}" = start ]; then
    shift; parse_args "$@"; paths
    command -v setsid >/dev/null 2>&1 || die "нет setsid"
    command -v flock >/dev/null 2>&1 || die "нет flock"
    { mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"; } || die "каталог «$RUN_DIR» не заводится"
    flock -n "$LOCK" true || die "PR $REPO#$PR уже ведёт другой демон (замок $LOCK)" 3
    lag_sh="${AUTOLAND_LAG:-$(dirname "$SELF")/../main-clone-lag.sh}"
    [ -r "$lag_sh" ] || die "копия демона не сверена со стволом: $lag_sh нет — демон не запущен (ws#1228)" 4
    lag="$(bash "$lag_sh" --own "${AUTOLAND_TOOLING_TREE:-$(dirname "$SELF")}" -- scripts/autoland/ scripts/main-clone-lag.sh 2>&1)" \
        || die "копия демона старше ствола либо это не установлено — демон не запущен (ws#1228): ${lag#TOOLING-LAG: }" 4
    rm -f "$STATE" "$PIDF"
    # Демон исполняет СВОЮ копию: копия, откуда его запустили, может быть снята им же.
    cp "$SELF" "$RUN_DIR/$NAME.autoland.sh" || die "копия демона не легла в «$RUN_DIR»"
    printf 'running старт\n' > "$STATE"
    # Срок демона для переписи застоя (ws#1154): до --timeout и последнего шага проверки;
    # сирота своей сессии в сроке не судится как застой.
    setsid env --default-signal=PIPE AUTOLAND_WS="$WS" \
        KACHO_DETACHED_UNTIL="$(( $(date +%s) + TIMEOUT + GATE_TIMEOUT ))" \
        bash "$RUN_DIR/$NAME.autoland.sh" run "$@" \
        >> "$LOG" 2>&1 < /dev/null &
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$PIDF" ] && break
        sleep 0.25
    done
    printf 'autoland: идёт — %s#%s @%s\n' "$REPO" "$PR" "${HEAD:0:12}"
    printf 'pid\t%s\n' "$(cat "$PIDF" 2>/dev/null || echo "$!")"
    printf 'журнал\t%s\n' "$LOG"
    printf 'state\t%s\n' "$STATE"
    printf 'исход — одним шагом: bash %s status %s\n' "$SELF" "$STATE"
    exit 0
fi

[ "${1:-}" = run ] || die "подкоманда — start, status или run"
shift; parse_args "$@"; paths

# ── run: тело демона ───────────────────────────────────────────────────────────
mkdir -p "$RUN_DIR" || exit 2
cd / || exit 2
W="$(mktemp -d "${TMPDIR:-/tmp}/autoland.XXXXXX")" || exit 2
DONE=0
BG=""; TICKET=""; QDIR=""; TURN=0
export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
state() {
    local tmp="$STATE.$$.tmp"
    printf '%s\n' "$*" > "$tmp" && mv -f "$tmp" "$STATE"
}
finish() {  # <исход> <подробность> — пишет .state и выходит кодом исхода
    local outcome="$1" rc; shift
    state "$outcome${*:+ $*}"; log "ИСХОД: $outcome${*:+ $*}"
    case "$outcome" in merged) rc=0 ;; red) rc=1 ;; stale-base) rc=4 ;; head-moved) rc=5 ;; timeout) rc=6 ;; *) rc=2 ;; esac
    DONE=1; exit "$rc"
}
cleanup() {
    local rc=$?
    if [ "$DONE" -eq 0 ]; then state "void демон оборвался кодом $rc до исхода; журнал $LOG"; fi
    [ -z "$BG" ] || kill "$BG" 2>/dev/null
    [ -z "$TICKET" ] || rm -f "$TICKET" "$RUN_DIR/$NAME.ticket"   # уход из очереди; flock черёда снимает выход
    rm -rf "$W"
    [ "$SELF" != "$RUN_DIR/$NAME.autoland.sh" ] || rm -f "$SELF"
}
trap cleanup EXIT
trap 'finish void "остановлен сигналом TERM"' TERM
trap 'finish void "остановлен сигналом INT"' INT

exec 9> "$LOCK"
flock -n 9 || { DONE=1; state "void замок $LOCK занят: PR ведёт другой демон"; exit 2; }
echo $$ > "$PIDF"
state "running старт"
log "старт: $REPO#$PR голова $HEAD; предел ${TIMEOUT} с, пауза ${POLL} с, допуск «${ALLOW:-—}»; гейты: ${AUTOLAND_GATES:-рецепт «ЗАПУСК» из origin/main $WS}"

join() { awk 'NR > 1 { printf " | " } { printf "%s", $0 } END { print "" }'; }

GATE_RC=0
gate() {  # <скрипт> <доводы…> → $W/<скрипт>.out, код в GATE_RC
    local s="$1" out="$W/$1.out" recipe; shift
    if [ -n "${AUTOLAND_GATES:-}" ]; then
        timeout "$GATE_TIMEOUT" bash "$AUTOLAND_GATES/$s" "$@" > "$out" 2>&1; GATE_RC=$?
    else
        recipe="$(git -C "$WS" fetch -q origin main 2>/dev/null \
            && git -C "$WS" show origin/main:scripts/landing-precheck.sh 2>/dev/null \
            | sed -n '/^# >>> рецепт ЗАПУСК$/,/^# <<< рецепт ЗАПУСК$/{/рецепт ЗАПУСК$/d;s/^#//;p}')"
        if [ -z "$recipe" ]; then
            printf 'VOID\tЗАПУСК: рецепт не вырезан из шапки origin/main:scripts/landing-precheck.sh «%s»\n' "$WS" > "$out"
            GATE_RC=2
        else
            WS="$WS" S="$s" TMPDIR="$W" timeout "$GATE_TIMEOUT" bash -c "$recipe" _ "$@" > "$out" 2>&1; GATE_RC=$?
        fi
    fi
    [ "$GATE_RC" -ne 124 ] || { printf 'VOID\t%s: предел %s с исчерпан\n' "$s" "$GATE_TIMEOUT" >> "$out"; GATE_RC=2; }
    log "гейт $s $*: код $GATE_RC; $(grep -m1 '^VERDICT' "$out" || tail -n1 "$out")"
}
reasons() {  # строки REASON вывода гейта дословно; строки о снимке демона — не о голове
    grep -P '^REASON\t' "$W/$1.out" | grep -vP '^REASON\t(STATE-STALE|STATE-KEY-MISMATCH)\t' | join
}
quote() {  # причины, а нет их — VOID либо хвост вывода
    local r; r="$(reasons "$1")"
    [ -n "$r" ] || r="$(grep -P '^VOID\t' "$W/$1.out" | join)"
    [ -n "$r" ] || r="$(grep -v '^[[:space:]]*$' "$W/$1.out" | tail -n3 | join)"
    printf '%s' "$r"
}

declare -A VOIDS=()
LAST="—"
void_step() {  # <ключ> <что> <текст> — «не выполнилось»: повтор; подряд VOID_LIMIT раз — исход void
    local k="$1" what="$2" q="$3"
    VOIDS[$k]=$(( ${VOIDS[$k]:-0} + 1 )); LAST="$what: $q"
    [ "${VOIDS[$k]}" -lt "$VOID_LIMIT" ] || finish void "$what ${VOIDS[$k]} раз подряд: $q"
    state "running не выполнилось (${VOIDS[$k]} из $VOID_LIMIT) — $LAST"
}
on_void() {  # <скрипт> — код 2 гейта; лимит площадки — ожидание сброса, а не VOID
    local s="$1" q; q="$(quote "$s")"
    if grep -qP '^REASON\tRATE-LIMIT\t' "$W/$s.out"; then
        LAST="$s код 2 (лимит площадки): $q"; state "running лимит площадки — $LAST"; return
    fi
    void_step "$s" "$s код $GATE_RC" "$q"
}

DEADLINE=$(( $(date +%s) + TIMEOUT ))
CI_STATE="${CI_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state}"
wait_change() {  # ждёт строки демона состояния в FIFO запроса не дольше POLL, иначе паузу
    local left t fifo="$CI_STATE/wait/$FIFO_NAME"
    left=$(( DEADLINE - $(date +%s) )); [ "$left" -gt 0 ] || return 0
    t="$POLL"; [ "$t" -le "$left" ] || t="$left"
    if [ -d "$CI_STATE/wait" ] && [ "$(stat -c '%u %a' "$CI_STATE/wait" 2>/dev/null)" = "$(id -u) 700" ]; then
        [ -p "$fifo" ] || mkfifo -m 600 "$fifo" 2>/dev/null
        if [ -p "$fifo" ]; then
            timeout "$t" head -n1 "$fifo" > "$W/fifo.line" 2>/dev/null & BG=$!; wait "$BG"; BG=""
            [ -s "$W/fifo.line" ] && log "демон состояния: $(cat "$W/fifo.line")"
            : > "$W/fifo.line"
            return 0
        fi
    fi
    sleep "$t" & BG=$!; wait "$BG"; BG=""
}

PR_ERR=""; PR_STATE=""; PR_MERGED=""; PR_HEAD=""; PR_REF=""; PR_BASE=""; PR_MSHA=""
read_pr() {
    if ! { "$GH" api "repos/$REPO/pulls/$PR" > "$W/pr.json" 2> "$W/pr.err" \
        && jq -e '(.head.sha | type == "string") and (.state | type == "string")' "$W/pr.json" > /dev/null 2>> "$W/pr.err"; }; then
        PR_ERR="$(head -c 300 "$W/pr.err" | tr '\n' ' ')"; return 1
    fi
    VOIDS[запрос]=0
    PR_STATE="$(jq -r .state "$W/pr.json")"; PR_MERGED="$(jq -r '.merged // false' "$W/pr.json")"
    PR_HEAD="$(jq -r .head.sha "$W/pr.json")"; PR_REF="$(jq -r '.head.ref // ""' "$W/pr.json")"
    PR_BASE="$(norm_base "$(jq -r '.base.ref // ""' "$W/pr.json")")"; PR_MSHA="$(jq -r '.merge_commit_sha // ""' "$W/pr.json")"
}

# ── снятие влитой ветки коммитным предикатом ───────────────────────────────────
origin_is_repo() {  # <клон> — его origin есть репозиторий запроса
    local u; u="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
    u="${u%.git}"; u="${u,,}"
    case "$u" in */"${REPO,,}" | *:"${REPO,,}") return 0 ;; esac
    return 1
}
clones() {
    if [ -n "${AUTOLAND_CLONES+x}" ]; then tr ':' '\n' <<< "$AUTOLAND_CLONES" | sed '/^$/d'; return; fi
    local c
    for c in "$WS" "$WS"/project/*; do
        [ -e "$c/.git" ] && origin_is_repo "$c" && printf '%s\n' "$c"
    done
    return 0
}
PRUNE=""
prune() {  # <ветка головы> <база>
    local br="$1" base="$2" c rh lh wt dirty removed=() kept=()
    if [ -z "$br" ] || [ "$br" = "$base" ] || [ "$br" = main ] || [ "$br" = master ]; then
        PRUNE="снятие: ветка «$br» не снимается (ствол либо база)"; return
    fi
    while IFS= read -r c; do
        if ! git -C "$c" fetch -q --prune origin 2> "$W/fetch.err"; then
            kept+=("$c: fetch не прошёл — $(head -c 200 "$W/fetch.err" | tr '\n' ' ')"); continue
        fi
        BRANCH_AUDIT_FRESH_MIN=0 BRANCH_AUDIT_KEEP="$base" gate branch-audit.sh "$c" "$br"
        if ! git -C "$c" merge-base --is-ancestor "$HEAD" "origin/$base" 2>/dev/null; then
            kept+=("$c: влитая голова ${HEAD:0:12} не предок origin/$base — ничего не снимаю"); continue
        fi
        rh="$(git -C "$c" ls-remote --heads origin "refs/heads/$br" 2>/dev/null | cut -f1)"
        if [ -n "$rh" ]; then
            if [ "$rh" = "$HEAD" ] || git -C "$c" merge-base --is-ancestor "$rh" "$HEAD" 2>/dev/null; then
                mkdir -p "$(dirname "$INTERIM_LOCK")"
                flock -w 240 "$INTERIM_LOCK" git -C "$c" push -q origin --delete "$br" > "$W/push.out" 2>&1
                if [ -z "$(git -C "$c" ls-remote --heads origin "refs/heads/$br" 2>/dev/null)" ]; then
                    removed+=("origin/$br")
                else kept+=("origin/$br: снятие не прошло — $(tail -n2 "$W/push.out" | tr '\n' ' ')"); fi
            else kept+=("origin/$br сдвинулась после вливания: ${rh:0:12} не равна и не предок ${HEAD:0:12}"); fi
        fi
        lh="$(git -C "$c" rev-parse -q --verify "refs/heads/$br" 2>/dev/null)" || lh=""
        [ -n "$lh" ] || continue
        if ! { [ "$lh" = "$HEAD" ] || git -C "$c" merge-base --is-ancestor "$lh" "$HEAD" 2>/dev/null; }; then
            kept+=("$c $br: местная голова ${lh:0:12} не равна и не предок влитой ${HEAD:0:12}"); continue
        fi
        dirty=0
        while IFS= read -r wt; do
            [ -n "$wt" ] || continue
            if [ "$wt" = "$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)" ]; then
                kept+=("$c: ветка $br выписана в основной копии клона"); dirty=1; continue
            fi
            busy="$(wt_procs "$wt")"
            if [ -n "$busy" ]; then kept+=("копия $wt: оставлено: процессы $busy"); dirty=1; continue; fi
            if [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] && git -C "$c" worktree remove "$wt" 2> "$W/wt.err"; then
                removed+=("копия $wt")
            else kept+=("копия $wt: не пуста либо не снята — $(head -c 200 "$W/wt.err" 2>/dev/null | tr '\n' ' ')"); dirty=1; fi
        done < <(git -C "$c" worktree list --porcelain | awk -v b="branch refs/heads/$br" '/^worktree /{w=substr($0, 10)} $0 == b {print w}')
        [ "$dirty" -eq 0 ] || continue
        if git -C "$c" branch -D "$br" > /dev/null 2> "$W/br.err"; then removed+=("$c $br")
        else kept+=("$c $br: $(head -c 200 "$W/br.err" | tr '\n' ' ')"); fi
        BRANCH_AUDIT_FRESH_MIN=0 BRANCH_AUDIT_KEEP="$base" gate branch-audit.sh "$c" "$br"
    done < <(clones)
    PRUNE="снятие: снято ${#removed[@]}${removed[*]:+ (${removed[*]})}, оставлено ${#kept[@]}"
    [ "${#kept[@]}" -eq 0 ] || PRUNE="$PRUNE: $(printf '%s\n' "${kept[@]}" | join)"
    log "$PRUNE"
}

# wt_procs <копия> — pid процессов, чей cwd либо открытый файл — внутри копии (ws#1244), кроме
# самого демона; чужие учётки /proc не отдают — их процессы не видны (граница).
wt_procs() {
    local d
    d="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
    { find /proc/[0-9]*/cwd -maxdepth 0 \( -lname "$d" -o -lname "$d/*" \) 2>/dev/null
      find /proc/[0-9]*/fd -mindepth 1 -maxdepth 1 \( -lname "$d" -o -lname "$d/*" \) 2>/dev/null
    } | cut -d/ -f3 | grep -vxF -e "$$" -e "$BASHPID" | sort -un | tr '\n' ' ' | sed 's/ $//'
}

# ── догон основного клона воркспейса (ws#1200) ─────────────────────────────────
SYNC=""
sync_main_clone() {  # запрос в main репозитория основного клона влит — ff основного клона
    local top common old new both
    SYNC=""
    [ "$PR_BASE" = main ] && origin_is_repo "$WS" || return 0
    top="$(cd "$WS" && pwd -P)"
    common="$(git -C "$WS" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    if [ "$common" != "$top/.git" ]; then
        SYNC="основной клон: не догоняется — $WS не основной клон (git-common-dir «${common:-—}»)"; log "$SYNC"; return 0
    fi
    if [ "$(git -C "$WS" symbolic-ref -q HEAD)" != refs/heads/main ]; then
        SYNC="основной клон: ff отказ — выписана не main ($(git -C "$WS" symbolic-ref -q --short HEAD || echo отделённая голова))"
        log "$SYNC"; return 0
    fi
    # Сеть не держит исход: предел и неинтерактивность — как у main-clone-lag.sh; влитое не становится void.
    if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
        timeout "$FF_FETCH_TIMEOUT" git -C "$WS" fetch -q origin main 2> "$W/sync.err"; then
        SYNC="основной клон: ff отказ — fetch origin main (предел $FF_FETCH_TIMEOUT с): $(head -c 200 "$W/sync.err" | tr '\n' ' ')"; log "$SYNC"; return 0
    fi
    old="$(git -C "$WS" rev-parse HEAD)"; new="$(git -C "$WS" rev-parse refs/remotes/origin/main)"
    if [ "$old" = "$new" ]; then SYNC="основной клон: на origin/main ${new:0:12}"; log "$SYNC"; return 0; fi
    if ! git -C "$WS" merge-base --is-ancestor "$old" "$new"; then
        SYNC="основной клон: ff отказ — main несёт $(git -C "$WS" rev-list --count "$new..$old") своих коммитов вне origin/main; голова ${old:0:12}"
        log "$SYNC"; return 0
    fi
    if git -C "$WS" merge --ff-only -q origin/main > "$W/sync.out" 2>&1; then
        SYNC="основной клон: ${old:0:12} → $(git -C "$WS" rev-parse HEAD | cut -c1-12) (origin/main)"; log "$SYNC"; return 0
    fi
    # Отказ ff: входящие файлы, пересекающие локальную правку (отслеживаемую и неотслеживаемую).
    both="$(comm -12 <(git -C "$WS" diff --name-only "$old" "$new" | sort -u) <({ git -C "$WS" diff --name-only HEAD; git -C "$WS" ls-files --others --exclude-standard; } | sort -u) | join)"
    SYNC="основной клон: ff отказ — пересекаются с локальной правкой: ${both:-—}; git: $(grep -v '^[[:space:]]*$' "$W/sync.out" | head -n2 | join); голова ${old:0:12}, origin/main ${new:0:12}"
    log "$SYNC"; return 0  # отказ ff — не ошибка вливания: исход остаётся merged
}

landed() {  # запрос влит — проверка родителя, снятие, догон основного клона, исход
    local note="${1:-}"
    if "$GH" api "repos/$REPO/commits/$PR_MSHA" > "$W/mc.json" 2>/dev/null \
        && jq -e --arg h "$HEAD" '[.parents[].sha] | index($h) != null' "$W/mc.json" > /dev/null 2>&1; then
        log "коммит слияния $PR_MSHA — родитель $HEAD есть"
    else
        log "коммит слияния $PR_MSHA: родитель $HEAD не подтверждён площадкой"
    fi
    prune "$PR_REF" "$PR_BASE"; sync_main_clone
    finish merged "$PR_MSHA${note:+ $note}${CU_NOTE:+; догон базы: $CU_NOTE}; $PRUNE${SYNC:+; $SYNC}"
}

# ── очередь: билет, черёд, ожидание (ws#1263) ──────────────────────────────────
enqueue() {  # билет в конец очереди (репо, база запроса)
    local seq st
    QDIR="$(queue_dir "$REPO" "$PR_BASE")"
    mkdir -p "$QDIR" || return 1
    printf '%s %s\n' "${REPO,,}" "$(norm_base "$PR_BASE")" > "$QDIR/key"
    st="$(proc_start $$)" || return 1
    seq="$( { flock -w 10 7 || exit 1; n=$(( $(cat "$QDIR/.seq" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$QDIR/.seq" && echo "$n"; } 7> "$QDIR/.seq.lock" )" \
        && [[ "$seq" =~ ^[0-9]+$ ]] || return 1
    TICKET="$QDIR/$(printf '%012d' "$seq").$NAME.t"
    printf '%s %s %s#%s %s\n' "$$" "$st" "$REPO" "$PR" "${HEAD:0:12}" > "$TICKET" || { TICKET=""; return 1; }
    printf '%s\n' "$TICKET" > "$RUN_DIR/$NAME.ticket"
    log "очередь: билет $seq — $REPO, база $(norm_base "$PR_BASE") ($QDIR)"
}
try_turn() {  # черёд: живых билетов впереди нет и flock черёда взят
    queue_scan "$QDIR" "$TICKET" 1
    [ -z "$Q_PRUNED" ] || log "очередь: сняты мёртвые билеты — $Q_PRUNED"
    if [ "$Q_POS" -eq 0 ]; then log "очередь: своего билета нет — встаю заново"; TICKET=""; enqueue || return 1; queue_scan "$QDIR" "$TICKET" 0; fi
    [ "$Q_POS" -eq 1 ] || return 1
    exec 8> "$QDIR/.turn.lock"
    flock -n 8 || { exec 8>&-; return 1; }
    TURN=1; log "очередь: черёд (в очереди $Q_LEN)"
}
queued_check() {  # в очереди: запрос и CI — исход сразу, не дожидаясь черёда
    if ! read_pr; then void_step запрос "запрос не прочитан" "$PR_ERR"; return; fi
    if [ "$PR_MERGED" = true ]; then
        [ "$PR_HEAD" = "$HEAD" ] || finish head-moved "$HEAD $PR_HEAD (влит другой головой)"
        landed "(влит не этим демоном)"
    fi
    if [ "$PR_STATE" != open ]; then finish red "запрос в очереди: REASON"$'\t'"PR-NOT-OPEN"$'\t'"состояние $PR_STATE без вливания"; fi
    if [ "$PR_HEAD" != "$HEAD" ]; then finish head-moved "$HEAD $PR_HEAD (в очереди)"; fi
    gate ci-read.sh "$REPO" "$PR" --head "$HEAD" --from-state
    case "$GATE_RC" in
        1) finish red "ci-read код 1 в очереди: $(quote ci-read.sh)" ;;
        4) [ "$PINNED" = 0 ] || finish stale-base "ci-read код 4 в очереди: $(quote ci-read.sh); $PIN_NOTE" ;&
        0 | 3 | 5) VOIDS[ci-read.sh]=0; LAST="ci-read код $GATE_RC: $(grep -m1 '^VERDICT' "$W/ci-read.sh.out")" ;;
        *) on_void ci-read.sh ;;
    esac
}
queue_turn() {  # ждёт черёда: очередь — раз в QUEUE_POLL с, запрос и CI — раз в POLL с
    local next=0 now seen=""
    while ! try_turn; do
        [ "$seen" = "$Q_POS/$Q_LEN/$Q_AHEAD" ] || { seen="$Q_POS/$Q_LEN/$Q_AHEAD"; log "очередь: позиция $Q_POS из $Q_LEN (впереди: ${Q_AHEAD:-—})"; }
        now="$(date +%s)"
        [ "$now" -lt "$DEADLINE" ] || finish timeout "предел $TIMEOUT с в очереди: позиция $Q_POS из $Q_LEN (впереди: ${Q_AHEAD:-—}); последнее: $LAST"
        if [ "$now" -ge "$next" ]; then next=$(( now + POLL )); queued_check; fi
        state "running очередь: позиция $Q_POS из $Q_LEN (впереди: ${Q_AHEAD:-—}); последнее: $LAST"
        sleep "$QUEUE_POLL" & BG=$!; wait "$BG"; BG=""
    done
}

# ── догон базы (ws#1263) ───────────────────────────────────────────────────────
CATCHUPS=0; CU_NOTE=""; CU_RC=0
cu_drop() {  # <клон> <копия> — копия догона снимается (после слияния или его снятия она чиста)
    git -C "$1" worktree remove "$2" 2> "$W/cu-wt.err" || log "догон базы: копия $2 не снята — $(head -c 200 "$W/cu-wt.err" | tr '\n' ' ')"
}
catchup() {  # <turn|stale> → CU_RC: 0 — отставания нет, дальше; 1 — круг заново; 2 — клона нет
    local mode="$1" c base n cw msg new rh rc task
    CU_RC=0; base="$(norm_base "$PR_BASE")"
    c="$(clones | head -n1)"
    if [ -z "$c" ]; then log "догон базы: клона $REPO нет — отставание не проверено"; CU_RC=2; return; fi
    if ! GIT_TERMINAL_PROMPT=0 git -C "$c" fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base" "refs/heads/$PR_REF" 2> "$W/cu.err" \
        || ! git -C "$c" cat-file -e "$HEAD^{commit}" 2>> "$W/cu.err"; then
        void_step догон "догон базы: fetch origin $base и $PR_REF в $c не дал голову ${HEAD:0:12}" "$(head -c 200 "$W/cu.err" | tr '\n' ' ')"
        CU_RC=1; wait_change; return
    fi
    n="$(git -C "$c" rev-list --count "$HEAD..refs/remotes/origin/$base")"
    if [ "$n" -eq 0 ]; then
        log "догон базы: ${HEAD:0:12} не отстаёт от origin/$base"
        [ "$mode" = stale ] || VOIDS[догон]=0
        if [ "$mode" = stale ]; then
            void_step догон "ci-read код 4, а голова ${HEAD:0:12} не отстаёт от origin/$base в $c" "$(quote ci-read.sh)"
            CU_RC=1; wait_change
        fi
        return
    fi
    [ "$CATCHUPS" -lt "$CATCHUP_LIMIT" ] \
        || finish stale-base "догон базы: предел $CATCHUP_LIMIT догонов исчерпан, голова ${HEAD:0:12} отстаёт от origin/$base на $n"
    # Копия догона — одна на очередь: догоняет лишь держатель черёда, а постоянный путь
    # сохраняет копии её TMPDIR класса ci-local (кэши хука отправки, ws#1087).
    cw="$QDIR/wt"; git -C "$c" worktree prune 2>/dev/null
    if [ -e "$cw" ]; then git -C "$c" worktree remove "$cw" 2>/dev/null || cw="$QDIR/wt.$$.$RANDOM"; fi
    if ! git -C "$c" worktree add -q --detach "$cw" "$HEAD" 2> "$W/cu.err"; then
        void_step догон "догон базы: копия в $c не заведена" "$(head -c 200 "$W/cu.err" | tr '\n' ' ')"; CU_RC=1; wait_change; return
    fi
    task="${SUBJECT%% *}"; [[ "$PR_REF" =~ ^([0-9]+)- ]] && task="#${BASH_REMATCH[1]}"
    msg="$task merge $base: догон базы перед вливанием #$PR"
    if ! git -C "$cw" merge --no-ff --no-edit -q -m "$msg" "refs/remotes/origin/$base" > "$W/cu-merge.out" 2>&1; then
        local files; files="$(git -C "$cw" diff --name-only --diff-filter=U | join)"
        git -C "$cw" merge --abort 2>/dev/null
        cu_drop "$c" "$cw"
        [ -n "$files" ] && finish stale-base "догон базы: слияние origin/$base в ${HEAD:0:12} — конфликт: $files"
        void_step догон "догон базы: слияние origin/$base не записано" "$(grep -v '^[[:space:]]*$' "$W/cu-merge.out" | tail -n2 | join)"
        CU_RC=1; wait_change; return
    fi
    new="$(git -C "$cw" rev-parse HEAD)"
    local -a push=(bash "$WS/scripts/heavy-slot.sh" --wait 300 ci-local --)
    [ -z "${AUTOLAND_PUSH:-}" ] || push=("$AUTOLAND_PUSH")
    state "running догон базы: отправка ${new:0:12} (слияние origin/$base, отставание $n)"
    ( cd "$cw" && timeout "$PUSH_TIMEOUT" "${push[@]}" git push origin "HEAD:refs/heads/$PR_REF" ) > "$W/cu-push.out" 2>&1; rc=$?
    rh="$(GIT_TERMINAL_PROMPT=0 git -C "$c" ls-remote origin "refs/heads/$PR_REF" 2>/dev/null | cut -f1)"
    cu_drop "$c" "$cw"
    log "догон базы: отправка ${new:0:12} кодом $rc; голова ветки на origin ${rh:-—}; $(tail -n2 "$W/cu-push.out" | join)"
    if [ "$rh" = "$new" ]; then
        CATCHUPS=$((CATCHUPS + 1)); VOIDS[догон]=0; VOIDS[отправка]=0
        CU_NOTE="${CU_NOTE:+$CU_NOTE, }${HEAD:0:12} → ${new:0:12}"
        log "догон базы: ${HEAD:0:12} → ${new:0:12} (origin/$base была впереди на $n)"
        HEAD="$new"; HEAD_SEEN=0; RUN_T0="$(date +%s)"
        state "running догон базы: $CU_NOTE — ожидание CI новой головы"
        CU_RC=1; return
    fi
    [ -z "$rh" ] || [ "$rh" = "$HEAD" ] || finish head-moved "$HEAD $rh (ветка ушла во время догона базы)"
    case "$rc" in
        74 | 75) LAST="догон базы: слот отправки занят (код $rc)"; state "running $LAST"; CU_RC=1; wait_change; return ;;
        0 | 69 | 76 | 77 | 124 | 141)
            void_step отправка "догон базы: отправка кодом $rc, голова ветки на origin не новая" "$(grep -v '^[[:space:]]*$' "$W/cu-push.out" | tail -n2 | join)"
            CU_RC=1; wait_change; return ;;
    esac
    finish red "догон базы: отправка ${new:0:12} отказала кодом $rc: $(grep -v '^[[:space:]]*$' "$W/cu-push.out" | tail -n3 | join)"
}

LP_ARGS=()
RUN_T0="$(date +%s)"; HEAD_SEEN=0
# Вердикты, привязанные к голове (ws#1263, ⛔ 1 приёмки): с ними догона нет — stale-base.
PINNED=0; [ -z "$REVIEWS$STAND_REPORT$STAND_EXPECT" ] || PINNED=1
PIN_NOTE="догона нет: --reviews, --stand-report, --stand-expect привязаны к голове ${HEAD:0:12} (REVIEW-STALE, STAND-REPORT-STALE, STAND-EXPECT-STALE) — догон снял бы их"
[ -z "$REVIEWS" ] || LP_ARGS+=(--reviews "$REVIEWS")
[ -z "$STAND_REPORT" ] || LP_ARGS+=(--stand-report "$STAND_REPORT" --stand-expect "$STAND_EXPECT")

while :; do
    [ "$(date +%s)" -lt "$DEADLINE" ] || finish timeout "предел $TIMEOUT с; последнее: $LAST"
    if ! read_pr; then void_step запрос "запрос не прочитан" "$PR_ERR"; wait_change; continue; fi
    if [ "$PR_MERGED" = true ]; then
        [ "$PR_HEAD" = "$HEAD" ] || finish head-moved "$HEAD $PR_HEAD (влит другой головой)"
        landed "(влит не этим демоном)"
    fi
    [ "$PR_STATE" = open ] || finish red "запрос: REASON"$'\t'"PR-NOT-OPEN"$'\t'"состояние $PR_STATE без вливания"
    if [ "$PR_HEAD" != "$HEAD" ] && [ "$HEAD_SEEN" = 0 ] && [ $(( $(date +%s) - RUN_T0 )) -lt "$HEAD_SYNC" ]; then
        log "голова запроса на площадке ${PR_HEAD:0:12}, ожидалась ${HEAD:0:12}: площадка ещё не видит отправку — повтор через $HEAD_SYNC_POLL с (предел $HEAD_SYNC с от старта)"
        sleep "$HEAD_SYNC_POLL"; continue
    fi
    [ "$PR_HEAD" = "$HEAD" ] || finish head-moved "$HEAD $PR_HEAD"
    HEAD_SEEN=1

    if [ "$TURN" = 0 ]; then  # очередь на базу, затем догон перед стартом — лишь без вердиктов о голове (ws#1263)
        if [ -z "$TICKET" ] && ! enqueue; then void_step очередь "билет очереди не заведён" "${QDIR:-—}"; wait_change; continue; fi
        queue_turn
        if [ "$PINNED" = 0 ]; then catchup turn; [ "$CU_RC" != 1 ] || continue; fi
    fi

    gate ci-read.sh "$REPO" "$PR" --head "$HEAD" --from-state
    case "$GATE_RC" in
        0) VOIDS[ci-read.sh]=0 ;;
        1) finish red "ci-read код 1: $(quote ci-read.sh)" ;;
        4) if [ "$PINNED" = 1 ]; then finish stale-base "$(quote ci-read.sh); $PIN_NOTE"; fi
           log "ci-read код 4 в черёд: база ушла мимо очереди — догон базы"; catchup stale
           [ "$CU_RC" != 2 ] || finish stale-base "$(quote ci-read.sh); догон базы невозможен: клона $REPO нет"
           continue ;;
        3 | 5) VOIDS[ci-read.sh]=0
               LAST="ci-read код $GATE_RC: $(grep -m1 '^VERDICT' "$W/ci-read.sh.out")"
               state "running ожидание CI — $LAST"; wait_change; continue ;;
        *) on_void ci-read.sh; wait_change; continue ;;
    esac

    gate merge-readiness.sh "$REPO" "$PR"
    case "$GATE_RC" in
        0) VOIDS[merge-readiness.sh]=0 ;;
        1) finish red "merge-readiness код 1: $(quote merge-readiness.sh)" ;;
        *) on_void merge-readiness.sh; wait_change; continue ;;
    esac

    gate landing-precheck.sh "$REPO" "$PR" "${LP_ARGS[@]}"
    if [ "$GATE_RC" -eq 0 ] || [ "$GATE_RC" -eq 1 ]; then
        # Голова, которую судил landing-precheck, — из его строки CENSUS «<репо>#<N> голова <12 hex>».
        lph="$(grep -m1 -oP "^CENSUS\t\Q$REPO#$PR\E голова \K[0-9a-f]{12}(?= )" "$W/landing-precheck.sh.out")"
        if [ -z "$lph" ]; then
            printf 'VOID\tlanding-precheck не напечатал судимую голову (CENSUS «%s#%s голова …»)\n' "$REPO" "$PR" >> "$W/landing-precheck.sh.out"
            GATE_RC=2
        elif [ "$lph" != "${HEAD:0:12}" ]; then
            finish head-moved "$HEAD $lph (судил landing-precheck)"
        fi
    fi
    case "$GATE_RC" in
        0) VOIDS[landing-precheck.sh]=0 ;;
        1) VOIDS[landing-precheck.sh]=0
           bad="$(grep -P '^REASON\t' "$W/landing-precheck.sh.out" \
               | awk -F'\t' -v allow=",$ALLOW," '$2 == "" || index(allow, "," $2 ",") == 0' | join)"
           all="$(reasons landing-precheck.sh)"
           [ -n "$all" ] || finish red "landing-precheck код 1 без строк REASON: $(quote landing-precheck.sh)"
           [ -z "$bad" ] || finish red "landing-precheck код 1: $bad"
           log "landing-precheck код 1 — все причины допущены диспетчером (--allow $ALLOW): $all" ;;
        *) on_void landing-precheck.sh; wait_change; continue ;;
    esac

    # Три гейта судили голову HEAD: перед вливанием она обязана быть той же.
    if ! read_pr; then void_step запрос "запрос не прочитан" "$PR_ERR"; wait_change; continue; fi
    [ "$PR_MERGED" != true ] || landed "(влит не этим демоном)"
    [ "$PR_HEAD" = "$HEAD" ] || finish head-moved "$HEAD $PR_HEAD"  # голова перед вливанием

    state "running вливание"
    "$GH" pr merge "$PR" -R "$REPO" --merge --match-head-commit "$HEAD" \
        --subject "$SUBJECT" --body "" --delete-branch > "$W/merge.out" 2>&1
    mrc=$?
    log "gh pr merge: код $mrc; $(tail -n2 "$W/merge.out" | join)"
    read_pr || read_pr || finish void "вливание: код $mrc, состояние запроса не прочитано — $PR_ERR"
    if [ "$PR_MERGED" = true ]; then
        [ "$PR_HEAD" = "$HEAD" ] || finish head-moved "$HEAD $PR_HEAD (влит другой головой)"
        landed
    fi
    [ "$PR_HEAD" = "$HEAD" ] || finish head-moved "$HEAD $PR_HEAD"
    finish red "gh pr merge код $mrc: $(grep -v '^[[:space:]]*$' "$W/merge.out" | tail -n3 | join)"
done
