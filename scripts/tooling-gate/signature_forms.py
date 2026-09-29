#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Распознаватель check-22: переопределение подписи git в исполняемом коде дерева.

Предмет — п.7 правила подписи (`.claude/rules/git-issues.md`,
gi-identity-owner-only): author и committer берутся ТОЛЬКО из корневого
gitconfig, и это действует в рабочем клоне и в песочнице пробы одинаково
(решение диспетчера 2026-09-27, ws#785). Находка — форма, которая подпись
переопределяет:

  на-команду   `-c <кто>.<что>=…`, `--config-env=<кто>.<что>=…`;
  на-репо      `config` с ключом подписи и значением без `--global`/`--system`
               (по умолчанию, `--local`, `--worktree`, `--file`, `--blob`);
  литерал      `config --global <ключ> <литерал>` — корень получает имя, не
               взятое ни из какого источника (значение с подстановкой `$` —
               перенос корневой подписи в HOME песочницы либо на ранер);
  окружение    присваивание `GIT_AUTHOR_NAME`/`_EMAIL`, `GIT_COMMITTER_NAME`/`_EMAIL`;
  флаг         `--author` у `commit`;
  запись       printf/echo с `>`/`>>`, `tee` и heredoc в файл конфигурации git:
               секция `user`/`author`/`committer` с ключом `name`/`email` в
               `.gitconfig` или `.config/git/config` — литерал (как `config
               --global`), в `.git/config` или `config.worktree` — любое значение
               (как `config` без `--global`); ws#873.

<кто> — `user`, `author`, `committer`; <что> — `name`, `email`; регистр ключа
git не различает, распознаватель тоже.

НЕ находка, и каждая — законный близнец той же формы: чтение
(`config --get …`, `config <ключ>` без значения), снятие (`unset GIT_AUTHOR_NAME`,
`env -u …`, `os.environ.pop(…)`), время коммита (`GIT_AUTHOR_DATE`,
`GIT_COMMITTER_DATE` — не подпись: держатель п.7 меряет `%an %ae`), другой ключ
той же формы (`-c core.hooksPath=…`), фильтр чтения (`git log --author=…`),
комментарий.

ЧТО НЕ СУДИТСЯ, И ЭТО ГРАНИЦА: чьё имя записано в корень, когда значение —
подстановка; ключ подписи, данный подстановкой (`git config "$k" …`), и файл
конфигурации, названный подстановкой целиком (`> "$GIT_CONFIG_GLOBAL"`); запись
файла конфигурации из Python (`open(…).write`); shell-строка внутри
Python-литерала; файлы вне трёх видов (оболочка, Python, конвейер).

Три исхода: 0 — осмотрено, находок нет; 1 — находки с координатой; 2 — обход
пуст либо часть Python-файлов не разобрана (вердикта о них нет).
"""
import ast
import pathlib
import re
import subprocess
import sys

WHO = ("user", "author", "committer")
WHAT = ("name", "email")
KEY_RE = re.compile(r"^(?:%s)\.(?:%s)$" % ("|".join(WHO), "|".join(WHAT)), re.I)
KEY_ASSIGN_RE = re.compile(r"^(?:%s)\.(?:%s)=" % ("|".join(WHO), "|".join(WHAT)), re.I)
ENV_NAMES = tuple("GIT_%s_%s" % (a, b) for a in ("AUTHOR", "COMMITTER") for b in ("NAME", "EMAIL"))
ENV_RE = re.compile(r"^(?:%s)$" % "|".join(ENV_NAMES))

KEY_ALT = r"(?:%s)\.(?:%s)" % ("|".join(WHO), "|".join(WHAT))
SH_PER_CMD = re.compile(r"(?:^|[\s'\"(])(?:-c\s*|--config-env[=\s]\s*)['\"]?%s=" % KEY_ALT, re.I)
SH_CFG_ENV = re.compile(r"GIT_CONFIG_(?:KEY_\w+=['\"]?|PARAMETERS=.*)%s\b" % KEY_ALT, re.I)
SH_ENV = re.compile(r"(?:^|[\s;&|(`'\"])(?:%s)=" % "|".join(ENV_NAMES))
YAML_ENV_KEY = re.compile(r"^\s*-?\s*['\"]?(?:%s)['\"]?\s*:" % "|".join(ENV_NAMES))

READ_OPTS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l",
             "--unset", "--unset-all", "--remove-section", "--rename-section",
             "--name-only", "--show-origin", "--show-scope", "-e", "--edit"}
READ_SUBCMDS = {"get", "list", "unset", "remove-section", "rename-section", "edit"}
ROOT_OPTS = {"--global", "--system"}
TAKES_ARG = {"--file", "-f", "--blob", "--type", "--default", "--comment", "--value"}

REASON = {
    "per-command": "подпись на команду (-c / --config-env)",
    "per-repo": "подпись на репозиторий (config без --global)",
    "literal-root": "литерал подписи в корневой gitconfig",
    "env": "подпись окружением (GIT_*_NAME / GIT_*_EMAIL)",
    "author": "подпись флагом --author у commit",
}


def judge_config(tokens):
    """tokens — последовательность аргументов; None — не литерал (подстановка).
    Возвращает вид находки либо None."""
    for i, tok in enumerate(tokens):
        if tok != "config":
            continue
        opts, key, value_present, value_literal = set(), None, False, False
        j = i + 1
        while j < len(tokens):
            t = tokens[j]
            if key is None:
                if t is None:
                    break
                if t.startswith("-"):
                    base = t.split("=", 1)[0]
                    opts.add(base)
                    if base in TAKES_ARG and "=" not in t:
                        j += 1
                    j += 1
                    continue
                if t in READ_SUBCMDS or t == "set":
                    opts.add(t)
                    j += 1
                    continue
                if KEY_RE.match(t):
                    key = t
                    j += 1
                    continue
                break
            else:
                value_present = True
                value_literal = t is not None and "$" not in t
                break
        if key is None:
            continue
        if opts & READ_OPTS or opts & READ_SUBCMDS or not value_present:
            continue
        if opts & ROOT_OPTS and not opts & {"--file", "-f", "--local", "--worktree", "--blob"}:
            if value_literal:
                return "literal-root"
            continue
        return "per-repo"
    return None


def judge_per_command(tokens):
    prev = None
    for t in tokens:
        if t is not None:
            if prev in ("-c", "--config-env") and KEY_ASSIGN_RE.match(t):
                return "per-command"
            if t.startswith("-c") and KEY_ASSIGN_RE.match(t[2:]):
                return "per-command"
            if t.startswith("--config-env=") and KEY_ASSIGN_RE.match(t[len("--config-env="):]):
                return "per-command"
        prev = t
    return None


def judge_author(tokens):
    if "commit" not in tokens:
        return None
    for t in tokens:
        if t is not None and (t == "--author" or t.startswith("--author=")):
            return "author"
    return None


# ── оболочка и конвейер ─────────────────────────────────────────────────────

def strip_comment(line):
    """Снять комментарий оболочки: `#` вне кавычек в начале слова."""
    q = None
    k = 0
    while k < len(line):
        ch = line[k]
        if q:
            if ch == "\\" and q == '"':
                k += 2
                continue
            if ch == q:
                q = None
        elif ch in "'\"":
            q = ch
        elif ch == "\\":
            k += 2
            continue
        elif ch == "#" and (k == 0 or line[k - 1] in " \t;&|("):
            return line[:k]
        k += 1
    return line


REDIRECT_RE = re.compile(r"^(?:\d*|&)[<>]")
TOKEN_RE = re.compile(r"""'[^']*'|"(?:\\.|[^"\\])*"|[^\s'"]+""")
SEG_SPLIT = re.compile(r"&&|\|\||[;|()`]|\$\(")


