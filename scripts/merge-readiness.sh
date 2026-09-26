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
# знает про требования, живущие вне своего источника вердикта.
#
# ИСТОЧНИКОВ ВЕРДИКТА ДВА, и выбирает их устройство репозитория, а не вкус.
# Там, где у базы есть обязательные контексты (монорепо продукта), — сверка по
# их именам, описанная выше. В воркспейсе автозапуска нет по решению владельца
# 2026-09-20, дословно: «Заливай правки и сделай весь ci что бы на любом бранче
# был не активен»; «Снимай любой ci что бы совсе. Не работал но был описан в
# ямл». Обязательных контекстов у его `main` нет тем же решением, а
# `statusCheckRollup` PR ручного прогона не несёт: «проверок 0» там не значит,
# что прогона не было. Вердикт воркспейса (ws#788) — check-runs ПОСЛЕДНЕГО
# ручного прогона `ci.yaml` (`workflow_dispatch`) на голове PR: все зелёные —
# зелёное; хоть один красный — «сливать нельзя»; идёт — «нельзя сейчас»;
# прогона на голове нет — «не выполнилось». Прогон на другой sha не
# засчитывается, даже если сосед его вернул.
#
# Объявление самоистекает: если защита базы воркспейса снова требует контексты,
# источник вердикта больше не один, и скрипт отвечает кодом 2, а не выбирает
# молча.
#
# Код возврата: 0 — сливать можно; 1 — нельзя (сказано, почему);
#               2 — вердикта нет: вопрос беспредметен (нет PR, нет доступа,
#                   защита не настроена) либо проверка не выполнилась (ручного
#                   прогона на голове нет). Это НЕ «сливать нельзя».

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

# ПРОВЕРКИ ЗЕЛЁНЫЕ — ЕЩЁ НЕ «СЛИВАЙ». Сервер держит слияние и по другим причинам:
# незавершённая НЕобязательная проверка, конфликт с базой, требование обзора,
# устаревшая ветка при строгом режиме. Молча сказать «можно» значит подтолкнуть к
# `gh pr merge`, который откажет, — и читатель пойдёт искать причину в этом выводе,
# которого в нём нет. Наблюдалось на самом этом скрипте 2026-08-17: восемь из восьми
# зелёных при `BLOCKED` и одной идущей необязательной. Общий конец обоих источников
# вердикта: судит одно и то же состояние слияния.
#
# merge_state_verdict <что зелёное> <что пройдено>
merge_state_verdict() {
  case "$merge_state" in
    CLEAN|UNSTABLE|HAS_HOOKS)
      echo
      echo "merge-readiness: можно сливать — $1"
      exit 0
      ;;
    *)
      echo
      echo "  $2 — все зелёные, но состояние слияния: $merge_state"
      case "$merge_state" in
        BLOCKED)  echo "    сервер держит слияние: идёт необязательная проверка, требуется обзор либо ветка устарела" ;;
        DIRTY)    echo "    конфликт с базовой веткой — догнать её и разрешить" ;;
        BEHIND)   echo "    ветка отстала от базы, а режим строгий — догнать" ;;
        DRAFT)    echo "    PR — черновик" ;;
        UNKNOWN)  echo "    сервер ещё считает состояние — спросить снова через несколько секунд" ;;
      esac
      echo
      echo "merge-readiness: проверки пройдены, СЛИЯНИЕ ЗАДЕРЖАНО не ими"
      exit 1
      ;;
  esac
}

