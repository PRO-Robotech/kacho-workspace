"""cg.adapter — контракт адаптера оснастки.

Приёмка §10. Манифест `.claude/adapters.yaml` объявляет ВЛАДЕНИЕ: канонические
входы, точный набор владеемых выходов и полные пакеты скилов. Выходы
отслеживаются; конвейер порождает их во временный каталог и сравнивает
побайтно.

**Миров у семейства ДВА, и это свойство предмета, а не недосмотр фикстур.**
Приёмка спрашивает адаптер о двух разных вещах, и вторая не выразима словарём
первой:

    перепись КОНТРАКТА   manifest_path · manifest_owned_outputs ·
                         canonical_inputs · generated_coordinates ·
                         tracked_outputs · regenerated_outputs ·
                         second_regeneration_outputs · nested_assets ·
                         design_decision_outputs · foreign_runtime_packages

    перепись ПАКЕТОВ     manifest_skills · package_contents ·
                         matches_actual_tree

Правила разведены по `requires`, а предмет семейства — объединение обоих
словарей. Мир одной формы не несёт координат другой, поэтому ядро не находит
непрочитанных фактов ни в той, ни в другой: «прочитать в предмете всё» здесь
означает «прочитать всё, что мир ОБЪЯВИЛ».

**Владение решает МАНИФЕСТ, а не диск.** Это не оговорка, а несущее решение, и
проверяется оно на самом трудном месте корпуса: пакет, который живой `.gitignore`
объявляет сторонней установкой, мир кейса вправе объявить владеемым — и тогда он
владеем. Правило, потянувшееся бы за ответом в настоящее дерево, сделало бы
вердикт функцией МАШИНЫ, а не кейса: тот же мир на другом диске получал бы другой
ответ, и ни одна проба этого бы не показала. Поэтому все предикаты ниже читают
ровно мир и ничего кроме.

**Обратная сторона того же решения — §10 «чужой пакет».** Пакет вне манифеста не
является выходом: он не считается лишним и — несущее требование — НЕ МАСКИРУЕТ
расхождение владеемого. Поэтому чужой набор читается правилами лишнего выхода и
расхождения как ВЫЧИТАЕМОЕ, а не как отдельная находка: своей диагностики у него
нет, и выдумывать её значило бы объявить контракт, которого приёмка не объявляла.

**Ни один предикат не ищет литерала координаты.** Заглавная буква ловится
разбором сегментов пути, непереносимость — формой пути, а не подстрокой
`/home/...`: слепая подстановка по имени и есть тот класс, который здесь судят
(и который в основной копии дал 141 заглавную, 7 машинных путей и 15 импортов
каталога, которого нет ни на одном диске).

**Порядок правил назван, а не получен случайно**, но корректность на нём НЕ
держится: оси разведены так, что два правила не срабатывают на одном дефекте.
Заглавная буква судится только правилом регистра — правило каноничности входов
сравнивает имена, приведёнными к нижнему регистру, поэтому `.Claude/agents`
для него канонический вход, а не второй, «заодно» неканонический. Иначе один
дефект давал бы две находки, и какая из них станет вердиктом, решала бы строка
объявления.
"""

import re

from .. import outcome
from ..rules import Rule

FAMILY = "adapter"

# --- перепись контракта ------------------------------------------------------
MANIFEST_PATH = "manifest_path"
OWNED_OUTPUTS = "manifest_owned_outputs"
CANONICAL_INPUTS = "canonical_inputs"
GENERATED_COORDINATES = "generated_coordinates"
TRACKED_OUTPUTS = "tracked_outputs"
REGENERATED_OUTPUTS = "regenerated_outputs"
SECOND_REGENERATION = "second_regeneration_outputs"
NESTED_ASSETS = "nested_assets"
DESIGN_DECISION = "design_decision_outputs"
FOREIGN_PACKAGES = "foreign_runtime_packages"

# --- перепись пакетов --------------------------------------------------------
MANIFEST_SKILLS = "manifest_skills"
PACKAGE_CONTENTS = "package_contents"
MATCHES_ACTUAL_TREE = "matches_actual_tree"

