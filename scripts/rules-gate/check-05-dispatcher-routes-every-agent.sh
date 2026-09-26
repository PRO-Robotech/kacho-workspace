#!/usr/bin/env bash
# check-05 — БАЗА МАРШРУТИЗАЦИИ ЗНАЕТ КАЖДОГО ИСПОЛНИТЕЛЯ, И ТОЛЬКО ЕГО.
#
# ЧТО УТВЕРЖДАЕТ. Про каждого исполнителя дерева `.claude/agents/` диспетчер знает
# ОБА факта: он вправе его запустить (имя в `tools: Agent(…)`) и знает, когда это
# делать (подраздел с его именем в теле `dispatcher.md`). Обратно: запускать он
# вправе ТОЛЬКО существующих. Сверх того — два свойства самой роли: исполнитель не
# запускает исполнителей (`disallowedTools` содержит `Agent`), а диспетчер не
# читает, не пишет и не исполняет (в его `tools:` нет ни одного такого инструмента).
# И последнее: ссылки на источник, которыми база обосновывает решения, резолвятся.
#
# ПОЧЕМУ ЭТО ГЕЙТ, А НЕ АБЗАЦ. С 2026-09-17 главный поток воркспейса — не человек с
# корпусом в окне, а `"agent": "dispatcher"` с базой маршрутизации вместо корпуса.
# Всё, что он умеет, названо в ДВУХ местах одного файла: список `Agent(…)` даёт
# ПРАВО запуска, тело даёт ПОВОД. Разойтись они могут молча и поодиночке:
#   · агент заведён, в список не попал — запустить его нельзя, и отказ приходит в
#     середине волны, когда полоса уже раздана;
#   · агент заведён, в список попал, подраздела нет — он существует, но повода
#     позвать его в базе нет, и он не будет позван НИКОГДА; по наблюдаемому
#     поведению это неотличимо от его отсутствия, а в переписи он есть;
#   · агент снят, из списка не убран — право на имя, которого нет.
# Ни одно из трёх состояний не проявляется ни в диффе, ни в прогоне продукта.
#
# ДВЕ ОСИ ПРО РОЛЬ — НЕ СИММЕТРИЯ, А ДВА РАЗНЫХ ОТКАЗА.
#   · AGENT-CAN-SPAWN: исполнитель, которому не запрещён `Agent`, заводит вложенные
#     запуски. Тогда решение о полосе принимает не диспетчер, учёт задач мимо
#     `TaskCreate`, а окно родителя растёт непредсказуемо
#     (`multi-agent-flow-orchestration.md` §«14а»).
#   · DISPATCHER-HAS-TOOLS: диспетчер с `Read`/`Bash` перестаёт быть диспетчером в
#     тот же час — разведать самому дешевле, чем раздать, и база съедает контекст,
#     ради экономии которого заведена. Перечень запрещённых инструментов объявлен
#     ОДИН раз, ниже в коде, и назван в тексте находки.
#
# ССЫЛКА НА ИСТОЧНИК — ПРЕДМЕТ, А НЕ УКРАШЕНИЕ. База не пересказывает правила, она
# на них ССЫЛАЕТСЯ: `` `<файл>.md` §«Заголовок» ``. Ссылка — единственный способ
# для читателя базы дойти до нормы, и стоит ей протухнуть (правило переименовано,
# раздел переписан), как база начинает уверенно отсылать в никуда. Правило при этом
# цело, дифф базы пуст, прогон зелен.
#
#   КАК СВЕРЯЕТСЯ ЗАГОЛОВОК, и почему не побайтово. В дереве цитата ЗАКОННО
#   сокращает заголовок: «## 2. Вердикт привязан к ОТПЕЧАТКУ» цитируется как
#   §«Вердикт привязан к ОТПЕЧАТКУ». Поэтому: с обеих сторон снимается ведущая
#   нумерация, пробельные последовательности схлопываются (цитата переносится по
#   строкам), и совпадением считается РАВЕНСТВО либо НАЧАЛО заголовка с цитаты.
#   Чистый номер (§«14а») — законная форма ссылки сам по себе: он верен, если такой
#   нумерованный заголовок есть. Логика измерена на дереве 2026-09-18: из 96 ссылок
#   базы она разрешает 95 и оставляет одну — ту, где цитата назвала ПРЕЖНЕЕ имя
#   раздела (`§«14а. ОРКЕСТРАТОР НЕ ИСПОЛНЯЕТ»` при заголовке `14а. ДИСПЕТЧЕР НЕ
#   ИСПОЛНЯЕТ`, переименованном в этой же ветке). Это находка, а не промах сверки:
#   послабление «номер совпал — считаем верным» сняло бы ось ровно на том классе,
#   ради которого она заведена.
#   Обратное решение (сверять по вхождению подстроки) зелено на ЛЮБОЙ цитате, слово
#   из которой встречается в любом заголовке файла, — то есть почти всегда.
#
#   ОБОРОТ «там же, §«…»» ПРЕДМЕТОМ НЕ ЯВЛЯЕТСЯ и считается отдельно. Файла он не
#   называет, и сверять его пришлось бы с УГАДАННЫМ предшественником; угаданная
#   находка посылает читателя не туда, а это хуже молчания
#   (`.claude/rules/testing.md` §«Гейт на класс», п.8). Число таких оборотов
#   печатается переписью — чтобы «находок 0» не путалось с «не смотрели».
#
# ЗАГОЛОВКИ ЧИТАЮТСЯ ВНЕ ОГРАД. Решётка внутри ```-фенса — строка примера, а не
# заголовок; зачти её, и ссылка на несуществующий раздел резолвилась бы примером.
#
# ЧЕГО ЭТА ПРОВЕРКА НЕ ДЕРЖИТ, названо прямо: она не судит, ПРАВИЛЬНО ли база
# маршрутизирует, — это предмет чтения человеком. Она держит одно: перечень, тело и
# дерево агентов не разъезжаются МОЛЧА.
#
# ПРЕДПОСЫЛКА (VOID, код 2) — ровно одна: в дереве нет каталога `.claude/agents/`.
# Тогда исполнителей не существует вовсе и маршрутизировать некого.
#
# СНЯТЫЙ `dispatcher.md` — НАХОДКА, А НЕ VOID, и это антимаска: главный поток
# объявлен диспетчером в `.claude/settings.json`, и отсутствие его базы при живых
# исполнителях означает главный поток БЕЗ маршрутизации. Иначе достаточно было бы
# снести базу, чтобы гейт перестал блокировать отправку.
#
# Коды выхода: 0 — база и дерево агентов сошлись, находок 0; 1 — находка либо
# пустой обход; 2 — предмета нет.

