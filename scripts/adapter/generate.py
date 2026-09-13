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


def render_agents_md(reader, manifest):
    """Корневой указатель для сред, читающих AGENTS.md.

    Тело — канонический CLAUDE.md ДОСЛОВНО. Именно дословно, а не «адаптировано»:
    подстановка имени каталога оснастки запрещена (см. шапку модуля), а
    пересказ дал бы второе место об одном предмете, которое разойдётся молча.
    """
    body = reader.read_text("CLAUDE.md")

    agent_files = [
        p for p in reader.listdir(".claude/agents") if p.endswith(".md")
    ]
    skill_names = sorted(manifest.skills)

    lines = ["<!--"]
    lines.extend("  %s" % line for line in BANNER_LINES)
    lines.append("-->")
    lines.append("")
    lines.append(body.rstrip("\n"))
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


def render_agent_toml(reader, relpath):
    text = reader.read_text(relpath)
    head, body = split_frontmatter(text, relpath)
    name = str(head.get("name") or "").strip()
    description = " ".join(str(head.get("description") or "").split())
    if not name:
        raise GeneratorError("у агента нет имени: %s" % relpath)

    banner = "\n".join("# %s" % line for line in BANNER_LINES)
    return "%s\nname = %s\ndescription = %s\ndeveloper_instructions = %s\n" % (
        banner,
        toml_basic_string(name),
        toml_basic_string(description),
        toml_multiline_string(body.lstrip("\n")),
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
            reader, relpath
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
