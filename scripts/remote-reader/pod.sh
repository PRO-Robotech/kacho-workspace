#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# pod.sh <вход> <доводы…> — сторона Job внешнего маршрута читателей (ws#1365); зовёт её
# scripts/remote-reader.sh через heavy-slot.sh (ведомость PORTABLE), каталог — rr с входами.
#
# Исполняет вход здесь (KACHO_REMOTE_READER_POD=1 — вход не уводит себя второй раз),
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
case "$entry" in
    scripts/stand-report.sh|scripts/pr-body.sh|scripts/landing-precheck.sh|scripts/ci-read.sh|scripts/branch-audit.sh) ;;
    *) echo "remote-reader-rc 64"; exit 64 ;;
esac
export KACHO_REMOTE_READER_POD=1 STAND_REPORT_GH="$HERE/replay-gh.sh" RITUAL_GH="$HERE/replay-gh.sh"
export REMOTE_READER_GH="$RR/gh"
unset LANDING_PRECHECK_WS RITUAL_LEDGER_CLONES RITUAL_REPO_DIR
if [ -f "$RR/env" ]; then IFS= read -r rel < "$RR/env"; export RITUAL_REPO_DIR="$TOPP/$rel"; fi
reg="$TOPP/tmp/operator-stand-registry"
# Клон Job (remote-heavy/run.sh: init + bundle) origin не несёт, а судья реестра (operator-stand.py
# registry()) сверяет адрес origin воркспейса: заводится адресом копии машины (rr/origin.url).
if ! git -C "$TOPP" remote get-url origin > /dev/null 2>&1 && [ -s "$RR/origin.url" ]; then
    git -C "$TOPP" remote add origin "$(head -n 1 "$RR/origin.url")" || { echo "remote-reader-rc 69"; exit 69; }
fi
box="$(mktemp -d)"
trap 'rm -rf -- "$box"' EXIT
# gh первым в PATH — снятый машиной: предпроверка зовёт gh сама и через merge-readiness и ci-read;
# ci-read — без условного чтения (`-i`), его ключи машина снимает простой формой.
mkdir -p "$box/bin" && ln -s "$HERE/replay-gh.sh" "$box/bin/gh" || { echo "remote-reader-rc 69"; exit 69; }
export PATH="$box/bin:$PATH" CI_READ_GH="$HERE/replay-gh.sh"
unset LANDING_PRECHECK_GH LANDING_PRECHECK_MERGE_READINESS CI_READ_GH_CONDITIONAL
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
