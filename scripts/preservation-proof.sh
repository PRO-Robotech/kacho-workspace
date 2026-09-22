#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# preservation-proof.sh — сохранность работы полосы после слияния, доказанная
# СОДЕРЖИМЫМ. Исполняемая форма нормы
# `.claude/rules/security-disclosure.md` §«Проверяемый признак для СООБЩЕНИЯ
# КОММИТА» (`disc-preservation-proof`).
#
# ПРЕДОК — НЕ ДОКАЗАТЕЛЬСТВО. Вливание — коммитом слияния (решение владельца
# 2026-09-22, ws#770): голова полосы становится предком итога сразу, но
# разрешение конфликта теряет строки молча, и `merge-base --is-ancestor` об этом
# не скажет. БАЗА — ствол ДО слияния: для коммита слияния это его первый
# родитель (`<итог>^1`); ствол, названный после посадки, уже содержит полосу, и
# знаменатель от него пуст — это отдельный отказ, а не «полоса пуста».
#
# ЗНАМЕНАТЕЛЬ — ПУТИ ВСЕЙ ПОЛОСЫ, А НЕ ГОЛОВНОГО КОММИТА. Прежняя запись нормы
# брала `git show --name-only --format= <голова>`, то есть файлы ОДНОГО коммита.
# Замер 2026-09-22 на настоящей полосе: коммитов три, путей 11, головной коммит
# трогает 3. Доказательство по трём путям пусто И ТОГДА, когда работа потеряна в
# остальных восьми; на той полосе оно совпало с истиной ПО УДАЧЕ РАСКЛАДКИ.
# Отсюда знаменатель: `git diff --name-only $(git merge-base <база> <голова>)..<голова>`.
#
# НЕПУСТОЕ РАСХОЖДЕНИЕ — НЕ ВЕРДИКТ. На широком знаменателе расхождение почти
# всегда непусто: в тот же файл писала соседняя полоса. Замер той же пары —
# 14 176 байт расхождения при нулевой потере. Поэтому вердикт даёт не размер
# дифа, а две оси:
#
#   ОСЬ 1, ТОЖДЕСТВО ДЕРЕВА (сильнейшая). `git merge-tree --write-tree <база>
#   <голова>` считает дерево трёхстороннего слияния, НЕ ИСПОЛНЯЯ его. Совпало с
#   деревом итога — сохранность доказана целиком, разбирать строки не нужно.
#   СРОК ГОДНОСТИ: факт верен для КОНКРЕТНОЙ ПАРЫ ГОЛОВ; сдвинется любая —
#   истекает, поэтому обе sha печатаются рядом с вердиктом.
#   Эта ось работает и ДО необратимого шага: предсказать дерево, сделать, сверить
#   (`--predict` печатает предсказание отдельно).
#
#   ОСЬ 2, ПОСТРОЧНАЯ ПЕРЕПИСЬ ПО ЗНАМЕНАТЕЛЮ. Каждая непустая строка, добавленная
#   полосой, обязана присутствовать в итоге дословно и в том же количестве; каждая
#   снятая полосой — НЕ уцелеть. Обе половины обязательны: без второй полоса, чья
#   работа — снятие, объявлялась бы сохранной молча.
#   Перепись — СВИДЕТЕЛЬСТВО, а не доказательство тождества: совпадение строк не
#   есть совпадение работы, и читается её исход только в сторону «потери нет».
#
# ТРИ ИСХОДА: 0 — потерь не найдено (сказано, какой осью); 1 — НАХОДКА: строки
# полосы в итоге отсутствуют либо снятое уцелело; 2 — БЕЗ ПРЕДМЕТА (не репозиторий,
# ревизия не резолвится, знаменатель пуст — сверять нечего, и это не успех).
#
# Способность упасть и смолчать доказана `scripts/preservation-proof-inject.sh`.
set -uo pipefail

usage() {
    cat >&2 <<'EOF'
preservation-proof.sh [-C <репо>] <база> <голова полосы> [<итог>]
preservation-proof.sh [-C <репо>] --predict <база> <голова полосы>
  база   — ствол ДО слияния (для коммита слияния — <итог>^1)
  голова — голова полосы, которую вливали
  итог   — что получилось; по умолчанию HEAD
  0 — потерь не найдено · 1 — потеря · 2 — сверять нечего
EOF
}

repo="."
predict_only=0
while [ $# -gt 0 ]; do
    case "$1" in
        -C) repo="${2:-}"; shift 2 || { usage; exit 2; } ;;
        --predict) predict_only=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

