#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-16 «объём таблицы манифеста,
# объявленный в id нормы `mf-registry-table-<N>-rows`, равен числу её строк»
# (ws#710 п.3) — дефект по каждой оси, законный близнец той же формы и отказ на
# отсутствии предмета.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.
#
# shellcheck disable=SC2154
# SC2154: `pass`, `fail`, `OUT`, `RC` задаёт подключающий `inject.sh`.

# ── СТРАЖ ПОДКЛЮЧЕНИЯ ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Она подключается из scripts/rules-gate/inject.sh и пользуется его оснасткой;" >&2
    echo "       самостоятельно писала бы в рабочее дерево. Запускать:" >&2
    echo "       bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i16_fn in sandbox capture assert_code assert_says assert_lacks assert_fixture_changed sandbox_digest; do
    command -v "$_i16_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i16_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i16_fn

C16=check-16-manifest-volume-declared.sh
i16_before=$((pass + fail))

# i16_edit <песочница> <операция> [аргумент] — правка MANIFEST.md песочницы.
# Всякая операция обязана что-то изменить: замена по подстроке вырождается в no-op
# молча, и утверждение относилось бы к нетронутому дереву.
i16_edit() {
    python3 - "$1/.claude/rules/MANIFEST.md" "$2" "${3-}" <<'PY'
import io, re, sys
path, op, arg = sys.argv[1], sys.argv[2], sys.argv[3]
before = io.open(path, encoding='utf-8').read()
lines = before.split('\n')
VOL = re.compile(r'^mf-registry-table-(\d+)-rows ')
vol = [k for k, l in enumerate(lines) if VOL.match(l)]
rows = [k for k, l in enumerate(lines)
        if re.match(r'^\|\s*`?[^|`]+?\.md`?\s*\|', l)]
if not vol or not rows:
    raise SystemExit('ФИКСТУРА ВАКУУМНА: в MANIFEST.md нет нормы объёма либо строк таблицы')


def bump(delta):
    k = vol[0]
    n = int(VOL.match(lines[k]).group(1))
    lines[k] = VOL.sub('mf-registry-table-%d-rows ' % (n + delta), lines[k], count=1)


def add_row(name):
    lines.insert(rows[-1] + 1,
                 '| `%s` | проба инъекции | гейт-свидетель | `tooling-maintainer` |' % name)


if op == 'row':            # строка таблицы без правки объёма — дефект
    add_row(arg)
elif op == 'row+vol':      # строка И объём одним изменением — законный рост
    bump(1)
    add_row(arg)
elif op == 'drop-row':     # строка снята, объём не поправлен — дефект
    del lines[rows[-1]]
elif op == 'drop-row+vol':  # строка снята вместе с объёмом — законно
    bump(-1)
    del lines[rows[-1]]
elif op == 'vol':          # объём назван другим числом — дефект
    k = vol[0]
    lines[k] = VOL.sub('mf-registry-table-%s-rows ' % arg, lines[k], count=1)
elif op == 'vol-drop':     # норма объёма снята — дефект
    del lines[vol[0]]
elif op == 'vol-twice':    # норма объёма объявлена дважды — дефект
    lines.insert(vol[0] + 1, lines[vol[0]])
elif op == 'prose':        # проза называет id с другим числом не с начала строки — законно
    lines += ['', 'Прежде норма звалась `mf-registry-table-30-rows` (ключ описи 2026-09-19).']
else:
    raise SystemExit('unknown op ' + op)
after = '\n'.join(lines)
if after == before:
    raise SystemExit('ФИКСТУРА ВАКУУМНА: операция «%s» не изменила MANIFEST.md' % op)
io.open(path, 'w', encoding='utf-8').write(after)
PY
}

# ── контроль: нетронутая копия — молчит, число названо ───────────────────────
d="$(sandbox i16_clean)"
capture "$d" "$C16"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — объявлено столько, сколько строк"
assert_says "строк таблицы разобрано" "  ...и перепись называет число строк"

# ── ось: строка заведена, объём в id не поправлен ────────────────────────────
d="$(sandbox i16_row)"
i16_edit "$d" row zz-inj16-newcomer.md
capture "$d" "$C16"
assert_code 1 "ДЕФЕКТ: строка таблицы добавлена, объём в id прежний — краснеет"
assert_says "ОБЪЁМ ТАБЛИЦЫ РАЗОШЁЛСЯ" "  ...и называет, что разошлось"
d="$(sandbox i16_row_twin)"; b="$(sandbox_digest "$d")"
i16_edit "$d" row+vol zz-inj16-newcomer.md
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: строка и объём одним изменением"
capture "$d" "$C16"
assert_code 0 "БЛИЗНЕЦ: строка добавлена И объём в id поправлен — молчит"

# ── ось: строка снята, объём не поправлен ────────────────────────────────────
d="$(sandbox i16_drop)"
i16_edit "$d" drop-row
capture "$d" "$C16"
assert_code 1 "ДЕФЕКТ: строка снята, объём в id прежний — краснеет"
d="$(sandbox i16_drop_twin)"; b="$(sandbox_digest "$d")"
i16_edit "$d" drop-row+vol
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: строка снята вместе с объёмом"
capture "$d" "$C16"
assert_code 0 "БЛИЗНЕЦ: строка снята И объём поправлен — молчит"

# ── ось: число в id не то — ровно дефект ws#710 (30 при 18) ──────────────────
d="$(sandbox i16_vol)"
i16_edit "$d" vol 999
capture "$d" "$C16"
assert_code 1 "ДЕФЕКТ: id нормы называет 999 при неизменной таблице — краснеет"
assert_says "mf-registry-table-999-rows" "  ...и называет объявленное число"

# ── ось: норма снята либо раздвоена — находка, а не «предмета нет» ───────────
d="$(sandbox i16_vol_drop)"
i16_edit "$d" vol-drop
capture "$d" "$C16"
assert_code 1 "ДЕФЕКТ: норма объёма снята при живой таблице — находка"
assert_says "ОБЪЁМ ТАБЛИЦЫ НЕ ОБЪЯВЛЕН" "  ...и называет, что снято"
d="$(sandbox i16_vol_twice)"
i16_edit "$d" vol-twice
capture "$d" "$C16"
assert_code 1 "ДЕФЕКТ: норма объёма объявлена дважды — находка"
assert_lacks "ОБЪЁМ ТАБЛИЦЫ РАЗОШЁЛСЯ" "  ...и диагноз ОДИН: раздвоение, а не расхождение числа"

# ── близнец формы: прежний id в прозе не с начала строки — не объявление ─────
d="$(sandbox i16_prose)"; b="$(sandbox_digest "$d")"
i16_edit "$d" prose
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: проза называет прежний id"
capture "$d" "$C16"
assert_code 0 "БЛИЗНЕЦ: прежний id в прозе — не объявление объёма, молчит"

# ── предмета нет — ОТКАЗ ─────────────────────────────────────────────────────
d="$(sandbox i16_void)"
rm -f "$d/.claude/rules/MANIFEST.md"
capture "$d" "$C16"
assert_code 2 "ОТКАЗ: манифеста нет — VOID, а не «объём сошёлся»"

echo "[CENSUS] inject-16: утверждений исполнено $((pass + fail - i16_before))"
if [ "$((pass + fail - i16_before))" -eq 0 ]; then
    echo "[VOID] inject-16 — ни одного утверждения: часть ничего не доказала" >&2
    fail=$((fail + 1))
fi
