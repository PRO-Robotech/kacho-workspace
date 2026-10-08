#!/usr/bin/env python3
"""skill_evals — состязательные evals скилов: схема `evals.json`, прогон «с навыком» и
«без навыка», машинный отчёт и таблица (ws#973).

ЗАЧЕМ. Скил утверждает, что меняет ответ модели. Утверждение без замера — пожелание:
скил, который модель и так «знает», стоит окна и ничего не даёт, а скил, чей текст
расходится с тем, что модель делает по умолчанию, ценен ровно в этом расхождении.
Замер — один и тот же вопрос, заданный модели в чистом каталоге дважды: без текста
скила и с ним, по нескольку повторов на каждый.

ЛОВУШКА (`trap`). Кейс, на котором модель без навыка ошибается ПРАВДОПОДОБНО: выбирает
общепринятый ответ, а норма воркспейса другая. Кейс без ловушки меряет знание, которое
и так есть, и делает долю «без навыка» неотличимой от доли «с навыком»; поэтому в
каждом файле ловушек не меньше `MIN_TRAPS`, и это судит гейт
(`scripts/skills-gate/check-08-skill-evals-schema.sh`). Идея и форма — пересказ
состязательных evals из открытого набора скилов для Go (samber/cc-skills-golang):
текст оттуда не переносится.

ФОРМА `.claude/skills/<скил>/evals/evals.json`:

    {"schema_version": 1, "skill": "<имя каталога скила>",
     "cases": [{"id": "<kebab>", "prompt": "<вопрос>",
                "trap": null | "<на чём ошибается модель без навыка>",
                "assertions": [{"id": "<kebab>", "kind": "must" | "must_not",
                                "pattern": "<регулярное выражение Python>",
                                "desc": "<что утверждение проверяет>"}]}]}

Утверждения МЕХАНИЧЕСКИЕ — регулярное выражение по тексту ответа (без учёта
регистра, многострочно), а не оценка второй моделью: оценщик-модель добавил бы свой
разброс к измеряемому, и таблицу нельзя было бы пересчитать из сохранённых ответов
(`regrade`). Цена названа: формулировку, которой выражение не ждёт, утверждение не
засчитает — поэтому вопросы требуют ответа первой строкой в закрытой форме.

ЧТО СУДИТ СХЕМА (`validate`): разбор JSON; ровно известные ключи на каждом уровне;
`skill` равен имени каталога; кейсов не меньше `MIN_CASES`, ловушек не меньше
`MIN_TRAPS`; идентификаторы — kebab и уникальны; у каждого кейса есть хотя бы одно
`must` — положительный контроль (кейс из одних `must_not` проходит на пустом ответе);
выражение компилируется и НЕ совпадает с пустой строкой (`.*` в `must` засчитывается
любому ответу, а `must_not`, совпадающий с пустотой, не проходит никогда); в каталоге
`evals/` нет ничего, кроме `evals.json` — прогонщик чужого файла не читает.

ПРОГОН (`run`). Каждый вызов — `claude -p` в СВЕЖЕМ пустом каталоге вне дерева
(создаётся и снимается на каждый вызов), `--safe-mode` (без CLAUDE.md, скилов,
плагинов, хуков, MCP), `--setting-sources local` (без личного слоя настроек: язык ответа
и прочее личное в замер не входят), `--tools ""` (модель отвечает, а не читает диск),
`--no-session-persistence`, модель — явным `--model`. Режим «с навыком» отличается
ОДНИМ фактом: текст `SKILL.md` (без шапки frontmatter) подан файлом через
`--append-system-prompt-file`. Срабатывание скила по описанию этим НЕ меряется — меряется
содержание; это предпосылка замера, и она названа здесь, а не подразумевается.
Переменные сессии вызывающего Claude Code снимаются (`SESSION_ENV`): дочерний процесс
иначе считал бы себя частью этой сессии.

ТРИ ИСХОДА ВЫЗОВА: ответ получен (судится утверждениями) · «не выполнилось» (код
процесса, разбор JSON, `is_error`, пустой ответ, предел времени) — в знаменатель доли
НЕ входит и считается отдельно; доля без числа исполненных не печатается.

ЗАПИСЬ. Каталог отчёта: `report.json` (модель запрошенная и отданная — из `modelUsage`,
версия `claude`, ревизия воркспейса, blob `SKILL.md` и `evals.json`, грязность каталога
скила, по каждому вызову — исход, утверждения, длительность, цена) и `raw/` — ответ
каждого вызова целиком. `regrade <каталог>` пересчитывает таблицу из `raw/` без
единого вызова модели; `report <каталог>` печатает таблицу из `report.json`.

КОДЫ: 0 — отчёт снят, все вызовы исполнены; 1 — находка (схема, аргументы, нет скила);
2 — отчёт снят, но часть вызовов не выполнилась, либо осматривать нечего.

Вызов: `python3 -I scripts/skill-evals/skill_evals.py run --skill code-authoring --reps 3`;
схема — `python3 -I scripts/skill-evals/skill_evals.py validate --root .`.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

SCHEMA_VERSION = 1
MIN_CASES = 5
MIN_TRAPS = 2
MIN_REPS = 3
MODES = ("without", "with")
KINDS = ("must", "must_not")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
TOP_KEYS = {"schema_version", "skill", "cases"}
CASE_KEYS = {"id", "prompt", "trap", "assertions"}
ASSERT_KEYS = {"id", "kind", "pattern", "desc"}
FLAGS = re.IGNORECASE | re.MULTILINE
EVALS_NAME = "evals.json"

# Переменные, которыми процесс Claude Code помечает своих детей. Дочерний `claude -p`,
# унаследовав их, считал бы себя частью сессии вызывающего. Перечень закрыт и назван:
# переменные авторизации сюда не входят.
SESSION_ENV = (
    "CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT", "CLAUDE_PROJECT_DIR",
    "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
    "CLAUDE_CODE_BRIDGE_SESSION_ID", "CLAUDE_CODE_SESSION_ATTENDED",
)
# Изоляция вызова. `--safe-mode` снимает CLAUDE.md, скилы, плагины, хуки и MCP, но НЕ
# личный слой настроек: в первом прогоне (2026-10-08) `language` из
# `~/.claude/settings.json` отвечал по-русски на английские вопросы, и англоязычные
# утверждения молча не засчитывались. `--setting-sources local` в пустом каталоге
# вызова не читает ни одного слоя.
ISOLATION = ("--safe-mode", "--setting-sources", "local", "--tools", "",
             "--no-session-persistence")
GIT_ENV = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
           "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_PREFIX")


# ── схема ────────────────────────────────────────────────────────────────────

def validate_doc(doc, skill_name, where):
    """Находки схемы одного evals.json: список строк «<координата>: <причина>»."""
    f = []
    if not isinstance(doc, dict):
        return [f"{where}: верхний уровень не объект"]
    extra = set(doc) - TOP_KEYS
    missing = TOP_KEYS - set(doc)
    if extra:
        f.append(f"{where}: неизвестные ключи {sorted(extra)}")
    if missing:
        f.append(f"{where}: нет ключей {sorted(missing)}")
    if doc.get("schema_version") != SCHEMA_VERSION:
        f.append(f"{where}: schema_version {doc.get('schema_version')!r}, ждали {SCHEMA_VERSION}")
    if doc.get("skill") != skill_name:
        f.append(f"{where}: skill {doc.get('skill')!r} не равен имени каталога {skill_name!r}")
    cases = doc.get("cases")
    if not isinstance(cases, list):
        f.append(f"{where}: cases не список")
        return f
    if len(cases) < MIN_CASES:
        f.append(f"{where}: кейсов {len(cases)}, нужно не меньше {MIN_CASES}")
    seen = set()
    traps = 0
    for i, c in enumerate(cases):
        cw = f"{where}: cases[{i}]"
        if not isinstance(c, dict):
            f.append(f"{cw}: не объект")
            continue
        cid = c.get("id")
        cw = f"{where}: {cid!r}" if isinstance(cid, str) else cw
        if set(c) - CASE_KEYS:
            f.append(f"{cw}: неизвестные ключи {sorted(set(c) - CASE_KEYS)}")
        if CASE_KEYS - set(c):
            f.append(f"{cw}: нет ключей {sorted(CASE_KEYS - set(c))}")
        if not isinstance(cid, str) or not ID_RE.match(cid):
            f.append(f"{cw}: id не kebab-case")
        elif cid in seen:
            f.append(f"{cw}: id повторяется")
        else:
            seen.add(cid)
        p = c.get("prompt")
        if not isinstance(p, str) or not p.strip():
            f.append(f"{cw}: prompt пуст")
        t = c.get("trap")
        if t is not None:
            if not isinstance(t, str) or not t.strip():
                f.append(f"{cw}: trap ни null, ни непустая строка")
            else:
                traps += 1
        al = c.get("assertions")
        if not isinstance(al, list) or not al:
            f.append(f"{cw}: assertions пуст")
            continue
        aseen = set()
        musts = 0
        for j, a in enumerate(al):
            aw = f"{cw}: assertions[{j}]"
            if not isinstance(a, dict):
                f.append(f"{aw}: не объект")
                continue
            aid = a.get("id")
            if isinstance(aid, str):
                aw = f"{cw}/{aid}"
            if set(a) - ASSERT_KEYS:
                f.append(f"{aw}: неизвестные ключи {sorted(set(a) - ASSERT_KEYS)}")
            if ASSERT_KEYS - set(a):
                f.append(f"{aw}: нет ключей {sorted(ASSERT_KEYS - set(a))}")
            if not isinstance(aid, str) or not ID_RE.match(aid):
                f.append(f"{aw}: id не kebab-case")
            elif aid in aseen:
                f.append(f"{aw}: id повторяется в кейсе")
            else:
                aseen.add(aid)
            kind = a.get("kind")
            if kind not in KINDS:
                f.append(f"{aw}: kind {kind!r} вне {list(KINDS)}")
            elif kind == "must":
                musts += 1
            d = a.get("desc")
            if not isinstance(d, str) or not d.strip():
                f.append(f"{aw}: desc пуст")
            pat = a.get("pattern")
            if not isinstance(pat, str) or not pat:
                f.append(f"{aw}: pattern пуст")
                continue
            try:
                rx = re.compile(pat, FLAGS)
            except re.error as e:
                f.append(f"{aw}: pattern не компилируется: {e}")
                continue
            if rx.search(""):
                f.append(f"{aw}: pattern совпадает с пустой строкой — утверждение ничего не различает")
        if musts == 0:
            f.append(f"{cw}: нет ни одного must — кейс проходит на пустом ответе")
    if traps < MIN_TRAPS:
        f.append(f"{where}: ловушек {traps}, нужно не меньше {MIN_TRAPS}")
    return f


def git_files(root, *specs):
    env = {k: v for k, v in os.environ.items() if k not in GIT_ENV}
    r = subprocess.run(["git", "-C", root, "-c", "core.quotepath=false", "ls-files",
                        "--cached", "--others", "--exclude-standard", "--", *specs],
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"git ls-files не ответил: {r.stderr.strip()}")
    return sorted({ln for ln in r.stdout.splitlines() if ln})


def cmd_validate(args):
    root = os.path.abspath(args.root)
    try:
        files = git_files(root, ".claude/skills/*/evals/*", ".claude/skills/*/evals/**")
    except RuntimeError as e:
        print(f"[VOID] skill-evals schema — {e}", file=sys.stderr)
        return 2
    present = [p for p in files if os.path.lexists(os.path.join(root, p))]
    findings = []
    evals = []
    for p in present:
        parts = p.split("/")
        if len(parts) != 5 or parts[4] != EVALS_NAME:
            findings.append(f"{p}: посторонний файл в evals/ — прогонщик читает только {EVALS_NAME}")
            continue
        evals.append(p)
    ncases = 0
    for p in evals:
        skill = p.split("/")[2]
        if not os.path.isfile(os.path.join(root, ".claude/skills", skill, "SKILL.md")):
            findings.append(f"{p}: рядом нет SKILL.md — нечего мерить")
        try:
            with open(os.path.join(root, p), encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError) as e:
            findings.append(f"{p}: не разбирается как JSON: {e}")
            continue
        if isinstance(doc, dict) and isinstance(doc.get("cases"), list):
            ncases += len(doc["cases"])
        findings.extend(validate_doc(doc, skill, p))
    print(f"перепись: файлов в evals/ {len(present)}, из них evals.json {len(evals)}, кейсов {ncases}")
    if findings:
        for x in findings:
            print(f"  {x}", file=sys.stderr)
        print(f"[FAIL] skill-evals schema — находок {len(findings)}", file=sys.stderr)
        return 1
    if not evals:
        print("[VOID] skill-evals schema — ни одного .claude/skills/*/evals/evals.json: судить нечего",
              file=sys.stderr)
        return 2
    print(f"[PASS] skill-evals schema — evals.json {len(evals)}, кейсов {ncases}, находок 0")
    return 0


# ── прогон ───────────────────────────────────────────────────────────────────

def skill_body(path):
    """Текст SKILL.md без frontmatter: подаётся модели как приложение к системному промпту."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            text = text[end + 5:]
    return text.lstrip("\n")