CONTRACT_SUBJECT = (
    MANIFEST_PATH, OWNED_OUTPUTS, CANONICAL_INPUTS, GENERATED_COORDINATES,
    TRACKED_OUTPUTS, REGENERATED_OUTPUTS, SECOND_REGENERATION, NESTED_ASSETS,
    DESIGN_DECISION, FOREIGN_PACKAGES,
)
PACKAGE_SUBJECT = (MANIFEST_SKILLS, PACKAGE_CONTENTS, MATCHES_ACTUAL_TREE)

# §10: единственные канонические входы. Перечень закрыт — «вход вне набора»
# определяется членством, а не догадкой о том, что выглядит служебным.
REGISTERED_CANONICAL_INPUTS = frozenset((
    "CLAUDE.md",
    ".claude/adapters.yaml",
    ".claude/agents",
    ".claude/hooks",
    ".claude/rules",
    ".claude/skills",
    ".claude/settings.json",
))

REGISTERED_MANIFEST_PATH = ".claude/adapters.yaml"

SKILL_PACKAGE_ROOT = ".agents/skills/"
SKILL_ENTRY_SUFFIX = "/SKILL.md"

PRESENT = "present"
TRACKED_DESIGN = "tracked"

_WINDOWS_DRIVE = re.compile(r"^[A-Za-z]:[\\/]")


# --- разбор координаты -------------------------------------------------------
def _segments(coordinate):
    return str(coordinate).split("/")


def _dot_segment_has_uppercase(coordinate):
    """Служебный каталог обязан быть строчным.

    Судится СЕГМЕНТ, начинающийся с точки, а не подстрока: `AGENTS.md`,
    `CLAUDE.md`, `SKILL.md` заглавны законно и находкой не являются, а
    `.Claude` и `.Codex` — находка независимо от того, какое из двух имён
    попалось. Поиск по литералу закрыл бы ровно одно из них.
    """
    for segment in _segments(coordinate):
        if segment.startswith(".") and segment != segment.lower():
            return True
    return False


def _is_not_portable(coordinate):
    """Координата обязана быть относительной внутри дерева.

    Непереносимость определяется ФОРМОЙ пути, а не именем машины: абсолютный
    путь, домашний тильда-путь, буква диска, разделитель Windows и выход за
    корень деревом не адресуются ни на одной машине, кроме той, где записаны.
    """
    text = str(coordinate)
    if not text:
        return False
    if text.startswith("/") or text.startswith("~"):
        return True
    if _WINDOWS_DRIVE.match(text):
        return True
    if "\\" in text:
        return True
    return ".." in _segments(text)


def _skill_name(owned_coordinate):
    """Имя скила из координаты его `SKILL.md`; иначе None."""
    text = str(owned_coordinate)
    if not text.startswith(SKILL_PACKAGE_ROOT) or not text.endswith(SKILL_ENTRY_SUFFIX):
        return None
    name = text[len(SKILL_PACKAGE_ROOT):-len(SKILL_ENTRY_SUFFIX)]
    if not name or "/" in name:
        return None
    return name


def _package_prefix(name):
    return "%s%s/" % (SKILL_PACKAGE_ROOT, name)


def _package_is_complete(prefix, census):
    """Пакет полон, когда перепись несёт хотя бы один НАЛИЧНЫЙ вложенный ресурс.

    Отсутствие записи и запись со значением, отличным от «на месте», —
    одно и то же состояние: полного пакета нет. Различать их значило бы
    признать пакет целым по тому, что о нём кто-то упомянул.
    """
    for coordinate in census:
        if str(coordinate).startswith(prefix) and census[coordinate] == PRESENT:
            return True
    return False


# --- чужой пакет: вычитаемое, а не находка -----------------------------------
def _foreign_prefixes(world):
    """Чужие пакеты. Читаются, только если мир их объявил."""
    if not world.has(FOREIGN_PACKAGES):
        return ()
    return tuple(sorted(world.read_all(FOREIGN_PACKAGES)))


def _is_foreign(coordinate, foreign_prefixes):
    text = str(coordinate)
    for prefix in foreign_prefixes:
        if text == prefix or text.startswith(str(prefix) + "/"):
            return True
    return False


