#!/usr/bin/env bash
# Birth inversion самого pre-RED driver'а.
#
# Приёмка §7 требует birth inversion от КАЖДОГО machine holder: known-good вход
# даёт ожидаемый pass, однофактный injected defect даёт ожидаемый RED, и нулевая
# перепись не может дать GREEN. Driver — тоже machine holder, поэтому те же три
# требования предъявляются здесь ему самому.
#
# Каждое утверждение проверяется В ОБЕ СТОРОНЫ: рядом с инъекцией стоит
# законный близнец, на котором driver обязан МОЛЧАТЬ. Односторонняя проба
# зеленела бы на driver'е, который отвергает всё.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$HERE/.." && pwd)"
DRIVER="$TESTS_DIR/run_case.py"
FAKE_SUT="$HERE/fake_sut.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0
ASSERTIONS=0
CAP_EXPECTATIONS=0

CAP_MISSING="RED · CASE_CAPABILITY_MISSING · exit 10"

# Отсутствующий SUT: путь внутри рабочего каталога, которого НЕТ на диске.
# Условие «признака у испытуемого нет» СТРОИТСЯ здесь, а не отыскивается среди
# кейсов, — см. врезку у стража ниже.
ABSENT_SUT="$WORK/absent-sut.py"

# expect <имя> <ожидаемая строка> <ожидаемый код> -- <команда...>
#
# СТРАЖ КЛАССА (задача воркспейса #485). Ожидание `CAP_MISSING` обязано наводить
# seam на подставленный SUT (`KACHO_CG_SUT=`), а не полагаться на то, что
# production SUT сегодня чего-то не умеет. Утверждение «у испытуемого этого
# признака нет», выписанное на кейсе живого семейства, переживает свой предмет в
# тот самый момент, когда семейство приземляется: за две волны так покраснели
# три утверждения — A1 и C2-близнец на волне 2 (17 семейств), к ним D1-близнец на
# волне 3 (33 семейства). Класс НЕ самоисцеляется — он растёт с числом семейств,
# а красное, приходящее не от дефекта, перестают читать вместе с настоящей
# находкой.
#
# Почему СТРОИТЬ, а не выбирать кейс необъявленного семейства: такого кейса нет
# и не будет. Замер на этом дереве — семейств в testdata 33, объявлено 33,
# разность в обе стороны пуста; предикат воспроизводится сравнением
# `run.py --capabilities` с именами каталогов `tests/testdata`. Выбор кейса
# отложил бы поломку, а не снял её.
expect() {
  local name="$1" want_line="$2" want_exit="$3"; shift 4
  ASSERTIONS=$((ASSERTIONS + 1))

  if [ "$want_line" = "$CAP_MISSING" ]; then
    CAP_EXPECTATIONS=$((CAP_EXPECTATIONS + 1))
    local argument seam_pinned=0
    for argument in "$@"; do
      case "$argument" in KACHO_CG_SUT=*) seam_pinned=1 ;; esac
    done
    if [ "$seam_pinned" = "0" ]; then
      FAILED=$((FAILED + 1))
      printf '  FAIL %s\n       ожидание CAP_MISSING не наводит seam: нет KACHO_CG_SUT=\n       оно опирается на то, чего production SUT ещё не умеет, и покраснеет,\n       как только семейство приземлится\n' "$name"
      return
    fi
  fi

  local out rc last
  out="$("$@" 2>&1)"; rc=$?
  last="$(printf '%s\n' "$out" | grep -v '^$' | tail -1)"
  if [ "$last" = "$want_line" ] && [ "$rc" = "$want_exit" ]; then
    PASSED=$((PASSED + 1))
    printf '  OK   %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL %s\n       ждали: %s (код %s)\n       имеем: %s (код %s)\n' \
      "$name" "$want_line" "$want_exit" "$last" "$rc"
  fi
}

fresh_testdata() {
  local dest="$WORK/$1"
  rm -rf "$dest"; mkdir -p "$dest"
  cp -r "$TESTS_DIR/testdata/." "$dest/"
  printf '%s' "$dest"
}

echo "== A. Честный acceptance RED: SUT отсутствует =="
# Отсутствие СТРОИТСЯ: seam наводится на путь, которого нет на диске. Прежняя
# редакция полагалась на то, что production SUT ещё не написан, — и утверждение
# умерло вместе с этой предпосылкой (#485).
expect "A1 SUT отсутствует -> capability RED" \
  "$CAP_MISSING" 10 -- \
  env KACHO_CG_SUT="$ABSENT_SUT" python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