set -uo pipefail

NAME="check-05-dispatcher-routes-every-agent"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Корень воркспейса. `RULES_GATE_ROOT` переопределяет его — этим пользуется ТОЛЬКО
# инъекция, чтобы прогонять гейт по временному дереву с внесённым дефектом и не
# трогать рабочее (`.claude/rules/testing.md` §«Гейт на класс»).
if [ -n "${RULES_GATE_ROOT:-}" ]; then
    if ! WS="$(cd "$RULES_GATE_ROOT" 2>/dev/null && pwd)"; then
        echo "[CENSUS] $NAME: разбор не запускался; агентов 0, имён в allowlist 0, ссылок 0"
        echo "[VOID] $NAME — RULES_GATE_ROOT=$RULES_GATE_ROOT не открывается — читать неоткуда" >&2
        exit 2
    fi
else
    WS="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

CHECK_NAME="$NAME" RULES_GATE_WS="$WS" python3 - <<'PY'
import os
import re
import sys

NAME = os.environ["CHECK_NAME"]
root = os.environ["RULES_GATE_WS"]

AGENTS_REL = ".claude/agents"
RULES_REL = ".claude/rules"
DISPATCHER = "dispatcher"
DISPATCHER_REL = "%s/%s.md" % (AGENTS_REL, DISPATCHER)