def shell_tokens(segment):
    out = []
    for raw in TOKEN_RE.findall(segment):
        t = raw
        if len(t) >= 2 and t[0] == t[-1] and t[0] in "'\"":
            t = t[1:-1]
        t = t.strip("[](),")
        if not t or REDIRECT_RE.match(t):
            continue
        out.append(t)
    return out


def logical_lines(text):
    buf, start = "", None
    for no, line in enumerate(text.split("\n"), 1):
        code = strip_comment(line)
        if start is None:
            start = no
        if code.rstrip().endswith("\\"):
            buf += code.rstrip()[:-1] + " "
            continue
        buf += code
        yield start, buf
        buf, start = "", None
    if buf:
        yield start, buf


# ── запись файла конфигурации git мимо `git config` (ws#873) ────────────────
#
# Форма: printf/echo с перенаправлением (`>`, `>>`) либо `tee` в файл конфигурации
# git, и heredoc в такой файл. Корневой файл — `.gitconfig` и `.config/git/config`
# (литерал подписи — находка, подстановка — перенос корневой подписи, молчит);
# файл репозитория — `.git/config` и `config.worktree` (находка при любом
# значении, как у `git config` без `--global`). Секция запоминается по файлу:
# `echo "[user]" >> …` и `echo "name = x" >> …` строками подряд — та же запись.

