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

ЧИТАЕТСЯ ИСПОЛНЯЕМОЕ, А НЕ ТЕКСТ. Объявление разбирается как YAML, у блока `run:`
снимаются комментарии (`scripts/lib/shellcode.py`): имя скрипта стоит и в
объяснении рядом с шагом, и предикат по подстроке зеленел бы на комментарии.

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
import shellcode  # noqa: E402

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
        for job_id, job in jobs.items():
            if not isinstance(job, dict):
                continue
            for step in job.get("steps") or []:
                if not isinstance(step, dict) or not isinstance(step.get("run"), str):
                    continue
                steps += 1
                code = shellcode.code_text(step["run"])
                where = "%s/%s" % (rel, job_id)
                for line in code.split("\n"):
                    if DERIVED in line:
                        derived_by.append(where)
                        if "--proofs" in line.split(DERIVED, 1)[1].split():
                            derived_proofs.append(where)
                for s in names:
                    if "scripts/%s/run-all.sh" % s in code:
                        literal.setdefault(s, []).append(where)
                    if "scripts/%s/inject.sh" % s in code:
                        literal_proof.setdefault(s, []).append(where)

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
                "перечня: %s (с --proofs: %s); поимённо: %s"
                % (len(names), len(names) - len(missing), len(missing),
                   len(with_proof) - len(proof_missing), len(with_proof), len(workflows), steps,
                   ", ".join(derived_by) or "нет", ", ".join(derived_proofs) or "нет",
                   ", ".join(sorted(literal)) or "нет"))
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
