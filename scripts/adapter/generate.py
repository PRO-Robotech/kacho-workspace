#!/usr/bin/env python3
"""Генератор производного оснастки для других агентских сред.

    python3 scripts/adapter/generate.py            # записать в дерево
    python3 scripts/adapter/generate.py --out DIR  # записать во временный каталог
    python3 scripts/adapter/generate.py --list     # перечислить владеемые выходы

ЧТО ЭТО. Оснастка Kachō живёт в единственном экземпляре — `.claude/` воркспейса
(`.claude/rules/ai-tooling.md` §Модель распространения). Среды, читающие
`AGENTS.md`, `.agents/skills/` и `.codex/`, получают её ПРОЕКЦИЮ. Проекция —
выход; оснастка — вход; владение объявлено в `.claude/adapters.yaml`.

ТРИ СВОЙСТВА, РАДИ КОТОРЫХ ЭТО СКРИПТ, А НЕ РУЧНАЯ РАБОТА.

1. ДЕТЕРМИНИЗМ. Один и тот же вход даёт побайтово один и тот же выход: обходы
   отсортированы по байтам (не по локали), переводы строк нормализованы, ни
   одной отметки времени и ни одного пути машины в выходе нет. Без этого
   побайтовое сравнение с деревом невозможно, а значит расхождение входа и
   выхода не обнаруживается ничем.

2. КАНОНИЧЕСКИЕ ВХОДЫ. Читается ТОЛЬКО то, что перечислено в манифесте, и это
   не декларация: `_read()` отвергает путь вне набора. Производное, зависящее
   от неканонического входа, перестаёт быть воспроизводимым из оснастки.

3. ИМЯ КАТАЛОГА ОСНАСТКИ НЕ ПОДСТАВЛЯЕТСЯ. Соблазн «раз выход для другой среды,
   заменим `.claude` на её имя» выглядит естественным и измеренно дорог: в
   порождённых вручную файлах, лежавших в дереве до этой работы, оказалось 141
   вхождение заглавной формы имени второй среды в 25 файлах, а корневой
   указатель импортировал 15 координат правил в каталоге, которого не
   существует ни на одном диске. Обе беды — прямое следствие слепой подстановки
   по имени: она попадает внутрь чужих имён и рождает координаты без предмета.
   Поэтому подстановка не производится ВОВСЕ, а порождённые тексты ссылаются на
   канонические координаты `.claude/...` — те, что существуют.

Коды выхода: 0 — записано N выходов; 1 — манифест или дерево не сходятся;
2 — предмета нет (манифест не найден).
"""

import argparse
import os
import re
import shutil
import sys

import yaml

MANIFEST_RELPATH = os.path.join(".claude", "adapters.yaml")

# Единственный предикат привязки, который умеет этот генератор. Сверяется с
# объявленным в манифесте: разойдутся — отказ, а не подстановка своего понимания.
BINDING_PREDICATE = "symlinked-skill-md"

# Заголовок, который несёт каждый порождённый текстовый файл. Без него читатель
# правит производное, а правка уезжает при следующей регенерации — молча.
BANNER_LINES = [
    "ПОРОЖДЁННЫЙ ФАЙЛ — РУКАМИ НЕ ПРАВИТЬ.",
    "Источник: канонические входы .claude/ и корневой CLAUDE.md.",
    "Владение: .claude/adapters.yaml. Генератор: scripts/adapter/generate.py.",
    "Правка уедет при следующей регенерации; предмет правки — во входе.",
]


class GeneratorError(Exception):
    """Предмета нет либо манифест не сходится с деревом."""


def repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def _norm(text):
    """Нормализует переводы строк и хвост файла.

    Порождённый файл обязан быть побайтово воспроизводимым, а редакторы и
    системы контроля версий по-разному оканчивают последнюю строку. Различие в
    одном байте хвоста неотличимо от настоящего расхождения.
    """
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if text and not text.endswith("\n"):
        text += "\n"
    return text


