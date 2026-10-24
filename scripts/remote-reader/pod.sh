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
#   remote-reader-fail <проверка>[: ожидалось …; получено «…»]   отказ стороны pod (код 70)
#   remote-reader-rc <код входа>                        последней строкой
# tar — новые файлы реестра (kaname-imports/<отпечаток>.json), записанные входом.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPP="$(cd "$HERE/../.." && pwd)"
RR="$PWD"
# Судья реестра (operator-stand.py registry()) сверяет адрес origin воркспейса. Клон Job
# (remote-heavy/run.sh: init + bundle) origin НЕСЁТ — `https://github.com/PRO-Robotech/<репо>.git`, как
# checkout конвейера (ws#1301), а копия машины — свой адрес, обычно ssh (ws#1403). Поэтому сверяется
# РЕПОЗИТОРИЙ: и rr/workspace-origin, и origin клона — одна из канонических форм адреса
# PRO-Robotech/kacho-workspace (тот же перечень, что у судьи реестра), а не одно написание. Клону без
# origin он заводится адресом rr/workspace-origin; иной репозиторий у файла либо у клона — 70.
# Отказ называет проверку: «remote-reader-fail <проверка>: ожидалось …; получено «…»» перед
# строкой кода; полученное — без userinfo и управляющих знаков, не длиннее 200.
CANON='git@github.com:PRO-Robotech/kacho-workspace.git | https://github.com/PRO-Robotech/kacho-workspace.git | https://github.com/PRO-Robotech/kacho-workspace'
canonical_origin() {
    case "$1" in
        git@github.com:PRO-Robotech/kacho-workspace.git|https://github.com/PRO-Robotech/kacho-workspace.git|https://github.com/PRO-Robotech/kacho-workspace) return 0 ;;
        *) return 1 ;;
    esac
}
shown() { printf '%s' "$1" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#' | tr -d '\000-\037\177' | cut -c1-200; }
reader_fail() {  # reader_fail <проверка> [<ожидалось> <получено>]
    printf 'remote-reader-fail %s' "$1"
    [ $# -lt 3 ] || printf ': ожидалось %s; получено «%s»' "$2" "$(shown "$3")"
    printf '\nremote-reader-rc 70\n'; exit 70
}
top_got="$(git -C "$TOPP" rev-parse --show-toplevel 2> /dev/null)" || top_got=""
[ "$top_got" = "$TOPP" ] || reader_fail "корень клона Job" "$TOPP" "$top_got"
if [ -L "$RR/workspace-origin" ]; then reader_fail "файл rr/workspace-origin" "обычный файл" "символьная ссылка"; fi
[ -f "$RR/workspace-origin" ] || reader_fail "файл rr/workspace-origin" "обычный файл" "нет файла"
lines="$(wc -l < "$RR/workspace-origin")"
[ "$lines" -eq 1 ] || reader_fail "строк в rr/workspace-origin" 1 "$lines"
IFS= read -r workspace_origin < "$RR/workspace-origin"
canonical_origin "$workspace_origin" || reader_fail "rr/workspace-origin (адрес копии машины)" "$CANON" "$workspace_origin"
workspace_remotes="$(git -C "$TOPP" remote)" || reader_fail "перечень remote клона Job"
if grep -qx origin <<< "$workspace_remotes"; then
    clone_origin="$(git -C "$TOPP" remote get-url origin)" || reader_fail "адрес origin клона Job"
    canonical_origin "$clone_origin" || reader_fail "origin клона Job (remote-heavy/run.sh)" "$CANON" "$clone_origin"
else
    git -C "$TOPP" remote add origin "$workspace_origin" || reader_fail "origin клону Job не заведён"
fi
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
box="$(mktemp -d)"
trap 'rm -rf -- "$box"' EXIT
if [ -d "$reg" ]; then (cd "$reg" && find . -type f | sort) > "$box/before" || reader_fail "перепись реестра до входа"; else : > "$box/before"; fi
# gh первым в PATH — снятый машиной: предпроверка зовёт gh сама и через merge-readiness и ci-read;
# ci-read — без условного чтения (`-i`), его ключи машина снимает простой формой.
mkdir -p "$box/bin" && ln -s "$HERE/replay-gh.sh" "$box/bin/gh" || { echo "remote-reader-rc 69"; exit 69; }
export PATH="$box/bin:$PATH" CI_READ_GH="$HERE/replay-gh.sh"
unset LANDING_PRECHECK_GH LANDING_PRECHECK_MERGE_READINESS CI_READ_GH_CONDITIONAL
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
rc=0
bash "$TOPP/$entry" "${args[@]}" > "$box/out" 2> "$box/err" || rc=$?
if [ -d "$reg" ]; then (cd "$reg" && find . -type f | sort) > "$box/after" || reader_fail "перепись реестра после входа"; else : > "$box/after"; fi
: > "$box/tar"
comm -13 "$box/before" "$box/after" | sed 's#^\./##' > "$box/new" || reader_fail "новые файлы реестра"
mapfile -t new < "$box/new"
if [ "${#new[@]}" -gt 0 ]; then tar -cf "$box/tar" -C "$reg" -- "${new[@]}" || reader_fail "архив новых файлов реестра"; fi
cp -- "$RR/gh/misses" "$box/miss" || reader_fail "промахи GitHub"
for kind in out err miss tar; do
    base64 -w 76 < "$box/$kind" | awk -v k="$kind" '{print "remote-reader-" k " " NR " " $0}' || reader_fail "поток $kind"
    printf 'remote-reader-size %s %s\n' "$kind" "$(wc -c < "$box/$kind")"
done
printf 'remote-reader-rc %s\n' "$rc"
exit "$rc"
