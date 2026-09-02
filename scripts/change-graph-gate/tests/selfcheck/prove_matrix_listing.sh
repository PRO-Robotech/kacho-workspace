#!/usr/bin/env bash
# Сквозное утверждение о перечнях run_matrix — на НАСТОЯЩЕМ прогоне матрицы.
#
# Секция J файла prove.sh судит печатник прямым вызовом и его место — разбором
# main. Ни то, ни другое не говорит, что ПРОГРАММА перечень выводит: печатник
# мог бы быть позван и его результат отброшен. Здесь ломается 25 кейсов-листьев,
# матрица гоняется целиком, и вывод обязан назвать все 25 поломок и свою полноту.
#
# Живёт ОТДЕЛЬНО от prove.sh намеренно. Один прогон матрицы стоит ~40 с, а
# inject.sh гоняет prove.sh по разу на инъекцию — то есть утверждение,
# поставленное туда, умножилось бы на число инъекций и подорожало бы обе пробы
# в полтора десятка раз. Поэтому способность падать доказывается здесь же:
# рядом с контролем стоит дерево, где предел поломок возвращён, и контрольные
# утверждения на нём обязаны НЕ выполниться.
#
# Исходов три: 0 — всё прошло; 1 — есть провалившееся; 2 — проба беспредметна.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
ACCEPTANCE="$ROOT/docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0
ASSERTIONS=0

note_ok() { PASSED=$((PASSED + 1)); printf '  OK   %s\n' "$1"; }
note_bad() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

# contains <имя> <ожидаемая строка целиком> <файл>
contains() {
  ASSERTIONS=$((ASSERTIONS + 1))
  if grep -qxF -- "$2" "$3"; then note_ok "$1"
  else note_bad "$1" "строки нет: $2"; fi
}

# absent <имя> <строка, которой быть НЕ должно> <файл>
absent() {
  ASSERTIONS=$((ASSERTIONS + 1))
  if grep -qxF -- "$2" "$3"; then note_bad "$1" "строка есть, а быть не должна: $2"
  else note_ok "$1"; fi
}

# counts <имя> <образец> <сколько> <файл>
counts() {
  ASSERTIONS=$((ASSERTIONS + 1))
  local got; got="$(grep -c -- "$2" "$4")"
  if [ "$got" = "$3" ]; then note_ok "$1 (строк $got)"
  else note_bad "$1" "строк по образцу $2 — $got, ждали $3"; fi
}

# --- вход: копия testdata с 25 сломанными кейсами-листьями --------------------
TD="$WORK/testdata"
mkdir -p "$TD"
cp -r "$TESTS_DIR/testdata/." "$TD/"

cat > "$WORK/break_leaves.py" <<'PY'
"""Ломает world.yaml у 25 кейсов-листьев копии testdata.

Лист — кейс, который не служит twin'ом никому: у derived-кейса дельта считается
против мира twin'а, поэтому поломка twin'а уронила бы и его потомков, и число
поломок перестало бы равняться числу сломанных fixtures. Число, которое проба
утверждает, обязано быть ВЫБРАНО ею, а не получиться.
"""
import os
import sys

sys.path.insert(0, sys.argv[1])
from caselib import spec as spec_module

registry, order = spec_module.load_registry()
twins = {registry[case_id].get("twin") for case_id in order}
leaves = [case_id for case_id in order if case_id not in twins]
chosen = leaves[:25]
if len(chosen) != 25:
    sys.stderr.write("листьев только %d — ломать нечего\n" % len(leaves))
    raise SystemExit(1)
for case_id in chosen:
    with open(os.path.join(sys.argv[2], case_id, "world.yaml"), "w",
              encoding="utf-8") as handle:
        handle.write("не: [YAML\n  - и не\n")
sys.stdout.write("сломано листьев: %d\n" % len(chosen))
PY

ASSERTIONS=$((ASSERTIONS + 1))
if BROKEN="$(python3 "$WORK/break_leaves.py" "$TESTS_DIR" "$TD" 2>&1)" \
   && [ "$BROKEN" = "сломано листьев: 25" ]; then
  note_ok "L0 вход выбран пробой: сломано ровно 25 кейсов-листьев"
else
  note_bad "L0 вход выбран пробой: сломано ровно 25 кейсов-листьев" \
    "заготовщик ответил: $BROKEN — дальше утверждения о числе вакуумны"
  echo
  echo "=== перепись сквозных проб перечня ==="
  echo "утверждений: $ASSERTIONS · прошло: $PASSED · провалено: $FAILED"
  exit 1
fi

# --- контроль: нетронутый run_matrix на этом входе ----------------------------
CONTROL_OUT="$WORK/control.txt"
env KACHO_CG_TESTDATA="$TD" python3 "$TESTS_DIR/run_matrix.py" final \
  > "$CONTROL_OUT" 2>&1 || true

contains "L1 перечень поломок называет свою полноту" \
  "  поломок harness показано 25 из 25" "$CONTROL_OUT"
counts "L2 названы все 25 поломок поимённо" \
  '^  HARNESS SDD-1-' 25 "$CONTROL_OUT"

# --- инъекция: предел поломок возвращён --------------------------------------
# Обрезанный перечень поломок и есть предмет запрета: поломка — третья категория
# исхода, вердикта нет ни у одного такого кейса, и скрытая часть перечня
# неотличима от его конца.
cp -r "$TESTS_DIR" "$WORK/tests"
find "$WORK/tests" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null
ASSERTIONS=$((ASSERTIONS + 1))
if python3 - "$WORK/tests/run_matrix.py" <<'PY'
import io
import sys