# --- предикаты: перепись контракта -------------------------------------------
def _all_declared_coordinates(world):
    """Все координаты, которые контракт называет: манифест, входы, выходы."""
    coordinates = [world.read(MANIFEST_PATH)]
    coordinates.extend(world.read_all(CANONICAL_INPUTS))
    coordinates.extend(world.read_all(GENERATED_COORDINATES))
    return coordinates


def _canonical_case_invalid(world):
    return any(
        _dot_segment_has_uppercase(coordinate)
        for coordinate in _all_declared_coordinates(world)
    )


def _path_not_portable(world):
    return any(
        _is_not_portable(coordinate)
        for coordinate in _all_declared_coordinates(world)
    )


def _input_not_canonical(world):
    """Вход вне закрытого набора §10.

    Имена сравниваются приведёнными к нижнему регистру НАМЕРЕННО: регистр —
    предмет соседнего правила, и путь, отличающийся от канонического только им,
    здесь находкой не является. Так один дефект остаётся одной находкой.
    """
    registered = {name.lower() for name in REGISTERED_CANONICAL_INPUTS}
    manifest_path = str(world.read(MANIFEST_PATH))
    if manifest_path.lower() not in registered:
        return True
    return any(
        str(declared).lower() not in registered
        for declared in world.read_all(CANONICAL_INPUTS)
    )


def _design_outputs_not_tracked(world):
    return world.read(DESIGN_DECISION) != TRACKED_DESIGN


def _owned_output_extra(world):
    """Отслеживаемый выход, которого манифест не называет.

    Чужой пакет вычитается: §10 прямо говорит, что он не является выходом и
    лишним не считается.
    """
    owned = world.read_all(OWNED_OUTPUTS)
    tracked = world.read_all(TRACKED_OUTPUTS)
    foreign = _foreign_prefixes(world)
    return any(
        coordinate not in owned and not _is_foreign(coordinate, foreign)
        for coordinate in tracked
    )


def _owned_output_missing(world):
    """Манифест называет выход, которого в отслеживаемом дереве нет."""
    owned = world.read_all(OWNED_OUTPUTS)
    tracked = world.read_all(TRACKED_OUTPUTS)
    return any(coordinate not in tracked for coordinate in owned)


def _nested_asset_missing(world):
    """Пакет скила, объявленного манифестом, неполон.

    Скилы выводятся из владеемых выходов по координате `SKILL.md`, а не из
    отдельного списка: второй список был бы вторым местом об одном предмете.
    """
    owned = world.read_all(OWNED_OUTPUTS)
    census = world.read_all(NESTED_ASSETS)
    for coordinate in sorted(owned):
        name = _skill_name(coordinate)
        if name is None:
            continue
        if not _package_is_complete(_package_prefix(name), census):
            return True
    return False


def _derived_drift(world):
    """Отслеживаемый байт разошёлся с регенерацией.

    Сравниваются только ВЛАДЕЕМЫЕ координаты, присутствующие на обеих сторонах:
    отсутствие координаты — предмет правил лишнего и недостающего выхода, и
    объявлять его расхождением значило бы дать одному дефекту две находки.

    Чужой пакет вычитается — §10 требует, чтобы он расхождение НЕ МАСКИРОВАЛ:
    его наличие не отменяет сравнения владеемого.
    """
    owned = world.read_all(OWNED_OUTPUTS)
    tracked = world.read_all(TRACKED_OUTPUTS)
    regenerated = world.read_all(REGENERATED_OUTPUTS)
    foreign = _foreign_prefixes(world)
    for coordinate in sorted(owned):
        if _is_foreign(coordinate, foreign):
            continue
        if coordinate not in tracked or coordinate not in regenerated:
            continue
        if tracked[coordinate] != regenerated[coordinate]:
            return True
    return False


def _nondeterministic(world):
    """Два прогона регенерации при тех же входах дали разное."""
    first = world.read_all(REGENERATED_OUTPUTS)
    second = world.read_all(SECOND_REGENERATION)
    return first != second


# --- предикат: перепись пакетов ----------------------------------------------
def _package_census_incomplete(world):
    """Полный пакет каждого манифестного скила и согласие переписи с деревом."""
    skills = world.read_all(MANIFEST_SKILLS)
    census = world.read_all(PACKAGE_CONTENTS)
    if not world.read(MATCHES_ACTUAL_TREE):
        return True
    return any(
        not _package_is_complete(_package_prefix(name), census)
        for name in sorted(skills)
    )


