#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# PreToolUse(Bash|Monitor) hook — heavy-guard. Тяжёлая команда без слота памяти
# (`scripts/heavy-slot.sh`) получает отказ с текстом, как запустить её правильно.
# Разбор команды и словарь форм — в heavy-guard/guard.py; доказательство —
# heavy-guard/prove.sh (его зовёт scripts/hook-proofs.sh).
#
# Кому адресован отказ: тому, кто звал Bash, — исполнителю. У диспетчера Bash нет,
# и переписать команду может только её автор.
#
# Собственная поломка — ГРОМКАЯ, но не запирающая: страж, отказывающий всему,
# остановил бы каждую полосу на любой команде. Поэтому поломка — пропуск (код 0)
# со словом «СЛОМАН» в additionalContext, которое модель видит.
set -u

_src="${BASH_SOURCE[0]}"
HOOK_DIR="$(cd "${_src%/*}" 2>/dev/null && pwd)" || HOOK_DIR="."
GUARD="$HOOK_DIR/heavy-guard/guard.py"

broken() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"HEAVY-GUARD СЛОМАН: %s. Тяжёлые команды этим вызовом НЕ проверялись — это не «чисто»; тяжёлое всё равно запускай через scripts/heavy-slot.sh <класс> -- <команда>; починка — tooling-maintainer."}}\n' "$1"
    exit 0
}

[ -f "$GUARD" ] || broken "не найден heavy-guard/guard.py рядом с хуком"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || broken "python3 не найден в PATH"
exec "$PY" "$GUARD"
