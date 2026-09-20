#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-06 «объём и форма корпуса» по семи
# осям — перевес потолка, строка без `red:`, нечётный backtick, пустой императив,
# пустой держатель, пустой признак, слово «держится» — плюс отказ по усечённому
# обходу и законные близнецы той же формы.
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
for _i06_fn in sandbox capture assert_code assert_fixture_changed sandbox_digest; do
    command -v "$_i06_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i06_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i06_fn

C6=check-06-corpus-ceiling.sh
# Жертва выводится ИЗ ДЕРЕВА: имя в коде рассыпалось бы вместе с раскладкой.
V6=""
for _v in "$WS"/.claude/rules/*.md; do
    [ -e "$_v" ] || continue
    V6=".claude/rules/$(basename "$_v")"
    break
done
unset -v _v
if [ -z "$V6" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — в .claude/rules нет ни одного файла;" \
         "строку-норму вписывать некуда" >&2
    exit 2
fi

# row <ось> <строка> <утверждение> — одна дефектная строка-норма, один вердикт.
row() {
    local d; d="$(sandbox "i06_$1")"
    printf '\n%s\n' "$2" >> "$d/$V6"
    capture "$d" "$C6"
    assert_code 1 "$3"
}

# ── ось A: перевес потолка ───────────────────────────────────────────────────
# Добор считается ОТ ФАКТИЧЕСКОГО объёма копии, а не от числа в коде: иначе проба
# зеленела бы сама собой, как только корпус подрос, и «перевес» перестал бы быть
# внесённым ею.
d="$(sandbox i06_ceiling)"
NEED="$( cd "$d" && python3 -c '
import glob
t = sum(len(open(f, encoding="utf-8").read()) for f in glob.glob(".claude/rules/*.md"))
print(max(1, 200000 - t + 1000))' )"
python3 - "$d/$V6" "$NEED" <<'PY'
import sys
p, n = sys.argv[1], int(sys.argv[2])
with open(p, 'a', encoding='utf-8') as fh:
    fh.write('\n' + ('доборный текст перевеса. ' * ((n // 25) + 1)))
PY
capture "$d" "$C6"
assert_code 1 "ДЕФЕКТ: корпус перевесил потолок 200 000 — краснеет"

# ── оси B…G: форма строки-нормы ──────────────────────────────────────────────
row nored 'probe-bez-red · императив пробы · ЗАВЕСТИ probe-bez-red · признак без метки' \
    "ДЕФЕКТ: строка-норма без поля red: — краснеет"
row oddbt 'probe-odd-bt · императив с `незакрытым обратным апострофом · ЗАВЕСТИ probe-odd-bt · red: признак' \
    "ДЕФЕКТ: нечётный backtick в строке-норме — краснеет"
row noimp 'probe-pustoj-imperativ · — · ЗАВЕСТИ probe-pustoj-imperativ · red: признак' \
    "ДЕФЕКТ: пустой императив (поле 2) — краснеет"
row nohold 'probe-pustoj-derzhatel · императив пробы · — · red: признак' \
    "ДЕФЕКТ: пустой держатель (поле 3) — краснеет"
row nosign 'probe-pustoj-priznak · императив пробы · ЗАВЕСТИ probe-pustoj-priznak · red: —' \
    "ДЕФЕКТ: пустой признак красноты — краснеет"
row held 'probe-derzhitsya · императив пробы · держится вниманием · red: признак' \
    "ДЕФЕКТ: «держится» вместо названного механизма — краснеет"

# ── ось VOID: усечённый обход — ОТКАЗ, а не зелёный потолок ──────────────────
# Недочитанное дерево даёт сумму МЕНЬШЕ настоящей: «находок 0» здесь неотличимо
# от «в потолок уложились».
d="$(sandbox i06_trunc)"
_left=0
for _f in "$d"/.claude/rules/*.md; do
    [ -e "$_f" ] || continue
    _left=$((_left + 1))
    [ "$_left" -le 3 ] || rm -f "$_f"
done
unset -v _f _left
capture "$d" "$C6"
assert_code 2 "ДЕФЕКТ: усечённый обход — ОТКАЗ по предмету, не зелёный потолок"

# ── БЛИЗНЕЦ осей B…G: строка-норма ТОЙ ЖЕ формы, но полная ──────────────────
d="$(sandbox i06_twin_row)"; b="$(sandbox_digest "$d")"
printf '\n%s\n' "probe-polnaya-stroka · императив пробы в \`кавычках\` целиком · scripts/rules-gate/check-06-corpus-ceiling.sh · red: признак назван" \
    >> "$d/$V6"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: строка-норма добавлена, все четыре поля полны"
capture "$d" "$C6"
assert_code 0 "БЛИЗНЕЦ: полная строка-норма — молчит"

# ── БЛИЗНЕЦ оси A: корпус ВЫРОС, но потолка не достал ───────────────────────
d="$(sandbox i06_twin_grow)"; b="$(sandbox_digest "$d")"
python3 - "$d/$V6" <<'PY'
import sys
with open(sys.argv[1], 'a', encoding='utf-8') as fh:
    fh.write('\n' + ('прирост в пределах потолка. ' * 30))
PY
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: корпус вырос на 800 символов"
capture "$d" "$C6"
assert_code 0 "БЛИЗНЕЦ: рост под потолком — молчит"

# ── ось Z: нетронутая копия — молчит ────────────────────────────────────────
d="$(sandbox i06_clean)"
capture "$d" "$C6"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"
