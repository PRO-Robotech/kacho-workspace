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

# Настройка git машины сюда не доходит: цвет, переименования и экранирование
# путей, выставленные личным ~/.gitconfig, меняли бы то, что читает предмет, и
# проба судила бы машину. Там, где настройка и есть предмет (E4e, E4f), она
# ставится в самой фикстуре.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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

# fixture <имя> — полоса из трёх коммитов: существо в c1/c2, узкий хвост в c3
# (пробы d, i1, i2 дописывают четвёртый; перепись в конце считает их сама).
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

# ── E4. ФОРМА ВЫВОДА git НЕ МЕНЯЕТ ВЕРДИКТА ──────────────────────────────────
#
# Предмет читает `git diff` — и то, что он печатает, зависит от настройки клона:
# переименование склеивает два пути в один, цвет вставляет управляющие
# последовательности в каждую строку, `core.quotePath` экранирует путь не из
# ASCII. Каждая из этих форм прежде давала «СОХРАНЕНО» на потере.
merge_lose() {  # <репо> <путь, разрешаемый в пользу ствола> — слияние work в main
    git -C "$1" checkout -q main
    git -C "$1" merge -q --no-ff --no-commit work >/dev/null 2>&1
    git -C "$1" checkout -q main -- "$2"
    git -C "$1" commit -q -m "слияние work ($2 потерян)" >/dev/null 2>&1
}
merge_clean() {
    git -C "$1" checkout -q main
    git -C "$1" merge -q --no-ff --no-edit work >/dev/null 2>&1
}