# Переопределение seam в A1 законно ровно потому, что БЕЗ него seam указывает на
# production-координату. Без этой пары A1 доказывал бы поведение подставленного
# пути и молчал бы о том, куда driver ходит в матрице.
#
# Сверяется ХВОСТ пути, а не путь целиком: дерево проб копируют в сторону
# (`selfcheck/inject.sh` делает ровно это), и корень репозитория в копии другой,
# тогда как относительная координата испытуемого — свойство контракта §6 и от
# места копии не зависит. Обе стороны: без переопределения — production-хвост,
# с переопределением — дословно переданный путь.
ASSERTIONS=$((ASSERTIONS + 1))
seam_path_of() {
  ( cd "$TESTS_DIR" && "$@" python3 -c \
      'import sys; sys.path.insert(0, "."); from caselib import seam; print(seam.sut_path())' )
}
SEAM_DEFAULT="$(seam_path_of env -u KACHO_CG_SUT)"
SEAM_OVERRIDDEN="$(seam_path_of env KACHO_CG_SUT="$ABSENT_SUT")"
seam_default_ok=0
case "$SEAM_DEFAULT" in
  */scripts/change-graph-gate/run.py) seam_default_ok=1 ;;
esac
if [ "$seam_default_ok" = "1" ] && [ "$SEAM_OVERRIDDEN" = "$ABSENT_SUT" ]; then
  PASSED=$((PASSED + 1))
  echo "  OK   A2 seam: без переопределения — production-координата, с ним — переданный путь"
else
  FAILED=$((FAILED + 1))
  printf '  FAIL A2 seam ведёт не туда\n       без переопределения: %s (ждали хвост */scripts/change-graph-gate/run.py)\n       с переопределением: %s (ждали %s)\n' \
    "$SEAM_DEFAULT" "$SEAM_OVERRIDDEN" "$ABSENT_SUT"
fi

echo
echo "== B. Собственная поломка driver'а НЕ выдаёт себя за capability RED =="
TD="$(fresh_testdata b)"

rm -rf "$TD/SDD-1-BOOT-01"
expect "B1 нет каталога fixture -> HARNESS, не capability" \
  "HARNESS · HARNESS_FIXTURE_MISSING · exit 40" 40 -- \
  env KACHO_CG_TESTDATA="$TD" python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

printf 'не: [YAML\n  - и не\n' > "$TD/SDD-1-BOOT-02/world.yaml"
expect "B2 world.yaml не разбирается -> HARNESS" \
  "HARNESS · HARNESS_FIXTURE_MALFORMED · exit 40" 40 -- \
  env KACHO_CG_TESTDATA="$TD" python3 "$DRIVER" --case SDD-1-BOOT-02 --quiet

expect "B3 неизвестный case ID -> HARNESS" \
  "HARNESS · HARNESS_CASE_UNKNOWN · exit 40" 40 -- \
  python3 "$DRIVER" --case SDD-1-NOSUCH-01 --quiet

TD="$(fresh_testdata b2)"
python3 - "$TD" <<'PY'
import sys, yaml
path = sys.argv[1] + "/SDD-1-AUTH-03/case.yaml"
doc = yaml.safe_load(open(path, encoding="utf-8"))
doc["driver_assertion"]["diagnostic"] = "CG_SOMETHING_ELSE"
yaml.safe_dump(doc, open(path, "w", encoding="utf-8"), allow_unicode=True, sort_keys=False)
PY
expect "B4 fixture расходится с приёмкой -> HARNESS" \
  "HARNESS · HARNESS_FIXTURE_SPEC_MISMATCH · exit 40" 40 -- \
  env KACHO_CG_TESTDATA="$TD" python3 "$DRIVER" --case SDD-1-AUTH-03 --quiet

echo
echo "== C. One-fact delta: два факта и необъявленный факт не дают verdict =="
TD="$(fresh_testdata c)"
python3 - "$TD" <<'PY'
import sys, yaml
path = sys.argv[1] + "/SDD-1-BOOT-02/world.yaml"
doc = yaml.safe_load(open(path, encoding="utf-8"))
doc["bootstrap"]["epoch"] = "post-cutover"   # второй факт поверх объявленного
yaml.safe_dump(doc, open(path, "w", encoding="utf-8"), allow_unicode=True, sort_keys=False)
PY
expect "C1 два факта относительно twin -> HARNESS, verdict НЕ выдан" \
  "HARNESS · HARNESS_TWIN_DELTA_NOT_SINGLE · exit 40" 40 -- \
  env KACHO_CG_TESTDATA="$TD" python3 "$DRIVER" --case SDD-1-BOOT-02 --quiet

