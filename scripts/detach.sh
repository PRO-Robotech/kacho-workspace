#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# detach.sh — долгий шаг отсоединённо, исход — отдельным коротким шагом (ws#1225).
#
# ЗАЧЕМ. Норма `CLAUDE.md` «Не жди»: ни один вызов не держит ожидание дольше 10 минут.
# Уроки «ожидание-в-вызове» 18–19.10 (6 случаев): исполнитель дежурил паузами sleep в
# вызовах — no-wait-guard их отказывает, — задание называло предел паузы (270 с) и предел
# вызова (60 с) разными числами, `.rc` в пределах 10 мин был недостижим, полный хук отправки
# шёл дольше двух пауз. Форма отсоединения жила строкой в тексте стража и заданий, и каждый
# исполнитель собирал её заново. Здесь она — одна команда: пауза не нужна вовсе.
#
# ФОРМА
#   detach.sh start <каталог> [--deadline <с>] -- <команда> [доводы…]
#       — служба systemd --user `kacho-detach-<метка>` ВНЕ scope сессии (переживает её
#         перезапуск; scripts/detach-launch.sh), при недоступном systemd --user — setsid в
#         scope сессии с громким предупреждением; env --default-signal=PIPE,HUP (ws#1274), stdin /dev/null;
#         файлы <каталог>/<метка>.log, .rc (код команды, пишется атомарно по её выходу), .pid
#         .unit (имя службы) и .exit (исход службы — пишет она сам; на пути setsid их нет); метка
#         уникальна: время UTC, pid вызова, 8 знаков sha256 команды; .rc снимается до старта.
#         Печатает строку «идёт: pid N; журнал …; rc …; срок <UTC>; вид служба <юнит> | setsid
#         (не переживёт перезапуск сессии)» и строку дочитки исхода.
#         Код 0 — запущено; 64 — вызов неверен (в том числе строка `sh|bash|dash -c`, чья
#         последняя команда — echo или printf после «;», перевода строки, «||», «|» или «&»: в
#         .rc лёг бы её код, ws#1242; после «&&» — пропуск. ГРАНИЦА — не судятся: обёртки
#         перед оболочкой (`env sh -c`, `timeout … bash -c`, `setsid sh -c`), слитые флаги
#         (`bash -lc`), группа `{ …; echo; }` и подоболочка с хвостом после «}»/«)»;
#         каталог внутри рабочего дерева
#         git, где файлы шага не игнорируются: они делают копию грязной, kacho#3251);
#         69 — не запущено (нет ни службы, ни setsid; каталог не заводится; pid не записан за 5 с).
#   detach.sh status <файл .rc | .log | .pid | <журнал>.log.rc | путь без расширения>
#       — 5: ⟳ прогон недействителен — предмет (голова, правка отслеживаемого каталога
#         вызова, доводы-файлы; отпечаток .fp при старте и .fp-end при выходе команды —
#         detach_fp в detach-launch.sh) сменился за время прогона, что сменилось — названо;
#         0: команда вышла кодом 0; 1: вышла не нулём (код назван); 3: идёт; 2: не
#         выполнилось — процесса нет, а .rc нет, либо файлов шага нет; 4: внешний шаг (без
#         .pid) без .rc, журнал не держит ни один процесс — не судим как идущий. По выходу команды —
#         хвост журнала (5 строк). Живость — pid из .pid И метка DETACH_TAG в его окружении:
#         чужой процесс на переиспользованном pid «идущим» не считается; вид шага (служба
#         или setsid) на живость не влияет. Оборванный шаг (2) назван причиной: перезагрузка
#         машины (.pid старше загрузки); служба остановлена менеджером служб либо процесс
#         убит сигналом — разными фразами (запись .exit, нет её — журнал юнита); процесса нет.
#   detach.sh stop <файл шага> [--grace <с>]
#       — остановка С УБОРКОЙ (класс detach-stop-оставляет-ns, 7 случаев, урок c719d3fd): TERM
#         лишь прямым детям обёртки шага (команде), не обёртке и не группе; обёртка жива и
#         дописывает .rc, когда ловушка команды доведёт уборку. `systemctl --user stop` шлёт
#         TERM всей cgroup разом и KILL через TimeoutStopSec 90 с — ловушка remote-heavy и её
#         kubectl гибнут, ns остаются. Ждёт .rc до --grace (по умолчанию 300, предел 540 — норма
#         «Не жди») и выхода потомков с меткой шага (DETACH_TAG окружения), KILL не шлёт никогда.
#         Коды: 0 — .rc записан, потомков нет (код команды назван); 3 — TERM
#         послан, уборка дольше срока, шаг жив — исход status позже; 4 — шаг не идёт (уже вышел
#         либо оборван — сказано, что именно); 2 — файлов шага нет; 64 — вызов неверен.
# Срок (--deadline, с; по умолчанию 3600) — KACHO_DETACHED_UNTIL окружения шага: перепись
# застоя (scripts/stall-census.sh, ws#1154) сироту в сроке застоем не судит.
#
# ЧЕГО НЕ ДЕЛАЕТ: не ждёт и не опрашивает — status читает один раз. Тяжёлое (docker,
# линтер, -race, стенд) по-прежнему идёт слотом: `detach.sh start <каталог> -- $WS/scripts/
# heavy-slot.sh <класс> -- …`; очередь слота дольше 300 с — `heavy-slot.sh --enqueue`.
# Держит scripts/detach-inject.sh (исходы, уникальность, переиспользованный pid, страж,
# служба переживает снятие scope вызова — близнец setsid убит, перезагрузка названа; stop —
# ловушка команды доводит уборку, срок короче уборки — 3, вышедший шаг — 4).
set -uo pipefail
# shellcheck source=scripts/detach-launch.sh
. "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")/detach-launch.sh" || { printf 'detach: нет detach-launch.sh рядом\n' >&2; exit 69; }

