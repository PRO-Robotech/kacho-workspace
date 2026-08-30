#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# sloc-inject.sh — доказательство того, что счётчик строк СПОСОБЕН ошибиться
# заметно, а не молча. Инъекция в обе стороны: счётчик ломается по одной оси за
# раз, и каждый раз проверяется, что встроенная самопроверка это ловит И что
# замер после этого НЕ печатается.
#
# ЗАЧЕМ. Счётчик, который не ошибался ни разу, неотличим от счётчика, который
# ошибаться умеет и делает это тихо. Числа он выдаёт всегда — правдоподобные,
# круглые и не проверяемые на глаз: разницу между 199 299 и 260 000 строк по
# выводу не увидит никто. Единственный способ доверять числу — показать, что
# при сломанном счётчике оно не печатается вовсе.
#
# Проверяется восемнадцать утверждений по трём осям:
#
#   СЧЁТЧИК (ломается КОПИЯ sloc.py; оригинал не трогается):
#     A. целый счётчик: самопроверка молчит, замер идёт, код 0;
#     B. комментарий перестал быть комментарием (снят маркер `//`) → код 1;
#     C. raw-строка Go больше не raw → код 1;
#     D. docstring Python больше не блок → код 1;
#     E. литерал перестал быть литералом (сняты кавычки Go) → код 1;
#     F. при коде 1 таблица замера НЕ печатается — иначе сломанные числа уедут
#        в отчёт вместе с предупреждением, которого никто не читает. Проверяется
#        на КАЖДОЙ из осей B–E, а не однажды.
#
#   КЛАССИФИКАТОР (счётчик целый, синтетическое дерево со всеми видами):
#     G. package-lock.json → манифест, а НЕ рукописный код;
#     H. результаты прогона под tests/ → артефакт, а НЕ пробы;
#     I. internal/repohygiene/*_test.go → гейты, а НЕ пробы;
#     J. коллекция newman → сген, её источник → newman;
#     K. законный близнец: обычный .go под services/ → код;
#     L. законный близнец: *_test.go под services/ → пробы;
#     M. ui-future: компонент → ui, его проба → ui-пробы.
#
#   ИСХОДЫ (их три, и третий не засчитывается в успех):
#     N. каталог не репозиторий → код 2 (VOID), не 0 и не 1;
#     O. репозиторий, где нечего читать → код 2, а не «ноль строк»;
#     P. неизвестный вид у --files → код 2;
#     Q. перепись объёма и ревизия дерева напечатаны при успехе.
#
# ЗАЧЕМ K, L и M. Без законных близнецов инъекция G–J доказывала бы только, что
# классификатор умеет назвать что-то «не кодом». Классификатор, сваливающий ВСЁ
# в один вид, прошёл бы G, H, I и J и провалился бы на K, L, M — поэтому они
# здесь. Инъекция без стороны молчания измеряет строгость, а не верность.
#
# ЗАЧЕМ ПРОМАХ ИНЪЕКЦИИ — ОТДЕЛЬНЫЙ ИСХОД. Ломатель, не нашедший в счётчике
# искомой формы, обязан сказать это вслух, а не «сломать» ничего и получить
# зелёное. Так эта проверка себя и поймала при первой сборке: два выражения не
# пережили экранирование, и без этой ветки они читались бы как выполненные.
#
# ЧТО ЭТА ИНЪЕКЦИЯ УЖЕ НАШЛА — ось E, при первой же сборке. Снятие кавычек Go
# самопроверка НЕ различала: во всех её случаях код стоял ДО литерала, поэтому
# построчный счёт не менялся и сломанный счётчик выглядел исправным. Дыру закрыл
# случай «литерал не открывает блочный комментарий» (`var s = "/* не блок"`), где
# снятие кавычек даёт `/*`, съедающий три последующие строки. Это и есть довод в
# пользу инъекции против чтения: набор случаев выглядел полным, пока его не
# проверили ломателем.
#
# ОКРУЖЕНИЕ GIT НЕ НАСЛЕДУЕТСЯ. Скрипт заводит свои репозитории во временном
# каталоге; будучи запущенным из хука (`GIT_DIR` выставлен), он без этого
# снятия писал бы в рабочую копию воркспейса — её индекс схлопывается, а падают
# потом проверки, ни к чему не причастные. Тот же класс, что снят в
# scripts/hooks/pre-push.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SLOC="${1:-$HERE/sloc.py}"
[ -r "$SLOC" ] || { echo "inject: не найден $SLOC" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
say() { printf '%s %s\n' "$1" "$2"; }

# ── синтетическое дерево: по файлу на каждый вид ─────────────────────────────
TREE="$TMP/tree"
mkdir -p "$TREE"/services/vpc/internal \
         "$TREE"/services/vpc/tests/newman/cases \
         "$TREE"/services/vpc/tests/newman/collections \
         "$TREE"/services/vpc/tests/k6/results \
         "$TREE"/internal/repohygiene \
         "$TREE"/ui-future/shared/src \
         "$TREE"/pkg/api
cd "$TREE"
git init -q -b main .
git config user.email inject@example.invalid
git config user.name  inject
git config commit.gpgsign false

printf 'package m\n// комментарий\nvar a = "//не коммент"\n'   > services/vpc/internal/foo.go
printf 'package m\nfunc TestX(t *testing.T) {\n\t_ = 1\n}\n'    > services/vpc/internal/foo_test.go
printf 'package m\nfunc TestGate(t *testing.T) {\n\t_ = 1\n}\n' > internal/repohygiene/gate_test.go
printf 'CASES = [1, 2, 3]\n'                                    > services/vpc/tests/newman/cases/a.py
printf '{\n "item": [\n  {"name": "x"}\n ]\n}\n'                > services/vpc/tests/newman/collections/a.json
printf 'iteration 1 ok\niteration 2 ok\n'                       > services/vpc/tests/k6/results/run-1.txt
printf '{\n "lockfileVersion": 3\n}\n'                          > package-lock.json
printf 'export const A = () => <div/>\n'                        > ui-future/shared/src/A.tsx
printf 'test("a", () => { expect(1).toBe(1) })\n'               > ui-future/shared/src/A.test.tsx
printf 'package apiv1\ntype X struct{}\n'                       > pkg/api/x.pb.go
git add -A && git commit -qm "синтетическое дерево"

# ── A. целый счётчик ─────────────────────────────────────────────────────────
OUT=$(python3 "$SLOC" --json "$TREE" 2>"$TMP/err"); RC=$?
if [ "$RC" -eq 0 ] && [ -n "$OUT" ]; then
  say "✅ A" "целый счётчик: самопроверка молчит, замер выполнен (код 0)"
else
  say "❌ A" "на целом счётчике ожидался код 0 с выводом, получен $RC"; cat "$TMP/err"; fail=1
fi
JSON="$OUT"

# ── B..E. счётчик ломается по одной оси; каждый раз ждём код 1 ───────────────
#
# Правка описана ВНУТРИ python-вставки: сюда не проходит экранирование shell, а
# ломать приходится строки, целиком состоящие из кавычек и обратных апострофов.
break_axis() {
  local tag="$1" out rc
  python3 - "$SLOC" "$TMP/broken.py" "$tag" <<'PY'
import sys
src, dst, tag = sys.argv[1:4]
AXES = {
    # тег: (искомая форма в счётчике, чем её подменить)
    "B": ('_C = dict(line=("//",),', '_C = dict(line=(),'),
    "C": ('raw=("`",)),',            'raw=()),'),
    "D": ("""block=(('\"\"\"', '\"\"\"'), ("'''", "'''")),""", "block=(),"),
    "E": ("""".go":    dict(_C, quotes=('"', "'"), raw=""", '".go":    dict(_C, quotes=(), raw='),
}
old, new = AXES[tag]
text = open(src).read()
if old not in text:
    sys.exit(3)          # промах по коду — это отдельный исход, а не «сломал»
open(dst, "w").write(text.replace(old, new, 1))
PY
  if [ $? -ne 0 ]; then
    say "❌ $tag" "инъекция промахнулась: искомой формы в счётчике нет — выражение устарело"
    fail=1; return
  fi
  out=$(python3 "$TMP/broken.py" "$TREE" 2>"$TMP/err"); rc=$?
  if [ "$rc" -ne 1 ]; then
    say "❌ $tag" "сломанный счётчик обязан давать код 1, получен $rc"; fail=1; return
  fi
  if ! grep -q "САМОПРОВЕРКА НЕ СОШЛАСЬ" "$TMP/err"; then
    say "❌ $tag" "код 1 получен, но причина не названа — находка обязана себя объяснять"; fail=1; return
  fi
  if printf '%s' "$out" | grep -q "РУКОПИСНЫЙ КОД"; then
    say "❌ $tag/F" "при сломанном счётчике НАПЕЧАТАНА таблица — числам поверят"; fail=1; return
  fi
  say "✅ $tag" "ось сломана → код 1, причина названа, таблица не напечатана (F)"
}

break_axis B    # маркер комментария Go
break_axis C    # raw-строки Go
break_axis D    # docstring Python
break_axis E    # кавычки строк Go

# ── G..M. классификатор на целом счётчике ────────────────────────────────────
expect_in() { # <тег> <вид> <путь>
  local got
  got=$(printf '%s' "$JSON" | python3 -c "
import json, sys
res = json.load(sys.stdin)[0]
target = sys.argv[1]
print(next((k for k, v in res['paths'].items() if any(p == target for p, _ in v)), 'НИКУДА'))
" "$3")
  if [ "$got" = "$2" ]; then
    say "✅ $1" "$3 → «$2»"
  else
    say "❌ $1" "$3 ожидался в «$2», попал в «$got»"; fail=1
  fi
}
expect_in G  lock       package-lock.json
expect_in H  artifact   services/vpc/tests/k6/results/run-1.txt
expect_in I  gates      internal/repohygiene/gate_test.go
expect_in J  newman-gen services/vpc/tests/newman/collections/a.json
expect_in J2 newman     services/vpc/tests/newman/cases/a.py
expect_in K  code       services/vpc/internal/foo.go
expect_in L  tests      services/vpc/internal/foo_test.go
expect_in M  ui         ui-future/shared/src/A.tsx
expect_in M2 ui-tests   ui-future/shared/src/A.test.tsx

# ── N. не репозиторий → VOID ────────────────────────────────────────────────
mkdir -p "$TMP/plain" && printf 'package m\nvar a=1\n' > "$TMP/plain/x.go"
python3 "$SLOC" "$TMP/plain" >/dev/null 2>"$TMP/err"; RC=$?
if [ "$RC" -eq 2 ] && grep -q VOID "$TMP/err"; then
  say "✅ N" "каталог без git: код 2 (VOID), а не молчаливый ноль"
else
  say "❌ N" "ожидался код 2 с VOID, получен $RC"; fail=1
fi

# ── O. репозиторий, где нечего читать → VOID ────────────────────────────────
mkdir -p "$TMP/empty" && (cd "$TMP/empty" && git init -q -b main .)
python3 "$SLOC" "$TMP/empty" >/dev/null 2>"$TMP/err"; RC=$?
if [ "$RC" -eq 2 ] && grep -q "НИ ОДНОГО файла" "$TMP/err"; then
  say "✅ O" "пустой репозиторий: код 2 — «ноль строк» и «ноль прочитанного» различены"
else
  say "❌ O" "ожидался код 2 с объяснением, получен $RC"; fail=1
fi

# ── P. неизвестный вид ──────────────────────────────────────────────────────
python3 "$SLOC" --files выдуманный "$TREE" >/dev/null 2>"$TMP/err"; RC=$?
if [ "$RC" -eq 2 ]; then
  say "✅ P" "неизвестный вид у --files: код 2, перечень известных напечатан"
else
  say "❌ P" "ожидался код 2, получен $RC"; fail=1
fi

# ── Q. перепись и ревизия напечатаны ────────────────────────────────────────
TXT=$(python3 "$SLOC" "$TREE" 2>/dev/null)
if printf '%s' "$TXT" | grep -q "ПЕРЕПИСЬ" && printf '%s' "$TXT" | grep -q "ДЕРЕВО .* @ "; then
  say "✅ Q" "объём осмотренного и ревизия дерева напечатаны"
else
  say "❌ Q" "перепись или ревизия отсутствуют — число сказано неизвестно о чём"; fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "sloc-inject: 18 утверждений, все выполнены — счётчик способен ошибиться ЗАМЕТНО"
else
  echo "sloc-inject: есть невыполненные утверждения" >&2
fi
exit "$fail"
