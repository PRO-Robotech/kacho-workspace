#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""heavy-guard — тяжёлая команда без слота памяти не запускается.

Предмет: решение владельца 2026-09-24 «контроль за оперативной памятью не должна
переваливать за 45гб». Слот (`scripts/heavy-slot.sh`) держит потолок, только если
через него идут ВСЕ тяжёлые прогоны; команда в обход него — ровно та полоса,
которая «видела, что памяти хватает». Страж стоит на PreToolUse(Bash) и отказывает
такой команде с текстом, как запустить её правильно.

Судит РАЗОБРАННУЮ команду, а не текст: строка режется на простые команды по
управляющим операторам вне кавычек (включая `$(…)`, обратные кавычки и тела
`bash -c`), тела heredoc и комментарии выбрасываются, у каждой простой команды
снимаются присваивания и обёртки (`timeout`, `env`, `xargs`, `nice`, `sudo`, …).
Поэтому «go test -race» в сообщении коммита, в grep-образце или в записываемом
heredoc-файле не находка, а `cd x && timeout 900 go test -race ./...` — находка.

Команда слота (`heavy-slot.sh <класс> -- …`) законна целиком: её argv[0] — слот,
и ни одна форма тяжёлого с него не начинается; хвост после `--` — его аргументы.

Исходы: 0 без вывода — пропуск; 2 и текст в stderr — отказ (текст видит тот, кто
звал Bash: исполнитель, у диспетчера Bash нет); 0 и additionalContext «СЛОМАН» —
страж не смог судить. Последнее — пропуск, а не отказ, намеренно: сломанный страж,
отказывающий всему, остановил бы каждую полосу на любой команде; но молчать о
поломке он не вправе, и слово доходит до модели.
"""

import json
import os
import re
import shlex
import sys

# Имена классов — те же, что у слота (`heavy-slot.sh --classes`), в обе стороны:
# класс, которого слот не знает, дал бы исполнителю строку с кодом 64 (сверяет prove.sh).
CLASSES = ("go-race", "integration", "ci-local", "lint", "docker", "stand", "newman")

# make-цели монорепо (корневой Makefile и deploy/Makefile). Каждая обязана
# существовать в дереве продукта — запись без предмета находит prove.sh.
MAKE_TARGETS = {
    "test": "go-race",
    "test-unit": "go-race",
    "test-service": "go-race",
    "test-service-short": "go-race",
    "test-integration": "integration",
    "test-pg-outside-selection": "integration",
    "dev-up": "stand",
    "reload-svc": "stand",
    "reload-svc-nlb": "stand",
    "e2e-test": "newman",
    "e2e-newman": "newman",
}
# Цель, которой в монорепо нет, но которая названа в правилах как авторитетная
# форма линтера (kaname): `make lint`.
MAKE_TARGETS_ELSEWHERE = {"lint": "lint"}

SCRIPTS = {
    "ci-local.sh": "ci-local",
    "newman-e2e.sh": "newman",
    "newman-parallel.sh": "newman",
}

WRAPPERS_NOARG = {"nohup", "command", "exec", "time", "setsid", "builtin", "!", "{",
                  "do", "then", "else", "elif", "if", "while", "until"}
# обёртка → опции, берущие значение отдельным словом
WRAPPERS_OPTS = {
    "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "--class", "--classdata"},
    "stdbuf": {"-i", "-o", "-e"},
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"},
    "xargs": {"-a", "-d", "-E", "-I", "-L", "-n", "-P", "-s", "--arg-file", "--delimiter",
              "--max-args", "--max-procs", "--max-lines", "--max-chars"},
    "npx": {"-p", "--package"},
    "chrt": set(),
    "taskset": set(),
}
SHELLS = {"bash", "sh", "zsh", "dash"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_.-]*)\1")


def strip_heredocs(text):
    """Тела heredoc — данные, а не команды."""
    out, lines, i = [], text.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        ends = [m.group(2) for m in HEREDOC.finditer(line) if "<<<" not in line[max(0, m.start() - 1):m.start() + 3]]
        i += 1
        for word in ends:
            while i < len(lines) and lines[i].strip() != word:
                i += 1
            i += 1
    return "\n".join(out)


def split_commands(text):
    """Режет строку на простые команды вне кавычек; тела `$(…)` и `…` — отдельно."""
    parts, cur, i, n = [], [], 0, len(text)
    quote = None
    while i < n:
        c = text[i]
        if quote == "'":
            cur.append(c)
            if c == "'":
                quote = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            cur.append(text[i:i + 2])
            i += 2
            continue
        if c == "$" and text[i + 1:i + 2] == "(" and text[i + 2:i + 3] != "(":
            depth, j = 1, i + 2
            while j < n and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            parts.extend(split_commands(text[i + 2:j - 1]))
            cur.append("__SUBST__")
            i = j
            continue
        if c == "`":
            j = text.find("`", i + 1)
            j = n if j < 0 else j
            parts.extend(split_commands(text[i + 1:j]))
            cur.append("__SUBST__")
            i = j + 1
            continue
        if quote == '"':
            cur.append(c)
            if c == '"':
                quote = None
            i += 1
            continue
        if c in "'\"":
            quote = c
            cur.append(c)
            i += 1
            continue
        if c == "#" and (not cur or cur[-1] in " \t"):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "&" and (text[i - 1:i] in ("<", ">") or text[i + 1:i + 2] == ">"):
            cur.append(c)  # 2>&1, >&2, &>файл — перенаправление, а не фон
            i += 1
            continue
        if c in ";&|\n()":
            parts.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


def words(segment):
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def unwrap(argv):
    """Снимает присваивания и обёртки. Возвращает (присваивания, argv команды)."""
    env, i = [], 0
    while i < len(argv):
        w = argv[i]
        if ASSIGN.match(w):
            env.append(w)
            i += 1
            continue
        base = os.path.basename(w)
        if base in WRAPPERS_NOARG:
            i += 1
            continue
        if base == "env":
            i += 1
            while i < len(argv) and (argv[i].startswith("-") or ASSIGN.match(argv[i])):
                if ASSIGN.match(argv[i]):
                    env.append(argv[i])
                i += 2 if argv[i] in ("-u", "--unset", "-C", "--chdir") else 1
            continue
        if base in WRAPPERS_OPTS:
            opts, i = WRAPPERS_OPTS[base], i + 1
            while i < len(argv) and argv[i].startswith("-"):
                i += 2 if argv[i] in opts else 1
            if base == "timeout" and i < len(argv):
                i += 1  # длительность
            if base in ("chrt", "taskset") and i < len(argv):
                i += 1  # приоритет / маска
            continue
        break
    return env, argv[i:]


def flag_value(args, names):
    """Значения флага в формах `-f v`, `-f=v`, `--f v`, `--f=v`."""
    vals = []
    for k, a in enumerate(args):
        for nm in names:
            if a == nm and k + 1 < len(args):
                vals.append(args[k + 1])
            elif a.startswith(nm + "="):
                vals.append(a[len(nm) + 1:])
    return vals


def go_test_class(args, env):
    """args — после `go test`."""
    goflags = " ".join(e.split("=", 1)[1] for e in env if e.startswith("GOFLAGS="))
    allargs = args + goflags.split()
    tags = ",".join(flag_value(allargs, ("-tags", "--tags")))
    if "integration" in re.split(r"[,\s]+", tags):
        return "integration"
    if any(a in ("-race", "--race", "-race=true", "--race=true") for a in allargs):
        return "go-race"
    return None


def repo_top(path):
    p = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(p, ".git")):
            return p
        up = os.path.dirname(p)
        if up == p:
            return None
        p = up


def push_runs_ci_local(path):
    """git push тяжёл там, где pre-push клона зовёт ci-local.sh (признак — дерево)."""
    top = repo_top(path)
    if not top or not os.path.isfile(os.path.join(top, "scripts", "ci-local.sh")):
        return False
    try:
        with open(os.path.join(top, "scripts", "hooks", "pre-push"), encoding="utf-8") as fh:
            return "ci-local.sh" in fh.read()
    except OSError:
        return False


DOCKER_GLOBAL_VALUE = {"--context", "-c", "-H", "--host", "--config", "-l", "--log-level",
                       "--tlscacert", "--tlscert", "--tlskey"}
DOCKER_HEAVY = {"run", "create", "start", "build"}
COMPOSE_HEAVY = {"up", "run", "build", "start", "create"}


def docker_class(args):
    """args — после `docker`. Класс тоньше `docker`, если внутри go test."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in DOCKER_GLOBAL_VALUE else 1
    rest = args[i:]
    if not rest:
        return None
    sub, tail = rest[0], rest[1:]
    if sub in ("container", "image", "buildx", "builder") and tail:
        sub, tail = tail[0], tail[1:]
    if sub == "compose":
        heavy = any(t in COMPOSE_HEAVY for t in tail if not t.startswith("-"))
        return "docker" if heavy else None
    if sub not in DOCKER_HEAVY:
        return None
    if sub == "run":
        # Команда контейнера — хвост после образа, либо строка `sh -c '…'` в нём.
        # Её класс уточняет бюджет: go test -race в golang — это go-race, а с
        # docker.sock внутри — integration (testcontainers ходят в dockerd машины).
        env = [a.split("=", 1)[1] if a.startswith("--env=") else a for a in tail if "GOFLAGS=" in a]
        sock = any("docker.sock" in a for a in tail)
        for k, a in enumerate(tail):
            if a == "go" and tail[k + 1:k + 2] == ["test"]:
                inner = go_test_class(tail[k + 2:], env)
            elif a in SHELLS and tail[k + 1:k + 2] == ["-c"] and k + 2 < len(tail):
                inner = classify_text(tail[k + 2], None)
            else:
                continue
            if inner in ("go-race", "integration"):
                return "integration" if sock else inner
    return "docker"


