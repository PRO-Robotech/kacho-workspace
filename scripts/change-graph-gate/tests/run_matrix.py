#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Прогон всей матрицы через НАСТОЯЩУЮ matrix command, по кейсу на процесс.

Прогонщик не воспроизводит логику driver'а и не импортирует его: он вызывает ту
же команду, что названа в §14 приёмки. Второй путь исполнения разошёлся бы с
первым молча — и разошёлся бы там, где это не видно.

Исходов три, и третий не вычитается из вердикта:
    exit 0 — все кейсы дали ожидаемый initial holder
    exit 1 — хотя бы один дал НЕ его
    exit 2 — прогон беспредметен (кейсов ноль)
"""

import collections
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from caselib import spec as spec_module  # noqa: E402

EXPECTED_PHASE_INITIAL = "initial"
EXPECTED_PHASE_FINAL = "final"

# Перечень расхождений усекается, и обрезка НАЗЫВАЕТСЯ строкой переписи. Число
# над перечнем верно, а конец списка от обрезки читателем не отличается: грепнув
# вывод и не найдя своего кейса, он принимает артефакт обрезки за факт. Это тот
# же класс, что «tail уничтожает имя падения» — вердикт остаётся, разбор
# невозможен.
MISMATCH_LIST_CAP = 20

# Поломки harness НЕ усекаются, и это решение, а не недосмотр. Поломка — третья
# категория исхода: вердикта нет ни у одного такого кейса, а перечень здесь
# остаётся единственным местом, где виден их состав. Обрезать его значило бы
# скрыть часть кейсов, оставшихся без вердикта, при верном числе над ними —
# ровно то, чего третья категория не терпит. Верхняя граница перечня и так
# конечна: она равна числу кейсов матрицы.
HARNESS_LIST_CAP = None


def mismatch_row(row):
    """Строка перечня расхождений."""
    case_id, expected_line, actual_line, code = row
    return (
        "  РАСХОЖДЕНИЕ %s: ждали %r, получили %r (код %d)\n"
        % (case_id, expected_line, actual_line, code)
    )


def harness_row(row):
    """Строка перечня поломок harness."""
    case_id, actual_line = row
    return "  HARNESS %s: %s\n" % (case_id, actual_line)


def render_listing(rows, cap, render_row, subject):
    """Строки перечня плюс перепись «<предмет> показано X из Y».

    Перепись печатается ровно тогда, когда перечень НЕПУСТ: у пустого полнота
    уже названа числом выше («не совпало с ожидаемым: 0»), и строка
    «показано 0 из 0» была бы лишней на каждом зелёном прогоне. Как только
    читать есть что — читателю сказано, всё ли он видит.

    Предмет назван в самой строке, потому что перечней два подряд: голое
    «показано X из Y» дважды не отличило бы расхождения от поломок harness.

    `cap is None` означает «не усекать» — см. HARNESS_LIST_CAP.
    """
    shown = rows if cap is None else rows[:cap]
    lines = [render_row(row) for row in shown]
    if rows:
        lines.append("  %s показано %d из %d\n" % (subject, len(shown), len(rows)))
    return lines


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else EXPECTED_PHASE_INITIAL
    registry, order = spec_module.load_registry()
    if not order:
        sys.stdout.write("прогон беспредметен: кейсов ноль\n")
        return 2

    key = "expected_%s_holder" % phase
    counts = collections.Counter()
    mismatched = []
    harness = []

    for case_id in order:
        entry = registry[case_id]
        expected = entry[key]
        expected_line = "%s · %s · exit %d" % (
            expected["category"], expected["diagnostic"], expected["exit"],
        )
        completed = subprocess.run(
            [sys.executable, os.path.join(HERE, "run_case.py"),
             "--case", case_id, "--quiet"],
            capture_output=True, text=True,
        )
        lines = [line for line in completed.stdout.split("\n") if line.strip()]
        actual_line = lines[-1] if lines else "(без вывода)"
        counts[actual_line] += 1
        if completed.returncode == 40:
            harness.append((case_id, actual_line))
        elif actual_line != expected_line or completed.returncode != expected["exit"]:
            mismatched.append((case_id, expected_line, actual_line, completed.returncode))

    total = len(order)
    sys.stdout.write("\n=== перепись прогона (фаза: %s) ===\n" % phase)
    sys.stdout.write("кейсов исполнено: %d из %d\n" % (sum(counts.values()), total))
    for line, number in counts.most_common():
        sys.stdout.write("  %4d  %s\n" % (number, line))
    sys.stdout.write("не совпало с ожидаемым: %d\n" % len(mismatched))
    sys.stdout.write("поломок harness (exit 40, verdict НЕ выдан): %d\n" % len(harness))

    for line in render_listing(
            mismatched, MISMATCH_LIST_CAP, mismatch_row, "расхождений"):
        sys.stdout.write(line)
    for line in render_listing(
            harness, HARNESS_LIST_CAP, harness_row, "поломок harness"):
        sys.stdout.write(line)

    return 0 if not mismatched and not harness else 1


if __name__ == "__main__":
    raise SystemExit(main())