RULES = [
    Rule(
        rule_id="adapter.canonical-case",
        diagnostic="CG_ADAPTER_CANONICAL_CASE_INVALID",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(MANIFEST_PATH, CANONICAL_INPUTS, GENERATED_COORDINATES),
        predicate=_canonical_case_invalid,
        why="§10 канонические координаты записаны строчными; uppercase-вариант "
            "служебного каталога (.Claude, .Codex) — RED",
    ),
    Rule(
        rule_id="adapter.path-not-portable",
        diagnostic="CG_ADAPTER_PATH_NOT_PORTABLE",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(MANIFEST_PATH, CANONICAL_INPUTS, GENERATED_COORDINATES),
        predicate=_path_not_portable,
        why="§10 absolute path в generated artifact — RED; координата обязана "
            "адресоваться деревом, а не машиной",
    ),
    Rule(
        rule_id="adapter.input-not-canonical",
        diagnostic="CG_ADAPTER_INPUT_NOT_CANONICAL",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(MANIFEST_PATH, CANONICAL_INPUTS),
        predicate=_input_not_canonical,
        why="§10 единственные canonical inputs — root CLAUDE.md и tracked "
            ".claude/{adapters.yaml,agents,hooks,rules,skills,settings.json}",
    ),
    Rule(
        rule_id="adapter.design-outputs-untracked",
        diagnostic="CG_ADAPTER_OUTPUTS_MUST_BE_TRACKED",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(DESIGN_DECISION,),
        predicate=_design_outputs_not_tracked,
        why="§10 design «outputs только untracked/runtime» запрещён: generated "
            "contract обязан быть tracked",
    ),
    Rule(
        rule_id="adapter.owned-output-extra",
        diagnostic="CG_ADAPTER_OWNED_OUTPUT_EXTRA",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(OWNED_OUTPUTS, TRACKED_OUTPUTS),
        predicate=_owned_output_extra,
        why="§10 точный adapter-owned set; отслеживаемый выход в владеемом "
            "пространстве вне манифеста — RED, чужой пакет — не выход",
    ),
    Rule(
        rule_id="adapter.owned-output-missing",
        diagnostic="CG_ADAPTER_OWNED_OUTPUT_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(OWNED_OUTPUTS, TRACKED_OUTPUTS),
        predicate=_owned_output_missing,
        why="§10 набор сверяется в обе стороны: строка без файла — такая же "
            "находка, как файл без строки",
    ),
    Rule(
        rule_id="adapter.nested-asset-missing",
        diagnostic="CG_ADAPTER_NESTED_ASSET_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(OWNED_OUTPUTS, NESTED_ASSETS),
        predicate=_nested_asset_missing,
        why="§10 полные packages .agents/skills/<name>/** для каждого manifest "
            "skill, включая references, assets и scripts",
    ),
    Rule(
        rule_id="adapter.derived-drift",
        diagnostic="CGA_DERIVED_DRIFT",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(OWNED_OUTPUTS, TRACKED_OUTPUTS, REGENERATED_OUTPUTS),
        predicate=_derived_drift,
        why="§10 CI порождает выходы во временный каталог и сравнивает побайтно "
            "с tracked tree; чужой пакет расхождение не маскирует",
    ),
    Rule(
        rule_id="adapter.nondeterministic",
        diagnostic="CG_ADAPTER_NONDETERMINISTIC",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_SUBJECT,
        requires=(REGENERATED_OUTPUTS, SECOND_REGENERATION),
        predicate=_nondeterministic,
        why="§10 nondeterminism — RED: два temp-прогона при тех же входах "
            "обязаны совпасть",
    ),
    Rule(
        rule_id="adapter.package-census-incomplete",
        diagnostic="CG_ADAPTER_NESTED_ASSET_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=PACKAGE_SUBJECT,
        requires=(MANIFEST_SKILLS, PACKAGE_CONTENTS, MATCHES_ACTUAL_TREE),
        predicate=_package_census_incomplete,
        why="§10 текущие разновидности вложенного (audit-round.workflow.js, "
            "EXAMPLES, Obsidian references) сверяются с регенерацией по "
            "фактическому дереву",
    ),
]