# Чистое переименование: файл, которого полоса не правила, переехал целиком —
# `git diff --name-only` по умолчанию называет только НОВЫЙ путь, и исходный
# выпадает из знаменателя.
rename_fixture() {  # <имя> — печатает путь; work: c1 правит a.txt, c2 old.txt → renamed.txt
    local d="$TMP/$1"
    git init -q -b main "$d" || return 1
    git -C "$d" config user.email inject@example.invalid; git -C "$d" config user.name inject
    for n in 1 2 3 4 5 6 7 8 9 10; do printf 'старый файл: строка %s\n' "$n" >> "$d/old.txt"; done
    printf 'ствол\n' > "$d/a.txt"
    git -C "$d" add -A && git -C "$d" commit -q -m "ствол" || return 1
    git -C "$d" checkout -q -b work
    printf 'полоса: правка a\n' >> "$d/a.txt"; git -C "$d" commit -qam "c1: правка a" || return 1
    git -C "$d" mv old.txt renamed.txt; git -C "$d" commit -q -m "c2: переименование old → renamed" || return 1
    printf '%s\n' "$d"
}
d="$(rename_fixture e4d)" || { echo "[VOID] фикстура e4d не собралась" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
merge_clean "$d"
git -C "$d" checkout -q HEAD^1 -- old.txt; git -C "$d" commit -q --amend --no-edit >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 1 "E4d переименование: исходный путь в знаменателе, снятый полосой old.txt вернулся — ПОТЕРЯ" \
    "$out" "$rc" "ПОТЕРЯ" "old.txt"
d="$(rename_fixture e4d2)" || { echo "[VOID] фикстура e4d2 не собралась" >&2; exit 2; }
head_sha="$(git -C "$d" rev-parse work)"
merge_clean "$d"
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 0 "E4d близнец: переименование честно влито — сохранено" "$out" "$rc" "СОХРАНЕНО"

for knob in color.diff color.ui; do
    d="$(fixture "e4e-$knob")" || { echo "[VOID] фикстура e4e не собралась" >&2; exit 2; }
    git -C "$d" config "$knob" always
    head_sha="$(git -C "$d" rev-parse work)"
    merge_lose "$d" essence.txt
    out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
    probe 1 "E4e1 $knob=always: цвет не съедает перепись — потеря существа краснеет" \
        "$out" "$rc" "ПОТЕРЯ" "полоса: существо A1"
done

d="$(fixture e4f)" || { echo "[VOID] фикстура e4f не собралась" >&2; exit 2; }
git -C "$d" checkout -q work
printf 'существо в файле с именем не из ASCII\n' > "$d/ведомость.txt"
git -C "$d" add -A; git -C "$d" commit -q -m "c4: файл не-ASCII" >/dev/null 2>&1
head_sha="$(git -C "$d" rev-parse work)"
git -C "$d" checkout -q main
git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
git -C "$d" rm -q --cached "ведомость.txt"; rm -f "$d/ведомость.txt"
git -C "$d" commit -q -m "слияние work (файл не-ASCII потерян)" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" HEAD^1 "$head_sha" HEAD 2>&1)"; rc=$?
probe 1 "E4f путь не из ASCII (core.quotePath): пропавший файл полосы — ПОТЕРЯ, а не пропуск" \
    "$out" "$rc" "ПОТЕРЯ" "ведомость.txt"

# ── ФОРМЫ ЗАПИСИ РАБОТЫ: не только строки текста ────────────────────────────
#
# Работа полосы записывается в дереве не одними строками: двоичное содержимое,
# бит исполнения, цель символьной ссылки, указатель подмодуля. Перепись строк
# видит лишь текст, и потеря любой другой формы давала «СОХРАНЕНО — по всем N
# путям» (находки приёмки: двоичный файл и chmod +x — код 0). Каждая проба
# роняет ОДНУ форму, остальные доезжают; близнец — честное слияние, после
# которого сосед пишет в ствол (итог уходит от предсказанного дерева, и вердикт
# выносит ось 2 — та, где живёт распознаватель).
forms_fixture() {  # <имя> — печатает путь; ствол сдвинут соседом, полоса — 3 коммита
    local d="$TMP/$1"
    git init -q -b main "$d" || return 1
    git -C "$d" config user.email inject@example.invalid; git -C "$d" config user.name inject
    printf 'двоичное\000старое\000\001\002' > "$d/bin.dat"
    printf '#!/usr/bin/env bash\necho hook\n' > "$d/hook.sh"
    ln -s target-a "$d/link"
    : > "$d/d.txt"
    for n in 1 2 3 4 5 6; do printf 'строка %s\n' "$n" >> "$d/d.txt"; done
    printf 'повтор\n' >> "$d/d.txt"
    for n in 7 8 9 10 11 12; do printf 'строка %s\n' "$n" >> "$d/d.txt"; done
    printf 'повтор\n' >> "$d/d.txt"
    git -C "$d" add -A && git -C "$d" commit -q -m "ствол" || return 1
    base_commit="$(git -C "$d" rev-parse HEAD)"
    # Подмодуль без клона: пустой каталог — «не заведён», и `add` его не снимает.
    mkdir -p "$d/sub"
    git -C "$d" update-index --add --cacheinfo "160000,$base_commit,sub" && git -C "$d" commit -q -m "ствол: подмодуль" || return 1
    git -C "$d" checkout -q -b work
    printf 'двоичное\000НОВОЕ полосы\000\003\004' > "$d/bin.dat"
    ln -sfn target-b "$d/link"
    git -C "$d" add bin.dat link && git -C "$d" commit -q -m "c1: двоичное и цель ссылки" || return 1
    chmod +x "$d/hook.sh"
    git -C "$d" update-index --chmod=+x hook.sh && git -C "$d" commit -q -m "c2: только бит исполнения" || return 1
    git -C "$d" update-index --cacheinfo "160000,$(git -C "$d" rev-parse HEAD~1),sub"
    sed -i '$d' "$d/d.txt"     # снят ПОСЛЕДНИЙ из двух повторов
    git -C "$d" add d.txt && git -C "$d" commit -q -m "c3: подмодуль сдвинут, один повтор снят" || return 1
    git -C "$d" checkout -q main
    printf 'соседняя полоса\n' > "$d/neighbour.md"
    git -C "$d" add neighbour.md && git -C "$d" commit -q -m "соседняя полоса в стволе" || return 1
    printf '%s\n' "$d"
}
forms_lose() {  # <имя> <что уронить: bin|mode|link|sub|dup> — печатает вывод, код в rc
    local d h b
    d="$(forms_fixture "$1")" || { echo "[VOID] фикстура $1 не собралась" >&2; exit 2; }
    h="$(git -C "$d" rev-parse work)"; b="$(git -C "$d" rev-parse main)"
    git -C "$d" merge -q --no-ff --no-commit work >/dev/null 2>&1
    case "$2" in
        bin)  git -C "$d" checkout -q main -- bin.dat ;;
        mode) git -C "$d" update-index --chmod=-x hook.sh; chmod -x "$d/hook.sh" ;;
        link) git -C "$d" checkout -q main -- link ;;
        sub)  git -C "$d" update-index --cacheinfo "160000,$(git -C "$d" rev-parse main:sub),sub" ;;
        dup)  git -C "$d" checkout -q main -- d.txt ;;
    esac
    git -C "$d" commit -q -m "слияние work ($2 потерян)" >/dev/null 2>&1
    out="$(cd "$d" && bash "$SUBJECT" "$b" "$h" HEAD 2>&1)"; rc=$?
}
forms_lose j-bin bin
probe 1 "J двоичное содержимое полосы потеряно — ПОТЕРЯ с путём (строк в нём нет)" "$out" "$rc" "ПОТЕРЯ" "bin.dat" "двоичн"
forms_lose j-mode mode
probe 1 "K бит исполнения, поставленный полосой, снят слиянием — ПОТЕРЯ «режим»" "$out" "$rc" "ПОТЕРЯ" "hook.sh" "режим"
forms_lose j-link link
probe 1 "L цель символьной ссылки полосы потеряна — ПОТЕРЯ" "$out" "$rc" "ПОТЕРЯ" "link"
forms_lose j-sub sub
probe 1 "M указатель подмодуля, сдвинутый полосой, откачен — ПОТЕРЯ" "$out" "$rc" "ПОТЕРЯ" "sub" "подмодул"
forms_lose j-dup dup
probe 1 "N полоса сняла один из двух повторов, слияние его вернуло — снятая уцелела" "$out" "$rc" "ПОТЕРЯ" "уцелела" "повтор"