class Manifest:
    """Единственное объявление владения; читается, а не угадывается."""

    def __init__(self, root):
        self.root = root
        path = os.path.join(root, MANIFEST_RELPATH)
        if not os.path.exists(path):
            raise GeneratorError("манифест не найден: %s" % MANIFEST_RELPATH)
        with open(path, "r", encoding="utf-8") as handle:
            doc = yaml.safe_load(handle)
        if not isinstance(doc, dict):
            raise GeneratorError("манифест не разбирается в отображение")

        self.canonical_inputs = list(doc.get("canonical_inputs") or [])
        self.owned_namespaces = list(doc.get("owned_namespaces") or [])
        self.skills = list(doc.get("skills") or [])
        self.owned_outputs = list(doc.get("owned_outputs") or [])

        # Привязки правил: объявление читается, а не подразумевается.
        #
        # `.claude/skills/rule-<имя>/SKILL.md` — символьная ссылка в
        # `.claude/rules/`; такой каталог есть АДРЕС правила для предзагрузки, а не
        # экспертиза, и пакетом во вторую среду не едет (довод — в манифесте,
        # §ПРИВЯЗКИ ПРАВИЛ НЕ ПРОЕЦИРУЮТСЯ). Ключ отсутствует или несёт незнакомое
        # значение — ОТКАЗ: «понял по-своему» здесь означало бы, что генератор
        # решает за манифест, какой текст удваивать.
        bindings = doc.get("skill_bindings")
        if not isinstance(bindings, dict):
            raise GeneratorError(
                "в манифесте нет ключа skill_bindings — не объявлено, чем привязка "
                "правила отличается от скила"
            )
        self.binding_predicate = str(bindings.get("predicate") or "")
        self.binding_prefix = str(bindings.get("reserved_prefix") or "")
        if self.binding_predicate != BINDING_PREDICATE:
            raise GeneratorError(
                "skill_bindings.predicate = %r, а генератор умеет только %r"
                % (self.binding_predicate, BINDING_PREDICATE)
            )
        if not self.binding_prefix:
            raise GeneratorError("skill_bindings.reserved_prefix пуст — имя не занято ничем")

        # Пустой набор — отказ, а не успех: генератор, которому нечего писать,
        # неотличим от исправно отработавшего, и это ровно тот класс, который
        # корпус ловит («ноль находок» против «ноль прочитанного»).
        if not self.canonical_inputs:
            raise GeneratorError("canonical_inputs пуст — читать нечего")
        if not self.owned_outputs:
            raise GeneratorError("owned_outputs пуст — писать нечего")
        if not self.skills:
            raise GeneratorError("skills пуст — пакеты не из чего порождать")

    def is_canonical(self, relpath):
        """Принадлежит ли путь каноническим входам."""
        relpath = relpath.replace(os.sep, "/")
        for entry in self.canonical_inputs:
            if relpath == entry or relpath.startswith(entry.rstrip("/") + "/"):
                return True
        return False

    def owns(self, relpath):
        """Отвечает ли адаптер за КАЖДЫЙ отслеживаемый файл по этому пути.

        Пакеты скилов проверяются поимённо: пакет внутри `.agents/skills/`,
        которого нет среди `skills`, принадлежит другой установке и выходом
        адаптера не является.
        """
        relpath = relpath.replace(os.sep, "/")
        for entry in self.owned_namespaces:
            if relpath == entry or relpath.startswith(entry.rstrip("/") + "/"):
                return True
        for name in self.skills:
            prefix = ".agents/skills/%s/" % name
            if relpath.startswith(prefix):
                return True
        return False


