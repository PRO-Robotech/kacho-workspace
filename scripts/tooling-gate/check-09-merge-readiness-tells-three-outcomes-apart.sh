#!/usr/bin/env bash
# check-09 — merge-readiness различает ТРИ исхода, и отказ его разбора не
# приходит вызывающему кодом находки.
#
# ЧТО ЗАПРЕЩАЕТ ЭТА ПРОВЕРКА. У `scripts/merge-readiness.sh` коды значат разное:
# 0 — сливать можно, 1 — СЛИВАТЬ НЕЛЬЗЯ, 2 — вопрос беспредметен (нет PR, нет
# защиты, разбор не состоялся). Инструмент, у которого собственная поломка
# выходит ЕДИНИЦЕЙ, отвечает «нельзя» всегда — и его перестают читать вместе с
# настоящей находкой.
#
# Цена измерена (ws#530). Сверка множеств шла через `comm` над входом, который
# `sort` упорядочил ПО ЛОКАЛИ: `comm` сравнивает байты и локаль не читает вовсе,
# поэтому объявлял вход неупорядоченным и выходил единицей. Под `set -e` скрипт
# умирал на этой строке, не напечатав НИ ОДНОЙ строки вердикта, и возвращал 1 —
# тот же код, каким он говорит «сливать нельзя». Так он отвечал на всех четырёх
# открытых PR, то есть не выносил вердикта вообще ни разу.
#
# Почему проверка появилась только сейчас: у инструмента НЕ БЫЛО НИ ОДНОГО
# вызывающего-проверяющего (`git grep -l merge-readiness` давал правило и
# записку). Он потерял способность выносить вердикт, и этого никто не заметил —
# ровно тот случай, ради которого гейт обязан уметь падать.
#
# ПРОВЕРКА ПОВЕДЕНЧЕСКАЯ. Искать в исходнике `LC_ALL=C` значит ловить форму:
# автор волен сверять множества иначе — на awk, на jq, на встроенном сравнении.
# Спрашивается ИСХОД: настоящему скрипту подкладывается подставной `gh` с
# заранее записанным ответом соседа, и читается код, который скрипт вернул, и
# то, что он напечатал.
#
# ПОДДЕЛКА СТРУКТУРНО НЕ СПОСОБНА ДАТЬ ЗЕЛЁНОЕ. Подставной `gh` не выносит
# вердикта: он отдаёт фикстуру, а решение целиком принимает настоящий скрипт —
# со своим `jq`, своей сортировкой и своей сверкой. Незнакомый вызов заглушка
# отвергает кодом 99, а не пустым ответом: пустой увёл бы скрипт в ветку
# «сосед недоступен» и промах провязки пришёл бы ожидаемым кодом 2. Обе стороны
# заглушки проверяются отдельной пробой ДО того, как ей верят.
#
# КАЖДАЯ ПРОБА СВЕРЯЕТ КОД И ТЕКСТ. Код 2 сам по себе неоднозначен — его дают и
# «PR недоступен», и «защита не настроена», и «разбор сломан». Проба, читающая
# только код, зеленела бы на чужой ветке.
#
# ДВА ИСТОЧНИКА ВЕРДИКТА — И ОБА ПОД ПРОБАМИ (ws#788). Для репозитория продукта
# инструмент сверяет обязательные контексты защиты базы; для воркспейса — check-runs
# ПОСЛЕДНЕГО ручного прогона `ci.yaml` на голове PR. Пробы воркспейса держат то, ради
# чего источник заведён: зелёный ручной прогон при пустом `statusCheckRollup` — код 0;
# прогона на голове нет — код 2 «не выполнилось», а не 1; красный check-run — код 1;
# прогон на ПРЕЖНЕЙ голове не засчитан; из прогонов на голове судит последний —
# и в хронологическом порядке ответа, и в порядке соседа, где новый идёт первым
# (ws#862: без второго снятие сортировки перед `last` не замечала ни одна проба), —
# и check-runs чужого прогона той же sha в счёт не идут. Три охраны инструмента
# держатся каждая своей пробой, потому что их снятие прежние пробы не замечали:
# прогон идёт при всех зелёных check-runs — код 1, а не 0; ответ о check-runs
# усечён — код 2, а не 0; прогон без заданий (`startup_failure`) — код 1, а не 2.
#
# ЧТЕНИЕ ЗАЩИТЫ И ЧЕЙ НАБОР СУДИТ (ws#844, решение диспетчера 2026-10-01).
# Подставной gh отдаёт ответ-отказ НАСТОЯЩЕЙ формы — тело в stdout и ненулевой
# код. Прежняя фикстура «не защищена» была пустым ответом, а настоящий gh пишет
# 404 «Branch not protected» телом: инструмент брал его за защиту без
# контекстов, и проба C этого не видела. Случаи C-* держат три исхода чтения,
# EP-* — набор ствола для базы-ветки линии продукта (эпик, волна), NE-* — его
# отсутствие для прочих баз. Путь воркспейса выбирается ТЕМ ЖЕ чтением: U — ветка
# линии воркспейса без защиты судится ручным прогоном, а не набором ствола (его
# контекстов на её PR не бывает: `pull_request` воркспейса сужен по `main`);
# U-EMPTY и U-403 — непрочитанная защита базы воркспейса приходит кодом 2, а не
# уходом в ручной прогон, как при прежней записи `$(gh api … || true)`.
#
# ИСТОЧНИК ВЫБИРАЕТ ЗАЩИТА БАЗЫ, А НЕ ИМЯ РЕПОЗИТОРИЯ (ws#886). С решения владельца
# 2026-10-01 задания `ci.yaml` — обязательные контексты `main` воркспейса, и PR
# воркспейса в защищённую контекстами базу судится путём контекстов: зелёный ручной
# прогон их не заменяет (проба P — код 1 при отсутствующем контексте), а пробы
# RC-*, A-*, Z-*, WA гонят путь контекстов именем воркспейса. Ручной прогон остаётся
# путём баз без требования контекстов — ветки эпика и волны (пробы J…X, U).
#
# ЗЕЛЁНЫЙ — ТОЛЬКО ИСХОД SUCCESS (ws#884). Каждый иной исход проверки (восемь, плюс
# «идёт») держит своя проба RC-*, а не повтор перечня красных инструмента; каждое
# удерживающее состояние слияния — проба A-*, законное «можно» — Z-*. Пробы исполняют
# инструмент под локалью, ЗАМЕРЕННОЙ как расходящаяся с байтовым порядком, и перепись
# её называет. Имя пробы начинается меткой случая `[<буква>]`: по ней `inject.sh`
# сверяет, что порча решения покраснила ИМЕННО держащую его пробу.
#
# ГОЛОВА PR — УРОВЕНЬ КАСКАДА (ws#909). Вливание снимает голову PR
# (`delete_branch_on_merge=true`), поэтому PR, чья голова — ветка эпика или волны, законен
# только ВВЕРХ: в ствол либо в ветку задачи-родителя. Синхронизация вниз такой головой
# сняла ветку эпика kaname `296` (PR #576, 2026-10-03). Уровень — задача ветки с дочерними
# либо с меткой `epic`; признак берётся у трекера, имя ветки задачи от имени волны не
# отличает. Случаи CL-* держат: вниз по дочерним, вниз по метке, родитель из чужого
# репозитория с тем же номером — код 1; вверх в родителя, вверх в ствол, голова `tmp/*`,
# ветка задачи синхронизации в форме каждого репозитория — код 0; задача не прочитана,
# номер ветки — запрос, родитель не прочитан — код 2. Голова прочих случаев — задача
# без дочерних (`issue@788`, её кладёт `mkcase`).
#
# ПОДСКАЗКА ОБЯЗАНА БЫТЬ ИСПОЛНИМОЙ В РЕПОЗИТОРИИ PR (ws#910). Прежняя называла
# `tmp/sync-…`, а kaname такую голову отвергает (`branch-rule.sh`: ветка — `^[0-9]+$`,
# исключение `main`): норма была невыполнима, и догон `296` → `536` прошёл веткой задачи
# `584` (kaname#585). Форма — ветка задачи синхронизации N: в kaname `<N>`, в прочих
# `<N>-sync-<M>-into-<цель>` (`<N>-<суть>`; `tmp/*` там черновик без проверок отправки).
# CL-DOWN и CL-DOWN-KANAME сверяют форму по репозиторию, CL-SYNC-TASK и CL-SYNC-KANAME —
# что голова этой формы проходит инструмент.
#
# Предпосылка проверки (исход VOID): в дереве есть сам инструмент, есть `jq`, и
# подставной `gh` доказал обе свои стороны. Отсутствие любого из трёх — «не
# выполнилось», а не «находок нет».
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)" || exit 2
NAME="check-09-merge-readiness-tells-three-outcomes-apart"
TOOL_REL="scripts/merge-readiness.sh"

