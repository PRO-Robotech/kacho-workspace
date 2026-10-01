#!/usr/bin/env python3
"""check-04 — конвейер зовёт КАЖДЫЙ набор проверок дерева и его доказательство.

ЧТО УТВЕРЖДАЕТ (ws#753). Каждый набор `scripts/<имя>/run-all.sh`, который есть в
дереве, исполняется хотя бы одним заданием конвейера: либо выводом перечня
(`scripts/lib/run-suites.sh` — набор попадает туда сам), либо поимённым вызовом.
Расхождение «наборов в дереве × вызвано» печатается числом, и каждый невызванный
набор называется по имени.

ВТОРАЯ ОСЬ (ws#817) — ДОКАЗАТЕЛЬСТВО. У каждого набора есть `inject.sh`, и конвейер
его зовёт: выводом перечня с ключом `--proofs` либо поимённо. Способность набора
упасть иначе не доказывает ничто, кроме ручного вызова, и поломку самого
доказательства не видит никто (так было у crossrepo-gate: прогон хук исполнял,
доказательство — никто). Набор без `inject.sh` — находка той же оси.

ЦЕНА. Хук отправки выводил перечень глобом и видел все наборы; конвейер выписывал
их от руки и видел выписанные. Набор, заведённый в дереве, на стволе не исполнялся,
и это не краснело ничем: не выполнено не значит зелено, но выглядит так же.

ТРЕТЬЯ ОСЬ (возврат по #816) — ЗАДАНИЕ, ЧЬЁ ИМЯ НЕСЁТ ВЕРДИКТ НАБОРА. Защита `main`
требует контексты поимённо, а имя контекста — `name:` задания; поэтому вывод перечня
зовётся по заданиям (`--job "$GITHUB_JOB"`), и задание исполняет наборы, объявившие
его файлом `scripts/<набор>/ci-job`. Набор без объявления при выводе по заданиям,
объявление задания, которого нет, задание, не зовущее вывод с `--job`, `--job` с
чужим ключом и задание, которое не объявил ни один набор, — находки с причиной.
Ответ «кто исполняет набор» — один, `scripts/lib/ci_suites.py`: тем же ответом
`run-suites.sh --job` отказывается исполнять задание, пока разметка не покрывает
дерево, и `change-graph-gate/check-03` судит дешёвую полосу контура.

ЧИТАЕТСЯ ИСПОЛНЯЕМОЕ, А НЕ ТЕКСТ. Объявление разбирается как YAML, вызов узнаёт
общий распознаватель `scripts/lib/ci_calls.py` — тот же, что у
`change-graph-gate/check-03` (второго дома у него нет); кто какой набор исполняет —
`scripts/lib/ci_suites.py` поверх него. Вызов — путь в положении
команды, а не в строке `echo` и не в комментарии; засчитывается он, только если его
вердикт доходит до задания: не `|| …`, не звено трубы, не фон, не условие, шаг с
errexit (либо вызов — последняя команда шага), у задания и шага нет `if:` и
`continue-on-error`. Незасчитанный вызов — находка с причиной (круг 1: `echo "…"`,
`|| true`, `continue-on-error: true` и `if: false` проходили эту проверку при
«вызвано 8 из 8»).

ЧЕГО НЕ УТВЕРЖДАЕТ — названо прямо. Что задание, зовущее вывод, СОЗДАЁТ наборам
предпосылки (клоны продукта, глубину истории, разборщик), эта проверка не судит:
это видно только в прогоне конвейера, и там `run-suites.sh --void-is-failure`
роняет задание, если какой-то набор остался без предмета.

Коды: 0 — каждый набор дерева вызван; 1 — находка; 2 — наборов нет, процессов нет
либо разборщик YAML недоступен.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import ci_suites  # noqa: E402

NAME = "check-04-ci-calls-every-suite"


def main():
    ws = _lib.root(__file__)
    names, _ = _lib.suite_census(NAME, ws)
    if not names:
        _lib.void(NAME, "наборов scripts/*/run-all.sh в %s нет — сверять конвейер не с чем" % ws)
        return 2
    try:
        docs, parse = ci_suites.load_workflows(ws)
    except ci_suites.Unavailable as exc:
        _lib.void(NAME, str(exc))
        return 2

    cov = ci_suites.Coverage(ws, names, docs)
    findings = parse + cov.findings()
    missing = [s for s in names if not cov.run_called(s)]
    proof_missing = [s for s in cov.with_proof if not cov.proof_called(s)]
    declared = [s for s in names if cov.declared.get(s)]

    _lib.census(NAME, "наборов в дереве %d; вызвано конвейером %d; не вызвано %d; "
                "доказательств вызвано %d из %d — процессов %d, шагов с `run:` %d; вывод "
                "перечня: %s (с --proofs: %s); поимённо: %s; объявили задание %d из %d "
                "наборов; вызовов не засчитано %d"
                % (len(names), len(names) - len(missing), len(missing),
                   len(cov.with_proof) - len(proof_missing), len(cov.with_proof),
                   len(cov.workflows), cov.steps,
                   ", ".join(r.label for r in cov.runs) or "нет",
                   ", ".join(r.label for r in cov.runs if r.proofs) or "нет",
                   ", ".join(sorted(cov.literal)) or "нет",
                   len(declared), len(names), len(cov.uncounted)))
    if cov.steps == 0:
        _lib.void(NAME, "ни одного шага `run:` не разобрано — сверять не с чем")
        return 2
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "находок %d; наборов дерева, которых конвейер не исполняет: %d"
                  % (len(findings), len(missing)))
        return 1
    _lib.passed(NAME, "все %d наборов дерева и их доказательства исполняются конвейером"
                % len(names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
