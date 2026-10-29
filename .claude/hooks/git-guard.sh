#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# PreToolUse(Bash|Monitor) hook — git-guard (ws#974). Команда git, обходящая хуки
# (`--no-verify` и `-n` у commit/am, `*_SKIP_PREPUSH`, `core.hooksPath` в любой
# форме, алиас с обходом), получает отказ с правилом и тем, что делать вместо.
# Разбор — git-guard/guard.py (разборщик строки общий с heavy-guard);
# доказательство — git-guard/prove.sh (его зовёт scripts/hook-proofs.sh).
#
# Кому адресован отказ: тому, кто звал Bash, — исполнителю. У диспетчера Bash нет.
#
# Собственная поломка — ГРОМКАЯ, но не запирающая: хук срабатывает и внутри
# сабагентов, и страж, отказывающий всему, остановил бы все полосы на любой
# команде. Поломка — пропуск (код 0) со словом «СЛОМАН» в additionalContext.
set -u

_src="${BASH_SOURCE[0]}"
HOOK_DIR="$(cd "${_src%/*}" 2>/dev/null && pwd)" || HOOK_DIR="."
GUARD="$HOOK_DIR/git-guard/guard.py"

broken() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"GIT-GUARD СЛОМАН: %s. Команды git этим вызовом НЕ проверялись — это не «чисто»: --no-verify (и -n у commit/am), *_SKIP_PREPUSH и core.hooksPath запрещены и без стража (git-issues.md#gi-no-hook-bypass); починка — tooling-maintainer."}}\n' "$1"
    exit 0
}

[ -f "$GUARD" ] || broken "не найден git-guard/guard.py рядом с хуком"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || broken "python3 не найден в PATH"
# Код 0 и 2 — суждение стража; любой иной — его поломка: громко, но не запирая.
ERR="$(mktemp 2>/dev/null || echo "/tmp/git-guard.$$")"
"$PY" -I "$GUARD" 2> "$ERR"; rc=$?
case "$rc" in
    0) rm -f "$ERR" ;;
    2) cat "$ERR" >&2; rm -f "$ERR"; exit 2 ;;
    *) why="$(head -c 300 "$ERR" | tr '\n"' '  ' | tr -d '\134')"; rm -f "$ERR"
       broken "guard.py вышел кодом $rc: $why" ;;
esac
exit 0