class Reader:
    """Чтение входов с проверкой каноничности — по построению, а не по обещанию."""

    def __init__(self, root, manifest):
        self.root = root
        self.manifest = manifest
        self.read_paths = []

    def read(self, relpath):
        if not self.manifest.is_canonical(relpath):
            raise GeneratorError(
                "попытка прочитать неканонический вход: %s "
                "(канонические перечислены в %s)" % (relpath, MANIFEST_RELPATH)
            )
        full = os.path.join(self.root, relpath)
        if not os.path.exists(full):
            raise GeneratorError("канонический вход отсутствует: %s" % relpath)
        self.read_paths.append(relpath)
        with open(full, "rb") as handle:
            return handle.read()

    def read_text(self, relpath):
        return _norm(self.read(relpath).decode("utf-8"))

    def islink(self, relpath):
        """Символьная ли это ссылка — с той же проверкой каноничности.

        Спрашивается ДИСК, а не индекс: «ссылка» есть свойство файла, и именно им
        отличается привязка правила от экспертизы. Проверка каноничности здесь
        та же, что у чтения: путь вне набора не должен влиять на выход даже
        вопросом о своём типе.
        """
        if not self.manifest.is_canonical(relpath):
            raise GeneratorError("неканонический путь: %s" % relpath)
        return os.path.islink(os.path.join(self.root, relpath))

    def listdir(self, relpath):
        """Отсортированный по БАЙТАМ обход каталога канонического входа.

        Сортировка по байтам, а не по локали: `sorted()` над строками Python
        сравнивает кодовые точки и от переменных окружения не зависит, тогда
        как `ls`/`sort` зависят — и тогда выход менялся бы от машины.
        """
        if not self.manifest.is_canonical(relpath):
            raise GeneratorError("неканонический каталог: %s" % relpath)
        full = os.path.join(self.root, relpath)
        if not os.path.isdir(full):
            raise GeneratorError("канонический каталог отсутствует: %s" % relpath)
        out = []
        for dirpath, dirnames, filenames in os.walk(full):
            dirnames[:] = sorted(d for d in dirnames if d not in (".git", "__pycache__"))
            for name in sorted(filenames):
                absolute = os.path.join(dirpath, name)
                out.append(os.path.relpath(absolute, self.root).replace(os.sep, "/"))
        return sorted(out)


# ─── разбор входов ────────────────────────────────────────────────────────────

FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n(.*)\Z", re.DOTALL)
FRONTMATTER_KEY = re.compile(r"\A([A-Za-z0-9_-]+):[ \t]?(.*)\Z")


def split_frontmatter(text, label):
    """Разбирает шапку файла оснастки построчно, а НЕ строгим YAML.

    Это не небрежность, а соответствие фактическому формату входа. Замер по
    дереву: из 30 шапок агентов и скилов **4** строгим YAML не разбираются —
    описание содержит двоеточие («на крае (каталог gateway/ монорепо):
    allowlist …»), и разборщик YAML читает его как вложенное отображение.

    Эти четыре файла подхватываются средой и работают, то есть строгий YAML —
    не тот предикат, которым проверяют вход. Требовать его значило бы править
    канонические входы под удобство генератора: генератор существует ради
    входов, а не наоборот.

    Форма шапки: `ключ: значение` на верхнем уровне, продолжение — строки,
    не начинающиеся с ключа.
    """
    match = FRONTMATTER.match(text)
    if not match:
        raise GeneratorError("нет frontmatter: %s" % label)

    head = {}
    key = None
    for line in match.group(1).split("\n"):
        found = FRONTMATTER_KEY.match(line)
        if found:
            key = found.group(1)
            head[key] = found.group(2).strip()
        elif key is not None and line.strip():
            head[key] = (head[key] + " " + line.strip()).strip()
    if not head:
        raise GeneratorError("в frontmatter не разобрано ни одного ключа: %s" % label)

    for key, value in list(head.items()):
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            head[key] = value[1:-1]
    return head, match.group(2)


# ── шапка агента: КАЖДЫЙ ключ назван, ни один не теряется молча ───────────────
#
# ЧТО ЗДЕСЬ БЫЛО И ЧЕМ ЭТО СТОИЛО. Прежняя редакция брала из шапки `name` и
# `description`, а всё остальное роняла БЕЗ СЛОВА. Роняла она при этом несущее:
# `skills: rule-*` — перечень правил, которые харнесс кладёт агенту в окно ДО
# первого действия (решение владельца 2026-09-17), и агент во второй среде
# получал тело, написанное в расчёте на корпус, которого у него нет;
# `disallowedTools: Agent` — запрет вложенных запусков, то есть ровно то, чем
# держится «последовательность агентов выставляет только диспетчер».
#
# Тихая потеря хуже отказа: её не видно ни в выходе, ни в гейте — производное
# сходится с регенерацией побайтово, потому что обе стороны теряют одно и то же.
#
# ПОЭТОМУ КЛЮЧИ ПЕРЕЧИСЛЕНЫ ПОИМЁННО. Незнакомый ключ — ОТКАЗ генератора: он
# означает, что в оснастке завелось поведение, о переводе которого никто не
# решал, и молчание было бы решением «оно неважно», принятым не человеком.
AGENT_FRONTMATTER_KEYS = (
    "name",
    "description",
    "skills",
    "tools",
    "disallowedTools",
    "omitClaudeMd",
)