if [ -z "$(tooling_gate_files "$WS" "$TOOL_REL")" ]; then
    tooling_gate_void "$NAME" "$TOOL_REL в дереве нет — проверять нечего"
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    tooling_gate_void "$NAME" "jq не найден — инструмент не запустить, вердикта не будет"
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── ПОДСТАВНОЙ СОСЕД ─────────────────────────────────────────────────────────
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Подставной gh: отдаёт заранее записанный ответ и НИЧЕГО не решает.
# Незнакомый вызов — жёсткий отказ, а не пустой ответ: пустой прошёл бы за
# «сосед недоступен» и замаскировал промах провязки успехом.
# Ответ выбирается по ПУТИ запроса, а не по глаголу: у инструмента три разных
# вопроса к `gh api`, и один ответ на все три провязку не доказывал бы.
set -u
# Фикстура защиты — СВОЯ НА КАЖДУЮ ВЕТКУ (`protection@<ветка>`): чтение защиты
# ветки, у которой фикстуры нет (например, ствола там, где набор ствола брать
# не положено), — отказ 98, а не ответ.
case "${1:-}" in
    pr)  target="${MR_FIXTURE:?}/pr" ;;
    api)
        case "${2:-}" in
            repos/*/branches/*/protection)
                br="${2#*/branches/}"; br="${br%/protection}"
                target="${MR_FIXTURE:?}/protection@$br" ;;
            repos/*/actions/workflows/*/runs\?*) target="${MR_FIXTURE:?}/runs" ;;
            repos/*/commits/*/check-runs\?*)     target="${MR_FIXTURE:?}/checkruns" ;;
            repos/*/issues/*/parent)
                n="${2#*/issues/}"; n="${n%/parent}"
                target="${MR_FIXTURE:?}/parent@$n" ;;
            repos/*/issues/*)
                target="${MR_FIXTURE:?}/issue@${2##*/}" ;;
            *) echo "gh-stub: незнакомый путь api: $*" >&2; exit 99 ;;
        esac ;;
    *)   echo "gh-stub: незнакомый вызов: $*" >&2; exit 99 ;;
esac
if [ -e "$target.unavailable" ]; then exit 1; fi
# Вопрос, на который фикстура не заготовлена, — отказ 98, а не пустой ответ.
[ -e "$target.json" ] || { echo "gh-stub: нет фикстуры $target.json на: $*" >&2; exit 98; }
cat "$target.json"
# `<цель>.rc` — код выхода настоящего gh при ответе-отказе: тело отказа он
# пишет в STDOUT и выходит ненулевым (замер gh 2.100.0, 2026-10-01, ws#844).
if [ -e "$target.rc" ]; then exit "$(cat "$target.rc")"; fi
STUBEOF
chmod +x "$STUB/gh"

# ── ФИКСТУРЫ ─────────────────────────────────────────────────────────────────
# Имена контекстов намеренно смешанные: латиница, латиница с длинным тире и
# кириллица. Это НЕ украшение — именно на таком наборе байтовый и локальный
# порядок расходятся, и именно он ронял инструмент.
CTX_LAT="bats-and-shellcheck"
CTX_DASH="authz-fixtures bootstrap — lint (KAC-122)"
CTX_CYR="доказательства хуков инъекцией исполняются, а не лежат"

# Каждый случай несёт задачу головы по умолчанию — `788`, лист без дочерних и без
# метки `epic`: голова прочих случаев уровнем каскада не является.
mkcase() {
    local d="$TMP/case-$1"; mkdir -p "$d"
    mk_issue "$d" 788 0
    printf '%s' "$d"
}

# mk_issue <каталог> <номер> <дочерних> [<метка>...] — ответ о задаче ветки головы.
mk_issue() {
    local d="$1" n="$2" subs="$3"; shift 3
    printf '%s\n' "$@" | jq -R 'select(length > 0) | {name: .}' | jq -s \
        --argjson n "$n" --argjson s "$subs" \
        '{number: $n, labels: ., sub_issues_summary: {total: $s, completed: 0}}' > "$d/issue@$n.json"
}

# mk_parent <каталог> <номер> <репозиторий родителя> <номер родителя> — родитель задачи.
mk_parent() {
    jq -n --argjson p "$4" --arg u "https://github.com/$3/issues/$4" \
        '{number: $p, html_url: $u}' > "$1/parent@$2.json"
}

mk_protection() {  # <файл> <контекст>...
    local f="$1"; shift
    printf '%s\n' "$@" | jq -R . | jq -s '{required_status_checks:{contexts:.}}' > "$f"
}

HEAD_SHA="1111111111111111111111111111111111111111"
OLD_SHA="2222222222222222222222222222222222222222"

# База PR — `MR_BASE` (по умолчанию `main`): для случаев ветки линии задаётся
# на вызов.
mk_pr() {  # <файл> <состояние> <состояние-слияния> <зелёный-контекст>...
    local f="$1" st="$2" ms="$3"; shift 3
    local rollup='[]'
    if [ "$#" -gt 0 ]; then
        rollup="$(printf '%s\n' "$@" | jq -R '{name: ., conclusion: "SUCCESS"}' | jq -s .)"
    fi
    jq -n --arg st "$st" --arg ms "$ms" --arg h "$HEAD_SHA" --arg b "${MR_BASE:-main}" --argjson r "$rollup" \
        --arg hd "${MR_HEAD:-788}" \
        '{state:$st, baseRefName:$b, headRefName:$hd, headRefOid:$h,
          mergeStateStatus:$ms, statusCheckRollup:$r}' > "$f"
}

# mk_pr_mixed <файл> <состояние-слияния> <имя=ИСХОД>... — rollup с НЕзелёными
# записями. Пустой исход — контекст идёт (`conclusion: null`). Без такой фикстуры
# решение «контекст зелёный только по исходу SUCCESS» не держала ни одна проба:
# `mk_pr` пишет одни SUCCESS, и фильтр, снятый до `select(true)`, давал ложное
# «можно» при зелёном check-09 (возврат check-verifier @4a02d37a9).
mk_pr_mixed() {
    local f="$1" ms="$2"; shift 2
    local rollup
    rollup="$(printf '%s\n' "$@" | jq -R 'capture("^(?<name>.*)=(?<c>[A-Z_]*)$")
        | {name, status:(if .c=="" then "IN_PROGRESS" else "COMPLETED" end),
           conclusion:(if .c=="" then null else .c end)}' | jq -s .)"
    jq -n --arg ms "$ms" --arg b "${MR_BASE:-main}" --argjson r "$rollup" \
        '{state:"OPEN", baseRefName:$b, mergeStateStatus:$ms, statusCheckRollup:$r}' > "$f"
}

