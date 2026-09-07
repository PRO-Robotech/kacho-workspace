#!/usr/bin/env bash
# shellcheck disable=SC2016
#   Вносимые строки — markdown; обратные кавычки в них разметка, а не подстановка
#   команды, поэтому одинарные кавычки здесь намеренны на весь файл.
#
# Доказательство набора rules-gate ИНЪЕКЦИЕЙ В ОБЕ СТОРОНЫ — на ВРЕМЕННОЙ копии
# дерева. Рабочее дерево не читается на запись и не меняется ни одной пробой.
#
# ЗАЧЕМ. Зелёные проверки на сошедшемся дереве не доказывают ничего: ровно так же
# выглядит набор, потерявший способность краснеть. Раскладка регламента держится
# ЭТИМ набором — перенос правила обратно в автозагрузку возвращает четверть окна
# каждому агенту волны, и другого сигнала об этом нет. Поэтому по каждой оси сюда
# вносится НАСТОЯЩИЙ дефект (проверка обязана покраснеть И НАЗВАТЬ координату) и
# рядом ставится ЗАКОННЫЙ БЛИЗНЕЦ той же формы (проверка обязана смолчать). Без
# близнеца проверка ловила бы форму, а не существо, и первый ложный срабат
# отключил бы её вместе с настоящими находками.
#
# ПРОВЕРЯЕТСЯ НЕ ТОЛЬКО КОД, НО И ЧТО НАПЕЧАТАНО. Находка, называющая симптом
# вместо координаты, посылает читателя искать не там; на неё тратят прогон, а
# потом снимают гейт как непонятный. Поэтому у каждого дефекта есть утверждение
# о ТЕКСТЕ вердикта, а не только о его коде.
#
# ОДИН ФАКТ НА ИНЪЕКЦИЮ. Каждая проба меняет ровно одно и меняет это там, где
# живёт предмет проверки. Инъекция вида «завести ещё один элемент» отвергнута
# намеренно: новый элемент нарушает всё, что требуется от элементов вообще, и
# красное пришло бы неизвестно от чего.
#
# КОНТРАКТ НАБОРА. Проверка обязана читать корень из `RULES_GATE_ROOT` — иначе её
# нельзя прогнать во временной копии, а инъекция в настоящем дереве не инъекция,
# а порча. Контрольный прогон идёт по ВСЕМ проверкам набора, выведенным глобом из
# дерева, а не по выписанному списку: выписанный разошёлся бы молча.
#
# Коды выхода: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — не
# исполнено ни одного утверждения (это НЕ успех).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/../.." && pwd)"
GATE="$HERE"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
OUT=""; RC=0

# sandbox <имя> — свежая копия автозагружаемого замыкания со своим git-индексом.
sandbox() {
    local dir="$TMP/s.$1"
    rm -rf "$dir"; mkdir -p "$dir/.claude"
    cp "$WS/CLAUDE.md" "$dir/"
    cp -r "$WS/.claude/rules" "$dir/.claude/"
    cp -r "$WS/.claude/rulebook" "$dir/.claude/" 2>/dev/null || true
    cp "$WS/.gitignore" "$dir/" 2>/dev/null || true
    git -C "$dir" init -q >/dev/null 2>&1
    git -C "$dir" add -A >/dev/null 2>&1
    echo "$dir"
}

# capture <каталог> <имя проверки> — заполняет RC и OUT.
capture() {
    OUT="$( cd "$1" && RULES_GATE_ROOT="$1" bash "$GATE/$2" 2>&1 )"
    RC=$?
}

assert_code() {   # <ожидаемый> <утверждение>
    if [ "$1" = "$RC" ]; then
        echo "  [OK]   $2"; pass=$((pass + 1))
    else
        echo "  [FAIL] $2 — ожидался код $1, получен $RC" >&2
        printf '%s\n' "$OUT" | sed 's/^/         | /' >&2
        fail=$((fail + 1))
    fi
}

