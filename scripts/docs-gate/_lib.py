"""Общее для проверок набора docs-gate.

Состав дерева берётся из ИНДЕКСА git (`--cached --others --exclude-standard`), а
не с диска: посторонний каталог рядом с репозиторием иначе влияет на вердикт, а
ещё не закоммиченный, но и не игнорируемый файл обязан проверяться ровно в тот
коммит, где его заводят, — иначе гейт молчит в единственный день, когда он нужен.

`DOCS_GATE_ROOT` переопределяет корень. Этим пользуется ТОЛЬКО inject.sh, чтобы
прогонять проверки по временной копии дерева с внесённым дефектом.
"""
import os
import subprocess

_HERE = os.path.dirname(os.path.abspath(__file__))


def workspace_root():
    override = os.environ.get("DOCS_GATE_ROOT")
    if override:
        return os.path.abspath(override)
    return os.path.dirname(os.path.dirname(_HERE))


def tracked(root, pattern):
    """Отсортированный список путей индекса, подходящих под pathspec."""
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others",
         "--exclude-standard", pattern],
        capture_output=True, text=True,
    )
    return sorted(set(p for p in out.stdout.split("\n") if p))


def read(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def census(text):
    print("[CENSUS] %s" % text)


def passed(name, detail):
    print("[PASS] %s — %s" % (name, detail))


def fail(name, detail):
    import sys
    print("[FAIL] %s — %s" % (name, detail), file=sys.stderr)


def void(name, detail):
    """«Проверять нечего» ≠ «находок ноль»."""
    import sys
    print("[VOID] %s — %s" % (name, detail), file=sys.stderr)
