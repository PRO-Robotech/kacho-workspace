#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# pod.sh <вход> <доводы…> — сторона Job внешнего маршрута читателей (ws#1365); зовёт её
# scripts/remote-reader.sh через heavy-slot.sh (ведомость PORTABLE), каталог — rr с входами.
#
# Исполняет вход здесь (KACHO_REMOTE_READER_POD=1 — route.sh не уводит его второй раз),
# GitHub — снятым машиной (replay-gh.sh рядом), реестр — tmp/ этого клона. Печатает:
#   remote-reader-<вид> <номер> <base64 до 76 знаков>   вид: out, err, miss, tar
#   remote-reader-size <вид> <байт>                     для каждого вида, и пустого
#   remote-reader-rc <код входа>                        последней строкой
# tar — новые файлы реестра (kaname-imports/<отпечаток>.json), записанные входом.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPP="$(cd "$HERE/../.." && pwd)"
RR="$PWD"
entry="${1:-}"; [ $# -gt 0 ] && shift
case "$entry" in scripts/stand-report.sh|scripts/pr-body.sh) ;; *) echo "remote-reader-rc 64"; exit 64 ;; esac
export KACHO_REMOTE_READER_POD=1 STAND_REPORT_GH="$HERE/replay-gh.sh" RITUAL_GH="$HERE/replay-gh.sh"
export REMOTE_READER_GH="$RR/gh"
unset LANDING_PRECHECK_WS RITUAL_LEDGER_CLONES RITUAL_REPO_DIR
if [ -f "$RR/env" ]; then IFS= read -r rel < "$RR/env"; export RITUAL_REPO_DIR="$TOPP/$rel"; fi
reg="$TOPP/tmp/operator-stand-registry"
box="$(mktemp -d)"
trap 'rm -rf -- "$box"' EXIT
(cd "$reg" 2> /dev/null && find . -type f | sort) > "$box/before"
: > "$RR/gh/misses"
# Копия expect (@checkout:<bundle>) — клон bundle: голова отсоединена, ветки и origin/* — как
# у копии машины, origin — её адрес; правок вне коммита у клона нет по построению.
args=(); k=0
for a in "$@"; do
    case "$a" in
        @checkout:in/*.bundle)
            k=$(( k + 1 )); co="$box/checkout-$k"; b="$RR/${a#@checkout:}"
            git init -q "$co" &&
                git -C "$co" fetch -q --update-head-ok "$b" 'refs/heads/*:refs/heads/*' 'refs/remotes/*:refs/remotes/*' &&
                git -C "$co" fetch -q "$b" HEAD && git -C "$co" checkout -q --detach FETCH_HEAD &&
                git -C "$co" remote add origin "$(cat "${b%.bundle}.url")" || { echo "remote-reader-rc 69"; exit 69; }
            a="$co" ;;
    esac
    args+=("$a")
done
bash "$TOPP/$entry" "${args[@]}" > "$box/out" 2> "$box/err"
rc=$?
(cd "$reg" 2> /dev/null && find . -type f | sort) > "$box/after"
: > "$box/tar"
mapfile -t new < <(comm -13 "$box/before" "$box/after" | sed 's#^\./##')
[ "${#new[@]}" -eq 0 ] || tar -cf "$box/tar" -C "$reg" -- "${new[@]}"
cp -- "$RR/gh/misses" "$box/miss"
for kind in out err miss tar; do
    base64 -w 76 < "$box/$kind" | awk -v k="$kind" '{print "remote-reader-" k " " NR " " $0}'
    printf 'remote-reader-size %s %s\n' "$kind" "$(wc -c < "$box/$kind")"
done
printf 'remote-reader-rc %s\n' "$rc"
exit "$rc"
