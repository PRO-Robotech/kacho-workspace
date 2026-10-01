#!/usr/bin/env bash
#
# cascade-census.sh — дочерние задачи уровня каскада (волны, эпика) по ОБОИМ
# отношениям трекера: sub-issue и перечню задач в теле.
#
# ЗАЧЕМ. Каскад закрытия (`.claude/rules/git-issues.md#gi-close-cascade`)
# закрывает уровень вместе с его дочерними. Прежний предикат читал одно
# отношение из двух — sub-issue — и печатал только открытые номера. Волна без
# единого привязанного дочернего давала пустой вывод, то есть «открытых ноль»;
# перечень в теле (`gi-epic-label-and-list`) не читался вовсе, и два объявления
# одной величины расходились молча. Замер 2026-09-26: тело kacho#2794
# перечисляет #2724, #2709 и #2714, а их родитель по sub-issue — #2795;
# у ws#786 в sub-issue #847 и #755, которых нет в перечне тела.
#
# ЧТО ПЕЧАТАЕТСЯ. Перепись каждого отношения отдельной строкой — total,
# открытых, закрытых; затем расхождение в обе стороны и открытые поимённо.
# «Открытых ноль» без total — не вердикт, поэтому total печатается всегда.
#
# ФОРМЫ ПУНКТА ПЕРЕЧНЯ В ТЕЛЕ. Пункт — строка списка задач с флажком `[ ]` или
# `[x]` и маркером `-`, `*` или `+`. Дочерний — ПЕРВАЯ ссылка сразу после
# флажка в одной из трёх форм: `#N`, `владелец/репо#N`,
# `https://github.com/владелец/репо/issues/N`. Ссылка дальше по строке —
# упоминание (PR вливания, соседняя задача), а не дочерний. Пункт с флажком без
# ссылки первой — не дочерний, их число печатается. Строки внутри огороженного
# блока кода (``` или ~~~) — пример, а не перечень. Перевод строки `\r\n` тела,
# правленного в браузере, снимается до разбора.
#
# РЕЖИМ `--children-closed` — ПЕРЕД ЗАКРЫТИЕМ УРОВНЯ, А НЕ ПОСЛЕ. Без ключа
# открытый дочерний — находка только у ЗАКРЫТОГО уровня: открытая волна с
# открытыми задачами законна. Но эпик до посадки в `main` открыт, а его волны к
# ней обязаны быть закрыты (`git-issues.md#gi-cascade-epic-main`), и без ключа
# открытый эпик с тремя открытыми волнами выходил кодом 0 (ws#771, замер
# 2026-09-26) — предикат посадки не краснел никогда, потому что до посадки эпик
# открыт всегда. С ключом открытый дочерний — находка при любом состоянии
# уровня.
#
# ПЕРЕЧНЯ В ТЕЛЕ МОЖЕТ НЕ БЫТЬ: в kacho тело волны пишет «задачи волны — её
# sub-issue, в теле они не перечисляются» (kacho#2795). Тогда сверяется одно
# отношение, и это печатается строкой, а не молчанием. Перечень есть — он
# обязан совпасть с sub-issue в обе стороны.
#
# Код возврата: 0 — дочерних больше нуля, отношения совпадают (или перечня в
#                   теле нет, и это сказано), у ЗАКРЫТОГО уровня открытых ноль,
#                   с `--children-closed` — открытых ноль у любого уровня;
#               1 — находка: отношения расходятся, либо уровень закрыт, а
#                   дочерние открыты, либо с `--children-closed` открыт хоть
#                   один дочерний;
#               2 — вердикта нет: задача не читается, ответ не разбирается,
#                   либо дочерних ноль в обоих отношениях (пустая волна — не
#                   «открытых ноль»).
# Находка объявляется раньше беспредметности: расхождение отношений —
# находка, даже если состояние части дочерних прочитать не удалось.
set -uo pipefail