# mk_refusal <каталог> <ветка> <код> <тело> — ответ-отказ настоящей формы:
# тело в stdout и ненулевой код. Тело 404 «Branch not protected» — дословно
# то, что gh 2.100.0 вернул 2026-10-01 на `branches/2914-notify/protection`.
BODY_UNPROTECTED='{"message":"Branch not protected","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"404"}'
mk_refusal() {
    printf '%s\n' "$4" > "$1/protection@$2.json"
    printf '%s\n' "$3" > "$1/protection@$2.rc"
}

# mk_runs <файл> <id,sha,status,conclusion,created_at,suite>... — ответ о ручных
# прогонах. Сосед вправе вернуть и прогон чужой sha: фильтр обязан стоять у инструмента.
mk_runs() {
    local f="$1"; shift
    printf '%s\n' "$@" | jq -R 'split(",") | {id: (.[0]|tonumber), head_sha: .[1],
        event: "workflow_dispatch", status: .[2], conclusion: (if .[3] == "" then null else .[3] end),
        created_at: .[4], check_suite_id: (.[5]|tonumber), run_attempt: 1}' \
        | jq -s '{total_count: length, workflow_runs: .}' > "$f"
}

# mk_checkruns <файл> <suite|name|status|conclusion>... — check-runs коммита.
mk_checkruns() {
    local f="$1"; shift
    printf '%s\n' "$@" | jq -R 'split("|") | {check_suite: {id: (.[0]|tonumber)}, name: .[1],
        status: .[2], conclusion: (if .[3] == "" then null else .[3] end)}' \
        | jq -s '{total_count: length, check_runs: .}' > "$f"
}

# Защита без требования контекстов: `enforce_admins` включён, контекстов нет
# (такой была защита `main` воркспейса до ws#886; с ним `main` требует контексты).
mk_ws_protection() { printf '{"enforce_admins":{"enabled":true}}\n' > "$1"; }

# A — все обязательные зелены.
A="$(mkcase A)"
mk_protection "$A/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
mk_pr "$A/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"

# B — обязательный контекст не появлялся на ревизии (случай kacho#614).
B="$(mkcase B)"
mk_protection "$B/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
mk_pr "$B/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH"

# C — защита ветки не настроена: ответ настоящей формы, 404 «Branch not
# protected» в stdout и код 1. Прежняя фикстура (пустой ответ) этой формы не
# знала, и инструмент, бравший тело отказа за защиту без контекстов, проходил
# пробу (ws#844). База `main` — не ветка линии, набора ствола ей не положено.
C="$(mkcase C)"
mk_pr "$C/pr.json" OPEN CLEAN "$CTX_LAT"
mk_refusal "$C" main 1 "$BODY_UNPROTECTED"

# C-<отказ> — защита НЕ ПРОЧИТАНА: отказ, который не говорит «не защищена».
# Против C меняется ровно ответ соседа. Каждый обязан прийти третьим исходом
# чтения, а не «НЕ ЗАЩИЩЕНА» и не «защита есть, контекстов ноль».
#   EMPTY — код 1 без тела (сеть, обрыв);
#   403   — тело JSON другого статуса;
#   404NF — тот же статус 404, но «Not Found» (у токена нет права читать защиту).
d="$(mkcase C-EMPTY)"; mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT"; : > "$d/protection@main.unavailable"
d="$(mkcase C-403)";   mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT"
mk_refusal "$d" main 1 '{"message":"Resource not accessible by integration","status":"403"}'
d="$(mkcase C-404NF)"; mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT"
mk_refusal "$d" main 1 '{"message":"Not Found","status":"404"}'

# D — PR недоступен.
D="$(mkcase D)"
: > "$D/pr.unavailable"
: > "$D/pr.json"
mk_protection "$D/protection@main.json" "$CTX_LAT"

# E — ответ о защите не разбирается.
E="$(mkcase E)"
mk_pr "$E/pr.json" OPEN CLEAN "$CTX_LAT"
printf '<html><head><title>503</title></head></html>\n' > "$E/protection@main.json"

# F — ответ о PR не разбирается.
F="$(mkcase F)"
printf '<html><head><title>502</title></head></html>\n' > "$F/pr.json"
mk_protection "$F/protection@main.json" "$CTX_LAT"

# G — защита есть, обязательных контекстов ноль.
G="$(mkcase G)"
mk_pr "$G/pr.json" OPEN CLEAN
printf '{"required_status_checks":{"contexts":[]}}\n' > "$G/protection@main.json"

# H — два обязательных имени, различающихся ТОЛЬКО длинным тире.
#
# Это не экзотика, а второй дефект той же строки. Локальный `sort -u` считает
# такие имена ОДНИМ и выбрасывает одно из них: недостающий обязательный контекст
# молча исчезает из перечня, и инструмент отвечает «можно сливать» ровно там,
# где обязан сказать «нельзя». Ложное зелёное здесь дороже ложного красного:
# именно его этот инструмент и заведён предотвращать.
H="$(mkcase H)"
mk_protection "$H/protection@main.json" "проба — раз" "проба - раз"
mk_pr "$H/pr.json" OPEN CLEAN "проба — раз"

# I — PR уже не открыт.
I="$(mkcase I)"
mk_pr "$I/pr.json" MERGED CLEAN "$CTX_LAT"
mk_protection "$I/protection@main.json" "$CTX_LAT"

# ── С ОБЯЗАТЕЛЬНЫМИ КОНТЕКСТАМИ: ЗЕЛЁНЫЙ — ТОЛЬКО ИСХОД SUCCESS ────────────────
# RC-<исход> — обязательный контекст на ревизии ЕСТЬ, но не зелёный: идёт
# (`running`, conclusion null) либо красный. Против A меняется ровно один факт —
# исход записи CTX_CYR. Это класс kacho#614 на основном пути: идущий или красный
# обязательный контекст, засчитанный за «можно». Каждый исход — своей пробой:
# фильтр, ослабленный до «не FAILURE», ловится остальными, «не null» — красными.
#
# Перечень — ВСЕ исходы проверки, кроме SUCCESS, плюс «идёт», а не повтор
# перечня `red=` инструмента. Повтор держал бы лишь то, что инструмент и так
# называет красным: зелёный, заданный дополнением к перечню красных, проходил
# все пробы, а на STARTUP_FAILURE и STALE отвечал «можно» (возврат
# check-verifier @5f3080335). Красные исходы (RC_RED) инструмент называет
# красными; прочие незелёные (RC_OTHER) — своим исходом.
RC_RED="FAILURE CANCELLED TIMED_OUT ACTION_REQUIRED STARTUP_FAILURE"
RC_OTHER="STALE NEUTRAL SKIPPED"
RC_OUTCOMES="running $RC_RED $RC_OTHER"
for oc in $RC_OUTCOMES; do
    d="$(mkcase "RC-$oc")"
    mk_protection "$d/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
    c="$oc"; [ "$oc" = running ] && c=""
    mk_pr_mixed "$d/pr.json" CLEAN "$CTX_LAT=SUCCESS" "$CTX_DASH=SUCCESS" "$CTX_CYR=$c"
done

# A-<состояние> — все обязательные зелены, а сервер держит слияние. Против A один
# факт — состояние слияния, и каждое удерживающее — своей пробой: порча перечня
# «можно» на любом из них — ложное «можно».
# Z-<состояние> — законные «можно» при зелёных обязательных: снятие их из перечня
# дало бы ложное «нельзя», и близнец удерживающих проб обязан молчать на них.
MS_HELD="BLOCKED DIRTY BEHIND DRAFT UNKNOWN"
MS_LAWFUL="UNSTABLE HAS_HOOKS"
for ms in $MS_HELD; do
    d="$(mkcase "A-$ms")"
    mk_protection "$d/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
    mk_pr "$d/pr.json" OPEN "$ms" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
done
for ms in $MS_LAWFUL; do
    d="$(mkcase "Z-$ms")"
    mk_protection "$d/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
    mk_pr "$d/pr.json" OPEN "$ms" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
done

