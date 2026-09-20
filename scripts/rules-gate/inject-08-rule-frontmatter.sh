#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-08 «файл правил несёт frontmatter,
# имя в нём сходится с именем файла» по четырём осям — frontmatter снят, имя
# разошлось, description пуст, обход усечён.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

# ── СТРАЖ ПОДКЛЮЧЕНИЯ ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Она подключается из scripts/rules-gate/inject.sh и пользуется его оснасткой;" >&2
    echo "       самостоятельно писала бы в рабочее дерево. Запускать:" >&2
    echo "       bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i08_fn in sandbox capture assert_code assert_fixture_changed sandbox_digest; do
    command -v "$_i08_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i08_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i08_fn

C8=check-08-rule-frontmatter.sh
# Жертва выводится ИЗ ДЕРЕВА, а не из имени в коде.
V8=""
for _v in "$WS"/.claude/rules/*.md; do
    [ -e "$_v" ] || continue
    V8=".claude/rules/$(basename "$_v")"
    break
done
unset -v _v
if [ -z "$V8" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — в .claude/rules нет ни одного файла;" \
         "frontmatter портить не у чего" >&2
    exit 2
fi

# ── ось A: frontmatter снят целиком ──────────────────────────────────────────
d="$(sandbox i08_none)"
python3 - "$d/$V8" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read().split('\n')
assert t[0] == '---', 'у жертвы нет frontmatter — ось A беспредметна'
end = t.index('---', 1)
open(p, 'w', encoding='utf-8').write('\n'.join(t[end + 1:]))
PY
capture "$d" "$C8"
assert_code 1 "ДЕФЕКТ: файл правил без frontmatter — краснеет"

# ── ось B: имя в frontmatter не сходится с именем файла ──────────────────────
d="$(sandbox i08_name)"
sed -i 's/^name: rule-.*/name: rule-ne-to-imya/' "$d/$V8"
capture "$d" "$C8"
assert_code 1 "ДЕФЕКТ: имя скила разошлось с именем файла — краснеет"

# ── ось C: description пуст ─────────────────────────────────────────────────
d="$(sandbox i08_desc)"
sed -i 's/^description: .*/description:/' "$d/$V8"
capture "$d" "$C8"
assert_code 1 "ДЕФЕКТ: description пуст — краснеет"

# ── ось D: обход усечён — вердикт беспредметен, а не «находок ноль» ──────────
# Проверка обязана отличать «осмотрел 17 файлов и не нашёл» от «осмотрел три».
d="$(sandbox i08_trunc)"
_left=0
for _f in "$d"/.claude/rules/*.md; do
    [ -e "$_f" ] || continue
    _left=$((_left + 1))
    [ "$_left" -le 3 ] || rm -f "$_f"
done
unset -v _f _left
capture "$d" "$C8"
assert_code 1 "ДЕФЕКТ: усечённый обход — краснеет, а не молчит"

# ── БЛИЗНЕЦ: файл ДОБАВЛЕН, frontmatter правильный ──────────────────────────
d="$(sandbox i08_twin)"; b="$(sandbox_digest "$d")"
printf -- '---\nname: rule-zz-bliznec-proby\ndescription: правило-близнец пробы: frontmatter на месте, имя сходится\n---\n\nтело.\n' \
    > "$d/.claude/rules/zz-bliznec-proby.md"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: новый файл правил с верным frontmatter"
capture "$d" "$C8"
assert_code 0 "БЛИЗНЕЦ: файл с верным frontmatter — молчит"

# ── ось Z: нетронутая копия — молчит ────────────────────────────────────────
d="$(sandbox i08_clean)"
capture "$d" "$C8"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"
