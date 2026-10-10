#!/usr/bin/env python3
"""ci_suites — какое задание конвейера исполняет какой набор проверок. ЕДИНСТВЕННЫЙ ответ
для всех, кто его спрашивает: `scripts/suites-gate/check-04-ci-calls-every-suite.py`
судит им дерево, `scripts/change-graph-gate/lanes.py` (`check-03`) — дешёвую полосу и
доказательство контура, `scripts/lib/run-suites.sh --job` — исполняет своё задание и
отказывается, пока разметка не покрывает дерево.

ЗАЧЕМ РАЗМЕТКА, А НЕ ОДНО ЗАДАНИЕ НА ВСЕ НАБОРЫ (возврат по #816). Имя контекста
конвейера — `name:` задания, а защита `main` требует контексты ПОИМЁННО. Одно
задание на все наборы производит один контекст, и обязательные контексты наборов не
появляются никогда: слияние встаёт. Задание на набор с поимённым вызовом вернуло бы
выписанный перечень (ws#753: набор, заведённый в дереве, на стволе не исполнялся, и
это не краснело ничем). Поэтому принадлежность объявляет НАБОР — файлом
`scripts/<набор>/ci-job` с ключом задания (чтение — `scripts/lib/suites.py`), а
задание зовёт вывод перечня с `--job "$GITHUB_JOB"` и исполняет ровно те наборы, что
объявили его. Имя контекста живёт в одном месте — `name:` задания; принадлежность — в
одном месте — у набора; перечень наборов по-прежнему выводится из индекса.

ЧТО СЧИТАЕТСЯ ИСПОЛНЕНИЕМ НАБОРА — засчитанный вызов (`scripts/lib/ci_calls.py`):
  * вывода перечня без `--job` — исполняет каждый набор переписи;
  * вывода перечня с `--job <ключ>` — наборы, объявившие этот ключ; ключ обязан быть
    ключом СВОЕГО задания (`$GITHUB_JOB`, `${GITHUB_JOB}` либо он сам буквально):
    чужой исполнил бы наборы под именем чужого контекста, и такой вызов не засчитан;
  * поимённого `scripts/<набор>/run-all.sh`.
Доказательство набора исполняет вызов вывода с `--proofs`, исполняющий набор, либо
поимённый `scripts/<набор>/inject.sh`.

НАХОДКИ — каждая называет набор и причину: набор не исполняет никто, и почему
(объявления нет, а вывод зовётся только по заданиям; объявлено задание, которого в
конвейере нет; объявленное задание не зовёт вывод с `--job`); объявление не
разбирается; задание выбирает наборы, а ни один набор его не объявил; вызов не
засчитан; доказательства нет либо его не зовёт никто.

ЧЕГО НЕ УТВЕРЖДАЕТ. Что задание СОЗДАЁТ наборам предпосылки (клоны продукта, глубину
истории, разборщик), отсюда не видно: это видно только в прогоне, и там
`run-suites.sh --void-is-failure` роняет задание, если набор остался без предмета.

Вызов из bash: `python3 ci_suites.py members <корень> <задание>` — наборы задания
построчно; 1 — разметка не покрывает дерево (находки в stderr); 2 — предпосылки нет
(разборщика YAML, переписи, процессов).
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import ci_calls  # noqa: E402
import suites as S  # noqa: E402

DERIVED = "scripts/lib/run-suites.sh"
SELF_JOB = ("$GITHUB_JOB", "${GITHUB_JOB}")


class Unavailable(Exception):
    """Предпосылки нет — ответ не выводится, и это не «покрыто» и не «не покрыто»."""


class Run:
    """Засчитанный вызов вывода перечня: где, с доказательствами ли, по какому заданию."""

    def __init__(self, workflow, job, proofs, selector):
        self.workflow = workflow
        self.job = job
        self.proofs = proofs
        self.selector = selector

    @property
    def where(self):
        return "%s/%s" % (self.workflow, self.job)

    @property
    def label(self):
        return self.where + (" по заданию" if self.selector else "")


def selector(args, job):
    """(ключ выбранного задания либо None, причина отказа либо None)."""
    values = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--job":
            if i + 1 >= len(args):
                return None, "ключ --job без имени задания"
            values.append(args[i + 1])
            i += 2
            continue
        if a.startswith("--job="):
            values.append(a[len("--job="):])
        i += 1
    if not values:
        return None, None
    if len(values) > 1:
        return None, "ключ --job назван %d раза — задание у вызова одно" % len(values)
    v = values[0]
    if v in SELF_JOB or v == job:
        return job, None
    return None, ("--job %s в задании %s: наборы чужого задания исполнялись бы под "
                  "именем контекста этого" % (v, job))


def load_workflows(root):
    """([(путь, разобранный процесс)], [находки разбора]). Unavailable — без предпосылки."""
    try:
        import yaml
    except ImportError:
        raise Unavailable("разборщик YAML недоступен — объявление конвейера читать нечем")
    try:
        rels = S.tracked(root, ".github/workflows/*.yml", ".github/workflows/*.yaml")
    except S.CensusUnreadable as exc:
        raise Unavailable("перепись процессов не снята: %s" % exc)
    if not rels:
        raise Unavailable("файлов конвейера в %s нет — проверять нечего" % root)
    docs, findings = [], []
    for rel in rels:
        try:
            with open(os.path.join(root, rel), encoding="utf-8") as fh:
                docs.append((rel, yaml.safe_load(fh)))
        except (OSError, yaml.YAMLError) as exc:
            findings.append("%s — объявление не разбирается как YAML: %s" % (rel, exc))
    return docs, findings


class Coverage:
    """Кто исполняет каждый набор переписи и его доказательство."""

    def __init__(self, root, names, docs):
        self.names = list(names)
        self.workflows = [rel for rel, _ in docs]
        self.runs = []
        self.uncounted = []          # (скрипт, ci_calls.Call, причина)
        self.job_ids = set()
        self.steps = 0
        self.literal = {}
        self.literal_proof = {}
        self.declared = {}
        self.invalid = {}
        for s in self.names:
            job, why = S.declared_job(root, s)
            self.declared[s] = job
            if why:
                self.invalid[s] = why
        self.with_proof = [s for s in self.names if S.proof(root, s)]
        for rel, doc in docs:
            self._read(rel, doc)

    def _read(self, rel, doc):
        if not isinstance(doc, dict):
            return
        jobs = doc.get("jobs")
        if not isinstance(jobs, dict):
            return
        for jid, job in jobs.items():
            self.job_ids.add(str(jid))
            if isinstance(job, dict):
                self.steps += sum(1 for st in job.get("steps") or []
                                  if isinstance(st, dict) and isinstance(st.get("run"), str))
        for c in ci_calls.calls(doc, rel, DERIVED):
            if not c.counted:
                self.uncounted.append((DERIVED, c, c.why))
                continue
            sel, why = selector(c.args, c.job)
            if why:
                self.uncounted.append((DERIVED, c, why))
                continue
            self.runs.append(Run(rel, c.job, "--proofs" in c.args, sel))
        for s in self.names:
            for script, into in (("scripts/%s/run-all.sh" % s, self.literal),
                                 ("scripts/%s/inject.sh" % s, self.literal_proof)):
                for c in ci_calls.calls(doc, rel, script):
                    if c.counted:
                        into.setdefault(s, []).append(c.where)
                    else:
                        self.uncounted.append((script, c, c.why))

    def runs_of(self, s):
        """Засчитанные вызовы вывода перечня, исполняющие набор `s`."""
        job = self.declared.get(s)
        return [r for r in self.runs if r.selector is None or (job and r.selector == job)]

    def members(self, job):
        return [s for s in self.names if self.declared.get(s) == job]

    def run_called(self, s):
        return bool(self.runs_of(s) or self.literal.get(s))

    def proof_called(self, s):
        return bool(any(r.proofs for r in self.runs_of(s)) or self.literal_proof.get(s))

    def why_uncovered(self, s):
        """Почему набор `s` не исполняет ни одно задание."""
        job = self.declared.get(s)
        if s in self.invalid:
            return "объявление задания не разбирается (%s)" % self.invalid[s]
        if job is None:
            if any(r.selector for r in self.runs):
                return ("объявления scripts/%s/%s нет, а вывод перечня (%s) зовётся только "
                        "по заданиям" % (s, S.JOB_DECL, DERIVED))
            return "ни выводом перечня (%s), ни поимённо" % DERIVED
        if job not in self.job_ids:
            return ("объявлено задание %s (scripts/%s/%s), а такого задания в конвейере нет"
                    % (job, s, S.JOB_DECL))
        return ("объявлено задание %s, а оно не зовёт вывод перечня (%s) с --job — набор "
                "в нём не исполняется" % (job, DERIVED))

    def findings(self):
        out = []
        for script, c, why in self.uncounted:
            out.append("%s — вызов %s не засчитан: %s" % (c.where, script, why))
        for s in self.names:
            if not self.run_called(s):
                out.append("набор %s есть в дереве (scripts/%s/run-all.sh), а конвейер его "
                           "не зовёт — %s" % (s, s, self.why_uncovered(s)))
            elif s in self.invalid:
                out.append(self.invalid[s])
        declared = set(j for j in self.declared.values() if j)
        for r in self.runs:
            if r.selector and r.selector not in declared:
                out.append("%s зовёт вывод перечня по заданию %s, а ни один набор его не "
                           "объявил — задание судило бы пустоту" % (r.where, r.selector))
        for s in self.names:
            if s not in self.with_proof:
                out.append("у набора %s нет доказательства scripts/%s/inject.sh — способность "
                           "его проверок упасть не доказывает ничто" % (s, s))
            elif not self.proof_called(s):
                out.append("доказательство набора %s (scripts/%s/inject.sh) конвейер не зовёт "
                           "— ни выводом перечня с --proofs, ни поимённо: его поломку увидит "
                           "только ручной вызов" % (s, s))
        return out


def coverage(root):
    """Coverage дерева `root`; Unavailable без предпосылки. Находки разбора — в `.parse`."""
    try:
        names = S.suites(root)
    except S.CensusUnreadable as exc:
        raise Unavailable("перепись наборов не снята: %s" % exc)
    if not names:
        raise Unavailable("наборов scripts/*/run-all.sh в %s нет — размечать нечего" % root)
    docs, parse = load_workflows(root)
    cov = Coverage(root, names, docs)
    cov.parse = parse
    return cov


def main(argv):
    if len(argv) != 4 or argv[1] != "members":
        print("использование: ci_suites.py members <корень> <задание>", file=sys.stderr)
        return 2
    root, job = argv[2], argv[3]
    try:
        cov = coverage(root)
    except Unavailable as exc:
        print("[VOID] ci_suites — %s" % exc, file=sys.stderr)
        return 2
    findings = cov.parse + cov.findings()
    if findings:
        for f in findings:
            print("  находка: %s" % f, file=sys.stderr)
        print("[FAIL] ci_suites — разметка наборов по заданиям не покрывает дерево: находок %d "
              "(наборов в переписи %d)" % (len(findings), len(cov.names)), file=sys.stderr)
        return 1
    for s in cov.members(job):
        print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