pr_json=$(gh pr view "$PR" -R "$REPO" --json state,baseRefName,headRefName,headRefOid,mergeStateStatus,statusCheckRollup 2>/dev/null) || {
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

# ── ИСТОЧНИК ВЕРДИКТА ВОРКСПЕЙСА: РУЧНОЙ ПРОГОН НА ГОЛОВЕ PR (ws#788) ──────────
# Имя репозитория GitHub регистр не различает, поэтому сравнение — без регистра.
manual_workflow=""
if [ "${REPO,,}" = "pro-robotech/kacho-workspace" ]; then
  manual_workflow="ci.yaml"
fi

if [ -n "$manual_workflow" ]; then
  head_sha=$(jq -r '.headRefOid // empty' <<<"$pr_json")
  head_ref=$(jq -r '.headRefName // empty' <<<"$pr_json")
  [ -n "$head_sha" ] \
    || parse_broken "у PR $REPO#$PR в ответе нет headRefOid" \
                    "голова неизвестна — прогон на ней не найти."

  # Предпосылка объявления, а не источник вердикта: защита базы НЕ требует
  # контекстов. Незащищённая база (ветка волны, ветка эпика) здесь законна — её
  # вердикт тот же ручной прогон; непустой ответ, не являющийся JSON, — отказ соседа.
  protection=$(gh api "repos/$REPO/branches/$base/protection" 2>/dev/null || true)
  if [ -n "$protection" ]; then
    jq -e 'type == "object"' >/dev/null 2>&1 <<<"$protection" \
      || parse_broken "ответ о защите ветки '$base' не разбирается как объект JSON" \
                      "предпосылку «контекстов защита не требует» проверить нечем."
    ws_required=$(jq -r '.required_status_checks.contexts[]?' <<<"$protection" | grep -c . || true)
    if [ "${ws_required:-0}" -gt 0 ]; then
      echo "merge-readiness: защита ветки '$base' требует обязательных контекстов: $ws_required —"
      echo "                 объявление «вердикт воркспейса — ручной прогон» расходится с сервером."
      echo "                 Источников вердикта стало два; вердикта нет, пока не выбран заново (ws#788)."
      exit 2
    fi
  fi

  runs_json=$(gh api "repos/$REPO/actions/workflows/$manual_workflow/runs?event=workflow_dispatch&head_sha=$head_sha&per_page=100" 2>/dev/null) || {
    echo "merge-readiness: прогоны $manual_workflow репозитория $REPO недоступны" >&2; exit 2; }
  jq -e 'type == "object" and (.workflow_runs | type == "array")' >/dev/null 2>&1 <<<"$runs_json" \
    || parse_broken "ответ о прогонах $manual_workflow не разбирается как объект со списком workflow_runs" \
                    "сосед вернул не то, что обещает контракт API."

  # ПОСЛЕДНИЙ ручной прогон на ЭТОЙ голове. Фильтр по sha и событию стоит и здесь,
  # а не только в запросе: прогон на прежней голове судил другое дерево.
  run=$(jq -c --arg sha "$head_sha" \
    '[.workflow_runs[] | select(.head_sha == $sha and .event == "workflow_dispatch")]
     | sort_by(.created_at, .id) | last // empty' <<<"$runs_json")

  echo "merge-readiness: $REPO#$PR → $base"
  echo "  источник вердикта: ручной прогон $manual_workflow (workflow_dispatch) на голове $head_sha"
  echo "  statusCheckRollup PR: проверок $(jq '[.statusCheckRollup[]?] | length' <<<"$pr_json") — источником вердикта не служит"

  if [ -z "$run" ]; then
    echo "  ручных прогонов на голове: 0"
    echo
    echo "merge-readiness: НЕ ВЫПОЛНИЛОСЬ — ручного прогона на голове нет; вердикта нет, это НЕ «сливать нельзя»"
    echo "                 запуск: gh workflow run $manual_workflow -R $REPO --ref ${head_ref:-<ветка PR>}"
    exit 2
  fi

  run_id=$(jq -r '.id' <<<"$run")
  run_status=$(jq -r '.status // ""' <<<"$run")
  run_concl=$(jq -r '.conclusion // ""' <<<"$run")
  run_suite=$(jq -r '.check_suite_id // empty' <<<"$run")
  [ -n "$run_suite" ] \
    || parse_broken "у прогона $run_id нет check_suite_id" \
                    "его check-runs от чужих на той же sha не отличить."

  cr_json=$(gh api "repos/$REPO/commits/$head_sha/check-runs?per_page=100&filter=latest" 2>/dev/null) || {
    echo "merge-readiness: check-runs коммита $head_sha недоступны" >&2; exit 2; }
  jq -e 'type == "object" and (.check_runs | type == "array")' >/dev/null 2>&1 <<<"$cr_json" \
    || parse_broken "ответ о check-runs коммита не разбирается как объект со списком check_runs" \
                    "сосед вернул не то, что обещает контракт API."
  # Усечённый ответ — не вердикт: недочитанная страница могла нести красное.
  jq -e '(.total_count // 0) <= (.check_runs | length)' >/dev/null 2>&1 <<<"$cr_json" \
    || parse_broken "check-runs коммита усечены: $(jq -r '"получено \(.check_runs | length) из \(.total_count)"' <<<"$cr_json")" \
                    "непрочитанная страница могла нести красное."

  # Только check-runs ЭТОГО прогона: на той же sha бывают прогоны прежних запусков.
  suite_runs=$(jq -c --argjson s "$run_suite" '[.check_runs[] | select(.check_suite.id == $s)]' <<<"$cr_json")
  RED_SET='["failure","timed_out","cancelled","action_required","startup_failure","stale"]'
  cr_total=$(jq 'length' <<<"$suite_runs")
  cr_green=$(jq '[.[] | select(.status == "completed" and .conclusion == "success")] | length' <<<"$suite_runs")
  cr_red=$(jq -r --argjson r "$RED_SET" '.[] | select(.status == "completed" and (.conclusion as $c | $r | index($c)) != null) | .name + " [" + (.conclusion | ascii_upcase) + "]"' <<<"$suite_runs" | LC_ALL=C sort)
  cr_running=$(jq -r '.[] | select(.status != "completed") | .name' <<<"$suite_runs" | LC_ALL=C sort)
  cr_void=$(jq -r --argjson r "$RED_SET" '.[] | select(.status == "completed" and .conclusion != "success" and (.conclusion as $c | $r | index($c)) == null) | .name + " [" + ((.conclusion // "без исхода") | ascii_upcase) + "]"' <<<"$suite_runs" | LC_ALL=C sort)
  red_count=$(printf '%s\n' "$cr_red" | grep -c . || true)
  running_count=$(printf '%s\n' "$cr_running" | grep -c . || true)
  void_count=$(printf '%s\n' "$cr_void" | grep -c . || true)

  echo "  прогон: $run_id · состояние $run_status · исход ${run_concl:-нет}"
  echo "  check-runs: $cr_total · зелёных: $cr_green · красных: $red_count · идут: $running_count · без исхода: $void_count · состояние слияния: $merge_state"

  # Исход прогона целиком — отдельно от его check-runs: прогон, не поднявший ни
  # одного задания (`startup_failure`), красен при пустом перечне.
  run_red=$(jq -n --arg c "$run_concl" --argjson r "$RED_SET" 'if ($r | index($c)) != null then 1 else 0 end')
  if [ "$red_count" -gt 0 ] || [ "$run_red" -eq 1 ]; then
    echo "  КРАСНЫЕ:"
    [ "$red_count" -gt 0 ] && printf '%s\n' "$cr_red" | sed 's/^/    /'
    [ "$run_red" -eq 1 ] && echo "    прогон $run_id целиком [$(printf '%s' "$run_concl" | tr '[:lower:]' '[:upper:]')]"
    echo
    echo "merge-readiness: СЛИВАТЬ НЕЛЬЗЯ — ручной прогон на голове красный"
    exit 1
  fi
  if [ "$running_count" -gt 0 ] || [ "$run_status" != "completed" ]; then
    echo "  ИДУТ:"
    printf '%s\n' "$cr_running" | sed '/^$/d; s/^/    /'
    echo
    echo "merge-readiness: СЛИВАТЬ НЕЛЬЗЯ — ручной прогон на голове идёт"
    exit 1
  fi
  if [ "$cr_total" -eq 0 ] || [ "$void_count" -gt 0 ] || [ "$cr_green" -ne "$cr_total" ]; then
    [ "$void_count" -gt 0 ] && { echo "  БЕЗ ИСХОДА:"; printf '%s\n' "$cr_void" | sed 's/^/    /'; }
    echo
    echo "merge-readiness: НЕ ВЫПОЛНИЛОСЬ — зелёных $cr_green из $cr_total check-runs прогона $run_id; вердикта нет"
    exit 2
  fi

  merge_state_verdict "все $cr_total check-runs ручного прогона $run_id на голове зелёные" "Check-runs ручного прогона"
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
  echo "                 слияние ничем не гейтится. Это находка, а не норма."
  exit 2
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

# Обязательные зелёные — дальше судит состояние слияния (`merge_state_verdict`).
merge_state_verdict "каждый обязательный контекст имеет зелёный исход" "Обязательные"
