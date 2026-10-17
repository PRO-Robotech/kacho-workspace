#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# install.sh — установка, сверка и снятие пользовательской службы ci-stated (ws#1151).
#
# ЗАЧЕМ. Без живой службы ci-read.sh --from-state и демон вливания читают CI живьём:
# ~8 единиц REST на чтение раз в 180 с на каждый ожидаемый PR вместо 0 из снимка.
# Службу ставят одной командой, и установка сама доказывает, что служба работает:
# первый проход демона оставил свежий снимок по КАЖДОМУ репозиторию из --repos юнита.
#
# ИСПОЛЬЗОВАНИЕ
#   install.sh [--ws <каталог>] [--wait <с>]  — поставить либо обновить и проверить
#   install.sh --check                        — сверить без правок
#   install.sh --uninstall                    — снять службу (настройки и снимки остаются)
# --ws — откуда служба исполняет демон; по умолчанию основной клон воркспейса (общий
# каталог git этой копии), а не копия под tmp/: копию снимут вместе с веткой.
# --wait — сколько ждать первого прохода, 30–540 с (по умолчанию 240).
#
# ШАГИ УСТАНОВКИ — до первой правки на диске всё судится, отказ ничего не меняет:
#   1. --repos в ExecStart юнита равен DEFAULT_REPOS демона дерева; Restart=on-failure,
#      RestartPreventExitStatus содержит 4 и не содержит 6 — иначе 2 (и при --check);
#   2. токен gh — из keyring (то же правило, что у демона), иначе 4;
#   3. остаток лимита REST и GraphQL не ниже 1500 (scripts/lib/gh-rate.sh: резерв
#      демона 1000 плюс холодный проход), иначе 3 со временем сброса;
#   4. systemd-analyze --user verify: код 0 И ни одной строки о нашем файле — verify
#      отвечает 0 и на нераспознанное значение («…, ignoring», замер 2026-10-17); путь в
#      строке verify нормализован, и временный каталог нормализуется так же (realpath -ms);
#   5. настройки 0600 (KACHO_WS), копия юнита, daemon-reload, enable, restart;
#   6. первый проход: служба active и по каждому репозиторию есть снимок с checked_at
#      не раньше перезапуска. Служба упала либо перезапускалась (NRestarts > 0) —
#      снята (disable --now) и код 1; жива, но
#      репозиторий без свежего снимка к сроку — код 3, служба оставлена работать.
# Печатается: остаток лимита до и после (лимит общий на учётку — расход прочих
# сессий входит в разность), действует ли песочница ФС (mnt-пространство MainPID
# против своего: равны — не действует, см. шапку юнита).
#
# ИСХОДЫ: 0 — установлено и первый проход подтверждён | сверка прошла; 1 — служба не
# поднялась | сверка не прошла; 2 — довод, инструмент, перечни разошлись, verify
# отказал; 3 — не выполнилось (лимит, первый проход не подтверждён к сроку); 4 —
# токен не из keyring либо keyring не ответил.
#
# ВХОД ПОДМЕНЯЕМ — ради доказательства (scripts/ci-state/install-inject.sh):
#   CI_STATED_SYSTEMCTL, CI_STATED_ANALYZE, CI_STATED_JOURNALCTL, CI_STATED_GH — команды;
#   CI_STATED_UNIT_DIR (~/.config/systemd/user), CI_STATED_ENV_DIR (~/.config/kacho),
#   CI_STATE_DIR (~/.cache/kacho-ci-state), CI_STATED_STEP — шаг ожидания, с (5).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT=ci-stated.service
SRC_UNIT="$HERE/$UNIT"
SC="${CI_STATED_SYSTEMCTL:-systemctl}"
SA="${CI_STATED_ANALYZE:-systemd-analyze}"
JC="${CI_STATED_JOURNALCTL:-journalctl}"
GH="${CI_STATED_GH:-gh}"
UNIT_DIR="${CI_STATED_UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
ENV_DIR="${CI_STATED_ENV_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/kacho}"
STATE="${CI_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state}"
STEP="${CI_STATED_STEP:-5}"
RATE_MIN=1500
FRESH=180

say() { printf 'ci-stated-install: %s\n' "$*"; }
die() { say "ОТКАЗ: $2" >&2; exit "$1"; }

