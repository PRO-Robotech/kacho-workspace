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
# ЧТЕНИЕ ЗАЩИТЫ И ЧЕЙ НАБОР СУДИТ (ws#844, решение диспетчера 2026-10-01).
# Подставной gh отдаёт ответ-отказ НАСТОЯЩЕЙ формы — тело в stdout и ненулевой
# код. Прежняя фикстура «не защищена» была пустым ответом, а настоящий gh пишет
# 404 «Branch not protected» телом: инструмент брал его за защиту без
# контекстов, и проба C этого не видела. Случаи C-* держат три исхода чтения,
# EP-* — набор ствола для базы-ветки линии (эпик, волна), NE-* — его отсутствие
# для прочих баз.
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
# `api` различается по ПУТИ: инструмент читает у соседа ровно защиту ветки.
# Любой иной путь — отказ 99: чтение, которого инструмент делать не обязан,
# видно, а не проходит пустым ответом. Фикстура защиты — СВОЯ НА КАЖДУЮ ВЕТКУ
# (`protection@<ветка>`): чтение защиты ветки, у которой фикстуры нет (например,
# ствола там, где набор ствола брать не положено), — отказ 98, а не ответ.
case "${1:-}" in
    pr)  target="${MR_FIXTURE:?}/pr" ;;
    api)
        case "${2:-}" in
            */branches/*/protection)
                br="${2#*/branches/}"; br="${br%/protection}"
                target="${MR_FIXTURE:?}/protection@$br" ;;
            *) echo "gh-stub: незнакомый путь api: $*" >&2; exit 99 ;;
        esac ;;
    *)   echo "gh-stub: незнакомый вызов: $*" >&2; exit 99 ;;
esac
if [ ! -e "$target.json" ] && [ ! -e "$target.unavailable" ]; then
    echo "gh-stub: фикстуры $target.json нет" >&2; exit 98
fi
if [ -e "$target.unavailable" ]; then exit 1; fi
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

mkcase() { local d="$TMP/case-$1"; mkdir -p "$d"; printf '%s' "$d"; }

mk_protection() {  # <файл> <контекст>...
    local f="$1"; shift
    printf '%s\n' "$@" | jq -R . | jq -s '{required_status_checks:{contexts:.}}' > "$f"
}

# База PR — `MR_BASE` (по умолчанию `main`): для случаев ветки линии задаётся
# на вызов.
mk_pr() {  # <файл> <состояние> <состояние-слияния> <зелёный-контекст>...
    local f="$1" st="$2" ms="$3"; shift 3
    local rollup='[]'
    if [ "$#" -gt 0 ]; then
        rollup="$(printf '%s\n' "$@" | jq -R '{name: ., conclusion: "SUCCESS"}' | jq -s .)"
    fi
    jq -n --arg st "$st" --arg ms "$ms" --arg b "${MR_BASE:-main}" --argjson r "$rollup" \
        '{state:$st, baseRefName:$b, mergeStateStatus:$ms, statusCheckRollup:$r}' > "$f"
}

