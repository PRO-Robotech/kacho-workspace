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
# прогон на ПРЕЖНЕЙ голове не засчитан; из двух прогонов на голове судит последний, и
# check-runs чужого прогона той же sha в счёт не идут; защита, снова требующая
# контекстов, — код 2, а не молчаливый выбор источника. Три охраны инструмента
# держатся каждая своей пробой, потому что их снятие прежние пробы не замечали:
# прогон идёт при всех зелёных check-runs — код 1, а не 0; ответ о check-runs
# усечён — код 2, а не 0; прогон без заданий (`startup_failure`) — код 1, а не 2.
#
# Предпосылка проверки (исход VOID): в дереве есть сам инструмент, есть `jq`, и
# подставной `gh` доказал обе свои стороны. Отсутствие любого из трёх — «не
# выполнилось», а не «находок нет».
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
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
case "${1:-}" in
    pr)  target="${MR_FIXTURE:?}/pr" ;;
    api)
        case "${2:-}" in
            repos/*/branches/*/protection)      target="${MR_FIXTURE:?}/protection" ;;
            repos/*/actions/workflows/*/runs\?*) target="${MR_FIXTURE:?}/runs" ;;
            repos/*/commits/*/check-runs\?*)     target="${MR_FIXTURE:?}/checkruns" ;;
            *) echo "gh-stub: незнакомый путь api: $*" >&2; exit 99 ;;
        esac ;;
    *)   echo "gh-stub: незнакомый вызов: $*" >&2; exit 99 ;;
esac
if [ -e "$target.unavailable" ]; then exit 1; fi
# Вопрос, на который фикстура не заготовлена, — отказ 98, а не пустой ответ.
[ -e "$target.json" ] || { echo "gh-stub: нет фикстуры $target.json на: $*" >&2; exit 98; }
cat "$target.json"
STUBEOF
chmod +x "$STUB/gh"

# ── ФИКСТУРЫ ─────────────────────────────────────────────────────────────────
# Имена контекстов намеренно смешанные: латиница, латиница с длинным тире и
# кириллица. Это НЕ украшение — именно на таком наборе байтовый и локальный
# порядок расходятся, и именно он ронял инструмент.
CTX_LAT="bats-and-shellcheck"
CTX_DASH="authz-fixtures bootstrap — lint (KAC-122)"
CTX_CYR="доказательства хуков инъекцией исполняются, а не лежат"

mkcase() { local d="$TMP/case-$1"; mkdir -p "$d"; printf '%s' "$d"; }

mk_protection() {  # <файл> <контекст>...
    local f="$1"; shift
    printf '%s\n' "$@" | jq -R . | jq -s '{required_status_checks:{contexts:.}}' > "$f"
}

HEAD_SHA="1111111111111111111111111111111111111111"
OLD_SHA="2222222222222222222222222222222222222222"

mk_pr() {  # <файл> <состояние> <состояние-слияния> <зелёный-контекст>...
    local f="$1" st="$2" ms="$3"; shift 3
    local rollup='[]'
    if [ "$#" -gt 0 ]; then
        rollup="$(printf '%s\n' "$@" | jq -R '{name: ., conclusion: "SUCCESS"}' | jq -s .)"
    fi
    jq -n --arg st "$st" --arg ms "$ms" --arg h "$HEAD_SHA" --argjson r "$rollup" \
        '{state:$st, baseRefName:"main", headRefName:"788", headRefOid:$h,
          mergeStateStatus:$ms, statusCheckRollup:$r}' > "$f"
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

# Защита `main` воркспейса, как она есть: `enforce_admins` включён, контекстов нет.
mk_ws_protection() { printf '{"enforce_admins":{"enabled":true}}\n' > "$1"; }

# A — все обязательные зелены.
A="$(mkcase A)"
mk_protection "$A/protection.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
mk_pr "$A/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"

# B — обязательный контекст не появлялся на ревизии (случай kacho#614).
B="$(mkcase B)"
mk_protection "$B/protection.json" "$CTX_LAT" "$CTX_DASH" "$CTX_CYR"
mk_pr "$B/pr.json" OPEN CLEAN "$CTX_LAT" "$CTX_DASH"

