#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Доказательство, что долгий прогон inject.py НЕ МОЛЧИТ.

`inject.py` идёт десятки минут: инъекций три с лишним десятка, каждая — полный
прогон `prove.py`. Пока он молчит, «идёт» и «повис» неотличимы, и молчание
провоцирует снять прогон своим пределом — а снятый прогон даёт третью категорию
исхода («не выполнилось»), которую легко прочесть как красное.

Проверяются ДВА свойства, и второе не следует из первого:

* **сброс буфера.** Вывод почти всегда перенаправляют, а у неинтерактивного
  stdout буферизация блочная: без сброса первые ~8 КБ строк сидят в буфере
  невидимо, сколько бы их ни написали. Поэтому проба читает файл, а не терминал;
* **объявление ДО прогона.** Строка, напечатанная после, о зависшей инъекции не
  скажет ничего — её просто не будет. Проверяется тем, что объявление уже в
  файле, а вердикт того же прогона — ещё нет.

Каждое утверждение доказано инъекцией: рядом стоит дерево, где свойство снято, и
проба обязана на нём покраснеть. Без этой половины она ловила бы «процесс
запустился», а не «прогон себя показывает».

Окно ожидания здесь — сам предмет утверждения, а не способ дождаться условия:
проба спрашивает «видно ли объявление РАНЬШЕ, чем завершился прогон», и
измеряется это временем by construction.

    python3 scripts/change-graph-gate/selftest/prove_run_progress.py

