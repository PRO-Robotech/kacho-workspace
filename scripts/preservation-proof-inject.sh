#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# preservation-proof-inject.sh — доказательство того, что доказательство
# сохранности СПОСОБНО упасть и способно смолчать. Инъекция в обе стороны на
# синтетических репозиториях, которые скрипт заводит сам и сносит за собой.
#
# ПАРА, РАДИ КОТОРОЙ ЭТО НАПИСАНО (наблюдение 2026-09-22). Знаменатель прежней
# нормы — файлы ГОЛОВНОГО коммита (`git show --name-only --format= <голова>`).
# Полоса же несёт несколько коммитов, и существо работы обычно лежит НЕ в
# головном: замеренная полоса — три коммита, 11 путей, головной трогает 3.
# Поэтому фикстура собрана ровно этой формы:
#   c1, c2 — СУЩЕСТВО (файл `essence.txt`);
#   c3     — головной коммит, узкий хвост (`tail.md`), существа не касается.
# И каждая проба задаёт ОБА вопроса — старой формой и новой:
#   потеря в существе → СТАРАЯ форма молчит (ложное зелёное), НОВАЯ краснеет;
#   честное слияние   → молчат обе.
# Без первой половины правка знаменателя была бы переносом утверждения, а не его
# доказательством.
#
# Итог — КОММИТ СЛИЯНИЯ (вливание без схлопывания, ws#770), база — его первый
# родитель `HEAD^1`: ствол после посадки уже содержит полосу (проба H).
#
# ТРИ ИСХОДА: 0 — доказано в обе стороны; 1 — проба не дала ожидаемого; 2 — без
# предмета (нет git либо фикстура не собралась).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/.." && pwd)"
SUBJECT="$WS/scripts/preservation-proof.sh"

