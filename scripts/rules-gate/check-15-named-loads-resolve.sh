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
# Замер при заведении — перепись самого гейта (редакция 1e7e887c) на выписке
# 5bb3ef77, то есть до перевода корпуса: «вызовов Skill 398 (имён 37), не
# резолвится 156; путей .claude/ 510, не резолвится 164». Предикат —
# `git archive 5bb3ef77 | tar -x -C <кат>; cd <кат>; git init -q; git add -A;
# bash <этот файл>`. Прежде здесь стояло «путей 173», выписанное руками: его не
# воспроизводит ни одна единица счёта (приёмка ws#742, круг 1).
#
# Почему не check-07. Он судит адрес «файл §раздел» по БАЗОВОМУ имени — в корпусе
# И в архиве, — поэтому `.claude/rules/<снятое>.md §…` для него резолвится о
# `.claude/backup/<снятое>.md`, а путь, по которому пойдёт читающий, ложен. Имя
# скила адресом его формы не является вовсе. Два предмета, два вопроса.
#
# Источники ВЫВОДЯТСЯ из дерева (`git ls-files` вместе с неотслеживаемыми, но не
# игнорируемыми — новый агент судится в тот же день, когда его пишут):
#   .claude/agents/*.md · .claude/rules/*.md · CLAUDE.md ·
#   каждый настоящий (не символьная ссылка) текстовый файл `.claude/skills/<скил>/`,
#     включая `references/` — его читает агент, которому скил загружен; ссылки
#     `rule-*/SKILL.md` не читаются (их текст — правило, оно уже в перечне) ·
#   каждый текстовый файл `.claude/hooks/**`, КРОМЕ самих проб `.claude/hooks/<хук>/prove.sh`.
# Проба несёт синтетические входы (`.claude/rules/x.md`, снятые каталоги): это
# фикстуры инъекции, и мёртвыми им быть положено. Исключается ФАЙЛ пробы по тому
# же признаку (место и имя), по которому пробы находит `scripts/hook-proofs.sh`, —
# а не каталог: рядом с пробой живёт код хука, печатающий диспетчеру (ws#710), и
# до 2026-09-28 он не судился вместе с каталогом. Число исключённых файлов и число
# файлов вне распознаваемых расширений печатаются в переписи.
#
# Цель резолвится, только если она в ИНДЕКСЕ git (`--cached`): файл, который есть
# на диске, но не отслеживается, в клоне конвейера отсутствует, и вердикт по нему
# не вправе зависеть от рабочего дерева — это отдельная находка «не отслеживается».
# Содержимое источника читается из рабочего дерева: правка до коммита судится до
# коммита (строже, а не мягче клона).
#
# Формы записи — ВСЕ законные, и каждая доказана инъекцией (inject-15):
#   вызов:   `Skill <имя>` одним code span; вне code span — только имя с дефисом
#            (иначе это проза: «Skill tool»). Имя с `<`, `*` — шаблон, не вызов.
#            Имя с `:` — скил плагина, живёт вне дерева: считается, не судится.
#   skills:  frontmatter агента РАЗБИРАЕТСЯ как YAML (`yaml.compose`): блочный
#            список с любым отступом, кавычки, хвостовой комментарий, поточный
#            `[a, b]`, строка через запятую. Frontmatter, который не разбирается,
#            и значение иной формы — находки: харнесс их не прочтёт так, как задумано.
#   путь:    `.claude/…` от корня; `./.claude/…` — тоже от корня; перед ним
#            переменная `$ИМЯ/`, `${ИМЯ}/`, `${ИМЯ:-…}/`, в том числе закрытая
#            кавычкой до косой черты (`"$ИМЯ"/`) — тоже от корня (так пишут хуки).
#            Перед ним `~/`, `../`, литеральный каталог или глоб — путь ЧУЖОГО
#            дерева (личные настройки, продукт, маска): считается, не судится.
#            За ним `<`, `*`, `{`, `[`, `$` — шаблон. Путь, который git
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


def ls(*pats, cached_only=False):
    args = ["git", "ls-files", "--cached"] + ([] if cached_only else ["--others", "--exclude-standard"])
    out = subprocess.run(args + list(pats), capture_output=True, text=True).stdout
    return sorted({p for p in out.split("\n") if p})


def dirs_of(paths):
    out = set()
    for p in paths:
        parts = p.split("/")
        for i in range(1, len(parts)):
            out.add("/".join(parts[:i]))
    return out


tree = set(ls())                       # рабочее дерево без игнорируемого — откуда источники
tracked = set(ls(cached_only=True))    # индекс — что уедет в коммит и будет в клоне
dirs = dirs_of(tree)
tdirs = dirs_of(tracked)

