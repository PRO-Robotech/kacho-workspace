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
set -u
# `api` различается по ПУТИ: защита ветки, перечень прогонов процесса, задания
# одного прогона. Задания отдаются по номеру прогона — прочитай скрипт задания
# не того прогона, фикстуры у него нет, и промах придёт отказом соседа.
case "${1:-}" in
    pr)  target="${MR_FIXTURE:?}/pr" ;;
    api)
        case "${2:-}" in
            */branches/*/protection)      target="${MR_FIXTURE:?}/protection" ;;
            */actions/workflows/*/runs*)  target="${MR_FIXTURE:?}/runs" ;;
            */actions/runs/*/jobs*)
                rid="${2#*/actions/runs/}"; rid="${rid%%/*}"
                target="${MR_FIXTURE:?}/jobs-$rid" ;;
            *) echo "gh-stub: незнакомый путь api: $*" >&2; exit 99 ;;
        esac ;;
    *)   echo "gh-stub: незнакомый вызов: $*" >&2; exit 99 ;;
esac
if [ ! -e "$target.json" ] && [ ! -e "$target.unavailable" ]; then
    echo "gh-stub: фикстуры $target.json нет" >&2; exit 98
fi
if [ -e "$target.unavailable" ]; then exit 1; fi
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

mk_pr() {  # <файл> <состояние> <состояние-слияния> <зелёный-контекст>...
    local f="$1" st="$2" ms="$3"; shift 3
    local rollup='[]'
    if [ "$#" -gt 0 ]; then
        rollup="$(printf '%s\n' "$@" | jq -R '{name: ., conclusion: "SUCCESS"}' | jq -s .)"
    fi
    jq -n --arg st "$st" --arg ms "$ms" --arg h "$HEAD" --argjson r "$rollup" \
        '{state:$st, baseRefName:"main", headRefOid:$h, mergeStateStatus:$ms, statusCheckRollup:$r}' > "$f"
}

# Голова PR и чужая ревизия. Чужая отличается от головы ОДНИМ последним знаком —
# сверка по префиксу или по вхождению приняла бы её за голову.
HEAD="68b0d0a1ede6920b4aa7d7a99dbb7adb39ec1d25"
OTHER="68b0d0a1ede6920b4aa7d7a99dbb7adb39ec1d26"
ZERO_CTX='{"required_status_checks":null}'

mk_runs() {  # <файл> <id:sha:событие:status:conclusion:created_at>...
    local f="$1"; shift
    local rows='[]'
    if [ "$#" -gt 0 ]; then
        rows="$(printf '%s\n' "$@" | jq -R 'split(":") | {id:(.[0]|tonumber), head_sha:.[1], event:.[2],
            status:.[3], conclusion:(if .[4]=="" then null else .[4] end), created_at:.[5],
            html_url:("https://example.invalid/runs/" + .[0])}' | jq -s .)"
    fi
    jq -n --argjson r "$rows" '{total_count:($r|length), workflow_runs:$r}' > "$f"
}

mk_jobs() {  # <файл> <имя=conclusion>...
    local f="$1"; shift
    printf '%s\n' "$@" | jq -R 'capture("^(?<name>.*)=(?<c>[a-z_]*)$")
        | {name, status:(if .c=="" then "in_progress" else "completed" end),
           conclusion:(if .c=="" then null else .c end)}' \
        | jq -s '{total_count:length, jobs:.}' > "$f"
}

# mk_jobs_declared <файл> <объявлено> <имя=conclusion>... — сервер объявляет
# заданий больше, чем отдал в перечне: недочитанная страница.
mk_jobs_declared() {
    local f="$1" n="$2"; shift 2
    mk_jobs "$f" "$@"
    jq --argjson n "$n" '.total_count = $n' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# mk_green_run <каталог> — зелёный прогон ci.yaml на голове. Кладётся и туда, где
# процесс читаться НЕ ДОЛЖЕН (C, I): иначе порча выбора пути приводила бы скрипт
# к отказу соседа, кодом 2, и ложное «можно» на ней не было бы представимо.
mk_green_run() {
    mk_runs "$1/runs.json" "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
    mk_jobs "$1/jobs-11.json" "$JOB_A=success" "$JOB_B=success"
}

# Прогон процесса с заданиями «все зелены» — строительный блок проб без контекстов.
JOB_A="bats-and-shellcheck"
JOB_B="доказательства хуков инъекцией исполняются, а не лежат"
mk_zero_ctx_case() {  # <каталог> <состояние-слияния>
    mk_pr "$1/pr.json" OPEN "$2"
    printf '%s\n' "$ZERO_CTX" > "$1/protection.json"
}

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

# G — защита есть, обязательных контекстов ноль, прогона процесса нет вовсе.
G="$(mkcase G)"
mk_pr "$G/pr.json" OPEN CLEAN
printf '{"required_status_checks":{"contexts":[]}}\n' > "$G/protection.json"
mk_runs "$G/runs.json"

# ── БЕЗ ОБЯЗАТЕЛЬНЫХ КОНТЕКСТОВ ВЕРДИКТ БЕРЁТСЯ ИЗ ПРОГОНА ci.yaml НА ГОЛОВЕ ─────
# (ws#884). Каждая проба меняет против J ровно один факт.

# J — прогон на голове завершён, все задания зелены.
J="$(mkcase J)"; mk_zero_ctx_case "$J" CLEAN
mk_runs "$J/runs.json" "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
mk_jobs "$J/jobs-11.json" "$JOB_A=success" "$JOB_B=success"

# K — одно задание красное.
K="$(mkcase K)"; mk_zero_ctx_case "$K" CLEAN
mk_runs "$K/runs.json" "11:$HEAD:workflow_dispatch:completed:failure:2026-09-30T10:00:00Z"
mk_jobs "$K/jobs-11.json" "$JOB_A=success" "$JOB_B=failure"

# L — одно задание отменено.
L="$(mkcase L)"; mk_zero_ctx_case "$L" CLEAN
mk_runs "$L/runs.json" "11:$HEAD:workflow_dispatch:completed:cancelled:2026-09-30T10:00:00Z"
mk_jobs "$L/jobs-11.json" "$JOB_A=cancelled" "$JOB_B=success"

# M — прогон на голове ещё идёт.
M="$(mkcase M)"; mk_zero_ctx_case "$M" CLEAN
mk_runs "$M/runs.json" "11:$HEAD:workflow_dispatch:in_progress::2026-09-30T10:00:00Z"
mk_jobs "$M/jobs-11.json" "$JOB_A=success" "$JOB_B="

# N — зелёный прогон есть, но на ДРУГОЙ ревизии. Сервер фильтр по голове
# обещает, а засчитывается только сверенное самим скриптом.
N="$(mkcase N)"; mk_zero_ctx_case "$N" CLEAN
mk_runs "$N/runs.json" "11:$OTHER:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
mk_jobs "$N/jobs-11.json" "$JOB_A=success" "$JOB_B=success"

# O — зелёный прогон на голове, но ДРУГИМ событием.
O="$(mkcase O)"; mk_zero_ctx_case "$O" CLEAN
mk_runs "$O/runs.json" "11:$HEAD:push:completed:success:2026-09-30T10:00:00Z"
mk_jobs "$O/jobs-11.json" "$JOB_A=success" "$JOB_B=success"

# P — на голове два прогона: старый зелёный, НОВЫЙ красный. Судит последний.
P="$(mkcase P)"; mk_zero_ctx_case "$P" CLEAN
mk_runs "$P/runs.json" \
    "12:$HEAD:workflow_dispatch:completed:failure:2026-09-30T11:00:00Z" \
    "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
mk_jobs "$P/jobs-11.json" "$JOB_A=success" "$JOB_B=success"
mk_jobs "$P/jobs-12.json" "$JOB_A=failure" "$JOB_B=success"

# Q — задание пропущено: не красное и не зелёное — «не выполнилось».
Q="$(mkcase Q)"; mk_zero_ctx_case "$Q" CLEAN
mk_runs "$Q/runs.json" "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
mk_jobs "$Q/jobs-11.json" "$JOB_A=success" "$JOB_B=skipped"

# R — ответ о прогонах не разбирается.
R="$(mkcase R)"; mk_zero_ctx_case "$R" CLEAN
printf '<html><head><title>502</title></head></html>\n' > "$R/runs.json"

# S — прогон зелёный, но сервер держит слияние (BLOCKED).
S="$(mkcase S)"; mk_zero_ctx_case "$S" BLOCKED
mk_runs "$S/runs.json" "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
mk_jobs "$S/jobs-11.json" "$JOB_A=success" "$JOB_B=success"

# T — обязательные контексты ЕСТЬ и зелены, а прогон процесса на голове красный:
# поведение для репозитория с контекстами не меняется, процесс не читается.
T="$(mkcase T)"
mk_protection "$T/protection.json" "$CTX_LAT"
mk_pr "$T/pr.json" OPEN CLEAN "$CTX_LAT"
mk_runs "$T/runs.json" "11:$HEAD:workflow_dispatch:completed:failure:2026-09-30T10:00:00Z"
mk_jobs "$T/jobs-11.json" "$JOB_A=failure" "$JOB_B=success"

# U — все задания зелены, а ИТОГ ПРОГОНА — failure. Исход прогона и исходы
# заданий расходятся: вердикта нет, а не «можно».
U="$(mkcase U)"; mk_zero_ctx_case "$U" CLEAN
mk_runs "$U/runs.json" "11:$HEAD:workflow_dispatch:completed:failure:2026-09-30T10:00:00Z"
mk_jobs "$U/jobs-11.json" "$JOB_A=success" "$JOB_B=success"

# V — сервер объявил три задания, отдал два, оба зелёные. Суждение по
# прочитанной части дало бы «можно».
V="$(mkcase V)"; mk_zero_ctx_case "$V" CLEAN
mk_runs "$V/runs.json" "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
mk_jobs_declared "$V/jobs-11.json" 3 "$JOB_A=success" "$JOB_B=success"

# W — прогон завершён успехом, заданий НОЛЬ. «Все ноль заданий зелены» — пустой
# обход, а не вердикт.
W="$(mkcase W)"; mk_zero_ctx_case "$W" CLEAN
mk_runs "$W/runs.json" "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
printf '{"total_count":0,"jobs":[]}\n' > "$W/jobs-11.json"

# X* — красные исходы задания, кроме failure (K) и cancelled (L): каждый — «нельзя».
Xt="$(mkcase Xt)"; mk_zero_ctx_case "$Xt" CLEAN
mk_runs "$Xt/runs.json" "11:$HEAD:workflow_dispatch:completed:timed_out:2026-09-30T10:00:00Z"
mk_jobs "$Xt/jobs-11.json" "$JOB_A=success" "$JOB_B=timed_out"
Xa="$(mkcase Xa)"; mk_zero_ctx_case "$Xa" CLEAN
mk_runs "$Xa/runs.json" "11:$HEAD:workflow_dispatch:completed:action_required:2026-09-30T10:00:00Z"
mk_jobs "$Xa/jobs-11.json" "$JOB_A=success" "$JOB_B=action_required"
Xs="$(mkcase Xs)"; mk_zero_ctx_case "$Xs" CLEAN
mk_runs "$Xs/runs.json" "11:$HEAD:workflow_dispatch:completed:startup_failure:2026-09-30T10:00:00Z"
mk_jobs "$Xs/jobs-11.json" "$JOB_A=success" "$JOB_B=startup_failure"

# Y — прогон объявлен завершённым, а задание ещё идёт.
Y="$(mkcase Y)"; mk_zero_ctx_case "$Y" CLEAN
mk_runs "$Y/runs.json" "11:$HEAD:workflow_dispatch:completed:success:2026-09-30T10:00:00Z"
mk_jobs "$Y/jobs-11.json" "$JOB_A=success" "$JOB_B="

# S-<состояние> — прогон зелёный, сервер держит слияние. S (BLOCKED) — выше;
# здесь остальные удерживающие состояния, каждое своей пробой: порча перечня
# «можно» на любом из них — ложное «можно».
# Z-<состояние> — законные «можно» при зелёном прогоне: снятие их из перечня
# дало бы ложное «нельзя», и близнец удерживающих проб обязан молчать на них.
for ms in DIRTY BEHIND DRAFT UNKNOWN; do
    d="$(mkcase "S-$ms")"; mk_zero_ctx_case "$d" "$ms"; mk_green_run "$d"
done
for ms in UNSTABLE HAS_HOOKS; do
    d="$(mkcase "Z-$ms")"; mk_zero_ctx_case "$d" "$ms"; mk_green_run "$d"
done

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

# C и I получают зелёный прогон на голове: вердикт «можно» по процессу здесь
# доступен, и пути, ведущие к нему мимо своего решения, видны кодом 0.
mk_green_run "$C"
mk_green_run "$I"

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

# ── ПРОБЫ ────────────────────────────────────────────────────────────────────
probes=0
findings=0
by_code0=0; by_code1=0; by_code2=0
by_run=0

# probe <каталог> <ожидаемый-код> <имя-пробы> <обязательная-подстрока>...
#
# Имя пробы начинается МЕТКОЙ случая — `[<буква>]` из имени каталога фикстуры.
# По метке inject.sh сверяет, что порча решения покраснила ИМЕННО держащую его
# пробу, а не соседнюю: код 1 набора сам по себе этого не говорит.
#
# Перепись по кодам и по пути «без контекстов» считается ЗДЕСЬ, по вызовам, а не
# выписывается литералом: добавленная или снятая проба меняет строку сама.
probe() {
    local dir="$1" want="$2" title="$3"; shift 3
    local out rc needle
    title="[${dir##*/case-}] $title"
    probes=$((probes + 1))
    case "$want" in
        0) by_code0=$((by_code0 + 1)) ;;
        1) by_code1=$((by_code1 + 1)) ;;
        2) by_code2=$((by_code2 + 1)) ;;
    esac
    if [ ! -e "$dir/protection.unavailable" ] && [ -s "$dir/protection.json" ] \
        && jq -e '(.required_status_checks.contexts // []) | length == 0' "$dir/protection.json" >/dev/null 2>&1; then
        by_run=$((by_run + 1))
    fi
    out="$(PATH="$STUB:$PATH" MR_FIXTURE="$dir" \
        bash "$WS/$TOOL_REL" PRO-Robotech/kacho-workspace 1 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -ne "$want" ]; then
        tooling_gate_fail "$NAME" "$title — ждали код $want, получили $rc"
        printf '%s\n' "${out//$'\n'/$'\n'      }" | sed 's/^/      /' >&2
        findings=$((findings + 1))
        return
    fi
    for needle in "$@"; do
        if ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
            tooling_gate_fail "$NAME" "$title — код $rc верен, но в выводе нет «$needle»"
            printf '%s\n' "${out//$'\n'/$'\n'      }" | sed 's/^/      /' >&2
            findings=$((findings + 1))
            return
        fi
    done
    tooling_gate_pass "$NAME" "$title (код $rc)"
}