WRITE_TARGET = re.compile(r"""(?:(?<![0-9&<>])>>?\|?|\btee\s+(?:-a\s+|--append\s+)*)\s*("[^"]*"|'[^']*'|[^\s;&|)<>]+)""")
HEREDOC = re.compile(r"""<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1""")
SECTION = re.compile(r"\[\s*([A-Za-z][A-Za-z0-9.-]*)(?:\s+\"[^\"]*\")?\s*\]", re.I)
SIG_KEY = re.compile(r"(?:^|[\s'\"])(%s)\s*=\s*(.*)$" % "|".join(WHAT), re.I)


def config_target(line):
    """Вид файла конфигурации git, в который пишет строка: 'root', 'repo' либо None."""
    for m in WRITE_TARGET.finditer(line):
        t = m.group(1).strip("'\"").rstrip("/")
        if t.endswith(".git/config") or t.endswith("config.worktree"):
            return "repo"
        if t.endswith(".gitconfig") or t.endswith(".config/git/config"):
            return "root"
    return None


def config_pieces(text):
    """Строки записываемого содержимого: `\\n` формата printf — перевод строки."""
    return text.replace("\\t", " ").replace("\\n", "\n").split("\n")


def judge_config_text(pieces, section, target):
    """Секция после разбора и находка ('literal-root' | 'per-repo' | None)."""
    kind = None
    for piece in pieces:
        m = None
        for m in SECTION.finditer(piece):
            pass
        if m is not None:
            section = m.group(1).lower()
            piece = piece[m.end():]
        k = SIG_KEY.search(piece)
        if not k or section not in WHO:
            continue
        value = re.match(r"[^'\"]*", k.group(2)).group(0).strip()
        if target == "repo":
            kind = kind or "per-repo"
        elif value and not re.search(r"[$%`]", value):
            kind = kind or "literal-root"
    return section, kind


def judge_config_writes(lines):
    """lines — список (номер, логическая строка). Находки записи конфигурации и
    число осмотренных записей: «находок 0» отличимо от «записей 0»."""
    found = []
    writes = 0
    section = {"root": None, "repo": None}
    i = 0
    while i < len(lines):
        no, line = lines[i]
        target = config_target(line)
        i += 1
        if target is None:
            continue
        writes += 1
        h = HEREDOC.search(line)
        if h:
            delim = h.group(2)
            while i < len(lines) and lines[i][1].strip() != delim:
                bno, body = lines[i]
                section[target], kind = judge_config_text([body], section[target], target)
                if kind:
                    found.append((bno, kind, body))
                i += 1
            i += 1
            continue
        section[target], kind = judge_config_text(config_pieces(line), section[target], target)
        if kind:
            found.append((no, kind, line))
    return found, writes


def judge_shell(text, yaml=False):
    found = []
    n = 0
    lines = list(logical_lines(text))
    writes_found, writes = judge_config_writes(lines)
    written = {no: (kind, src) for no, kind, src in writes_found}
    for no, line in lines:
        n += 1
        if no in written:
            found.append((no,) + written[no])
            continue
        if yaml and YAML_ENV_KEY.search(line):
            found.append((no, "env", line))
            continue
        if SH_PER_CMD.search(line) or SH_CFG_ENV.search(line):
            found.append((no, "per-command", line))
            continue
        if SH_ENV.search(line):
            found.append((no, "env", line))
            continue
        for seg in SEG_SPLIT.split(line):
            toks = shell_tokens(seg)
            kind = judge_per_command(toks) or judge_config(toks) or judge_author(toks)
            if kind:
                found.append((no, kind, line))
                break
    return found, n, writes


# ── Python ──────────────────────────────────────────────────────────────────

def flat_args(call):
    seq = []
    for a in call.args:
        items = a.elts if isinstance(a, (ast.List, ast.Tuple)) else [a]
        for it in items:
            if isinstance(it, ast.Constant) and isinstance(it.value, str):
                seq.append(it.value)
            elif isinstance(it, ast.Starred) and isinstance(it.value, (ast.List, ast.Tuple)):
                for s in it.value.elts:
                    seq.append(s.value if isinstance(s, ast.Constant) and isinstance(s.value, str) else None)
            else:
                seq.append(None)
    return seq


def is_env_const(node):
    return isinstance(node, ast.Constant) and isinstance(node.value, str) and ENV_RE.match(node.value)