def git_out(root, *a):
    env = {k: v for k, v in os.environ.items() if k not in GIT_ENV}
    r = subprocess.run(["git", "-C", root, *a], capture_output=True, text=True, env=env)
    return r.stdout.strip() if r.returncode == 0 else None


def blob(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def child_env():
    return {k: v for k, v in os.environ.items() if k not in SESSION_ENV and k not in GIT_ENV}


def call_model(claude, model, prompt, sysfile, scratch, timeout):
    """Один вызов в свежем пустом каталоге. Возвращает словарь исхода; каталог снимается."""
    work = tempfile.mkdtemp(prefix="skill-eval-", dir=scratch)
    argv = [*claude, "-p", *ISOLATION, "--output-format", "json", "--model", model]
    if sysfile:
        argv += ["--append-system-prompt-file", sysfile]
    argv.append(prompt)
    t0 = time.monotonic()
    out = {"rc": None, "void": None, "text": "", "models": [], "cost_usd": None}
    try:
        r = subprocess.run(argv, cwd=work, capture_output=True, text=True,
                           env=child_env(), timeout=timeout, stdin=subprocess.DEVNULL)
        out["rc"] = r.returncode
        try:
            d = json.loads(r.stdout)
        except ValueError:
            d = None
        if r.returncode != 0:
            out["void"] = f"код процесса {r.returncode}: {(r.stderr or r.stdout).strip()[:300]}"
        elif not isinstance(d, dict):
            out["void"] = "ответ не JSON"
        else:
            out["text"] = d.get("result") or ""
            out["models"] = sorted((d.get("modelUsage") or {}).keys())
            out["cost_usd"] = d.get("total_cost_usd")
            if d.get("is_error"):
                out["void"] = f"is_error: {d.get('subtype')} {d.get('api_error_status')}"
            elif not out["text"].strip():
                out["void"] = "пустой ответ"
    except subprocess.TimeoutExpired:
        out["void"] = f"предел времени {timeout} с"
    except OSError as e:
        out["void"] = f"не запустился: {e}"
    finally:
        shutil.rmtree(work, ignore_errors=True)
    out["seconds"] = round(time.monotonic() - t0, 2)
    return out


def grade(case, text):
    res = []
    for a in case["assertions"]:
        hit = re.search(a["pattern"], text, FLAGS) is not None
        ok = hit if a["kind"] == "must" else not hit
        res.append({"id": a["id"], "kind": a["kind"], "passed": ok})
    return res


def load_evals(root, skill):
    p = os.path.join(root, ".claude/skills", skill, "evals", EVALS_NAME)
    with open(p, encoding="utf-8") as fh:
        doc = json.load(fh)
    found = validate_doc(doc, skill, os.path.relpath(p, root))
    return p, doc, found


def summarize(report):
    """Сводка по скилу × режиму из записей вызовов: исполнено, доли утверждений."""
    rows = []
    for skill in report["skills"]:
        name = skill["skill"]
        traps = {c["id"] for c in skill["cases"] if c["trap"]}
        for mode in MODES:
            runs = [r for r in report["runs"] if r["skill"] == name and r["mode"] == mode]
            done = [r for r in runs if not r["void"]]
            ap = sum(sum(a["passed"] for a in r["assertions"]) for r in done)
            at = sum(len(r["assertions"]) for r in done)
            tp = sum(sum(a["passed"] for a in r["assertions"]) for r in done if r["case"] in traps)
            tt = sum(len(r["assertions"]) for r in done if r["case"] in traps)
            per_rep = {}
            for r in done:
                k = per_rep.setdefault(r["rep"], [0, 0])
                k[0] += sum(a["passed"] for a in r["assertions"])
                k[1] += len(r["assertions"])
            rows.append({
                "skill": name, "mode": mode, "planned": len(runs), "executed": len(done),
                "void": len(runs) - len(done), "passed": ap, "total": at,
                "share": round(ap / at, 3) if at else None,
                "trap_passed": tp, "trap_total": tt,
                "trap_share": round(tp / tt, 3) if tt else None,
                "per_rep": {str(k): round(v[0] / v[1], 3) if v[1] else None
                            for k, v in sorted(per_rep.items())},
            })
    return rows


def fmt_share(x):
    return "—" if x is None else f"{x:.2f}"


def table(report):
    rows = summarize(report)
    lines = [
        f"модель: запрошена {report['meta']['model_requested']}, отдана "
        f"{', '.join(report['meta']['models_reported']) or '—'}; повторов {report['meta']['reps']}; "
        f"claude {report['meta']['claude_version']}; воркспейс {report['meta']['workspace_rev']}",
        "",
        "| скил | режим | вызовов исполнено/план | не выполнилось | утверждений прошло/всего | доля | доля на ловушках | доля по повторам |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for r in rows:
        reps = " · ".join(f"r{k}={fmt_share(v)}" for k, v in r["per_rep"].items()) or "—"
        lines.append(
            f"| {r['skill']} | {r['mode']} | {r['executed']}/{r['planned']} | {r['void']} | "
            f"{r['passed']}/{r['total']} | {fmt_share(r['share'])} | "
            f"{r['trap_passed']}/{r['trap_total']} = {fmt_share(r['trap_share'])} | {reps} |")
    lines += ["", "по кейсам (доля утверждений, without → with):", ""]
    for skill in report["skills"]:
        for c in skill["cases"]:
            cells = []
            for mode in MODES:
                done = [r for r in report["runs"] if r["skill"] == skill["skill"]
                        and r["mode"] == mode and r["case"] == c["id"] and not r["void"]]
                p = sum(sum(a["passed"] for a in r["assertions"]) for r in done)
                t = sum(len(r["assertions"]) for r in done)
                cells.append(f"{p}/{t}")
            mark = " [ловушка]" if c["trap"] else ""
            lines.append(f"- {skill['skill']} / {c['id']}{mark}: {cells[0]} → {cells[1]}")
    return "\n".join(lines)


def write_report(outdir, report):
    with open(os.path.join(outdir, "report.json"), "w", encoding="utf-8") as fh:
        json.dump({**report, "summary": summarize(report)}, fh, ensure_ascii=False, indent=2)
    t = table(report)
    with open(os.path.join(outdir, "report.md"), "w", encoding="utf-8") as fh:
        fh.write(t + "\n")
    return t


def cmd_run(args):
    root = os.path.abspath(args.root)
    if args.reps < MIN_REPS:
        print(f"[FAIL] повторов {args.reps}: меньше {MIN_REPS} — разброс одного прогона не отличим от эффекта",
              file=sys.stderr)
        return 1
    skills = args.skill or sorted({p.split("/")[2] for p in
                                   git_files(root, ".claude/skills/*/evals/" + EVALS_NAME)})
    if not skills:
        print("[VOID] ни одного evals.json — мерить нечего", file=sys.stderr)
        return 2
    claude = (os.environ.get("SKILL_EVALS_CLAUDE") or "claude").split()
    ver = subprocess.run([*claude, "--version"], capture_output=True, text=True,
                         env=child_env(), stdin=subprocess.DEVNULL)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    outdir = os.path.abspath(args.out or os.path.join(root, "tmp", "skill-evals", stamp))
    os.makedirs(os.path.join(outdir, "raw"), exist_ok=True)
    scratch = tempfile.mkdtemp(prefix="skill-evals-scratch-", dir=args.scratch)
    report = {"meta": {
        "started_utc": stamp, "model_requested": args.model, "models_reported": [],
        "reps": args.reps, "claude_cmd": claude,
        "claude_version": (ver.stdout or ver.stderr).strip() or None,
        "workspace_rev": git_out(root, "rev-parse", "HEAD"),
        "flags": ["-p", *ISOLATION, "--output-format", "json"],
    }, "skills": [], "runs": []}
    jobs = []
    try:
        for skill in skills:
            sk = os.path.join(root, ".claude/skills", skill, "SKILL.md")
            if not os.path.isfile(sk):
                print(f"[FAIL] нет {sk}", file=sys.stderr)
                return 1
            ep, doc, found = load_evals(root, skill)
            if found:
                for x in found:
                    print(f"  {x}", file=sys.stderr)
                print(f"[FAIL] схема {ep} — прогон не начат", file=sys.stderr)
                return 1
            sysfile = os.path.join(scratch, f"{skill}.system.md")
            with open(sysfile, "w", encoding="utf-8") as fh:
                fh.write(f"Ниже — навык `{skill}`. Применяй его, отвечая на вопрос.\n\n")
                fh.write(skill_body(sk))
            dirty = git_out(root, "status", "--porcelain", "--", f".claude/skills/{skill}")
            report["skills"].append({
                "skill": skill, "skill_md_blob": blob(sk), "evals_blob": blob(ep),
                "skill_dir_last_commit": git_out(root, "log", "-1", "--format=%H", "--",
                                                 f".claude/skills/{skill}"),
                "skill_dir_dirty": bool(dirty),
                "cases": [{"id": c["id"], "trap": c["trap"]} for c in doc["cases"]],
            })
            for c in doc["cases"]:
                for mode in MODES:
                    for rep in range(1, args.reps + 1):
                        jobs.append((skill, c, mode, rep, sysfile if mode == "with" else None))
        print(f"план: скилов {len(skills)}, вызовов {len(jobs)} (кейс × режим × повтор), "
              f"параллельно {args.jobs}; отчёт → {outdir}", file=sys.stderr)

        def one(j):
            skill, c, mode, rep, sysfile = j
            o = call_model(claude, args.model, c["prompt"], sysfile, scratch, args.timeout)
            rawp = os.path.join(outdir, "raw", skill, mode)
            os.makedirs(rawp, exist_ok=True)
            with open(os.path.join(rawp, f"{c['id']}.r{rep}.txt"), "w", encoding="utf-8") as fh:
                fh.write(o["text"])
            return {"skill": skill, "case": c["id"], "mode": mode, "rep": rep,
                    "void": o["void"], "rc": o["rc"], "models": o["models"],
                    "seconds": o["seconds"], "cost_usd": o["cost_usd"],
                    "assertions": [] if o["void"] else grade(c, o["text"])}

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
            for n, rec in enumerate(ex.map(one, jobs), 1):
                report["runs"].append(rec)
                if n % 10 == 0 or n == len(jobs):
                    print(f"  исполнено вызовов {n}/{len(jobs)}", file=sys.stderr)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    report["meta"]["models_reported"] = sorted({m for r in report["runs"] for m in r["models"]})
    report["meta"]["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    print(write_report(outdir, report))
    voids = sum(1 for r in report["runs"] if r["void"])
    print(f"вызовов {len(report['runs'])}, не выполнилось {voids}; отчёт: {outdir}/report.json",
          file=sys.stderr)
    return 2 if voids else 0


def cmd_regrade(args):
    """Пересчёт утверждений по сохранённым ответам и ТЕКУЩЕМУ evals.json — без вызова модели."""
    outdir = os.path.abspath(args.dir)
    with open(os.path.join(outdir, "report.json"), encoding="utf-8") as fh:
        report = json.load(fh)
    root = os.path.abspath(args.root)
    cases = {}
    for s in report["skills"]:
        _, doc, found = load_evals(root, s["skill"])
        if found:
            print(f"[FAIL] схема {s['skill']}: {found[0]}", file=sys.stderr)
            return 1
        if blob(os.path.join(root, ".claude/skills", s["skill"], "evals", EVALS_NAME)) != s["evals_blob"]:
            print(f"предупреждение: evals.json {s['skill']} изменился после прогона — "
                  f"пересчёт по новым утверждениям", file=sys.stderr)
        cases.update({(s["skill"], c["id"]): c for c in doc["cases"]})
    for r in report["runs"]:
        if r["void"]:
            continue
        p = os.path.join(outdir, "raw", r["skill"], r["mode"], f"{r['case']}.r{r['rep']}.txt")
        with open(p, encoding="utf-8") as fh:
            r["assertions"] = grade(cases[(r["skill"], r["case"])], fh.read())
    print(write_report(outdir, report))
    return 2 if any(r["void"] for r in report["runs"]) else 0


def cmd_report(args):
    with open(os.path.join(os.path.abspath(args.dir), "report.json"), encoding="utf-8") as fh:
        print(table(json.load(fh)))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="skill_evals")
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("validate", help="схема всех .claude/skills/*/evals/evals.json")
    v.add_argument("--root", default=".")
    r = sub.add_parser("run", help="прогон with/without × повторы")
    r.add_argument("--root", default=".")
    r.add_argument("--skill", action="append", help="скил (повторяемый); по умолчанию все с evals")
    r.add_argument("--reps", type=int, default=MIN_REPS)
    r.add_argument("--model", default="sonnet")
    r.add_argument("--jobs", type=int, default=4)
    r.add_argument("--timeout", type=int, default=300)
    r.add_argument("--out", help="каталог отчёта; по умолчанию <root>/tmp/skill-evals/<UTC>")
    r.add_argument("--scratch", default=None, help="где заводить чистые каталоги вызовов")
    g = sub.add_parser("regrade", help="пересчёт по сохранённым ответам")
    g.add_argument("dir")
    g.add_argument("--root", default=".")
    t = sub.add_parser("report", help="таблица из report.json")
    t.add_argument("dir")
    a = ap.parse_args(argv)
    return {"validate": cmd_validate, "run": cmd_run, "regrade": cmd_regrade,
            "report": cmd_report}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
