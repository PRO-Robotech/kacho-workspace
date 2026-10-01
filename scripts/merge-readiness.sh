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
# знает про требования, живущие вне списка обязательных контекстов (правила
# наборов — rulesets — не читаются: у `2914-notify` их ноль, замер 2026-10-01
# `gh api repos/PRO-Robotech/kacho/rules/branches/2914-notify` → `[]`).
#
# ЧЕЙ НАБОР СУДИТ. Набор обязательных контекстов базы PR. У ветки ЛИНИИ (эпик
# или волна — имя формы `[0-9]+` либо `[0-9]+-*`, те же две формы, что у
# фильтра `pull_request` конвейера продукта, решение Д59 эпика kacho#2914)
# собственного набора нет намеренно: прямые отправки в эпик должны оставаться
# возможными (Д62), поэтому защиту на ней не ставят. Такую базу инструмент
# судит НАБОРОМ СТВОЛА `main` — решение диспетчера 2026-10-01 (каскад Д61
# «волна → PR в эпик» стоял: на каждом PR в `2914-notify` был код 2). Набор,
# взятый у ствола, назван в выводе строкой «набор обязательных».
#
# Код возврата: 0 — сливать можно; 1 — нельзя (сказано, почему);
#               2 — вопрос беспредметен (нет PR, нет доступа, защита не
#                   настроена либо не прочитана, разбор не состоялся).

# ПОЧЕМУ СВЕРКА МНОЖЕСТВ ИДЁТ ПОД LC_ALL=C — И НА sort, И НА comm (ws#530).
#
# `sort` читает LC_COLLATE, `comm` (в uutils) не читает вовсе и сравнивает
# байты. Под ru_RU.UTF-8 `sort` ставит кириллицу перед латиницей, а имена
# обязательных контекстов здесь русские; `comm` объявлял такой вход
# неупорядоченным, выходил ЕДИНИЦЕЙ, и под `set -e` скрипт умирал, не напечатав
# ни строки вердикта. Единица — то, чем этот скрипт говорит «сливать нельзя»,
# поэтому отказ разбора был неотличим от находки: инструмент отвечал «нельзя»
# на КАЖДОМ открытом PR.
#
# Починка стоит на ОБОИХ, и это не перестраховка. На `sort` — потому что
# `LC_ALL=C` на одном лишь `comm` не помогает: замерено, жалоба та же (comm тут
# локаль игнорирует). На `comm` — потому что GNU-реализация локаль читает, и
# байтовый вход при локальном сравнении сломался бы зеркально. Под C оба конца
# сверки говорят на одном языке при любой реализации.
#
# ВТОРОЕ, ЧТО СНИМАЕТ ТА ЖЕ СТРОКА, И ОНО ОПАСНЕЕ ПЕРВОГО. Локальный `sort -u`
# считает ОДНИМ имена, различающиеся только длинным тире, дефисом или пробелом
# (`a — b`, `a - b`, `a b` → одна строка), и выбрасывает лишние. Обязательный
# контекст молча исчезал из перечня, а инструмент отвечал «можно сливать» —
# ложное зелёное ровно там, ради предотвращения чего он и написан. Байтовое
# сравнение не схлопывает ничего.

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

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# ОТКАЗ РАЗБОРА — ЭТО КОД 2, А НЕ 1. Единственная точка, где скрипт объявляет,
# что вердикта у него нет. Всё, что не сошлось при чтении ответа соседа или при
# сверке множеств, обязано приходить сюда: иначе вызывающий прочитает поломку
# инструмента как «сливать нельзя» и пойдёт искать причину в PR, где её нет.
parse_broken() {
  echo "merge-readiness: РАЗБОР СЛОМАН — $1" >&2
  shift
  for line in "$@"; do
    [ -n "$line" ] && echo "                 $line" >&2
  done
  echo "                 вердикта нет; это НЕ «сливать нельзя»." >&2
  exit 2
}

pr_json=$(gh pr view "$PR" -R "$REPO" --json state,baseRefName,mergeStateStatus,statusCheckRollup 2>/dev/null) || {
  echo "merge-readiness: PR $REPO#$PR недоступен" >&2; exit 2; }

