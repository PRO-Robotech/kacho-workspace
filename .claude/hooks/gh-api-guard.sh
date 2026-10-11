#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# PreToolUse(Bash) hook — gh-api-guard (ws#1008). Изменяющий вызов `gh api` (метод
# записи либо тело без --method GET) у агента, кроме git-operator, пути вливания
# `repos/*/merges` и `pulls/*/merge` у всех, `gh pr merge` вне правила вливания
# (не git-operator; без --match-head-commit; --auto, --admin) получают отказ с
# правильным чтением: merge-base — `gh api …/compare/<base>...<head>` (GET) или
# `git merge-base`. Разбор — gh-api-guard/guard.py (лексер — no-wait-guard);
# доказательство — gh-api-guard/prove.sh (его зовёт scripts/hook-proofs.sh).
#
# Кому адресован отказ: тому, кто звал Bash, — исполнителю. У диспетчера Bash нет.
#
# Собственная поломка — ГРОМКАЯ, но не запирающая: пропуск (код 0) со словом
# «СЛОМАН» в additionalContext.
set -u

_src="${BASH_SOURCE[0]}"
HOOK_DIR="$(cd "${_src%/*}" 2>/dev/null && pwd)" || HOOK_DIR="."
GUARD="$HOOK_DIR/gh-api-guard/guard.py"

broken() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"GH-API-GUARD СЛОМАН: %s. Изменяющие вызовы gh api этим вызовом НЕ проверялись — это не «чисто»; норма действует: gh api — только GET, вливание — только gh pr merge --match-head-commit у git-operator; починка — tooling-maintainer."}}\n' "$1"
    exit 0
}

[ -f "$GUARD" ] || broken "не найден gh-api-guard/guard.py рядом с хуком"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || broken "python3 не найден в PATH"
# Код 0 и 2 — суждение стража; любой иной — его поломка: громко, но не запирая.
ERR="$(mktemp 2>/dev/null || echo "/tmp/gh-api-guard.$$")"
"$PY" "$GUARD" 2> "$ERR"; rc=$?
case "$rc" in
    0) rm -f "$ERR" ;;
    2) cat "$ERR" >&2; rm -f "$ERR"; exit 2 ;;
    *) why="$(head -c 300 "$ERR" | tr '\n"' '  ' | tr -d '\134')"; rm -f "$ERR"
       broken "guard.py вышел кодом $rc: $why" ;;
esac
exit 0
