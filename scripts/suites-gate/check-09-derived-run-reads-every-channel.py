#!/usr/bin/env python3
"""check-09 — вывод перечня наборов (`scripts/lib/run-suites.sh`) не выносит зелёного, которого не было.

ЧТО УТВЕРЖДАЕТ (ws#753, ws#762 п.1). Задания наборов конвейера целиком стоят на
одном файле — `scripts/lib/run-suites.sh`. Его вердикт обязан краснеть (код 1), когда:
  * набор без предмета, а вызов с `--void-is-failure` (в конвейере предпосылки создаёт
    само задание, и их отсутствие — поломка);
  * набор не отчитался строкой переписи (второй канал помимо кода);
  * строка переписи расходится с кодом набора — «исполнено 0» при нуле, код 0 при
    провалах, сумма исходов не равна исполненному;
  * доказательство набора (`inject.sh`) красное либо его нет, а вызов с `--proofs`;
  * набор красный;
  * перепись наборов пуста — пустой обход был бы зелёным при снятых проверках;
  * ПО ЗАДАНИЮ (`--job`, возврат по #816): набор объявил задание, которого в конвейере
    нет; набор не объявил задания; объявленное задание лишилось шага вывода — набор не
    исполняет никто, и краснеет КАЖДОЕ задание, а не только потерявшее его; ни один
    набор не объявил выбранное задание — пустой выбор.
Законные близнецы: те же наборы исправными — 0; беспредметный набор БЕЗ
`--void-is-failure` — 2 (так его читает хук отправки); красное доказательство без
`--proofs` — 0 (доказательство не исполнялось и вердикта не несёт). Близнецы выбора
по заданию отвечают тем же нулём: оба набора объявили одно задание; красный набор
объявил ДРУГОЕ задание и в выбранном не исполняется (выбор сужает перечень).

ЦЕНА, РАДИ КОТОРОЙ ПРОВЕРКА ЗАВЕДЕНА. `check-04` и `change-graph-gate/check-03` судят,
что конвейер ЗОВЁТ этот файл, — текст вызова. Что вызванный файл делает со своими
каналами, не держало ничто: составной мутант (беспредметность, неотчитавшийся набор,
красное доказательство и пустая перепись — все проглочены) выжил во всех
самопроверках, а конвейер на нём зеленел бы на любом из этих дефектов.

ПРОБА ПОВЕДЕНЧЕСКАЯ. В песочнице — отдельный git-репозиторий с КОПИЕЙ `scripts/lib/`
судимого дерева и синтетическими наборами `aaa-gate`, `bbb-gate` на общем прогонщике;
исполняется копия судимого `run-suites.sh`, читается её код. Каждый отрицательный
случай меняет РОВНО один факт против положительного контроля.

ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПЕРВЫМ. Вывод перечня, не отвечающий нулём на исправных
наборах `aaa-gate` и `bbb-gate` с исправными доказательствами, к остальным пробам
непригоден — они прошли бы
на нём тождественно. Такой исход — VOID, а не «доказано».

Пробам по заданию нужен разборщик YAML (разметку читает `scripts/lib/ci_suites.py`):
без него они не исполняются, и проверка, не найдя иных находок, отвечает «без
предмета», а не «доказано».

Коды: 0 — каждый канал читается; 1 — находка; 2 — вывода перечня в дереве нет,
положительный контроль сорван либо пробы по заданию без разборщика YAML.
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-09-derived-run-reads-every-channel"
DERIVED = "scripts/lib/run-suites.sh"

SHIM = ('#!/usr/bin/env bash\nset -uo pipefail\n'
        'here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
        '. "$here/../lib/suite-runner.sh"\nsuite_run "$here"\n')
GREEN = 'echo "осмотрено 1"\nexit 0\n'
VOIDED = 'echo "[VOID] сверять не с чем: файлов 0" >&2\nexit 2\n'
RED = 'echo "находок 1 из 1"\nexit 1\n'
PROOF_OK = '#!/usr/bin/env bash\necho "проб 1, провалов 0"\nexit 0\n'
PROOF_RED = '#!/usr/bin/env bash\necho "проб 1, провалов 1"\nexit 1\n'
# Прогонщик набора, который не пишет строку переписи: код есть, второго канала нет.
UNREPORTED = '#!/usr/bin/env bash\necho "осмотрено 1"\nexit 0\n'


def row_runner(n, ok, bad, void, rc):
    """Прогонщик, пишущий заданную строку переписи и выходящий заданным кодом."""
    return ('#!/usr/bin/env bash\nname="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" '
            '&& pwd)")"\necho "$name: рассмотрено проверок %d"\n'
            '[ -z "${SUITE_SUMMARY:-}" ] || printf \'%%s\\t%d\\t%d\\t%d\\t%d\\n\' "$name" '
            '>> "$SUITE_SUMMARY"\nexit %d\n' % (n, n, ok, bad, void, rc))


def workflow(*jobs):
    """Процесс песочницы: {задание: зовёт ли оно вывод перечня по заданию}."""
    out = "name: injected\non:\n  workflow_dispatch:\njobs:\n"
    for job, calls in jobs:
        out += ("  %s:\n    runs-on: ubuntu-latest\n    steps:\n      - run: %s\n"
                % (job, 'bash scripts/lib/run-suites.sh --proofs --void-is-failure --job "$GITHUB_JOB"'
                   if calls else "true"))
    return out


def world(ws, suites, decl=None, wf=None):
    """Песочница: {набор: (прогонщик, проверка либо None, доказательство либо None)};
    `decl` — {набор: объявленное задание}, `wf` — текст процесса конвейера."""
    box = tempfile.mkdtemp(prefix="derived-run.")
    subprocess.run(["git", "-C", box, "init", "-q"], check=True, env=_lib.clean_env())
    shutil.copytree(os.path.join(ws, "scripts", "lib"), os.path.join(box, "scripts", "lib"))
    for name, (runner, check, proof) in suites.items():
        d = os.path.join(box, "scripts", name)
        os.makedirs(d)
        with open(os.path.join(d, "run-all.sh"), "w", encoding="utf-8") as fh:
            fh.write(runner)
        if check is not None:
            with open(os.path.join(d, "check-01-probe.sh"), "w", encoding="utf-8") as fh:
                fh.write("#!/usr/bin/env bash\n" + check)
        if proof is not None:
            with open(os.path.join(d, "inject.sh"), "w", encoding="utf-8") as fh:
                fh.write(proof)
    for name, job in (decl or {}).items():
        with open(os.path.join(box, "scripts", name, "ci-job"), "w", encoding="utf-8") as fh:
            fh.write("# объявление песочницы\n%s\n" % job)
    if wf is not None:
        os.makedirs(os.path.join(box, ".github", "workflows"))
        with open(os.path.join(box, ".github", "workflows", "ci.yaml"), "w",
                  encoding="utf-8") as fh:
            fh.write(wf)
    return box


def run(ws, suites, args, decl=None, wf=None):
    box = world(ws, suites, decl, wf)
    try:
        env = {k: v for k, v in _lib.world_env(box).items()
               if k not in ("GATE_ROOT", "SUITE_SUMMARY")}
        try:
            out = subprocess.run(["bash", os.path.join(box, DERIVED)] + args, cwd=box, env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 timeout=300)
            return out.returncode, out.stdout.decode("utf-8", "replace")
        except subprocess.TimeoutExpired:
            return "timeout", ""
    finally:
        shutil.rmtree(box, ignore_errors=True)


def healthy():
    return {"aaa-gate": (SHIM, GREEN, PROOF_OK), "bbb-gate": (SHIM, GREEN, PROOF_OK)}


def with_bbb(runner=SHIM, check=GREEN, proof=PROOF_OK):
    w = healthy()
    w["bbb-gate"] = (runner, check, proof)
    return w


FULL = ["--proofs", "--void-is-failure"]

# (что изменено против контроля, мир, ключи, ждём код)
CASES = (
    ("bbb-gate без предмета, вызов с --void-is-failure", with_bbb(check=VOIDED), FULL, 1),
    ("близнец: bbb-gate без предмета, вызов без --void-is-failure",
     with_bbb(check=VOIDED), ["--proofs"], 2),
    ("bbb-gate не отчитался строкой переписи", with_bbb(runner=UNREPORTED, check=None), FULL, 1),
    ("bbb-gate вышел нулём над строкой «исполнено 0»",
     with_bbb(runner=row_runner(0, 0, 0, 0, 0), check=None), FULL, 1),
    ("bbb-gate вышел нулём, а строка переписи говорит «провалено 1»",
     with_bbb(runner=row_runner(1, 0, 1, 0, 0), check=None), FULL, 1),
    ("доказательство bbb-gate красное, вызов с --proofs", with_bbb(proof=PROOF_RED), FULL, 1),
    ("близнец: доказательство bbb-gate красное, вызов без --proofs",
     with_bbb(proof=PROOF_RED), ["--void-is-failure"], 0),
    ("у bbb-gate нет доказательства, вызов с --proofs", with_bbb(proof=None), FULL, 1),
    ("bbb-gate красный", with_bbb(check=RED), FULL, 1),
    ("перепись наборов пуста", {}, FULL, 1),
)

BY_JOB = FULL + ["--job", "suites"]
ONE = workflow(("suites", True))
TWO = workflow(("suites", True), ("other", True))
LOST = workflow(("suites", True), ("other", False))
BOTH = {"aaa-gate": "suites", "bbb-gate": "suites"}
SPLIT = {"aaa-gate": "suites", "bbb-gate": "other"}

# Исход по заданию судится кодом И причиной: отказ разметки, проглоченный выводом,
# доходит до кода 1 другой дорогой — пустым выбором, — и называет не ту причину.
UNCOVERED = "разметка наборов по заданиям не покрывает дерево (код 1)"

# (что изменено против близнеца «оба объявили suites», мир, объявления, процесс, ключи,
#  ждём код, ждём в выводе)
JOB_CASES = (
    ("близнец: оба набора объявили задание suites, вывод по заданию", healthy(), BOTH, ONE,
     BY_JOB, 0, "объявили задание suites 2 · исполнено 2"),
    ("bbb-gate объявил задание other, которого в конвейере нет", healthy(), SPLIT, ONE,
     BY_JOB, 1, UNCOVERED),
    ("близнец: красный bbb-gate объявил задание other, зовущее вывод, — в задании suites "
     "не исполняется", with_bbb(check=RED), SPLIT, TWO, BY_JOB, 0,
     "объявили задание suites 1 · исполнено 1"),
    ("bbb-gate не объявил задания, вывод зовётся по заданиям", healthy(),
     {"aaa-gate": "suites"}, ONE, BY_JOB, 1, UNCOVERED),
    ("задание other лишилось шага вывода — bbb-gate не исполняет никто", healthy(), SPLIT,
     LOST, BY_JOB, 1, UNCOVERED),
    ("задание nobody не объявил ни один набор — пустой выбор", healthy(), BOTH, ONE,
     FULL + ["--job", "nobody"], 1, "ни один набор не объявил задание nobody"),
)


def main():
    ws = _lib.root(__file__)
    target = os.path.join(ws, DERIVED)
    if not os.path.isfile(target):
        _lib.void(NAME, "вывода перечня %s в %s нет — судить нечего" % (DERIVED, ws))
        return 2
    if not os.path.isdir(os.path.join(ws, "scripts", "lib")):
        _lib.void(NAME, "общей библиотеки scripts/lib в %s нет — песочницу не из чего собрать" % ws)
        return 2

    rc, out = run(ws, healthy(), FULL)
    if rc != 0:
        _lib.void(NAME, "%s — на двух исправных наборах с исправными доказательствами вернул "
                  "%s; остальные пробы на нём недоказательны; вывод: %s"
                  % (DERIVED, rc, out.strip().split("\n")[-1][:160]))
        return 2

    findings = []
    for what, suites, args, want in CASES:
        rc, out = run(ws, suites, args)
        if rc != want:
            findings.append("%s — %s (%s): вернул %s вместо %s; последняя строка: %s"
                            % (DERIVED, what, " ".join(args), rc, want,
                               out.strip().split("\n")[-1][:160]))
    try:
        import yaml  # noqa: F401  разметку по заданиям читает ci_suites.py
        by_job = JOB_CASES
    except ImportError:
        by_job = ()
    for what, suites, decl, wf, args, want, said in by_job:
        rc, out = run(ws, suites, args, decl, wf)
        if rc != want or said not in out:
            findings.append("%s — %s (%s): вернул %s (ждали %s), «%s» в выводе %s; последняя "
                            "строка: %s"
                            % (DERIVED, what, " ".join(args), rc, want, said,
                               "есть" if said in out else "нет",
                               out.strip().split("\n")[-1][:160]))

    cases = [(c[0], c[3]) for c in CASES] + [(c[0], c[5]) for c in by_job]
    _lib.census(NAME, "вывод перечня %s; проб %d — контроль и %d случаев (из них близнецов %d, "
                "по заданию %d из %d); находок %d"
                % (DERIVED, 1 + len(cases), len(cases),
                   sum(1 for what, _ in cases if what.startswith("близнец")),
                   len(by_job), len(JOB_CASES), len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "каналов, которые вывод перечня не читает: %d" % len(findings))
        return 1
    if not by_job:
        _lib.void(NAME, "разборщик YAML недоступен — проб по заданию не исполнено %d из %d: "
                  "выбор по заданию не доказан" % (len(JOB_CASES), len(JOB_CASES)))
        return 2
    _lib.passed(NAME, "вывод перечня краснеет на каждом из %d дефектных каналов и молчит на "
                "близнецах" % sum(1 for what, want in cases
                                  if want != 0 and not what.startswith("близнец")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
