#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# PreToolUse(Bash) hook — no-wait-guard (ws#1004). Команда ожидания в переднем
# плане (цикл until/while со sleep, tail --pid, gh run watch, sleep ≥ 300,
# timeout ≥ 600, flock -w ≥ 300) получает отказ с правилом «Не жди» (CLAUDE.md) и
# правильной формой: отсоединённо с журналом и pid-файлом, исход — коротким шагом.
# Разбор — no-wait-guard/guard.py; доказательство — no-wait-guard/prove.sh (его
# зовёт scripts/hook-proofs.sh).
#
# Кому адресован отказ: тому, кто звал Bash, — исполнителю. У диспетчера Bash нет.
#
# Собственная поломка — ГРОМКАЯ, но не запирающая: пропуск (код 0) со словом
# «СЛОМАН» в additionalContext.
set -u

_src="${BASH_SOURCE[0]}"
HOOK_DIR="$(cd "${_src%/*}" 2>/dev/null && pwd)" || HOOK_DIR="."
GUARD="$HOOK_DIR/no-wait-guard/guard.py"

broken() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"NO-WAIT-GUARD СЛОМАН: %s. Команды ожидания этим вызовом НЕ проверялись — это не «чисто»; правило «Не жди» (CLAUDE.md) действует; починка — tooling-maintainer."}}\n' "$1"
    exit 0
}

[ -f "$GUARD" ] || broken "не найден no-wait-guard/guard.py рядом с хуком"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || broken "python3 не найден в PATH"
# Код 0 и 2 — суждение стража; любой иной — его поломка (исключение до main,
# синтаксис, нет модуля heavy-guard): громко, но не запирая.
ERR="$(mktemp 2>/dev/null || echo "/tmp/no-wait-guard.$$")"
"$PY" "$GUARD" 2> "$ERR"; rc=$?
case "$rc" in
    0) rm -f "$ERR" ;;
    2) cat "$ERR" >&2; rm -f "$ERR"; exit 2 ;;
    *) why="$(head -c 300 "$ERR" | tr '\n"' '  ' | tr -d '\134')"; rm -f "$ERR"
       broken "guard.py вышел кодом $rc: $why" ;;
esac
exit 0