assert_says() {   # <подстрока> <утверждение>
    if printf '%s\n' "$OUT" | grep -qF -- "$1"; then
        echo "  [OK]   $2"; pass=$((pass + 1))
    else
        echo "  [FAIL] $2 — в вердикте нет «$1»" >&2
        printf '%s\n' "$OUT" | sed 's/^/         | /' >&2
        fail=$((fail + 1))
    fi
}

# ── КОНТРОЛЬ: нетронутая копия — молчат ВСЕ проверки набора ──────────────────
#
# Перечень проверок выводится глобом из дерева: набор растёт, и выписанный
# список отстал бы от него молча. Пустой глоб — ОТКАЗ, а не молчаливый успех:
# инъекция, потерявшая свои проверки, вышла бы нулём и объявила доказанным то,
# чего не прогоняла ни разу.
echo "== контроль: нетронутая копия — все проверки набора молчат =="
d="$(sandbox control)"
checks=0
for c in "$GATE"/check-*; do
    [ -f "$c" ] || continue
    checks=$((checks + 1))
    n="$(basename "$c")"
    capture "$d" "$n"
    assert_code 0 "нетронутая копия · $n"
done
if [ "$checks" -eq 0 ]; then
    echo "инъекция rules-gate: проверок в $GATE не найдено — доказывать нечего" >&2
    exit 2
fi

# ── имена берутся ИЗ ДЕРЕВА, а не выписываются ──────────────────────────────
#
# Жертвой первой оси намеренно выбрано правило, которое CLAUDE.md УПОМИНАЕТ в
# прозе в обратных кавычках: сняв у него строку-объявление, мы оставляем
# упоминание — и проверка обязана всё равно сказать «НЕ ИМПОРТИРОВАН». Это самое
# острое утверждение набора: упоминание в прозе объявлением не является.
prose_rule="$(python3 - "$WS" <<'PY'
import os, re, sys
ws = sys.argv[1]
claude = open(os.path.join(ws, "CLAUDE.md"), encoding="utf-8").read()
names = sorted(n for n in os.listdir(os.path.join(ws, ".claude", "rules"))
               if n.endswith(".md"))
for n in names:
    if re.search(r"`@\.claude/rules/" + re.escape(n) + r"`", claude):
        print(n); break
else:
    print(names[0] if names else "")
PY
)"
book_rule="$(cd "$WS/.claude/rulebook" && ls -1 ./*.md 2>/dev/null | sed 's|^\./||' \
    | grep -v '^MANIFEST' | head -1)"
core_rule="$(cd "$WS/.claude/rules" && ls -1 ./*.md 2>/dev/null | sed 's|^\./||' | head -1)"
echo
echo "жертвы выведены из дерева: правило в прозе «$prose_rule», ядровое «$core_rule», rulebook «$book_rule»"

# ═════════════════════════════════════════════════════════════════════════════
# check-02-nothing-lost — четыре оси, у каждой дефект и законный близнец
# ═════════════════════════════════════════════════════════════════════════════
C2=check-02-nothing-lost.sh

echo
echo "== ось A: ничего не потеряно (файл есть, объявления нет) =="

d="$(sandbox a1)"
python3 - "$d" "$prose_rule" <<'PY'
import os, sys
d, name = sys.argv[1], sys.argv[2]
p = os.path.join(d, "CLAUDE.md")
lines = open(p, encoding="utf-8").readlines()
out = [l for l in lines if l.strip() != f"@.claude/rules/{name}"]
assert len(out) == len(lines) - 1, "ожидалась ровно одна строка-объявление"
open(p, "w", encoding="utf-8").writelines(out)
PY
capture "$d" "$C2"
assert_code 1 "ДЕФЕКТ: снята строка-объявление правила, упомянутого в прозе"
assert_says "НЕ ИМПОРТИРОВАН" "  ...и вердикт назван своим именем"
assert_says ".claude/rules/$prose_rule" "  ...и координата названа"

