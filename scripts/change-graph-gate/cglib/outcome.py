"""Словарь исходов испытуемого — и шов между ЕГО отказом и отказом ПРЕДМЕТА.

Различение несущее, и оно устроено так, что перепутать стороны нельзя
by construction, а не по договорённости.

**Вердикт о предмете** — тройка `КАТЕГОРИЯ · ДИАГНОСТИКА · exit N` на stdout,
последней строкой, с кодом возврата, выведенным ИЗ категории. Категорий ровно
три (GREEN / RED / NOT_EXECUTED), кодов — 0 / 10 / 20. Соответствие
фиксированное: «категория говорит одно, код возврата другое» здесь невыразимо.

**Собственный отказ** испытуемого вердиктом не является и вердиктом стать не
может: он не печатает на stdout НИ ОДНОЙ строки, пишет разбор на stderr и
выходит кодом 40. Драйвер, не найдя на stdout тройки, отвечает
`HARNESS · HARNESS_SUT_OUTPUT_UNPARSEABLE · exit 40` — то есть исходом, который
не входит в тройку holder-кодов и потому не читается как вердикт ни одним
потребителем. «Не знаю» никогда не выдаётся за «нет».

Диагностики собственного отказа несут префикс `CG_SELF_`, а диагностики о
предмете — `CG_`. Пересечься они не могут: приёмка не объявляет ни одной
диагностики предмета, начинающейся с `CG_SELF_`, и это проверяется пробой.
"""

SEPARATOR = "·"

CATEGORY_GREEN = "GREEN"
CATEGORY_RED = "RED"
CATEGORY_NOT_EXECUTED = "NOT_EXECUTED"

SUBJECT_EXIT_CODES = {
    CATEGORY_GREEN: 0,
    CATEGORY_RED: 10,
    CATEGORY_NOT_EXECUTED: 20,
}

# Код собственного отказа. Он намеренно совпадает с harness-кодом драйвера:
# оба означают «вердикта нет», и совпадение делает это читаемым в одну строку.
SELF_FAILURE_EXIT = 40

SELF_DIAGNOSTIC_PREFIX = "CG_SELF_"

DIAGNOSTIC_OK = "CG_OK"

# --- диагностики собственного отказа ----------------------------------------
SELF_USAGE = "CG_SELF_USAGE"
SELF_WORLD_UNREADABLE = "CG_SELF_WORLD_UNREADABLE"
SELF_WORLD_MALFORMED = "CG_SELF_WORLD_MALFORMED"
SELF_CASE_ID_UNPARSEABLE = "CG_SELF_CASE_ID_UNPARSEABLE"
SELF_FAMILY_UNDECLARED = "CG_SELF_FAMILY_UNDECLARED"
SELF_REGISTRY_BROKEN = "CG_SELF_REGISTRY_BROKEN"
SELF_WORLD_NOT_JUDGED = "CG_SELF_WORLD_NOT_JUDGED"
SELF_WORLD_FACT_UNREAD = "CG_SELF_WORLD_FACT_UNREAD"
SELF_RULE_READ_OUTSIDE_SUBJECT = "CG_SELF_RULE_READ_OUTSIDE_SUBJECT"
SELF_RULE_CRASHED = "CG_SELF_RULE_CRASHED"
SELF_APPROVAL_ROLE_UNRESOLVED = "CG_SELF_APPROVAL_ROLE_UNRESOLVED"
SELF_INTERNAL = "CG_SELF_INTERNAL"


class Outcome:
    """Вердикт о предмете. Код возврата выводится из категории, а не задаётся."""

    __slots__ = ("category", "diagnostic")

    def __init__(self, category, diagnostic):
        if category not in SUBJECT_EXIT_CODES:
            raise ValueError("не категория вердикта: %r" % (category,))
        if str(diagnostic).startswith(SELF_DIAGNOSTIC_PREFIX):
            # Диагностика собственного отказа не вправе доехать до предмета:
            # иначе испытуемый объявил бы свою поломку свойством мира.
            raise ValueError(
                "диагностика собственного отказа не может быть вердиктом: %r"
                % (diagnostic,)
            )
        self.category = category
        self.diagnostic = diagnostic

    @property
    def exit_code(self):
        return SUBJECT_EXIT_CODES[self.category]

    def render(self):
        return "%s %s %s %s exit %d" % (
            self.category, SEPARATOR, self.diagnostic, SEPARATOR, self.exit_code,
        )

    def __eq__(self, other):
        return (
            isinstance(other, Outcome)
            and self.category == other.category
            and self.diagnostic == other.diagnostic
        )

    def __repr__(self):
        return "Outcome(%s)" % self.render()


def green():
    return Outcome(CATEGORY_GREEN, DIAGNOSTIC_OK)


def red(diagnostic):
    return Outcome(CATEGORY_RED, diagnostic)


def not_executed(diagnostic):
    return Outcome(CATEGORY_NOT_EXECUTED, diagnostic)


class SelfFailure(Exception):
    """Испытуемый не может ответить о предмете. Это НЕ вердикт о предмете.

    Поднимается там, где отвечать было бы враньём: мир не читается, мир не
    описывает предмет этого семейства, ни одно правило к миру неприменимо, факт
    мира внутри предмета семейства остался непрочитанным, правило упало.

    Ни один из этих случаев не имеет права стать GREEN: «правил не нашлось» и
    «нарушений не найдено» — разные вещи, и вторая произносится только после
    первой.
    """

    def __init__(self, diagnostic, detail):
        if not str(diagnostic).startswith(SELF_DIAGNOSTIC_PREFIX):
            raise ValueError(
                "диагностика собственного отказа обязана нести префикс %r: %r"
                % (SELF_DIAGNOSTIC_PREFIX, diagnostic)
            )
        super(SelfFailure, self).__init__("%s: %s" % (diagnostic, detail))
        self.diagnostic = diagnostic
        self.detail = detail