def classify_argv(env, argv, cwd):
    """Класс простой команды или None."""
    if not argv:
        return None
    base = os.path.basename(argv[0])
    args = argv[1:]
    if base in SHELLS:
        if "-c" in args:
            k = args.index("-c")
            if k + 1 < len(args):
                return classify_text(args[k + 1], cwd)
            return None
        script = next((a for a in args if not a.startswith("-")), None)
        if script is None:
            return None
        return classify_argv(env, [script] + args[args.index(script) + 1:], cwd)
    if base == "eval":
        return classify_text(" ".join(args), cwd)
    if base in ("make", "gmake"):
        if any(a in ("-n", "--dry-run", "--just-print", "--recon", "-q", "--question") for a in args):
            return None
        targets, k = [], 0
        while k < len(args):
            a = args[k]
            if a in ("-C", "-f", "-I", "-j", "-l", "-o", "-W", "--directory", "--file", "--makefile"):
                k += 2
                continue
            if not a.startswith("-") and "=" not in a:
                targets.append(a)
            k += 1
        for t in targets:
            c = MAKE_TARGETS.get(t) or MAKE_TARGETS_ELSEWHERE.get(t)
            if c:
                return c
        return None
    if base in SCRIPTS:
        return SCRIPTS[base]
    if base == "go" and args[:1] == ["test"]:
        return go_test_class(args[1:], env)
    if base == "golangci-lint" and "run" in args:
        return "lint"
    if base in ("govulncheck", "gosec"):
        return "lint"
    if base == "docker":
        return docker_class(args)
    if base == "docker-compose" and any(a in COMPOSE_HEAVY for a in args):
        return "docker"
    if base == "kind" and args[:2] == ["create", "cluster"]:
        return "stand"
    if base == "helm" and args[:1] and args[0] in ("install", "upgrade"):
        return "stand"
    if base == "newman" and args[:1] == ["run"]:
        return "newman"
    if base == "git":
        k, where = 0, None
        while k < len(args) and args[k].startswith("-"):
            if args[k] == "-C" and k + 1 < len(args):
                where = args[k + 1]
                k += 2
            elif args[k] in ("-c", "--git-dir", "--work-tree", "--namespace"):
                k += 2
            else:
                k += 1
        if args[k:k + 1] == ["push"] and "--no-verify" not in args:
            base_dir = cwd or os.getcwd()
            path = os.path.join(base_dir, os.path.expanduser(where)) if where else base_dir
            if push_runs_ci_local(path):
                return "ci-local"
    return None


