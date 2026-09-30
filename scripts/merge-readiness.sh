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
#               2 — вердикта нет (нет PR, нет доступа, защита не настроена,
#                   прогона на голове PR нет или он ещё идёт).
#
# РЕПОЗИТОРИЙ БЕЗ ОБЯЗАТЕЛЬНЫХ КОНТЕКСТОВ (ws#884). Защита `main` воркспейса
# читается, а обязательных контекстов у неё ноль, конвейер же запускается
# `workflow_dispatch` и к PR не привязан: `statusCheckRollup` пуст. Прежде
# инструмент отвечал здесь кодом 2 на КАЖДОМ PR, и PR вливались при нуле проверок
# (#715, #763, #768, #806, #809). Теперь для этого — и только для этого — случая
# вердикт берётся из прогона `ci.yaml` событием `workflow_dispatch` ровно на
# голове PR (`headRefOid`): все задания зелёные — 0; любое красное, отменённое,
# просроченное — 1; прогона на голове нет, он идёт или задание не выполнилось —
# 2. Прогон на другой ревизии или другим событием НЕ засчитывается, даже если
# сервер вернул его в ответе: фильтр сервера — обещание, засчитывается только
# сверенное здесь. На голове несколько прогонов — судит последний по времени
# создания: он и есть ответ на вопрос «что сейчас».
#
# Ветка вовсе без защиты сюда НЕ ведёт: чтение защиты требует прав
# администратора, и «защиты нет» неотличимо от «прав нет» — подставить вердикт
# процесса там, где обязательные контексты есть, но не прочитаны, значило бы
# выдать ложное зелёное. Репозиторий с обязательными контекстами процесс не
# читает вовсе: поведение там прежнее.

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

pr_json=$(gh pr view "$PR" -R "$REPO" --json state,baseRefName,headRefOid,mergeStateStatus,statusCheckRollup 2>/dev/null) || {
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
head_sha=$(jq -r '.headRefOid // ""' <<<"$pr_json")

# Процесс, чей прогон судит репозиторий без обязательных контекстов.
CI_WORKFLOW="ci.yaml"

# merge_state_verdict <что зелёное> <чем зелёное названо в задержке> <то же в итоговой строке>
#
# Третий аргумент передаётся готовым, а не выводится `${,,}`: под байтовой
# локалью bash кириллицу в нижний регистр не переводит.
#
# ЗЕЛЁНЫЕ ПРОВЕРКИ — ЕЩЁ НЕ «СЛИВАЙ». Сервер держит слияние и по другим причинам:
# незавершённая НЕобязательная проверка, конфликт с базой, требование обзора,
# устаревшая ветка при строгом режиме. Молча сказать «можно» значит подтолкнуть к
# `gh pr merge`, который откажет, — и читатель пойдёт искать причину в этом выводе,
# которого в нём нет. Наблюдалось на самом этом скрипте 2026-08-17: восемь из восьми
# зелёных при `BLOCKED` и одной идущей необязательной.
merge_state_verdict() {
  local green_what="$1" held_what="$2" held_tail="$3"
  case "$merge_state" in
    CLEAN|UNSTABLE|HAS_HOOKS)
      echo
      echo "merge-readiness: можно сливать — $green_what"
      exit 0
      ;;
    *)
      echo
      echo "  $held_what — все зелёные, но состояние слияния: $merge_state"
      case "$merge_state" in
        BLOCKED)  echo "    сервер держит слияние: идёт необязательная проверка, требуется обзор либо ветка устарела" ;;
        DIRTY)    echo "    конфликт с базовой веткой — догнать её и разрешить" ;;
        BEHIND)   echo "    ветка отстала от базы, а режим строгий — догнать" ;;
        DRAFT)    echo "    PR — черновик" ;;
        UNKNOWN)  echo "    сервер ещё считает состояние — спросить снова через несколько секунд" ;;
      esac
      echo
      echo "merge-readiness: $held_tail пройдены, СЛИЯНИЕ ЗАДЕРЖАНО не ими"
      exit 1
      ;;
  esac
}