# WA — близнец A под именем воркспейса: база воркспейса требует контексты, все
# зелёные. Путь — контекстов (ws#886), а не ручного прогона: фикстуры прогонов нет,
# и уход в ручной путь дал бы отказ заглушки, а не «можно».
WA="$(mkcase WA)"
mk_protection "$WA/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
mk_pr "$WA/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"

# ── БАЗА — ВЕТКА ЛИНИИ: СУДИТ НАБОР СТВОЛА (решение диспетчера 2026-10-01) ────
# Ветка эпика или волны (`[0-9]+` либо `[0-9]+-*`, формы фильтра Д59) своей
# защиты не несёт (Д62), и инструмент судит её PR набором ствола `main`.
# Каждый случай меняет против EP-GREEN ровно один факт. Пробы этого блока идут
# именем продукта: ветка линии воркспейса судится ручным прогоном (проба U).
EPIC="2914-notify"; WAVE="2796"
ep_case() {  # <имя> <база> — каталог с незащищённой базой и защищённым стволом
    local d; d="$(mkcase "$1")"
    mk_refusal "$d" "$2" 1 "$BODY_UNPROTECTED"
    mk_protection "$d/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
    printf '%s' "$d"
}
# EP-GREEN — законный близнец: эпик не защищён, набор ствола зелен целиком.
d="$(ep_case EP-GREEN "$EPIC")"
MR_BASE="$EPIC" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
# EP-RED — один контекст из набора ствола красный.
d="$(ep_case EP-RED "$EPIC")"
MR_BASE="$EPIC" mk_pr_mixed "$d/pr.json" CLEAN "$CTX_LAT=SUCCESS" "$CTX_DASH=SUCCESS" "$CTX_CYR=FAILURE"
# EP-MISSING — один контекст из набора ствола на ревизии не появлялся.
d="$(ep_case EP-MISSING "$EPIC")"
MR_BASE="$EPIC" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH"
# EP-WAVE — вторая форма имени: волна голым номером.
d="$(ep_case EP-WAVE "$WAVE")"
MR_BASE="$WAVE" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
# EP-ZERO — эпик защищён, но обязательных контекстов у него ноль: собственного
# набора нет так же, как при 404.
d="$(mkcase EP-ZERO)"
printf '{"required_status_checks":{"contexts":[]}}\n' > "$d/protection@$EPIC.json"
mk_protection "$d/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
MR_BASE="$EPIC" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
# EP-OWN — у эпика СВОЙ непустой набор: судит он, ствол не читается. Фикстуры
# ствола нет нарочно — чтение её подставной gh отвергает кодом 98.
d="$(mkcase EP-OWN)"
mk_protection "$d/protection@$EPIC.json" "$CTX_LAT"
MR_BASE="$EPIC" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT"
# EP-BARE — не защищены ни эпик, ни ствол: судить нечем.
d="$(mkcase EP-BARE)"
mk_refusal "$d" "$EPIC" 1 "$BODY_UNPROTECTED"
mk_refusal "$d" main 1 "$BODY_UNPROTECTED"
MR_BASE="$EPIC" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
# EP-TRUNK-<отказ> — эпик не защищён, а защита СТВОЛА не прочитана (403 либо
# пустой ответ): это третий исход чтения, а не «ствол не защищён» — против
# EP-BARE меняется ровно ответ о стволе.
d="$(mkcase EP-TRUNK-403)"
mk_refusal "$d" "$EPIC" 1 "$BODY_UNPROTECTED"
mk_refusal "$d" main 1 '{"message":"Resource not accessible by integration","status":"403"}'
MR_BASE="$EPIC" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
d="$(mkcase EP-TRUNK-EMPTY)"
mk_refusal "$d" "$EPIC" 1 "$BODY_UNPROTECTED"
: > "$d/protection@main.unavailable"
MR_BASE="$EPIC" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
# NE-<имя> — база НЕ формы линии и не защищена. Ствол защищён и его набор на
# ревизии зелен: инструмент, ошибочно взявший набор ствола, ответил бы «можно».
NE_BASES="notify-2914 v2914-notify release"
for nb in $NE_BASES; do
    d="$(ep_case "NE-$nb" "$nb")"
    MR_BASE="$nb" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
done

# ── ГОЛОВА PR — УРОВЕНЬ КАСКАДА (ws#909) ─────────────────────────────────────────
# Каждый случай — ep_case: база-линия без защиты, набор ствола зелен целиком, то есть
# по проверкам PR сливаем, и код 1 приходит только от головы. Против CL-UP-WAVE
# (законный близнец: волна в своего родителя-эпика) меняется ровно один факт.
NO_PARENT='{"message":"No parent issue found","documentation_url":"https://docs.github.com/rest/issues/sub-issues#get-parent-issue","status":"404"}'
cl_case() {  # <имя> <голова> <база>
    local d; d="$(ep_case "$1" "$3")"
    MR_HEAD="$2" MR_BASE="$3" mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
    printf '%s' "$d"
}
# CL-DOWN — случай kaname#576: эпик (дочерние и метка) догоняет волну своей головой.
d="$(cl_case CL-DOWN 296 535)"; mk_issue "$d" 296 16 epic P1; mk_parent "$d" 296 PRO-Robotech/other 1266
# CL-WAVE-DOWN — волна (только дочерние) в ветку своей сборки.
d="$(cl_case CL-WAVE-DOWN 535-wave 7001-asm)"; mk_issue "$d" 535 23 P1; mk_parent "$d" 535 PRO-Robotech/kacho 296
# CL-EPIC-LABEL — только метка `epic`, дочерних ноль, родителя нет.
d="$(cl_case CL-EPIC-LABEL 296 535)"; mk_issue "$d" 296 0 epic
printf '%s\n' "$NO_PARENT" > "$d/parent@296.json"; printf '1\n' > "$d/parent@296.rc"
# CL-CROSS-PARENT — родитель с номером базы, но в ДРУГОМ репозитории.
d="$(cl_case CL-CROSS-PARENT 535 296)"; mk_issue "$d" 535 23; mk_parent "$d" 535 PRO-Robotech/kaname 296
# CL-UP-WAVE — законный близнец: волна в ветку своего эпика.
d="$(cl_case CL-UP-WAVE 535 296-own)"; mk_issue "$d" 535 23; mk_parent "$d" 535 PRO-Robotech/kacho 296
# CL-UP-TRUNK — эпик в ствол: вверх, родителя не спрашивают (фикстуры родителя нет).
d="$(mkcase CL-UP-TRUNK)"; mk_issue "$d" 296 16 epic
mk_protection "$d/protection@main.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
MR_HEAD=296 mk_pr "$d/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
# CL-DOWN-KANAME — тот же случай в kaname: подсказка обязана назвать форму, которую
# пропускает правило ветки kaname (`branch-rule.sh`: `^[0-9]+$`), а не `tmp/*`.
d="$(cl_case CL-DOWN-KANAME 296 535)"; mk_issue "$d" 296 16 epic P1; mk_parent "$d" 296 PRO-Robotech/other 1266
# CL-SYNC — голова не формы ветки задачи (`tmp/*`): уровнем не бывает, задачу не спрашивают.
d="$(cl_case CL-SYNC tmp/sync-296-into-535 535)"
# CL-SYNC-TASK — законная форма синхронизации вне kaname: ветка задачи-листа `<N>-sync-…`.
d="$(cl_case CL-SYNC-TASK 910-sync-296-into-535 535)"; mk_issue "$d" 910 0
# CL-SYNC-KANAME — законная форма в kaname: ветка — голый номер задачи-листа (kaname#584).
d="$(cl_case CL-SYNC-KANAME 584 536)"; mk_issue "$d" 584 0 P1
# CL-ISSUE-403 — задача ветки головы не прочитана.
d="$(cl_case CL-ISSUE-403 296 535)"
printf '%s\n' '{"message":"Resource not accessible by integration","status":"403"}' > "$d/issue@296.json"
printf '1\n' > "$d/issue@296.rc"
# CL-ISSUE-PR — номер ветки головы — запрос, а не задача.
d="$(cl_case CL-ISSUE-PR 296 535)"
jq -n '{number: 296, labels: [], pull_request: {url: "x"}}' > "$d/issue@296.json"
# CL-PARENT-403 — уровень, база-линия, родитель не прочитан.
d="$(cl_case CL-PARENT-403 535 296)"; mk_issue "$d" 535 23
printf '%s\n' '{"message":"Resource not accessible by integration","status":"403"}' > "$d/parent@535.json"
printf '1\n' > "$d/parent@535.rc"