d="$(sandbox a2)"
python3 - "$d" <<'PY'
import os, re, sys
d = sys.argv[1]
p = os.path.join(d, "CLAUDE.md")
lines = open(p, encoding="utf-8").readlines()
idx = [i for i, l in enumerate(lines) if re.match(r"^@\.claude/rules/\S+\s*$", l)]
assert len(idx) >= 2, "для перестановки нужно хотя бы два объявления"
lines[idx[0]], lines[idx[-1]] = lines[idx[-1]], lines[idx[0]]
open(p, "w", encoding="utf-8").writelines(lines)
PY
capture "$d" "$C2"
assert_code 0 "БЛИЗНЕЦ: порядок объявлений другой, все на месте — молчит"

d="$(sandbox a3)"
printf 'черновик, не markdown\n' > "$d/.claude/rules/заметки.txt"
capture "$d" "$C2"
assert_code 0 "БЛИЗНЕЦ: файл не-.md в каталоге правил — единица счёта не он"

echo
echo "== ось B: ничего не забыто (объявление есть, файла нет) =="

d="$(sandbox b1)"
rm -f "$d/.claude/rules/$core_rule"
capture "$d" "$C2"
assert_code 1 "ДЕФЕКТ: файл правила снят, строка-объявление осталась"
assert_says "ИМПОРТ В НИКУДА" "  ...и вердикт назван своим именем"
assert_says "CLAUDE.md:" "  ...и координата строки названа"

d="$(sandbox b2)"
printf '\nКоординаты снятого правила — `@.claude/rules/такого-нет.md`.\n' >> "$d/CLAUDE.md"
capture "$d" "$C2"
assert_code 0 "БЛИЗНЕЦ: несуществующая координата в обратных кавычках — не импорт"

echo
echo "== ось C: rulebook не автозагружается (замыкание, а не один файл) =="

d="$(sandbox c1)"
printf '\n@.claude/rulebook/%s\n' "$book_rule" >> "$d/CLAUDE.md"
capture "$d" "$C2"
assert_code 1 "ДЕФЕКТ: правило rulebook возвращено в автозагрузку строкой целиком"
assert_says "ИМПОРТ RULEBOOK" "  ...и вердикт назван своим именем"
assert_says "@.claude/rulebook/$book_rule" "  ...и координата названа"

d="$(sandbox c2)"
printf '\nПодробности см. @.claude/rulebook/%s — там разобран класс.\n' "$book_rule" \
    >> "$d/.claude/rules/$core_rule"
capture "$d" "$C2"
assert_code 1 "ДЕФЕКТ: ТРАНЗИТИВНЫЙ импорт rulebook из ядрового правила"
assert_says "ИМПОРТ RULEBOOK: .claude/rules/$core_rule:" \
    "  ...и названа координата ЯДРОВОГО файла, а не CLAUDE.md"

d="$(sandbox c3)"
printf '\nПодробности — `@.claude/rulebook/%s` §«класс».\n' "$book_rule" >> "$d/CLAUDE.md"
capture "$d" "$C2"
assert_code 0 "БЛИЗНЕЦ: та же координата в обратных кавычках — законна, молчит"

d="$(sandbox c4)"
{ printf '\n```\n'; printf '@.claude/rulebook/%s\n' "$book_rule"; printf '```\n'; } \
    >> "$d/CLAUDE.md"
capture "$d" "$C2"
assert_code 0 "БЛИЗНЕЦ: та же координата в ограждённом блоке — не вычисляется, молчит"

echo
echo "== ось D: импорт, вставленный в СЕРЕДИНУ ПРЕДЛОЖЕНИЯ =="

d="$(sandbox d1)"
python3 - "$d" <<'PY'
import os, re, sys
d = sys.argv[1]
p = os.path.join(d, "CLAUDE.md")
lines = open(p, encoding="utf-8").readlines()
pat = re.compile(r"`(@\.claude/rules/[A-Za-z0-9_.-]+)`")
for i, l in enumerate(lines):
    if re.match(r"^@\.claude/rules/", l):
        continue
    m = pat.search(l)
    if m:
        lines[i] = l[:m.start()] + m.group(1) + l[m.end():]
        break
