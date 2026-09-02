#!/usr/bin/env python3
"""Предикаты набора adapter-gate. Одна реализация на все проверки набора.

    python3 scripts/adapter-gate/probe.py <предикат>

ПОЧЕМУ ОДИН МОДУЛЬ, А НЕ СЕМЬ СКРИПТОВ. Все семь предикатов задают вопросы об
ОДНОМ предмете — соответствии производного каноническим входам, — и все семь
нуждаются в регенерации во временный каталог. Семь копий этой регенерации
разошлись бы молча: это тот же класс, что копия нормативной карты. Проверки
остаются семью отдельными файлами (у каждой свой вердикт и свой объём
осмотренного), а вычисление у них одно.

ИСХОДЫ — ТРИ, и третий не засчитывается в успех:

    0 — осмотрено N, находок 0
    1 — находка
    2 — БЕЗ ПРЕДМЕТА: сверять не с чем (нет манифеста, дерево не под git)

КОРЕНЬ ПЕРЕОПРЕДЕЛЯЕТСЯ `ADAPTER_GATE_ROOT` — этим пользуется ТОЛЬКО inject.sh,
чтобы прогнать предикат по временному дереву с внесённым дефектом и не тронуть
рабочее.
"""

import os
import shutil
import subprocess
import sys
import tempfile

import yaml

SECOND_ENV_DIR = ".codex"


def repo_root():
    override = os.environ.get("ADAPTER_GATE_ROOT")
    if override:
        return os.path.abspath(override)
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


class Void(Exception):
    """Предмета нет: сверять не с чем. Это НЕ успех и НЕ находка."""


def load_manifest(root):
    path = os.path.join(root, ".claude", "adapters.yaml")
    if not os.path.exists(path):
        raise Void("манифеста .claude/adapters.yaml нет — владение не объявлено")
    with open(path, "r", encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)
    if not isinstance(doc, dict):
        raise Void("манифест не разбирается в отображение")
    return doc