agents = [p for p in ls(".claude/agents") if re.fullmatch(r"\.claude/agents/[^/]+\.md", p)]
if not agents:
    print(f"[VOID] {NAME} — в .claude/agents/ нет ни одного агента: звать некому, "
          "и «находок 0» здесь значило бы «не читали»", file=sys.stderr)
    sys.exit(2)

TEXT = ("md", "sh", "py", "json", "js", "go", "yaml", "yml")
PROBE = re.compile(r"\.claude/hooks/[^/]+/prove\.sh")
skipped_ext = []
sources = list(agents)
sources += [p for p in ls(".claude/rules") if re.fullmatch(r"\.claude/rules/[^/]+\.md", p)]
sources += [p for p in ["CLAUDE.md"] if p in tree]
skill_real = []
for p in ls(".claude/skills"):
    if os.path.islink(p) or not os.path.isfile(p):
        continue
    if p.rsplit(".", 1)[-1] in TEXT:
        skill_real.append(p)
    else:
        skipped_ext.append(p)
sources += skill_real
probe_files = [p for p in ls(".claude/hooks") if PROBE.fullmatch(p)]
hook_src = []
for p in ls(".claude/hooks"):
    if os.path.islink(p) or not os.path.isfile(p) or PROBE.fullmatch(p):
        continue
    if p.rsplit(".", 1)[-1] in TEXT:
        hook_src.append(p)
    else:
        skipped_ext.append(p)
sources += hook_src


def tracked_status(path):
    """ok — в индексе (файл или каталог); untracked — только на диске; missing — нигде."""
    if path in tracked or path in tdirs:
        return "ok"
    if path in tree or path in dirs or os.path.exists(path):
        return "untracked"
    return "missing"


def skill_status(name):
    # Символьная ссылка обязана вести в существующий ОТСЛЕЖИВАЕМЫЙ файл: висячая —
    # тот же отказ, цель вне индекса — тот же, что у пути.
    p = f".claude/skills/{name}/SKILL.md"
    st = tracked_status(p)
    if st != "ok":
        return st
    if os.path.islink(p):
        # Висячая ссылка: цели нет ни в индексе, ни на диске — «missing» по цели.
        return tracked_status(os.path.relpath(os.path.realpath(p), os.getcwd()))
    return "ok"


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

def lenient(fm):
    """Скаляр верхнего уровня, в котором есть «: », — в двойные кавычки."""
    out = []
    for ln in fm.split("\n"):
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]+(.+)$", ln)
        if m and m.group(2)[0] not in "\"'[{|>&*!#" and ": " in m.group(2):
            v = m.group(2).replace("\\", "\\\\").replace('"', '\\"')
            ln = f'{m.group(1)}: "{v}"'
        out.append(ln)
    return "\n".join(out)


try:
    import yaml
except ImportError:
    print(f"[VOID] {NAME} — нет модуля yaml (PyYAML): frontmatter агентов не разобрать, "
          "строки skills: не судились бы вовсе", file=sys.stderr)
    sys.exit(2)

findings = []
cnt = dict(calls=0, calls_bad=0, plugin=0, templ_call=0, prose=0,
           fm=0, fm_bad=0, fm_lenient=0, paths=0, paths_bad=0, templ_path=0, foreign=0, ign=0,
           no_subtree=0)
names = set()

CALL = re.compile(r"(?<![A-Za-z0-9_])Skill[ \t]+(`?)([A-Za-z0-9][A-Za-z0-9_:.-]*)")
PATH = re.compile(r"\.claude/[A-Za-z0-9_./-]*")
_VAR = r"(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*(?::?[-=?+][^}\s]*)?\})"
ROOT_PFX = re.compile(r"(?:^|(?<=[\s`'\"(=:\[{,;|&]))(?:\.|" + _VAR + r"|\"" + _VAR + r"\"|'" + _VAR + r"')/$")