# Элемент списка YAML, свёрнутого разбором шапки в одну строку. Перед дефисом
# обязан стоять пробел или начало строки, за ним — пробел: иначе выражение резало
# бы по дефису ВНУТРИ имени (`rule-git-issues-ci-runs`).
FRONTMATTER_ITEM = re.compile(r"(?:\A|\s)-\s+(\S+)")


def frontmatter_list(value, key, label):
    """Значение-список из свёрнутой шапки.

    Разбор шапки складывает продолжения строк в одну (см. `split_frontmatter`),
    поэтому список приезжает сюда как «- a - b - c». Пустое значение списком не
    является: ключ, объявленный без единого элемента, — не «ничего не выбрано», а
    незаконченная правка, и отказ здесь дешевле тихого пустого перечня.
    """
    items = FRONTMATTER_ITEM.findall(value)
    if not items:
        raise GeneratorError(
            "ключ %s в шапке %s объявлен, но не несёт ни одного элемента" % (key, label)
        )
    return items


def rule_coordinate(name, prefix):
    """Координата правила по имени его привязки: `rule-<имя>` → `.claude/rules/<имя>.md`.

    Существование файла здесь НЕ перепроверяется намеренно: это предмет
    `scripts/rules-gate/` (оси `RULE-SKILL-MISSING`, `AGENT-RULE-DANGLING`), и
    второй кодек об одном предмете разошёлся бы с первым молча.
    """
    return ".claude/rules/%s.md" % name[len(prefix):]