def tracked(root):
    """Отслеживаемые пути — из индекса git, а не с диска.

    Посторонний каталог рядом (сборочный мусор, чужая установка, состояние
    хуков) иначе влиял бы на вердикт, и «лишний выход» стало бы невозможно
    отличить от «файл просто лежит».
    """
    if not os.path.isdir(os.path.join(root, ".git")) and not os.path.isfile(
        os.path.join(root, ".git")
    ):
        raise Void("дерево не под git — отслеживаемый набор не определён")
    # `core.quotepath=false` — не косметика. По умолчанию git ЭКРАНИРУЕТ путь с
    # не-ASCII именем и оборачивает его в кавычки: `".codex/agents/\320\273…"`.
    # Такой путь не начинается с владеемого пространства, поэтому лишний выход с
    # не-ASCII именем становился для предиката НЕВИДИМ — то есть маской ровно на
    # том, что проверка обязана ловить. Найдено инъекцией, не чтением.
    out = subprocess.run(
        [
            "git",
            "-C",
            root,
            "-c",
            "core.quotepath=false",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
        ],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise Void("git ls-files отказал: %s" % out.stderr.strip()[:200])
    return sorted(p for p in out.stdout.split("\n") if p)


def regenerate(root, destination):
    """Регенерация во временный каталог ИЗ ЭТОГО ЖЕ дерева.

    Зовётся именно копия генератора из проверяемого дерева, а не из рабочего:
    иначе инъекция в генератор осталась бы незамеченной — гейт проверял бы
    чужой, исправный экземпляр.
    """
    generator = os.path.join(root, "scripts", "adapter", "generate.py")
    if not os.path.exists(generator):
        raise Void("генератора scripts/adapter/generate.py нет — регенерировать нечем")
    out = subprocess.run(
        [sys.executable, generator, "--out", destination, "--quiet"],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        return None, (out.stderr or out.stdout).strip()
    produced = {}
    for dirpath, dirnames, filenames in os.walk(destination):
        dirnames[:] = sorted(dirnames)
        for name in sorted(filenames):
            absolute = os.path.join(dirpath, name)
            rel = os.path.relpath(absolute, destination).replace(os.sep, "/")
            with open(absolute, "rb") as handle:
                produced[rel] = handle.read()
    return produced, None


def owned_namespace_members(manifest, paths):
    """Отслеживаемые пути внутри пространств, за которые отвечает адаптер.

    Пакеты скилов — ПОИМЁННО: пакет внутри `.agents/skills/`, которого нет среди
    `skills`, принадлежит другой установке. Он не выход адаптера, и — несущее
    требование — он НЕ МАСКИРУЕТ расхождение владеемого: расхождение считается
    по владеемым путям, а чужие в это множество не входят вовсе.
    """
    namespaces = list(manifest.get("owned_namespaces") or [])
    skills = list(manifest.get("skills") or [])
    members = []
    for path in paths:
        hit = any(
            path == ns or path.startswith(ns.rstrip("/") + "/") for ns in namespaces
        )
        if not hit:
            hit = any(path.startswith(".agents/skills/%s/" % s) for s in skills)
        if hit:
            members.append(path)
    return sorted(members)


# ─── предикаты ────────────────────────────────────────────────────────────────


def predicate_manifest_tree(root):
    """Точный набор манифеста совпадает с отслеживаемым деревом — в обе стороны."""
    manifest = load_manifest(root)
    declared = set(manifest.get("owned_outputs") or [])
    if not declared:
        raise Void("owned_outputs пуст — сверять не с чем")
    present = set(owned_namespace_members(manifest, tracked(root)))

    missing = sorted(declared - present)
    extra = sorted(present - declared)
    lines = []
    for path in missing:
        lines.append("объявлен в манифесте, в дереве не отслеживается: %s" % path)
    for path in extra:
        lines.append("отслеживается в владеемом пространстве, но не объявлен: %s" % path)
    return len(declared), lines


def predicate_derived_drift(root):
    """Отслеживаемое производное побайтово равно регенерации."""
    manifest = load_manifest(root)
    declared = sorted(manifest.get("owned_outputs") or [])
    if not declared:
        raise Void("owned_outputs пуст — сравнивать нечего")

    workdir = tempfile.mkdtemp(prefix="adapter-gate-")
    try:
        produced, error = regenerate(root, workdir)
        if produced is None:
            return 0, ["генератор отказал: %s" % error]
        lines = []
        for path in declared:
            target = os.path.join(root, path)
            if path not in produced:
                lines.append("регенерация не произвела объявленный выход: %s" % path)
                continue
            if not os.path.exists(target):
                lines.append("объявленного выхода нет в дереве: %s" % path)
                continue
            with open(target, "rb") as handle:
                current = handle.read()
            if current != produced[path]:
                lines.append(
                    "производное разошлось с регенерацией: %s (в дереве %d Б, "
                    "регенерация %d Б)" % (path, len(current), len(produced[path]))
                )
        for path in sorted(set(produced) - set(declared)):
            lines.append("регенерация произвела необъявленный выход: %s" % path)
        return len(declared), lines
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def predicate_determinism(root):
    """Две регенерации из тех же входов дают побайтово один результат."""
    first_dir = tempfile.mkdtemp(prefix="adapter-gate-a-")
    second_dir = tempfile.mkdtemp(prefix="adapter-gate-b-")
    try:
        first, error = regenerate(root, first_dir)
        if first is None:
            return 0, ["генератор отказал на первом прогоне: %s" % error]
        second, error = regenerate(root, second_dir)
        if second is None:
            return 0, ["генератор отказал на втором прогоне: %s" % error]

        lines = []
        for path in sorted(set(first) | set(second)):
            if path not in first:
                lines.append("второй прогон произвёл лишний выход: %s" % path)
            elif path not in second:
                lines.append("второй прогон не произвёл выход: %s" % path)
            elif first[path] != second[path]:
                lines.append("два прогона разошлись на одном входе: %s" % path)
        return len(first), lines
    finally:
        shutil.rmtree(first_dir, ignore_errors=True)
        shutil.rmtree(second_dir, ignore_errors=True)


def predicate_canonical_case(root):
    """Ни один порождённый файл не содержит ЗАГЛАВНОЙ формы имени второй среды.

    Предмет измерен, а не предположен: в порождённых вручную файлах, лежавших в
    дереве до заведения генератора, было 141 вхождение заглавной формы в 25
    файлах. Она рождается слепой подстановкой по имени и не является опечаткой,
    поэтому ловится предикатом, а не вычиткой.
    """
    manifest = load_manifest(root)
    declared = sorted(manifest.get("owned_outputs") or [])
    if not declared:
        raise Void("owned_outputs пуст — читать нечего")

    wrong = "." + SECOND_ENV_DIR[1].upper() + SECOND_ENV_DIR[2:]
    lines = []
    read = 0
    for path in declared:
        target = os.path.join(root, path)
        if not os.path.exists(target):
            continue
        read += 1
        with open(target, "rb") as handle:
            body = handle.read().decode("utf-8", "replace")
        count = body.count(wrong)
        if count:
            lines.append("заглавная форма %r в порождённом: %s (%d)" % (wrong, path, count))
    if read == 0:
        raise Void("ни одного объявленного выхода нет на диске — читать нечего")
    return read, lines


def predicate_portable(root):
    """В порождённом нет абсолютного пути, ВНЕСЁННОГО генератором.

    Различение несущее, а не педантское. Порождённый текст наследует прозу
    канонического входа дословно, и в этой прозе законно встречается абсолютный
    путь — как ЦИТАТА наблюдения, а не как координата, по которой пойдут.
    Запрет на «любой абсолютный путь» краснел бы на такой цитате, то есть на
    верном дереве, — а гейт, краснеющий на верном, отключают первым.

    Поэтому находкой является путь, которого НЕТ ни в одном каноническом входе:
    его ввёл генератор, и он не переносится ни на другую машину, ни в другой
    клон, оставаясь на вид рабочим.
    """
    import re

    manifest = load_manifest(root)
    declared = sorted(manifest.get("owned_outputs") or [])
    inputs = list(manifest.get("canonical_inputs") or [])
    if not declared:
        raise Void("owned_outputs пуст — читать нечего")

    haystack = []
    for entry in inputs:
        full = os.path.join(root, entry)
        if os.path.isfile(full):
            files = [full]
        elif os.path.isdir(full):
            files = []
            for dirpath, dirnames, filenames in os.walk(full):
                dirnames[:] = [d for d in dirnames if d != "__pycache__"]
                files.extend(os.path.join(dirpath, n) for n in filenames)
        else:
            continue
        for path in files:
            try:
                with open(path, "rb") as handle:
                    haystack.append(handle.read().decode("utf-8", "replace"))
            except OSError:
                continue
    inherited = "\n".join(haystack)

    absolute = re.compile(r"(?<![\w.-])/(?:home|Users|root|tmp|var)/[\w./-]+")
    lines = []
    read = 0
    for rel in declared:
        target = os.path.join(root, rel)
        if not os.path.exists(target):
            continue
        read += 1
        with open(target, "rb") as handle:
            body = handle.read().decode("utf-8", "replace")
        for hit in sorted(set(absolute.findall(body))):
            if hit in inherited:
                continue  # цитата из канонического входа, не координата генератора
            lines.append("внесённый генератором абсолютный путь: %s → %s" % (rel, hit))
    if read == 0:
        raise Void("ни одного объявленного выхода нет на диске — читать нечего")
    return read, lines


def predicate_canonical_inputs(root):
    """Генератор читает ТОЛЬКО канонические входы, и они все существуют.

    Проверяется ИСХОДОМ, а не чтением исходника генератора: у него есть отказ по
    неканоническому пути, и подставленный неканонический вход обязан этот отказ
    вызвать. Чтение исходника ловило бы форму — комментарий про запрет прошёл бы
    за сам запрет.
    """
    manifest = load_manifest(root)
    inputs = list(manifest.get("canonical_inputs") or [])
    if not inputs:
        raise Void("canonical_inputs пуст — проверять нечего")

    lines = []
    for entry in inputs:
        if os.path.isabs(entry):
            lines.append("канонический вход задан абсолютным путём: %s" % entry)
        if not os.path.exists(os.path.join(root, entry)):
            lines.append("объявленного канонического входа нет в дереве: %s" % entry)

    # Поведенческая половина: генератор обязан ОТКАЗАТЬ на неканоническом входе.
    generator = os.path.join(root, "scripts", "adapter", "generate.py")
    if not os.path.exists(generator):
        raise Void("генератора нет — поведение проверить не на чем")
    # Подаётся СУЩЕСТВУЮЩИЙ, но неканонический путь — сам генератор.
    #
    # Это не педантизм: с несуществующим путём проба была ЛОЖНО-ЗЕЛЁНОЙ. Сняв
    # проверку каноничности, генератор доходил до проверки существования, падал
    # на ней тем же типом ошибки — и предикат читал отказ «файла нет» как отказ
    # «вход неканоничен». Два разных отказа неотличимы, если вход не существует.
    # Найдено инъекцией: снятая проверка каноничности не краснела.
    noncanonical = "scripts/adapter/generate.py"
    probe = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys;sys.path.insert(0,%r);import generate as g;"
            "m=g.Manifest(%r);r=g.Reader(%r,m);\n"
            # Токены НЕ ПЕРЕСЕКАЮТСЯ как подстроки — и это не стиль. Первая
            # редакция печатала «ОТКАЗАЛ» и «НЕ ОТКАЗАЛ», а проверяла вхождение
            # подстроки: «НЕ ОТКАЗАЛ» СОДЕРЖИТ «ОТКАЗАЛ», поэтому снятая защита
            # читалась как сработавшая. Предикат совпадал с собственным
            # отрицанием. Найдено инъекцией, не чтением.
            "try:\n r.read(%r)\n"
            " print('ПРОПУСТИЛ')\n"
            "except g.GeneratorError as e:\n"
            " print('ОТВЕРГ' if 'неканонический' in str(e) else 'ЧУЖОЙ-ОТКАЗ: %%s' %% e)\n"
            % (os.path.dirname(generator), root, root, noncanonical),
        ],
        capture_output=True,
        text=True,
    )
    if probe.stdout.strip() != "ОТВЕРГ":
        lines.append(
            "генератор НЕ отказывает на неканоническом входе (ответ: %r)"
            % ((probe.stdout or probe.stderr).strip()[:200],)
        )
    return len(inputs), lines


