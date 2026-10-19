#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# canary.sh — проверка среды внешнего Job ОДИН раз на пачку отправок, до её раздачи.
#
# ПРЕДМЕТ (ws#1268, урок 2026-10-18 «корень A… среда Job не проверяется перед раздачей
# отправок», корни A1/A2/C — ws#1207). Серия из N отправок уходила в слоты, и каждая
# через двадцать минут хука находила одно и то же: инструмент подготовки не виден
# подпроцессу с пустым окружением, образ тестовой базы не загружен. Починка #1207 сняла
# причину, но следующую такую же ловит лишь проба до раздачи — она здесь.
#
# ФОРМА
#   canary.sh --batch <id пачки> --task <N> --repo <kacho|kaname|corelib> --ref <ревизия>
#             [--src <клон>] [--profiles <профили пачки через запятую>] [-- <доп. проба в pod>…]
#
# ЧТО СУДИТ. Один Job (run.sh): подготовка pod — та же, что у пачки (СРЕДА, МОДУЛИ,
# ВИДИМОСТЬ). Профиль Job — по профилям пачки (--profiles, по умолчанию ci-local): есть в ней
# integration — Job integration, и загрузка образа тестовой базы в предел судится (ОБРАЗЫ
# TESTCONTAINERS run.sh, иначе 75); нет — Job ci-local, образ не грузится: команде пачки он
# не нужен, и 75 медленного реестра был бы ложным отказом серии (приёмка ws#1268). Командой — шаг «# canary-begin»: jq, psql и модуль
# yaml python3 обязаны находиться подпроцессом `env -i` с PATH образа (как их зовут
# пробы и хук, собирающие окружение заново); затем — доп. проба после `--`, если дана
# (например, `go test ./deploy/… -run …` дерева kacho).
#
# РАЗ НА ПАЧКУ. Вердикт пачки — файл <каталог>/<id>.rc (каталог — KACHO_CANARY_DIR, иначе
# $WS/tmp/remote-heavy-canary): первое обращение пачки запускает Job и пишет вердикт,
# каждое следующее читает его, Job не запуская. Обращение, пришедшее при идущем Job той
# же пачки, не ждёт: 75 «идёт». Каждая строка итога несёт счёт: «Job запущен N раз,
# обращений M» — число вызовов видно в выводе. Новая пачка — новый id.
#
# КОДЫ: 0 — канарейка зелёная, раздача идёт; 75 — не выполнилось: Job красный (любой код
# run.sh, кроме 0 — с цитатой последней его строки «remote-heavy…»), инструмент не виден,
# канарейка пачки идёт; 64 — вызов неверен. Красная канарейка — серия НЕ раздаётся.
#
# KACHO_CANARY_RUN подменяет run.sh (двойник inject.sh); в остальном не используется.
set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_common="$(git -C "$SELF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
WS="$(dirname "${_common:-$SELF_DIR/../../.git}")"
RUN="${KACHO_CANARY_RUN:-$SELF_DIR/run.sh}"
DIR="${KACHO_CANARY_DIR:-$WS/tmp/remote-heavy-canary}"

say() { printf 'remote-heavy-canary: %s\n' "$*" >&2; }
usage() { say "$1"; exit 64; }

BATCH="" TASK="" REPO="" REF="" SRC="" PROFILES="ci-local"
while [ $# -gt 0 ]; do
    case "$1" in
        --batch) BATCH="${2:-}"; shift 2 ;;
        --task) TASK="${2:-}"; shift 2 ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        --ref) REF="${2:-}"; shift 2 ;;
        --src) SRC="${2:-}"; shift 2 ;;
        --profiles) PROFILES="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) usage "неизвестный аргумент «$1»" ;;
    esac
done
[[ "$BATCH" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || usage "--batch вне формы [A-Za-z0-9._-]{1,64}: «$BATCH»"
[[ "$TASK" =~ ^[1-9][0-9]*$ ]] || usage "--task — номер задачи: «$TASK»"
case "$REPO" in kacho|kaname|corelib) ;; *) usage "--repo вне kacho|kaname|corelib: «$REPO»" ;; esac
[ -n "$REF" ] || usage "--ref обязателен"
[[ "$PROFILES" =~ ^(ci-local|integration|go-race|lint)(,(ci-local|integration|go-race|lint))*$ ]] \
    || usage "--profiles — профили run.sh через запятую: «$PROFILES»"
