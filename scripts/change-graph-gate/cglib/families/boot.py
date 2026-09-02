"""cg.boot — единственность bootstrap-исключения.

Приёмка §1: SDD-1 — единственный bootstrap change, долговечно ограниченный
парой «Issue #480 + этот acceptance»; собственного package он не фабрикует.
Приёмка §4: acceptance subject всегда сохраняет статическую форму DRAFT, а с
момента cutover bootstrap exception недействителен.

Из этого следует ОДНО правило, а не пять: исключение выдаётся не «изменению
вообще», а ровно этому изменению в ровно этих обстоятельствах. Поэтому предикат
— равенство ЗАЯВЛЕННОГО набора фактов ЗАРЕГИСТРИРОВАННОМУ, а не конъюнкция
пяти независимых проверок с пятью диагностиками, четырёх из которых приёмка не
объявляет. Всякое отличие означает одно и то же: перед нами не то единственное
исключение, которое зарегистрировано, — то есть второе.
"""

from .. import outcome
from ..rules import Rule

REGISTERED_BOOTSTRAP = {
    "change_id": "SDD-1",
    "issue": "PRO-Robotech/kacho-workspace#480",
    "epoch": "pre-cutover",
    "recorded_exception": True,
}
REGISTERED_SUBJECT_STATIC_FORM = "DRAFT"
REGISTERED_SELF_PACKAGE_PRESENT = False

REGISTERED_ADMISSION = {
    "bootstrap": REGISTERED_BOOTSTRAP,
    "subject.static_form": REGISTERED_SUBJECT_STATIC_FORM,
    "self_package_present": REGISTERED_SELF_PACKAGE_PRESENT,
}

FAMILY = "boot"


def _declared_admission(world):
    """Заявленный миром набор фактов допуска — целиком, без выборки."""
    return {
        "bootstrap": world.read_all("bootstrap"),
        "subject.static_form": world.read("subject.static_form"),
        "self_package_present": world.read("self_package_present"),
    }


def _not_the_registered_bootstrap(world):
    return _declared_admission(world) != REGISTERED_ADMISSION


RULES = [
    Rule(
        rule_id="boot.single-exception",
        diagnostic="CG_BOOTSTRAP_NOT_UNIQUE",
        category=outcome.CATEGORY_RED,
        subject_keys=("bootstrap", "subject", "self_package_present"),
        requires=("bootstrap", "subject.static_form", "self_package_present"),
        predicate=_not_the_registered_bootstrap,
        why="§1 единственный bootstrap change, ограниченный парой #480 + этот "
            "acceptance; §4 статическая форма subject DRAFT и недействительность "
            "исключения с момента cutover",
    ),
]
