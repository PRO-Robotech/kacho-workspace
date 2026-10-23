#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# replay-gh.sh <доводы gh…> — ответ GitHub, снятый машиной до Job (ws#1365): токена в pod нет
# (scripts/remote-heavy/run.sh, СРЕДА ВОРКСПЕЙСА). Ключ — доводы ДОСЛОВНО, как их строит
# читатель (STAND_REPORT_GH, RITUAL_GH); ответ — те же байты stdout и тот же код, что дал `gh`.
# Ключа нет — промах: доводы строкой JSON в $REMOTE_READER_GH/misses, код 1, читатель
# отказывает «не выполнилось», а драйвер снимает промах и повторяет прогон.
set -uo pipefail
dir="${REMOTE_READER_GH:?replay-gh: REMOTE_READER_GH не задан}"
key="$(jq -cn '$ARGS.positional' --args "$@")" || exit 1
hit="$(jq -c --argjson k "$key" 'select(.argv == $k)' "$dir/index.jsonl" 2> /dev/null | head -n 1)"
if [ -z "$hit" ]; then
    printf '%s\n' "$key" >> "$dir/misses"
    printf 'replay-gh: ответа нет в снятом машиной — %s\n' "$key" >&2
    exit 1
fi
cat -- "$dir/../$(jq -r .out <<< "$hit")" || exit 1
exit "$(jq -r .rc <<< "$hit")"