say() { printf 'detach: %s\n' "$*" >&2; }
usage() { say "форма: detach.sh start <каталог> [--deadline <с>] -- <команда…> | detach.sh status <файл шага> | detach.sh stop <файл шага> [--grace <с>]"; exit 64; }

# alive <pid> <метка> — процесс жив и несёт метку шага в окружении.
alive() {
    local e; local -a env=()
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    { mapfile -d '' -t env < "/proc/$1/environ"; } 2>/dev/null || return 1
    for e in "${env[@]}"; do [ "$e" = "DETACH_TAG=$2" ] && return 0; done
    return 1
}

case "${1:-}" in
start)
    shift
    [ $# -ge 1 ] || usage
    dir="$1"; shift
    deadline=3600
    if [ "${1:-}" = --deadline ]; then
        [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || { say "--deadline «${2:-}» — не секунды"; exit 64; }
        deadline="$2"; shift 2
    fi
    [ "${1:-}" = -- ] || usage
    shift
    [ $# -ge 1 ] || { say "после «--» команды нет"; exit 64; }
    # Код шага — код ПОСЛЕДНЕЙ команды: строка оболочки (`sh|bash -c '…'`), кончающаяся echo или
    # printf, пишет в .rc код echo — 0 при любом исходе (ws#1242: «…; echo rc=$?» дважды за полосу).
    # Судится лишь САМА команда шага (sh|bash … -c '<строка>'), не доводы внутри неё: шаг
    # цепочки (push-then.sh … -- sh -c 'printf …') — код цепочки, а не строки.
    prev=""; case "${1##*/}" in sh | bash | dash) ;; *) prev=stop ;; esac
    for a in "$@"; do
        [ "$prev" = stop ] && break
        [ "$prev" != -c ] && [ "$prev" != "" ] && [ "${prev:0:1}" != - ] && [ "$prev" != "$1" ] && break
        if [ "$prev" = -c ]; then
            s="${a%"${a##*[![:space:];]}"}"; last="${s##*[;&|$'\n']}"; pre="${s%"$last"}"
            last="${last#"${last%%[![:space:]({]*}"}"
            # Маскирует код лишь echo после «;», перевода строки, «||», «|», «&»: после «&&»
            # echo идёт только при коде 0 — код .rc верен; строка из одного echo — его код.
            if [ -n "$pre" ] && [ "${pre: -2}" != "&&" ] && [[ "$last" =~ ^(echo|printf)([[:space:]]|$) ]]; then
                say "строка оболочки кончается «${last:0:60}» — в .rc лёг бы код echo, а не прогона. Код сохрани и верни: «…; rc=\$?; echo …; exit \$rc»"
                exit 64
            fi
        fi
        prev="$a"
    done
    # `heavy-slot.sh --enqueue` сам отсоединяется и выходит сразу: внутри службы шага его ожидатель
    # гибнет с ней, .rc не появляется (урок 239bf44d) — форма одна, без detach.sh.
    for a in "$@"; do case "$a" in --enqueue) case " $* " in *heavy-slot*) say "heavy-slot.sh --enqueue сам отсоединяется и печатает свой .rc — зови его напрямую, без detach.sh start"; exit 64 ;; esac ;; esac; done
    # Входы шага (ws#1476, урок 6846b2ee и возврат check-verifier 2026-10-28: путь к предмету не
    # проверен — прогон впустую). Судятся лишь ПОЗИЦИИ входа, не любое слово с расширением (выходной
    # путь `cp a.yaml out.yaml` — не вход): первое слово с «/» (и первое после «--» слота);
    # сценарий интерпретатора bash|sh|dash|python3|python (первый не-флаг, -c и -m — без сценария);
    # makefile у make (-f X, -fX, --file=X, --makefile=X; с -C D — от D). Нет — 64. После слова
    # heavy-slot (слот исполняет коммит головы) вход внутри копии — ещё и в коммите без правки;
    # абсолютный путь и симлинк — по пути и по цели в копии.
    dx_in() {  # <путь> <под слотом 0|1>
        [ -e "$1" ] || { say "вход «$1» не существует (от $PWD) — прогон ушёл бы впустую; проверь путь до start"; exit 64; }
        [ "$2" = 1 ] || return 0
        local top p r; top="$(git rev-parse --show-toplevel 2> /dev/null)" || return 0
        for p in "$1" "$(readlink -f -- "$1")"; do
            r="$(realpath -m -s --relative-to="$top" -- "$p")"; case "$r" in .. | ../*) continue ;; esac
            { git -C "$top" ls-files --error-unmatch -- "$r" && git -C "$top" diff --quiet HEAD -- "$r"; } > /dev/null 2>&1 ||
                { say "вход «$1» не в коммите головы — слот исполняет коммит, правка до него не дойдёт; закоммить до start"; exit 64; }
        done
    }
    slot=0; first=1; interp=0; mk=0; next=""; mdir=""; mfs=()
    for a in "$@"; do
        if [ -n "$next" ]; then [ "$next" = C ] && mdir="$a"; [ "$next" = f ] && mfs+=("$a"); next=""; continue; fi
        if [ "$first" = 1 ]; then first=0; [[ "$a" == */* ]] && dx_in "$a" "$slot"
        elif [ "$interp" = 1 ]; then case "$a" in -c | -m | -[!-]*c*) interp=0 ;; -*) ;; *) interp=0; dx_in "$a" "$slot" ;; esac
        elif [ "$mk" = 1 ]; then
            case "$a" in -f | --file | --makefile) next=f ;; --file=* | --makefile=*) mfs+=("${a#*=}") ;; -f?*) mfs+=("${a#-f}") ;;
                -C | --directory) next=C ;; --directory=*) mdir="${a#*=}" ;; -C?*) mdir="${a#-C}" ;; esac
        fi
        case "${a##*/}" in bash | sh | dash | python3 | python) interp=1 ;; make | gmake) mk=1 ;; *heavy-slot*) slot=1 ;; --) [ "$slot" = 1 ] && first=1 ;; esac
    done
    for m in "${mfs[@]}"; do case "$m" in /*) dx_in "$m" "$slot" ;; *) dx_in "${mdir:+$mdir/}$m" "$slot" ;; esac; done
    mkdir -p "$dir" 2>/dev/null || { say "каталог «$dir» не заводится — не запущено"; exit 69; }
    dir="$(cd "$dir" && pwd -P)"
    ign=1
    for x in x.log x.rc x.pid x.rc.tmp x.unit x.exit x.fp x.fp-end; do git -C "$dir" check-ignore -q "$dir/$x" 2>/dev/null || ign=0; done
    if [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && [ "$ign" = 0 ]; then
        say "каталог «$dir» — внутри рабочего дерева git, и файлы шага там не игнорируются: копия стала бы грязной (kacho#3251). Каталог шагов — вне копии, например \$WS/tmp/<полоса>/"
        exit 64
    fi
    tag="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(printf '%s\0' "$@" | sha256sum | cut -c1-8)"
    base="$dir/$tag"
    rm -f "$base.rc" "$base.pid" "$base.unit" "$base.exit" "$base.fp" "$base.fp-end"
    detach_fp "$@" > "$base.fp"
    until_ts=$(( $(date +%s) + deadline ))
    unit="kacho-detach-$tag"
    # Внутренняя оболочка пишет СВОЙ pid (обёртка и env исполняются через exec — pid тот же;
    # $! вызова был бы pid обёртки setsid-пути), затем отпечаток предмета при выходе команды
    # (detach_fp — тот же, что при старте) и код команды — атомарно, ПОСЛЕ отпечатка.
    # shellcheck disable=SC2016
    detach_launch "$unit" "$base.log" -- env --default-signal=PIPE,HUP DETACH_TAG="$tag" KACHO_DETACHED_UNTIL="$until_ts" \
        DETACH_SELF="$(readlink -f -- "${BASH_SOURCE[0]}")" \
        bash -c 'echo $$ > "$0.pid"; "$@"; rc=$?; bash "$DETACH_SELF" fp "$@" > "$0.fp-end" 2> /dev/null; printf "%s\n" "$rc" > "$0.rc.tmp" && mv -f "$0.rc.tmp" "$0.rc"' "$base" "$@" \
        || { say "${DETACH_WARN:-не запущено}"; exit 69; }
    if [ "$DETACH_MODE" = unit ]; then printf '%s\n' "$unit" > "$base.unit"; kind="служба $unit"
    else kind="setsid (не переживёт перезапуск сессии)"; fi
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$base.pid" ] && break
        sleep 0.25
    done
    [ -s "$base.pid" ] || { say "pid шага не записан за 5 с — не запущено либо вышел сразу; журнал $base.log"; exit 69; }
    printf 'идёт: pid %s; журнал %s; rc %s; срок %s; вид %s\n' "$(cat "$base.pid")" "$base.log" "$base.rc" \
        "$(date -u -d "@$until_ts" +%Y-%m-%dT%H:%M:%SZ)" "$kind"
    printf 'исход — одним шагом: bash %s status %s\n' "$(readlink -f -- "${BASH_SOURCE[0]}")" "$base.rc"
    exit 0 ;;
status)
    [ $# -eq 2 ] || usage
    base="${2%.rc}"; base="${base%.log}"; base="${base%.pid}"
    tag="${base##*/}"; rcf="$base.rc"; logf="$base.log"
    # Форма вызывающих «<журнал>.log.rc» (код рядом с журналом, ws#1242: chain-3296-3292-r2.sh) —
    # .rc берётся тем именем, которым назван; «<журнал>.log» при таком .rc — тоже.
    case "$2" in
        *.log.rc) rcf="$2"; logf="${2%.rc}" ;;
        *.log) [ -f "$2.rc" ] && [ ! -f "$rcf" ] && { rcf="$2.rc"; logf="$2"; } ;;
    esac
    if [ -f "$rcf" ]; then
        code="$(head -n 1 "$rcf")"
        [[ "$code" =~ ^[0-9]+$ ]] || { echo "не выполнилось: .rc «$code» не код — журнал $logf"; exit 2; }
        echo "исход: код $code; журнал $logf"
        tail -n 5 "$logf" 2>/dev/null | sed 's/^/  | /'
        # Предмет сменился за время прогона — исход не о проверяемом (⟳, не зелёное и не красное).
        if [ -f "$base.fp" ] && [ -f "$base.fp-end" ] && ! cmp -s "$base.fp" "$base.fp-end"; then
            what="$(diff "$base.fp" "$base.fp-end" | sed -n 's/^> \(голова\|правка отслеживаемого\|файл [^ ]*\).*/\1/p' | paste -sd ',' - | sed 's/,/, /g')"
            echo "⟳ прогон недействителен: за время прогона сменились ${what:-доводы-файлы} — код $code не о проверяемом; перезапусти на неизменном предмете (правка — после исхода либо в другой копии)"
            exit 5
        fi
        [ "$code" -eq 0 ] && exit 0
        exit 1
    fi
    pid="$(cat "$base.pid" 2>/dev/null)"
    if alive "$pid" "$tag"; then
        u="$(cat "$base.unit" 2>/dev/null)"
        echo "идёт: pid $pid; журнал $logf${u:+; служба $u}"
        exit 3
    fi
    # Внешний шаг (не detach.sh start: ни .pid, ни метки DETACH_TAG) — живость по журналу:
    # процесс, держащий его открытым (/proc/*/fd), — «идёт»; не держит никто — «не судим как
    # идущий» (4): цепочка, дописывающая журнал наездами, его не держит (ws#1242, check-verifier).
    if [ ! -e "$base.pid" ] && [ -e "$logf" ]; then
        lp="$(readlink -f -- "$logf")"; lg="$(printf '%s' "$lp" | sed 's/[][*?\\]/\\&/g')"
        # Один find по всем fd (не readlink на каждый: тысячи вызовов — минуты).
        holder="$(find /proc/[0-9]*/fd -maxdepth 1 -lname "$lg" -print -quit 2>/dev/null)"
        holder="${holder#/proc/}"; holder="${holder%%/*}"
        if [ -n "$holder" ]; then echo "идёт: внешний шаг без .pid — журнал держит pid $holder; журнал $logf"; exit 3; fi
        echo "не судим как идущий: внешний шаг без .pid и метки, журнал $logf не держит ни один процесс — .rc нет; исход — status позже либо по журналу"
        exit 4
    fi
    if [ -e "$base.pid" ] || [ -e "$logf" ]; then
        echo "не выполнилось: процесса ${pid:-—} нет, а .rc нет — шаг оборван: $(detach_gone_reason "$base.pid" "$base.unit"); журнал $logf"
    else
        echo "не выполнилось: файлов шага $rcf, $logf, $base.pid нет"
    fi
    exit 2 ;;
