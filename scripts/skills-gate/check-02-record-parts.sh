#!/usr/bin/env bash
# skills-gate #02 — запись каталога классов несёт ВСЕ семь обязательных частей.
#
# ЧТО УТВЕРЖДАЕТ. Каждая предметная запись `code-authoring` (заголовок `### N.N`
# в разделах §1–§7) несёт: имя (сам заголовок) · признак · противоядие · инцидент ·
# дату и ревизию наблюдения · предикат снятия · чем держится.
#
# ПОЧЕМУ. Скил объявляет эти семь частей обязательными в собственном §9.3. Первая
# же его редакция выпустила 18 записей из 19 без предиката снятия и все 19 без
# даты — то есть механизм накопления не связывал собственные записи. Каталог без
# предиката снятия через полгода становится ровно тем, что мы ловим в коде:
# набором утверждений, переживших свой предмет.
#
# ПРЕДПОСЫЛКА ГЕЙТА (проверяется здесь же). Запрет опирается на факт о дереве:
# записи объявлены заголовками `### N.N`, а предметные разделы — `## §1`..`## §7`.
# Сменится форма объявления — запрет станет ложью, поэтому «нашёл 0 записей» —
# отдельный исход (VOID), а не успех.
#
# Коды выхода: 0 — осмотрено N, неполных 0; 1 — неполные записи; 2 — VOID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(skills_gate_workspace_root)"
NAME="02-record-parts"
TARGET=".claude/skills/code-authoring/SKILL.md"
F="$WS/$TARGET"

if [ ! -f "$F" ]; then
    skills_gate_void "$NAME" "$TARGET отсутствует — проверять нечего"
    exit 2
fi

# Границы предметной части: от первого «## §1.» до первого «## §8».
start="$(grep -n '^## §1\.' "$F" | head -1 | cut -d: -f1 || true)"
stop="$(grep -n '^## §8\.' "$F" | head -1 | cut -d: -f1 || true)"
if [ -z "${start:-}" ] || [ -z "${stop:-}" ] || [ "$stop" -le "$start" ]; then
    skills_gate_void "$NAME" "не нашёл границы §1..§8 — форма объявления разделов сменилась, запрет больше не опирается на факт"
    exit 2
fi

body="$(sed -n "${start},$((stop - 1))p" "$F")"

# Разбор по записям: каждый `### N.N` открывает запись, следующий закрывает.
records=0
incomplete=0
report=""
declare -A missing_count=()

current=""
buf=""

check_record() {
    local head="$1" text="$2" miss=()
    [ -n "$head" ] || return 0
    records=$((records + 1))
    grep -q '^\*\*Признак'        <<<"$text" || miss+=("признак")
    grep -q '^\*\*Противоядие'    <<<"$text" || miss+=("противоядие")
    grep -q '^\*\*Что наблюдалось' <<<"$text" || miss+=("инцидент")
    # Дата и ревизия — одной строкой, дата обязана быть в форме YYYY-MM-DD,
    # ревизия — токеном в обратных кавычках (`<репо>@<sha>` либо `<sha>`).
    if ! grep -qE '^> \*\*Наблюдение:\*\*.*[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$text"; then
        miss+=("дата")
    elif ! grep -E '^> \*\*Наблюдение:\*\*' <<<"$text" | grep -qE '`[^`]*[0-9a-f]{7,40}[^`]*`'; then
        miss+=("ревизия")
    fi
    grep -q '^> \*\*Предикат снятия:\*\*' <<<"$text" || miss+=("предикат снятия")
    grep -q '^> \*\*Держится:\*\*'        <<<"$text" || miss+=("держится")

    if [ ${#miss[@]} -gt 0 ]; then
        incomplete=$((incomplete + 1))
        report+="  ${head}"$'\n'"      нет: $(IFS=', '; echo "${miss[*]}")"$'\n'
        for m in "${miss[@]}"; do
            missing_count["$m"]=$(( ${missing_count["$m"]:-0} + 1 ))
        done
    fi
}

while IFS= read -r line; do
    case "$line" in
        '### '[0-9]*)
            check_record "$current" "$buf"
            current="$line"; buf=""
            ;;
        *) buf+="$line"$'\n' ;;
    esac
done <<<"$body"
check_record "$current" "$buf"

if [ "$records" -eq 0 ]; then
    skills_gate_void "$NAME" "в §1..§7 не нашлось ни одной записи «### N.N» — форма сменилась, гейт без предмета"
    exit 2
fi

echo "перепись: осмотрено записей §1–§7 — $records; полных — $((records - incomplete)); неполных — $incomplete"

if [ "$incomplete" -gt 0 ]; then
    printf '%s' "$report" >&2
    detail=""
    for m in "${!missing_count[@]}"; do detail+="$m:${missing_count[$m]} "; done
    skills_gate_fail "$NAME" "неполных записей $incomplete из $records (по частям: ${detail% })"
    exit 1
fi

skills_gate_pass "$NAME" "все $records записей несут семь частей"
exit 0
