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

РАЗРЕШЕНО: `gh api <путь>` без тела и метода (GET), `gh api --method GET … -f q=…`
(поля уходят строкой запроса), `gh api graphql -f query='query{…}'`, `compare`,
`git merge-base`; у git-operator — изменяющие вызовы, кроме путей вливания.

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
(другой класс: его держат хук отправки и защита ветки).
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
}


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


class Walker:
    """Обходит простые команды строки тем же разбором, что no-wait-guard."""

    def __init__(self, agent):
        self.agent = agent
        self.found = []

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
        argv, _, _ = nwg.head(hg.words(seg))
        if not argv:
            return
        base = os.path.basename(argv[0])
        args = argv[1:]
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


def judge(cmd, agent_type=None):
    w = Walker(agent_type or None)
    w.text(cmd)
    return w.found


def deny(found):
    f = found[0]
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
    msg = ("GH-API-GUARD СЛОМАН: %s. Изменяющие вызовы gh api этим вызовом НЕ проверялись — "
           "это не «чисто»; норма действует: gh api — только GET, вливание — только "
           "gh pr merge --match-head-commit у git-operator; починка — tooling-maintainer." % why)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}, ensure_ascii=False))
    sys.exit(0)


def main():
    if sys.argv[1:2] == ["--judge"] and len(sys.argv) >= 3:
        found = judge(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
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
    found = judge(cmd, data.get("agent_type"))
    if found:
        deny(found)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — страж обязан сказать о своей поломке
        broken("%s: %s" % (type(exc).__name__, exc))