def render_agent_preamble(head, label, manifest):
    """Шапка агента, переведённая в ПОРУЧЕНИЕ СЛОВАМИ.

    Среда, читающая `.codex/agents/*.toml`, не применяет ни `skills:`, ни
    `tools:`: у неё этих настроек нет. Значит выбор ровно один — либо потерять их
    молча, либо объявить их текстом и оставить держаться чтением агента. Первое
    уже стоило корпуса в окне исполнителя; второе честно называет, чем оно
    держится, и потому написано словами «прочитай», «у тебя нет», а не «настроено».
    """
    lines = []

    if "skills" in head:
        names = frontmatter_list(head["skills"], "skills", label)
        rules, expertise = [], []
        for name in names:
            if name.startswith(manifest.binding_prefix):
                rules.append(rule_coordinate(name, manifest.binding_prefix))
            else:
                expertise.append(name)
        lines.append("## Предзагрузка норм — здесь она твоё первое действие")
        lines.append("")
        lines.append(
            "В канонической оснастке эти нормы приезжают ПРЕДЗАГРУЗКОЙ: их "
            "перечисляет `skills:` шапки агента, и харнесс кладёт их текст в окно "
            "до первого твоего действия. Здесь такой настройки нет, поэтому "
            "предзагрузка — твоё первое действие, а не условие запуска. "
            "Прочитанное назови в возврате: норма, которую ты не открыл, тобой не "
            "применена, чем бы ни выглядел результат."
        )
        lines.append("")
        if rules:
            lines.append(
                "**При старте прочитай целиком:** %s."
                % ", ".join("`%s`" % path for path in rules)
            )
            lines.append("")
        if expertise:
            lines.append(
                "**Скилы-экспертизы:** %s — пакет каждого лежит в "
                "`.agents/skills/<имя>/`, источник `.claude/skills/<имя>/`."
                % ", ".join("`%s`" % name for name in expertise)
            )
            lines.append("")

    if "tools" in head or "disallowedTools" in head:
        lines.append("## Ограничение инструментов — объявлено, а не настроено")
        lines.append("")
        lines.append(
            "В канонической оснастке это ограничение применяет харнесс. Здесь его "
            "применять нечему, поэтому оно держится твоим чтением: вышел за него — "
            "прогон недействителен, и объявить это обязан ты сам, а не тот, кто "
            "будет разбирать последствия."
        )
        lines.append("")
        if "tools" in head:
            lines.append(
                "**Разрешено только это (перечень шапки, дословно):** %s."
                % head["tools"]
            )
            lines.append("")
        if "disallowedTools" in head:
            lines.append("**Запрещено:** %s." % head["disallowedTools"])
            lines.append("")
            # `Agent` назван отдельно: это не один из запретов, а то, чем держится
            # «последовательность агентов выставляет только диспетчер».
            if "Agent" in [t.strip() for t in head["disallowedTools"].split(",")]:
                lines.append(
                    "Запуска другого агента у тебя НЕТ. Нужен другой — строкой "
                    "«нужен следующий» в блоке ВОЗВРАТ: это заказ диспетчеру, а не "
                    "команда, и кого запускать, решает он."
                )
                lines.append("")

    if "omitClaudeMd" in head:
        value = head["omitClaudeMd"].strip().lower()
        if value not in ("true", "false"):
            raise GeneratorError(
                "omitClaudeMd в шапке %s несёт %r — генератор знает только true/false"
                % (label, head["omitClaudeMd"])
            )
        if value == "true":
            lines.append("## Общий протокол воркспейса тебе НЕ грузится")
            lines.append("")
            lines.append(
                "Шапка агента объявляет `omitClaudeMd: true`: корневой `CLAUDE.md` "
                "в твоё окно не попадает. Это решение, а не упущение, — и открывать "
                "его самому тоже не нужно: всё, что тебе положено, в этом файле."
            )
            lines.append("")

    if not lines:
        return ""
    return "\n".join(lines).rstrip("\n") + "\n\n---\n\n"


def toml_basic_string(value):
    """Однострочный TOML-литерал с экранированием по спецификации."""
    out = []
    for char in value:
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        elif ord(char) < 0x20:
            out.append("\\u%04X" % ord(char))
        else:
            out.append(char)
    return '"%s"' % "".join(out)


def toml_multiline_string(value):
    """Многострочный TOML-литерал.

    Экранируются ровно две вещи, и обе — не педантизм: обратная косая (иначе
    следующий символ становится управляющей последовательностью) и тройная
    кавычка (иначе литерал закрывается посреди текста, и файл перестаёт
    разбираться — молча для генератора и громко для читающей среды).
    """
    body = value.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    if body.endswith('"'):
        body = body[:-1] + '\\"'
    return '"""\n%s"""' % body


# ─── порождение ───────────────────────────────────────────────────────────────


DISPATCHER_RELPATH = ".claude/agents/dispatcher.md"


