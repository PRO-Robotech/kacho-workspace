#!/usr/bin/env python3
"""check-03 — прогонщик КАЖДОГО набора не засчитывает молчаливый ноль и не отдаёт проверке свой рабочий каталог.

ЧТО УТВЕРЖДАЕТ (ws#762 п.1–2, ws#757). У каждого `scripts/<набор>/run-all.sh`:
  (а) исход проверки берётся НЕ из одного канала: проверка, вышедшая нулём и не
      напечатавшая ни одного числа (объёма осмотренного), — находка набора, а не
      «пройдено». Иначе «ноль находок» у набора неотличим от «ноль прочитанного»;
  (б) проверка исполняется из ПУСТОГО чужого рабочего каталога, а не из каталога
      вызывающего: проверка, взявшая корень оттуда, увидит пустоту, а не дерево;
  (в) набор пишет машинную строку переписи в `SUITE_SUMMARY` — второй канал для
      `scripts/lib/run-suites.sh`, которым конвейер сверяет код набора с числом
      исполненного.

Все три свойства написаны ОДИН раз — в `scripts/lib/suite-runner.sh`. Эта проверка
не читает исходник прогонщика и не ищет в нём вызов библиотеки: набор волен
устроить прогон как угодно, спрашивается ИСХОД. Рядом с копией прогонщика в
песочнице кладут одну проверку-заглушку и читают код.

ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПЕРВЫМ. Прогонщик, не отвечающий нулём даже на единственной
проверке, напечатавшей объём, к остальным пробам непригоден — они прошли бы на нём
тождественно. Такой исход — VOID, а не «доказано».

Коды: 0 — все прогонщики держат три свойства; 1 — находка; 2 — прогонщиков нет либо
положительный контроль сорван.
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-03-runner-demands-a-printed-volume"

STUB_OK = 'echo "осмотрено 1"\nexit 0\n'
STUB_SILENT = 'exit 0\n'
STUB_LEAK = (
    'top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""\n'
    'if [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$(cd "%s" && pwd -P)" ]; then\n'
    '    echo "рабочий каталог проверки — дерево набора: 1 из 1"\n'
    '    exit 1\n'
    'fi\n'
    'echo "осмотрено 1"\nexit 0\n')


def probe(ws, suite, stub, summary=None):
    """Код прогонщика набора в песочнице с одной заглушкой; для summary — ещё строки переписи."""
    box = tempfile.mkdtemp(prefix="runner-probe.")
    try:
        subprocess.run(["git", "-C", box, "init", "-q"], check=True, env=_lib.clean_env())
        sdir = os.path.join(box, "scripts", suite)
        os.makedirs(sdir)
        shutil.copy2(os.path.join(ws, "scripts", suite, "run-all.sh"), sdir)
        lib = os.path.join(ws, "scripts", "lib")
        if os.path.isdir(lib):
            shutil.copytree(lib, os.path.join(box, "scripts", "lib"))
        chk = os.path.join(sdir, "check-01-stub.sh")
        with open(chk, "w", encoding="utf-8") as fh:
            fh.write("#!/usr/bin/env bash\n" + (stub % box if "%s" in stub else stub))
        os.chmod(chk, 0o755)
        env = {k: v for k, v in _lib.clean_env().items() if k != "SUITE_SUMMARY"}
        sumfile = None
        if summary:
            sumfile = os.path.join(box, "summary.tsv")
            env["SUITE_SUMMARY"] = sumfile
        try:
            out = subprocess.run(["bash", os.path.join(sdir, "run-all.sh")], cwd=box, env=env,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 timeout=120)
            rc = out.returncode
        except subprocess.TimeoutExpired:
            rc = "timeout"
        rows = []
        if sumfile and os.path.isfile(sumfile):
            with open(sumfile, encoding="utf-8") as fh:
                rows = [line.rstrip("\n").split("\t") for line in fh if line.strip()]
        return rc, rows
    finally:
        shutil.rmtree(box, ignore_errors=True)


def main():
    ws = _lib.root(__file__)
    names, _ = _lib.suite_census(NAME, ws)
    if not names:
        _lib.void(NAME, "прогонщиков scripts/*/run-all.sh в %s нет — осматривать нечего" % ws)
        return 2

    findings = []
    examined = 0
    for s in names:
        rel = "scripts/%s/run-all.sh" % s
        rc, rows = probe(ws, s, STUB_OK, summary=True)
        if rc != 0:
            _lib.void(NAME, "%s — на единственной проверке, напечатавшей объём, вернул %s; "
                      "остальные пробы на нём недоказательны" % (rel, rc))
            return 2
        examined += 1
        if [s, "1", "1", "0", "0"] not in rows:
            findings.append("%s — не записал машинную строку переписи в SUITE_SUMMARY "
                            "(ждали «%s 1 1 0 0», получили %s): конвейеру нечем сверить код "
                            "набора с числом исполненного" % (rel, s, rows or "ничего"))
        rc, _ = probe(ws, s, STUB_SILENT)
        if rc != 1:
            findings.append("%s — проверка вышла нулём, не напечатав ни одного числа, а "
                            "прогонщик вернул %s вместо 1: исход взят из одного канала, "
                            "«ноль прочитанного» засчитан за «ноль находок»" % (rel, rc))
        rc, _ = probe(ws, s, STUB_LEAK)
        if rc != 0:
            findings.append("%s — проверка исполнена из рабочего каталога вызывающего "
                            "(его дерево ей видно, код %s): корень, взятый оттуда, судил "
                            "бы настоящее дерево, а не пустоту" % (rel, rc))

    _lib.census(NAME, "прогонщиков осмотрено %d (%s); проб %d — контроль с переписью, "
                "молчаливый ноль, рабочий каталог; находок %d"
                % (examined, ", ".join(names), 3 * examined, len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "находок у прогонщиков: %d" % len(findings))
        return 1
    _lib.passed(NAME, "все %d прогонщиков требуют напечатанного объёма, исполняют проверки "
                "из пустого каталога и пишут перепись" % examined)
    return 0


if __name__ == "__main__":
    sys.exit(main())