# ── ИСТОЧНИК ВОРКСПЕЙСА: РУЧНОЙ ПРОГОН НА ГОЛОВЕ ────────────────────────────────
T0="2026-09-26T10:00:00Z"; T1="2026-09-26T11:00:00Z"

# J — зелёный ручной прогон на голове при пустом rollup (три check-runs).
J="$(mkcase J)"
mk_pr "$J/pr.json" OPEN CLEAN
mk_ws_protection "$J/protection@main.json"
mk_runs "$J/runs.json" "501,$HEAD_SHA,completed,success,$T1,9001"
mk_checkruns "$J/checkruns.json" "9001|$CTX_LAT|completed|success" \
    "9001|$CTX_DASH|completed|success" "9001|$CTX_CYR|completed|success"

# K — ручного прогона на голове нет.
K="$(mkcase K)"
mk_pr "$K/pr.json" OPEN CLEAN
mk_ws_protection "$K/protection@main.json"
printf '{"total_count":0,"workflow_runs":[]}\n' > "$K/runs.json"

# L — на голове красный ручной прогон (один check-run упал).
L="$(mkcase L)"
mk_pr "$L/pr.json" OPEN CLEAN
mk_ws_protection "$L/protection@main.json"
mk_runs "$L/runs.json" "502,$HEAD_SHA,completed,failure,$T1,9002"
mk_checkruns "$L/checkruns.json" "9002|$CTX_LAT|completed|success" \
    "9002|$CTX_CYR|completed|failure"

# M — ручной прогон на голове идёт.
M="$(mkcase M)"
mk_pr "$M/pr.json" OPEN CLEAN
mk_ws_protection "$M/protection@main.json"
mk_runs "$M/runs.json" "503,$HEAD_SHA,in_progress,,$T1,9003"
mk_checkruns "$M/checkruns.json" "9003|$CTX_LAT|completed|success" \
    "9003|$CTX_CYR|in_progress|"

# N — зелёный прогон есть, но на ПРЕЖНЕЙ голове; сосед вернул его на вопрос о новой.
N="$(mkcase N)"
mk_pr "$N/pr.json" OPEN CLEAN
mk_ws_protection "$N/protection@main.json"
mk_runs "$N/runs.json" "504,$OLD_SHA,completed,success,$T1,9004"
mk_checkruns "$N/checkruns.json" "9004|$CTX_LAT|completed|success"

# O — на голове два прогона: прежний зелёный, последний красный.
O="$(mkcase O)"
mk_pr "$O/pr.json" OPEN CLEAN
mk_ws_protection "$O/protection@main.json"
mk_runs "$O/runs.json" "505,$HEAD_SHA,completed,success,$T0,9005" \
    "506,$HEAD_SHA,completed,failure,$T1,9006"
mk_checkruns "$O/checkruns.json" "9005|$CTX_LAT|completed|success" \
    "9006|$CTX_LAT|completed|failure"

# S — близнец O: прежний красный, последний зелёный; красное прежнего не в счёт.
S="$(mkcase S)"
mk_pr "$S/pr.json" OPEN CLEAN
mk_ws_protection "$S/protection@main.json"
mk_runs "$S/runs.json" "507,$HEAD_SHA,completed,failure,$T0,9007" \
    "508,$HEAD_SHA,completed,success,$T1,9008"
mk_checkruns "$S/checkruns.json" "9007|$CTX_LAT|completed|failure" \
    "9008|$CTX_LAT|completed|success"

# Y — то же, что O, но в ПОРЯДКЕ СОСЕДА: API прогонов отдаёт новый прогон первым.
# O и S кладут прежний прогон первым, то есть их порядок уже хронологический, и
# снятие сортировки перед `last` ни одну из них не меняло (ws#862, находка M4
# check-verifier: 23 пробы из 23 зелёные при снятой сортировке). На этом порядке
# `last` без сортировки берёт прежний зелёный прогон, и инструмент отвечает
# «можно сливать» при красном последнем. Отличие от O — только порядок записей.
Y="$(mkcase Y)"
mk_pr "$Y/pr.json" OPEN CLEAN
mk_ws_protection "$Y/protection@main.json"
mk_runs "$Y/runs.json" "517,$HEAD_SHA,completed,failure,$T1,9017" \
    "516,$HEAD_SHA,completed,success,$T0,9016"
mk_checkruns "$Y/checkruns.json" "9016|$CTX_LAT|completed|success" \
    "9017|$CTX_LAT|completed|failure"

# P — защита базы воркспейса требует контекст, на ревизии его нет, а ручной
# прогон на голове зелёный: судят контексты (ws#886), прогон их не заменяет.
P="$(mkcase P)"
mk_pr "$P/pr.json" OPEN CLEAN
mk_protection "$P/protection@main.json" "$CTX_LAT"
mk_runs "$P/runs.json" "509,$HEAD_SHA,completed,success,$T1,9009"
mk_checkruns "$P/checkruns.json" "9009|$CTX_LAT|completed|success"

# Q — ответ о прогонах не разбирается.
Q="$(mkcase Q)"
mk_pr "$Q/pr.json" OPEN CLEAN
mk_ws_protection "$Q/protection@main.json"
printf '<html><head><title>502</title></head></html>\n' > "$Q/runs.json"

# R — прогон зелёный, а его check-runs нет: на sha лежат только чужие.
R="$(mkcase R)"
mk_pr "$R/pr.json" OPEN CLEAN
mk_ws_protection "$R/protection@main.json"
mk_runs "$R/runs.json" "510,$HEAD_SHA,completed,success,$T1,9010"
mk_checkruns "$R/checkruns.json" "7777|$CTX_LAT|completed|success"

# U — база воркспейса не защищена (ветка эпика `771`, форма ветки линии), ручной
# прогон зелёный. Ответ о защите — настоящей формы (404 «Branch not protected»,
# код 1). Фикстуры защиты ствола нет нарочно: инструмент, взявший для ветки линии
# воркспейса набор ствола, получил бы отказ заглушки 98 — и код 2, а не 0.
WS_LINE="771"
U="$(mkcase U)"
MR_BASE="$WS_LINE" mk_pr "$U/pr.json" OPEN CLEAN
mk_refusal "$U" "$WS_LINE" 1 "$BODY_UNPROTECTED"
mk_runs "$U/runs.json" "511,$HEAD_SHA,completed,success,$T1,9011"
mk_checkruns "$U/checkruns.json" "9011|$CTX_LAT|completed|success"

# U-<отказ> — близнецы U, у которых защита базы воркспейса НЕ ПРОЧИТАНА: пустой
# отказ и 403. Против U меняется ровно ответ о защите; зелёный ручной прогон на
# голове остаётся, и уход в ручной путь ответил бы «можно» там, где вердикта нет.
for rf in EMPTY 403; do
    d="$(mkcase "U-$rf")"
    MR_BASE="$WS_LINE" mk_pr "$d/pr.json" OPEN CLEAN
    if [ "$rf" = EMPTY ]; then
        : > "$d/protection@$WS_LINE.unavailable"
    else
        mk_refusal "$d" "$WS_LINE" 1 '{"message":"Resource not accessible by integration","status":"403"}'
    fi
    mk_runs "$d/runs.json" "512,$HEAD_SHA,completed,success,$T1,9012"
    mk_checkruns "$d/checkruns.json" "9012|$CTX_LAT|completed|success"