def render_agents_md(reader, manifest):
    """Корневой указатель для сред, читающих AGENTS.md.

    Тело — канонический CLAUDE.md ДОСЛОВНО. Именно дословно, а не «адаптировано»:
    подстановка имени каталога оснастки запрещена (см. шапку модуля), а
    пересказ дал бы второе место об одном предмете, которое разойдётся молча.

    БАЗА МАРШРУТИЗАЦИИ ЕДЕТ СЮДА ЖЕ — И ЭТО НЕ УДОБСТВО. В канонической оснастке
    главный поток есть агент `dispatcher` (`.claude/settings.json` → `agent`), и
    тело `dispatcher.md` заменяет ему системный промпт. У сред, читающих
    `AGENTS.md`, настройки `agent` нет вовсе: главный поток там ничем не
    заменяется и без базы остаётся БЕЗ МАРШРУТИЗАЦИИ — то есть читает общий
    протокол, где сказано «раздаёт диспетчер», и не имеет ни одного правила, кому
    что раздавать. Дословно — по тому же доводу, что и `CLAUDE.md`: пересказ базы
    был бы вторым местом об одном предмете и разошёлся бы с оригиналом молча.
    """
    body = reader.read_text("CLAUDE.md")

    agent_files = [
        p for p in reader.listdir(".claude/agents") if p.endswith(".md")
    ]
    if DISPATCHER_RELPATH not in agent_files:
        raise GeneratorError(
            "нет %s — в AGENTS.md нечем заменить базу маршрутизации, а без неё "
            "главный поток второй среды остаётся без неё вовсе" % DISPATCHER_RELPATH
        )
    _, dispatcher_body = split_frontmatter(
        reader.read_text(DISPATCHER_RELPATH), DISPATCHER_RELPATH
    )

    skill_names = sorted(manifest.skills)

    lines = ["<!--"]
    lines.extend("  %s" % line for line in BANNER_LINES)
    lines.append("-->")
    lines.append("")
    lines.append(body.rstrip("\n"))
    lines.append("")
    lines.append("## База маршрутизации — тело `%s` ДОСЛОВНО" % DISPATCHER_RELPATH)
    lines.append("")
    lines.append(
        "В канонической оснастке эту базу получает агент `dispatcher`, назначенный "
        "главным потоком в `.claude/settings.json`. Здесь настройки `agent` нет, "
        "заменить главному потоку системный промпт нечем — поэтому база лежит "
        "прямо тут и читается как часть указателя. Правится она **только** в "
        "`%s`: этот текст порождён из неё и уедет при следующей регенерации."
        % DISPATCHER_RELPATH
    )
    lines.append("")
    lines.append(dispatcher_body.strip("\n"))
    lines.append("")
    lines.append("## Роли и экспертиза, доступные в этом дереве")
    lines.append("")
    lines.append(
        "Перечни ВЫВЕДЕНЫ из канонической оснастки при регенерации, а не выписаны: "
        "рукописный список расходится с деревом молча."
    )
    lines.append("")
    lines.append("### Агенты (%d)" % len(agent_files))
    lines.append("")
    for relpath in agent_files:
        text = reader.read_text(relpath)
        head, _ = split_frontmatter(text, relpath)
        name = str(head.get("name") or "").strip()
        description = " ".join(str(head.get("description") or "").split())
        if not name:
            raise GeneratorError("у агента нет имени: %s" % relpath)
        lines.append("- `%s` — %s" % (name, description))
    lines.append("")
    lines.append("### Скилы (%d)" % len(skill_names))
    lines.append("")
    for name in skill_names:
        relpath = ".claude/skills/%s/SKILL.md" % name
        head, _ = split_frontmatter(reader.read_text(relpath), relpath)
        description = " ".join(str(head.get("description") or "").split())
        lines.append("- `%s` — %s" % (name, description))
    lines.append("")
    lines.append(
        "Полные пакеты скилов лежат рядом, в `.agents/skills/<имя>/`; "
        "источник — `.claude/skills/<имя>/`."
    )
    return "\n".join(lines) + "\n"


def render_agent_toml(reader, relpath, manifest):
    text = reader.read_text(relpath)
    head, body = split_frontmatter(text, relpath)

    # Незнакомый ключ — ОТКАЗ, а не тихая потеря. Проверка стоит ПЕРВОЙ: дальше
    # генератор читает только знакомое, и незнакомое иначе просто не встретилось
    # бы ему на пути.
    unknown = [key for key in head if key not in AGENT_FRONTMATTER_KEYS]
    if unknown:
        raise GeneratorError(
            "в шапке %s ключи, о переводе которых никто не решал: %s "
            "(известные: %s). Молчаливая потеря ключа не видна ни в выходе, ни в "
            "гейте — предмет решения во входе"
            % (relpath, ", ".join(sorted(unknown)), ", ".join(AGENT_FRONTMATTER_KEYS))
        )

    name = str(head.get("name") or "").strip()
    description = " ".join(str(head.get("description") or "").split())
    if not name:
        raise GeneratorError("у агента нет имени: %s" % relpath)

    preamble = render_agent_preamble(head, relpath, manifest)
    banner = "\n".join("# %s" % line for line in BANNER_LINES)
    return "%s\nname = %s\ndescription = %s\ndeveloper_instructions = %s\n" % (
        banner,
        toml_basic_string(name),
        toml_basic_string(description),
        toml_multiline_string(preamble + body.lstrip("\n")),
    )


