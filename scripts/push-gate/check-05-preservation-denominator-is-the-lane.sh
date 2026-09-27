#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-05 — доказательство сохранности работы полосы берёт знаменатель со ВСЕЙ
# полосы и судит двумя осями (ws#776).
#
# ЗАЧЕМ. Знаменатель нормы `disc-preservation-proof` был файлами ГОЛОВНОГО
# коммита: полоса из трёх коммитов, потерявшая при слиянии работу не головного,
# давала пустое расхождение и «сохранено». Исполняется доказательство
# `scripts/preservation-proof-inject.sh` целиком — потеря вне головного
# коммита, снятое, уцелевшее при слиянии, строки «-- …»/«++ …», база после
# посадки краснеют; законные близнецы молчат, — его исход проходит насквозь.
set -uo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
NAME="check-05-preservation-denominator-is-the-lane"

proof="$PG_SUBJECT/scripts/preservation-proof-inject.sh"
[ -f "$PG_SUBJECT/scripts/preservation-proof.sh" ] || { pg_void "$NAME — scripts/preservation-proof.sh нет"; exit 2; }
[ -f "$proof" ] || { pg_void "$NAME — доказательства scripts/preservation-proof-inject.sh нет"; exit 2; }

pg_hermetic
out="$(bash "$proof" 2>&1 </dev/null)"; rc=$?
census="$(printf '%s\n' "$out" | grep -E '^\[CENSUS\]' | tail -1)"
pg_census "$NAME: ${census#\[CENSUS\] }"
if [ "$rc" = 0 ] && [[ "$census" == *"провалов 0"* ]]; then
    pg_pass "$NAME — потеря вне головного коммита краснеет, законное слияние молчит"
    exit 0
fi
pg_fail "$NAME — доказательство сохранности не прошло (код $rc)"
printf '%s\n' "$out" | grep -E '^\[FAIL\]' | head -10 >&2
exit 1
