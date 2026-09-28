#!/usr/bin/env bash
# check-08 — КАЖДЫЙ ФАЙЛ ПРАВИЛ НЕСЁТ FRONTMATTER, ИМЯ В НЁМ СХОДИТСЯ С ИМЕНЕМ ФАЙЛА.
# Предмет: скил `rule-<имя>` — симлинк на файл правила, и харнесс регистрирует скил по
# frontmatter ЦЕЛИ. Файл без frontmatter = правило, которое не доходит до исполнителя:
# автозагрузка снята `claudeMdExcludes`. Вердикт — в КОДЕ ВЫХОДА: 0 — чисто; 1 —
# находка (в том числе усечённый обход при живом корпусе); 2 — файлов правил нет,
# судить нечего. Нераскрытый глоб — не файл: прежде он считался файлом правил, и
# пустой каталог давал код находки на пустом дереве.
set -euo pipefail
cd "$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
rc=0
n=0
for f in .claude/rules/*.md; do
  [ -e "$f" ] || continue
  n=$((n + 1))
  base="$(basename "$f" .md)"
  if [ "$(head -1 "$f")" != '---' ]; then
    printf 'КРАСНОЕ %s — нет frontmatter\n' "$f"
    rc=1
    continue
  fi
  if ! grep -qxF -- "name: rule-${base}" <<<"$(sed -n '2,6p' "$f")"; then
    printf 'КРАСНОЕ %s — нет строки «name: rule-%s»\n' "$f" "$base"
    rc=1
    continue
  fi
  if ! grep -q '^description: .' <<<"$(sed -n '2,6p' "$f")"; then
    printf 'КРАСНОЕ %s — description пуст\n' "$f"
    rc=1
  fi
done
printf 'осмотрено файлов правил: %s\n' "$n"
if [ "$n" -eq 0 ]; then
  printf 'ОТКАЗ — в .claude/rules нет ни одного файла *.md: frontmatter судить не у чего, вердикт беспредметен\n'
  exit 2
fi
if [ "$n" -lt 17 ]; then
  printf 'КРАСНОЕ — файлов правил %s, ожидалось не меньше 17: обход усечён, вердикт беспредметен\n' "$n"
  rc=1
fi
exit "$rc"