probe "$A" 0 "все обязательные зелены — «сливать можно»" \
    "можно сливать" "обязательных контекстов: 3"

probe "$B" 1 "обязательный контекст не появлялся — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "НЕ ПОЯВЛЯЛСЯ" "$CTX_CYR"

probe "$C" 2 "защита ветки не настроена — беспредметно, а не «нельзя»" \
    "НЕ ЗАЩИЩЕНА"

probe "$D" 2 "PR недоступен — беспредметно, а не «нельзя»" \
    "недоступен"

probe "$E" 2 "ответ о защите не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$F" 2 "ответ о PR не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$G" 2 "обязательных контекстов ноль и прогона нет — беспредметно, а не «нельзя»" \
    "обязательных контекстов ноль" "прогона ci.yaml" "НЕТ" "ВЕРДИКТА НЕТ"

probe "$J" 0 "без контекстов: прогон ci.yaml на голове зелёный — «сливать можно»" \
    "можно сливать" "заданий 2 · зелёных 2" "$HEAD"

probe "$K" 1 "без контекстов: задание прогона красное — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$JOB_B [failure]"

probe "$L" 1 "без контекстов: задание прогона отменено — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$JOB_A [cancelled]"

probe "$M" 2 "без контекстов: прогон на голове идёт — вердикта нет, а не «нельзя»" \
    "идёт" "ВЕРДИКТА НЕТ"