# Ответ соседа проверяется на разбираемость ДО первого чтения поля. Без этого
# испорченный ответ (страница ошибки, обрыв, чужой формат) ронял `jq` под
# `set -e`, и наружу уходил его код — ни вердикта, ни объяснения.
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$pr_json" \
  || parse_broken "ответ о PR $REPO#$PR не разбирается как объект JSON" \
                  "сосед вернул не то, что обещает контракт gh."

state=$(jq -r '.state' <<<"$pr_json")
base=$(jq -r '.baseRefName' <<<"$pr_json")
merge_state=$(jq -r '.mergeStateStatus' <<<"$pr_json")

if [ "$state" != "OPEN" ]; then
  echo "merge-readiness: PR $REPO#$PR в состоянии $state — сливать нечего"
  exit 2
fi

# ── ОБЯЗАТЕЛЬНЫЕ КОНТЕКСТЫ: ЧЕЙ НАБОР СУДИТ ЭТОТ PR ───────────────────────────
# Отсутствие защиты — НЕ повод молчать: это состояние, о котором надо сказать
# вслух, иначе «проверок нет» прочитается как «замечаний нет».
#
# КОД `gh api` СУДИТСЯ, А НЕ ГЛОТАЕТСЯ (ws#844). На незащищённой ветке `gh api`
# выходит кодом 1 и пишет тело отказа в STDOUT (gh 2.100.0, замер 2026-10-01):
#     {"message":"Branch not protected",…,"status":"404"}
# Прежняя запись `$(gh api … 2>/dev/null || true)` брала это тело за ответ о
# защите: строка непуста, JSON разбирается, контекстов ноль — и инструмент
# печатал «защита есть, обязательных контекстов ноль» о ветке, которую сервер
# называет незащищённой (kacho#2869, #2960, #2975). Тем же путём проходил любой
# отказ с телом JSON (403, 5xx): непрочитанная защита выдавалась за прочитанную.
#
# Исходов чтения три, у каждого свой текст:
#   код 0, объект JSON                    — защита прочитана;
#   код ≠ 0, 404 «Branch not protected»   — ветка НЕ ЗАЩИЩЕНА;
#   иначе                                 — защита НЕ ПРОЧИТАНА, код 2, отказ назван.
# 404 с другим текстом («Not Found» — у токена нет права читать защиту) — третий
# исход, а не второй: статус тот же, смысл другой.
TRUNK="main"
# Ветка линии — эпик или волна. Обе формы фильтра Д59; `*` провайдера не
# берёт `/`, поэтому и здесь хвост без косой черты.
LINE_BRANCH_RE='^[0-9]+(-[^/]*)?$'