Исходов три: 0 — все утверждения прошли; 1 — есть провалившееся; 2 — проба
беспредметна (утверждений ноль).
"""

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GATE_DIR = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

import inject as inject_module  # noqa: E402

# Окно, внутри которого ни один прогон prove.py завершиться не может: он идёт
# порядка двадцати секунд. Всё, что видно в файле раньше, напечатано ДО прогона.
EARLY_WINDOW_SECONDS = 4.0
# Бюджеты ожидания. Объявление первой инъекции приходит после контрольного
# прогона; в дереве с перенесённым объявлением — ещё через один прогон.
PROGRESS_BUDGET_SECONDS = 120.0
LATE_PROGRESS_BUDGET_SECONDS = 240.0

# Снятие сброса буфера: строки пишутся, но остаются невидимы.
EDIT_NO_FLUSH = [(
    "    sys.stdout.write(text)\n    sys.stdout.flush()\n",
    "    sys.stdout.write(text)\n",
)]
# Объявление контрольного прогона снято вовсе.
EDIT_NO_CONTROL_ANNOUNCE = [(
    "        say(CONTROL_LINE)\n",
    "        pass  # инъекция: объявление контрольного прогона снято\n",
)]
# Объявление контрольного прогона печатается ПОСЛЕ него.
EDIT_LATE_CONTROL_ANNOUNCE = [(
    "        say(CONTROL_LINE)\n"
    "        started = time.monotonic()\n"
    "        code, failed, control_passed = run_prove(control_root)\n",
    "        started = time.monotonic()\n"
    "        code, failed, control_passed = run_prove(control_root)\n"
    "        say(CONTROL_LINE)\n",
)]
# Объявление инъекции печатается ПОСЛЕ её прогона.
EDIT_LATE_LOOP_ANNOUNCE = [
    (
        "            say(PROGRESS_LINE % (index + 1, len(selected), name))\n"
        "            started = time.monotonic()\n",
        "            started = time.monotonic()\n",
    ),
    (
        "            code, failed, _ = run_prove(root)\n"
        "            seconds = time.monotonic() - started\n",
        "            code, failed, _ = run_prove(root)\n"
        "            seconds = time.monotonic() - started\n"
        "            say(PROGRESS_LINE % (index + 1, len(selected), name))\n",
    ),
]


class Ledger(object):
    """Счёт утверждений: перепись отличает «ноль находок» от «ноль проверенного»."""

    def __init__(self):
        self.passed = 0
        self.failed = 0

    def ok(self, name):
        self.passed += 1
        sys.stdout.write("  OK   %s\n" % name)
        sys.stdout.flush()

    def bad(self, name, detail):
        self.failed += 1
        sys.stdout.write("  FAIL %s\n       %s\n" % (name, detail))
        sys.stdout.flush()

    def check(self, name, condition, detail):
        if condition:
            self.ok(name)
        else:
            self.bad(name, detail)

    @property
    def total(self):
        return self.passed + self.failed


def prepare_copy(work, name, edits):
    """Копия дерева гейта с подстановками в selftest/inject.py.

    Дерево проб подключается символической ссылкой и только чтением: fixtures
    принадлежат pre-RED diff, и трогать их нельзя даже во временной копии.
    Возвращает (путь, несостоявшийся образец): образец, не найденный в тексте,
    дал бы «зелёную» инъекцию на неизменённом дереве — доказательство наоборот.
    """
    destination = os.path.join(work, name)
    shutil.copytree(
        GATE_DIR, destination,
        ignore=shutil.ignore_patterns("__pycache__", "tests"),
    )
    os.symlink(os.path.join(GATE_DIR, "tests"), os.path.join(destination, "tests"))
    if not edits:
        return destination, None
    target = os.path.join(destination, "selftest", "inject.py")
    with open(target, encoding="utf-8") as handle:
        source = handle.read()
    for needle, replacement in edits:
        if needle not in source:
            return destination, needle
        source = source.replace(needle, replacement, 1)
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(source)
    return destination, None


def launch(root, selector, out_path):
    """Запускает inject.py, направив вывод в ФАЙЛ.

    Файл, а не терминал: предмет утверждения — блочная буферизация, которой у
    терминала нет. И `PYTHONUNBUFFERED` снимается из окружения — с ней зелёным
    оказалось бы и дерево без сброса, то есть проба измеряла бы окружение.
    """
    environment = dict(os.environ)
    environment.pop("PYTHONUNBUFFERED", None)
    handle = open(out_path, "w", encoding="utf-8")
    process = subprocess.Popen(
        [sys.executable, os.path.join(root, "selftest", "inject.py"), selector],
        stdout=handle, stderr=subprocess.STDOUT, env=environment,
        start_new_session=True,
    )
    return process, handle


def stop(process, handle):
    """Снимает прогон вместе с его потомками: prove.py живёт своим процессом."""
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        pass
    try:
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        pass
    handle.close()


def read(out_path):
    with open(out_path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def wait_for(out_path, needle, budget):
    """Ждёт появления строки в файле; возвращает текст на момент появления."""
    deadline = time.monotonic() + budget
    while time.monotonic() < deadline:
        text = read(out_path)
        if needle in text:
            return text
        time.sleep(0.5)
    return None


def sleep_early_window():
    time.sleep(EARLY_WINDOW_SECONDS)


def verdict_of(name, text):
    """Строка вердикта прогона: и зелёная, и красная — обе суть «прогон кончился»."""
    return ("  OK   %s" % name) in text or ("  FAIL %s" % name) in text


def main():
    ledger = Ledger()

    # P0 стоит первым НАМЕРЕННО. Без него отсутствие самих строк хода прогона
    # выходило бы трассировкой разбора, а трассировка — не вердикт: читатель не
    # отличит «свойства нет» от «проба сломалась». Здесь это названо признаком.
    declared = [
        name for name in ("HEADER_LINE", "CONTROL_LINE", "PROGRESS_LINE", "say")
        if hasattr(inject_module, name)
    ]
    ledger.check(
        "P0 inject.py объявляет строки хода прогона и печатник со сбросом",
        len(declared) == 4,
        "объявлено %d из 4: %s — свойства нет вовсе, дальше проверять нечего"
        % (len(declared), declared),
    )
    if len(declared) != 4:
        sys.stdout.write("\n=== перепись проб видимости прогона ===\n")
        sys.stdout.write(
            "утверждений: %d · прошло: %d · провалено: %d\n"
            % (ledger.total, ledger.passed, ledger.failed)
        )
        return 1

    selector = inject_module.INJECTIONS[0][0]
    chosen = [entry for entry in inject_module.INJECTIONS if selector in entry[0]]
    header = inject_module.HEADER_LINE % (len(inject_module.INJECTIONS), len(chosen))
    control_line = inject_module.CONTROL_LINE
    progress_line = inject_module.PROGRESS_LINE % (1, len(chosen), selector)

    with tempfile.TemporaryDirectory(prefix="cg-progress-") as work:
        # --- P1/P5: нетронутое дерево показывает себя, пока прогон ИДЁТ -------
        out = os.path.join(work, "clean.txt")
        process, handle = launch(GATE_DIR, selector, out)
        try:
            sleep_early_window()
            early = read(out)
            ledger.check(
                "P1 шапка видна, пока ни один прогон не завершился",
                header in early,
                "за %.0f с в файле нет шапки; прочитано %d байт"
                % (EARLY_WINDOW_SECONDS, len(early)),
            )
            ledger.check(
                "P2 объявление контрольного прогона напечатано ДО него",
                control_line in early and not verdict_of("контроль", early),
                "объявление %r; вердикт контроля %r"
                % (control_line in early, verdict_of("контроль", early)),
            )
            text = wait_for(out, progress_line, PROGRESS_BUDGET_SECONDS)
            ledger.check(
                "P3 объявление инъекции напечатано ДО её прогона",
                text is not None and not verdict_of(selector, text),
                "объявление за %.0f с не появилось"
                % PROGRESS_BUDGET_SECONDS if text is None
                else "объявление пришло уже с вердиктом — то есть после прогона",
            )
        finally:
            stop(process, handle)

        # --- инъекции: каждое утверждение обязано УМЕТЬ покраснеть ------------
        for name, edits, out_name, predicate, detail in (
            (
                "P1-инъекция сброс буфера снят -> шапки не видно",
                EDIT_NO_FLUSH, "no-flush.txt",
                lambda early: header not in early,
                "шапка видна и без сброса — проба измеряет не буферизацию",
            ),
            (
                "P2-инъекция объявление снято -> его не видно",
                EDIT_NO_CONTROL_ANNOUNCE, "no-announce.txt",
                lambda early: header in early and control_line not in early,
                "объявление видно при снятой строке — проба вакуумна",
            ),
            (
                "P2-инъекция объявление после прогона -> в окне его нет",
                EDIT_LATE_CONTROL_ANNOUNCE, "late-announce.txt",
                lambda early: header in early and control_line not in early,
                "объявление видно раньше прогона, хотя перенесено после него",
            ),
        ):
            root, missed = prepare_copy(work, out_name.replace(".txt", ""), edits)
            if missed is not None:
                ledger.bad(name, "подстановка не состоялась: образец %r не найден"
                                 % missed[:60])
                continue
            path = os.path.join(work, out_name)
            process, handle = launch(root, selector, path)
            try:
                sleep_early_window()
                early = read(path)
                ledger.check(name, predicate(early),
                             "%s (прочитано %d байт)" % (detail, len(early)))
            finally:
                stop(process, handle)

        # --- P3-инъекция: объявление инъекции перенесено ПОСЛЕ её прогона -----
        root, missed = prepare_copy(work, "late-loop", EDIT_LATE_LOOP_ANNOUNCE)
        name = "P3-инъекция объявление инъекции после прогона -> приходит с вердиктом"
        if missed is not None:
            ledger.bad(name, "подстановка не состоялась: образец %r не найден"
                             % missed[:60])
        else:
            path = os.path.join(work, "late-loop.txt")
            process, handle = launch(root, selector, path)
            try:
                text = wait_for(path, progress_line,
                                LATE_PROGRESS_BUDGET_SECONDS)
                ledger.check(
                    name,
                    text is not None and verdict_of(selector, text),
                    "объявление за %.0f с не появилось"
                    % LATE_PROGRESS_BUDGET_SECONDS if text is None
                    else "объявление пришло без вердикта, хотя перенесено после прогона",
                )
            finally:
                stop(process, handle)

    sys.stdout.write("\n=== перепись проб видимости прогона ===\n")
    sys.stdout.write(
        "утверждений: %d · прошло: %d · провалено: %d\n"
        % (ledger.total, ledger.passed, ledger.failed)
    )
    if ledger.total == 0:
        sys.stdout.write("проба беспредметна: утверждений ноль\n")
        return 2
    return 1 if ledger.failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
