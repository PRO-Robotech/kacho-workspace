#!/usr/bin/env bash
# check-15 — ИМЯ, КОТОРОЕ ТЕЛО ОСНАСТКИ ЗОВЁТ, РЕЗОЛВИТСЯ.
#
# Предмет. Тело агента, правило, канонический скил, `CLAUDE.md` и живой хук называют
# три рода целей, и каждый род отказывает МОЛЧА:
#   1. вызов `Skill <имя>` — имени без каталога `.claude/skills/<имя>/SKILL.md` среда
#      не даёт ничего: агент продолжает работу без нормы, которую его тело обязало
#      применить, и в отчёте это неотличимо от «условие не сработало» (ws#742);
#   2. строка `skills:` во frontmatter агента — то же, но при старте;
#   3. путь `.claude/<…>` — перенос файла рвёт адрес, а читающий идёт по нему
#      (ws#710: 12 координат снятых правил, два живых хука печатали их диспетчеру).
# Замер при заведении, 2026-09-27 @5bb3ef77: имён `Skill rule-*` 28, без каталога
# 11, вызовов без каталога 156 в 30 телах из 32; путей `.claude/rules/<снятое>.md`
# в тех же источниках 173.
#
# Почему не check-07. Он судит адрес «файл §раздел» по БАЗОВОМУ имени — в корпусе
# И в архиве, — поэтому `.claude/rules/<снятое>.md §…` для него резолвится о
# `.claude/backup/<снятое>.md`, а путь, по которому пойдёт читающий, ложен. Имя
# скила адресом его формы не является вовсе. Два предмета, два вопроса.
#
# Источники ВЫВОДЯТСЯ из дерева (`git ls-files` вместе с неотслеживаемыми, но не
# игнорируемыми — новый агент судится в тот же день, когда его пишут):
#   .claude/agents/*.md · .claude/rules/*.md · CLAUDE.md ·
#   .claude/skills/*/SKILL.md, КРОМЕ символьных ссылок `rule-*` (их текст — правило,
#   он уже в перечне) ·
#   файлы `.claude/hooks/` верхнего уровня и подкаталогов БЕЗ `prove.sh`.
# Подкаталог хука с `prove.sh` несёт синтетические входы проб (`.claude/rules/x.md`,
# `.claude/rulebook/`): это фикстуры инъекции, и мёртвыми им быть положено.
# Исключение выводится из дерева — признаком «здесь лежит проба», а не списком имён.
#
# Формы записи — ВСЕ законные, и каждая доказана инъекцией (inject-15):
#   вызов:   `Skill <имя>` одним code span; вне code span — только имя с дефисом
#            (иначе это проза: «Skill tool»). Имя с `<`, `*` — шаблон, не вызов.
#            Имя с `:` — скил плагина, живёт вне дерева: считается, не судится.
#   путь:    `.claude/…` от корня; `$ПЕРЕМЕННАЯ/.claude/…` — тоже от корня (так
#            пишут хуки). Перед ним `~/`, литеральный каталог или глоб — путь
#            ЧУЖОГО дерева (личные настройки, продукт, маска): считается, не
#            судится. За ним `<`, `*`, `{`, `[`, `$` — шаблон. Путь, который git
#            игнорирует (`.state/`, `settings.local.json`), — принадлежность машины:
#            считается, не судится. Путь в поддерево `.claude/<x>`, которое
#            объявляет провязка `settings.json` (команды хуков), а в копии его нет
#            ЦЕЛИКОМ, — неполнота копии, а не адреса: считается, не судится
#            (исчезновение каталога хуков в полном дереве ловит tooling-gate
#            check-21 — «запись без файла»). Не объявленное провязкой отсутствующее
#            поддерево судится как любой путь.
#
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 отказ (агентов нет — судить не
# о чем, и это не «находок 0»). Перепись печатается всегда, отдельной строкой.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 - <<'PY'
import os
import re
import subprocess
import sys

NAME = "check-15-named-loads-resolve"


def ls(*pats):
    out = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", *pats],
                         capture_output=True, text=True).stdout
    return sorted({p for p in out.split("\n") if p})