d="$(forms_fixture j-twin)" || { echo "[VOID] фикстура j-twin не собралась" >&2; exit 2; }
h="$(git -C "$d" rev-parse work)"; b="$(git -C "$d" rev-parse main)"
git -C "$d" merge -q --no-ff --no-edit work >/dev/null 2>&1
printf 'сосед после слияния\n' >> "$d/neighbour.md"; git -C "$d" commit -qam "сосед после слияния" >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" "$b" "$h" HEAD 2>&1)"; rc=$?
probe 0 "J–N близнец: все формы доехали, судит ось 2 — сохранено, перепись называет каждую форму" \
    "$out" "$rc" "СОХРАНЕНО — по всем" "тождества дерева не было" "текстовых 2" "двоичных 1" "подмодулей 1" "режим задан или сменён полосой 1" "не распознано 0"

# Счёт по числу вхождений — в обе стороны, и с поправкой на соседа: сосед,
# добавивший ТУ ЖЕ строку, что полоса сняла один раз из двух, — не находка;
# сосед, снявший строку, которую полоса добавила, — тоже.
d="$(forms_fixture j-dup2)" || { echo "[VOID] фикстура j-dup2 не собралась" >&2; exit 2; }
{ printf 'повтор\n'; cat "$d/d.txt"; } > "$d/d.new"; mv "$d/d.new" "$d/d.txt"
git -C "$d" commit -qam "сосед добавил такой же повтор в начало" >/dev/null 2>&1
h="$(git -C "$d" rev-parse work)"; b="$(git -C "$d" rev-parse main)"
git -C "$d" merge -q --no-ff --no-edit work >/dev/null 2>&1
out="$(cd "$d" && bash "$SUBJECT" "$b" "$h" HEAD 2>&1)"; rc=$?
probe 0 "N близнец: сосед добавил такую же строку, полоса сняла свою — не «уцелела»" "$out" "$rc" "СОХРАНЕНО"

echo
# Перепись фикстур ВЫВОДИТСЯ: сколько собрано и сколько коммитов полосы в каждой —
# у части фикстур полоса дополняется четвёртым коммитом по ходу пробы.
lanes="$(for g in $(find "$TMP" -mindepth 2 -maxdepth 2 -name .git -type d); do
    r="${g%/.git}"; root="$(git -C "$r" rev-list --max-parents=0 work 2>/dev/null | head -1)"
    [ -n "$root" ] && git -C "$r" rev-list --count work --not "$root"
done | sort -n | uniq -c | awk '{printf "%s%s — у %s", (NR > 1 ? ", " : ""), $2, $1}')"
echo "[CENSUS] preservation-proof-inject: проб исполнено $probes, провалов $failed; фикстур собрано $(find "$TMP" -mindepth 2 -maxdepth 2 -name .git -type d | wc -l); коммитов полосы: ${lanes:-—}"
if [ "$probes" -eq 0 ]; then
    echo "[VOID] ни одной пробы не исполнено" >&2
    exit 2
fi
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] доказательство сохранности не доказано: провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] доказано в обе стороны: проб $probes, провалов 0"