probe "$N" 2 "без контекстов: зелёный прогон на ДРУГОЙ ревизии не засчитан" \
    "НЕТ" "не засчитаны: 1" "ВЕРДИКТА НЕТ"

probe "$O" 2 "без контекстов: зелёный прогон ДРУГИМ событием не засчитан" \
    "НЕТ" "не засчитаны: 1" "ВЕРДИКТА НЕТ"

probe "$P" 1 "без контекстов: судит ПОСЛЕДНИЙ прогон на голове, а не любой зелёный" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$JOB_A [failure]" "runs/12"

probe "$Q" 2 "без контекстов: пропущенное задание — «не выполнилось», а не зелёное" \
    "не выполнилось" "$JOB_B [skipped]" "ВЕРДИКТА НЕТ"

probe "$R" 2 "без контекстов: ответ о прогонах не разбирается — беспредметно" \
    "РАЗБОР СЛОМАН"

probe "$S" 1 "без контекстов: прогон зелёный, но сервер держит слияние" \
    "СЛИЯНИЕ ЗАДЕРЖАНО" "BLOCKED"

probe "$T" 0 "с контекстами: прогон процесса не читается, вердикт — по контекстам" \
    "можно сливать" "обязательных контекстов: 1"

probe "$U" 2 "без контекстов: задания зелены, а итог прогона failure — вердикта нет, а не «можно»" \
    "РАЗБОР СЛОМАН" "исход прогона 'failure'"