tree = set(ls())
dirs = set()
for p in tree:
    parts = p.split("/")
    for i in range(1, len(parts)):
        dirs.add("/".join(parts[:i]))

agents = [p for p in ls(".claude/agents") if re.fullmatch(r"\.claude/agents/[^/]+\.md", p)]
if not agents:
    print(f"[VOID] {NAME} — в .claude/agents/ нет ни одного агента: звать некому, "
          "и «находок 0» здесь значило бы «не читали»", file=sys.stderr)
    sys.exit(2)

proof_dirs = {os.path.dirname(p) for p in ls(".claude/hooks") if p.endswith("/prove.sh")}
sources = list(agents)
sources += [p for p in ls(".claude/rules") if re.fullmatch(r"\.claude/rules/[^/]+\.md", p)]
sources += [p for p in ["CLAUDE.md"] if p in tree]
skill_real = []
for p in ls(".claude/skills"):
    if re.fullmatch(r"\.claude/skills/[^/]+/SKILL\.md", p) and not os.path.islink(p):
        skill_real.append(p)
sources += skill_real
hook_src = [p for p in ls(".claude/hooks")
            if os.path.isfile(p) and not os.path.islink(p)
            and os.path.dirname(p) not in proof_dirs
            and p.rsplit(".", 1)[-1] in ("sh", "py", "md", "json")]
sources += hook_src


def skill_resolves(name):
    # Символьная ссылка обязана вести в существующий файл: висячая — тот же отказ.
    return os.path.exists(os.path.join(".claude/skills", name, "SKILL.md"))


def ignored(path):
    return subprocess.run(["git", "check-ignore", "-q", path]).returncode == 0


# Поддеревья `.claude/<x>`, которые объявляет провязка харнесса (команды хуков).
declared_tops = set()
try:
    import json as _json
    _st = _json.load(open(".claude/settings.json", encoding="utf-8"))
    for _groups in (_st.get("hooks") or {}).values():
        for _g in _groups or []:
            for _h in (_g or {}).get("hooks") or []:
                for _m in re.finditer(r"(\.claude/[A-Za-z0-9_.-]+)/", _h.get("command") or ""):
                    declared_tops.add(_m.group(1))
except (OSError, ValueError):
    pass

findings = []
cnt = dict(calls=0, calls_bad=0, plugin=0, templ_call=0, prose=0,
           fm=0, fm_bad=0, paths=0, paths_bad=0, templ_path=0, foreign=0, ign=0,
           no_subtree=0)
names = set()

CALL = re.compile(r"(?<![A-Za-z0-9_])Skill[ \t]+(`?)([A-Za-z0-9][A-Za-z0-9_:.-]*)")
PATH = re.compile(r"\.claude/[A-Za-z0-9_./-]*")

