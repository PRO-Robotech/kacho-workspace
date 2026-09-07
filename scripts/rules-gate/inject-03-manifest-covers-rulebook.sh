#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-03 «манифест полон в обе стороны»
# по осям, которых общие оси инъекции НЕ КАСАЮТСЯ — по формам записи строки.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой — `sandbox`,
# `capture`, `assert_code`, `assert_says`, счётчиками `pass`/`fail`.
#
# ЗАЧЕМ ОТДЕЛЬНАЯ ЧАСТЬ, И ЭТО ИЗМЕРЕНО. До неё набор давал 50 утверждений и
# сошёлся 50 из 50 на гейте, где ЖИЛИ ПЯТЬ ДЕФЕКТОВ, четыре из них МАСКИ:
# пример строки в блоке кода и строка в HTML-комментарии зачитывались за живую;
# `\|` внутри ячейки съезжал колонками и прятал пустого держателя; неразрывный
# пробел, пустой код-спан и `TODO` проходили за названного держателя; локальная
# сортировка против байтового `comm` превращала одну настоящую находку в три,
# две из них ложные и обе на невиновное правило. Доказательство, зелёное и на
# починенном, и на дырявом, доказывает не то, что объявляет.
#
# По каждой оси — НАСТОЯЩИЙ дефект (гейт краснеет И называет координату) и рядом
# ЗАКОННЫЙ БЛИЗНЕЦ той же формы, на котором гейт обязан смолчать. Ни одна проба
# не меняет двух фактов сразу.

CH03=check-03-manifest-covers-rulebook.sh

# Жертва берётся ИЗ ДЕРЕВА, а не выписывается: набор правил растёт.
inj03_victim="$(cd "$WS/.claude/rulebook" && ls -1 ./*.md 2>/dev/null | sed 's|^\./||' \
    | grep -v '^MANIFEST' | head -1)"

# Заменить/снять/переписать строку жертвы в манифесте песочницы.
inj03_row() {   # <каталог> <имя правила> <операция> [текст]
    python3 - "$1/.claude/rulebook/MANIFEST.md" "$2" "$3" "${4-}" <<'PY'
import io, sys
path, name, op, arg = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
lines = io.open(path, encoding='utf-8').read().split('\n')
i = next(k for k, l in enumerate(lines) if l.startswith('| `%s`' % name))
row = lines[i]
if op == 'drop':
    lines[i:i+1] = []
elif op == 'fence':                      # снять строку и оставить её же ПРИМЕРОМ в блоке кода
    lines[i:i+1] = []
    lines += ['', '## Форма строки', '', '```', row, '```']
elif op == 'comment':                    # снять строку, закомментировав её
    lines[i:i+1] = ['<!-- снято на время переезда', row, '-->']
elif op == 'hold':                       # подменить ячейку держателя
    c = row.split('|'); c[3] = arg; lines[i] = '|'.join(c)
elif op == 'hold_named':                 # ячейка, пустая для ЧЕЛОВЕКА, но не для байтов
    cell = {'nbsp': ' \u00a0 ', 'span': ' `` ', 'todo': ' TODO ', 'dash': ' `\u2014` '}[arg]
    c = row.split('|'); c[3] = cell; lines[i] = '|'.join(c)
elif op == 'escaped_pipe':               # держатель пуст, в действии — законная `\|`
    lines[i] = '| `%s` | правка `x/**` `grep -E \'a\\|b\'` |  |' % name
io.open(path, 'w', encoding='utf-8').write('\n'.join(lines))
PY
}

echo "== ось G: ПРИМЕР строки — не строка (блок кода) =="
d="$(sandbox c03_fence)"
inj03_row "$d" "$inj03_victim" fence
capture "$d" "$CH03"
assert_code 1 "строка снята, имя осталось лишь примером в блоке кода — находка"
assert_says "$inj03_victim" "находка называет координату правила, а не «строка есть»"

echo "== ось G′: БЛИЗНЕЦ — живая строка на месте, пример рядом =="
d="$(sandbox c03_fence_twin)"
python3 - "$d/.claude/rulebook/MANIFEST.md" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
io.open(p, 'w', encoding='utf-8').write(
    s + '\n## Форма строки\n\n```\n| `primer.md` | действие | держатель |\n```\n')
PY
capture "$d" "$CH03"
assert_code 0 "пример в блоке кода сам по себе находкой НЕ является"

