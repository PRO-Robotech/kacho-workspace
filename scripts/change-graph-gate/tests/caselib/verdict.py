"""Словарь исходов pre-RED driver.

Разделение несущее: у holder verdict ровно три категории (GREEN / RED /
NOT_EXECUTED) с кодами 0 / 10 / 20. Собственная поломка harness'а holder
verdict НЕ производит вовсе — она выходит кодом 40 и категорией HARNESS.

Приёмка §6 требует, чтобы command-not-found, посторонний crash драйвера и
infrastructure failure НЕ подменяли честный `CASE_CAPABILITY_MISSING`: они не
открывают RED_PROVEN. Отдельный код возврата — механизм этого требования, а не
украшение: код 40 не может быть прочитан как holder verdict ни одним
потребителем, потому что не входит в тройку holder-кодов.

Приёмка §12 требует, чтобы fixture, меняющая больше одного факта, была invalid
и НЕ давала holder verdict. Код 40 — ровно это состояние.
"""

SEPARATOR = "·"

CATEGORY_GREEN = "GREEN"
CATEGORY_RED = "RED"
CATEGORY_NOT_EXECUTED = "NOT_EXECUTED"
CATEGORY_HARNESS = "HARNESS"

EXIT_GREEN = 0
EXIT_RED = 10
EXIT_NOT_EXECUTED = 20
EXIT_HARNESS = 40

# Коды, которые вообще могут нести holder verdict. Всё прочее — не verdict.
HOLDER_EXIT_CODES = {
    CATEGORY_GREEN: EXIT_GREEN,
    CATEGORY_RED: EXIT_RED,
    CATEGORY_NOT_EXECUTED: EXIT_NOT_EXECUTED,
}

# --- holder-диагностики -----------------------------------------------------
CASE_CAPABILITY_MISSING = "CASE_CAPABILITY_MISSING"
CASE_ASSERTION_MATCHED = "CASE_ASSERTION_MATCHED"
CASE_ASSERTION_CATEGORY_MISMATCH = "CASE_ASSERTION_CATEGORY_MISMATCH"
CASE_ASSERTION_DIAGNOSTIC_MISMATCH = "CASE_ASSERTION_DIAGNOSTIC_MISMATCH"
CASE_ASSERTION_EXIT_MISMATCH = "CASE_ASSERTION_EXIT_MISMATCH"

# --- harness-диагностики (verdict НЕ производится) --------------------------
HARNESS_ACCEPTANCE_UNREADABLE = "HARNESS_ACCEPTANCE_UNREADABLE"
HARNESS_CASE_UNKNOWN = "HARNESS_CASE_UNKNOWN"
HARNESS_FIXTURE_MISSING = "HARNESS_FIXTURE_MISSING"
HARNESS_FIXTURE_MALFORMED = "HARNESS_FIXTURE_MALFORMED"
HARNESS_FIXTURE_SPEC_MISMATCH = "HARNESS_FIXTURE_SPEC_MISMATCH"
HARNESS_PLANNED_HOLDER_MISSING = "HARNESS_PLANNED_HOLDER_MISSING"
HARNESS_TWIN_MISSING = "HARNESS_TWIN_MISSING"
HARNESS_TWIN_DELTA_NOT_SINGLE = "HARNESS_TWIN_DELTA_NOT_SINGLE"
HARNESS_TWIN_DELTA_UNDECLARED = "HARNESS_TWIN_DELTA_UNDECLARED"
HARNESS_STUB_NOT_PERMITTED = "HARNESS_STUB_NOT_PERMITTED"
HARNESS_SUT_PROBE_FAILED = "HARNESS_SUT_PROBE_FAILED"
HARNESS_SUT_OUTPUT_UNPARSEABLE = "HARNESS_SUT_OUTPUT_UNPARSEABLE"
HARNESS_INTERNAL = "HARNESS_INTERNAL"


class Triple:
    """Тройка category + diagnostic + exit — единица сравнения драйвера."""

    __slots__ = ("category", "diagnostic", "exit_code")

    def __init__(self, category, diagnostic, exit_code):
        self.category = category
        self.diagnostic = diagnostic
        self.exit_code = int(exit_code)

    def render(self):
        return "%s %s %s %s exit %d" % (
            self.category, SEPARATOR, self.diagnostic, SEPARATOR, self.exit_code,
        )

    def as_dict(self):
        return {
            "category": self.category,
            "diagnostic": self.diagnostic,
            "exit": self.exit_code,
        }

    def __eq__(self, other):
        return (
            isinstance(other, Triple)
            and self.category == other.category
            and self.diagnostic == other.diagnostic
            and self.exit_code == other.exit_code
        )

    def __repr__(self):
        return "Triple(%s)" % self.render()


def holder(category, diagnostic):
    """Holder verdict: код выводится ИЗ категории, а не задаётся отдельно.

    Это устраняет класс «категория говорит одно, код возврата другое»: у
    holder verdict соответствие фиксированное и не может разъехаться.
    """
    if category not in HOLDER_EXIT_CODES:
        raise ValueError("не holder-категория: %r" % (category,))
    return Triple(category, diagnostic, HOLDER_EXIT_CODES[category])


def harness(diagnostic):
    """Поломка самого harness'а. Holder verdict не производится."""
    return Triple(CATEGORY_HARNESS, diagnostic, EXIT_HARNESS)


def is_holder_verdict(triple):
    return triple.category in HOLDER_EXIT_CODES
