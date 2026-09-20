#!/usr/bin/env bash
# check-08 — КАЖДЫЙ ФАЙЛ ПРАВИЛ НЕСЁТ FRONTMATTER, ИМЯ В НЁМ СХОДИТСЯ С ИМЕНЕМ ФАЙЛА.
# Предмет: скил `rule-<имя>` — симлинк на файл правила, и харнесс регистрирует скил по
# frontmatter ЦЕЛИ. Файл без frontmatter = правило, которое не доходит до исполнителя:
# автозагрузка снята `claudeMdExcludes`. Вердикт — в КОДЕ ВЫХОДА.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
rc=0
n=0
for f in .claude/rules/*.md; do
  n=$((n + 1))
  base="$(basename "$f" .md)"
  if [ "$(head -1 "$f")" != '---' ]; then
    printf 'КРАСНОЕ %s — нет frontmatter\n' "$f"
    rc=1
    continue
  fi
  if ! sed -n '2,6p' "$f" | grep -qxF "name: rule-${base}"; then
    printf 'КРАСНОЕ %s — нет строки «name: rule-%s»\n' "$f" "$base"
    rc=1
    continue
  fi
  if ! sed -n '2,6p' "$f" | grep -q '^description: .'; then
    printf 'КРАСНОЕ %s — description пуст\n' "$f"
    rc=1
  fi
done
printf 'осмотрено файлов правил: %s\n' "$n"
if [ "$n" -lt 17 ]; then
  printf 'КРАСНОЕ — файлов правил %s, ожидалось не меньше 17: обход усечён, вердикт беспредметен\n' "$n"
  rc=1
fi
exit "$rc"