# verdict_from_dispatched_run — вердикт по прогону $CI_WORKFLOW (workflow_dispatch)
# ровно на голове PR. Зовётся ТОЛЬКО когда защита прочитана и обязательных
# контекстов у неё ноль. Всегда завершает скрипт.
verdict_from_dispatched_run() {
  local runs_json run other run_id run_status run_concl run_url jobs_json
  local jobs_total jobs_listed green_jobs red_jobs open_jobs void_jobs
  local green_n red_n open_n void_n

  [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] \
    || parse_broken "голова PR не прочитана: headRefOid='$head_sha'" \
                    "без неё прогон не с чем сверять."

  runs_json=$(gh api "repos/$REPO/actions/workflows/$CI_WORKFLOW/runs?event=workflow_dispatch&head_sha=$head_sha&per_page=100" 2>/dev/null) || {
    echo "merge-readiness: прогоны $CI_WORKFLOW в $REPO недоступны — ВЕРДИКТА НЕТ" >&2; exit 2; }
  jq -e 'type == "object" and (.workflow_runs | type == "array")' >/dev/null 2>&1 <<<"$runs_json" \
    || parse_broken "ответ о прогонах $CI_WORKFLOW не разбирается как объект с workflow_runs" \
                    "сосед вернул не то, что обещает контракт Actions API."

  run=$(jq -c --arg sha "$head_sha" \
    '[.workflow_runs[] | select(.head_sha == $sha and .event == "workflow_dispatch")]
     | sort_by(.created_at, .id) | last // empty' <<<"$runs_json")
  other=$(jq --arg sha "$head_sha" \
    '[.workflow_runs[] | select(.head_sha != $sha or .event != "workflow_dispatch")] | length' <<<"$runs_json")

  echo "merge-readiness: $REPO#$PR → $base"
  echo "  голова PR: $head_sha · вердикт — прогон $CI_WORKFLOW (workflow_dispatch) на ней"
  if [ "$other" -gt 0 ]; then
    echo "  прогонов на другой ревизии или другим событием в ответе — не засчитаны: $other"
  fi

  if [ -z "$run" ]; then
    echo "  прогона $CI_WORKFLOW (workflow_dispatch) на голове PR НЕТ"
    echo "  запустить: gh workflow run $CI_WORKFLOW -R $REPO --ref <ветка PR>"
    echo
    echo "merge-readiness: ВЕРДИКТА НЕТ — прогона на голове PR нет; это НЕ «сливать нельзя»"
    exit 2
  fi

  run_id=$(jq -r '.id' <<<"$run")
  run_status=$(jq -r '.status // ""' <<<"$run")
  run_concl=$(jq -r '.conclusion // ""' <<<"$run")
  run_url=$(jq -r '.html_url // ""' <<<"$run")
  [[ "$run_id" =~ ^[0-9]+$ ]] || parse_broken "у прогона на голове нет номера: id='$run_id'"
  echo "  прогон: $run_url · состояние: $run_status${run_concl:+ · исход: $run_concl}"

  if [ "$run_status" != "completed" ]; then
    echo
    echo "merge-readiness: ВЕРДИКТА НЕТ — прогон на голове PR ещё идёт; спросить снова по его завершении"
    exit 2
  fi

  jobs_json=$(gh api "repos/$REPO/actions/runs/$run_id/jobs?per_page=100" 2>/dev/null) || {
    echo "merge-readiness: задания прогона $run_id недоступны — ВЕРДИКТА НЕТ" >&2; exit 2; }
  jq -e 'type == "object" and (.jobs | type == "array") and (.total_count | type == "number")' >/dev/null 2>&1 <<<"$jobs_json" \
    || parse_broken "ответ о заданиях прогона $run_id не разбирается как объект с jobs и total_count"

  # Перепись: заданий прочитано столько, сколько сервер объявил. Недочитанная
  # страница — не «все зелёные», а неполный вход.
  jobs_total=$(jq -r '.total_count' <<<"$jobs_json")
  jobs_listed=$(jq -r '.jobs | length' <<<"$jobs_json")
  if [ "$jobs_total" -ne "$jobs_listed" ]; then
    parse_broken "заданий прогона $run_id объявлено $jobs_total, прочитано $jobs_listed" \
                 "вход неполон — судить по части нельзя."
  fi
  if [ "$jobs_total" -eq 0 ]; then
    echo "  заданий в прогоне 0"
    echo
    echo "merge-readiness: ВЕРДИКТА НЕТ — прогон завершён, не исполнив ни одного задания"
    exit 2
  fi

  green_jobs=$(jq -r '.jobs[] | select(.status == "completed" and .conclusion == "success") | .name' <<<"$jobs_json")
  red_jobs=$(jq -r '.jobs[] | select(.conclusion == "failure" or .conclusion == "cancelled" or .conclusion == "timed_out"
                                     or .conclusion == "action_required" or .conclusion == "startup_failure")
                            | .name + " [" + .conclusion + "]"' <<<"$jobs_json")
  open_jobs=$(jq -r '.jobs[] | select(.status != "completed") | .name + " [" + .status + "]"' <<<"$jobs_json")
  void_jobs=$(jq -r '.jobs[] | select(.status == "completed")
                             | select((.conclusion // "") as $c
                                      | ["success","failure","cancelled","timed_out","action_required","startup_failure"]
                                      | index($c) | not)
                             | .name + " [" + (.conclusion // "без исхода") + "]"' <<<"$jobs_json")
  green_n=$(printf '%s\n' "$green_jobs" | grep -c . || true)
  red_n=$(printf '%s\n' "$red_jobs" | grep -c . || true)
  open_n=$(printf '%s\n' "$open_jobs" | grep -c . || true)
  void_n=$(printf '%s\n' "$void_jobs" | grep -c . || true)

  echo "  заданий $jobs_total · зелёных $green_n · красных $red_n · идут $open_n · не выполнилось $void_n · состояние слияния: $merge_state"

  if [ "$red_n" -gt 0 ]; then
    echo "  КРАСНЫЕ:"
    printf '%s\n' "$red_jobs" | sed 's/^/    /'
    echo
    echo "merge-readiness: СЛИВАТЬ НЕЛЬЗЯ"
    exit 1
  fi
  if [ "$open_n" -gt 0 ]; then
    echo "  ИДУТ:"
    printf '%s\n' "$open_jobs" | sed 's/^/    /'
    echo
    echo "merge-readiness: ВЕРДИКТА НЕТ — задания прогона ещё идут"
    exit 2
  fi
  if [ "$void_n" -gt 0 ]; then
    echo "  НЕ ВЫПОЛНИЛОСЬ (не красное и не зелёное):"
    printf '%s\n' "$void_jobs" | sed 's/^/    /'
    echo
    echo "merge-readiness: ВЕРДИКТА НЕТ — задание не выполнилось; это НЕ «сливать нельзя»"
    exit 2
  fi
  if [ "$green_n" -ne "$jobs_total" ] || [ "$run_concl" != "success" ]; then
    parse_broken "задания прогона $run_id зелёных $green_n из $jobs_total, а исход прогона '$run_concl'" \
                 "исход прогона и исходы его заданий не сходятся."
  fi

  merge_state_verdict "каждое задание прогона $CI_WORKFLOW на голове PR имеет зелёный исход" \
                      "Задания прогона $CI_WORKFLOW" "задания прогона $CI_WORKFLOW"
}

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

jq -e 'type == "object"' >/dev/null 2>&1 <<<"$protection" \
  || parse_broken "ответ о защите ветки '$base' не разбирается как объект JSON" \
                  "непустой ответ, который не является JSON, — это отказ соседа," \
                  "а не отсутствие защиты: молча прочитать его как «защиты нет»" \
                  "значило бы подменить один исход другим."

required=$(jq -r '.required_status_checks.contexts[]?' <<<"$protection" | LC_ALL=C sort -u)
req_count=$(printf '%s\n' "$required" | grep -c . || true)

if [ "${req_count:-0}" -eq 0 ]; then
  echo "merge-readiness: у ветки '$base' защита есть, а обязательных контекстов ноль —"
  echo "                 сервер слияние ничем не гейтит. Это находка, а не норма;"
  echo "                 вердикт берётся из прогона $CI_WORKFLOW на голове PR."
  verdict_from_dispatched_run
fi

# Исходы на ревизии PR. Один контекст может встретиться дважды (перезапуск),
# поэтому зелёным считается имя, у которого ЕСТЬ успешный исход.
green=$(jq -r '.statusCheckRollup[]? | select(.conclusion=="SUCCESS") | (.name // .context)' <<<"$pr_json" | LC_ALL=C sort -u)
red=$(jq -r '.statusCheckRollup[]? | select(.conclusion=="FAILURE" or .conclusion=="TIMED_OUT" or .conclusion=="CANCELLED" or .conclusion=="ACTION_REQUIRED") | (.name // .context) + " [" + .conclusion + "]"' <<<"$pr_json" | LC_ALL=C sort -u)
running=$(jq -r '.statusCheckRollup[]? | select((.conclusion // "")=="") | (.name // .context)' <<<"$pr_json" | LC_ALL=C sort -u)

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

# Обязательные зелёные — ещё не «сливай»: почему, сказано у merge_state_verdict.
merge_state_verdict "каждый обязательный контекст имеет зелёный исход" "Обязательные" "обязательные"
