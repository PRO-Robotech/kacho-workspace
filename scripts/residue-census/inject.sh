#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство, что `census.sh compare` СПОСОБЕН назвать след,
# способен смолчать на законном близнеце и отличает «сравнивать нечего» от
# «следов 0».
#
# Вход НАСТОЯЩИЙ: перепись снимается самим инструментом с настоящего каталога
# (свой TMPDIR пробы), а след — настоящий файл, созданный между снимками. Ось
# одна (RESIDUE_AXES=tmpdir): прочие оси общие с соседями, и чужой след в них
# красил бы пробу по жребию. Каждый случай меняет ОДИН факт против контроля.
#
#   K0 контроль: между снимками ничего          → код 0, «новых следов 0»
#   K1 файл остался                              → код 1, след назван путём
#   K2 близнец K1: файл создан и снят            → код 0
#   K3 файл под --keep                           → код 0, «оставлено как отчёт»
#   K4 --keep не шире префикса: файл рядом       → код 1, след назван
#   K5 каталог остался (не только файл)          → код 1, след назван
#   K6 локаль со свёрткой: 20 записей лежали, одна добавлена → код 1, след ровно 1
#      (порядок `sort` локали и побайтовый слияние `comm` расходятся, и лежавшее
#      называется следом: на живом `tmp/` 49 «следов» вместо 2, 2026-10-07)
#   V1 ось VOID в обоих снимках                  → код 2, не «следов 0»
#   V2 снимок не читается                        → код 2
#   V3 ось осмотрена лишь в снимке «до»          → код 2, ось названа неосмотренной
#   V4 читатель оси вернул ненулевой код         → код 2, «читатель оси вернул код»
#      (не «#axis ось 0»: отказ чтения, названный пустой осью, — VOID, объявленная
#      чистой). Два настоящих отказа: worktree — репозиторий из RESIDUE_REPOS не
#      существует (git отказывает); tmpdir — каталог есть, но закрыт 000 (find
#      отказывает). Сравнивать в обоих случаях нечего.
#
# Запуск: bash scripts/residue-census/inject.sh   (код 0 — все случаи сошлись)
#
# Проба убирает за собой то, что создала (trap на EXIT), — норма, которую она
# держит, распространяется и на неё.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENSUS="$SELF_DIR/census.sh"
BOX="$(mktemp -d)" || { echo "inject: каталог пробы не создан" >&2; exit 2; }
# chmod до rm: случай V4 закрывает каталог 000, и обрыв посреди него не должен
# оставить нечитаемый след.
trap 'chmod -R u+rwx -- "$BOX" 2>/dev/null; rm -rf -- "$BOX"' EXIT

PASS=0
FAIL=0
EXTRA=()
T="$BOX/tmp"
mkdir -p "$T"

snap() { TMPDIR="$1" RESIDUE_AXES=tmpdir bash "$CENSUS" snapshot >"$2"; }