# C — защита ветки не настроена.
C="$(mkcase C)"
mk_pr "$C/pr.json" OPEN CLEAN "$CTX_LAT"
: > "$C/protection.unavailable"
: > "$C/protection.json"

# D — PR недоступен.
D="$(mkcase D)"
: > "$D/pr.unavailable"
: > "$D/pr.json"
mk_protection "$D/protection.json" "$CTX_LAT"

# E — ответ о защите не разбирается.
E="$(mkcase E)"
mk_pr "$E/pr.json" OPEN CLEAN "$CTX_LAT"
printf '<html><head><title>503</title></head></html>\n' > "$E/protection.json"

# F — ответ о PR не разбирается.
F="$(mkcase F)"
printf '<html><head><title>502</title></head></html>\n' > "$F/pr.json"
mk_protection "$F/protection.json" "$CTX_LAT"

# G — защита есть, обязательных контекстов ноль.
G="$(mkcase G)"
mk_pr "$G/pr.json" OPEN CLEAN
printf '{"required_status_checks":{"contexts":[]}}\n' > "$G/protection.json"

# H — два обязательных имени, различающихся ТОЛЬКО длинным тире.
#
# Это не экзотика, а второй дефект той же строки. Локальный `sort -u` считает
# такие имена ОДНИМ и выбрасывает одно из них: недостающий обязательный контекст
# молча исчезает из перечня, и инструмент отвечает «можно сливать» ровно там,
# где обязан сказать «нельзя». Ложное зелёное здесь дороже ложного красного:
# именно его этот инструмент и заведён предотвращать.
H="$(mkcase H)"
mk_protection "$H/protection.json" "проба — раз" "проба - раз"
mk_pr "$H/pr.json" OPEN CLEAN "проба — раз"

# I — PR уже не открыт.
I="$(mkcase I)"
mk_pr "$I/pr.json" MERGED CLEAN "$CTX_LAT"
mk_protection "$I/protection.json" "$CTX_LAT"

# ── ИСТОЧНИК ВОРКСПЕЙСА: РУЧНОЙ ПРОГОН НА ГОЛОВЕ ────────────────────────────────
T0="2026-09-26T10:00:00Z"; T1="2026-09-26T11:00:00Z"

# J — зелёный ручной прогон на голове при пустом rollup (три check-runs).
J="$(mkcase J)"
mk_pr "$J/pr.json" OPEN CLEAN
mk_ws_protection "$J/protection.json"
mk_runs "$J/runs.json" "501,$HEAD_SHA,completed,success,$T1,9001"
mk_checkruns "$J/checkruns.json" "9001|$CTX_LAT|completed|success" \
    "9001|$CTX_DASH|completed|success" "9001|$CTX_CYR|completed|success"

# K — ручного прогона на голове нет.
K="$(mkcase K)"
mk_pr "$K/pr.json" OPEN CLEAN
mk_ws_protection "$K/protection.json"
printf '{"total_count":0,"workflow_runs":[]}\n' > "$K/runs.json"

# L — на голове красный ручной прогон (один check-run упал).
L="$(mkcase L)"
mk_pr "$L/pr.json" OPEN CLEAN
mk_ws_protection "$L/protection.json"
mk_runs "$L/runs.json" "502,$HEAD_SHA,completed,failure,$T1,9002"
mk_checkruns "$L/checkruns.json" "9002|$CTX_LAT|completed|success" \
    "9002|$CTX_CYR|completed|failure"

# M — ручной прогон на голове идёт.
M="$(mkcase M)"
mk_pr "$M/pr.json" OPEN CLEAN
mk_ws_protection "$M/protection.json"
mk_runs "$M/runs.json" "503,$HEAD_SHA,in_progress,,$T1,9003"
mk_checkruns "$M/checkruns.json" "9003|$CTX_LAT|completed|success" \
    "9003|$CTX_CYR|in_progress|"

# N — зелёный прогон есть, но на ПРЕЖНЕЙ голове; сосед вернул его на вопрос о новой.
N="$(mkcase N)"
mk_pr "$N/pr.json" OPEN CLEAN
mk_ws_protection "$N/protection.json"
mk_runs "$N/runs.json" "504,$OLD_SHA,completed,success,$T1,9004"
mk_checkruns "$N/checkruns.json" "9004|$CTX_LAT|completed|success"