def classify_text(text, cwd):
    """Первый тяжёлый класс в строке команды: (класс, простая команда) либо None."""
    hit = find_heavy(text, cwd)
    return hit[0] if hit else None


def find_heavy(text, cwd):
    cur = cwd
    for seg in split_commands(strip_heredocs(text)):
        env, argv = unwrap(words(seg))
        if argv and argv[0] in ("cd", "pushd") and len(argv) > 1 and "__SUBST__" not in argv[1]:
            cur = os.path.join(cur or os.getcwd(), os.path.expanduser(argv[1]))
            continue
        c = classify_argv(env, argv, cur)
        if c:
            return c, env, argv
    return None


REDIRECT = re.compile(r"^(\d*|&)(>>?|<)&?[\w./-]*$")


def show(ws):
    return " ".join(w if REDIRECT.match(w) else shlex.quote(w) for w in ws)


def deny(cls, env, argv, slot):
    shown = show(argv)
    fixed = " ".join([show(env), slot, cls, "--", shown]).strip()
    if len(fixed) > 400:
        fixed = fixed[:400] + " …"
        shown = shown[:300] + " …"
    sys.stderr.write(
        "HEAVY-GUARD: отказ — тяжёлая команда без слота памяти (класс «%s»).\n"
        "  найдено: %s\n"
        "Машина держит ≤ 45 ГиБ на всё (решение владельца 2026-09-24); тяжёлое входит только\n"
        "через слот: он ждёт памяти, а не отнимает её у соседних полос, и держит команду\n"
        "под жёстким пределом бюджета класса.\n"
        "Как запустить правильно (остальная строка — как была):\n"
        "  %s\n"
        "  · ожидание слота — до 30 мин: долгий прогон — с run_in_background: true;\n"
        "  · классы и бюджеты: %s --classes · кто занял: %s --status;\n"
        "  · коды: 75 — слот не выдан, 76 — оборвано пределом памяти: оба «не выполнилось»,\n"
        "    не красное; иначе — код самой команды.\n"
        "Быстрое по своим пакетам (go test без -race, go vet, gofmt) слота не требует.\n"
        % (cls, shown, fixed, slot, slot))
    sys.exit(2)