[ $# -ge 2 ] || { usage; exit 2; }
base_ref="$1"; head_ref="$2"; result_ref="${3:-HEAD}"

root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "preservation-proof: БЕЗ ПРЕДМЕТА — «$repo» не рабочая копия git" >&2; exit 2; }
cd "$root" || exit 2

resolve() {
    local r; r="$(git rev-parse --verify -q "$1^{commit}" 2>/dev/null)" || {
        echo "preservation-proof: БЕЗ ПРЕДМЕТА — ревизия «$1» не резолвится" >&2; exit 2; }
    printf '%s' "$r"
}
base="$(resolve "$base_ref")" || exit 2
head="$(resolve "$head_ref")" || exit 2

mb="$(git merge-base "$base" "$head" 2>/dev/null)"
if [ -z "$mb" ]; then
    echo "preservation-proof: БЕЗ ПРЕДМЕТА — у «$base_ref» и «$head_ref» нет общего предка" >&2
    exit 2
fi
# База, уже содержащая голову, названа ПОСЛЕ слияния: знаменатель от неё пуст не
# потому, что полоса ничего не трогала. Равенство базы и головы — другой случай
# (сверять и правда нечего), он уходит в отказ пустого знаменателя ниже.
if [ "$mb" = "$head" ] && [ "$base" != "$head" ]; then
    echo "preservation-proof: БЕЗ ПРЕДМЕТА — база «$base_ref» уже содержит голову полосы $head:" >&2
    echo "  слияние состоялось, и знаменатель от этой базы пуст. Назовите ствол ДО слияния —" >&2
    echo "  для коммита слияния это его первый родитель: <итог>^1" >&2
    exit 2
fi

# ── ПРЕДСКАЗАНИЕ ДЕРЕВА: считается, но НЕ ИСПОЛНЯЕТСЯ ────────────────────────
# ТРИ ИСХОДА У САМОГО ПРЕДСКАЗАНИЯ, и путать их нельзя: «не поддерживается» и
# «слияние конфликтует» — разные факты, а первая редакция звала их одним словом
# и объявляла недоступным инструмент, который прекрасно работал (нашлось пробой
# C в inject: конфликтующая пара давала код 1).
predicted=""
mt_out="$(git merge-tree --write-tree "$base" "$head" 2>&1)"
case $? in
    0) predicted="$(printf '%s\n' "$mt_out" | head -1)"
       predict_note="предсказано деревом трёхстороннего слияния" ;;
    1) predict_note="трёхстороннее слияние $base × $head КОНФЛИКТУЕТ — дерево не предсказуемо, судит ось 2" ;;
    *) predict_note="git merge-tree --write-tree недоступен ($(git --version)) — ось тождества дерева не работала" ;;
esac

if [ "$predict_only" = 1 ]; then
    if [ -z "$predicted" ]; then
        echo "preservation-proof: БЕЗ ПРЕДМЕТА — $predict_note" >&2
        exit 2
    fi
    echo "preservation-proof: предсказанное дерево слияния $base × $head = $predicted"
    echo "  СРОК ГОДНОСТИ: факт верен для этой пары голов; сдвинется любая — истекает."
    exit 0
fi

result="$(resolve "$result_ref")" || exit 2

# ── ЗНАМЕНАТЕЛЬ — ПУТИ ВСЕЙ ПОЛОСЫ ───────────────────────────────────────────
mapfile -t paths < <(git diff --name-only "$mb..$head" 2>/dev/null)
mapfile -t head_paths < <(git show --name-only --format= "$head" 2>/dev/null | sed '/^$/d' | sort -u)

if [ "${#paths[@]}" -eq 0 ]; then
    echo "preservation-proof: БЕЗ ПРЕДМЕТА — полоса $mb..$head не трогает НИ ОДНОГО пути" >&2
    echo "  Пустой знаменатель дал бы пустое расхождение и зелёное на любой потере." >&2
    exit 2
fi

commits="$(git rev-list --count "$mb..$head" 2>/dev/null || echo 0)"
delta_bytes="$(git diff "$head" "$result" -- "${paths[@]}" 2>/dev/null | wc -c)"

echo "preservation-proof: полоса $mb..$head — коммитов $commits, путей ${#paths[@]}; головной коммит трогает ${#head_paths[@]}"
if [ "${#head_paths[@]}" -lt "${#paths[@]}" ]; then
    echo "  прежний знаменатель (файлы головного коммита) не смотрел бы на $(( ${#paths[@]} - ${#head_paths[@]} )) путей полосы — молча"