JOBPROF=ci-local; WHY="образ команде пачки не нужен — загрузку не сужу"
case ",$PROFILES," in *,integration,*) JOBPROF=integration; WHY="в пачке integration — сужу и загрузку образа тестовой базы" ;; esac

mkdir -p "$DIR" || { say "каталог вердиктов $DIR не создан"; exit 75; }
RC_F="$DIR/$BATCH.rc"; LOG="$DIR/$BATCH.log"; CALLS="$DIR/$BATCH.calls"; JOBS="$DIR/$BATCH.jobs"
printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" >> "$CALLS"
tally() { printf 'Job запущен %d раз, обращений %d' "$(wc -l 2>/dev/null < "$JOBS" || echo 0)" "$(wc -l < "$CALLS")"; }

exec {lk}>> "$DIR/$BATCH.lock"
if ! flock -n "$lk"; then
    say "пачка $BATCH: канарейка идёт другим обращением — не жду, повтор позже (не выполнилось; $(tally))"; exit 75
fi
if [ -f "$RC_F" ]; then
    read -r rc why < "$RC_F"
    say "пачка $BATCH: вердикт уже есть — код $rc${why:+: $why} ($(tally))"; exit "$rc"
fi

# Шаг пробы — командой Job: исполняется в pod после всей подготовки. Маркеры — граница,
# по которой inject.sh исполняет его над поддельным PATH образа (HEAVY_STD_PATH).
# shellcheck disable=SC2016  # раскрывается в pod, не здесь
PROBE='# canary-begin
sp="${HEAVY_STD_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"; miss=""
env -i PATH="$sp" bash -c "command -v jq && jq --version" >/dev/null 2>&1 || miss="$miss jq"
env -i PATH="$sp" bash -c "command -v psql && psql --version" >/dev/null 2>&1 || miss="$miss psql"
env -i PATH="$sp" bash -c "python3 -c \"import yaml\"" >/dev/null 2>&1 || miss="$miss yaml"
if [ -n "$miss" ]; then echo "remote-heavy-canary: подпроцессу с пустым окружением (PATH образа) не видны:$miss" >&2; exit 3; fi
echo "remote-heavy-canary: jq, psql, yaml видны подпроцессу с пустым окружением" >&2
[ "$#" -eq 0 ] || "$@"
# canary-end'

echo "$$" >> "$JOBS"
say "пачка $BATCH: запускаю Job канарейки ($JOBPROF $REPO@$REF; профили пачки $PROFILES: $WHY) — до раздачи серии"
"$RUN" --task "$TASK" --repo "$REPO" --ref "$REF" ${SRC:+--src "$SRC"} --profile "$JOBPROF" --short canary \
    -- bash -c "$PROBE" canary "$@" > "$LOG" 2>&1
jrc=$?
if [ "$jrc" -eq 0 ]; then
    printf '0 Job канарейки зелёный\n' > "$RC_F.tmp" && mv "$RC_F.tmp" "$RC_F"
    say "пачка $BATCH: канарейка зелёная — раздача идёт ($(tally))"; exit 0
fi
# Цитата — причина пробы, если она есть, иначе последняя строка run.sh, кроме строк
# снятия ns: их trap печатает ПОСЛЕ причины (живой прогон 2026-10-19 процитировал
# «ns … снято» вместо отказа загрузки образа), а после причины пробы run.sh печатает лишь
# «команда завершилась кодом N».
cite="$(grep -E '^remote-heavy-canary: .*не видны' "$LOG" | tail -n 1)"
[ -n "$cite" ] || cite="$(grep -E '^remote-heavy: ' "$LOG" | grep -vE '^remote-heavy: (\[[^]]*\] )?ns [^ ]+ (снято|НЕ снято|оставлено)' | tail -n 1)"
[ -n "$cite" ] || cite="$(grep -v '^$' "$LOG" | tail -n 1)"
cite="${cite:-вывода нет}"
printf '75 run.sh код %s — %s\n' "$jrc" "$(printf '%s' "$cite" | tr '\n' ' ' | cut -c1-600)" > "$RC_F.tmp" && mv "$RC_F.tmp" "$RC_F"
say "пачка $BATCH: канарейка красная (run.sh код $jrc) — серия НЕ раздаётся: $cite ($(tally); журнал $LOG)"
exit 75
