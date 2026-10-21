#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# sweep-systmp.sh — снятие ПРЕЖНЕГО мусора `tmp.*` во временном каталоге системы (ws#1292).
#
# Предмет: 2026-10-21 в `/tmp` — 3558 записей `tmp.*` одного владельца, из них каталогов 2473,
# старше 28 ч — 2405, старший ~39 суток: безымянное `mktemp` прогонов, чей TMPDIR не был задан и
# чья уборка исполнилась не на каждом пути выхода. Новые прогоны наборов идут слотом с TMPDIR под
# общим каталогом слотов (класс suite, вне дерева git), перепись видит ось sys-tmp (`census.sh`); здесь — лишь накопленное.
#
#   sweep-systmp.sh [--age-h N] [--apply]
#
# По умолчанию — только ПЕРЕЧЕНЬ: «СНЯТЬ <путь>» на каждую запись, которую --apply снял бы, и
# строки «до:»/«после:» числами. Снимается запись, у которой ВСЁ сразу:
#   · имя `tmp.*` на верхнем уровне системного каталога (RESIDUE_SYSTMP, по умолчанию /tmp);
#   · владелец — этот uid (RESIDUE_UID перекрывает — инъекция: чужой владелец не снимается);
#   · не символьная ссылка (снималась бы чужая цель) — «ссылок N», остаются;
#   · сама запись и всё внутри неё не менялись дольше N часов (по умолчанию 28 — граница
#     «прошлых прогонов» из предмета) — иначе «молодых N», остаются;
#   · ни один процесс этого uid не держит в ней дескриптор, рабочий каталог или отображение
#     (/proc/<pid>/fd, cwd, maps) — иначе «ЗАНЯТ <путь> pid …», остаются.
# Снятие — `rm -rf --one-file-system`, владелец и вид перепроверяются перед каждым снятием.
#
# КОДЫ: 0 — перечень (и снятие) сошлись; 1 — часть не снялась (названа «НЕ СНЯТ»); 2 — не
# выполнилось: каталога нет либо он не читается, ключ неверен.
# ГРАНИЦА: процесс другого uid и процесс, открывший путь после переписи дескрипторов, не видны;
# путь, который прогон держит в переменной без открытого дескриптора и не трогал N часов, снимется.
set -uo pipefail
export LC_ALL=C

SYSTMP="${RESIDUE_SYSTMP:-/tmp}"
RUID="${RESIDUE_UID:-$(id -u)}"
AGE_H=28
APPLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        --age-h)
            [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || { echo "sweep: --age-h «${2:-}» — целое число часов > 0" >&2; exit 2; }
            AGE_H="$2"; shift 2 ;;
        *) echo "usage: sweep-systmp.sh [--age-h N] [--apply]" >&2; exit 2 ;;
    esac
done
[ -d "$SYSTMP" ] && [ -r "$SYSTMP" ] || { echo "sweep: каталога $SYSTMP нет либо он не читается — не выполнилось" >&2; exit 2; }
SYSTMP="$(cd "$SYSTMP" && pwd -P)"
CUT_MIN=$(( AGE_H * 60 ))

# Перепись удерживаемого: путь под SYSTMP/tmp.* в fd, cwd и maps процессов этого uid → имя записи и pid.
declare -A HELD=()
for pd in /proc/[0-9]*; do
    [ "$(stat -c %u "$pd" 2>/dev/null)" = "$(id -u)" ] || continue
    pid="${pd#/proc/}"
    while IFS= read -r tgt; do
        case "$tgt" in "$SYSTMP"/tmp.*) ;; *) continue ;; esac
        rest="${tgt#"$SYSTMP"/}"; name="${rest%%/*}"
        HELD[$name]="${HELD[$name]:-}${HELD[$name]:+,}$pid"
    done < <(
        for l in "$pd"/fd/* "$pd"/cwd; do readlink -- "$l" 2>/dev/null; done
        awk 'NF >= 6 { print $6 }' "$pd/maps" 2>/dev/null
    )
done

own=0; take=(); young=0; busy=0; links=0
while IFS= read -r -d '' p; do
    own=$((own + 1))
    name="${p##*/}"
    if [ -L "$p" ]; then links=$((links + 1)); continue; fi
    if [ -n "$(find "$p" -maxdepth 0 -mmin -"$CUT_MIN" -print -quit 2>/dev/null)" ] ||
       [ -n "$(find "$p" -mindepth 1 -mmin -"$CUT_MIN" -print -quit 2>/dev/null)" ]; then
        young=$((young + 1)); continue
    fi
    if [ -n "${HELD[$name]:-}" ]; then
        busy=$((busy + 1)); printf 'ЗАНЯТ %s pid %s\n' "$p" "$(printf '%s' "${HELD[$name]}" | tr ',' '\n' | sort -un | head -n 5 | tr '\n' ' ')"
        continue
    fi
    take+=("$p")
done < <(find "$SYSTMP" -mindepth 1 -maxdepth 1 -name 'tmp.*' -user "$RUID" -print0 2>/dev/null | sort -z)

printf 'до: своих tmp.* %d · снять %d · молодых %d · с открытым дескриптором %d · ссылок %d (каталог %s, uid %s, срок %d ч)\n' \
    "$own" "${#take[@]}" "$young" "$busy" "$links" "$SYSTMP" "$RUID" "$AGE_H"
done_n=0; miss=0
for p in "${take[@]+"${take[@]}"}"; do
    if [ -z "$APPLY" ]; then printf 'СНЯТЬ %s\n' "$p"; continue; fi
    # Перепроверка перед снятием: вид, владелец, место — всё тем же предикатом.
    if [ -L "$p" ] || [ "$(stat -c %u -- "$p" 2>/dev/null)" != "$RUID" ] || [ "${p%/*}" != "$SYSTMP" ]; then
        printf 'НЕ СНЯТ %s — запись сменилась после переписи\n' "$p"; miss=$((miss + 1)); continue
    fi
    if rm -rf --one-file-system -- "$p" 2>/dev/null && [ ! -e "$p" ]; then
        printf 'СНЯТ %s\n' "$p"; done_n=$((done_n + 1))
    else
        printf 'НЕ СНЯТ %s — rm отказал\n' "$p"; miss=$((miss + 1))
    fi
done
if [ -n "$APPLY" ]; then
    left=0
    for p in "$SYSTMP"/tmp.*; do
        { [ -e "$p" ] || [ -L "$p" ]; } && [ "$(stat -c %u -- "$p" 2>/dev/null)" = "$RUID" ] && left=$((left + 1))
    done
    printf 'после: своих tmp.* %d · снято %d · не снято %d\n' "$left" "$done_n" "$miss"
else
    printf 'после: перечень без снятия (--apply снимет %d)\n' "${#take[@]}"
fi
[ "$miss" -eq 0 ] || exit 1
exit 0