else:
    raise SystemExit("в CLAUDE.md нет прозаической координаты в обратных кавычках")
open(p, "w", encoding="utf-8").writelines(lines)
PY
capture "$d" "$C2"
assert_code 1 "ДЕФЕКТ: с прозаической координаты сняты обратные кавычки"
assert_says "ИМПОРТ В СЕРЕДИНЕ ПРЕДЛОЖЕНИЯ" "  ...и вердикт назван своим именем"

d="$(sandbox d2)"
python3 - "$d" <<'PY'
import os, re, sys
d = sys.argv[1]
p = os.path.join(d, "CLAUDE.md")
lines = open(p, encoding="utf-8").readlines()
for i, l in enumerate(lines):
    if re.match(r"^@\.claude/rules/\S+\s*$", l):
        lines[i] = "- " + l          # объявление стало элементом списка
        break
else:
    raise SystemExit("в CLAUDE.md нет ни одной строки-объявления")
open(p, "w", encoding="utf-8").writelines(lines)
PY
capture "$d" "$C2"
assert_code 1 "ДЕФЕКТ: объявление превращено в элемент списка"
assert_says "ИМПОРТ В СЕРЕДИНЕ ПРЕДЛОЖЕНИЯ" "  ...названо: это уже не объявление"
assert_says "НЕ ИМПОРТИРОВАН" "  ...и названо: правило перестало быть объявленным"

d="$(sandbox d3)"
printf '\nЯдро описано в `@.claude/rules/%s`.\n' "$core_rule" >> "$d/CLAUDE.md"
capture "$d" "$C2"
assert_code 0 "БЛИЗНЕЦ: новая координата в прозе в обратных кавычках — молчит"

echo
echo "== ось E: пустой обход — ОТКАЗ, а не «находок 0» =="

d="$(sandbox e1)"
rm -f "$d"/.claude/rules/*.md
capture "$d" "$C2"
assert_code 1 "каталог правил есть, .md в нём ноль — код 1"
assert_says "ОБХОД БЕСПРЕДМЕТЕН" "  ...и сказано, что обход беспредметен"

echo
echo "== ось F: предмета нет — код 2, и это НЕ успех =="

d="$(sandbox f1)"
rm -rf "$d/.claude/rules"
capture "$d" "$C2"
assert_code 2 "каталога .claude/rules/ нет вовсе — код 2, не 0 и не 1"

d="$(sandbox f2)"
rm -f "$d/CLAUDE.md"
capture "$d" "$C2"
assert_code 2 "корневого CLAUDE.md нет — код 2, не 0 и не 1"

# ═════════════════════════════════════════════════════════════════════════════
# Части соседних проверок набора. Файл общий на все проверки; тот, кто не хочет
# править его посередине, кладёт рядом `inject-NN-*.sh` и получает здешние
# sandbox/capture/assert_* готовыми.
# ═════════════════════════════════════════════════════════════════════════════
parts=0
for part in "$HERE"/inject-*.sh; do
    [ -f "$part" ] || continue
    parts=$((parts + 1))
    echo
    echo "== часть: $(basename "$part") =="
    # shellcheck disable=SC1090
    . "$part"
done

echo
# Перепись объёма — отдельным утверждением, а не подразумеваемым: «утверждений 0,
# разошлось 0» иначе печаталось бы как успех.
echo "[CENSUS] инъекция rules-gate: проверок набора на контроле $checks;" \
     "подключено частей $parts; утверждений $((pass + fail)) —" \
     "сошлось $pass, разошлось $fail"
if [ "$((pass + fail))" -eq 0 ]; then
    echo "[VOID] инъекция rules-gate — не прогнано ни одного утверждения; это НЕ успех" >&2
    exit 2
fi
if [ "$fail" -gt 0 ]; then
    echo "[FAIL] инъекция rules-gate — гейт не доказан: разошлось $fail из $((pass + fail))" >&2
    exit 1
fi
echo "[PASS] инъекция rules-gate — гейт доказан в обе стороны: утверждений $pass, разошлось 0"
exit 0