done

# Три пробы ниже держат по одной охране, которую до них не держало ничего: снятие
# каждой оставляло набор зелёным (опыты check-verifier M1–M3 по ws#788). У каждой
# фикстуры ровно одно отличие от J — зелёного ручного прогона на голове.

# V — прогон на голове идёт, а все поднятые им check-runs уже зелёные: заданий,
# которых ещё нет, в перечне не видно. Отличие от J — только состояние прогона.
V="$(mkcase V)"
mk_pr "$V/pr.json" OPEN CLEAN
mk_ws_protection "$V/protection@main.json"
mk_runs "$V/runs.json" "513,$HEAD_SHA,in_progress,,$T1,9013"
mk_checkruns "$V/checkruns.json" "9013|$CTX_LAT|completed|success" \
    "9013|$CTX_DASH|completed|success" "9013|$CTX_CYR|completed|success"

# W — ответ о check-runs усечён: прочитано три из ста пятидесяти, все три
# зелёные. Непрочитанная страница могла нести красное. Отличие от J — только
# total_count ответа.
W="$(mkcase W)"
mk_pr "$W/pr.json" OPEN CLEAN
mk_ws_protection "$W/protection@main.json"
mk_runs "$W/runs.json" "514,$HEAD_SHA,completed,success,$T1,9014"
mk_checkruns "$W/checkruns.json" "9014|$CTX_LAT|completed|success" \
    "9014|$CTX_DASH|completed|success" "9014|$CTX_CYR|completed|success"
jq '.total_count = 150' "$W/checkruns.json" > "$W/checkruns.tmp" && mv "$W/checkruns.tmp" "$W/checkruns.json"

# X — прогон на голове не поднял ни одного задания (`startup_failure`): check-runs
# у него нет, и красен он исходом целиком, а не перечнем. Пустой перечень
# записан явно — `mk_checkruns` без строк породил бы одну пустую запись.
X="$(mkcase X)"
mk_pr "$X/pr.json" OPEN CLEAN
mk_ws_protection "$X/protection@main.json"
mk_runs "$X/runs.json" "515,$HEAD_SHA,completed,startup_failure,$T1,9015"
printf '{"total_count":0,"check_runs":[]}\n' > "$X/checkruns.json"

# ── ПРЕДПОСЫЛКА: ЗАГЛУШКА ДОКАЗАНА В ОБЕ СТОРОНЫ ─────────────────────────────
# Положительная сторона: знакомый вызов отдаёт именно фикстуру. Отрицательная:
# незнакомый отвергается кодом 99, а не тишиной. Проверяется БЕЗ участия
# испытуемого — иначе его дефект прятался бы в предпосылке.
stub_state="$(PATH="$STUB:$PATH" MR_FIXTURE="$A" gh pr view 1 -R x --json state 2>/dev/null | jq -r '.state' 2>/dev/null || true)"
if [ "$stub_state" != "OPEN" ]; then
    tooling_gate_void "$NAME" "подставной gh не отдал фикстуру (получено '$stub_state') — пробы на нём недоказательны"
    exit 2
fi
PATH="$STUB:$PATH" MR_FIXTURE="$A" gh 'незнакомый-глагол' >/dev/null 2>&1 && stub_rc=0 || stub_rc=$?
if [ "$stub_rc" -ne 99 ]; then
    tooling_gate_void "$NAME" "подставной gh на незнакомом вызове вернул $stub_rc вместо 99 — он способен молча подыграть"
    exit 2
fi
PATH="$STUB:$PATH" MR_FIXTURE="$A" gh api 'repos/x/незнакомый-путь' >/dev/null 2>&1 && stub_rc=0 || stub_rc=$?
if [ "$stub_rc" -ne 99 ]; then
    tooling_gate_void "$NAME" "подставной gh на незнакомом пути api вернул $stub_rc вместо 99 — он способен молча подыграть"
    exit 2
fi
stub_runs="$(PATH="$STUB:$PATH" MR_FIXTURE="$J" gh api "repos/x/actions/workflows/ci.yaml/runs?head_sha=$HEAD_SHA" 2>/dev/null | jq -r '.workflow_runs[0].id' 2>/dev/null || true)"
if [ "$stub_runs" != "501" ]; then
    tooling_gate_void "$NAME" "подставной gh не отдал фикстуру прогонов (получено '$stub_runs') — пробы воркспейса недоказательны"
    exit 2
fi

stub_issue="$(PATH="$STUB:$PATH" MR_FIXTURE="$A" gh api "repos/x/issues/788" 2>/dev/null | jq -r '.sub_issues_summary.total' 2>/dev/null || true)"
if [ "$stub_issue" != "0" ]; then
    tooling_gate_void "$NAME" "подставной gh не отдал фикстуру задачи головы (получено '$stub_issue') — пробы уровня каскада недоказательны"
    exit 2
fi

# ── ЛОКАЛЬ ПРОБ: ТА, ГДЕ ПОРЯДОК РАСХОДИТСЯ С БАЙТОВЫМ ─────────────────────────
# Инструмент сверяет множества под `LC_ALL=C` (ws#530). Снятие этого пина —
# дефект лишь там, где локаль среды упорядочивает или схлопывает иначе, чем
# байты: под C.UTF-8 проба его не видит (возврат check-verifier @5f3080335).
# Поэтому пробы не наследуют локаль вызова, а исполняют инструмент под
# локалью, ЗАМЕРЕННОЙ здесь как расходящаяся с байтовым порядком на входе
# фикстур: ru_RU первой (кириллица перед латиницей и схлопывание тире), затем
# любая иная из `locale -a`. Нет такой — снятие пина в этой среде
# непредставимо, и перепись говорит это вслух; держат тогда инъекции inject.sh,
# не зависящие от среды (обратный порядок, дедупликация по полю).
mr_locale_sample() { printf '%s\n' "$CTX_LAT" "$CTX_CYR" "$CTX_DASH" "проба — раз" "проба - раз"; }
byte_order="$(mr_locale_sample | LC_ALL=C sort -u)"
PROBE_LOCALE=""
for cand in $(locale -a 2>/dev/null | grep -i '^ru_RU.*utf' ; locale -a 2>/dev/null | grep -iv '^ru_RU' | grep -iv '^\(c\|posix\)\(\..*\)\?$'); do
    if [ "$(mr_locale_sample | LC_ALL="$cand" sort -u 2>/dev/null)" != "$byte_order" ]; then
        PROBE_LOCALE="$cand"; break
    fi
done
if [ -n "$PROBE_LOCALE" ]; then
    locale_note="пробы исполняют инструмент под LC_ALL=$PROBE_LOCALE — порядок расходится с байтовым, снятие LC_ALL=C представимо"
else
    locale_note="локали, чей порядок расходится с байтовым, в системе нет — снятие LC_ALL=C здесь непредставимо; держат инъекции inject.sh, от среды не зависящие"
fi

# ── ПРОБЫ ────────────────────────────────────────────────────────────────────
probes=0
findings=0
declare -A by_code=() by_repo=()

# Репозиторий выбирает источник вердикта, поэтому он — часть пробы: продукт
# судится обязательными контекстами, воркспейс — ручным прогоном.
PRODUCT_REPO="PRO-Robotech/kacho"
WS_REPO="PRO-Robotech/kacho-workspace"