usage() {
    echo "usage: cascade-census.sh [--children-closed] <владелец/репо> <номер задачи>" >&2
    exit 2
}
WANT_CLOSED=0
if [ "${1:-}" = "--children-closed" ]; then WANT_CLOSED=1; shift; fi
[ "$#" -eq 2 ] || usage
REPO=$1
NUM=$2
case "$REPO" in */*) ;; *) usage ;; esac
case "$NUM" in '' | *[!0-9]*) usage ;; esac

WHO="$REPO#$NUM"
void() {
    echo "cascade-census: $WHO — $1; вердикта НЕТ" >&2
    exit 2
}
command -v jq >/dev/null 2>&1 || void "jq не найден"
command -v perl >/dev/null 2>&1 || void "perl не найден"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── Задача верхнего уровня ───────────────────────────────────────────────────
gh api "repos/$REPO/issues/$NUM" > "$TMP/parent.json" 2> "$TMP/err" \
    || void "задача не читается: $(head -c 300 "$TMP/err")"
state="$(jq -er '.state | select(. == "open" or . == "closed")' "$TMP/parent.json" 2> /dev/null)" \
    || void "ответ о задаче не разбирается"
title="$(jq -r '.title // ""' "$TMP/parent.json")"
jq -r '.body // ""' "$TMP/parent.json" > "$TMP/body"

# ── Отношение 1: sub-issue, постранично ──────────────────────────────────────
# Ключ сверки — `владелец/репо#N` в нижнем регистре: имена владельца и
# репозитория на хостинге регистр не различают. Печатается исходное написание.
gh api --paginate "repos/$REPO/issues/$NUM/sub_issues" \
    --jq '.[] | [(.repository_url | sub("^.*/repos/"; "")), (.number | tostring), .state] | @tsv' \
    > "$TMP/sub.raw" 2> "$TMP/err" \
    || void "sub-issue не читаются: $(head -c 300 "$TMP/err")"
awk -F'\t' 'NF == 3 && $2 ~ /^[0-9]+$/ && ($3 == "open" || $3 == "closed") {
        print tolower($1) "#" $2 "\t" $1 "#" $2 "\t" $3; next }
    NF { bad = 1 }
    END { exit bad }' "$TMP/sub.raw" | LC_ALL=C sort -u -t$'\t' -k1,1 > "$TMP/sub.tsv"
[ "${PIPESTATUS[0]}" -eq 0 ] || void "ответ о sub-issue не разбирается"