fi
echo "  расхождение итога с головой по этим путям: $delta_bytes байт (это ПЕРЕПИСЬ, не вердикт: в те же файлы пишут соседние полосы)"

# ── ОСЬ 1: тождество дерева ──────────────────────────────────────────────────
result_tree="$(git rev-parse "$result^{tree}" 2>/dev/null)"
if [ -n "$predicted" ] && [ "$predicted" = "$result_tree" ]; then
    echo "preservation-proof: СОХРАНЕНО — дерево итога $result_tree равно предсказанному трёхстороннему ($predict_note)"
    echo "  срок годности факта: пара голов $base × $head; сдвинется любая — перепроверять"
    exit 0
fi
if [ -n "$predicted" ]; then
    echo "  дерево итога ($result_tree) не равно предсказанному ($predicted) — законно, если в итог вошли соседние полосы; разбирает ось 2"
else
    echo "  $predict_note"
fi

# ── ОСЬ 2: построчная перепись ПО ВСЕМУ знаменателю ───────────────────────────
missing=0
survived=0
missing_paths=()
lines_added=0
lines_removed=0
gone_paths=0

for p in "${paths[@]}"; do
    lane_blob="$(git show "$head:$p" 2>/dev/null)"; lane_rc=$?
    res_blob="$(git show "$result:$p" 2>/dev/null)"; res_rc=$?

    # Полоса СНЯЛА файл: его отсутствие в итоге — исполненная работа, а не потеря.
    if [ "$lane_rc" -ne 0 ]; then
        if [ "$res_rc" -eq 0 ]; then
            # снятое полосой вернулось — это уцелевшее снятие, находка оси 2
            survived=$((survived + 1))
            missing_paths+=("$p (полоса сняла файл, в итоге он есть)")
        fi
        continue
    fi
    if [ "$res_rc" -ne 0 ]; then
        gone_paths=$((gone_paths + 1))
        missing_paths+=("$p (файла нет в итоге вовсе)")
        missing=$((missing + 1))
        continue
    fi

    # Заголовки дифа (`+++`/`---`) отбрасываются ПО ПРИЗНАКУ, а не по номеру
    # строки: у переименования их больше одного, и счёт по позиции молча съел бы
    # первую настоящую строку.
    lane_diff="$(git diff "$mb..$head" -- "$p")"
    added="$(printf '%s\n' "$lane_diff" | grep '^+' | grep -v '^+++' | cut -c2- | grep -v '^[[:space:]]*$' | sort -u)"
    removed="$(printf '%s\n' "$lane_diff" | grep '^-' | grep -v '^---' | cut -c2- | grep -v '^[[:space:]]*$' | sort -u)"

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        lines_added=$((lines_added + 1))
        want="$(printf '%s\n' "$lane_blob" | grep -cxF -- "$line")"
        got="$(printf '%s\n' "$res_blob"  | grep -cxF -- "$line")"
        if [ "$got" -lt "$want" ]; then
            missing=$((missing + 1))
            missing_paths+=("$p: строка полосы отсутствует ($got из $want) — «${line:0:70}»")
        fi
    done <<< "$added"

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        lines_removed=$((lines_removed + 1))
        still="$(printf '%s\n' "$res_blob" | grep -cxF -- "$line")"
        was_in_lane="$(printf '%s\n' "$lane_blob" | grep -cxF -- "$line")"
        # Строка, которую полоса снимала и сама же вернула, снятой не считается.
        if [ "$still" -gt 0 ] && [ "$was_in_lane" -eq 0 ]; then
            survived=$((survived + 1))
            missing_paths+=("$p: снятая полосой строка уцелела — «${line:0:70}»")
        fi
    done <<< "$removed"
done

echo "preservation-proof: перепись — путей ${#paths[@]}, строк добавлено $lines_added, снято $lines_removed; отсутствует $missing, уцелело снятых $survived; файлов пропало $gone_paths"

if [ "$missing" -gt 0 ] || [ "$survived" -gt 0 ]; then
    echo "preservation-proof: ПОТЕРЯ — работа полосы в итоге не воспроизведена:" >&2
    printf '  %s\n' "${missing_paths[@]:0:40}" >&2
    [ "${#missing_paths[@]}" -gt 40 ] && echo "  … и ещё $(( ${#missing_paths[@]} - 40 ))" >&2
    echo "  Это ПРЯМОЙ запрет говорить «влито»: слияние могло быть частичным." >&2
    exit 1
fi

echo "preservation-proof: СОХРАНЕНО — по всем ${#paths[@]} путям полосы потерь не найдено (перепись; тождества дерева не было)"
exit 0