MODE=install; WS=""; WAIT=240
while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE=check; shift ;;
        --uninstall) MODE=uninstall; shift ;;
        --ws) WS="${2:-}"; shift 2 ;;
        --wait) WAIT="${2:-}"; shift 2 ;;
        *) die 2 "довод «$1»: --ws <каталог>, --wait <с>, --check, --uninstall" ;;
    esac
done
[[ "$WAIT" =~ ^[0-9]+$ ]] && [ "$WAIT" -le 540 ] || die 2 "--wait «$WAIT»: целое до 540 с"
for c in python3 jq "$SC"; do command -v "$c" >/dev/null 2>&1 || die 2 "нет $c"; done
[ -r "$SRC_UNIT" ] && [ -r "$HERE/ci-stated.py" ] || die 2 "нет $SRC_UNIT либо $HERE/ci-stated.py"

if [ "$MODE" = uninstall ]; then
    "$SC" --user disable --now "$UNIT" 2>&1 | sed 's/^/  /'
    rm -f "$UNIT_DIR/$UNIT"
    "$SC" --user daemon-reload
    say "служба снята; настройки $ENV_DIR и снимки $STATE оставлены"
    exit 0
fi

# Перечень репозиториев: --repos юнита и DEFAULT_REPOS демона — одна величина.
unit_repos() { grep -m1 '^ExecStart=' "$1" | grep -oP -- '--repos[ =]\K\S+'; }
REPOS="$(unit_repos "$SRC_UNIT")"
DEF="$(grep -m1 -oP '^DEFAULT_REPOS = "\K[^"]+' "$HERE/ci-stated.py")"
[ -n "$REPOS" ] || die 2 "в ExecStart $SRC_UNIT нет --repos"
[ "$REPOS" = "$DEF" ] || die 2 "перечни разошлись: --repos юнита «$REPOS», DEFAULT_REPOS демона «$DEF»"
IFS=, read -r -a REPO_LIST <<< "$REPOS"

# Политика перезапуска юнита: keyring не ответил (код 6) — повтор, токен не из keyring
# (4) и довод (2) — без повтора. Restart — последнее присваивание; RestartPreventExitStatus
# копится по строкам, пустое присваивание сбрасывает перечень (семантика systemd).
# svc_values <ключ> <юнит> — значения ключа в секции [Service] по порядку, по строке на
# присваивание, по грамматике systemd: ведущий отступ и пробелы вокруг «=» допустимы,
# «#» и «;» в начале — комментарий, «\» в конце — продолжение строки; ключ в другой
# секции не судится (прежний разбор «^Restart=» не видел «Restart = no» и «<таб>Restart=no»).
svc_values() {
    awk -v k="$1" '
        { line = $0
          while (line ~ /\\$/) { sub(/\\$/, " ", line); if ((getline nxt) > 0) line = line nxt; else break }
          sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
          if (line == "" || line ~ /^[#;]/) next
          if (line ~ /^\[.*\]$/) { sec = line; next }
          if (sec != "[Service]") next
          i = index(line, "="); if (!i) next
          key = substr(line, 1, i - 1); sub(/[ \t]+$/, "", key)
          if (key != k) next
          val = substr(line, i + 1); sub(/^[ \t]+/, "", val); print val }' "$2"
}
RESTART="$(svc_values Restart "$SRC_UNIT" | tail -n1)"
PREVENT=" $(svc_values RestartPreventExitStatus "$SRC_UNIT" | awk '{ if ($0 == "") v = ""; else v = v " " $0 } END { print v }') "
read -r -a pv_list <<< "$PREVENT"; PV="${pv_list[*]}"   # для печати: без пробелов по краям
[ "$RESTART" = on-failure ] || die 2 "Restart=«$RESTART» в $SRC_UNIT: нужен on-failure — keyring, не ответивший при загрузке (код 6), повторяется"
[[ "$PREVENT" == *" 4 "* ]] || die 2 "RestartPreventExitStatus=«$PV» в $SRC_UNIT без 4: токен не из keyring повторялся бы вечно"
[[ "$PREVENT" != *" 6 "* ]] || die 2 "RestartPreventExitStatus=«$PV» в $SRC_UNIT с 6: keyring, не ответивший при загрузке, не повторится"

# fresh_count <репо> <не раньше, эпоха> — снимков репозитория с checked_at не раньше
fresh_count() {
    local f n=0
    for f in "$STATE/snap/${1/\//__}__"*.json; do
        [ -f "$f" ] || continue
        jq -e --argjson t "$2" '(.checked_at | type == "number") and .checked_at >= $t' "$f" >/dev/null 2>&1 && n=$((n + 1))
    done
    echo "$n"
}
# repos_fresh <не раньше> — печать «репо N»; 0 — у каждого репозитория N > 0
repos_fresh() {
    local r n bad=0
    for r in "${REPO_LIST[@]}"; do
        n="$(fresh_count "$r" "$1")"; printf '  %s: свежих снимков %s\n' "$r" "$n"
        [ "$n" -gt 0 ] || bad=1
    done
    return "$bad"
}
sandbox_fact() {
    local pid mine theirs
    pid="$("$SC" --user show -p MainPID --value "$UNIT" 2>/dev/null)"
    mine="$(readlink /proc/self/ns/mnt 2>/dev/null)"; theirs="$(readlink "/proc/${pid:-0}/ns/mnt" 2>/dev/null)"
    if [ -z "$pid" ] || [ "$pid" = 0 ] || [ -z "$theirs" ]; then say "песочница ФС: не судима (MainPID «$pid» не прочитан)"
    elif [ "$theirs" = "$mine" ]; then say "песочница ФС: НЕ действует (mnt-пространство службы равно своему $mine): запись держат страж демона и права 0700/0600"
    else say "песочница ФС: действует (mnt-пространство службы $theirs, своё $mine)"; fi
}
rate_line() { "$GH" api rate_limit -q '"REST \(.resources.core.remaining) из \(.resources.core.limit), GraphQL \(.resources.graphql.remaining) из \(.resources.graphql.limit)"' 2>/dev/null || echo "не прочитан"; }

if [ "$MODE" = check ]; then
    bad=0
    if ! cmp -s "$SRC_UNIT" "$UNIT_DIR/$UNIT"; then say "юнит $UNIT_DIR/$UNIT разошёлся с деревом $SRC_UNIT (либо его нет) — install.sh"; bad=1; fi
    ws="$(sed -n 's/^KACHO_WS=//p' "$ENV_DIR/ci-stated.env" 2>/dev/null)"
    if [ -z "$ws" ] || [ ! -r "$ws/scripts/ci-state/ci-stated.py" ]; then say "KACHO_WS «$ws» в $ENV_DIR/ci-stated.env без демона"; bad=1; fi
    st="$("$SC" --user is-active "$UNIT" 2>/dev/null)"
    [ "$st" = active ] || { say "служба: $st"; bad=1; }
    say "снимки не старше $FRESH с:"
    repos_fresh $(( $(date +%s) - FRESH )) || bad=1
    sandbox_fact
    [ "$bad" -eq 0 ] && say "сверка прошла: служба active, юнит равен дереву, по репозиториям ${#REPO_LIST[@]} из ${#REPO_LIST[@]} снимки свежие"
    exit "$bad"
fi

# ── установка ────────────────────────────────────────────────────────────────
if [ -z "$WS" ]; then
    cd_common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die 2 "$HERE не в git: назови --ws"
    WS="$(dirname "$cd_common")"
fi
WS="$(cd "$WS" 2>/dev/null && pwd)" || die 2 "--ws: каталога нет"
[ -r "$WS/scripts/ci-state/ci-stated.py" ] || die 2 "в $WS нет scripts/ci-state/ci-stated.py"
[[ "$WS" != *[[:space:]]* ]] || die 2 "путь $WS с пробелом: ExecStart его разорвёт"

ghenv=(env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN)
src="$("${ghenv[@]}" "$GH" auth status --json hosts 2>/dev/null \
    | jq -r '.hosts["github.com"][]? | select(.active) | .tokenSource' 2>/dev/null)"
[ -n "$src" ] || die 4 "keyring не ответил: gh auth status без активной учётки github.com"
[ "$src" = keyring ] || die 4 "токен не из keyring (источник «$src»): служба его не возьмёт"

# Без библиотеки лимит не проверить: это отказ инструмента (2) с причиной, а не
# «не выполнилось» (3) с пустой — gh_rate_short без подключения не определена.
[ -r "$HERE/../lib/gh-rate.sh" ] || die 2 "нет $HERE/../lib/gh-rate.sh — остаток лимита не проверить"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gh-rate.sh
. "$HERE/../lib/gh-rate.sh" || die 2 "$HERE/../lib/gh-rate.sh не подключилась — остаток лимита не проверить"
declare -F gh_rate_short >/dev/null || die 2 "в $HERE/../lib/gh-rate.sh нет gh_rate_short — остаток лимита не проверить"
if ! short="$(gh_rate_short "$GH" "$RATE_MIN")"; then die 3 "не выполнилось — $short"; fi
say "лимит до: $(rate_line)"

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-stated-install.XXXXXX")" || die 2 "mktemp"
trap 'rm -rf "$T"' EXIT
# Путь — в той форме, в какой verify печатает его в строке о юните: абсолютный,
# без «./» и «//», ссылки не раскрыты (замер systemd 259: TMPDIR вида <abs>/./x,
# <abs>//x и ./x печатался нормализованным, и буквальный поиск строку не видел).
T="$(realpath -ms -- "$T")" || die 2 "realpath $T"
cp "$SRC_UNIT" "$T/$UNIT"
"$SA" --user verify "$T/$UNIT" > "$T/verify" 2>&1; vrc=$?
# Строка о нашем юните — та, что начинается его путём либо именем: «<путь>:<строка>: …»,
# «ci-stated.service: …»; строки о чужих юнитах (spice-vdagent и т.п.) не судятся.
if [ "$vrc" -ne 0 ] || grep -qF "$T/$UNIT:" "$T/verify" || grep -qE "^([^ :]*/)?${UNIT//./\\.}:" "$T/verify"; then
    sed 's/^/  /' "$T/verify" >&2
    die 2 "systemd-analyze verify отказал юниту (код $vrc либо строка о нём)"
fi

umask 077
mkdir -p "$ENV_DIR" "$UNIT_DIR" || die 2 "не завести $ENV_DIR или $UNIT_DIR"
if ! { printf 'KACHO_WS=%s\n' "$WS" > "$ENV_DIR/ci-stated.env.$$" && chmod 600 "$ENV_DIR/ci-stated.env.$$" \
    && mv -f "$ENV_DIR/ci-stated.env.$$" "$ENV_DIR/ci-stated.env"; }; then die 2 "не записать $ENV_DIR/ci-stated.env"; fi
rm -f "$UNIT_DIR/$UNIT"   # прежняя установка могла оставить ссылку (systemctl link)
install -m 644 "$T/$UNIT" "$UNIT_DIR/$UNIT" || die 2 "не положить $UNIT_DIR/$UNIT"
T0="$(date +%s)"
if ! { "$SC" --user daemon-reload && "$SC" --user enable "$UNIT" 2>/dev/null && "$SC" --user restart "$UNIT"; }; then
    die 1 "systemctl не включил службу"
fi
say "юнит $UNIT_DIR/$UNIT, KACHO_WS=$WS; репозиториев ${#REPO_LIST[@]}: $REPOS"

deadline=$(( T0 + WAIT ))
while :; do
    st="$("$SC" --user is-active "$UNIT" 2>/dev/null)"
    nr="$("$SC" --user show -p NRestarts --value "$UNIT" 2>/dev/null)"
    if [ "$st" = failed ] || [ "$st" = inactive ] || { [[ "$nr" =~ ^[0-9]+$ ]] && [ "$nr" -gt 0 ]; }; then
        "$JC" --user -u "$UNIT" -n 20 --no-pager 2>/dev/null | sed 's/^/  /'
        "$SC" --user disable --now "$UNIT" >/dev/null 2>&1
        die 1 "служба не поднялась ($st, перезапусков ${nr:-?}): снята disable --now, журнал выше"
    fi
    if [ "$st" = active ] && repos_fresh "$T0" > "$T/fresh"; then break; fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        cat "$T/fresh"
        "$JC" --user -u "$UNIT" --since "@$T0" --no-pager 2>/dev/null | grep -E 'не прошёл|ОТКАЗ' | tail -5 | sed 's/^/  /'
        die 3 "не выполнилось: за $WAIT с служба «$st», не у каждого репозитория свежий снимок (открытых PR нет либо опрос не прошёл); служба оставлена работать — install.sh --check"
    fi
    sleep "$STEP"
done
cat "$T/fresh"
sandbox_fact
say "лимит после: $(rate_line) (лимит общий на учётку)"
say "установлено: служба active, первый проход подтверждён по репозиториям ${#REPO_LIST[@]} из ${#REPO_LIST[@]} за $(( $(date +%s) - T0 )) с"