TD="$(fresh_testdata c2)"
python3 - "$TD" <<'PY'
import sys, yaml
base = sys.argv[1] + "/SDD-1-BOOT-02"
doc = yaml.safe_load(open(base + "/world.yaml", encoding="utf-8"))
doc["bootstrap"]["change_id"] = "SDD-1"          # объявленный факт откачен
doc["bootstrap"]["epoch"] = "post-cutover"        # изменён ДРУГОЙ факт
yaml.safe_dump(doc, open(base + "/world.yaml", "w", encoding="utf-8"), allow_unicode=True, sort_keys=False)
PY
expect "C2 один факт, но не объявленный -> HARNESS" \
  "HARNESS · HARNESS_TWIN_DELTA_UNDECLARED · exit 40" 40 -- \
  env KACHO_CG_TESTDATA="$TD" python3 "$DRIVER" --case SDD-1-BOOT-02 --quiet

# Близнец C1/C2: нетронутая fixture проходит проверку дельты и ДОХОДИТ до пробы
# capability. Что она там увидит, к предмету не относится, поэтому seam наводится
# на отсутствующий SUT — исход детерминирован и не зависит ни от объявленных
# семейств, ни от правил живого семейства boot.
TD="$(fresh_testdata c3)"
expect "C2-близнец нетронутая fixture молчит о дельте" \
  "$CAP_MISSING" 10 -- \
  env KACHO_CG_TESTDATA="$TD" KACHO_CG_SUT="$ABSENT_SUT" \
  python3 "$DRIVER" --case SDD-1-BOOT-02 --quiet

echo
echo "== D. Пиновать фактическую тройку вправе только три birth fixtures =="
TD="$(fresh_testdata d)"
python3 - "$TD" <<'PY'
import sys, yaml
path = sys.argv[1] + "/SDD-1-BOOT-01/case.yaml"
doc = yaml.safe_load(open(path, encoding="utf-8"))
doc["sut_stub"] = {"category": "GREEN", "diagnostic": "CG_OK", "exit": 0}
yaml.safe_dump(doc, open(path, "w", encoding="utf-8"), allow_unicode=True, sort_keys=False)
PY
expect "D1 stub на обычном кейсе -> HARNESS, матрица не вакуумна" \
  "HARNESS · HARNESS_STUB_NOT_PERMITTED · exit 40" 40 -- \
  env KACHO_CG_TESTDATA="$TD" python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

# Близнец D1: stub на DRIVER-01 принят, HARNESS_STUB_NOT_PERMITTED не выдан —
# fixture загрузилась и driver дошёл до пробы capability (шаг 5), тогда как сам
# stub читается позже (шаг 6). Seam наведён на отсутствующий SUT ровно затем,
# чтобы предметом осталась законность stub, а не тройка семейства driver.
TD="$(fresh_testdata d2)"
expect "D1-близнец stub на DRIVER-01 законен" \
  "$CAP_MISSING" 10 -- \
  env KACHO_CG_TESTDATA="$TD" KACHO_CG_SUT="$ABSENT_SUT" \
  python3 "$DRIVER" --case SDD-1-DRIVER-01 --quiet

echo
echo "== E. Присутствующий SUT: сломанная проба НЕ есть отсутствие capability =="
expect "E1 проба capability падает -> HARNESS, не capability RED" \
  "HARNESS · HARNESS_SUT_PROBE_FAILED · exit 40" 40 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_PROBE_MODE=crash \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

expect "E2 проба вернула не JSON -> HARNESS" \
  "HARNESS · HARNESS_SUT_PROBE_FAILED · exit 40" 40 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_PROBE_MODE=garbage \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

expect "E3 проба вернула не список строк -> HARNESS" \
  "HARNESS · HARNESS_SUT_PROBE_FAILED · exit 40" 40 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_PROBE_MODE=wrong-shape \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

expect "E4 SUT есть, нашей capability не объявил -> честный capability RED" \
  "$CAP_MISSING" 10 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.other" \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

echo
echo "== F. Компаратор различает три поля тройки ПОРОЗНЬ =="
expect "F1 тройка совпала -> GREEN" \
  "GREEN · CASE_ASSERTION_MATCHED · exit 0" 0 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.boot" \
  KACHO_CG_FAKE_TRIPLE="GREEN · CG_OK · exit 0" \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

expect "F2 разошлась только category -> category-mismatch" \
  "RED · CASE_ASSERTION_CATEGORY_MISMATCH · exit 10" 10 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.boot" \
  KACHO_CG_FAKE_TRIPLE="RED · CG_OK · exit 0" KACHO_CG_FAKE_EXIT_OVERRIDE=0 \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

