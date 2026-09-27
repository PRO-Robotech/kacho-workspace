#!/usr/bin/env bash
# PreToolUse (Bash) — страж команды ДО исполнения. Разбор и запреты — в
# `lib/bash_guard.py` (там же предмет, признаки, обход и граница); здесь только
# дешёвый отсев: хук стоит на КАЖДОЙ команде Bash каждого агента сессии, и
# команду без слова подкоманды, которую страж судит, разбирать нечего — выход
# сразу, без интерпретатора.
#
# Коды: 0 — пропустить; 2 — отказ (stderr уходит агенту, команда не исполняется);
# 1 — поломка стража, команда НЕ блокируется (страж, упавший на своей ошибке, не
# вправе останавливать чужую работу), stderr видит человек.
set -uo pipefail
payload="$(cat)"
case "$payload" in
    *push*) ;;
    *) exit 0 ;;
esac
guard="$(dirname "${BASH_SOURCE[0]}")/lib/bash_guard.py"
if [ ! -f "$guard" ] || ! command -v python3 >/dev/null 2>&1; then
    echo "bash-guard: нет $guard или python3 — страж НЕ применён, команда пропущена. → tooling-maintainer" >&2
    exit 1
fi
printf '%s' "$payload" | python3 "$guard"
