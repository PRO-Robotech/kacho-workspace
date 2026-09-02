#!/usr/bin/env bash
# Доказательство того, что prove.sh СПОСОБЕН упасть — и падает на предмете.
#
# Контрольный прогон без дефекта обязан быть зелёным: проба, красная на целом
# дереве, доказывает не способность падать, а собственную поломку. Каждая
# инъекция обязана ронять НАЗВАННЫЕ утверждения, а не «много».
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

TOTAL=0
GOOD=0

run_case_of_injection() {
  local label="$1" mode="$2" want_failed="$3" want_named="$4" want_phrase="${5-}"
  local tmp; tmp="$(mktemp -d)"
  cp -r "$TESTS_DIR" "$tmp/tests"
  find "$tmp/tests" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null

  python3 - "$tmp" "$mode" <<'PY'
import sys
tmp, mode = sys.argv[1], sys.argv[2]
path = tmp + "/tests/run_case.py"
source = open(path, encoding="utf-8").read()
edits = {
    "none": (None, None),
    "mask-harness": (
        '''def finish(reporter, triple, as_json=False, payload=None):
    """Печатает финальную тройку и завершает процесс её кодом."""''',
        '''def finish(reporter, triple, as_json=False, payload=None):
    """Печатает финальную тройку и завершает процесс её кодом."""
    if triple.category == verdict_module.CATEGORY_HARNESS:
        triple = verdict_module.holder(
            verdict_module.CATEGORY_RED, verdict_module.CASE_CAPABILITY_MISSING)''',
    ),
    "blind-diagnostic": (
        "    if actual_triple.diagnostic != assertion.diagnostic:",
        "    if False and actual_triple.diagnostic != assertion.diagnostic:",
    ),
    "blind-exit": (
        "    if actual_triple.exit_code != assertion.exit_code:",
        "    if False and actual_triple.exit_code != assertion.exit_code:",
    ),
    "blind-delta": (
        "        if len(differences) != 1:",
        "        if False and len(differences) != 1:",
    ),
    "unpinned-cap": (
        '  env KACHO_CG_SUT="$ABSENT_SUT" python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet',
        '  python3 "$DRIVER" --case SDD-1-BOOT-01 --quiet',
    ),
    "allow-stub": (
        '        if stub is not None and case_id not in STUB_PERMITTED_CASES:',
        '        if False and stub is not None and case_id not in STUB_PERMITTED_CASES:',
    ),
}
old, new = edits[mode]
if old is not None:
    target = path
    if mode == "unpinned-cap":
        # Предмет этой инъекции — сам prove.sh: страж класса обязан уметь упасть.
        target = tmp + "/tests/selfcheck/prove.sh"
        source = open(target, encoding="utf-8").read()
    if mode == "allow-stub":
        target = tmp + "/tests/caselib/fixture.py"
        source = open(target, encoding="utf-8").read()
        old = old.strip()
        new = new.strip()
        old = "    " + old
        new = "    " + new
    assert old in source, (mode, old[:60])
    source = source.replace(old, new, 1)
    open(target, "w", encoding="utf-8").write(source)
PY

  local out failed
  out="$(KACHO_CG_ACCEPTANCE="$ROOT/docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md" \
        KACHO_CG_TESTDATA="$tmp/tests/testdata" \
        bash "$tmp/tests/selfcheck/prove.sh" 2>&1)"
  failed="$(printf '%s\n' "$out" | sed -n 's/^утверждений: [0-9]* · прошло: [0-9]* · провалено: \([0-9]*\)$/\1/p')"

  TOTAL=$((TOTAL + 1))
  local ok=1
  [ "$failed" = "$want_failed" ] || ok=0
  if [ -n "$want_named" ]; then
    printf '%s\n' "$out" | grep -q "FAIL $want_named" || ok=0
  fi
  # Находка, называющая симптом вместо причины, посылает читателя искать не там,
  # поэтому инъекция сверяет и ТЕКСТ отказа, а не только его наличие.
  if [ -n "$want_phrase" ]; then
    printf '%s\n' "$out" | grep -q -- "$want_phrase" || ok=0
  fi
  if [ "$ok" = "1" ]; then
    GOOD=$((GOOD + 1))
    printf '  OK   %-46s провалено %s\n' "$label" "$failed"
  else
    printf '  FAIL %-46s провалено %s (ждали %s, ключевое «%s»)\n' \
      "$label" "$failed" "$want_failed" "$want_named"
    printf '%s\n' "$out" | grep '^  FAIL' | sed 's/^/         /'
  fi
  rm -rf "$tmp"
}

echo "=== инъекции в pre-RED driver ==="
run_case_of_injection "КОНТРОЛЬ: дефекта нет"                 none              0  ""
run_case_of_injection "harness маскируется под capability RED" mask-harness      11 "B1"
run_case_of_injection "компаратор слеп к diagnostic"           blind-diagnostic  2  "F3"
run_case_of_injection "компаратор слеп к exit"                 blind-exit        2  "F4"
run_case_of_injection "проверка one-fact delta отключена"      blind-delta       1  "C1"
run_case_of_injection "stub разрешён любому кейсу"             allow-stub        1  "D1"
run_case_of_injection "ожидание CAP_MISSING без seam-пина" unpinned-cap 1 "A1" "не наводит seam"

echo
echo "=== перепись инъекций ==="
echo "инъекций: $TOTAL · с ожидаемым исходом: $GOOD"
[ "$TOTAL" = "$GOOD" ] || exit 1
exit 0
