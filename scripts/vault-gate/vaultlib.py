#!/usr/bin/env python3
"""Общая механика для проверок хранилища знаний: перечень записок, разбор
frontmatter, резолв wikilink'ов ровно так, как это делает Obsidian.

Почему резолв вынесен сюда и почему он не «просто путь». Obsidian разрешает
ссылку по трём правилам подряд: путь относительно файла-источника, путь от корня
хранилища, базовое имя файла где угодно в дереве. Проверка, знающая только
третье правило, объявляет висячими 1 700 живых ссылок вида `[[../KAC/KAC-94]]`;
проверка, знающая только первые два, пропускает короткую форму `[[KAC-94]]`.
Оба перекоса наблюдались на первом же прогоне — поэтому правило одно и общее.
"""

from __future__ import annotations

import os
import posixpath
import re
import subprocess

VAULT = "obsidian/kacho"

LINK_RE = re.compile(r"(?<!!)\[\[([^\]|#^]+)(?:[#^][^\]|]*)?(?:\\?\|[^\]]*)?\]\]")


def workspace_root(script_file: str) -> str:
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(script_file)), "..", ".."))


def vault_files(root: str) -> list[str]:
    """Файлы хранилища из индекса git: отслеживаемые плюс ещё не добавленные, но
    не игнорируемые. С диска читались бы и посторонние файлы, из `--cached` —
    не читалась бы записка ровно в тот день, когда её пишут."""
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", f"{VAULT}/"],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        return []
    return sorted({p[len(VAULT) + 1 :] for p in out.stdout.split() if p.startswith(VAULT + "/")})


def notes(files: list[str]) -> list[str]:
    return [f for f in files if f.endswith(".md")]


def frontmatter(path: str) -> dict[str, str]:
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return {}
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    fm: dict[str, str] = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if m and m.group(2).strip():
            fm[m.group(1)] = m.group(2).strip().strip('"')
    return fm


class Resolver:
    def __init__(self, files: list[str]):
        self.files = set(files)
        self.by_name: dict[str, str] = {}
        for f in files:
            base = os.path.basename(f)
            self.by_name.setdefault(base, f)
            self.by_name.setdefault(os.path.splitext(base)[0], f)

    def resolve(self, link: str, source: str) -> str | None:
        link = link.strip().rstrip("\\")
        candidates: list[str] = []
        if "/" in link or link.startswith("."):
            candidates.append(posixpath.normpath(posixpath.join(posixpath.dirname(source), link)))
            candidates.append(posixpath.normpath(link))
        for c in candidates:
            for ext in ("", ".md", ".base", ".canvas"):
                if c + ext in self.files:
                    return c + ext
        key = link.split("/")[-1]
        return self.by_name.get(link) or self.by_name.get(key)


def link_kind(target: str) -> str:
    t = target.strip().rstrip("\\")
    if re.fullmatch(r"(\.\./)?(KAC/)?KAC-[0-9A-Za-z.\-]+", t) or t.isdigit():
        return "KAC"
    return "cat" if "/" in t else "bare"