# check ИМЯ ОЖИДАЕМЫЙ_КОД [СТРОКА_В_ВЫВОДЕ] — ДО и ПОСЛЕ уже сняты.
check() {
    local name="$1" want="$2" needle="${3:-}" out rc
    out="$(bash "$CENSUS" compare "$BOX/before" "$BOX/after" "${EXTRA[@]}" 2>&1)"
    rc=$?
    if [ "$rc" -ne "$want" ]; then
        printf 'ПРОВАЛ %s: код %d, ждали %d\n%s\n' "$name" "$rc" "$want" "$out"
        FAIL=$((FAIL + 1)); return
    fi
    if [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$out"; then
        printf 'ПРОВАЛ %s: код %d верен, но в выводе нет «%s»\n%s\n' "$name" "$rc" "$needle" "$out"
        FAIL=$((FAIL + 1)); return
    fi
    printf 'ок %s (код %d)\n' "$name" "$rc"
    PASS=$((PASS + 1))
}

reset_box() { rm -rf -- "${T:?}"/* "${T:?}"/.[!.]* 2>/dev/null; EXTRA=(); }

# K0
reset_box; snap "$T" "$BOX/before"; snap "$T" "$BOX/after"
check K0-контроль 0 "новых следов 0"

# K1
reset_box; snap "$T" "$BOX/before"; : >"$T/run-left.log"; snap "$T" "$BOX/after"
check K1-файл-остался 1 "СЛЕД: tmpdir $T/run-left.log"

# K2
reset_box; snap "$T" "$BOX/before"; : >"$T/run-left.log"; rm -f "$T/run-left.log"; snap "$T" "$BOX/after"
check K2-создан-и-снят 0 "новых следов 0"

# K3
reset_box; snap "$T" "$BOX/before"; mkdir -p "$T/report-1"; : >"$T/report-1/junit.xml"; snap "$T" "$BOX/after"
EXTRA=(--keep "$T/report-")
check K3-отчёт-под-keep 0 "оставлено как отчёт: tmpdir $T/report-1"

# K4
reset_box; snap "$T" "$BOX/before"; : >"$T/reportless.log"; snap "$T" "$BOX/after"
EXTRA=(--keep "$T/report-")
check K4-keep-не-шире-префикса 1 "СЛЕД: tmpdir $T/reportless.log"

# K5
reset_box; snap "$T" "$BOX/before"; mkdir -p "$T/kacho-ci-local-12345678/run-1"; snap "$T" "$BOX/after"
check K5-каталог-остался 1 "СЛЕД: tmpdir $T/kacho-ci-local-12345678"

# K6 — локаль со свёрткой берётся из установленных; её нет — случай не выполнен,
# и это провал пробы, а не тихий пропуск: без него свойство не доказано.
# Перечень локалей читается целиком в переменную, а выбор — из неё: `grep -m1`
# в трубе под pipefail обрывал бы писателя, и найденное объявилось бы ненайденным.
LOCALES="$(locale -a 2>/dev/null)" || LOCALES=""
COLLATE=""
while IFS= read -r loc; do
    case "$loc" in
        ru_RU.[uU][tT][fF]8|ru_RU.[uU][tT][fF]-8|en_US.[uU][tT][fF]8|en_US.[uU][tT][fF]-8) COLLATE="$loc"; break ;;
    esac
done <<<"$LOCALES"
if [ -z "$COLLATE" ]; then
    printf 'ПРОВАЛ K6-локаль-со-свёрткой: не выполнено — локали ru_RU/en_US UTF-8 не установлены\n'
    FAIL=$((FAIL + 1))
else
    reset_box
    for n in ciw-611 \
             ciw-616 \
             ciw-622 \
             ciw-624 \
             ciw624 \
             ciw-814-91dc3632-20260923T131405 \
             ciw-90ab287.go-test-short.log \
             ciw-90ab287.log \
             ci-watch-183-run-35907735501 \
             ci-watch-2820 \
             ciwatch-2833-3f5041eb \
             ci-watch-2833-jobs-final.tsv \
             ci-watch-2833-jobs-t0.tsv \
             ci-watch-2837 \
             ci-watch-2861 \
             ci-watch-2861-e305 \
             ci-watch-2978 \
             ci-watch-3043 \
             ci-watch-305 \
             ci-watch-314; do : >"$T/$n"; done
    LC_ALL="$COLLATE" snap "$T" "$BOX/before"
    : >"$T/2917-pr-body.3Z4L"
    LC_ALL="$COLLATE" snap "$T" "$BOX/after"
    LC_ALL="$COLLATE" check "K6-локаль-со-свёрткой($COLLATE)" 1 "новых следов 1"
fi

# V1
reset_box; snap "$BOX/нет-такого" "$BOX/before"; snap "$BOX/нет-такого" "$BOX/after"
check V1-ось-void 2 "ОТКАЗ"

# V2
reset_box; snap "$T" "$BOX/before"; rm -f "$BOX/after"
check V2-снимок-не-читается 2 "не читается"

# V3
reset_box; snap "$T" "$BOX/before"; snap "$BOX/нет-такого" "$BOX/after"
check V3-ось-лишь-в-одном-снимке 2 "не осмотрено: tmpdir"

# V4 — worktree: репозиторий из RESIDUE_REPOS не существует, git отказывает.
reset_box
RESIDUE_AXES=worktree RESIDUE_REPOS="$BOX/нет-такого-репозитория" bash "$CENSUS" snapshot >"$BOX/before"
RESIDUE_AXES=worktree RESIDUE_REPOS="$BOX/нет-такого-репозитория" bash "$CENSUS" snapshot >"$BOX/after"
check V4-читатель-worktree-отказал 2 "не осмотрено: worktree (читатель оси вернул код"

# V4 — tmpdir: каталог есть, но закрыт; find отказывает. От root 000 не закрывает,
# и случай тогда не выполнен — это провал пробы, а не тихий пропуск.
reset_box
L="$BOX/locked"
mkdir -p "$L/внутри"; chmod 000 "$L"
if [ -r "$L" ]; then
    printf 'ПРОВАЛ V4-читатель-tmpdir-отказал: не выполнено — каталог 000 читается (uid %s)\n' "$(id -u)"
    FAIL=$((FAIL + 1))
else
    snap "$L" "$BOX/before"; snap "$L" "$BOX/after"
    check V4-читатель-tmpdir-отказал 2 "не осмотрено: tmpdir (читатель оси вернул код"
fi
chmod 700 "$L"; rm -rf -- "$L"

printf 'residue-census inject: случаев %d · сошлось %d · разошлось %d\n' $((PASS + FAIL)) "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && [ "$PASS" -gt 0 ]