# mk_refusal <каталог> <ветка> <код> <тело> — ответ-отказ настоящей формы:
# тело в stdout и ненулевой код. Тело 404 «Branch not protected» — дословно
# то, что gh 2.100.0 вернул 2026-10-01 на `branches/2914-notify/protection`.
BODY_UNPROTECTED='{"message":"Branch not protected","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"404"}'
mk_refusal() {
    printf '%s\n' "$4" > "$1/protection@$2.json"
    printf '%s\n' "$3" > "$1/protection@$2.rc"
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

# ── БАЗА — ВЕТКА ЛИНИИ: СУДИТ НАБОР СТВОЛА (решение диспетчера 2026-10-01) ────
# Ветка эпика или волны (`[0-9]+` либо `[0-9]+-*`, формы фильтра Д59) своей
# защиты не несёт (Д62), и инструмент судит её PR набором ствола `main`.
# Каждый случай меняет против EP-GREEN ровно один факт.
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
by_code0=0; by_code1=0; by_code2=0

# probe <каталог> <ожидаемый-код> <имя-пробы> <обязательная-подстрока>...
#
# Имя пробы начинается МЕТКОЙ случая — `[<буква>]` из имени каталога фикстуры.
# По метке inject.sh сверяет, что порча решения покраснила ИМЕННО держащую его
# пробу, а не соседнюю: код 1 набора сам по себе этого не говорит.
#
# Перепись по кодам считается ЗДЕСЬ, по вызовам, а не
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
    out="$(PATH="$STUB:$PATH" MR_FIXTURE="$dir" LC_ALL="${PROBE_LOCALE:-${LC_ALL:-}}" \
        bash "$WS/$TOOL_REL" PRO-Robotech/kacho-workspace 1 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -ne "$want" ]; then
        tooling_gate_fail "$NAME" "$title — ждали код $want, получили $rc"
        printf '%s\n' "${out//$'\n'/$'\n'      }" | sed 's/^/      /' >&2
        findings=$((findings + 1))
        return
    fi
    for needle in "$@"; do
        # Здесь-строка, а не труба: `grep -q` под pipefail роняет пишущего по SIGPIPE.
        if ! grep -qF -- "$needle" <<<"$out"; then
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

probe "$C" 2 "защита ветки не настроена (404 «Branch not protected») — «НЕ ЗАЩИЩЕНА», а не «защита есть»" \
    "НЕ ЗАЩИЩЕНА" "Branch not protected"

for rf in EMPTY 403 404NF; do
    probe "$TMP/case-C-$rf" 2 "ответ о защите — отказ ($rf), а не состояние — «НЕ ПРОЧИТАНА»" \
        "защита ветки 'main' НЕ ПРОЧИТАНА" "отказ чтения, а не состояние защиты"
done

probe "$TMP/case-EP-GREEN" 0 "база-эпик без защиты, набор ствола зелен — «сливать можно» по набору ствола" \
    "можно сливать" "набор обязательных: ствола 'main'" "(ветка не защищена)" "обязательных контекстов: 3"
probe "$TMP/case-EP-RED" 1 "база-эпик, контекст из набора ствола красный — «сливать нельзя», имя названо" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR — красный" "набор обязательных: ствола 'main'"
probe "$TMP/case-EP-MISSING" 1 "база-эпик, контекст из набора ствола не появлялся — «нельзя», без слов о защите базы" \
    "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR — НЕ ПОЯВЛЯЛСЯ" "у базы защиты нет"
probe "$TMP/case-EP-WAVE" 0 "база-волна голым номером — та же ветка линии, набор ствола" \
    "можно сливать" "у ветки линии '$WAVE'" "обязательных контекстов: 3"
probe "$TMP/case-EP-ZERO" 0 "база-эпик с защитой без контекстов — набор ствола, а не «ничем не гейтится»" \
    "можно сливать" "у ветки линии '$EPIC' собственного нет (защита есть" "обязательных контекстов: 3"
probe "$TMP/case-EP-OWN" 0 "база-эпик со своим набором — судит он, ствол не читается" \
    "можно сливать" "набор обязательных: собственный ветки '$EPIC'" "обязательных контекстов: 1"
probe "$TMP/case-EP-BARE" 2 "не защищены ни эпик, ни ствол — беспредметно" \
    "ствол 'main' НЕ ЗАЩИЩЕН"
for rf in 403 EMPTY; do
    probe "$TMP/case-EP-TRUNK-$rf" 2 "база-эпик, защита ствола не прочитана ($rf) — «НЕ ПРОЧИТАНА», а не «ствол НЕ ЗАЩИЩЕН»" \
        "защита ветки 'main' НЕ ПРОЧИТАНА" "отказ чтения, а не состояние защиты"
done
for nb in $NE_BASES; do
    probe "$TMP/case-NE-$nb" 2 "база '$nb' не формы линии, без защиты — «НЕ ЗАЩИЩЕНА», набор ствола не берётся" \
        "ветка '$nb' НЕ ЗАЩИЩЕНА"
done

probe "$D" 2 "PR недоступен — беспредметно, а не «нельзя»" \
    "недоступен"

probe "$E" 2 "ответ о защите не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$F" 2 "ответ о PR не разбирается — беспредметно, а не «нельзя»" \
    "РАЗБОР СЛОМАН"

probe "$G" 2 "обязательных контекстов ноль — беспредметно, а не «нельзя» и не «можно»" \
    "обязательных контекстов ноль" "ничем не гейтится"

for ms in $MS_HELD; do
    probe "$TMP/case-A-$ms" 1 "с контекстами: все обязательные зелены, состояние слияния $ms — задержано, а не «можно»" \
        "СЛИЯНИЕ ЗАДЕРЖАНО" "состояние слияния: $ms" "обязательных контекстов: 3"
done

for ms in $MS_LAWFUL; do
    probe "$TMP/case-Z-$ms" 0 "с контекстами: все обязательные зелены, состояние слияния $ms — «сливать можно»" \
        "можно сливать" "состояние слияния: $ms"
done

for oc in $RC_OUTCOMES; do
    d="$TMP/case-RC-$oc"
    case " $RC_OTHER " in *" $oc "*) other=1 ;; *) other=0 ;; esac
    if [ "$oc" = running ]; then
        probe "$d" 1 "с контекстами: обязательный контекст идёт — «сливать нельзя», а не «можно»" \
            "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR — идёт" "без него: 1"
    elif [ "$other" -eq 1 ]; then
        probe "$d" 1 "с контекстами: обязательный контекст $oc — не зелёный, «сливать нельзя»" \
            "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR [$oc] — не зелёный" "без него: 1"
    else
        probe "$d" 1 "с контекстами: обязательный контекст $oc — «сливать нельзя», а не «можно»" \
            "СЛИВАТЬ НЕЛЬЗЯ" "$CTX_CYR [$oc]" "$CTX_CYR — красный"
    fi
done

probe "$H" 1 "имена, различные только длинным тире, не схлопнуты — учтены оба" \
    "обязательных контекстов: 2" "проба - раз"

probe "$I" 2 "PR уже не открыт — беспредметно, а не «нельзя»" \
    "сливать нечего"

tooling_gate_census "$NAME: проб исполнено $probes над $TOOL_REL; по ожидаемому коду: 0 — $by_code0, 1 — $by_code1, 2 — $by_code2"
tooling_gate_census "$NAME: $locale_note"
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