probe "$V" 2 "без контекстов: заданий объявлено больше, чем прочитано, — вердикта нет, а не «можно»" \
    "РАЗБОР СЛОМАН" "объявлено 3, прочитано 2"

probe "$W" 2 "без контекстов: прогон без единого задания — вердикта нет, а не «можно»" \
    "заданий в прогоне 0" "ВЕРДИКТА НЕТ"

probe "$Xt" 1 "без контекстов: задание просрочено — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$JOB_B [timed_out]"

probe "$Xa" 1 "без контекстов: задание ждёт одобрения — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$JOB_B [action_required]"

probe "$Xs" 1 "без контекстов: задание не стартовало — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$JOB_B [startup_failure]"

probe "$Y" 2 "без контекстов: прогон завершён, а задание ещё идёт — вердикта нет" \
    "ИДУТ" "$JOB_B [in_progress]" "ВЕРДИКТА НЕТ"

for ms in DIRTY BEHIND DRAFT UNKNOWN; do
    d="$TMP/case-S-$ms"
    probe "$d" 1 "без контекстов: прогон зелёный, состояние слияния $ms — задержано, а не «можно»" \
        "СЛИЯНИЕ ЗАДЕРЖАНО" "состояние слияния: $ms"
done

for ms in UNSTABLE HAS_HOOKS; do
    d="$TMP/case-Z-$ms"
    probe "$d" 0 "без контекстов: прогон зелёный, состояние слияния $ms — «сливать можно»" \
        "можно сливать" "состояние слияния: $ms"
done

probe "$H" 1 "имена, различные только длинным тире, не схлопнуты — учтены оба" \
    "обязательных контекстов: 2" "проба - раз"

probe "$I" 2 "PR уже не открыт — беспредметно, а не «нельзя»" \
    "сливать нечего"

tooling_gate_census "$NAME: проб исполнено $probes над $TOOL_REL; по ожидаемому коду: 0 — $by_code0, 1 — $by_code1, 2 — $by_code2; из них без обязательных контекстов, по прогону ci.yaml, — $by_run"
for n in "$by_code0" "$by_code1" "$by_code2"; do
    if [ "$n" -eq 0 ]; then
        tooling_gate_void "$NAME" "один из трёх исходов не представлен ни одной пробой — различение не доказано"
        exit 2
    fi
done

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings из $probes"
    exit 1
fi

tooling_gate_pass "$NAME" "инструмент различает все три исхода: вердикт печатается, отказ разбора приходит кодом 2, имена контекстов не схлопываются"