stop)
    [ $# -eq 2 ] || [ $# -eq 4 ] || usage
    grace=300
    if [ $# -eq 4 ]; then
        [ "$3" = --grace ] || usage
        [[ "$4" =~ ^[1-9][0-9]*$ ]] && [ "$4" -le 540 ] || { say "--grace «$4» — не секунды 1…540 (норма «Не жди»: вызов не дольше 10 мин)"; exit 64; }
        grace="$4"
    fi
    base="${2%.rc}"; base="${base%.log}"; base="${base%.pid}"; tag="${base##*/}"
    if [ -f "$base.rc" ]; then echo "не идёт: шаг уже вышел кодом $(head -n 1 "$base.rc") — останавливать нечего; журнал $base.log"; exit 4; fi
    [ -e "$base.pid" ] || { echo "не выполнилось: файла $base.pid нет — шаг не запускался detach.sh start"; exit 2; }
    pid="$(cat "$base.pid" 2>/dev/null)"
    if ! alive "$pid" "$tag"; then
        echo "не идёт: процесса ${pid:-—} нет, а .rc нет — шаг уже оборван: $(detach_gone_reason "$base.pid" "$base.unit"); уборку его ловушки проверь отдельно (residue-census)"
        exit 4
    fi
    # Дети обёртки — команда шага (`"$@"` её bash -c); обёртку не трогаем: она пишет .rc.
    kids="$(cat /proc/"$pid"/task/*/children 2>/dev/null | tr -s ' \n' ' ')"
    kids="${kids# }"; kids="${kids% }"
    if [ -n "$kids" ]; then
        # shellcheck disable=SC2086 # перечень pid — словами
        kill -TERM $kids 2>/dev/null
        echo "TERM → команда шага (pid $kids), обёртка $pid жива; уборка — до $grace с"
    else
        echo "у обёртки $pid детей нет — команда уже вышла, обёртка пишет .rc; ожидание до $grace с"
    fi
    end=$(( $(date +%s) + grace ))
    while [ ! -f "$base.rc" ] && [ "$(date +%s)" -lt "$end" ] && alive "$pid" "$tag"; do sleep 1; done
    # Потомки команды несут метку шага в окружении: .rc пишется при выходе команды, а её внук
    # (git push под push-then.sh, kubectl ловушки) может доживать дольше — ждать и их (ws#1432:
    # «отправка уже идёт» после stop).
    tagged() { grep -lzx "DETACH_TAG=$tag" /proc/[0-9]*/environ 2> /dev/null | cut -d/ -f3 | grep -vx "$$" | paste -sd ' ' -; }
    while [ -f "$base.rc" ] && [ -n "$(tagged)" ] && [ "$(date +%s)" -lt "$end" ]; do sleep 1; done
    if [ -f "$base.rc" ] && [ -n "$(tagged)" ]; then
        echo "идёт: команда вышла кодом $(head -n 1 "$base.rc"), но потомки шага живы дольше $grace с (pid $(tagged)) — KILL не послан; исход — bash $(readlink -f -- "${BASH_SOURCE[0]}") stop $base.rc позже"
        exit 3
    fi
    if [ -f "$base.rc" ]; then
        echo "остановлен: команда вышла кодом $(head -n 1 "$base.rc") после TERM, потомков с меткой шага 0 — уборка дошла до конца; журнал $base.log"
        tail -n 5 "$base.log" 2>/dev/null | sed 's/^/  | /'
        exit 0
    fi
    if alive "$pid" "$tag"; then
        echo "идёт: TERM послан, уборка дольше $grace с — шаг жив, KILL не послан; исход — bash $(readlink -f -- "${BASH_SOURCE[0]}") status $base.rc"
        exit 3
    fi
    echo "не выполнилось: обёртка $pid вышла без .rc — $(detach_gone_reason "$base.pid" "$base.unit"); журнал $base.log"
    exit 2 ;;
fp)
    # Внутренняя форма обёртки шага: отпечаток предмета при выходе команды (detach_fp).
    shift; detach_fp "$@"; exit 0 ;;
*) usage ;;
esac