path = sys.argv[1]
source = io.open(path, encoding="utf-8").read()
needle = "HARNESS_LIST_CAP = None"
if needle not in source:
    sys.stderr.write("подстановка не состоялась: %r не найдено\n" % needle)
    raise SystemExit(1)
io.open(path, "w", encoding="utf-8").write(
    source.replace(needle, "HARNESS_LIST_CAP = 20", 1))
PY
then
  note_ok "L3 подстановка состоялась: предел поломок возвращён"
else
  note_bad "L3 подстановка состоялась: предел поломок возвращён" \
    "образец не найден — инъекция беспредметна, и всё ниже доказывает не то"
fi

INJECTED_OUT="$WORK/injected.txt"
# Копия дерева лежит в /tmp, и приёмки относительно неё нет: координата
# называется явно — иначе прогон падает на чтении, а перечень выходит пустым,
# и утверждения об ОТСУТСТВИИ строк проходили бы по чужой причине.
env KACHO_CG_TESTDATA="$TD" KACHO_CG_ACCEPTANCE="$ACCEPTANCE" \
  python3 "$WORK/tests/run_matrix.py" final > "$INJECTED_OUT" 2>&1 || true

absent "L4 на усечённом перечне утверждение L1 НЕ выполняется" \
  "  поломок harness показано 25 из 25" "$INJECTED_OUT"
counts "L5 на усечённом перечне утверждение L2 НЕ выполняется" \
  '^  HARNESS SDD-1-' 20 "$INJECTED_OUT"
# Даже усечённый перечень обязан называть обрезку — иначе конец списка от неё
# не отличить, и число над перечнем остаётся единственной правдой.
contains "L6 усечённый перечень называет обрезку" \
  "  поломок harness показано 20 из 25" "$INJECTED_OUT"
# Число над перечнем от обрезки не меняется: обрезается ПОКАЗ, а не счёт.
contains "L7 число над перечнем обрезкой не затронуто" \
  "поломок harness (exit 40, verdict НЕ выдан): 25" "$INJECTED_OUT"

# --- третий вход: перечень РАСХОЖДЕНИЙ, тоже сквозным прогоном ----------------
# У расхождений предел показа оставлен, поэтому обрезка на них происходит в
# настоящем прогоне — и утверждать её надо там же. Композиции «печатник умеет ×
# main его зовёт» здесь недостаточно: свойство целого меряется на целом.
#
# Все кейсы разом делаются расходящимися подменой финальной тройки driver'а на
# одну и ту же: тогда совпадут только те, кто её и ожидал, а остальные разойдутся.
cp -r "$TESTS_DIR" "$WORK/tests-mismatch"
find "$WORK/tests-mismatch" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null
ASSERTIONS=$((ASSERTIONS + 1))
if python3 - "$WORK/tests-mismatch/run_case.py" <<'PY'
import io
import sys

path = sys.argv[1]
source = io.open(path, encoding="utf-8").read()
needle = ('def finish(reporter, triple, as_json=False, payload=None):\n'
          '    """Печатает финальную тройку и завершает процесс её кодом."""\n')
if needle not in source:
    sys.stderr.write("подстановка не состоялась: сигнатура finish не найдена\n")
    raise SystemExit(1)
io.open(path, "w", encoding="utf-8").write(source.replace(
    needle,
    needle + '    triple = verdict_module.holder(\n'
             '        verdict_module.CATEGORY_RED,\n'
             '        verdict_module.CASE_ASSERTION_EXIT_MISMATCH)\n',
    1))
PY
then
  note_ok "M0 подстановка состоялась: driver отдаёт одну тройку всем кейсам"
else
  note_bad "M0 подстановка состоялась: driver отдаёт одну тройку всем кейсам" \
    "сигнатура не найдена — вход не построен, и всё ниже доказывает не то"
fi

MISMATCH_OUT="$WORK/mismatch.txt"
env KACHO_CG_ACCEPTANCE="$ACCEPTANCE" \
  python3 "$WORK/tests-mismatch/run_matrix.py" final > "$MISMATCH_OUT" 2>&1 || true

# Числа не выписаны: они растут с каждым новым семейством, и выписанное здесь
# устарело бы молча. Сверяется РАВЕНСТВО числа над перечнем и числа в переписи
# перечня — при показанных ровно двадцати.
ASSERTIONS=$((ASSERTIONS + 1))
COUNTED="$(sed -n 's/^не совпало с ожидаемым: \([0-9]*\)$/\1/p' "$MISMATCH_OUT")"
SHOWN="$(sed -n 's/^  расхождений показано \([0-9]*\) из \([0-9]*\)$/\1 \2/p' "$MISMATCH_OUT")"
if [ -n "$COUNTED" ] && [ "$SHOWN" = "20 $COUNTED" ] && [ "$COUNTED" -gt 20 ]; then
  note_ok "M1 усечённый перечень расхождений называет обрезку ($SHOWN)"
else
  note_bad "M1 усечённый перечень расхождений называет обрезку" \
    "над перечнем «$COUNTED», перепись перечня «$SHOWN» — ждали «20 \$COUNTED» при \$COUNTED > 20"
fi

counts "M2 показано ровно предел строк расхождений" \
  '^  РАСХОЖДЕНИЕ SDD-1-' 20 "$MISMATCH_OUT"

echo
echo "=== перепись сквозных проб перечня ==="
echo "утверждений: $ASSERTIONS · прошло: $PASSED · провалено: $FAILED"
if [ "$ASSERTIONS" = "0" ]; then
  echo "проба беспредметна: утверждений ноль"
  exit 2
fi
[ "$FAILED" = "0" ] || exit 1
exit 0
