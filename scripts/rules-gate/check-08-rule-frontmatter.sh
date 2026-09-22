#!/usr/bin/env bash
# check-08 — КАЖДЫЙ ФАЙЛ ПРАВИЛ НЕСЁТ FRONTMATTER, ИМЯ В НЁМ СХОДИТСЯ С ИМЕНЕМ ФАЙЛА.
# Предмет: скил `rule-<имя>` — симлинк на файл правила, и харнесс регистрирует скил по
# frontmatter ЦЕЛИ. Файл без frontmatter = правило, которое не доходит до исполнителя:
# автозагрузка снята `claudeMdExcludes`. Вердикт — в КОДЕ ВЫХОДА.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# КОРЕНЬ ВЫВОДИТСЯ ИЗ СВОЕГО РАСПОЛОЖЕНИЯ, А НЕ ИЗ ТЕКУЩЕГО КАТАЛОГА (2026-09-22).
# Здесь стоял `cd "$(git rev-parse --show-toplevel)"`, и это тот же класс, что
# измерен на `check-11`: проверка, запущенная с cwd в соседнем worktree полосы,
# МОЛЧА судит чужое дерево и выходит нулём — «полоса получает чужой вердикт».
# Образец решения взят у соседей — `check-02:196` и
# `scripts/tooling-gate/check-12:65`. Шов `RULES_GATE_ROOT` остаётся первым:
# инъекция гоняет проверку на КОПИИ дерева, и без него ось была бы недоказуема
# (контракт набора, `run-all.sh` §«КОНТРАКТ НАБОРА ДЛЯ ЕГО ПРОВЕРОК», п. «а»).
# Корень ПЕЧАТАЕТСЯ переписью: без имени дерева все прочие числа не читаются.
root="${RULES_GATE_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}"
cd "$root" 2>/dev/null || {
    echo "[VOID] check-08-rule-frontmatter — корень «$root» не открывается; обходить нечего" >&2
    exit 2
}
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
printf 'осмотрено файлов правил: %s; корень %s\n' "$n" "$root"
if [ "$n" -lt 17 ]; then
  printf 'КРАСНОЕ — файлов правил %s, ожидалось не меньше 17: обход усечён, вердикт беспредметен\n' "$n"
  rc=1
fi
exit "$rc"