echo "== ось H: закомментированная строка объявлена снятой =="
d="$(sandbox c03_comment)"
inj03_row "$d" "$inj03_victim" comment
capture "$d" "$CH03"
assert_code 1 "строка в HTML-комментарии не покрывает правило"
assert_says "$inj03_victim" "находка называет координату правила"

echo "== ось H′: БЛИЗНЕЦ — комментарий рядом с живой таблицей =="
d="$(sandbox c03_comment_twin)"
printf '\n<!-- перечень выше выводится из дерева -->\n' >> "$d/.claude/rulebook/MANIFEST.md"
capture "$d" "$CH03"
assert_code 0 "комментарий, не прячущий строк, молчания не отменяет"

echo "== ось I: пустой держатель при законной \\| в соседней ячейке =="
d="$(sandbox c03_escpipe)"
inj03_row "$d" "$inj03_victim" escaped_pipe
capture "$d" "$CH03"
assert_code 1 "экранированная труба не скрывает пустого держателя"
assert_says "чем соблюдение держится" "находка называет ИМЕННО пустого держателя"

echo "== ось I′: БЛИЗНЕЦ — \\| в ячейке при ПОЛНОЙ строке =="
d="$(sandbox c03_escpipe_twin)"
inj03_row "$d" "$inj03_victim" hold " гейт \`grep -E 'a\\|b'\` "
capture "$d" "$CH03"
assert_code 0 "труба внутри держателя — содержимое ячейки, а не её граница"

echo "== ось J: держатель, пустой ДЛЯ ЧЕЛОВЕКА =="
# Форма ИМЕНУЕТСЯ, а ячейка собирается внутри python: неразрывный пробел,
# пронесённый через слово оболочки, съедается разбиением по пробелу — и проба
# начинает подставлять ПУСТУЮ ячейку, то есть проверять уже покрытый случай под
# чужим заголовком. Поймано на себе: такая проба была зелена на дофиксовом гейте.
for tag in nbsp span todo dash; do
    d="$(sandbox "c03_hold_$tag")"
    inj03_row "$d" "$inj03_victim" hold_named "$tag"
    capture "$d" "$CH03"
    assert_code 1 "держатель вида «$tag» — пустота, а не ответ"
    assert_says "чем соблюдение держится" "находка вида «$tag» называет ИМЕННО держателя"
done

echo "== ось J′: БЛИЗНЕЦ — «держится вниманием» словами =="
d="$(sandbox c03_hold_words)"
inj03_row "$d" "$inj03_victim" hold " держится вниманием ревьюера волны "
capture "$d" "$CH03"
assert_code 0 "названный вслух отсутствующий механизм — законный ответ (§11)"

echo "== ось K: сортировка не плодит ложных обвинений =="
# Одна НАСТОЯЩАЯ находка (`rag.md` без строки) рядом с `README.md`, который есть
# и назван. На локальной сортировке против байтового `comm` невиновный README.md
# получал ДВА взаимно противоречивых обвинения сразу.
d="$(sandbox c03_sort)"
printf '# r\n' > "$d/.claude/rulebook/rag.md"
printf '# r\n' > "$d/.claude/rulebook/README.md"
git -C "$d" add -A >/dev/null 2>&1
python3 - "$d/.claude/rulebook/MANIFEST.md" <<'PY'
import io, sys
p = sys.argv[1]
lines = io.open(p, encoding='utf-8').read().split('\n')
i = next(k for k, l in enumerate(lines) if l.startswith('| `'))
lines.insert(i + 2, '| `README.md` | всегда | гейт readme |')
io.open(p, 'w', encoding='utf-8').write('\n'.join(lines))
PY
capture "$d" "$CH03"
assert_code 1 "правило без строки — находка"
assert_says "rag.md" "названо ВИНОВНОЕ правило"
if printf '%s\n' "$OUT" | grep -q 'README\.md'; then
    echo "  [FAIL] невиновное README.md не обвиняется" >&2
    printf '%s\n' "$OUT" | sed 's/^/         | /' >&2
    fail=$((fail + 1))
else
    echo "  [OK]   невиновное README.md не обвиняется"; pass=$((pass + 1))
fi
if printf '%s\n' "$OUT" | grep -q 'not in sorted order'; then
    echo "  [FAIL] слияние не жалуется на порядок" >&2; fail=$((fail + 1))
else
    echo "  [OK]   слияние не жалуется на порядок"; pass=$((pass + 1))
fi
