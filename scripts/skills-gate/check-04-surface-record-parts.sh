#!/usr/bin/env bash
# skills-gate #04 — запись каталога поверхностей несёт ВСЕ три обязательные части.
#
# ЧТО УТВЕРЖДАЕТ. Каждая предметная запись `security-surface` (заголовок вида
# `### S<N>.<M>.` в разделах `## S<N>.`) несёт: имя (сам заголовок) · **Признак** ·
# **Противоядие** · строку `> **Держится:**`.
#
# ПОЧЕМУ. Скил объявляет эти три части обязательными в собственном §0: класс без
# противоядия — жалоба, а класс, у которого не сказано, чем он держится, через
# полгода неотличим от закрытого. Соседний набор уже стоит на этом ровно наполовину:
# `check-02` держит семь частей у `code-authoring`, а 119 записей трёх других
# скилов не читает никто — и это записано у них самих. Новый каталог не имеет права
# приехать в то же состояние.
#
# ПРЕДПОСЫЛКА ГЕЙТА (проверяется здесь же). Запрет опирается на факт о дереве:
# записи объявлены заголовками `### S<N>.<M>.`, а разделы-поверхности — `## S<N>.`.
# Сменится форма объявления — запрет станет ложью, поэтому «нашёл 0 записей» —
# отдельный исход (VOID), а не успех.
#
# ЧЕГО ГЕЙТ НЕ ДЕЛАЕТ. Он не судит, верен ли класс и работает ли названный
# держатель: «класс усвоен» — свойство историческое и машинного предиката не имеет
# (`measurement-discipline` §Чего предикат не измеряет). Он держит форму записи и
# перепись — не больше.
#
# Коды выхода: 0 — осмотрено N, неполных 0; 1 — неполные записи; 2 — VOID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(skills_gate_workspace_root)"
NAME="04-surface-record-parts"
TARGET=".claude/skills/security-surface/SKILL.md"
F="$WS/$TARGET"

if [ ! -f "$F" ]; then
    skills_gate_void "$NAME" "$TARGET отсутствует — проверять нечего"
    exit 2
fi

# Предметная часть — от первого «## S1.» до первого «## §», закрывающего каталог.
start="$(grep -n '^## S1\.' "$F" | head -1 | cut -d: -f1 || true)"
stop="$(awk 'NR>1 && /^## §/{print NR; exit}' "$F" | tail -1 || true)"
if [ -z "${start:-}" ]; then
    skills_gate_void "$NAME" "не нашёл раздела «## S1.» — форма объявления поверхностей сменилась, запрет больше не опирается на факт"
    exit 2
fi
# Разделы §N после каталога поверхностей; если их нет — читаем до конца файла.
stop="$(awk -v s="$start" 'NR>s && /^## §/{print NR; exit}' "$F" || true)"
[ -n "${stop:-}" ] || stop="$(( $(wc -l <"$F") + 1 ))"
if [ "$stop" -le "$start" ]; then
    skills_gate_void "$NAME" "границы каталога поверхностей не разобраны — гейт без предмета"
    exit 2
fi

body="$(sed -n "${start},$((stop - 1))p" "$F")"

records=0
incomplete=0
surfaces=0
report=""
declare -A missing_count=()

check_record() {
    local head="$1" text="$2" miss=()
    [ -n "$head" ] || return 0
    records=$((records + 1))
    grep -q '^\*\*Признак'     <<<"$text" || miss+=("признак")
    grep -q '^\*\*Противоядие' <<<"$text" || miss+=("противоядие")
    grep -q '^> \*\*Держится:\*\*' <<<"$text" || miss+=("держится")

    if [ ${#miss[@]} -gt 0 ]; then
        incomplete=$((incomplete + 1))
        report+="  ${head}"$'\n'"      нет: $(IFS=', '; echo "${miss[*]}")"$'\n'
        for m in "${miss[@]}"; do
            missing_count["$m"]=$(( ${missing_count["$m"]:-0} + 1 ))
        done
    fi
}

current=""
buf=""
while IFS= read -r line; do
    case "$line" in
        # Заголовок поверхности ЗАКРЫВАЕТ последнюю запись предыдущей. Без этого
        # буфер последней записи каждой поверхности дотягивался бы до первого
        # `### S<N>.<M>.` следующей, захватывая её преамбулу: запись, у которой
        # часть снята, зеленела бы от строки, лежащей ЗА её границей.
        '## S'[0-9]*)
            surfaces=$((surfaces + 1))
            check_record "$current" "$buf"
            current=""; buf=""
            ;;
        '### S'[0-9]*)
            check_record "$current" "$buf"
            current="$line"; buf=""
            ;;
        *) buf+="$line"$'\n' ;;
    esac
done <<<"$body"
check_record "$current" "$buf"

if [ "$records" -eq 0 ]; then
    skills_gate_void "$NAME" "в каталоге поверхностей не нашлось ни одной записи «### S<N>.<M>.» — форма сменилась, гейт без предмета"
    exit 2
fi

# Перепись отдельным утверждением: «неполных 0» обязано быть отличимо от
# «прочитано 0» (`measurement-discipline` §Форма числа).
echo "перепись: поверхностей — $surfaces; осмотрено записей — $records; полных — $((records - incomplete)); неполных — $incomplete"

# Счёт и проверка полноты обязаны читать ОДНО множество, иначе разойдутся. Число,
# объявленное скилом в его §Счёт покрытия, сверяется с числом, которое гейт
# действительно осмотрел.
declared="$(grep -oE '^\*\*Записей класса — ([0-9]+)\*\*' "$F" | head -1 | grep -oE '[0-9]+' || true)"
if [ -z "${declared:-}" ]; then
    skills_gate_fail "$NAME" "скил не объявляет число записей строкой «**Записей класса — N**» — счёт и проверка полноты не связаны ничем"
    exit 1
fi
if [ "$declared" -ne "$records" ]; then
    echo "  объявлено записей: $declared; гейт осмотрел: $records" >&2
    skills_gate_fail "$NAME" "объявленное число записей разошлось с деревом ($declared против $records)"
    exit 1
fi

if [ "$incomplete" -gt 0 ]; then
    printf '%s' "$report" >&2
    detail=""
    for m in "${!missing_count[@]}"; do detail+="$m:${missing_count[$m]} "; done
    skills_gate_fail "$NAME" "неполных записей $incomplete из $records (по частям: ${detail% })"
    exit 1
fi

skills_gate_pass "$NAME" "$surfaces поверхностей, все $records записей несут три части; объявленное число сходится"
exit 0
