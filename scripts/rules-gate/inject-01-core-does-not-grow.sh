#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-01 «ядро не растёт».
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой — `sandbox`,
# `capture`, `assert_code`, `assert_says`, счётчиками `pass`/`fail`. Отдельным
# файлом, а не секцией общего: три полосы, писавшие один файл в один час, уже
# затёрли друг друга дважды; часть переживает чужую правку общего входа.
#
# Здесь по каждой оси вносится НАСТОЯЩИЙ дефект — гейт обязан покраснеть И
# НАЗВАТЬ КООРДИНАТУ, — а рядом ставится ЗАКОННЫЙ БЛИЗНЕЦ той же формы, на
# котором гейт обязан смолчать. Без близнеца гейт ловил бы форму, а не существо
# (`rulebook/testing.md` §«Гейт на класс», п.2).
#
# Ни одной пробы, меняющей два факта, кроме одной — «пятое правило заведено И
# объявлено». Это один поступок, и её предмет ровно в том, что он законен.

# Правка §«Ядро» манифеста песочницы. Фикстура трогает ПЕРВЫЙ АБЗАЦ секции — то
# самое, что гейт считает объявлением. Анкер по прозе («локальный индекс»)
# привязал бы пробу к тексту, который вправе меняться, и она краснела бы от
# чужой правки.
inj01_manifest_edit() {   # <каталог песочницы> <операция>
    python3 - "$1/.claude/rulebook/MANIFEST.md" "$2" <<'PY'
import io, sys
path, op = sys.argv[1], sys.argv[2]
lines = io.open(path, encoding='utf-8').read().split('\n')
i = next(k for k, l in enumerate(lines) if l.startswith('## ') and 'Ядро' in l)
j = i + 1
while j < len(lines) and not lines[j].strip():
    j += 1
k = j
while k < len(lines) and lines[k].strip():
    k += 1
if op == 'declare-fifth':
    lines[k - 1] = lines[k - 1].rstrip() + ' · `05-newcomer.md` (пятое правило ядра)'
elif op == 'gut':
    del lines[j:k]
elif op == 'rename-writing':
    for n in range(j, k):
        lines[n] = lines[n].replace('`writing.md`', '`writing-local.md`')
elif op == 'prose-names-md':
    lines[k:k] = ['', 'Раскладку объявляет `MANIFEST.md`; правило `testing.md` живёт '
                      'в `.claude/rulebook/`, а не здесь.']
else:
    raise SystemExit('unknown op ' + op)
io.open(path, 'w', encoding='utf-8').write('\n'.join(lines))
PY
}

C01="check-01-core-does-not-grow.sh"

echo "-- ось: ядро выросло --"
d01="$(sandbox c01_extra)"
cp "$d01/.claude/rulebook/testing.md" "$d01/.claude/rules/testing.md"
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: лишний файл в .claude/rules/"
assert_says "ЛИШНИЙ в ядре: .claude/rules/testing.md" "  ...и координата названа"
assert_says "прочитано файлов ядра 4" "  ...и перепись печатается НА НАХОДКЕ: «ноль находок» отличимо от «ноль прочитанного»"

echo "-- ось: правило ядра пропало --"
d01="$(sandbox c01_missing)"
rm -f "$d01/.claude/rules/writing.md"
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: объявленного правила нет в каталоге"
assert_says "НЕДОСТАЁТ в ядре: .claude/rules/writing.md" "  ...и координата названа"

echo "-- ось: плоское ядро обросло подкаталогом --"
d01="$(sandbox c01_nested)"
mkdir -p "$d01/.claude/rules/legacy"
printf 'старое правило\n' > "$d01/.claude/rules/legacy/old.md"
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: подкаталог в ядре"
assert_says "ПОДКАТАЛОГ в ядре: .claude/rules/legacy" "  ...и координата названа"

