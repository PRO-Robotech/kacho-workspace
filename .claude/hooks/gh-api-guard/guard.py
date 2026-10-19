#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""gh-api-guard — ОТКАЗ изменяющим вызовам `gh api` и вливанию мимо посадки (ws#1008).

Предмет. Агенты ci-watcher, выясняя merge-base, звали
`gh api repos/<r>/merges -X POST -f base=… -f head=…`. Этот вызов не читает, а ВЛИВАЕТ
head в base: так мимо посадки и проверок в ветки эпиков попали три PR (kacho#3142,
kacho#3144, kaname#703), а агенты этого не увидели — их `--jq` печатал `no_merge`.
«Только чтение» до этого стража держалось вниманием.

ОТКАЗ (класс — пример):
  api-write       — `gh api` с изменяющим методом: `-X/--method POST|PUT|PATCH|DELETE`
                    (любая запись: `-XPOST`, `--method=post`; группа коротких
                    флагов распаковывается как в pflag — `-iXPOST`, `-iX POST`,
                    `-if base=a` судятся по каждой букве), либо с телом
                    `-f/-F/--field/--raw-field/--input` без явного `--method GET`
                    (gh тогда сам шлёт POST); метод, не вычислимый по тексту
                    (`-X "$M"`), — тоже отказ: страж судит текст, а не исход.
                    Отказ у всех агентов, кроме git-operator;
  graphql-write   — `gh api graphql` с `mutation` в поле запроса либо с запросом из
                    файла (`-F query=@f`, `--input`): чтение GraphQL — это POST по
                    протоколу, поэтому здесь судится сам запрос, а не метод;
  merge-endpoint  — `repos/<o>/<r>/merges` и `repos/<o>/<r>/pulls/<N>/merge` с
                    изменяющим методом — отказ ВСЕМ, включая git-operator: вливание
                    делается только `gh pr merge … --match-head-commit <sha>`;
                    у git-operator — любым методом (его предмет — вливание, и чтение
                    этих путей ему не нужно);
  pr-merge        — `gh pr merge` у агента, кроме git-operator; у git-operator —
                    без `--match-head-commit`, либо с `--auto` или `--admin`.
                    `gh pr merge --disable-auto` ничего не вливает — пропуск.

Тот же предмет — запись мимо посадки — у коммита не в ту копию (ws#1237): исполнитель
kaname#878 сделал `cd <относительный путь> && git add -A && git commit`, каталог вызова
Bash был корнем воркспейса, и коммит лёг в main воркспейса (снят update-ref). Классы:
  commit-unanchored — `git add` / `git commit`, чей каталог выведен от каталога вызова
                    ОТНОСИТЕЛЬНЫМ шагом (`cd tmp/x`, `pushd ..`, `git -C tmp/x`) раньше
                    любого абсолютного: каталог вызова у сабагента сбрасывается, и
                    относительный путь разрешается не от копии. Абсолютный `cd` или
                    `-C` (литерал либо переменная строки или окружения с абсолютным
                    значением) — якорь, после него относительный шаг законен;
                    переменная с относительным значением (`X=rel; cd $X/y`) — шаг
                    относительный; значение `-c k=v` перед `-C` пропускается;
  commit-trunk    — `git add` / `git commit` в ОСНОВНОМ клоне (git-dir равен общему),
                    стоящем на `main`/`master`: ствол коммитом не пишется ни у кого —
                    работа в ветке своей копии под tmp/. Каталог вычисляется от поля
                    `cwd` входа хука тем же разбором; не вычислим (`cd "$X"` без
                    присваивания в строке) — класс не судится.

РАЗРЕШЕНО: `gh api <путь>` без тела и метода (GET), `gh api --method GET … -f q=…`
(поля уходят строкой запроса), `gh api graphql -f query='query{…}'`, `compare`,
`git merge-base`; у git-operator — изменяющие вызовы, кроме путей вливания;
`git -C <абсолютная копия> add|commit` в связанной копии (worktree) либо в клоне на ветке.

Кто вызвал — поле agent_type входа хука; его нет — вызов судится как не git-operator
(закрыто по умолчанию: отсутствие поля не выдаёт право записи).

Судит РАЗОБРАННУЮ строку тем же лексером, что no-wait-guard (его `tokens`, `Parser`,
`head`; слова — `words` heavy-guard): списки, конвейеры, группы, циклы, `bash -c`,
`$(…)` и heredoc, поданный оболочке. Второго лексера кавычек здесь нет.

Исходы: 0 без вывода — пропуск; 2 и текст в stderr — отказ; 0 и additionalContext
«СЛОМАН» — страж не смог судить (громко, но не запирая).

ГРАНИЦА (не ловится, известно): вызов внутри скрипта или рецепта make (страж судит
строку, а не текст файла); команда, собранная во время исполнения, — `eval "gh api …"`,
`echo … | xargs gh api …`, `$GH api …`; иной клиент того же API — `curl -X POST
https://api.github.com/…` и интерпретатор (`python3 -c …`); `git push` в ветку эпика
(другой класс: его держат хук отправки и защита ветки); коммит — иные записи истории
(`merge`, `cherry-pick`, `am`, `revert`), `--git-dir`/`--work-tree`, каталог из
`$(…)` и из переменной без присваивания в строке; `cd` внутри подоболочки `( … )`
считается действующим и после неё.
"""

import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "no_wait_guard", os.path.join(os.path.dirname(HERE), "no-wait-guard", "guard.py"))
nwg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nwg)   # он же кладёт heavy-guard в sys.path и берёт его `guard`
hg = nwg.hg

OPERATOR = "git-operator"
WRITE = {"POST", "PUT", "PATCH", "DELETE"}
READ = {"GET", "HEAD"}
# флаги `gh api` со значением (длинная форма → короткая)
VALUED_LONG = {"--method", "--field", "--raw-field", "--header", "--input", "--jq",
               "--template", "--hostname", "--preview", "--cache"}
VALUED_SHORT = {"-X", "-F", "-f", "-H", "-q", "-t", "-p"}
FIELD = {"-f", "-F", "--field", "--raw-field"}
MERGES = re.compile(r"(^|/)repos/[^/\s]+/[^/\s]+/merges/?(\?|$)")
PR_MERGE = re.compile(r"(^|/)repos/[^/\s]+/[^/\s]+/pulls/[^/\s]+/merge/?(\?|$)")
MUTATION = re.compile(r"(^|[^A-Za-z0-9_])mutation([^A-Za-z0-9_]|$)")

CLASS_TEXT = {
    "api-write": "изменяющий вызов gh api (метод записи либо тело без --method GET)",
    "graphql-write": "gh api graphql с mutation либо запросом, не видимым в строке",
    "merge-endpoint": "путь вливания repos/*/merges или pulls/*/merge",
    "pr-merge": "gh pr merge вне правила вливания",
    "commit-unanchored": "git add/commit после относительного cd или -C",
    "commit-trunk": "git add/commit в стволе основного клона",
}
TRUNKS = {"main", "master"}
COMMIT_SUBS = {"add", "commit"}
# глобальные ключи git со значением отдельным словом (кроме -C, он — шаг каталога)
GIT_VALUED = {"-c", "--namespace", "--config-env", "--super-prefix", "--exec-path",
              "--list-cmds", "--attr-source"}
VAR = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")


class Finding:
    def __init__(self, cls, text, why):
        self.cls, self.text, self.why = cls, text, why


def short_group(a):
    """Группа коротких флагов так, как её читает pflag (gh): КАЖДАЯ буква — флаг.

    Буква, требующая значения (VALUED_SHORT), берёт остаток группы (`-iXPOST` → -i, -X POST)
    либо, если остатка нет, следующий аргумент (`-iX POST`, `-if base=a`); `=` сразу за
    буквой отделяет значение (`-X=POST`, `-i=true`). Возвращает ([(флаг, значение|None)],
    нужен_ли_следующий_аргумент). Судить группу по первой букве нельзя: `-iXPOST` — это
    POST, хотя начинается с безобидного `-i` (возврат check-verifier, ws#1008).
    """
    out = []
    j = 1
    while j < len(a):
        name, rest = "-" + a[j], a[j + 1:]
        if rest.startswith("="):
            out.append((name, rest[1:]))
            return out, False
        if name in VALUED_SHORT:
            out.append((name, rest or None))
            return out, not rest
        out.append((name, None))
        j += 1
    return out, False


def api_call(args):
    """Разбор `gh api …` (args — после `api`): (путь, метод|None, поля, --input)."""
    endpoint, method, fields, inp = None, None, [], False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            if endpoint is None and i + 1 < len(args):
                endpoint = args[i + 1]
            break
        pairs = []
        if a.startswith("--"):
            name, val = a, None
            if "=" in a:
                name, val = a.split("=", 1)
            if name in VALUED_LONG and val is None:
                val = args[i + 1] if i + 1 < len(args) else ""
                i += 1
            pairs.append((name, val))
        elif a.startswith("-") and len(a) > 1:
            pairs, need = short_group(a)
            if need:
                pairs[-1] = (pairs[-1][0], args[i + 1] if i + 1 < len(args) else "")
                i += 1
        elif endpoint is None:
            endpoint = a
        i += 1
        for name, val in pairs:
            if name in ("-X", "--method"):
                method = (val or "").strip().upper()
            elif name in FIELD:
                fields.append(val or "")
            elif name == "--input":
                inp = True
    return endpoint or "", method, fields, inp


def judge_api(args, agent, shown):
    endpoint, method, fields, inp = api_call(args)
    ep = endpoint.split("?", 1)[0].strip()
    merge_path = bool(MERGES.search(ep) or PR_MERGE.search(ep))
    explicit_read = method in READ
    # метод вне READ — запись, в том числе не вычислимый по тексту (`-X "$M"`):
    # страж судит текст, и отсутствие доказанного чтения права записи не даёт
    writes = method in WRITE or (method is None and (fields or inp)) or (
        method is not None and method not in READ)
    if ep.lstrip("/") == "graphql":
        bad = [f for f in fields if MUTATION.search(f) or re.match(r"^[A-Za-z_]+=@", f)]
        if (bad or inp) and agent != OPERATOR:
            return Finding("graphql-write", shown,
                           "запрос с mutation" if any(MUTATION.search(f) for f in bad)
                           else "запрос из файла — страж его не видит")
        return None
    if merge_path and (writes or agent == OPERATOR):
        return Finding("merge-endpoint", shown,
                       "путь вливания: этот вызов ВЛИВАЕТ ветку, а не читает" if writes
                       else "путь вливания у git-operator — вливание только gh pr merge --match-head-commit")
    if writes and not explicit_read and agent != OPERATOR:
        return Finding("api-write", shown,
                       ("метод %s" % method if re.fullmatch(r"[A-Z]+", method) else
                        "метод не вычислим по тексту — запись не исключена") if method
                       else "тело (-f/-F/--input) без --method GET — gh шлёт POST")
    return None


def judge_pr_merge(args, agent, shown):
    flags = set()
    for a in args:
        flags.add(a.split("=", 1)[0] if a.startswith("--") else a)
    if "--disable-auto" in flags:
        return None
    if agent != OPERATOR:
        return Finding("pr-merge", shown, "вливание — шаг git-operator, у агента «%s» его нет" % (agent or "без agent_type"))
    if "--auto" in flags:
        return Finding("pr-merge", shown, "--auto вливает позже без сверки головы")
    if "--admin" in flags:
        return Finding("pr-merge", shown, "--admin обходит защиту ветки")
    if "--match-head-commit" not in flags:
        return Finding("pr-merge", shown, "нет --match-head-commit <sha головы из landing-precheck>")
    return None


def trunk_clone(d):
    """(верх клона, ветка), если `d` — в основном клоне на main/master; иначе None.

    Основной клон — git-dir равен общему (у связанной копии worktree git-dir свой).
    Окружение git вызова снимается: страж судит каталог, а не чужой GIT_DIR. Каталога
    нет, не репозиторий, git не ответил за 3 с — None: судить нечем, отказа нет.
    """
    if not os.path.isdir(d):
        return None
    import subprocess  # здесь, а не в шапке: 4–7 мс импорта — лишь строкам с add/commit
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        r = subprocess.run(["git", "-C", d, "rev-parse", "--path-format=absolute",
                            "--git-dir", "--git-common-dir", "--show-toplevel",
                            "--abbrev-ref", "HEAD"],
                           capture_output=True, text=True, timeout=3, env=env)
    except (OSError, subprocess.TimeoutExpired):
        return None
    out = r.stdout.split("\n")
    if r.returncode != 0 or len(out) < 4:
        return None
    gitdir, common, top, branch = out[:4]
    if os.path.realpath(gitdir) != os.path.realpath(common) or branch not in TRUNKS:
        return None
    return top, branch


class Walker:
    """Обходит простые команды строки тем же разбором, что no-wait-guard."""

    def __init__(self, agent, cwd=None):
        self.agent = agent
        self.found = []
        # каталог по ходу строки: путь | None (не вычислим); как он выведен от каталога
        # вызова — inherited (шагов не было) | abs (был абсолютный якорь) | rel (первый
        # шаг — относительный) | unknown (шаг из невычислимой переменной)
        self.cwd = cwd if cwd and os.path.isabs(cwd) else None
        self.how = "inherited"
        self.rel = ""
        self.vars = {}

    def value(self, w):
        """Слово пути с подставленными переменными строки: (путь | None, был ли `$`)."""
        w = w.replace(hg.DQ, "$")
        if hg.SQ in w or "__SUBST__" in w:  # `$(…)`: каталог из исполнения не вычислим
            return None, True
        if "$" not in w:
            return w, False

        def sub(m):
            name = m.group(1) or m.group(2)
            v = self.vars[name] if name in self.vars else os.environ.get(name)
            if v is None:
                raise KeyError(name)
            return v
        try:
            out = VAR.sub(sub, w)
        except KeyError:
            return None, True
        return (None, True) if "$" in out else (out, True)

    def step(self, base, how, rel, word):
        """Шаг каталога `word` от (base, how): новые (каталог, how, первый rel)."""
        if word in ("", "~") or word.startswith("~/"):
            home = os.environ.get("HOME", "")
            return os.path.normpath(home + word[1:]) if home else None, "abs", rel
        # Подставленная переменная (строки или окружения) судится как литерал её
        # значения: относительный X в `cd $X/y` — тот же относительный шаг (ws#1242 п.0).
        path, _ = self.value(word)
        if path is None:
            return None, "unknown", rel
        if os.path.isabs(path):
            return os.path.normpath(path), "abs", rel
        joined = os.path.normpath(os.path.join(base, path)) if base else None
        if how in ("inherited", "rel"):
            return joined, "rel", rel or word
        return joined, how, rel

    def assign(self, ws):
        """`K=/abs …` отдельной командой — переменная строки (`export K=…` — тоже)."""
        if ws[:1] == ["export"]:
            ws = ws[1:]
        if not ws or not all(hg.ASSIGN.match(w) for w in ws):
            return False
        for w in ws:
            name, val = w.split("=", 1)
            path, _ = self.value(val)
            self.vars[name] = path
        return True

    def git_commit(self, args, shown):
        """`git [-C d]… add|commit …`: где ляжет коммит и выведено ли это от якоря."""
        d, how, rel = self.cwd, self.how, self.rel
        i, sub, other = 0, None, False
        while i < len(args):
            a = args[i]
            if a == "-C" and i + 1 < len(args):
                d, how, rel = self.step(d, how, rel, args[i + 1])
                i += 2
                continue
            if a.startswith(("--git-dir", "--work-tree")):
                other = True
                i += 1 if "=" in a else 2
                continue
            if a in GIT_VALUED:
                i += 2
                continue
            if a.startswith("-"):
                i += 1
                continue
            sub = a
            break
        if sub not in COMMIT_SUBS or other:
            return None
        if how == "rel":
            return Finding("commit-unanchored", shown,
                           "первый шаг каталога — относительный «%s»: разрешён от каталога "
                           "вызова %s → %s, а не от копии" % (rel, self.cwd or "?", d or "?"))
        if how == "unknown" or not d:
            return None
        trunk = trunk_clone(d)
        if trunk:
            return Finding("commit-trunk", shown,
                           "цель — основной клон %s на ветке %s" % trunk)
        return None

    def text(self, text):
        text = text.replace(hg.SQ, "$").replace(hg.DQ, "$")
        body, bodies = hg.strip_heredocs(text)
        for n in nwg.Parser(nwg.tokens(body)).parse_list(set()):
            self.node(n)
        for line, hbody in bodies:  # heredoc, поданный оболочке, — команды
            for seg in line.split("|"):
                argv, _, _ = nwg.head(hg.words(seg))
                if argv and os.path.basename(argv[0]) in nwg.SHELLS:
                    self.text(hbody)
                    break

    def node(self, n):
        for s in n.substs:
            self.text(s)
        if n.kind == "group":
            for k in n.kids:
                self.node(k)
            return
        self.simple(n.text)

    def simple(self, seg):
        ws = hg.words(seg)
        if self.assign(ws):
            return
        argv, _, _ = nwg.head(ws)
        if not argv:
            return
        base = os.path.basename(argv[0])
        args = argv[1:]
        if base in ("cd", "pushd"):
            word = next((a for a in args if not a.startswith("-") or a == "-"), "")
            if word == "-":
                self.cwd, self.how = None, "unknown"
            else:
                self.cwd, self.how, self.rel = self.step(self.cwd, self.how, self.rel, word)
            return
        if base == "popd":
            self.cwd, self.how = None, "unknown"
            return
        if base == "git":
            f = self.git_commit(args, seg.strip())
            if f:
                self.found.append(f)
            return
        if base == "timeout":  # head вернул timeout ≥ 600 вместе с командой
            self.simple(" ".join(nwg.shlex.quote(w) for w in argv[2:]))
            return
        if base in nwg.SHELLS:
            cmd, _, _, _ = hg.shell_args(args)
            if cmd is not None:
                self.text(cmd)
            return
        if base == "flock":
            k = 0
            while k < len(args) and args[k].startswith("-"):
                k += 2 if args[k] in ("-w", "--wait", "--timeout", "-E", "--conflict-exit-code") else 1
            rest = args[k + 1:]
            if rest[:1] in (["-c"], ["--command"]) and len(rest) > 1:
                self.text(rest[1])
            elif rest:
                self.simple(" ".join(nwg.shlex.quote(x) for x in rest))
            return
        if base != "gh":
            return
        sub = [a for a in args if not a.startswith("-")]
        shown = seg.strip()
        f = None
        if sub[:1] == ["api"]:
            f = judge_api(args[args.index("api") + 1:], self.agent, shown)
        elif sub[:2] == ["pr", "merge"]:
            f = judge_pr_merge(args[args.index("merge") + 1:], self.agent, shown)
        if f:
            self.found.append(f)


def judge(cmd, agent_type=None, cwd=None):
    w = Walker(agent_type or None, cwd)
    w.text(cmd)
    return w.found


def deny_commit(f, more):
    lines = [
        "GH-API-GUARD: отказ — коммит ляжет не в ту копию (ws#1237).",
        "  форма: %s — %s" % (CLASS_TEXT[f.cls], hg.clip(f.text, 200)),
        "  почему: %s" % f.why,
        "Норма: `git -C <абсолютный путь своей копии> add|commit …`. Каталог вызова Bash у",
        "сабагента сбрасывается, относительный `cd`/`-C` разрешается от него: так коммит",
        "kaname#878 лёг в main воркспейса. Ствол основного клона (main/master) коммитом не",
        "пишется — работа в ветке `<N>-<суффикс>` своей копии под tmp/.",
    ]
    if more:
        lines.append("  ещё форм в строке: %d" % more)
    sys.stderr.write("\n".join(lines) + "\n")
    sys.exit(2)


def deny(found):
    f = found[0]
    if f.cls.startswith("commit-"):
        deny_commit(f, len(found) - 1)
    lines = [
        "GH-API-GUARD: отказ — вызов меняет состояние хостинга мимо посадки.",
        "  форма: %s — %s" % (CLASS_TEXT[f.cls], hg.clip(f.text, 200)),
        "  почему: %s" % f.why,
        "Норма (ws#1008): `gh api` у агентов — только GET. `gh api repos/<r>/merges -X POST`",
        "не «узнаёт merge-base», а ВЛИВАЕТ head в base: так мимо посадки ушли kacho#3142,",
        "kacho#3144, kaname#703.",
        "Правильное чтение:",
        "  · merge-base: gh api repos/<o>/<r>/compare/<base>...<head> --jq .merge_base_commit.sha",
        "    либо git merge-base <base> <head> в своей копии;",
        "  · влита ли голова: git merge-base --is-ancestor <head> origin/<base>;",
        "  · поиск с параметрами: gh api --method GET search/issues -f q='…';",
        "  · комментарий, метка, задача — gh issue/pr comment|edit (их ведёт git-operator).",
        "Вливание — только git-operator: gh pr merge <N> --merge --match-head-commit <sha>;",
        "repos/*/merges, pulls/*/merge, --auto, --admin запрещены всем.",
    ]
    if len(found) > 1:
        lines.append("  ещё форм в строке: %d" % (len(found) - 1))
    sys.stderr.write("\n".join(lines) + "\n")
    sys.exit(2)


def broken(why):
    msg = ("GH-API-GUARD СЛОМАН: %s. Изменяющие вызовы gh api и коммиты этим вызовом НЕ проверялись — "
           "это не «чисто»; норма действует: gh api — только GET, вливание — только "
           "gh pr merge --match-head-commit у git-operator; починка — tooling-maintainer." % why)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}, ensure_ascii=False))
    sys.exit(0)


def main():
    if sys.argv[1:2] == ["--judge"] and len(sys.argv) >= 3:
        found = judge(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None,
                      sys.argv[4] if len(sys.argv) > 4 else os.getcwd())
        print(",".join(f.cls for f in found) or "-")
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
    found = judge(cmd, data.get("agent_type"), data.get("cwd"))
    if found:
        deny(found)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — страж обязан сказать о своей поломке
        broken("%s: %s" % (type(exc).__name__, exc))