def broken(why):
    msg = ("HEAVY-GUARD СЛОМАН: %s. Тяжёлые команды этим вызовом НЕ проверялись — это не "
           "«чисто». Тяжёлое (go test -race, integration, ci-local, golangci-lint, docker run, "
           "стенд, newman) всё равно запускай через scripts/heavy-slot.sh <класс> -- <команда>; "
           "починка — tooling-maintainer." % why)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}, ensure_ascii=False))
    sys.exit(0)


def main():
    if sys.argv[1:] == ["--classes"]:
        print("\n".join(CLASSES))
        return
    if sys.argv[1:] == ["--make-targets"]:
        print("\n".join(sorted(MAKE_TARGETS)))
        return
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError) as exc:
        broken("вход хука не разобран как JSON (%s)" % exc)
    if data.get("tool_name") not in (None, "Bash"):
        return
    cmd = (data.get("tool_input") or {}).get("command")
    if not isinstance(cmd, str):
        broken("у вызова Bash нет tool_input.command")
    ws = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    slot = os.path.join(ws, "scripts", "heavy-slot.sh")
    hit = find_heavy(cmd, data.get("cwd") or os.getcwd())
    if hit:
        cls, env, argv = hit
        deny(cls, env, argv, slot)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — страж обязан сказать о своей поломке
        broken("%s: %s" % (type(exc).__name__, exc))