echo "-- ось: .gitignore не выводит файл ядра из-под наблюдения --"
# Один факт против пробы «лишний файл» выше — добавлена строка игнора. Ядро
# читает загрузчик, а он читает диск: файл, невидимый в свежем клоне, означает,
# что ядро различается между машинами, и молчать здесь нельзя.
d01="$(sandbox c01_hidden)"
cp "$d01/.claude/rulebook/testing.md" "$d01/.claude/rules/testing.md"
printf '.claude/rules/testing.md\n' >> "$d01/.gitignore"
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: файл ядра скрыт .gitignore — из-под наблюдения не уходит"
assert_says "СКРЫТ ОТ GIT: .claude/rules/testing.md" "  ...и координата названа"

echo "-- ось: выпотрошенное объявление — НАХОДКА, а не VOID (антимаска) --"
# Отдай гейт здесь VOID, и пустая §«Ядро» стала бы способом погасить его, не
# роняя отправку: код 2 её не блокирует. Манифест на месте — предмет есть.
d01="$(sandbox c01_gutted)"
inj01_manifest_edit "$d01" gut
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: §«Ядро» не объявляет ни одного правила"
assert_says "объявление пусто" "  ...и названо, что объявление пусто"

echo "-- ось: пустой обход — ОТКАЗ, а не «находок 0» --"
d01="$(sandbox c01_empty)"
rm -f "$d01"/.claude/rules/*
capture "$d01" "$C01"
assert_code 1 "файлов ядра не прочитано ни одного ⇒ код 1"
assert_says "обход беспредметен" "  ...и сказано, что обход беспредметен"
assert_says "прочитано файлов ядра 0" "  ...и перепись называет ноль прочитанного"

echo "-- ось: предмета нет — код 2, и это НЕ успех --"
d01="$(sandbox c01_nodir)"
rm -rf "$d01/.claude/rules"
capture "$d01" "$C01"
assert_code 2 "каталога ядра нет вовсе — раскладки в этом дереве не существует"

d01="$(sandbox c01_noman)"
rm -f "$d01/.claude/rulebook/MANIFEST.md"
capture "$d01" "$C01"
assert_code 2 "манифеста нет — источника истины о составе ядра не существует"

echo "-- законные близнецы: гейт обязан смолчать --"
# Та же форма, что у дефекта «лишний файл» — файл появился, — но в законном месте.
d01="$(sandbox c01_twin_rulebook)"
printf '# новое модульное правило\n' > "$d01/.claude/rulebook/observability.md"
capture "$d01" "$C01"
assert_code 0 "БЛИЗНЕЦ: правило заведено в rulebook, а не в ядре"

d01="$(sandbox c01_twin_content)"
printf '\nдописанный абзац\n' >> "$d01/.claude/rules/writing.md"
capture "$d01" "$C01"
assert_code 0 "БЛИЗНЕЦ: правка СОДЕРЖИМОГО правила ядра — гейт судит набор, а не текст"

# Ключевой близнец: источник истины — манифест, а не выписанное в скрипт число.
# Рост ядра, ОБЪЯВЛЕННЫЙ человеком, законен; молчаливый — нет.
d01="$(sandbox c01_twin_declared)"
printf '# пятое правило ядра\n' > "$d01/.claude/rules/05-newcomer.md"
inj01_manifest_edit "$d01" declare-fifth
capture "$d01" "$C01"
assert_code 0 "БЛИЗНЕЦ: пятое правило ядра ВМЕСТЕ со своим объявлением"

d01="$(sandbox c01_twin_rename)"
mv "$d01/.claude/rules/writing.md" "$d01/.claude/rules/writing-local.md"
inj01_manifest_edit "$d01" rename-writing
capture "$d01" "$C01"
assert_code 0 "БЛИЗНЕЦ: переименование, доехавшее и до манифеста"

# Проза секции вправе называть координаты `.md`; объявление — первый абзац.
# Читай гейт всю секцию, эта правка стала бы ложной находкой на законном тексте.
d01="$(sandbox c01_twin_prose)"
inj01_manifest_edit "$d01" prose-names-md
capture "$d01" "$C01"
assert_code 0 "БЛИЗНЕЦ: проза §«Ядро» называет MANIFEST.md и testing.md"

# ── ось: СИМВОЛЬНАЯ ССЫЛКА — тоже запись каталога ────────────────────────────
#
# Заведена 2026-09-07 по находке противника. До неё набор собирался через
# `find -type f`, а `-type f` ссылок не видит ВОВСЕ: живая ссылка на правило
# rulebook лежала в ядре, читалась, тянула 1326 строк в окно — и гейт печатал
# «прочитано файлов ядра 3 … лишних 0», код 0. Молчание, а не красное: ровно
# класс `rulebook/testing.md` §«Гейт на класс», п.7.
#
# ПЕРВАЯ проба — ОДНО-ФАКТНАЯ (там же, п.2в). Она не заводит новой записи, а
# снимает у существующей ТОЛЬКО новое свойство: имя `writing.md` объявлено и на месте,
# набор по-прежнему сходится с манифестом, изменился один факт — запись перестала
# быть обычным файлом. Значит краснеет ровно новая ось, и её красное не одолжено
# у соседней. Проба «завести ещё одну запись» такого не доказывает: новая запись
# нарушает и старое требование тоже.

# Утверждение об ОТСУТСТВИИ строки. Помощник живёт в ЧАСТИ, а не в общем входе:
# общий вход за час переписывали дважды, и добавленный туда помощник уехал бы с
# чужой правкой (см. шапку файла).
inj01_assert_lacks() {   # <подстрока> <утверждение>
    if printf '%s\n' "$OUT" | grep -qF -- "$1"; then
        echo "  [FAIL] $2 — в вердикте есть лишнее «$1»" >&2
        printf '%s\n' "$OUT" | sed 's/^/         | /' >&2
        fail=$((fail + 1))
    else
        echo "  [OK]   $2"; pass=$((pass + 1))
    fi
}

# Вердикт состоит ТОЛЬКО из строк гейта. Утверждение по форме строки, а не по
# тексту жалобы: текст шелла зависит от локали и на другой машине не совпал бы.
inj01_assert_only_gate_lines() {   # <утверждение>
    local stray
    stray="$(printf '%s\n' "$OUT" | grep -vE '^\[(PASS|FAIL|VOID|CENSUS)\] ' | grep -v '^$')"
    if [ -n "$stray" ]; then
        echo "  [FAIL] $1 — в вердикте посторонние строки" >&2
        printf '%s\n' "$stray" | sed 's/^/         | /' >&2
        fail=$((fail + 1))
    else
        echo "  [OK]   $1"; pass=$((pass + 1))
    fi
}

d01="$(sandbox c01_link_declared)"
rm -f "$d01/.claude/rules/writing.md"
ln -s ../rulebook/vault.md "$d01/.claude/rules/writing.md"
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: объявленное правило ядра подменено ссылкой (снят ОДИН факт)"
assert_says "ССЫЛКА В ЯДРЕ: .claude/rules/writing.md" "  ...и координата названа"
inj01_assert_lacks "НЕДОСТАЁТ" "  ...и диагноз ОДИН: не «правило пропало» — оно читается"

d01="$(sandbox c01_link_extra)"
ln -s ../rulebook/testing.md "$d01/.claude/rules/testing.md"
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: лишнее правило внесено ССЫЛКОЙ — форма, на которой гейт молчал"
assert_says "ССЫЛКА В ЯДРЕ: .claude/rules/testing.md" "  ...и координата названа"
assert_says "прочитано файлов ядра 4" "  ...и перепись считает ссылку записью каталога"

d01="$(sandbox c01_link_dangling)"
ln -s ../rulebook/no-such-rule.md "$d01/.claude/rules/ghost.md"
capture "$d01" "$C01"
assert_code 1 "ДЕФЕКТ: битая ссылка в ядре"
assert_says "цель НЕ резолвится" "  ...и сказано, что правило не читается вовсе"
inj01_assert_only_gate_lines "  ...и вердикт не оброс сырой жалобой шелла"

# Та же форма, что у дефекта, — ссылка появилась, — но в законном месте: rulebook
# читается файлом по требованию, ссылка там окна волны не трогает.
d01="$(sandbox c01_twin_link_rulebook)"
ln -s ./testing.md "$d01/.claude/rulebook/testing-alias.md"
capture "$d01" "$C01"
assert_code 0 "БЛИЗНЕЦ: ссылка заведена в rulebook, а не в ядре"