# probe <репозиторий> <каталог> <ожидаемый-код> <имя-пробы> <обязательная-подстрока>...
#
# Имя пробы начинается МЕТКОЙ случая — `[<буква>]` из имени каталога фикстуры.
# По метке inject.sh сверяет, что порча решения покраснила ИМЕННО держащую его
# пробу, а не соседнюю: код 1 набора сам по себе этого не говорит.
probe() {
    local repo="$1" dir="$2" want="$3" title="$4"; shift 4
    local out rc needle
    title="[${dir##*/case-}] $title"
    probes=$((probes + 1))
    by_code[$want]=$(( ${by_code[$want]:-0} + 1 ))
    by_repo[$repo]=$(( ${by_repo[$repo]:-0} + 1 ))
    out="$(PATH="$STUB:$PATH" MR_FIXTURE="$dir" LC_ALL="${PROBE_LOCALE:-${LC_ALL:-}}" \
        bash "$WS/$TOOL_REL" "$repo" 1 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -ne "$want" ]; then
        tooling_gate_fail "$NAME" "$title — ждали код $want, получили $rc"
        printf '%s\n' "${out//$'\n'/$'\n'      }" | sed 's/^/      /' >&2
        findings=$((findings + 1))
        return
    fi
    # Вывод подаётся строкой, а не трубой. `printf` пишет в трубу построчно, `grep -q`
    # выходит на первом совпадении, следующая запись получает SIGPIPE, и под
    # `pipefail` труба возвращает 141 — «подстроки нет» при подстроке в выводе.
    # Наблюдалось 2026-09-27 под нагрузкой (load 29): проба S покраснела на
    # «прогон: 508», стоявшем в её же напечатанном выводе; повтор — зелёный.
    for needle in "$@"; do
        if ! grep -qF -- "$needle" <<<"$out"; then
            tooling_gate_fail "$NAME" "$title — код $rc верен, но в выводе нет «$needle»"
            printf '%s\n' "${out//$'\n'/$'\n'      }" | sed 's/^/      /' >&2
            findings=$((findings + 1))
            return
        fi
    done
    tooling_gate_pass "$NAME" "$title (код $rc)"
}

probe "$PRODUCT_REPO" "$A" 0 "все обязательные зелены — «сливать можно»" \
    "можно сливать" "обязательных контекстов: 3"

probe "$PRODUCT_REPO" "$B" 1 "обязательный контекст не появлялся — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "НЕ ПОЯВЛЯЛСЯ" "$CTX_CYR"

probe "$PRODUCT_REPO" "$C" 2 "защита ветки не настроена (404 «Branch not protected») — «НЕ ЗАЩИЩЕНА», а не «защита есть»" \
    "НЕ ЗАЩИЩЕНА" "Branch not protected"

for rf in EMPTY 403 404NF; do
    probe "$PRODUCT_REPO" "$TMP/case-C-$rf" 2 "ответ о защите — отказ ($rf), а не состояние — «НЕ ПРОЧИТАНА»" \
        "защита ветки 'main' НЕ ПРОЧИТАНА" "отказ чтения, а не состояние защиты"
done

probe "$PRODUCT_REPO" "$D" 2 "PR недоступен — беспредметно, а не «нельзя»" \
    "недоступен"

probe "$PRODUCT_REPO" "$E" 2 "ответ о защите не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$PRODUCT_REPO" "$F" 2 "ответ о PR не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$PRODUCT_REPO" "$G" 2 "обязательных контекстов ноль — беспредметно, а не «нельзя» и не «можно»" \
    "обязательных контекстов ноль" "ничем не гейтится"

probe "$PRODUCT_REPO" "$H" 1 "имена, различные только длинным тире, не схлопнуты — учтены оба" \
    "обязательных контекстов: 2" "проба - раз"

probe "$PRODUCT_REPO" "$I" 2 "PR уже не открыт — беспредметно, а не «нельзя»" \
    "сливать нечего"

probe "$PRODUCT_REPO" "$TMP/case-EP-GREEN" 0 "база-эпик без защиты, набор ствола зелен — «сливать можно» по набору ствола" \
    "можно сливать" "набор обязательных: ствола 'main'" "(ветка не защищена)" "обязательных контекстов: 3"
probe "$PRODUCT_REPO" "$TMP/case-EP-RED" 1 "база-эпик, контекст из набора ствола красный — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR — красный" "набор обязательных: ствола 'main'"
probe "$PRODUCT_REPO" "$TMP/case-EP-MISSING" 1 "база-эпик, контекст из набора ствола не появлялся — «нельзя», без слов о защите базы" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR — НЕ ПОЯВЛЯЛСЯ" "у базы защиты нет"
probe "$PRODUCT_REPO" "$TMP/case-EP-WAVE" 0 "база-волна голым номером — та же ветка линии, набор ствола" \
    "можно сливать" "у ветки линии '$WAVE'" "обязательных контекстов: 3"
probe "$PRODUCT_REPO" "$TMP/case-EP-ZERO" 0 "база-эпик с защитой без контекстов — набор ствола, а не «ничем не гейтится»" \
    "можно сливать" "у ветки линии '$EPIC' собственного нет (защита есть" "обязательных контекстов: 3"
probe "$PRODUCT_REPO" "$TMP/case-EP-OWN" 0 "база-эпик со своим набором — судит он, ствол не читается" \
    "можно сливать" "набор обязательных: собственный ветки '$EPIC'" "обязательных контекстов: 1"
probe "$PRODUCT_REPO" "$TMP/case-EP-BARE" 2 "не защищены ни эпик, ни ствол — беспредметно" \
    "ствол 'main' НЕ ЗАЩИЩЕН"
for rf in 403 EMPTY; do
    probe "$PRODUCT_REPO" "$TMP/case-EP-TRUNK-$rf" 2 "база-эпик, защита ствола не прочитана ($rf) — «НЕ ПРОЧИТАНА», а не «ствол НЕ ЗАЩИЩЕН»" \
        "защита ветки 'main' НЕ ПРОЧИТАНА" "отказ чтения, а не состояние защиты"
done
for nb in $NE_BASES; do
    probe "$PRODUCT_REPO" "$TMP/case-NE-$nb" 2 "база '$nb' не формы линии, без защиты — «НЕ ЗАЩИЩЕНА», набор ствола не берётся" \
        "ветка '$nb' НЕ ЗАЩИЩЕНА"
done

probe "$PRODUCT_REPO" "$TMP/case-CL-DOWN" 1 "голова — эпик (дочерние и метка), база — его волна — «нельзя»: вливание снимет эпик" \
    "СЛИВАТЬ НЕЛЬЗЯ" "голова PR '296' — уровень каскада" "ветка задачи синхронизации N" \
    "refs/heads/<N>-sync-296-into-535" "#<N> merge #296: "
probe "PRO-Robotech/kaname" "$TMP/case-CL-DOWN-KANAME" 1 "kaname: подсказка называет форму правила ветки kaname — голый номер задачи" \
    "СЛИВАТЬ НЕЛЬЗЯ" "refs/heads/<N> " "^[0-9]+\$" "#<N> merge #296: "
probe "$PRODUCT_REPO" "$TMP/case-CL-WAVE-DOWN" 1 "голова — волна (только дочерние), база — сборка — «нельзя»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "голова PR '535-wave' — уровень каскада" "дочерних 23"
probe "$PRODUCT_REPO" "$TMP/case-CL-EPIC-LABEL" 1 "голова — задача с меткой epic без дочерних и без родителя — «нельзя»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "метка epic" "родителя нет"
probe "$PRODUCT_REPO" "$TMP/case-CL-CROSS-PARENT" 1 "родитель с номером базы из другого репозитория — не вверх, «нельзя»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "PRO-Robotech/kaname/issues/296"
probe "$PRODUCT_REPO" "$TMP/case-CL-UP-WAVE" 0 "голова — волна, база — ветка её родителя — вверх, «сливать можно»" \
    "можно сливать" "вверх — в родителя"
probe "$PRODUCT_REPO" "$TMP/case-CL-UP-TRUNK" 0 "голова — эпик, база — ствол — вверх, «сливать можно»" \
    "можно сливать" "вверх — в ствол"
probe "$PRODUCT_REPO" "$TMP/case-CL-SYNC" 0 "голова не формы ветки задачи (tmp/*) — уровнем не бывает, «сливать можно»" \
    "можно сливать" "не формы ветки задачи"
