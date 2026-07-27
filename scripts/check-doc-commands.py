#!/usr/bin/env python3
"""Every make command quoted in docs/ must run, unchanged, from the monorepo root.

There is no Makefile at the root of `project/kacho`. Targets live in `deploy/`,
`gateway/` and the per-service `services/*/` directories, so a bare `make <target>`
copied out of a document fails with "No rule to make target" for whoever runs it.
This check reads every make invocation quoted in `docs/**/*.md` and asserts that the
directory it would run in really declares that target.

What counts as a quoted command: a `make` invocation standing at the start of a
command — inside a code span or a fenced block, optionally after `$ `, `sudo`, a
`VAR=value` prefix, a YAML `- run:`, or a shell connective (`&&`, `||`, `;`, `|`).
Prose that merely names make, and make's own output ("No rule to make target ..."),
are not commands and are not checked. Neither is Go's `make(` — it has no space.

How the working directory is resolved, in order:
  1. an explicit `-C <dir>`;
  2. otherwise a `cd <dir>` earlier in the same quoted command;
  3. otherwise the monorepo root — which has no Makefile, so the citation fails.
`{a,b}` brace lists are expanded the way bash expands them; every branch is checked.

Scope note, so the boundary is not mistaken for an omission: only make citations are
checked. A bare `cd` in front of a non-make command is not, because several procedures
in these documents are rooted somewhere else on purpose (cloning the workspace, a CI
script that already runs inside a service directory, a chained cd within deploy/helm).
A cd is still checked when it decides where a make citation would run.

There is no exception list. If something here cannot be made to run, the document
should say so in prose instead of quoting a command that does not exist.

Exit code 0 when every citation resolves, 1 otherwise (each failure printed).
"""
import collections
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MONO = os.path.join(REPO, "project", "kacho")
DOCS = os.path.join(REPO, "docs")

FENCE = re.compile(r"^\s*(```+|~~~+)\s*([A-Za-z0-9_+-]*)")
SPAN = re.compile(r"`([^`\n]+)`")


SEP = re.compile(r"&&|\|\||;|\|")
# leading noise that can precede a command: list bullet, YAML `run:`, shell prompt,
# subshell paren, sudo/time/env, and any number of VAR=value assignments.
LEAD = re.compile(
    r"^\s*(?:[-*]\s+)?(?:run:\s*)?(?:\$\s+)?(?:\(\s*)?"
    r"(?:sudo\s+|time\s+|env\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
)


def declared_targets():
    """dir (relative to the monorepo root) -> set of targets its Makefile declares."""
    targets = collections.defaultdict(set)
    for dirpath, dirnames, filenames in os.walk(MONO):
        dirnames[:] = [d for d in dirnames if d not in (".claude", "node_modules", ".git")]
        if "Makefile" not in filenames:
            continue
        rel = os.path.relpath(dirpath, MONO)
        with open(os.path.join(dirpath, "Makefile"), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = re.match(r"^([A-Za-z][A-Za-z0-9_.-]*):", line)
                if m:
                    targets[rel].add(m.group(1))
    return targets


def snippets(path):
    """Yield (lineno, snippet, language) for every code span and fenced code line.

    Code spans are scanned by pairing backticks in order, carrying an unclosed span
    onto the next line: markdown lets a span wrap, rendering the break as a space, so
    a checker that only read single lines could be defeated by wrapping a broken
    citation. A blank line ends the paragraph and drops any unclosed carry.
    """
    fence = None
    lang = None
    carry = None          # text of a span opened on an earlier line
    carry_line = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            opener = FENCE.match(line)
            if opener:
                carry = None
                if fence is None:
                    fence = opener.group(1)[:3]
                    lang = opener.group(2).lower() or "plain"
                    continue
                if line.strip().startswith(fence):
                    fence = None
                    continue
            if fence is not None:
                spans = list(SPAN.finditer(line))
                for m in spans:
                    yield lineno, m.group(1), lang + "-span"
                if not spans:
                    yield lineno, line, lang
                continue
            if not line.strip():
                carry = None
                continue
            rest = line
            if carry is not None:
                head, tick, rest = rest.partition("`")
                if not tick:
                    carry += " " + head.strip()
                    continue
                yield carry_line, " ".join((carry + " " + head).split()), "wrapped-span"
                carry = None
            while True:
                _, tick, after = rest.partition("`")
                if not tick:
                    break
                body, tick2, tail = after.partition("`")
                if not tick2:
                    carry, carry_line = body.strip(), lineno
                    break
                yield lineno, body, "span"
                rest = tail


def expand_braces(text):
    """Expand one level of `{a,b}` at a time, the way bash does."""
    m = re.search(r"\{([^{}]*,[^{}]*)\}", text)
    if not m:
        return [text]
    out = []
    for part in m.group(1).split(","):
        out += expand_braces(text[: m.start()] + part + text[m.end():])
    return out


def commands(snippet):
    """Yield (directory, target, raw) for each make command in one quoted snippet."""
    cwd = None
    for segment in SEP.split(snippet):
        head = LEAD.sub("", segment)
        cd = re.match(r"cd\s+([^\s]+)\s*$", head)
        if cd:
            cwd = cd.group(1).strip("\"'").rstrip("/")
            continue
        if not re.match(r"make\s", head):
            continue
        rest = re.split(r"[`)#]", head[len("make"):])[0]
        tokens = rest.split()
        directory = None
        target = None
        i = 0
        while i < len(tokens):
            token = tokens[i]
            if token == "-C" and i + 1 < len(tokens):
                directory = tokens[i + 1].strip("\"'")
                i += 2
                continue
            if token.startswith("-C") and len(token) > 2:
                directory = token[2:].strip("\"'")
                i += 1
                continue
            if token.startswith("-") or "=" in token:
                i += 1
                continue
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", token):
                target = token
            break
        yield directory if directory is not None else cwd, target, ("make " + rest).strip()


def main():
    targets = declared_targets()
    if not targets:
        print("cannot check: no Makefile found under %s" % MONO, file=sys.stderr)
        return 1
    failures = []
    for dirpath, _, filenames in os.walk(DOCS):
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            shown = os.path.relpath(path, REPO)
            for lineno, snippet, lang in snippets(path):
                for directory, target, raw in commands(snippet):
                    if target is None:
                        continue
                    if directory is None:
                        failures.append((shown, lineno, lang, raw,
                                         "no -C and no cd — the monorepo root has no Makefile"))
                        continue
                    for one in expand_braces(directory):
                        if one not in targets:
                            failures.append((shown, lineno, lang, raw,
                                             "no Makefile in %r" % one))
                        elif target not in targets[one]:
                            failures.append((shown, lineno, lang, raw,
                                             "%s/Makefile does not declare %r" % (one, target)))
    for shown, lineno, lang, raw, why in failures:
        print("%s:%d: [%s] %s  <-  %s" % (shown, lineno, lang, raw, why))
    if failures:
        print("\n%d quoted command(s) would not run from the monorepo root." % len(failures))
        print("Name the directory (`make -C <dir> <target>`), or say in prose that the")
        print("target does not exist instead of quoting it as a command.")
        return 1
    print("all make citations in %s run from the monorepo root"
          % os.path.relpath(DOCS, REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