agents_abs = os.path.join(root, AGENTS_REL)
disp_abs = os.path.join(root, DISPATCHER_REL)

# ПЕРЕЧЕНЬ ЗАПРЕЩЁННОГО ДИСПЕТЧЕРУ — ОБЪЯВЛЕН ОДИН РАЗ И НАЗЫВАЕТСЯ В НАХОДКЕ.
# Это инструменты чтения, записи и исполнения: любой из них возвращает диспетчеру
# возможность сделать работу самому, а роль его — раздавать.
FORBIDDEN = ("Read", "Write", "Edit", "Bash", "Grep", "Glob",
             "NotebookEdit", "Skill", "WebFetch", "WebSearch")


def census(msg):
    # Корень — первым: числа переписи суть утверждения о ДЕРЕВЕ (2026-09-22).
    print("[CENSUS] %s: корень %s; %s" % (NAME, root, msg))


def fail(msg):
    print("[FAIL] %s — %s" % (NAME, msg), file=sys.stderr)


def void(msg):
    print("[VOID] %s — %s" % (NAME, msg), file=sys.stderr)
    sys.exit(2)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


# ── предпосылка: исполнители в этом дереве есть ──────────────────────────────
if not os.path.isdir(agents_abs):
    census("каталога %s нет; агентов 0, имён в allowlist 0, подразделов 0, ссылок 0" % AGENTS_REL)
    void("каталога %s нет в %s — исполнителей в этом дереве не существует, "
         "маршрутизировать некого" % (AGENTS_REL, root))

agent_files = sorted(f for f in os.listdir(agents_abs)
                     if f.endswith(".md") and os.path.isfile(os.path.join(agents_abs, f)))
agents = [f[:-3] for f in agent_files]
execs = [a for a in agents if a != DISPATCHER]

FM = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.S)


def split_doc(path):
    """Frontmatter и тело. Нет головного блока — frontmatter пуст, тело целиком."""
    text = read(path)
    m = FM.match(text)
    if not m:
        return "", text
    return m.group(1), text[m.end():]


def fm_value(fm, key):
    m = re.search(r"^%s:[ \t]*(.*)$" % key, fm, re.M)
    return m.group(1).strip() if m else None


# ── база маршрутизации ───────────────────────────────────────────────────────
disp_fm, disp_body = ("", "")
disp_bytes = 0
if os.path.isfile(disp_abs):
    disp_bytes = os.path.getsize(disp_abs)
    disp_fm, disp_body = split_doc(disp_abs)

tools_raw = fm_value(disp_fm, "tools") or ""
m = re.search(r"Agent\s*\(([^)]*)\)", tools_raw)
allow = [x.strip() for x in m.group(1).split(",") if x.strip()] if m else []
allow_set = set(allow)
# Остальные инструменты — то, что осталось от строки `tools:` после снятия
# `Agent(…)`: скобка внутри перечня иначе разрезала бы имена по запятым.
rest_tools = [x.strip() for x in re.sub(r"Agent\s*\([^)]*\)", "", tools_raw).split(",") if x.strip()]

FENCE = re.compile(r"^\s*(?:```|~~~)")
HEAD = re.compile(r"^#{1,6}\s+(.*?)\s*$")


def headings(text):
    """Заголовки ВНЕ оград: решётка внутри фенса — строка примера, а не заголовок."""
    out = []
    fence = False
    for line in text.split("\n"):
        if FENCE.match(line):
            fence = not fence
            continue
        if fence:
            continue
        m = HEAD.match(line)
        if m:
            out.append(m.group(1))
    return out


disp_heads = headings(disp_body)

# ── ССЫЛКИ НА ИСТОЧНИК ──────────────────────────────────────────────────────
# Форма — `<файл>.md` в обратных кавычках, за ней одна или несколько цитат §«…»
# подряд: вторая цитата относится к тому же файлу и обязана сверяться так же.
REF = re.compile(r"`([^`\n]+\.md)`((?:\s*§«[^»]*»\s*,?)+)")
QUOTE = re.compile(r"§«([^»]*)»")
# Ведущая нумерация: «14а.», «2.», «5)». Снимается с ОБЕИХ сторон.
NUMBER = re.compile(r"^\s*([0-9]+[A-Za-zА-Яа-яЁё]?)[.)]?\s*")
PURE_NUMBER = re.compile(r"^\s*[0-9]+[A-Za-zА-Яа-яЁё]?[.)]?\s*$")