probe "$PRODUCT_REPO" "$TMP/case-CL-SYNC-TASK" 0 "голова — ветка задачи синхронизации <N>-sync-… — не уровень, «сливать можно»" \
    "можно сливать" "задача PRO-Robotech/kacho#910 без дочерних"
probe "PRO-Robotech/kaname" "$TMP/case-CL-SYNC-KANAME" 0 "kaname: голова — голый номер задачи синхронизации — не уровень, «сливать можно»" \
    "можно сливать" "задача PRO-Robotech/kaname#584 без дочерних"
probe "$PRODUCT_REPO" "$TMP/case-CL-ISSUE-403" 2 "задача ветки головы не прочитана — уровень НЕ УСТАНОВЛЕН, а не «можно»" \
    "уровень каскада головы '296' НЕ УСТАНОВЛЕН"
probe "$PRODUCT_REPO" "$TMP/case-CL-ISSUE-PR" 2 "номер ветки головы — запрос — уровень НЕ УСТАНОВЛЕН" \
    "уровень каскада головы '296' НЕ УСТАНОВЛЕН" "запрос, а не задача"
probe "$PRODUCT_REPO" "$TMP/case-CL-PARENT-403" 2 "родитель задачи-уровня не прочитан — НЕ УСТАНОВЛЕН, а не «нельзя»" \
    "родитель задачи PRO-Robotech/kacho#535 НЕ ПРОЧИТАН"

probe "$WS_REPO" "$WA" 0 "воркспейс: база требует контексты, все зелёны — путь контекстов, «сливать можно»" \
    "можно сливать" "обязательных контекстов: 3" "ручной прогон их не заменяет"

for ms in $MS_HELD; do
    probe "$WS_REPO" "$TMP/case-A-$ms" 1 "с контекстами: все обязательные зелены, состояние слияния $ms — задержано, а не «можно»" \
        "СЛИЯНИЕ ЗАДЕРЖАНО" "состояние слияния: $ms" "обязательных контекстов: 3"
done

for ms in $MS_LAWFUL; do
    probe "$WS_REPO" "$TMP/case-Z-$ms" 0 "с контекстами: все обязательные зелены, состояние слияния $ms — «сливать можно»" \
        "можно сливать" "состояние слияния: $ms"
done

for oc in $RC_OUTCOMES; do
    d="$TMP/case-RC-$oc"
    case " $RC_OTHER " in *" $oc "*) other=1 ;; *) other=0 ;; esac
    if [ "$oc" = running ]; then
        probe "$WS_REPO" "$d" 1 "с контекстами: обязательный контекст идёт — «сливать нельзя», а не «можно»" \
            "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR — идёт" "без него: 1"
    elif [ "$other" -eq 1 ]; then
        probe "$WS_REPO" "$d" 1 "с контекстами: обязательный контекст $oc — не зелёный, «сливать нельзя»" \
            "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR [$oc] — не зелёный" "без него: 1"
    else
        probe "$WS_REPO" "$d" 1 "с контекстами: обязательный контекст $oc — «сливать нельзя», а не «можно»" \
            "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR [$oc]" "$CTX_CYR — красный"
    fi
done

probe "$WS_REPO" "$J" 0 "воркспейс: ручной прогон на голове зелёный при пустом rollup — «сливать можно»" \
    "можно сливать" "check-runs: 3" "проверок 0"

probe "$WS_REPO" "$K" 2 "воркспейс: ручного прогона на голове нет — «не выполнилось», а не «нельзя»" \
    "НЕ ВЫПОЛНИЛОСЬ" "gh workflow run ci.yaml"

probe "$WS_REPO" "$L" 1 "воркспейс: ручной прогон на голове красный — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR [FAILURE]"

probe "$WS_REPO" "$M" 1 "воркспейс: ручной прогон на голове идёт — «нельзя сейчас»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "идёт"

probe "$WS_REPO" "$N" 2 "воркспейс: зелёный прогон прежней головы не засчитан — «не выполнилось»" \
    "НЕ ВЫПОЛНИЛОСЬ" "ручных прогонов на голове: 0"

probe "$WS_REPO" "$O" 1 "воркспейс: судит последний прогон головы — прежний зелёный не спасает" \
    "СЛИВАТЬ НЕЛЬЗЯ" "прогон: 506"

probe "$WS_REPO" "$S" 0 "воркспейс: красное прежнего прогона той же sha не в счёт — «сливать можно»" \
    "можно сливать" "прогон: 508"

probe "$WS_REPO" "$Y" 1 "воркспейс: сосед отдал новый прогон первым — судит последний, а не прежний зелёный" \
    "СЛИВАТЬ НЕЛЬЗЯ" "прогон: 517"

probe "$WS_REPO" "$P" 1 "воркспейс: база требует контекст, его нет — судят контексты, зелёный ручной прогон их не заменяет" \
    "СЛИВАТЬ НЕЛЬЗЯ" "НЕ ПОЯВЛЯЛСЯ" "ручной прогон их не заменяет"

probe "$WS_REPO" "$Q" 2 "воркспейс: ответ о прогонах не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$WS_REPO" "$R" 2 "воркспейс: у прогона нет своих check-runs — «не выполнилось», чужие не в счёт" \
    "НЕ ВЫПОЛНИЛОСЬ" "зелёных 0 из 0"

probe "$WS_REPO" "$U" 0 "воркспейс: ветка линии без защиты (404) судится ручным прогоном, а не набором ствола — «сливать можно»" \
    "можно сливать" "источник вердикта: ручной прогон ci.yaml"

for rf in EMPTY 403; do
    probe "$WS_REPO" "$TMP/case-U-$rf" 2 "воркспейс: защита базы не прочитана ($rf) — «НЕ ПРОЧИТАНА», а не уход в ручной прогон" \
        "защита ветки '$WS_LINE' НЕ ПРОЧИТАНА" "отказ чтения, а не состояние защиты"
done

probe "$WS_REPO" "$V" 1 "воркспейс: прогон идёт при всех зелёных check-runs — «нельзя сейчас», а не «можно»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "идёт" "прогон 513 целиком [IN_PROGRESS]"

probe "$WS_REPO" "$W" 2 "воркспейс: ответ о check-runs усечён — вердикта нет, а не «можно»" \
    "РАЗБОР СЛОМАН" "получено 3 из 150"

probe "$WS_REPO" "$X" 1 "воркспейс: прогон без заданий (startup_failure) — «сливать нельзя», а не «не выполнилось»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "прогон 515 целиком [STARTUP_FAILURE]"

tooling_gate_census "$NAME: проб исполнено $probes над $TOOL_REL; источников вердикта два — контексты (продукт, проб ${by_repo[$PRODUCT_REPO]:-0}) и ручной прогон либо контексты воркспейса по защите базы (проб ${by_repo[$WS_REPO]:-0}); по исходам: 0 — ${by_code[0]:-0}, 1 — ${by_code[1]:-0}, 2 — ${by_code[2]:-0}"
tooling_gate_census "$NAME: $locale_note"
for n in "${by_code[0]:-0}" "${by_code[1]:-0}" "${by_code[2]:-0}"; do
    if [ "$n" -eq 0 ]; then
        tooling_gate_void "$NAME" "один из трёх исходов не представлен ни одной пробой — различение не доказано"
        exit 2
    fi
done

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings из $probes"
    exit 1
fi

tooling_gate_pass "$NAME" "инструмент различает все три исхода у обоих источников: вердикт печатается, отказ разбора и «не выполнилось» приходят кодом 2, имена контекстов не схлопываются, зелёный — только SUCCESS, код gh api судится — не защищена и не прочитана различены, ветка линии продукта судится набором ствола, источник выбирает защита базы тем же чтением, ручной прогон судится на голове, голова-уровень каскада сливается только вверх"