def judge_python(text):
    tree = ast.parse(text)
    found = []
    calls = 0
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            calls += 1
            seq = flat_args(node)
            kind = None
            for k, t in enumerate(seq):
                if t is None:
                    continue
                if KEY_ASSIGN_RE.match(t) or (t.startswith("--config-env=") and KEY_ASSIGN_RE.match(t[len("--config-env="):])):
                    kind = "per-command"
                    break
            kind = kind or judge_config(seq) or judge_author(seq)
            if not kind:
                for kw in node.keywords:
                    if kw.arg and ENV_RE.match(kw.arg):
                        kind = "env"
                        break
            if not kind and isinstance(node.func, ast.Attribute) and node.func.attr in ("setdefault", "putenv") \
                    and node.args and is_env_const(node.args[0]):
                kind = "env"
            if kind:
                found.append((node.lineno, kind, ast.get_source_segment(text, node) or ""))
        elif isinstance(node, ast.Dict):
            for k, v in zip(node.keys, node.values):
                if k is not None and is_env_const(k):
                    found.append((k.lineno, "env", ast.get_source_segment(text, node) or ""))
                elif (isinstance(k, ast.Constant) and isinstance(k.value, str)
                      and k.value.startswith("GIT_CONFIG_KEY_")
                      and isinstance(v, ast.Constant) and isinstance(v.value, str)
                      and KEY_RE.match(v.value)):
                    found.append((k.lineno, "per-command", ast.get_source_segment(text, node) or ""))
        elif isinstance(node, (ast.Assign, ast.AugAssign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for t in targets:
                if isinstance(t, ast.Subscript) and is_env_const(t.slice):
                    found.append((node.lineno, "env", ast.get_source_segment(text, node) or ""))
    return found, calls


# ── обход ───────────────────────────────────────────────────────────────────

def kind_of(rel, head):
    p = pathlib.PurePosixPath(rel)
    if p.suffix in (".sh", ".bash", ".bats"):
        return "shell"
    if p.suffix == ".py":
        return "python"
    if rel.startswith(".github/workflows/") and p.suffix in (".yml", ".yaml"):
        return "yaml"
    if p.suffix == "" and head.startswith("#!"):
        if "python" in head:
            return "python"
        if re.search(r"\b(ba|z|da|k)?sh\b", head):
            return "shell"
    return None


def main():
    root = pathlib.Path(sys.argv[1])
    name = sys.argv[2]
    try:
        listing = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"],
            capture_output=True, text=True, check=True).stdout.split("\n")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"[VOID] {name} — индекс git не читается, состав дерева не выведен", file=sys.stderr)
        return 2

    counts = {"shell": 0, "python": 0, "yaml": 0}
    lines = calls = cfg_writes = 0
    unparsed = []
    sandbox_users = 0
    findings = []
    for rel in sorted(set(p for p in listing if p)):
        f = root / rel
        if not f.is_file() or f.is_symlink():
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        kind = kind_of(rel, text.split("\n", 1)[0])
        if kind is None:
            continue
        counts[kind] += 1
        if "sandbox_git" in text or "sandbox_home" in text:
            sandbox_users += 1
        if kind == "python":
            try:
                got, c = judge_python(text)
            except (SyntaxError, ValueError):
                unparsed.append(rel)
                continue
            calls += c
        else:
            got, c, w = judge_shell(text, yaml=(kind == "yaml"))
            lines += c
            cfg_writes += w
        for no, what, src in got:
            findings.append((rel, no, what, " ".join(src.split())[:150]))

    files = sum(counts.values())
    print(f"[CENSUS] {name}: файлов оболочки {counts['shell']}, Python {counts['python']}, "
          f"конвейера {counts['yaml']}; логических строк {lines}; записей файла конфигурации git "
          f"{cfg_writes}; вызовов Python {calls}; "
          f"не разобрано {len(unparsed)}; песочниц на HOME со своим gitconfig {sandbox_users}; "
          f"находок {len(findings)}")
    if files == 0:
        print(f"[VOID] {name} — ни одного файла оболочки, Python или конвейера: судить нечего",
              file=sys.stderr)
        return 2
    if findings:
        files_hit = len({r for r, *_ in findings})
        print(f"[FAIL] {name} — подпись переопределена мимо корневого gitconfig: находок "
              f"{len(findings)} в файлах {files_hit}. Песочница пробы берёт подпись из "
              f"своего HOME (scripts/lib/sandbox-git-home.sh), оговорки для неё нет",
              file=sys.stderr)
        for rel, no, what, src in findings:
            print(f"       {rel}:{no}: {REASON[what]} — {src}", file=sys.stderr)
        return 1
    if unparsed:
        print(f"[VOID] {name} — Python-файлы не разобраны, вердикта о них нет: "
              + ", ".join(unparsed), file=sys.stderr)
        return 2
    print(f"[PASS] {name} — осмотрено файлов {files}: подпись нигде не переопределена")
    return 0


if __name__ == "__main__":
    sys.exit(main())
