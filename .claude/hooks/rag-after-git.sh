#!/usr/bin/env bash
# rag-after-git.sh — событие PostToolUse(Bash): сверить свежесть ПОСЛЕ смены ревизии.
#
# # Честно о том, когда он срабатывает
#
# Цель прямо запрещает хук на КАЖДЫЙ вызов инструмента. Обойти это в Claude Code
# нельзя: события «после git» не существует, есть только PostToolUse с отбором по
# ИМЕНИ инструмента, и процесс хука поднимается на каждом Bash. Поэтому запрет
# исполнен там, где он исполним, — в РАБОТЕ: всё, что делает хук на постороннем
# вызове, это один grep по строке команды и выход.
#
# Цена холостого хода ЗАМЕРЕНА, а не объявлена: см. integration/README.md,
# раздел «Цена хуков». Ни git, ни curl, ни python на этом пути не зовутся.
#
# # Почему только эти глаголы
#
# checkout · switch · pull · rebase · merge · reset · cherry-pick — те, что
# двигают HEAD. `commit` в перечне ЕСТЬ: он тоже двигает HEAD, и после него
# индекс отстаёт ровно так же. `add`, `status`, `diff`, `log` HEAD не двигают.
#
# # Подавление повтора
#
# В отличие от session-start, здесь повтор подавляется: серия из пяти git-команд
# подряд не обязана печатать один и тот же вердикт пять раз. Печатается только
# ИЗМЕНИВШИЙСЯ вердикт. Отпечаток лежит рядом с индексом (data/ под .gitignore).
set -uo pipefail

payload="$(cat)"                      # stdin от Claude Code: JSON вызова

# Отбор по СТРОКЕ КОМАНДЫ, без разбора JSON: jq есть не везде, а поднимать
# python на каждом Bash — ровно то, что запрещено. grep по сырому телу даёт
# ложное срабатывание на команде, лишь УПОМИНАЮЩЕЙ git (например, на этом
# комментарии в heredoc). Это осознанный размен: ложное срабатывание стоит
# 26 мс молчаливой проверки, пропуск — устаревшего вердикта на всю сессию.
printf '%s' "$payload" | grep -qE 'git[^"]{0,40}(checkout|switch|pull|rebase|merge|reset|cherry-pick|commit)' || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(bash "$here/rag-freshness.sh" 2>/dev/null)"
[ -n "$out" ] || exit 0               # свежо — молчим

# Печатать только изменившийся вердикт.
mark="${KACHO_RAG_HOOK_STATE:-$here/../../data/.rag-freshness-last}"
mkdir -p "$(dirname "$mark")" 2>/dev/null
now="$(printf '%s' "$out" | cksum)"
[ -f "$mark" ] && [ "$(cat "$mark" 2>/dev/null)" = "$now" ] && exit 0
printf '%s' "$now" > "$mark" 2>/dev/null

printf '%s\n' "$out"
exit 0