def render_hook_shim(hook_name):
    """Переходник ко ВСТРОЕННОМУ каноническому хуку.

    Не копия. Копия хука разошлась бы с оригиналом молча — тот же класс, что
    копия нормативной карты; переходник расходиться не может by construction.

    Корень дерева вычисляется из собственного пути переходника, а не берётся из
    переменной окружения и не пишется абсолютным путём: абсолютный путь в
    порождённом — находка (`CG_ADAPTER_PATH_NOT_PORTABLE`), а переменная может
    быть не выставлена, и тогда хук молча не исполнится.
    """
    banner = "\n".join("# %s" % line for line in BANNER_LINES)
    return (
        "#!/usr/bin/env bash\n"
        "%s\n"
        "set -u\n"
        "_src=\"${BASH_SOURCE[0]}\"\n"
        "_dir=\"$(cd \"${_src%%/*}\" 2>/dev/null && pwd)\" || _dir=\".\"\n"
        "ROOT=\"$(cd \"$_dir/../..\" 2>/dev/null && pwd)\" || ROOT=\".\"\n"
        "CANONICAL=\"$ROOT/.claude/hooks/%s\"\n"
        "if [ ! -f \"$CANONICAL\" ]; then\n"
        "  echo \"переходник указывает на отсутствующий канонический хук: "
        ".claude/hooks/%s\" >&2\n"
        "  echo \"Это НАСТРОЙКА, а не сбой: она не чинится сама и не истечёт.\" >&2\n"
        "  exit 2\n"
        "fi\n"
        "exec bash \"$CANONICAL\" \"$@\"\n" % (banner, hook_name, hook_name)
    )


def render_hooks_json(reader):
    """Провязка хуков для второй среды из канонических настроек.

    Блок разрешений НЕ переносится намеренно: выбор режима разрешений — решение
    про конкретную машину, и закоммиченный в публичный репозиторий он принимал
    бы этот выбор за каждого клонирующего (`ai-tooling.md` §settings.json едет
    БЕЗ блока permissions).

    Команды перезаписываются на ОТНОСИТЕЛЬНЫЙ путь к переходнику. Абсолютный
    путь машины в порождённом файле — находка: он не переносится ни на другую
    машину, ни в другой клон, а выглядит рабочим.
    """
    import json

    raw = reader.read_text(".claude/settings.json")
    settings = json.loads(raw)
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict) or not hooks:
        raise GeneratorError("в .claude/settings.json нет провязки хуков")

    pattern = re.compile(r"\.claude/hooks/([A-Za-z0-9._-]+\.sh)")
    out_hooks = {}
    for event in sorted(hooks):
        entries = []
        for group in hooks[event]:
            new_group = {}
            if "matcher" in group:
                new_group["matcher"] = group["matcher"]
            commands = []
            for item in group.get("hooks", []):
                command = item.get("command", "")
                match = pattern.search(command)
                if not match:
                    raise GeneratorError(
                        "команда хука не называет канонического хука: %r" % command
                    )
                new_item = {
                    "type": item.get("type", "command"),
                    "command": 'bash ".codex/hooks/%s"' % match.group(1),
                }
                if "timeout" in item:
                    new_item["timeout"] = item["timeout"]
                commands.append(new_item)
            new_group["hooks"] = commands
            entries.append(new_group)
        out_hooks[event] = entries

    document = {
        "_generated": BANNER_LINES,
        "hooks": out_hooks,
    }
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=False) + "\n"