def predicate_skills_roster(root):
    """Перечень пакетов манифеста совпадает с отслеживаемыми скилами дерева.

    В обе стороны: имя без директории и директория без имени — обе находки.
    Совпадение ЧИСЛА ничего не доказывает: множества равной мощности бывают
    разными, и именно так перечень расходится с деревом незаметно.
    """
    manifest = load_manifest(root)
    declared = set(manifest.get("skills") or [])
    if not declared:
        raise Void("skills пуст — сверять не с чем")

    present = set()
    for path in tracked(root):
        if path.startswith(".claude/skills/") and path.endswith("/SKILL.md"):
            present.add(path.split("/")[2])
    if not present:
        raise Void("в дереве нет ни одного .claude/skills/*/SKILL.md")

    lines = []
    for name in sorted(declared - present):
        lines.append("манифест объявляет пакет, которого нет в оснастке: %s" % name)
    for name in sorted(present - declared):
        lines.append("скил оснастки не объявлен пакетом манифеста: %s" % name)
    return len(declared | present), lines


PREDICATES = {
    "manifest-tree": (predicate_manifest_tree, "выходов манифеста"),
    "derived-drift": (predicate_derived_drift, "выходов сверено"),
    "determinism": (predicate_determinism, "выходов в прогоне"),
    "canonical-case": (predicate_canonical_case, "порождённых прочитано"),
    "portable": (predicate_portable, "порождённых прочитано"),
    "canonical-inputs": (predicate_canonical_inputs, "канонических входов"),
    "skills-roster": (predicate_skills_roster, "имён в объединении"),
}


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) != 1 or argv[0] not in PREDICATES:
        sys.stderr.write("нужен один предикат: %s\n" % ", ".join(sorted(PREDICATES)))
        return 2
    function, unit = PREDICATES[argv[0]]
    try:
        examined, findings = function(repo_root())
    except Void as reason:
        sys.stdout.write("VOID %s\n" % reason)
        return 2
    for line in findings:
        sys.stdout.write("  %s\n" % line)
    sys.stdout.write("CENSUS %d %s\n" % (examined, unit))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
