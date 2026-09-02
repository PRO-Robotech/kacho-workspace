#!/usr/bin/env bash
# ПОРОЖДЁННЫЙ ФАЙЛ — РУКАМИ НЕ ПРАВИТЬ.
# Источник: канонические входы .claude/ и корневой CLAUDE.md.
# Владение: .claude/adapters.yaml. Генератор: scripts/adapter/generate.py.
# Правка уедет при следующей регенерации; предмет правки — во входе.
set -u
_src="${BASH_SOURCE[0]}"
_dir="$(cd "${_src%/*}" 2>/dev/null && pwd)" || _dir="."
ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd)" || ROOT="."
CANONICAL="$ROOT/.claude/hooks/vault-reminder.sh"
if [ ! -f "$CANONICAL" ]; then
  echo "переходник указывает на отсутствующий канонический хук: .claude/hooks/vault-reminder.sh" >&2
  echo "Это НАСТРОЙКА, а не сбой: она не чинится сама и не истечёт." >&2
  exit 2
fi
exec bash "$CANONICAL" "$@"