def build(root):
    """Собирает отображение «относительный путь выхода → байты»."""
    manifest = Manifest(root)
    reader = Reader(root, manifest)
    produced = {}

    produced["AGENTS.md"] = render_agents_md(reader, manifest).encode("utf-8")

    for name in sorted(manifest.skills):
        package = ".claude/skills/%s" % name
        # Привязка правила пакетом не едет — предикат тот же, что у гейтов:
        # «SKILL.md является символьной ссылкой» (манифест, §ПРИВЯЗКИ ПРАВИЛ НЕ
        # ПРОЕЦИРУЮТСЯ). Отказ, а не пропуск: имя привязки в перечне `skills`
        # означает, что кто-то решил удвоить текст нормы, и решение это надо
        # отменить во ВХОДЕ, а не обойти молча в генераторе.
        if reader.islink("%s/SKILL.md" % package):
            raise GeneratorError(
                "манифест объявляет пакетом привязку правила: %s "
                "(SKILL.md — символьная ссылка). Проекция удвоила бы текст нормы, "
                "а вторая копия расходится с оригиналом молча" % package
            )
        files = reader.listdir(package)
        if not files:
            raise GeneratorError("пакет скила пуст: %s" % package)
        for relpath in files:
            tail = relpath[len(package) + 1 :]
            produced[".agents/skills/%s/%s" % (name, tail)] = reader.read(relpath)

    for relpath in reader.listdir(".claude/agents"):
        if not relpath.endswith(".md"):
            continue
        name = os.path.basename(relpath)[: -len(".md")]
        produced[".codex/agents/%s.toml" % name] = render_agent_toml(
            reader, relpath, manifest
        ).encode("utf-8")

    for relpath in reader.listdir(".claude/hooks"):
        # Переходники — только верхнеуровневым точкам входа. Вложенные ресурсы
        # хука (его собственный python, ведомости, пробы) переходника не имеют:
        # их зовёт канонический хук, а не среда.
        if os.path.dirname(relpath) != ".claude/hooks" or not relpath.endswith(".sh"):
            continue
        name = os.path.basename(relpath)
        produced[".codex/hooks/%s" % name] = render_hook_shim(name).encode("utf-8")

    produced[".codex/hooks.json"] = render_hooks_json(reader).encode("utf-8")

    declared = set(manifest.owned_outputs)
    got = set(produced)
    missing = sorted(declared - got)
    extra = sorted(got - declared)
    if missing:
        raise GeneratorError(
            "манифест объявляет выходы, которых генератор не производит: %s"
            % ", ".join(missing)
        )
    if extra:
        raise GeneratorError(
            "генератор производит выходы, не объявленные в манифесте: %s"
            % ", ".join(extra)
        )
    return manifest, reader, produced


def write(produced, out_root):
    for relpath in sorted(produced):
        target = os.path.join(out_root, relpath)
        parent = os.path.dirname(target)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(target, "wb") as handle:
            handle.write(produced[relpath])
        if relpath.endswith(".sh"):
            os.chmod(target, 0o755)


def main(argv=None):
    parser = argparse.ArgumentParser(description="генератор производного оснастки")
    parser.add_argument("--out", help="куда писать (по умолчанию — корень дерева)")
    parser.add_argument(
        "--list", action="store_true", help="перечислить владеемые выходы и выйти"
    )
    parser.add_argument("--quiet", action="store_true", help="без переписи")
    args = parser.parse_args(argv)

    root = repo_root()
    try:
        manifest, reader, produced = build(root)
    except GeneratorError as error:
        sys.stderr.write("генератор адаптера: %s\n" % error)
        return 2 if "манифест не найден" in str(error) else 1

    if args.list:
        for relpath in sorted(produced):
            sys.stdout.write("%s\n" % relpath)
        return 0

    out_root = args.out or root
    if args.out:
        shutil.rmtree(os.path.join(out_root, ".agents"), ignore_errors=True)
        shutil.rmtree(os.path.join(out_root, ".codex"), ignore_errors=True)
    write(produced, out_root)

    if not args.quiet:
        sys.stdout.write(
            "перепись: прочитано канонических входов — %d; "
            "порождено выходов — %d; пакетов скилов — %d; куда — %s\n"
            % (
                len(set(reader.read_paths)),
                len(produced),
                len(manifest.skills),
                os.path.relpath(out_root, root) if args.out else ".",
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
