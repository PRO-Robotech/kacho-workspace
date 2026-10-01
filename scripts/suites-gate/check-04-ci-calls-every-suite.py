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

ЧИТАЕТСЯ ИСПОЛНЯЕМОЕ, А НЕ ТЕКСТ. Объявление разбирается как YAML, вызов узнаёт
общий распознаватель `scripts/lib/ci_calls.py` — тот же, что у
`change-graph-gate/check-03` (второго дома у него нет). Вызов — путь в положении
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
import ci_calls  # noqa: E402

NAME = "check-04-ci-calls-every-suite"
DERIVED = "scripts/lib/run-suites.sh"


def main():
    ws = _lib.root(__file__)
    names, _ = _lib.suite_census(NAME, ws)
    if not names:
        _lib.void(NAME, "наборов scripts/*/run-all.sh в %s нет — сверять конвейер не с чем" % ws)
        return 2
    try:
        import yaml
    except ImportError:
        _lib.void(NAME, "разборщик YAML недоступен — объявление конвейера читать нечем")
        return 2
    try:
        workflows = _lib.S.tracked(ws, ".github/workflows/*.yml", ".github/workflows/*.yaml")
    except _lib.S.CensusUnreadable as exc:
        _lib.void(NAME, "перепись процессов не снята: %s" % exc)
        return 2
    if not workflows:
        _lib.void(NAME, "файлов конвейера в %s нет — проверять нечего" % ws)
        return 2

    findings = []
    derived_by = []
    derived_proofs = []
    literal = {}
    literal_proof = {}
    uncounted = []
    steps = 0
    for rel in workflows:
        try:
            with open(os.path.join(ws, rel), encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except (OSError, yaml.YAMLError) as exc:
            findings.append("%s — объявление не разбирается как YAML: %s" % (rel, exc))
            continue
        jobs = (doc or {}).get("jobs") if isinstance(doc, dict) else None
        if not isinstance(jobs, dict):
            continue
        for job in jobs.values():
            if isinstance(job, dict):
                steps += sum(1 for st in job.get("steps") or []
                             if isinstance(st, dict) and isinstance(st.get("run"), str))
        for c in ci_calls.calls(doc, rel, DERIVED):
            if not c.counted:
                uncounted.append((DERIVED, c))
                continue
            derived_by.append(c.where)
            if "--proofs" in c.args:
                derived_proofs.append(c.where)
        for s in names:
            for script, into in (("scripts/%s/run-all.sh" % s, literal),
                                 ("scripts/%s/inject.sh" % s, literal_proof)):
                for c in ci_calls.calls(doc, rel, script):
                    if c.counted:
                        into.setdefault(s, []).append(c.where)
                    else:
                        uncounted.append((script, c))
    for script, c in uncounted:
        findings.append("%s — вызов %s не засчитан: %s" % (c.where, script, c.why))

    called = set(names) if derived_by else set(literal)
    missing = [s for s in names if s not in called]
    for s in missing:
        findings.append("набор %s есть в дереве (scripts/%s/run-all.sh), а конвейер его не "
                        "зовёт — ни выводом перечня (%s), ни поимённо" % (s, s, DERIVED))

    with_proof = [s for s in names if _lib.S.proof(ws, s)]
    for s in names:
        if s not in with_proof:
            findings.append("у набора %s нет доказательства scripts/%s/inject.sh — способность "
                            "его проверок упасть не доказывает ничто" % (s, s))
    proof_called = set(with_proof) if derived_proofs else set(literal_proof)
    proof_missing = [s for s in with_proof if s not in proof_called]
    for s in proof_missing:
        findings.append("доказательство набора %s (scripts/%s/inject.sh) конвейер не зовёт — ни "
                        "выводом перечня с --proofs, ни поимённо: его поломку увидит только "
                        "ручной вызов" % (s, s))

    _lib.census(NAME, "наборов в дереве %d; вызвано конвейером %d; не вызвано %d; "
                "доказательств вызвано %d из %d — процессов %d, шагов с `run:` %d; вывод "
                "перечня: %s (с --proofs: %s); поимённо: %s; вызовов не засчитано %d"
                % (len(names), len(names) - len(missing), len(missing),
                   len(with_proof) - len(proof_missing), len(with_proof), len(workflows), steps,
                   ", ".join(derived_by) or "нет", ", ".join(derived_proofs) or "нет",
                   ", ".join(sorted(literal)) or "нет", len(uncounted)))
    if steps == 0:
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
