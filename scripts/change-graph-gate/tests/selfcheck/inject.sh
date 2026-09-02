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
  local label="$1" mode="$2" want_failed="$3" want_named="$4"
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
    "allow-stub": (
        '        if stub is not None and case_id not in STUB_PERMITTED_CASES:',
        '        if False and stub is not None and case_id not in STUB_PERMITTED_CASES:',
    ),
    # Три инъекции ниже возвращают дефект секции J: перечень под верным числом
    # обрывается молча. Предмет у каждой свой, поэтому и падать они обязаны
    # порознь — иначе краснота приходила бы от соседа, а утверждение секции
    # оставалось бы вакуумным.
    "truncate-harness": (
        "HARNESS_LIST_CAP = None",
        "HARNESS_LIST_CAP = 20",
    ),
    "silent-listing": (
        "    if rows:\n        lines.append(",
        "    if False:\n        lines.append(",
    ),
    "stray-listing-print": (
        "    for line in render_listing(\n"
        "            mismatched, MISMATCH_LIST_CAP, mismatch_row, \"расхождений\"):\n"
        "        sys.stdout.write(line)",
        "    for case_id, expected_line, actual_line, code in mismatched[:20]:\n"
        "        sys.stdout.write(\n"
        "            \"  РАСХОЖДЕНИЕ %s: ждали %r, получили %r (код %d)\\n\"\n"
        "            % (case_id, expected_line, actual_line, code)\n"
        "        )",
    ),
}
# Файл, в который бьёт инъекция. Умолчание — driver; секция J судит прогонщик
# матрицы, поэтому её цели названы здесь явно, а не угаданы по имени режима.
targets = {
    "allow-stub": "/tests/caselib/fixture.py",
    "truncate-harness": "/tests/run_matrix.py",
    "silent-listing": "/tests/run_matrix.py",
    "stray-listing-print": "/tests/run_matrix.py",
}
old, new = edits[mode]
if old is not None:
    target = path
    if mode in targets:
        target = tmp + targets[mode]
        source = open(target, encoding="utf-8").read()
    if mode == "allow-stub":
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

# Секция J: перечень обязан называть свою полноту, поломки harness — не усекаться.
run_case_of_injection "поломки harness снова усекаются"        truncate-harness    3 "J3 перечень поломок harness НЕ усекается"
run_case_of_injection "перечень молчит о своей полноте"        silent-listing      3 "J1 усечённый перечень расхождений называет обрезку"
run_case_of_injection "перечень печатается мимо печатника"     stray-listing-print 1 "J5 в main перечни печатает только печатник"

echo
echo "=== перепись инъекций ==="
echo "инъекций: $TOTAL · с ожидаемым исходом: $GOOD"
[ "$TOTAL" = "$GOOD" ] || exit 1
exit 0
