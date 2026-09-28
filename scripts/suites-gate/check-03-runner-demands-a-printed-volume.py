#!/usr/bin/env python3
"""check-03 — прогонщик КАЖДОГО набора не засчитывает молчаливый ноль и не отдаёт проверке свой рабочий каталог.

ЧТО УТВЕРЖДАЕТ (ws#762 п.1–2, ws#757). У каждого `scripts/<набор>/run-all.sh`:
  (а) исход проверки берётся НЕ из одного канала. Код 0 засчитывается, только если
      проверка напечатала объём осмотренного — ОТДЕЛЬНОЕ число, а не цифры адреса
      проверки: строку `[PASS] check-NN-<имя>` печатает каждая проверка дерева, и
      «в выводе есть цифра» выполнялось бы номером в её собственном имени.
      Код 2 засчитывается за «без предмета», только если проверка напечатала
      строку `[VOID] <причина>`: код 2 отдаёт и сам интерпретатор (синтаксическая
      ошибка оболочки, отказ разбора аргументов), и сломанная проверка иначе
      неотличима от «нет клона продукта» — а хук отправки на коде 2 не
      останавливается;
  (б) проверка исполняется из ПУСТОГО чужого рабочего каталога, а не из каталога
      вызывающего: проверка, взявшая корень оттуда, увидит пустоту, а не дерево.
      Условие, при котором это ломается, создаётся здесь, а не наследуется:
      `TMPDIR` указывает ВНУТРЬ рабочей копии песочницы, и временный каталог
      без собственного `git init` отдал бы `git rev-parse --show-toplevel`
      саму песочницу;
  (в) набор без единой проверки — находка (1), а не «пройдено»: пустой обход не
      прочитал о дереве ничего;
  (г) набор пишет машинную строку переписи в `SUITE_SUMMARY` — второй канал для
      `scripts/lib/run-suites.sh`, которым конвейер сверяет код набора с числом
      исполненного.

Все свойства написаны ОДИН раз — в `scripts/lib/suite-runner.sh`. Эта проверка
не читает исходник прогонщика и не ищет в нём вызов библиотеки: набор волен
устроить прогон как угодно, спрашивается ИСХОД. Рядом с копией прогонщика в
песочнице кладут одну проверку-заглушку (либо ни одной) и читают код. У каждого
отрицательного случая есть законный близнец той же формы: заглушка с объёмом
против заглушки, напечатавшей только свой адрес; `[VOID]` с причиной против
синтаксической ошибки с тем же кодом 2.

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
# Только свой адрес: цифры есть — в номере проверки, объёма нет.
STUB_NAME_ONLY = 'echo "[PASS] check-01-stub — чисто"\nexit 0\n'
# «Без предмета» по договорённости: строка [VOID] с причиной, код 2.
STUB_VOID = 'echo "[VOID] check-01-stub — сверять не с чем: файлов 0" >&2\nexit 2\n'
# Тот же код 2 — от интерпретатора: `if` без `fi`.
STUB_BROKEN = 'if true; then\n    echo "осмотрено 1"\n'
STUB_LEAK = (
    'top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""\n'
    'if [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$(cd "%s" && pwd -P)" ]; then\n'
    '    echo "рабочий каталог проверки — дерево набора: 1 из 1"\n'
    '    exit 1\n'
    'fi\n'
    'echo "осмотрено 1"\nexit 0\n')


def probe(ws, suite, stub, summary=None):
    """Код прогонщика набора в песочнице с одной заглушкой (stub=None — без проверок);
    для summary — ещё строки переписи.

    `TMPDIR` песочницы лежит ВНУТРИ её рабочей копии: временный каталог прогонщика
    окажется внутри git-дерева, и только его собственный `git init` отделит его от
    песочницы. Унаследованный `TMPDIR` здесь не участвует: у вызывающего он может
    лежать в каталоге, чей `.git` указывает в никуда, и маскировать это условие."""
    box = tempfile.mkdtemp(prefix="runner-probe.")
    try:
        subprocess.run(["git", "-C", box, "init", "-q"], check=True, env=_lib.clean_env())
        sdir = os.path.join(box, "scripts", suite)
        os.makedirs(sdir)
        tmp_inside = os.path.join(box, "tmp")
        os.makedirs(tmp_inside)
        shutil.copy2(os.path.join(ws, "scripts", suite, "run-all.sh"), sdir)
        lib = os.path.join(ws, "scripts", "lib")
        if os.path.isdir(lib):
            shutil.copytree(lib, os.path.join(box, "scripts", "lib"))
        if stub is not None:
            chk = os.path.join(sdir, "check-01-stub.sh")
            with open(chk, "w", encoding="utf-8") as fh:
                fh.write("#!/usr/bin/env bash\n" + (stub % box if "%s" in stub else stub))
            os.chmod(chk, 0o755)
        env = {k: v for k, v in _lib.clean_env().items() if k != "SUITE_SUMMARY"}
        env["TMPDIR"] = tmp_inside
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


# (заглушка, ждём код, текст находки) — отрицательные случаи и их близнецы после
# положительного контроля. Порядок — порядок находок.
CASES = (
    (STUB_SILENT, 1, "проверка вышла нулём, не напечатав ни одного числа, а прогонщик "
                     "вернул %s вместо 1: исход взят из одного канала, «ноль прочитанного» "
                     "засчитан за «ноль находок»"),
    (STUB_NAME_ONLY, 1, "проверка вышла нулём, напечатав только свой адрес "
                        "(`[PASS] check-01-stub`), а прогонщик вернул %s вместо 1: за объём "
                        "осмотренного засчитаны цифры номера проверки"),
    (STUB_VOID, 2, "проверка напечатала `[VOID]` с причиной и вышла кодом 2, а прогонщик "
                   "вернул %s вместо 2: «без предмета» не отличено от находки либо от "
                   "успеха"),
    (STUB_BROKEN, 1, "проверка с синтаксической ошибкой оболочки (код 2 от интерпретатора, "
                     "строки `[VOID]` нет), а прогонщик вернул %s вместо 1: сломанная "
                     "проверка засчитана за «без предмета» и неотличима от «нет клона "
                     "продукта»"),
    (None, 1, "в наборе нет ни одной проверки, а прогонщик вернул %s вместо 1: пустой обход "
              "выдан за исход"),
    (STUB_LEAK, 0, "проверка исполнена внутри рабочей копии вызывающего (её дерево видно "
                   "`git rev-parse` из рабочего каталога проверки при TMPDIR внутри "
                   "песочницы, код %s): корень, взятый оттуда, судил бы настоящее дерево, а "
                   "не пустоту"),
)


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
        for stub, want, text in CASES:
            rc, _ = probe(ws, s, stub)
            if rc != want:
                findings.append("%s — %s" % (rel, text % rc))

    _lib.census(NAME, "прогонщиков осмотрено %d (%s); проб %d — по %d на прогонщик: "
                "контроль с переписью, молчаливый ноль, только адрес, [VOID] с причиной, "
                "синтаксическая ошибка, пустой набор, рабочий каталог; находок %d"
                % (examined, ", ".join(names), (1 + len(CASES)) * examined, 1 + len(CASES),
                   len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "находок у прогонщиков: %d" % len(findings))
        return 1
    _lib.passed(NAME, "все %d прогонщиков требуют отдельного числа объёма и строки [VOID] "
                "при коде 2, краснеют на пустом наборе, исполняют проверки из своего "
                "git-каталога и пишут перепись" % examined)
    return 0


if __name__ == "__main__":
    sys.exit(main())
