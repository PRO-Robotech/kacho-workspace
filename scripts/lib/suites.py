#!/usr/bin/env python3
"""suites — перепись наборов проверок воркспейса: что считается набором, проверкой и
доказательством. Определение для конвейера (`scripts/lib/run-suites.sh`) и проверок
набора `scripts/suites-gate/`.

ОПРЕДЕЛЕНИЕ НЕ ЕДИНСТВЕННОЕ — и это названо, а не подразумевается. Хук отправки
(`scripts/hooks/pre-push`) перечисляет наборы своим pathspec
`git ls-files 'scripts/*/run-all.sh'`, где `*` проходит через `/`: на вложенном
`run-all.sh` (`scripts/<набор>/tests/fixture/run-all.sh`) хук увидел бы набор, а эта
перепись — нет (измерено в круге 1: 2 против 1). Совпадают они сегодня по факту дерева:
вложенного `run-all.sh` нет, и держит это `scripts/suites-gate/check-10-no-nested-suite-runner.py`.
Второе определение снимается переводом хука на эту перепись — это предмет полосы хуков.

ЗАЧЕМ ОДНО ОПРЕДЕЛЕНИЕ. Хук отправки выводил перечень наборов глобом, конвейер
выписывал его от руки — и видел ровно те наборы, что были выписаны (ws#753): набор,
заведённый в дереве, не исполнялся на стволе, и это не краснело ничем. Второй
носитель факта «какие наборы есть» отстаёт молча, и его отставание выглядит как
«проверки прошли».

ЕДИНИЦЫ, И КАЖДАЯ ВЫВОДИТСЯ ИЗ ИНДЕКСА GIT, А НЕ С ДИСКА И НЕ ИЗ ПАМЯТИ:
  набор          — каталог `scripts/<имя>/`, в котором отслеживается `run-all.sh`;
  проверка       — отслеживаемый файл набора ВЕРХНЕГО уровня с именем `check-*`
                   (тот же образец, что глоб общего прогонщика `suite-runner.sh`:
                   прогонщик обходит диск, потому что исполняет то, что лежит;
                   перепись обходит индекс, потому что судит то, что отправляется);
  доказательство — `inject.sh` набора: единственный вход его инъекций. Части
                   инъекции (`inject-<N>*.sh`) зовёт сам вход; конвейер их по
                   отдельности не зовёт.

`--others --exclude-standard` добавляет ещё не закоммиченный, но и не игнорируемый
файл: иначе новый набор не попадал бы под перепись ровно в тот день, когда его
заводят.

ПУСТАЯ ПЕРЕПИСЬ — ОТКАЗ, А НЕ «НАХОДОК НОЛЬ». Вызывающий обязан отличать «наборов
нет» от «наборы есть и чисты»; модуль возвращает пустой список, а решение об
исходе принимает проверка, которая знает свой предмет.

Вызов из bash: `python3 suites.py suites <корень>` — имена наборов построчно;
`python3 suites.py checks <корень> <набор>` — пути проверок набора.
"""
import fnmatch
import os
import subprocess
import sys

RUNNER = "run-all.sh"
CHECK_PATTERN = "check-*"
PROOF = "inject.sh"


# Окружение git, которое сильнее `git -C`: `git push` запускает хук с выставленным
# `GIT_DIR`, и перепись, унаследовавшая его, считала бы чужой индекс. Перечень —
# тот же, что снимает хук отправки.
GIT_ENV = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
           "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_PREFIX")


def clean_env():
    return {k: v for k, v in os.environ.items() if k not in GIT_ENV}


class CensusUnreadable(Exception):
    """git не ответил о составе дерева — перепись не снята, а не пуста."""


def tracked(root, *pathspecs):
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard",
         "--", *pathspecs],
        capture_output=True, text=True, env=clean_env())
    if out.returncode != 0:
        raise CensusUnreadable("git ls-files в %s: %s" % (root, out.stderr.strip()))
    return sorted({p for p in out.stdout.split("\n") if p})


def suites(root):
    """Имена наборов — каталоги scripts/<имя>/ с отслеживаемым run-all.sh."""
    names = []
    for rel in tracked(root, "scripts/*/" + RUNNER):
        parts = rel.split("/")
        if len(parts) == 3:
            names.append(parts[1])
    return sorted(set(names))


def suite_files(root, name):
    """Отслеживаемые файлы набора, все уровни."""
    return tracked(root, "scripts/%s/" % name)


def checks(root, name):
    """Проверки набора: файлы верхнего уровня с именем check-*."""
    prefix = "scripts/%s/" % name
    out = []
    for rel in suite_files(root, name):
        base = rel[len(prefix):]
        if "/" in base:
            continue
        if fnmatch.fnmatchcase(base, CHECK_PATTERN):
            out.append(rel)
    return out


def proof(root, name):
    rel = "scripts/%s/%s" % (name, PROOF)
    return rel if os.path.isfile(os.path.join(root, rel)) else None


def interpreter(path):
    """Как прогонщик исполняет проверку: .py — python3, .sh — bash, иначе — сам файл."""
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith(".sh"):
        return ["bash", path]
    return [path]


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == "suites":
            print("\n".join(suites(argv[2])))
            return 0
        if len(argv) == 4 and argv[1] == "checks":
            print("\n".join(checks(argv[2], argv[3])))
            return 0
    except CensusUnreadable as exc:
        print("[VOID] suites — %s" % exc, file=sys.stderr)
        return 2
    print("использование: suites.py suites <корень> | checks <корень> <набор>",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
