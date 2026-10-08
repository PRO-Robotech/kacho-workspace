#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# PreToolUse(Bash|Monitor) hook — git-guard (ws#974). Команда git/gh, обходящая
# хуки (--no-verify, KACHO_SKIP_PREPUSH, core.hooksPath), переписывающая
# опубликованную историю (push --force / -f / --force-with-lease / +refspec) или
# обходящая защиту ствола (push в main/master, gh pr merge --admin), получает
# отказ с текстом, что делать вместо. Разбор — git-guard/guard.py (разборщик
# строки общий с heavy-guard), доказательство — git-guard/prove.sh (его зовёт
# scripts/hook-proofs.sh).
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
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"GIT-GUARD СЛОМАН: %s. Команды git этим вызовом НЕ проверялись — это не «чисто»: --no-verify, KACHO_SKIP_PREPUSH, push --force/+refspec, push в main/master, gh pr merge --admin и core.hooksPath запрещены и без стража; починка — tooling-maintainer."}}\n' "$1"
    exit 0
}

[ -f "$GUARD" ] || broken "не найден git-guard/guard.py рядом с хуком"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || broken "python3 не найден в PATH"
exec "$PY" -I "$GUARD"
