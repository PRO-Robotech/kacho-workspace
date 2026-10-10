#!/usr/bin/env bash
# check-08 — КАЖДЫЙ ФАЙЛ ПРАВИЛ НЕСЁТ FRONTMATTER, ИМЯ В НЁМ СХОДИТСЯ С ИМЕНЕМ ФАЙЛА.
# Предмет: скил `rule-<имя>` — симлинк на файл правила, и харнесс регистрирует скил по
# frontmatter ЦЕЛИ. Файл без frontmatter = правило, которое не доходит до исполнителя:
# автозагрузка снята `claudeMdExcludes`. Вердикт — в КОДЕ ВЫХОДА: 0 — чисто; 1 —
# находка (в том числе усечённый обход при живом корпусе); 2 — файлов правил нет,
# судить нечего. Нераскрытый глоб — не файл: прежде он считался файлом правил, и
# пустой каталог давал код находки на пустом дереве.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# КОРЕНЬ ВЫВОДИТСЯ ИЗ СВОЕГО РАСПОЛОЖЕНИЯ, А НЕ ИЗ ТЕКУЩЕГО КАТАЛОГА (2026-09-22,
# ws#757). Здесь стоял `cd "$(git rev-parse --show-toplevel)"`: проверка, запущенная
# с cwd в соседнем worktree полосы, МОЛЧА судила чужое дерево и выходила нулём —
# «полоса получает чужой вердикт». Порядок источников один на все наборы и живёт
# в `scripts/lib/gate_root.py`: шов набора `RULES_GATE_ROOT` (им инъекция гоняет
# проверку на КОПИИ дерева), общий `GATE_ROOT`, расположение файла.
root="$(python3 "$SELF_DIR/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
cd "$root" 2>/dev/null || {
    echo "[VOID] check-08-rule-frontmatter — корень «$root» не открывается; обходить нечего" >&2
    exit 2
}
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
printf 'осмотрено файлов правил: %s; корень %s\n' "$n" "$root"
if [ "$n" -eq 0 ]; then
  printf '[VOID] ОТКАЗ — в .claude/rules нет ни одного файла *.md: frontmatter судить не у чего, вердикт беспредметен\n'
  exit 2
fi
if [ "$n" -lt 17 ]; then
  printf 'КРАСНОЕ — файлов правил %s, ожидалось не меньше 17: обход усечён, вердикт беспредметен\n' "$n"
  rc=1
fi
exit "$rc"