# O — на голове два прогона: прежний зелёный, последний красный.
O="$(mkcase O)"
mk_pr "$O/pr.json" OPEN CLEAN
mk_ws_protection "$O/protection.json"
mk_runs "$O/runs.json" "505,$HEAD_SHA,completed,success,$T0,9005" \
    "506,$HEAD_SHA,completed,failure,$T1,9006"
mk_checkruns "$O/checkruns.json" "9005|$CTX_LAT|completed|success" \
    "9006|$CTX_LAT|completed|failure"

# S — близнец O: прежний красный, последний зелёный; красное прежнего не в счёт.
S="$(mkcase S)"
mk_pr "$S/pr.json" OPEN CLEAN
mk_ws_protection "$S/protection.json"
mk_runs "$S/runs.json" "507,$HEAD_SHA,completed,failure,$T0,9007" \
    "508,$HEAD_SHA,completed,success,$T1,9008"
mk_checkruns "$S/checkruns.json" "9007|$CTX_LAT|completed|failure" \
    "9008|$CTX_LAT|completed|success"

# P — защита базы воркспейса снова требует контекст: объявление истекло.
P="$(mkcase P)"
mk_pr "$P/pr.json" OPEN CLEAN
mk_protection "$P/protection.json" "$CTX_LAT"
mk_runs "$P/runs.json" "509,$HEAD_SHA,completed,success,$T1,9009"
mk_checkruns "$P/checkruns.json" "9009|$CTX_LAT|completed|success"

# Q — ответ о прогонах не разбирается.
Q="$(mkcase Q)"
mk_pr "$Q/pr.json" OPEN CLEAN
mk_ws_protection "$Q/protection.json"
printf '<html><head><title>502</title></head></html>\n' > "$Q/runs.json"

# R — прогон зелёный, а его check-runs нет: на sha лежат только чужие.
R="$(mkcase R)"
mk_pr "$R/pr.json" OPEN CLEAN
mk_ws_protection "$R/protection.json"
mk_runs "$R/runs.json" "510,$HEAD_SHA,completed,success,$T1,9010"
mk_checkruns "$R/checkruns.json" "7777|$CTX_LAT|completed|success"

# U — база воркспейса не защищена (ветка волны), ручной прогон зелёный.
U="$(mkcase U)"
mk_pr "$U/pr.json" OPEN CLEAN
: > "$U/protection.unavailable"
: > "$U/protection.json"
mk_runs "$U/runs.json" "511,$HEAD_SHA,completed,success,$T1,9011"
mk_checkruns "$U/checkruns.json" "9011|$CTX_LAT|completed|success"

# Три пробы ниже держат по одной охране, которую до них не держало ничего: снятие
# каждой оставляло набор зелёным (опыты check-verifier M1–M3 по ws#788). У каждой
# фикстуры ровно одно отличие от J — зелёного ручного прогона на голове.

# V — прогон на голове идёт, а все поднятые им check-runs уже зелёные: заданий,
# которых ещё нет, в перечне не видно. Отличие от J — только состояние прогона.
V="$(mkcase V)"
mk_pr "$V/pr.json" OPEN CLEAN
mk_ws_protection "$V/protection.json"
mk_runs "$V/runs.json" "513,$HEAD_SHA,in_progress,,$T1,9013"
mk_checkruns "$V/checkruns.json" "9013|$CTX_LAT|completed|success" \
    "9013|$CTX_DASH|completed|success" "9013|$CTX_CYR|completed|success"

# W — ответ о check-runs усечён: прочитано три из ста пятидесяти, все три
# зелёные. Непрочитанная страница могла нести красное. Отличие от J — только
# total_count ответа.
W="$(mkcase W)"
mk_pr "$W/pr.json" OPEN CLEAN
mk_ws_protection "$W/protection.json"
mk_runs "$W/runs.json" "514,$HEAD_SHA,completed,success,$T1,9014"
mk_checkruns "$W/checkruns.json" "9014|$CTX_LAT|completed|success" \
    "9014|$CTX_DASH|completed|success" "9014|$CTX_CYR|completed|success"
jq '.total_count = 150' "$W/checkruns.json" > "$W/checkruns.tmp" && mv "$W/checkruns.tmp" "$W/checkruns.json"