def flat(s):
    """Пробельные последовательности схлопнуты: цитата переносится по строкам."""
    return re.sub(r"\s+", " ", s).strip()


def denum(s):
    return NUMBER.sub("", flat(s)).strip()


def number_of(s):
    m = NUMBER.match(flat(s))
    return m.group(1) if m else None


def resolves(heads, quote):
    q = flat(quote)
    if PURE_NUMBER.match(q):
        n = number_of(q)
        return any(number_of(h) == n for h in heads)
    qd = denum(q)
    if not qd:
        return False
    for h in heads:
        hf = flat(h)
        hd = denum(hf)
        if hf == q or hf.startswith(q) or hd == qd or hd.startswith(qd):
            return True
    return False


refs = []          # (файл, цитата)
for m in REF.finditer(disp_body):
    for q in QUOTE.findall(m.group(2)):
        refs.append((m.group(1), q))
# «там же» — оборот без имени файла; предметом не является, но считается.
same_place = len(QUOTE.findall(disp_body)) - len(refs)

head_cache = {}


def heads_of(rel):
    if rel not in head_cache:
        head_cache[rel] = headings(read(rel))
    return head_cache[rel]


def source_path(name):
    """Куда ссылается база: файл корпуса либо файл в корне (`CLAUDE.md`)."""
    for cand in (os.path.join(root, RULES_REL, name), os.path.join(root, name)):
        if os.path.isfile(cand):
            return cand
    return None


# ── ПЕРЕПИСЬ ОБЪЁМА — печатается ВСЕГДА и до вердикта ────────────────────────
census("%s — %d Б, заголовков вне оград %d; агентов в %s — %d, из них исполнителей %d; "
       "имён в `tools: Agent(…)` — %d, прочих инструментов у диспетчера %d; "
       "ссылок вида `файл.md` §«…» — %d, оборотов «там же» (вне предмета) — %d"
       % (DISPATCHER_REL, disp_bytes, len(disp_heads), AGENTS_REL, len(agents), len(execs),
          len(allow), len(rest_tools), len(refs), same_place))

# ── ПУСТОЙ ОБХОД — НАХОДКА, А НЕ УСПЕХ ───────────────────────────────────────
if not os.path.isfile(disp_abs):
    fail("%s в дереве нет при %d исполнителях — главный поток объявлен диспетчером в "
         "`.claude/settings.json`, и без базы он остаётся без маршрутизации вовсе; это "
         "находка, а не отсутствие предмета" % (DISPATCHER_REL, len(execs)))
    sys.exit(1)
if not execs:
    fail("обход беспредметен: в %s нет ни одного файла исполнителя (кроме базы) — "
         "маршрутизировать некого, и «находок 0» здесь означало бы «не прочитано ничего»"
         % AGENTS_REL)
    sys.exit(1)

findings = 0

# ── ОСЬ ALLOWLIST-DRIFT: право запуска ≠ дерево агентов ──────────────────────
# Называются ОБЕ разности: находка про одну сторону посылает чинить половину.
missing = [a for a in execs if a not in allow_set]
extra = sorted(allow_set - set(execs))
for a in missing:
    fail("ALLOWLIST-DRIFT: %s/%s.md существует, а имени «%s» в `tools: Agent(…)` базы нет "
         "— диспетчер НЕ ВПРАВЕ его запустить, и отказ придёт в середине волны, когда "
         "полоса уже раздана" % (AGENTS_REL, a, a))
    findings += 1
for a in extra:
    fail("ALLOWLIST-DRIFT: `tools: Agent(…)` базы называет «%s», а файла %s/%s.md нет — "
         "право на имя, которого не существует; запуск отказывает в исполнении, а перепись "
         "агентов остаётся полной" % (a, AGENTS_REL, a))
    findings += 1