# ── Отношение 2: перечень задач в теле ───────────────────────────────────────
# Печатает `ключ<TAB>ссылка` по пункту; строку `NOREF` — по пункту без ссылки.
REPO="$REPO" perl -ne '
    BEGIN { $fence = 0 }
    s/\r$//;
    if (/^\s*(```|~~~)/) { $fence = !$fence; next }
    next if $fence;
    next unless /^\s*[-*+]\s+\[[ xX]\]\s+(.*)$/;
    my $rest = $1;
    $rest =~ s/^(?:\*\*|__)//;
    my ($r, $n);
    if    ($rest =~ m{^https://github\.com/([\w.-]+/[\w.-]+)/issues/(\d+)\b}) { ($r, $n) = ($1, $2) }
    elsif ($rest =~ m{^([\w.-]+/[\w.-]+)#(\d+)\b})                            { ($r, $n) = ($1, $2) }
    elsif ($rest =~ m{^#(\d+)\b})                                            { ($r, $n) = ($ENV{REPO}, $1) }
    else  { print "NOREF\n"; next }
    print lc("$r#$n"), "\t", "$r#$n", "\n";
' "$TMP/body" > "$TMP/body.raw"
noref="$(grep -c '^NOREF$' "$TMP/body.raw" || true)"
grep -v '^NOREF$' "$TMP/body.raw" | LC_ALL=C sort -u -t$'\t' -k1,1 > "$TMP/body.keys" || true

# Состояние пункта тела берётся из sub-issue, если он там есть; иначе — отдельным
# чтением. Флажок `[x]` состоянием задачи не является.
: > "$TMP/body.tsv"
unread=0
while IFS=$'\t' read -r key ref; do
    [ -n "$key" ] || continue
    st="$(awk -F'\t' -v k="$key" '$1 == k { print $3; exit }' "$TMP/sub.tsv")"
    if [ -z "$st" ]; then
        r="${ref%#*}"
        n="${ref##*#}"
        st="$(gh api "repos/$r/issues/$n" --jq .state 2> /dev/null)" || st=""
        case "$st" in open | closed) ;; *) st="?"; unread=$((unread + 1)) ;; esac
    fi
    printf '%s\t%s\t%s\n' "$key" "$ref" "$st" >> "$TMP/body.tsv"
done < "$TMP/body.keys"

# ── Перепись ─────────────────────────────────────────────────────────────────
count() { # <файл> <состояние|*>
    awk -F'\t' -v s="$2" 's == "*" || $3 == s { n++ } END { print n + 0 }' "$1"
}
refs() { # печатает вторые поля строк stdin через пробел либо «—»
    local out
    out="$(cut -f2 | tr '\n' ' ' | sed 's/ $//')"
    printf '%s' "${out:-—}"
}

s_total="$(count "$TMP/sub.tsv" '*')"
b_total="$(count "$TMP/body.tsv" '*')"
LC_ALL=C join -t$'\t' -v1 "$TMP/body.tsv" "$TMP/sub.tsv" > "$TMP/only_body"
LC_ALL=C join -t$'\t' -v2 "$TMP/body.tsv" "$TMP/sub.tsv" | awk -F'\t' '{ print $1 "\t" $2 "\t" $3 }' > "$TMP/only_sub"
cat "$TMP/sub.tsv" "$TMP/only_body" | awk -F'\t' '$3 == "open"' > "$TMP/open"
all_total=$((s_total + $(count "$TMP/only_body" '*')))
open_n="$(count "$TMP/open" '*')"

echo "cascade-census: $WHO [$state] $title"
if [ "$WANT_CLOSED" = 1 ]; then
    echo "  режим:      --children-closed — открытый дочерний находка при любом состоянии уровня"
fi
echo "  sub-issue:  total $s_total · открытых $(count "$TMP/sub.tsv" open) · закрытых $(count "$TMP/sub.tsv" closed)"
if [ "$b_total" -gt 0 ]; then
    echo "  тело:       total $b_total · открытых $(count "$TMP/body.tsv" open) · закрытых $(count "$TMP/body.tsv" closed) · не прочитано $unread · пунктов с флажком без ссылки $noref"
    echo "  только в теле (нет в sub-issue): $(refs < "$TMP/only_body")"
    echo "  только в sub-issue (нет в теле): $(refs < "$TMP/only_sub")"
else
    echo "  тело:       перечня дочерних нет (пунктов с флажком без ссылки $noref) — сверяется одно отношение"
fi
echo "  открытые:   $(refs < "$TMP/open")"

only_b="$(count "$TMP/only_body" '*')"
only_s=0
[ "$b_total" -gt 0 ] && only_s="$(count "$TMP/only_sub" '*')"

rc=0
if [ "$only_b" -gt 0 ] || [ "$only_s" -gt 0 ]; then
    echo "НАХОДКА: отношения дочерних расходятся — только в теле $only_b, только в sub-issue $only_s"
    rc=1
fi
if [ "$state" = closed ] && [ "$open_n" -gt 0 ]; then
    echo "НАХОДКА: уровень закрыт, а открытых дочерних $open_n"
    rc=1
elif [ "$WANT_CLOSED" = 1 ] && [ "$open_n" -gt 0 ]; then
    echo "НАХОДКА: --children-closed, а открытых дочерних $open_n — уровень закрывать рано"
    rc=1
fi
[ "$rc" -eq 1 ] && exit 1

if [ "$all_total" -eq 0 ]; then
    void "дочерних ноль в обоих отношениях: пустой уровень — не «открытых ноль»"
fi

echo "ИТОГ: дочерних $all_total, отношения не расходятся, открытых $open_n"
exit 0
