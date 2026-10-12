#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# SubagentStop hook — return-guard (ws#1030). Исполнитель, закончивший ход без
# блока «### ВОЗВРАТ» (контракт CLAUDE.md), получает отказ завершению и ход
# обратно с правилом: ход не завершается ожиданием события (Monitor, уведомление
# о фоновой задаче) — долгое отсоединённо, ВОЗВРАТ со статусом «идёт».
# Разбор — return-guard/guard.py (что судится, что нет, граница — в его шапке);
# доказательство — return-guard/prove.sh (его зовёт scripts/hook-proofs.sh).
#
# Кому адресован отказ: исполнителю, который заканчивал ход (reason уходит ему).
#
# Собственная поломка — ГРОМКАЯ, но не запирающая: пропуск (код 0) с systemMessage
# «СЛОМАН».
set -u

_src="${BASH_SOURCE[0]}"
HOOK_DIR="$(cd "${_src%/*}" 2>/dev/null && pwd)" || HOOK_DIR="."
GUARD="$HOOK_DIR/return-guard/guard.py"

broken() {
    printf '{"systemMessage":"RETURN-GUARD СЛОМАН: %s. Завершение исполнителя этим вызовом НЕ проверялось — это не «чисто»; починка — tooling-maintainer."}\n' "$1"
    exit 0
}

[ -f "$GUARD" ] || broken "не найден return-guard/guard.py рядом с хуком"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || broken "python3 не найден в PATH"
ERR="$(mktemp 2>/dev/null || echo "/tmp/return-guard.$$")"
OUT="$("$PY" "$GUARD" 2> "$ERR")"; rc=$?
if [ "$rc" -ne 0 ]; then
    why="$(head -c 300 "$ERR" | tr '\n"' '  ' | tr -d '\134')"; rm -f "$ERR"
    broken "guard.py вышел кодом $rc: $why"
fi
rm -f "$ERR"
[ -n "$OUT" ] && printf '%s\n' "$OUT"
exit 0