for src in sources:
    try:
        text = open(src, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    lines = text.split("\n")

    def lineno(off):
        return text.count("\n", 0, off) + 1

    # ── род 2: skills: во frontmatter агента ────────────────────────────────
    if src in agents and text.startswith("---"):
        end = text.find("\n---", 3)
        fm = text[:end if end > 0 else 0]
        inside = False
        for i, ln in enumerate(fm.split("\n"), 1):
            if re.match(r"^skills:\s*$", ln):
                inside = True
                continue
            if inside:
                m = re.match(r"^\s+-\s+([A-Za-z0-9][A-Za-z0-9_:-]*)\s*$", ln)
                if not m:
                    inside = False
                    continue
                cnt["fm"] += 1
                if ":" in m.group(1):
                    cnt["plugin"] += 1
                    continue
                if not skill_resolves(m.group(1)):
                    cnt["fm_bad"] += 1
                    findings.append(f"{src}:{i}: skills: «{m.group(1)}» — нет "
                                    f".claude/skills/{m.group(1)}/SKILL.md (предзагрузка "
                                    "не состоится, агент стартует без правила)")

    # ── род 1: вызов Skill <имя> ────────────────────────────────────────────
    for m in CALL.finditer(text):
        tick_open, raw = m.group(1), m.group(2)
        name = raw.rstrip(".,;")
        after = text[m.start(2) + len(name): m.start(2) + len(name) + 1]
        in_span = (text[m.start() - 1: m.start()] == "`" or tick_open == "`") and after == "`"
        if after in ("<", "*", "{") or name.endswith("-"):
            cnt["templ_call"] += 1
            continue
        if ":" in name:
            cnt["plugin"] += 1
            continue
        if not in_span and "-" not in name:
            cnt["prose"] += 1
            continue
        cnt["calls"] += 1
        names.add(name)
        if not skill_resolves(name):
            cnt["calls_bad"] += 1
            findings.append(f"{src}:{lineno(m.start())}: `Skill {name}` — нет "
                            f".claude/skills/{name}/SKILL.md; вызов не даст агенту ничего, "
                            "и отказ молчалив")

    # ── род 3: путь .claude/… ────────────────────────────────────────────────
    for m in PATH.finditer(text):
        tok = m.group(0).rstrip(".")
        post = text[m.end(): m.end() + 1]
        pre = text[max(0, m.start() - 40): m.start()]
        prev = pre[-1:]
        if post and post in "<*{[$":
            cnt["templ_path"] += 1
            continue
        if prev and re.match(r"[A-Za-z0-9_~.-]", prev):
            cnt["foreign"] += 1
            continue
        if prev == "/":
            seg = re.search(r"([^\s\"'`(=:]*)/$", pre)
            seg = seg.group(1) if seg else ""
            if "*" in seg:
                cnt["templ_path"] += 1
                continue
            if not re.fullmatch(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?", seg):
                cnt["foreign"] += 1
                continue
        path = tok.rstrip("/")
        if path in (".claude", ""):
            continue
        # Поддерево `.claude/<x>`, которое ОБЪЯВЛЯЕТ провязка `settings.json`, но
        # которого в копии нет ЦЕЛИКОМ, — неполнота копии (выписка без хуков), а не
        # мёртвый адрес: судить не о чем, и это считается отдельно, а не молчит.
        # Поддерево, которого провязка не объявляет (`.claude/rulebook/`), судится —
        # его отсутствие и есть находка.
        top = "/".join(path.split("/")[:2])
        if top in declared_tops and top not in dirs and top not in tree:
            cnt["no_subtree"] += 1
            continue
        cnt["paths"] += 1
        if path in tree or path in dirs:
            continue
        if ignored(path):
            cnt["ign"] += 1
            continue
        cnt["paths_bad"] += 1
        findings.append(f"{src}:{lineno(m.start())}: путь {path} — в дереве его нет; "
                        "читающий пойдёт по адресу, которого не существует")

print(f"[CENSUS] {NAME}: источников {len(sources)} (агентов {len(agents)}, "
      f"скилов-файлов {len(skill_real)}, файлов хуков {len(hook_src)}; "
      f"каталогов проб исключено {len(proof_dirs)}); "
      f"вызовов Skill {cnt['calls']} (имён {len(names)}), не резолвится {cnt['calls_bad']}; "
      f"строк skills: {cnt['fm']}, не резолвится {cnt['fm_bad']}; "
      f"путей .claude/ {cnt['paths']}, не резолвится {cnt['paths_bad']}; "
      f"не судилось: шаблонов вызова {cnt['templ_call']}, прозы «Skill» {cnt['prose']}, "
      f"имён плагина {cnt['plugin']}, шаблонов пути {cnt['templ_path']}, "
      f"путей чужого дерева {cnt['foreign']}, игнорируемых git {cnt['ign']}, "
      f"в поддерево, которого нет целиком, {cnt['no_subtree']}")
if findings:
    for f in findings:
        print(f"[FAIL] {NAME} — {f}", file=sys.stderr)
    print(f"[FAIL] {NAME} — находок {len(findings)}", file=sys.stderr)
    sys.exit(1)
if cnt["calls"] + cnt["fm"] + cnt["paths"] == 0:
    print(f"[VOID] {NAME} — источников {len(sources)}, но ни одного вызова, строки skills: "
          "или пути: судить нечего, и это не «всё резолвится»", file=sys.stderr)
    sys.exit(2)
print(f"[PASS] {NAME} — каждый вызов, строка skills: и путь резолвятся")
PY