prot_state=""   # protected | unprotected — выставляет read_protection
read_protection() {  # <ветка> <файл ответа>
  local branch="$1" file="$2" rc
  gh api "repos/$REPO/branches/$branch/protection" >"$file" 2>"$workdir/api.err" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    jq -e 'type == "object"' >/dev/null 2>&1 <"$file" \
      || parse_broken "ответ о защите ветки '$branch' не разбирается как объект JSON" \
                      "непустой ответ, который не является JSON, — это отказ соседа," \
                      "а не отсутствие защиты: молча прочитать его как «защиты нет»" \
                      "значило бы подменить один исход другим."
    prot_state=protected
    return 0
  fi
  if jq -e 'type == "object" and .message == "Branch not protected"
            and ((.status // "") | tostring) == "404"' >/dev/null 2>&1 <"$file"; then
    prot_state=unprotected
    return 0
  fi
  echo "merge-readiness: защита ветки '$branch' НЕ ПРОЧИТАНА — gh api вышел кодом $rc" >&2
  echo "                 ответ: $(head -c 300 "$file" | tr '\n' ' ')" >&2
  echo "                 stderr: $(head -c 300 "$workdir/api.err" | tr '\n' ' ')" >&2
  echo "                 это отказ чтения, а не состояние защиты; вердикта нет." >&2
  exit 2
}

contexts_in() {  # <файл ответа о защите> — число обязательных контекстов в нём
  jq -r '.required_status_checks.contexts[]?' <"$1" | grep -c . || true
}

own_file="$workdir/protection-base"
read_protection "$base" "$own_file"
own_state="$prot_state"
own_count=0
[ "$own_state" = protected ] && own_count="$(contexts_in "$own_file")"

set_file="$own_file"
set_branch="$base"
set_from="собственный ветки '$base'"

if [ "${own_count:-0}" -eq 0 ] && [[ "$base" =~ $LINE_BRANCH_RE ]]; then
  if [ "$own_state" = unprotected ]; then
    own_why="ветка не защищена"
  else
    own_why="защита есть, обязательных контекстов ноль"
  fi
  trunk_file="$workdir/protection-trunk"
  read_protection "$TRUNK" "$trunk_file"
  if [ "$prot_state" = unprotected ]; then
    echo "merge-readiness: у ветки линии '$base' собственного набора нет ($own_why),"
    echo "                 а ствол '$TRUNK' НЕ ЗАЩИЩЕН — судить нечем. Это находка, а не норма."
    exit 2
  fi
  set_file="$trunk_file"
  set_branch="$TRUNK"
  set_from="ствола '$TRUNK' — у ветки линии '$base' собственного нет ($own_why)"
elif [ "$own_state" = unprotected ]; then
  echo "merge-readiness: ветка '$base' НЕ ЗАЩИЩЕНА (сервер: 404 «Branch not protected») —"
  echo "                 обязательных контекстов нет, то есть проверить нечего. Это находка, а не норма."
  exit 2
fi

required=$(jq -r '.required_status_checks.contexts[]?' "$set_file" | LC_ALL=C sort -u)
req_count=$(printf '%s\n' "$required" | grep -c . || true)

if [ "${req_count:-0}" -eq 0 ]; then
  echo "merge-readiness: у ветки '$set_branch' защита есть, а обязательных контекстов ноль —"
  echo "                 слияние ничем не гейтится. Это находка, а не норма."
  exit 2
fi

# Исходы на ревизии PR. Один контекст может встретиться дважды (перезапуск),
# поэтому зелёным считается имя, у которого ЕСТЬ успешный исход.
#
# ЗЕЛЁНЫЙ — ТОЛЬКО SUCCESS, и это определение, а не дополнение к перечню
# красных. Исходов у проверки девять (SUCCESS, FAILURE, CANCELLED, TIMED_OUT,
# ACTION_REQUIRED, STARTUP_FAILURE, STALE, NEUTRAL, SKIPPED) плюс «идёт»;
# «зелёный = не красный» пропустил бы за «можно» любой исход, забытый в
# перечне красных (возврат check-verifier @5f3080335: STARTUP_FAILURE и STALE).
# Прочие неуспешные исходы — `other`: не красные, но и не зелёные, и вывод
# называет их своим исходом, а не «не появлялся».
green=$(jq -r '.statusCheckRollup[]? | select(.conclusion=="SUCCESS") | (.name // .context)' <<<"$pr_json" | LC_ALL=C sort -u)
red=$(jq -r '.statusCheckRollup[]? | select(.conclusion=="FAILURE" or .conclusion=="TIMED_OUT" or .conclusion=="CANCELLED" or .conclusion=="ACTION_REQUIRED" or .conclusion=="STARTUP_FAILURE") | (.name // .context) + " [" + .conclusion + "]"' <<<"$pr_json" | LC_ALL=C sort -u)
running=$(jq -r '.statusCheckRollup[]? | select((.conclusion // "")=="") | (.name // .context)' <<<"$pr_json" | LC_ALL=C sort -u)
other=$(jq -r '.statusCheckRollup[]? | select((.conclusion // "") as $c
                 | $c != "" and (["SUCCESS","FAILURE","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"] | index($c) | not))
               | (.name // .context) + " [" + .conclusion + "]"' <<<"$pr_json" | LC_ALL=C sort -u)

printf '%s\n' "$required" > "$workdir/required"
printf '%s\n' "$green"    > "$workdir/green"

# set_diff <ключ> — разность или пересечение множеств.
#
# Недостоверным считается не только ненулевой код, но и ЛЮБАЯ жалоба на stderr:
# `comm` на неупорядоченном входе печатает предупреждение и всё равно выдаёт
# строки — то есть отвечает, не имея права отвечать. Такой ответ обязан быть
# отвергнут целиком, а не разобран.
set_diff() {
  local key="$1" out rc
  out=$(LC_ALL=C comm "$key" "$workdir/required" "$workdir/green" 2>"$workdir/comm.err") && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] || [ -s "$workdir/comm.err" ]; then
    parse_broken "сверка множеств (comm $key) не выполнилась:" \
                 "$(sed 's/^/  /' "$workdir/comm.err" | tr '\n' ' ')" \
                 "перечень обязательных и перечень зелёных сопоставить не удалось."
  fi
  printf '%s' "$out"
}

missing=$(set_diff -23)
green_req=$(printf '%s' "$(set_diff -12)" | grep -c . || true)

missing_count=$(printf '%s\n' "$missing" | grep -c . || true)
red_count=$(printf '%s\n' "$red" | grep -c . || true)
running_count=$(printf '%s\n' "$running" | grep -c . || true)
other_count=$(printf '%s\n' "$other" | grep -c . || true)

echo "merge-readiness: $REPO#$PR → $base"
echo "  набор обязательных: $set_from"
echo "  обязательных контекстов: $req_count · с зелёным исходом: $green_req · без него: $missing_count"
echo "  красных на ревизии: $red_count · ещё идут: $running_count · с иным незелёным исходом: $other_count · состояние слияния: $merge_state"

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
    elif printf '%s\n' "$other" | grep -qF -- "$ctx ["; then
      printf '%s\n' "$other" | grep -F -- "$ctx [" | sed 's/$/ — не зелёный/; s/^/    /'
    else
      # Тот самый случай из kacho#614: контекста на ревизии НЕТ ВОВСЕ.
      if [ "$set_branch" = "$base" ]; then
        echo "    $ctx — НЕ ПОЯВЛЯЛСЯ на этой ревизии (защита сейчас не действует)"
      else
        echo "    $ctx — НЕ ПОЯВЛЯЛСЯ на этой ревизии (у базы защиты нет — сервер слияние не задержит)"
      fi
    fi
  done
  echo
  echo "merge-readiness: СЛИВАТЬ НЕЛЬЗЯ"
  exit 1
fi

# ОБЯЗАТЕЛЬНЫЕ ЗЕЛЁНЫЕ — ЕЩЁ НЕ «СЛИВАЙ». Сервер держит слияние и по другим причинам:
# незавершённая НЕобязательная проверка, конфликт с базой, требование обзора,
# устаревшая ветка при строгом режиме. Молча сказать «можно» значит подтолкнуть к
# `gh pr merge`, который откажет, — и читатель пойдёт искать причину в этом выводе,
# которого в нём нет. Наблюдалось на самом этом скрипте 2026-08-17: восемь из восьми
# зелёных при `BLOCKED` и одной идущей необязательной.
case "$merge_state" in
  CLEAN|UNSTABLE|HAS_HOOKS)
    echo
    echo "merge-readiness: можно сливать — каждый обязательный контекст имеет зелёный исход"
    exit 0
    ;;
  *)
    echo
    echo "  Обязательные — все зелёные, но состояние слияния: $merge_state"
    case "$merge_state" in
      BLOCKED)  echo "    сервер держит слияние: идёт необязательная проверка, требуется обзор либо ветка устарела" ;;
      DIRTY)    echo "    конфликт с базовой веткой — догнать её и разрешить" ;;
      BEHIND)   echo "    ветка отстала от базы, а режим строгий — догнать" ;;
      DRAFT)    echo "    PR — черновик" ;;
      UNKNOWN)  echo "    сервер ещё считает состояние — спросить снова через несколько секунд" ;;
    esac
    echo
    echo "merge-readiness: обязательные пройдены, СЛИЯНИЕ ЗАДЕРЖАНО не ими"
    exit 1
    ;;
esac