# X — прогон на голове не поднял ни одного задания (`startup_failure`): check-runs
# у него нет, и красен он исходом целиком, а не перечнем. Пустой перечень
# записан явно — `mk_checkruns` без строк породил бы одну пустую запись.
X="$(mkcase X)"
mk_pr "$X/pr.json" OPEN CLEAN
mk_ws_protection "$X/protection.json"
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

# ── ПРОБЫ ────────────────────────────────────────────────────────────────────
probes=0
findings=0
declare -A by_code=() by_repo=()

# Репозиторий выбирает источник вердикта, поэтому он — часть пробы: продукт
# судится обязательными контекстами, воркспейс — ручным прогоном.
PRODUCT_REPO="PRO-Robotech/kacho"
WS_REPO="PRO-Robotech/kacho-workspace"

# probe <репозиторий> <каталог> <ожидаемый-код> <имя-пробы> <обязательная-подстрока>...
probe() {
    local repo="$1" dir="$2" want="$3" title="$4"; shift 4
    local out rc needle
    probes=$((probes + 1))
    by_code[$want]=$(( ${by_code[$want]:-0} + 1 ))
    by_repo[$repo]=$(( ${by_repo[$repo]:-0} + 1 ))
    out="$(PATH="$STUB:$PATH" MR_FIXTURE="$dir" \
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

probe "$PRODUCT_REPO" "$C" 2 "защита ветки не настроена — беспредметно, а не «нельзя»" \
    "НЕ ЗАЩИЩЕНА"

probe "$PRODUCT_REPO" "$D" 2 "PR недоступен — беспредметно, а не «нельзя»" \
    "недоступен"

probe "$PRODUCT_REPO" "$E" 2 "ответ о защите не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$PRODUCT_REPO" "$F" 2 "ответ о PR не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$PRODUCT_REPO" "$G" 2 "обязательных контекстов ноль — беспредметно, а не «нельзя»" \
    "обязательных контекстов ноль"

probe "$PRODUCT_REPO" "$H" 1 "имена, различные только длинным тире, не схлопнуты — учтены оба" \
    "обязательных контекстов: 2" "проба - раз"

probe "$PRODUCT_REPO" "$I" 2 "PR уже не открыт — беспредметно, а не «нельзя»" \
    "сливать нечего"

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

probe "$WS_REPO" "$P" 2 "воркспейс: защита снова требует контекст — объявление истекло, вердикта нет" \
    "расходится с сервером"

probe "$WS_REPO" "$Q" 2 "воркспейс: ответ о прогонах не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$WS_REPO" "$R" 2 "воркспейс: у прогона нет своих check-runs — «не выполнилось», чужие не в счёт" \
    "НЕ ВЫПОЛНИЛОСЬ" "зелёных 0 из 0"

probe "$WS_REPO" "$U" 0 "воркспейс: база без защиты, ручной прогон зелёный — «сливать можно»" \
    "можно сливать"

probe "$WS_REPO" "$V" 1 "воркспейс: прогон идёт при всех зелёных check-runs — «нельзя сейчас», а не «можно»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "идёт" "прогон 513 целиком [IN_PROGRESS]"

probe "$WS_REPO" "$W" 2 "воркспейс: ответ о check-runs усечён — вердикта нет, а не «можно»" \
    "РАЗБОР СЛОМАН" "получено 3 из 150"

probe "$WS_REPO" "$X" 1 "воркспейс: прогон без заданий (startup_failure) — «сливать нельзя», а не «не выполнилось»" \
    "СЛИВАТЬ НЕЛЬЗЯ" "прогон 515 целиком [STARTUP_FAILURE]"

tooling_gate_census "$NAME: проб исполнено $probes над $TOOL_REL; источников вердикта два — контексты продукта (проб ${by_repo[$PRODUCT_REPO]:-0}) и ручной прогон воркспейса (проб ${by_repo[$WS_REPO]:-0}); по исходам: 0 — ${by_code[0]:-0}, 1 — ${by_code[1]:-0}, 2 — ${by_code[2]:-0}"

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings из $probes"
    exit 1
fi

tooling_gate_pass "$NAME" "инструмент различает все три исхода у обоих источников: вердикт печатается, отказ разбора и «не выполнилось» приходят кодом 2, имена контекстов не схлопываются, ручной прогон судится на голове"