for src in sources:
    try:
        text = open(src, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    lines = text.split("\n")

    def lineno(off):
        return text.count("\n", 0, off) + 1

    # ── род 2: skills: во frontmatter агента — РАЗБОРОМ YAML ──────────────────
    if src in agents and text.startswith("---"):
        end = text.find("\n---", 3)
        fm = text[4:end] if end > 0 else ""
        try:
            root = yaml.compose(fm)
        except yaml.YAMLError:
            # Харнесс читает frontmatter снисходительно: скаляр верхнего уровня с
            # «: » внутри он берёт строкой (тело диспетчера так и написано, и главный
            # поток работает). Повтор разбора — той же поправкой; не разобралось и
            # так — находка.
            try:
                root = yaml.compose(lenient(fm))
                cnt["fm_lenient"] += 1
            except yaml.YAMLError as e:
                cnt["fm_bad"] += 1
                findings.append(f"{src}:1: frontmatter не разбирается как YAML даже "
                                f"снисходительно ({str(e).splitlines()[0]}) — skills: не прочтён")
                root = None
        node = None
        if isinstance(root, yaml.MappingNode):
            for k, v in root.value:
                if isinstance(k, yaml.ScalarNode) and k.value == "skills":
                    node = v
        items = []                           # (имя, строка файла)
        if node is not None:
            line0 = node.start_mark.line + 2  # frontmatter начинается со 2-й строки файла
            if isinstance(node, yaml.SequenceNode):
                for it in node.value:
                    if isinstance(it, yaml.ScalarNode):
                        items.append((it.value, it.start_mark.line + 2))
                    else:
                        cnt["fm_bad"] += 1
                        findings.append(f"{src}:{it.start_mark.line + 2}: skills: элемент не строка — "
                                        "предзагрузка его не прочтёт")
            elif isinstance(node, yaml.ScalarNode) and node.value.strip():
                items = [(x.strip(), line0) for x in node.value.split(",") if x.strip()]
            elif not (isinstance(node, yaml.ScalarNode) and not node.value.strip()):
                cnt["fm_bad"] += 1
                findings.append(f"{src}:{line0}: skills: ни список, ни строка — предзагрузка "
                                "его не прочтёт")
        for name, i in items:
            cnt["fm"] += 1
            if ":" in name:
                cnt["plugin"] += 1
                continue
            st = skill_status(name)
            if st != "ok":
                cnt["fm_bad"] += 1
                findings.append(f"{src}:{i}: skills: «{name}» — "
                                + ("нет " if st == "missing" else "не отслеживается git (в клоне нет) ")
                                + f".claude/skills/{name}/SKILL.md (предзагрузка не состоится, "
                                "агент стартует без правила)")

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
        st = skill_status(name)
        if st != "ok":
            cnt["calls_bad"] += 1
            findings.append(f"{src}:{lineno(m.start())}: `Skill {name}` — "
                            + ("нет " if st == "missing" else "не отслеживается git (в клоне нет) ")
                            + f".claude/skills/{name}/SKILL.md; вызов не даст агенту ничего, "
                            "и отказ молчалив")

    # ── род 3: путь .claude/… ────────────────────────────────────────────────
    for m in PATH.finditer(text):
        tok = m.group(0).rstrip(".")
        post = text[m.end(): m.end() + 1]
        pre = text[max(0, m.start() - 80): m.start()]
        prev = pre[-1:]
        if post and post in "<*{[$":
            cnt["templ_path"] += 1
            continue
        if prev and re.match(r"[A-Za-z0-9_~.-]", prev):
            cnt["foreign"] += 1
            continue
        if prev == "/":
            # Корень: `./`, `$ИМЯ/`, `${ИМЯ}/`, `${ИМЯ:-…}/`, та же переменная в
            # кавычках до косой черты. Остальное перед `/` — чужое дерево или глоб.
            if ROOT_PFX.search(pre):
                pass
            else:
                seg = re.search(r"(\S*)/$", pre)
                if seg and "*" in seg.group(1):
                    cnt["templ_path"] += 1
                else:
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
        st = tracked_status(path)
        if st == "ok":
            continue
        if ignored(path):
            cnt["ign"] += 1
            continue
        cnt["paths_bad"] += 1
        if st == "untracked":
            findings.append(f"{src}:{lineno(m.start())}: путь {path} — есть на диске, но не "
                            "отслеживается git: в клоне конвейера его нет, и вердикт по "
                            "нему зависел бы от рабочего дерева")
        else:
            findings.append(f"{src}:{lineno(m.start())}: путь {path} — в дереве его нет; "
                            "читающий пойдёт по адресу, которого не существует")

print(f"[CENSUS] {NAME}: источников {len(sources)} (агентов {len(agents)}, "
      f"файлов скилов {len(skill_real)}, файлов хуков {len(hook_src)}; "
      f"файлов проб исключено {len(probe_files)}, файлов вне расширений {'/'.join(TEXT)} "
      f"не прочитано {len(skipped_ext)}); "
      f"вызовов Skill {cnt['calls']} (имён {len(names)}), не резолвится {cnt['calls_bad']}; "
      f"имён в skills: {cnt['fm']}, не резолвится или не разобрано {cnt['fm_bad']} "
      f"(frontmatter разобран снисходительно {cnt['fm_lenient']}); "
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
    print(f"[VOID] {NAME} — источников {len(sources)}, но ни одного вызова, имени в skills: "
          "или пути: судить нечего, и это не «всё резолвится»", file=sys.stderr)
    sys.exit(2)
print(f"[PASS] {NAME} — каждый вызов, строка skills: и путь резолвятся")
PY
