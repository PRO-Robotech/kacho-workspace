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
# РЕЖИМ `--proof` — ПЕРЕД ТЕМ, КАК КАСКАД ЗАКРОЕТ ЗАДАЧИ ВЛИТОЙ ВОЛНЫ. Строка
# `Closes` исполняется лишь в ветке по умолчанию, а запрос волны идёт в ветку
# эпика: задачи волны закрывает `git-operator` явным действием каскада
# (`git-issues.md#gi-cascade-no-auto-close`), и `merge-readiness.sh` такого
# закрытия не видит. Поэтому доказательство DoD (`gi-closes-last-line`) судится
# здесь: у каждого ОТКРЫТОГО дочернего — комментарий со строкой
# `DoD-proof @<ревизия>` в начале строки. Нет хоть у одного — находка с номерами:
# такая задача каскадом не закрывается, а переводится остатком
# (`gi-cascade-remainder`). Комментарии не прочитаны — вердикта нет (код 2).
# Закрытые дочерние не судятся: их закрыло не это действие. Без ключа
# доказательство не спрашивается (возврат check-verifier, ws#920).
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
#                   один дочерний, либо с `--proof` у открытого дочернего нет
#                   доказательства DoD;
#               2 — вердикта нет: задача не читается, ответ не разбирается,
#                   с `--proof` комментарии открытого дочернего не прочитаны,
#                   либо дочерних ноль в обоих отношениях (пустая волна — не
#                   «открытых ноль»).
# Находка объявляется раньше беспредметности: расхождение отношений —
# находка, даже если состояние части дочерних прочитать не удалось.
set -uo pipefail

# Распознаватель доказательства DoD — общий для всего дерева (`lib/dod_proof.jq`),
# своей копии выражения здесь нет.
dod_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

usage() {
    echo "usage: cascade-census.sh [--children-closed | --proof] <владелец/репо> <номер задачи>" >&2
    exit 2
}
WANT_CLOSED=0
WANT_PROOF=0
case "${1:-}" in
    --children-closed) WANT_CLOSED=1; shift ;;
    --proof) WANT_PROOF=1; shift ;;
esac
[ "$#" -eq 2 ] || usage
if [ "$WANT_PROOF" = 1 ] && [ ! -r "$dod_lib/dod_proof.jq" ]; then
    echo "cascade-census: распознавателя доказательства DoD нет ($dod_lib/dod_proof.jq) — судить нечем" >&2
    exit 2
fi
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

# ── Доказательство DoD у открытых дочерних (`--proof`) ───────────────────────
proof_missing=""
proof_unread=""
if [ "$WANT_PROOF" = 1 ]; then
    proof_ok=0
    while IFS=$'\t' read -r _ ref _; do
        [ -n "$ref" ] || continue
        r="${ref%#*}"
        n="${ref##*#}"
        # По странице — true/false; доказано, если true хоть на одной. Распознаватель —
        # общий `lib/dod_proof.jq` (своей копии выражения здесь нет); отказ трекера
        # роняет трубу (`pipefail`), и задача уходит в «не прочитано».
        if pages="$(gh api --paginate "repos/$r/issues/$n/comments" 2> /dev/null \
                | jq -L "$dod_lib" 'include "dod_proof"; [.[] | (.body // "") | dod_proof] | any' 2> /dev/null)" \
            && [ -n "$pages" ] && ! grep -qvxE 'true|false' <<<"$pages"; then
            if grep -qx true <<<"$pages"; then
                proof_ok=$((proof_ok + 1))
            else
                proof_missing="$proof_missing $ref"
            fi
        else
            proof_unread="$proof_unread $ref"
        fi
    done < "$TMP/open"
    echo "  режим:      --proof — у открытого дочернего обязателен комментарий «DoD-proof @<ревизия>»"
    echo "  DoD-proof:  открытых $open_n · с доказательством $proof_ok · без:${proof_missing:- —} · не прочитано:${proof_unread:- —}"
fi

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
if [ -n "$proof_missing" ]; then
    echo "НАХОДКА: --proof, у открытых дочерних нет доказательства DoD:$proof_missing — каскад их не закрывает, они переводятся остатком (gi-cascade-remainder)"
    rc=1
fi
[ "$rc" -eq 1 ] && exit 1
[ -z "$proof_unread" ] || void "комментарии открытых дочерних не прочитаны:$proof_unread — доказательство DoD не сверено"

if [ "$all_total" -eq 0 ]; then
    void "дочерних ноль в обоих отношениях: пустой уровень — не «открытых ноль»"
fi

echo "ИТОГ: дочерних $all_total, отношения не расходятся, открытых $open_n"
exit 0