# ── ОСЬ AGENT-NOT-IN-BASE: право есть, повода нет ───────────────────────────
# Имя ищется ЦЕЛИКОМ: `ui-reviewer` не должен зачитываться за `landing-reviewer`,
# иначе подраздел одного агента покрывал бы отсутствие подраздела другого.
for a in execs:
    word = re.compile(r"(?<![A-Za-z0-9_-])%s(?![A-Za-z0-9_-])" % re.escape(a))
    if not any(word.search(h) for h in disp_heads):
        fail("AGENT-NOT-IN-BASE: %s/%s.md существует, а подраздела с его именем в теле "
             "%s нет — повода позвать его в базе не названо, и позван он не будет НИКОГДА; "
             "по поведению это неотличимо от его отсутствия"
             % (AGENTS_REL, a, DISPATCHER_REL))
        findings += 1

# ── ОСЬ AGENT-CAN-SPAWN: исполнитель, запускающий исполнителей ──────────────
for a in execs:
    fm, _ = split_doc(os.path.join(agents_abs, a + ".md"))
    raw = fm_value(fm, "disallowedTools")
    items = [x.strip() for x in (raw or "").replace("[", "").replace("]", "").split(",") if x.strip()]
    if "Agent" not in items:
        fail("AGENT-CAN-SPAWN: %s/%s.md — `disallowedTools` не содержит `Agent` (там %s); "
             "исполнитель заводит вложенные запуски, решение о полосе принимает не "
             "диспетчер, а задачи идут мимо учёта"
             % (AGENTS_REL, a, ("«%s»" % raw) if raw else "ключа нет вовсе"))
        findings += 1

# ── ОСЬ DISPATCHER-HAS-TOOLS: база перестала быть базой ─────────────────────
got_forbidden = [t for t in rest_tools if t in FORBIDDEN]
for t in got_forbidden:
    fail("DISPATCHER-HAS-TOOLS: в `tools:` базы появился `%s` — инструмент чтения, записи "
         "или исполнения (перечень: %s); диспетчер, умеющий сделать сам, перестаёт "
         "раздавать, и контекст, ради которого база заведена, съедается им же"
         % (t, ", ".join(FORBIDDEN)))
    findings += 1

# ── ОСЬ BAD-SOURCE-REF: обоснование ведёт в никуда ──────────────────────────
missing_files = 0
missing_heads = 0
for name, quote in refs:
    path = source_path(name)
    if path is None:
        fail("BAD-SOURCE-REF: %s ссылается на `%s` §«%s» — такого файла нет ни в %s/, ни в "
             "корне; обоснование решения ведёт в никуда, а читатель базы дойти до нормы не "
             "может" % (DISPATCHER_REL, name, flat(quote), RULES_REL))
        findings += 1
        missing_files += 1
        continue
    if not resolves(heads_of(path), quote):
        fail("BAD-SOURCE-REF: %s ссылается на `%s` §«%s» — файл есть, заголовка с такой "
             "цитатой в нём нет (сверка: ведущая нумерация снята, совпадение по префиксу); "
             "раздел переименован либо снят, а ссылка осталась"
             % (DISPATCHER_REL, name, flat(quote)))
        findings += 1
        missing_heads += 1

if findings:
    fail("находок %d; исполнителей %d, имён в allowlist %d, ссылок %d (из них без файла %d, "
         "без заголовка %d)"
         % (findings, len(execs), len(allow), len(refs), missing_files, missing_heads))
    sys.exit(1)

print("[PASS] %s — база знает каждого исполнителя: исполнителей %d, все %d в "
      "`tools: Agent(…)` и у каждого подраздел в теле; лишних имён 0; исполнителей без "
      "запрета `Agent` 0; запрещённых инструментов у базы 0; ссылок на источник %d, "
      "все резолвятся" % (NAME, len(execs), len(allow), len(refs)))
sys.exit(0)
PY
