#!/usr/bin/env python3
"""selftest — поведенческая проба прогонщика `skill_evals.py` без единого вызова модели (ws#973).

ЧТО ДОКАЗЫВАЕТ. Прогонщик зовётся на синтетическом дереве (свой git-репозиторий во
временном каталоге: скил `demo` с маркером в тексте и его evals.json) с подменённым
`claude` (`SKILL_EVALS_CLAUDE`). Подмена отвечает ВЕРНО, только если ей подан файл
системного промпта с маркером скила, и НЕВЕРНО иначе, — поэтому таблица обязана дать
долю 1.0 «с навыком» и 0.0 «без навыка». Расхождение значит, что режимы не различаются
одним фактом (текст скила не доехал либо доехал в оба режима).

Подмена проверяет и условия вызова, которые прогонщик обещает, и при нарушении
отвечает ошибкой (такой вызов становится «не выполнилось» и роняет пробу): каталог
вызова пуст и лежит вне синтетического дерева; заданы `--safe-mode`,
`--setting-sources local`, пустой `--tools`, `--no-session-persistence`, `--model`; переменной `CLAUDECODE` в окружении нет.
После прогона ни один каталог вызова не должен остаться на диске.

Третий исход: кейс, чей вопрос несёт `VOIDME`, получает от подмены `is_error` — прогон
обязан выйти кодом 2, посчитать эти вызовы «не выполнилось» и НЕ включить их в
знаменатель доли. Повторов меньше минимума — код 1. `regrade` по сохранённым ответам
обязан дать ту же таблицу.

Вызов: `python3 -I scripts/skill-evals/selftest.py [<путь к skill_evals.py>]`.
Коды: 0 — все пробы сошлись; 1 — расхождение; 2 — прогонщика по пути нет.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

FAKE = r'''
import json, os, sys
argv = sys.argv[1:]
log = os.environ["SELFTEST_LOG"]
root = os.environ["SELFTEST_ROOT"]
if argv == ["--version"]:
    print("0.0.0 (selftest)"); sys.exit(0)
cwd = os.getcwd()
problems = []
if os.listdir(cwd): problems.append("каталог вызова не пуст")
if os.path.realpath(cwd).startswith(os.path.realpath(root) + os.sep): problems.append("каталог вызова внутри дерева")
for flag in ("-p", "--safe-mode", "--no-session-persistence"):
    if flag not in argv: problems.append("нет " + flag)
if "--tools" not in argv or argv[argv.index("--tools") + 1] != "": problems.append("--tools не пуст")
if "--model" not in argv: problems.append("нет --model")
if "--setting-sources" not in argv or argv[argv.index("--setting-sources") + 1] != "local": problems.append("личный слой настроек не снят")
if "CLAUDECODE" in os.environ: problems.append("CLAUDECODE унаследован")
with open(log, "a") as fh: fh.write(cwd + "\n")
prompt = argv[-1]
skill = False
if "--append-system-prompt-file" in argv:
    with open(argv[argv.index("--append-system-prompt-file") + 1]) as fh:
        skill = "MARKER-DEMO-SKILL" in fh.read()
if problems:
    print(json.dumps({"type": "result", "is_error": True, "subtype": "; ".join(problems), "result": ""})); sys.exit(0)
if "VOIDME" in prompt:
    print(json.dumps({"type": "result", "is_error": True, "subtype": "error_during_execution", "result": ""})); sys.exit(0)
text = "ОТВЕТ: 1\nобоснование" if skill else "ОТВЕТ: 2\nобоснование"
print(json.dumps({"type": "result", "is_error": False, "result": text, "total_cost_usd": 0,
                  "modelUsage": {"selftest-model": {}}}))
'''


def case(cid, trap, prompt="вопрос"):
    return {"id": cid, "prompt": prompt, "trap": trap, "assertions": [
        {"id": "right", "kind": "must", "pattern": "ОТВЕТ\\W{0,6}1(?!\\d)", "desc": "верный вариант"},
        {"id": "not-wrong", "kind": "must_not", "pattern": "ОТВЕТ\\W{0,6}2(?!\\d)", "desc": "не ловушка"}]}


def main():
    runner = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "skill_evals.py")
    if not os.path.isfile(runner):
        print(f"[VOID] skill-evals selftest — прогонщика нет: {runner}", file=sys.stderr)
        return 2
    base = tempfile.mkdtemp(prefix="skill-evals-selftest-")
    fails = []
    probes = 0

    def check(cond, what):
        nonlocal probes
        probes += 1
        print(f"  [{'ok' if cond else 'БЕДА'}] {what}")
        if not cond:
            fails.append(what)

    try:
        root = os.path.join(base, "ws")
        sk = os.path.join(root, ".claude/skills/demo")
        os.makedirs(os.path.join(sk, "evals"))
        with open(os.path.join(sk, "SKILL.md"), "w") as fh:
            fh.write("---\nname: demo\ndescription: x\n---\n\nMARKER-DEMO-SKILL: отвечай 1.\n")
        doc = {"schema_version": 1, "skill": "demo", "cases": [
            case("c1", "ловушка один"), case("c2", "ловушка два"), case("c3", None),
            case("c4", None), case("c5", None), case("c6", None, prompt="VOIDME")]}
        with open(os.path.join(sk, "evals/evals.json"), "w") as fh:
            json.dump(doc, fh, ensure_ascii=False)
        subprocess.run(["git", "init", "-q", root], check=True)
        subprocess.run(["git", "-C", root, "add", "-A"], check=True)
        fake = os.path.join(base, "fake_claude.py")
        with open(fake, "w") as fh:
            fh.write(FAKE)
        calls = os.path.join(base, "calls.log")
        scratch = os.path.join(base, "scratch")
        os.makedirs(scratch)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith("GIT_")}
        env.update({"SKILL_EVALS_CLAUDE": f"{sys.executable} -I {fake}", "SELFTEST_LOG": calls,
                    "SELFTEST_ROOT": root, "CLAUDECODE": "1"})
        out = os.path.join(base, "out")

        def run(*a):
            return subprocess.run([sys.executable, "-I", runner, *a], env=env,
                                  capture_output=True, text=True)

        r = run("run", "--root", root, "--reps", "3", "--model", "m", "--jobs", "3",
                "--out", out, "--scratch", scratch)
        check(r.returncode == 2, f"кейс с is_error даёт код 2 (получен {r.returncode})")
        try:
            with open(os.path.join(out, "report.json")) as fh:
                rep = json.load(fh)
        except (OSError, ValueError):
            rep = None
            print(r.stdout + r.stderr)
        check(rep is not None, "report.json записан")
        if rep:
            s = {row["mode"]: row for row in rep["summary"]}
            check(s["with"]["share"] == 1.0, f"доля с навыком 1.0 (получено {s['with']['share']})")
            check(s["without"]["share"] == 0.0, f"доля без навыка 0.0 (получено {s['without']['share']})")
            check(s["with"]["void"] == 3 and s["without"]["void"] == 3,
                  "вызовы с is_error посчитаны «не выполнилось» по 3 на режим")
            check(s["with"]["total"] == 5 * 3 * 2, "в знаменатель вошли только исполненные вызовы")
            check(s["with"]["trap_total"] == 2 * 3 * 2, "ловушки посчитаны отдельно")
            check(rep["meta"]["models_reported"] == ["selftest-model"], "модель записана из modelUsage")
            check(bool(rep["skills"][0]["skill_md_blob"]) and bool(rep["skills"][0]["evals_blob"]),
                  "ревизии SKILL.md и evals.json записаны")
            check(len(rep["runs"]) == 6 * 2 * 3, "вызовов кейс × режим × повтор")
            g = run("regrade", out, "--root", root)
            with open(os.path.join(out, "report.json")) as fh:
                rep2 = json.load(fh)
            check(g.returncode == 2 and rep2["summary"] == rep["summary"],
                  "regrade по сохранённым ответам даёт ту же сводку")
        with open(calls) as fh:
            dirs = [ln.strip() for ln in fh if ln.strip()]
        check(len(dirs) == 36 and not any(os.path.exists(d) for d in dirs),
              f"каталоги вызовов сняты ({len(dirs)} вызовов)")
        check(os.listdir(scratch) == [], "в каталоге scratch ничего не осталось")
        r = run("run", "--root", root, "--reps", "2", "--out", os.path.join(base, "o2"),
                "--scratch", scratch)
        check(r.returncode == 1, "повторов меньше минимума — код 1")
    finally:
        shutil.rmtree(base, ignore_errors=True)
    print(f"проб {probes}, расхождений {len(fails)}")
    if fails:
        print("[FAIL] skill-evals selftest — " + "; ".join(fails), file=sys.stderr)
        return 1
    print(f"[PASS] skill-evals selftest — проб {probes}, расхождений 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