[ -f "$SUBJECT" ] || { echo "[VOID] $SUBJECT в дереве нет — доказывать нечего" >&2; exit 2; }
command -v git >/dev/null || { echo "[VOID] git не найден" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

probes=0
failed=0

# ЗАКОННАЯ СТАРАЯ ФОРМА, дословно из прежней редакции нормы. Держится здесь
# ради контраста: показать, что она молчит там, где работа потеряна.
old_form_is_silent() {
    local dir="$1" head="$2"
    local names out
    names="$(git -C "$dir" show --name-only --format= "$head" | sed '/^$/d')"
    # shellcheck disable=SC2086
    out="$(cd "$dir" && git diff "$head" HEAD -- $names)"
    [ -z "$out" ]
}

# fixture <имя> — полоса из трёх коммитов: существо в c1/c2, узкий хвост в c3.
fixture() {
    local d="$TMP/$1"
    git init -q "$d" >/dev/null 2>&1 || return 1
    git -C "$d" config user.email inject@example.invalid || return 1
    git -C "$d" config user.name  inject || return 1
    git -C "$d" checkout -q -b main >/dev/null 2>&1 || return 1
    # Ствол намеренно ДЛИННЫЙ: две строки давали бы конфликт слияния там, где
    # предмет пробы — НЕпересекающиеся области (у трёхстороннего слияния контекст
    # три строки, и на коротком файле верх и низ файла в него попадают вместе).
    : > "$d/essence.txt"
    for n in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'ствол: строка %s\n' "$n" >> "$d/essence.txt"; done
    printf '# хвост\n' > "$d/tail.md"
    git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -q -m "ствол" >/dev/null 2>&1 || return 1

    git -C "$d" checkout -q -b work >/dev/null 2>&1 || return 1
    printf 'полоса: существо A1\nполоса: существо A2\nполоса: существо A3\n' >> "$d/essence.txt"
    git -C "$d" commit -q -am "c1: существо, часть первая" >/dev/null 2>&1 || return 1
    printf 'полоса: существо B1\nполоса: существо B2\n' >> "$d/essence.txt"
    git -C "$d" commit -q -am "c2: существо, часть вторая" >/dev/null 2>&1 || return 1
    printf 'узкий хвост полосы\n' >> "$d/tail.md"
    git -C "$d" commit -q -am "c3: головной коммит — только хвост" >/dev/null 2>&1 || return 1
    printf '%s\n' "$d"
}

# probe <ожидаемый код> <метка> <вывод> <код> [<подстрока>…]
probe() {
    local want="$1" label="$2" out="$3" rc="$4"; shift 4
    probes=$((probes + 1))
    local ok=1 needle
    [ "$rc" = "$want" ] || ok=0
    # Сравнением, а не трубой: см. тот же довод в push-verified-inject.sh.
    for needle in "$@"; do
        [[ "$out" == *"$needle"* ]] || ok=0
    done
    if [ "$ok" = 1 ]; then
        echo "[PASS] $label (код $rc)"
    else
        failed=$((failed + 1))
        echo "[FAIL] $label — ожидался код $want, получен $rc" >&2
        printf '%s\n' "$out" | sed 's/^/    | /' >&2
    fi
}

say() { probes=$((probes + 1)); if eval "$1"; then echo "[PASS] $2"; else failed=$((failed + 1)); echo "[FAIL] $2" >&2; fi; }

# ── A. ЧЕСТНОЕ СЛИЯНИЕ: молчат обе формы ─────────────────────────────────────
d="$(fixture a)" || { echo "[VOID] фикстура не собралась — нет git либо коммит не состоялся" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
predicted="$(cd "$d" && bash "$SUBJECT" --predict main work 2>&1)"
probe 0 "A0 предсказание ДО слияния: дерево посчитано, не исполняя слияние" \
    "$predicted" "$?" "предсказанное дерево слияния" "СРОК ГОДНОСТИ"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" commit -q -m "слияние work" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 0 "A честное слияние — сохранено" "$out" "$rc" "СОХРАНЕНО"
say "old_form_is_silent '$d' '$head_sha'" "A-контроль: старая форма на честном слиянии тоже молчит — расхождения нет"
probes=$((probes + 1))
if [[ "$out" == *"равно предсказанному"* ]]; then
    echo "[PASS] A-ось1: дерево итога совпало с предсказанным ДО слияния — постусловие проверено заранее"
else
    failed=$((failed + 1)); echo "[FAIL] A-ось1: предсказанное дерево не совпало с итогом честного слияния" >&2
    printf '%s\n' "$out" | sed 's/^/    | /' >&2
fi

# ── B. ПОТЕРЯ В СУЩЕСТВЕ: старая форма молчит, новая краснеет ─────────────────
d="$(fixture b)" || { echo "[VOID] фикстура b не собралась" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
# Разрешение «в пользу ствола» по одному файлу: хвост доехал, существо — нет.
git -C "$d" checkout -q main -- essence.txt
git -C "$d" commit -q -m "слияние work (существо потеряно)" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 1 "B потеря существа — краснеет и называет путь и строку" \
    "$out" "$rc" "ПОТЕРЯ" "essence.txt" "полоса: существо A1"
say "old_form_is_silent '$d' '$head_sha'" \
    "B-контроль, РАДИ КОТОРОГО ВСЁ: СТАРАЯ форма (файлы головного коммита) на той же потере МОЛЧИТ"

# ── C. ЗАКОННЫЙ БЛИЗНЕЦ: сосед писал в тот же файл, потери нет ────────────────
d="$(fixture c)" || { echo "[VOID] фикстура c не собралась" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
# Сосед пишет в НЕПЕРЕСЕКАЮЩУЮСЯ область того же файла — в начало, тогда как
# полоса дописывала в конец. Ровно та раскладка, что наблюдалась: один файл, два
# писателя, расхождение непусто, потери нет. Писать в ТУ ЖЕ область значило бы
# ставить пробу на конфликт слияния, а это другой предмет.
# Перевод строки в конце ОБЯЗАТЕЛЕН: подстановка команды срезает хвостовой
# перевод, файл теряет его, и правка «в начале» становится правкой ещё и в
# КОНЦЕ («\ No newline at end of file») — то есть конфликтом с полосой. Проба
# молча меняла бы предмет.
printf 'соседняя полоса: своя строка 1\nсоседняя полоса: своя строка 2\n%s\n' "$(cat "$d/essence.txt")" > "$d/essence.txt.new"
mv "$d/essence.txt.new" "$d/essence.txt"
git -C "$d" commit -q -am "соседняя полоса пишет в тот же файл" >/dev/null 2>&1
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" commit -q -m "слияние work поверх соседней полосы" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 0 "C близнец: непустое расхождение от соседней полосы — НЕ находка" \
    "$out" "$rc" "СОХРАНЕНО" "это ПЕРЕПИСЬ, не вердикт"
probes=$((probes + 1))
bytes="$(printf '%s' "$out" | sed -n 's/.*по этим путям: \([0-9]*\) байт.*/\1/p')"
if [ -n "$bytes" ] && [ "$bytes" -gt 0 ]; then
    echo "[PASS] C-контроль: расхождение и правда непусто ($bytes байт) — молчание не от пустого дифа"
else
    failed=$((failed + 1)); echo "[FAIL] C-контроль: расхождение пусто — проба C ничего не доказывает" >&2
fi

# ── D. ПОТЕРЯ СНЯТИЯ: полоса сняла строку, итог её вернул ─────────────────────
d="$(fixture d)" || { echo "[VOID] фикстура d не собралась" >&2; exit 2; }
git -C "$d" checkout -q work
sed -i '/ствол: строка 2/d' "$d/essence.txt"
git -C "$d" commit -q -am "c4: полоса снимает строку ствола" >/dev/null 2>&1
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" checkout -q main -- essence.txt     # снятие не доехало
git -C "$d" commit -q -m "слияние work (снятие потеряно)" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 1 "D вторая половина оси 2: снятая полосой строка уцелела — находка" \
    "$out" "$rc" "ПОТЕРЯ" "уцелела"

# ── E. ФАЙЛА НЕТ В ИТОГЕ ВОВСЕ ───────────────────────────────────────────────
d="$(fixture e)" || { echo "[VOID] фикстура e не собралась" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" rm -q --cached essence.txt >/dev/null 2>&1
rm -f "$d/essence.txt"
git -C "$d" commit -q -m "слияние work (файл существа не доехал)" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 1 "E файл существа отсутствует в итоге — находка с путём" \
    "$out" "$rc" "ПОТЕРЯ" "essence.txt"

# ── F. ПРЕДПОСЫЛКА: пустой знаменатель — «без предмета», а не успех ───────────
d="$(fixture f)" || { echo "[VOID] фикстура f не собралась" >&2; exit 2; }
out="$(cd "$d" && bash "$SUBJECT" work work HEAD 2>&1)"; rc=$?
probe 2 "F предпосылка: полоса не трогает путей — без предмета" \
    "$out" "$rc" "БЕЗ ПРЕДМЕТА" "Пустой знаменатель"

# ── G. ПЕРЕПИСЬ НАЗЫВАЕТ ШИРИНУ ЗНАМЕНАТЕЛЯ ──────────────────────────────────
d="$(fixture g)" || { echo "[VOID] фикстура g не собралась" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" commit -q -m "слияние work" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 0 "G перепись: названы пути полосы, пути головного коммита и разница между ними" \
    "$out" "$rc" "путей 2; головной коммит трогает 1" "не смотрел бы на 1 путей полосы"

# ── H. БАЗА УЖЕ СОДЕРЖИТ ПОЛОСУ: слияние состоялось, база названа после него ──
# Вливание — коммитом слияния (#770), поэтому ствол ПОСЛЕ посадки содержит голову
# полосы, и merge-base с ней равен самой голове: знаменатель пуст. Это не «полоса
# не трогает путей», а неверно названная база — отказ обязан сказать именно это и
# назвать базу до слияния.
d="$(fixture h)" || { echo "[VOID] фикстура h не собралась" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" commit -q -m "слияние work" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" main "$head_sha" HEAD 2>&1)"; rc=$?
probe 2 "H база после слияния уже содержит полосу — без предмета с названной причиной" \
    "$out" "$rc" "БЕЗ ПРЕДМЕТА" "уже содержит голову полосы" "^1"
probes=$((probes + 1))
if [[ "$out" == *"не трогает НИ ОДНОГО пути"* ]]; then
    failed=$((failed + 1)); echo "[FAIL] H-контроль: отказ называет полосу пустой, а она трогает пути" >&2
else
    echo "[PASS] H-контроль: полоса не объявлена пустой — причина названа верно"
fi

# ── I. СТРОКИ, ПОХОЖИЕ НА ЗАГОЛОВОК ДИФА: `-- …` снята, `++ …` добавлена ───────
# Комментарий SQL, разделитель YAML и markdown начинаются с `--`; в дифе снятая
# такая строка выглядит как `--- …`, добавленная `++ …` — как `+++ …`, то есть как
# заголовок файла. Разборщик, отбрасывающий заголовки по префиксу, теряет их молча
# и объявляет сохранным то, что потеряно.
d="$(fixture i1)" || { echo "[VOID] фикстура i1 не собралась" >&2; exit 2; }
git -C "$d" checkout -q main
printf -- '-- ствол: комментарий в стиле SQL\n' >> "$d/tail.md"
git -C "$d" commit -q -am "ствол: строка-комментарий" >/dev/null 2>&1
git -C "$d" checkout -q work
git -C "$d" merge -q --no-ff main -m "полоса: слияние ствола" >/dev/null 2>&1
grep -vxF -- '-- ствол: комментарий в стиле SQL' "$d/tail.md" > "$d/tail.md.new"; mv "$d/tail.md.new" "$d/tail.md"
printf -- '++ полоса: счётчик\n' >> "$d/essence.txt"
git -C "$d" commit -q -am "c4: полоса снимает строку «-- …» и добавляет «++ …»" >/dev/null 2>&1
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
printf -- '-- ствол: комментарий в стиле SQL\n' >> "$d/tail.md"              # снятие не доехало
grep -vxF -- '++ полоса: счётчик' "$d/essence.txt" > "$d/essence.txt.new"; mv "$d/essence.txt.new" "$d/essence.txt"  # добавленное не доехало
git -C "$d" add -A >/dev/null 2>&1
git -C "$d" commit -q -m "слияние work (потеряны строки вида заголовка)" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 1 "I строки вида «--»/«++» потеряны — краснеет и называет обе" \
    "$out" "$rc" "ПОТЕРЯ" "++ полоса: счётчик" "-- ствол: комментарий в стиле SQL"

# Законный близнец: те же строки, честное слияние — молчит. Без него разборщик,
# считающий заголовки содержимым, прошёл бы пробу I, краснея на всём подряд.
d="$(fixture i2)" || { echo "[VOID] фикстура i2 не собралась" >&2; exit 2; }
git -C "$d" checkout -q main
printf -- '-- ствол: комментарий в стиле SQL\n' >> "$d/tail.md"
git -C "$d" commit -q -am "ствол: строка-комментарий" >/dev/null 2>&1
git -C "$d" checkout -q work
git -C "$d" merge -q --no-ff main -m "полоса: слияние ствола" >/dev/null 2>&1
grep -vxF -- '-- ствол: комментарий в стиле SQL' "$d/tail.md" > "$d/tail.md.new"; mv "$d/tail.md.new" "$d/tail.md"
printf -- '++ полоса: счётчик\n' >> "$d/essence.txt"
git -C "$d" commit -q -am "c4: полоса снимает строку «-- …» и добавляет «++ …»" >/dev/null 2>&1
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
base_sha="$(git -C "$d" rev-parse main)"
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" commit -q -m "слияние work" >/dev/null 2>&1
# Сосед приходит в ствол ПОСЛЕ слияния: итог уходит от предсказанного дерева, и
# вердикт выносит построчная перепись — та самая ось, где живёт разборщик.
printf 'соседняя полоса после слияния\n' > "$d/neighbour.md"
git -C "$d" add -A >/dev/null 2>&1
git -C "$d" commit -q -m "соседняя полоса после слияния" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" "$base_sha" "$head_sha" HEAD 2>&1)"; rc=$?
probe 0 "I2 близнец: те же строки, честное слияние, судит перепись — сохранено" \
    "$out" "$rc" "СОХРАНЕНО — по всем" "тождества дерева не было"

echo
echo "[CENSUS] preservation-proof-inject: проб исполнено $probes, провалов $failed; фикстур собрано 10, у каждой полоса из трёх коммитов (существо — не в головном)"
if [ "$probes" -eq 0 ]; then
    echo "[VOID] ни одной пробы не исполнено" >&2
    exit 2
fi
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] доказательство сохранности не доказано: провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] доказано в обе стороны: проб $probes, провалов 0"
