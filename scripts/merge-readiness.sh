#!/usr/bin/env bash
#
# merge-readiness.sh — можно ли сливать этот PR ПРЯМО СЕЙЧАС.
#
# ЗАЧЕМ. Защита ветки не действует, пока обязательная проверка НЕ НАЧАЛАСЬ:
# между открытием PR и появлением check-run с обязательным именем контекста не
# существует ни как `pending`, ни как `failure`, и слияние проходит.
#
# Измерено 2026-08-17 на монорепо продукта (задача kacho#614):
#
#   контекст «сквозные пробы консоли» — в списке 45 обязательных для main
#   исход на ревизии:  FAILURE
#   прогон:            начат 05:41:12, закончен 06:18:14
#   MR влит:                   05:45:01
#   enforce_admins:    true   (то есть НЕ обход администратора)
#
# Красное просидело в стволе трое суток и всплыло, только когда та же проверка
# заблокировала два следующих MR.
#
# ГЛАВНОЕ СЛЕДСТВИЕ, ради которого скрипт написан: из «PR влит» НЕ следует
# «его проверки были зелёными». Отсутствие красного — не то же самое, что
# наличие зелёного: контекста может просто ещё не быть.
#
# ЧТО ИМЕННО ПРОВЕРЯЕТСЯ — сверка ПО ИМЕНАМ, а не по числам. Совпадение
# количеств («завершено 45, требуется 45») ничего не доказывает: лишний
# необязательный контекст закрыл бы недостающий обязательный. Поэтому берётся
# РАЗНОСТЬ МНОЖЕСТВ: какие из обязательных имён не имеют зелёного исхода.
#
# ГРАНИЦА. Скрипт отвечает на вопрос «готов ли PR к слиянию по проверкам» и
# только на него. Он НЕ судит о содержании изменения, НЕ заменяет обзор и НЕ
# знает про требования, живущие вне списка обязательных контекстов.
#
# Код возврата: 0 — сливать можно; 1 — нельзя (сказано, почему);
#               2 — вопрос беспредметен (нет PR, нет доступа, защита не настроена).

set -euo pipefail

REPO="${1:-}"
PR="${2:-}"

if [ -z "$REPO" ] || [ -z "$PR" ]; then
  cat >&2 <<'USAGE'
использование: merge-readiness.sh <владелец/репозиторий> <номер PR>
пример:        merge-readiness.sh PRO-Robotech/kacho 597
USAGE
  exit 2
fi

command -v gh >/dev/null 2>&1 || { echo "merge-readiness: gh не найден" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "merge-readiness: jq не найден" >&2; exit 2; }

pr_json=$(gh pr view "$PR" -R "$REPO" --json state,baseRefName,mergeStateStatus,statusCheckRollup 2>/dev/null) || {
  echo "merge-readiness: PR $REPO#$PR недоступен" >&2; exit 2; }

state=$(jq -r '.state' <<<"$pr_json")
base=$(jq -r '.baseRefName' <<<"$pr_json")
merge_state=$(jq -r '.mergeStateStatus' <<<"$pr_json")

if [ "$state" != "OPEN" ]; then
  echo "merge-readiness: PR $REPO#$PR в состоянии $state — сливать нечего"
  exit 2
fi

# Обязательные контексты целевой ветки. Отсутствие защиты — НЕ повод молчать:
# это состояние, о котором надо сказать вслух, иначе «проверок нет» прочитается
# как «замечаний нет».
protection=$(gh api "repos/$REPO/branches/$base/protection" 2>/dev/null || true)
if [ -z "$protection" ]; then
  echo "merge-readiness: ветка '$base' НЕ ЗАЩИЩЕНА — обязательных контекстов нет,"
  echo "                 то есть проверить нечего. Это находка, а не норма."
  exit 2
fi

required=$(jq -r '.required_status_checks.contexts[]?' <<<"$protection" | sort -u)
req_count=$(printf '%s\n' "$required" | grep -c . || true)

if [ "${req_count:-0}" -eq 0 ]; then
  echo "merge-readiness: у ветки '$base' защита есть, а обязательных контекстов ноль —"
  echo "                 слияние ничем не гейтится. Это находка, а не норма."
  exit 2
fi

# Исходы на ревизии PR. Один контекст может встретиться дважды (перезапуск),
# поэтому зелёным считается имя, у которого ЕСТЬ успешный исход.
green=$(jq -r '.statusCheckRollup[]? | select(.conclusion=="SUCCESS") | (.name // .context)' <<<"$pr_json" | sort -u)
red=$(jq -r '.statusCheckRollup[]? | select(.conclusion=="FAILURE" or .conclusion=="TIMED_OUT" or .conclusion=="CANCELLED" or .conclusion=="ACTION_REQUIRED") | (.name // .context) + " [" + .conclusion + "]"' <<<"$pr_json" | sort -u)
running=$(jq -r '.statusCheckRollup[]? | select((.conclusion // "")=="") | (.name // .context)' <<<"$pr_json" | sort -u)

missing=$(comm -23 <(printf '%s\n' "$required") <(printf '%s\n' "$green"))

green_req=$(comm -12 <(printf '%s\n' "$required") <(printf '%s\n' "$green") | grep -c . || true)
missing_count=$(printf '%s\n' "$missing" | grep -c . || true)
red_count=$(printf '%s\n' "$red" | grep -c . || true)
running_count=$(printf '%s\n' "$running" | grep -c . || true)

echo "merge-readiness: $REPO#$PR → $base"
echo "  обязательных контекстов: $req_count · с зелёным исходом: $green_req · без него: $missing_count"
echo "  красных на ревизии: $red_count · ещё идут: $running_count · состояние слияния: $merge_state"

if [ "$red_count" -gt 0 ]; then
  echo "  КРАСНЫЕ:"
  printf '%s\n' "$red" | sed 's/^/    /'
fi

if [ "$missing_count" -gt 0 ]; then
  echo "  ОБЯЗАТЕЛЬНЫЕ БЕЗ ЗЕЛЁНОГО ИСХОДА:"
  printf '%s\n' "$missing" | while read -r ctx; do
    [ -z "$ctx" ] && continue
    if printf '%s\n' "$running" | grep -qxF "$ctx"; then
      echo "    $ctx — идёт"
    elif printf '%s\n' "$red" | grep -qF "$ctx"; then
      echo "    $ctx — красный"
    else
      # Тот самый случай из kacho#614: контекста на ревизии НЕТ ВОВСЕ.
      echo "    $ctx — НЕ ПОЯВЛЯЛСЯ на этой ревизии (защита сейчас не действует)"
    fi
  done
  echo
  echo "merge-readiness: СЛИВАТЬ НЕЛЬЗЯ"
  exit 1
fi

echo
echo "merge-readiness: можно сливать — каждый обязательный контекст имеет зелёный исход"
exit 0
