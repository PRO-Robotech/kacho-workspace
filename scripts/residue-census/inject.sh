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
#   V1 ось VOID в обоих снимках                  → код 2, не «следов 0»
#   V2 снимок не читается                        → код 2
#   V3 ось осмотрена лишь в снимке «до»          → код 2, ось названа неосмотренной
#
# Запуск: bash scripts/residue-census/inject.sh   (код 0 — все случаи сошлись)
#
# Проба убирает за собой то, что создала (trap на EXIT), — норма, которую она
# держит, распространяется и на неё.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENSUS="$SELF_DIR/census.sh"
BOX="$(mktemp -d)" || { echo "inject: каталог пробы не создан" >&2; exit 2; }
trap 'rm -rf -- "$BOX"' EXIT

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

# V1
reset_box; snap "$BOX/нет-такого" "$BOX/before"; snap "$BOX/нет-такого" "$BOX/after"
check V1-ось-void 2 "ОТКАЗ"

# V2
reset_box; snap "$T" "$BOX/before"; rm -f "$BOX/after"
check V2-снимок-не-читается 2 "не читается"

# V3
reset_box; snap "$T" "$BOX/before"; snap "$BOX/нет-такого" "$BOX/after"
check V3-ось-лишь-в-одном-снимке 2 "не осмотрено: tmpdir"

printf 'residue-census inject: случаев %d · сошлось %d · разошлось %d\n' $((PASS + FAIL)) "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && [ "$PASS" -gt 0 ]
