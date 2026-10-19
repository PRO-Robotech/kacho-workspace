#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# gh-twin.sh — двойник `gh api` для проб ci-read.sh и демона состояния (ws#1006, ws#1113).
# Один на обе пробы (scripts/ci-read-inject.sh, scripts/ci-state/inject.sh): вторая
# копия двойника разошлась бы с первой молча.
#
# Путь (последний довод) → файл в каталоге $CI_READ_FX; файла нет — 404.
# Страницы — как у площадки: <файл>.p2 рядом — вторая страница; без --paginate
# отдаётся только первая, с ним — обе подряд (поток JSON, как печатает gh).
# Аннотации: annotations.<id>.json — для проверки <id>; файла нет — ЖИВАЯ форма по
# заключению проверки <id> из check-runs.json (+ .p2), как отдаёт площадка (снимок
# kaname, голова f11cbe7, 2026-10-12; ws#1019, N1 check-verifier): у failure —
# аннотация failure с ПУСТЫМ title и message «Process completed with exit code 1.»,
# у cancelled — «The operation was canceled.», у завершённой не skipped — notice
# раннера; у skipped — []. Проверки с таким id нет — 404, как у площадки.
#
# УСЛОВНОЕ ЧТЕНИЕ (ws#1113) — форма живого gh 2.100 (замер 2026-10-16, ветка main
# kacho-workspace): `-i` печатает строку статуса, заголовки с CRLF и пустую строку,
# затем тело; на `If-None-Match` с совпавшим ETag — «HTTP/2.0 304 Not Modified» без
# тела, в stderr «gh: HTTP 304», код 1. ETag двойника — md5 тела: то же тело — тот же
# ETag, другое — другой, ложного 304 не бывает.
#
# Файл на ревизии (`contents/<путь>?ref=`) — wf/<путь> каталога случая (ws#1216).
# GHLOG — файл: каждая вызванная команда дописывается строкой (счёт вызовов gh пробой).
[ -z "${GHLOG:-}" ] || printf '%s\n' "$*" >> "$GHLOG"
p="${!#}"
pg=0; inc=0; inm=""
prev=""
for a in "$@"; do
    case "$a" in
        --paginate) pg=1 ;;
        -i|--include) inc=1 ;;
    esac
    if [ "$prev" = -H ]; then case "$a" in [Ii]f-[Nn]one-[Mm]atch:*) inm="${a#*: }" ;; esac; fi
    prev="$a"
done

# GH_TWIN_NO_INCLUDE=1 — форма заглушки, не знающей `-i` (check-09): отказ, код 99
if [ "$inc" = 1 ] && [ "${GH_TWIN_NO_INCLUDE:-0}" = 1 ]; then echo "gh-stub: незнакомый путь api: $*" >&2; exit 99; fi
body="$(mktemp)"; err="$(mktemp)"
trap 'rm -f "$body" "$err"' EXIT
core() {
    case "$p" in
      repos/*/contents/*)
        # файл на ревизии: wf/<путь> случая, ответ — форма площадки (base64); нет — 404
        local wp="${p#repos/*/contents/}"; wp="${wp%%\?ref=*}"
        [ -f "$CI_READ_FX/wf/$wp" ] || { echo "gh: Not Found (HTTP 404) $p" >&2; return 1; }
        printf '{"encoding":"base64","content":"%s"}\n' "$(base64 -w0 < "$CI_READ_FX/wf/$wp")"
        return 0 ;;
      repos/*/pulls/*) f=pull.json ;;
      repos/*/commits/*/check-runs*) f=check-runs.json ;;
      repos/*/commits/*/status) f=status.json ;;
      repos/*/actions/runs*) f=runs.json ;;
      repos/*/branches/*/protection/required_status_checks) f=protection.json ;;
      repos/*/rules/branches/*) f=rules.json ;;
      repos/*/branches/*) f=branch.json ;;
      repos/*/compare/*) f=compare.json ;;
      rate_limit) f=rate_limit.json ;;
      repos/*/check-runs/*/annotations)
        id="${p#repos/*/check-runs/}"; id="${id%/annotations}"
        if [ -f "$CI_READ_FX/annotations.$id.json" ]; then f="annotations.$id.json"
        else
          c="$(cat "$CI_READ_FX/check-runs.json" "$CI_READ_FX/check-runs.json.p2" 2>/dev/null \
              | jq -rs --argjson i "$id" '[.[].check_runs[] | select(.id == $i)] | if length == 0 then "absent" else (last | "\(.status)/\(.conclusion)") end')"
          ann() { jq -cn --arg l "$1" --arg m "$2" '{path: ".github", blob_href: "", start_line: 1, start_column: null, end_line: 1, end_column: null, annotation_level: $l, title: "", message: $m, raw_details: ""}'; }
          note="$(ann notice 'runner image notice')"
          case "$c" in
            absent) echo "gh: Not Found (HTTP 404) $p" >&2; return 1 ;;
            completed/failure) printf '[%s,%s]\n' "$(ann failure 'Process completed with exit code 1.')" "$note" ;;
            completed/cancelled) printf '[%s,%s]\n' "$(ann failure 'The operation was canceled.')" "$note" ;;
            completed/skipped) echo '[]' ;;
            completed/*) printf '[%s]\n' "$note" ;;
            *) echo '[]' ;;
          esac
          return 0
        fi ;;
      *) f=none ;;
    esac
    if [ -f "$CI_READ_FX/$f.err" ]; then cat "$CI_READ_FX/$f.err" >&2; return 1; fi
    if [ "$f" = rules.json ] && [ ! -f "$CI_READ_FX/$f" ]; then echo '[]'; return 0; fi
    [ -f "$CI_READ_FX/$f" ] || { echo "gh: Not Found (HTTP 404) $p" >&2; return 1; }
    cat "$CI_READ_FX/$f"
    if [ "$pg" = 1 ] && [ -f "$CI_READ_FX/$f.p2" ]; then cat "$CI_READ_FX/$f.p2"; fi
}
core > "$body" 2> "$err"; rc=$?
[ "$inc" = 1 ] || { cat "$body"; cat "$err" >&2; exit "$rc"; }
if [ "$rc" -ne 0 ]; then
    printf 'HTTP/2.0 404 Not Found\r\nContent-Type: application/json\r\n\r\n{"message":"Not Found"}\n'
    cat "$err" >&2; exit "$rc"
fi
etag="\"$(md5sum < "$body" | cut -c1-32)\""
if [ -n "$inm" ] && [ "$inm" = "W/$etag" ]; then
    printf 'HTTP/2.0 304 Not Modified\r\nEtag: W/%s\r\n\r\n' "$etag"
    echo 'gh: HTTP 304' >&2; exit 1
fi
printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nEtag: W/%s\r\n\r\n' "$etag"
cat "$body"
