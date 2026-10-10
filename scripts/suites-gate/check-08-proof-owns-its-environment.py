#!/usr/bin/env python3
"""check-08 — доказательство набора, чей код читает дом репозитория продукта, само задаёт своё окружение.

ЧТО УТВЕРЖДАЕТ (ws#757). Если исполняемый код набора читает указатель на дом
репозитория продукта (`KACHO_HOME_<ИМЯ>`), то его доказательство `inject.sh`
подключает `scripts/lib/proofs.sh` и зовёт `proof_own_environment` — снимает
унаследованные указатели на деревья до своих проб.

ЦЕНА. Доказательство строит синтетический мир, а проверка берёт часть мира из
окружения, и унаследованный указатель сильнее песочницы. Вердикт доказательства
зависел от того, КТО его запустил: при заданных `KACHO_HOME_*` доказательство
crossrepo-gate краснело на настоящих парах (ось A), docs-gate — на пробе «дома
рядом нет» (ждали код 2, получили 0); без них оба зеленели. Решение диспетчера
2026-09-28: доказательства сами задают или очищают своё окружение, исход одинаков
при любом унаследованном `KACHO_HOME_*`.

ПРИЗНАК «ЧИТАЕТ» — литерал `KACHO_HOME_` в исполняемом коде набора, на всех
уровнях его каталога: в `.py` — строковая константа разобранного дерева (не
строка документации), в оболочке — код без комментариев (`scripts/lib/shellcode.py`).
Упоминание в комментарии и в строке документации читателем не делает.

ГРАНИЦЫ, НАЗВАННЫЕ ПРЯМО:
  * чтение через модуль ДРУГОГО набора без своего литерала — вне признака (сегодня
    таких нет: crossrepo-gate несёт литерал сам, хотя и импортирует `_lib`
    docs-gate);
  * порядок — что вызов стоит ДО первой пробы — не судится: вызов ищется в коде
    доказательства, и что он в начале файла, держит его место, а не эта проверка;
  * что функция действительно делает исход независимым от унаследованного, судит
    не эта проверка, а проба-пара `inject.sh` набора: один и тот же
    доказательство-двойник под указателем и без него, с вызовом — исходы равны,
    без вызова — различаются.

Коды: 0 — каждое такое доказательство владеет окружением; 1 — находка; 2 —
наборов нет либо ни один не читает указатель.
"""
import ast
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import shellcode  # noqa: E402

NAME = "check-08-proof-owns-its-environment"
KNOB = "KACHO_HOME_"
LIBRARY = "scripts/lib/proofs.sh"
CALL = re.compile(r"(?:^|[;&|({]|\b(?:then|do|else)\b)\s*proof_own_environment\b")


def py_reads(text):
    """Строковые константы с указателем — вне строк документации. None — не разобран."""
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return None
    docs = {id(n.value) for n in ast.walk(tree)
            if isinstance(n, ast.Expr) and isinstance(n.value, ast.Constant)}
    return any(isinstance(n, ast.Constant) and isinstance(n.value, str)
               and id(n) not in docs and KNOB in n.value for n in ast.walk(tree))


def is_shell(ws, rel):
    if rel.endswith(".sh"):
        return True
    try:
        with open(os.path.join(ws, rel), "rb") as fh:
            first = fh.readline(256).decode("utf-8", "replace")
    except OSError:
        return False
    return bool(re.match(r"^#!\s*\S*\b(?:env\s+)?(?:ba|da|k|z)?sh\b", first))


def main():
    ws = _lib.root(__file__)
    names, _ = _lib.suite_census(NAME, ws)
    if not names:
        _lib.void(NAME, "наборов scripts/*/run-all.sh в %s нет — осматривать нечего" % ws)
        return 2

    findings = []
    readers = {}
    files_read = 0
    unparsed = []
    for s in names:
        for rel in _lib.S.suite_files(ws, s):
            py = rel.endswith(".py")
            if not py and not is_shell(ws, rel):
                continue
            try:
                with open(os.path.join(ws, rel), encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError as exc:
                findings.append("%s — не читается: %s" % (rel, exc))
                continue
            files_read += 1
            if py:
                hit = py_reads(text)
                if hit is None:
                    unparsed.append(rel)
                    continue
            else:
                hit = KNOB in shellcode.code_text(text)
            if hit:
                readers.setdefault(s, []).append(rel)
    for rel in unparsed:
        findings.append("%s — не разбирается как Python: читает ли он %s*, не выводится"
                        % (rel, KNOB))

    owning = 0
    no_proof = []
    for s in sorted(readers):
        proof = _lib.S.proof(ws, s)
        who = ", ".join(readers[s])
        if not proof:
            no_proof.append(s)
            continue
        with open(os.path.join(ws, proof), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        plain = shellcode.code_lines(text)
        masked = shellcode.code_lines(text, mask_quotes=True)
        loops = shellcode.loop_words(plain)
        sourced = False
        for _, c in plain:
            for word in shellcode.sourced_words(c):
                if LIBRARY in shellcode.resolve_sourced(proof, word, [LIBRARY], loops):
                    sourced = True
        called = [n for n, c in masked if CALL.search(c)]
        if not called:
            findings.append("%s — код набора %s читает %s* (%s), а доказательство не зовёт "
                            "proof_own_environment: унаследованный дом сильнее песочницы, "
                            "и вердикт зависит от того, кто запустил"
                            % (proof, s, KNOB, who))
        elif not sourced:
            findings.append("%s:%d — proof_own_environment зовётся, но %s не подключён: "
                            "функции нет, вызов не выполнится, окружение останется "
                            "унаследованным" % (proof, called[0], LIBRARY))
        else:
            owning += 1

    _lib.census(NAME, "наборов %d; файлов кода прочитано %d; читают %s*: %d (%s); из них "
                "доказательство владеет окружением %d, доказательства нет %d (предмет "
                "check-04); находок %d"
                % (len(names), files_read, KNOB, len(readers), ", ".join(sorted(readers)) or "—",
                   owning, len(no_proof), len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "доказательств, чей вердикт зависит от унаследованного окружения: %d"
                  % len(findings))
        return 1
    if not readers:
        _lib.void(NAME, "ни один из %d наборов не читает %s* — судить нечего" % (len(names), KNOB))
        return 2
    _lib.passed(NAME, "все %d доказательств наборов, читающих %s*, задают своё окружение"
                % (owning, KNOB))
    return 0


if __name__ == "__main__":
    sys.exit(main())