expect "F3 разошлась только diagnostic -> diagnostic-mismatch" \
  "RED · CASE_ASSERTION_DIAGNOSTIC_MISMATCH · exit 10" 10 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.boot" \
  KACHO_CG_FAKE_TRIPLE="GREEN · CG_OTHER · exit 0" \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

expect "F4 разошёлся только exit -> exit-mismatch" \
  "RED · CASE_ASSERTION_EXIT_MISMATCH · exit 10" 10 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.boot" \
  KACHO_CG_FAKE_TRIPLE="GREEN · CG_OK · exit 7" \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

expect "F5 SUT печатает одно, возвращает другое -> HARNESS" \
  "HARNESS · HARNESS_SUT_OUTPUT_UNPARSEABLE · exit 40" 40 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.boot" \
  KACHO_CG_FAKE_TRIPLE="GREEN · CG_OK · exit 0" KACHO_CG_FAKE_EXIT_OVERRIDE=5 \
  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet

echo
echo "== G. Три birth fixtures драйвера дают ожидаемый final holder =="
expect "G1 DRIVER-01 -> category-mismatch" \
  "RED · CASE_ASSERTION_CATEGORY_MISMATCH · exit 10" 10 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.driver" \
  python3 "$DRIVER" --case SDD-1-DRIVER-01 --quiet

expect "G2 DRIVER-02 -> diagnostic-mismatch" \
  "RED · CASE_ASSERTION_DIAGNOSTIC_MISMATCH · exit 10" 10 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.driver" \
  python3 "$DRIVER" --case SDD-1-DRIVER-02 --quiet

expect "G3 DRIVER-03 -> exit-mismatch" \
  "RED · CASE_ASSERTION_EXIT_MISMATCH · exit 10" 10 -- \
  env KACHO_CG_SUT="$FAKE_SUT" KACHO_CG_FAKE_CAPABILITIES="cg.driver" \
  python3 "$DRIVER" --case SDD-1-DRIVER-03 --quiet

echo
echo "== H. Подделка недостижима из матрицы =="
ASSERTIONS=$((ASSERTIONS + 1))
if grep -rn 'KACHO_CG_SUT' "$TESTS_DIR/run_case.py" "$TESTS_DIR/run_matrix.py" \
     "$TESTS_DIR/caselib" >/dev/null 2>&1; then
  # переменную читает ровно один модуль — seam; матрица её не выставляет
  setters="$(grep -rln 'KACHO_CG_SUT=' "$TESTS_DIR/run_case.py" "$TESTS_DIR/run_matrix.py" \
             "$TESTS_DIR/caselib" "$TESTS_DIR/tools" 2>/dev/null | wc -l)"
  if [ "$setters" = "0" ]; then
    PASSED=$((PASSED + 1)); echo "  OK   H1 матрица не выставляет KACHO_CG_SUT (мест: 0)"
  else
    FAILED=$((FAILED + 1)); echo "  FAIL H1 матрица выставляет KACHO_CG_SUT в $setters местах"
  fi
else
  FAILED=$((FAILED + 1)); echo "  FAIL H1 переменная seam не найдена вовсе — проба беспредметна"
fi

ASSERTIONS=$((ASSERTIONS + 1))
FAKES="$(grep -rln 'fake_sut' "$TESTS_DIR/testdata" 2>/dev/null | wc -l)"
if [ "$FAKES" = "0" ]; then
  PASSED=$((PASSED + 1)); echo "  OK   H2 ни одна из 196 fixtures не ссылается на подделку"
else
  FAILED=$((FAILED + 1)); echo "  FAIL H2 подделка упомянута в $FAKES fixtures"
fi

echo
echo "== I. Предмет стража класса непуст =="
ASSERTIONS=$((ASSERTIONS + 1))
if [ "$CAP_EXPECTATIONS" -ge 1 ]; then
  PASSED=$((PASSED + 1))
  echo "  OK   I1 ожиданий CAP_MISSING: $CAP_EXPECTATIONS, каждое наводит seam"
else
  FAILED=$((FAILED + 1))
  echo "  FAIL I1 ожиданий CAP_MISSING ноль — страж класса беспредметен"
fi

echo
echo "=== перепись проб harness'а ==="
echo "утверждений: $ASSERTIONS · прошло: $PASSED · провалено: $FAILED"
if [ "$ASSERTIONS" = "0" ]; then
  echo "проба беспредметна: утверждений ноль"
  exit 2
fi
[ "$FAILED" = "0" ] || exit 1
exit 0
