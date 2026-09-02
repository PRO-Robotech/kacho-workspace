"""Правило над миром и порядок, в котором правила складываются в вердикт.

Несущее свойство: вердикт производится ПРЕДИКАТОМ НАД ФАКТАМИ МИРА, а
идентификатор кейса выбирает только семейство правил. Иначе испытуемый был бы
таблицей соответствий «ID -> ответ», зелёной по построению и не способной
упасть ни на чём.

Второе несущее свойство: применимые правила исполняются ВСЕ, а не до первого
нарушения. Причин две, и обе проверяемы:

1. короткое замыкание оставило бы факты последующих правил непрочитанными, и
   перепись прочитанного объявила бы находку там, где её нет;
2. перепись «нарушений найдено N» отличима от «нарушение одно», а вердикт берётся
   по первому в ОБЪЯВЛЕННОМ порядке — то есть порядок назван и виден, а не
   получается случайно из порядка выхода.
"""

from . import outcome


def _top_segment(path):
    """Верхнеуровневая координата пути. Ключ в кавычках берётся целиком."""
    if path.startswith("['"):
        end = path.find("']")
        if end != -1:
            return path[2:end]
    return path.split(".", 1)[0].split("[", 1)[0]


class Rule:
    """Одно правило: применимость, предикат нарушения и предмет.

    `subject_keys` — верхнеуровневые координаты мира, о которых правило судит.
    Их объединение по семейству и есть предмет семейства; факт мира внутри
    предмета обязан быть прочитан, факт вне предмета называется в переписи и
    судится другим семейством.
    """

    __slots__ = ("rule_id", "diagnostic", "category", "subject_keys", "requires",
                 "applicability", "predicate", "why")

    def __init__(self, rule_id, diagnostic, subject_keys, requires, predicate,
                 why, category=outcome.CATEGORY_RED, applicability=None):
        if not rule_id or not diagnostic:
            raise ValueError("правило без идентификатора либо без диагностики")
        if not subject_keys:
            raise ValueError("правило %s не объявило предмета" % rule_id)
        # Правило, чья диагностика не может стать вердиктом, бесполезно и
        # опасно: оно молчало бы всегда. Проверяется построением Outcome.
        outcome.Outcome(category, diagnostic)
        self.rule_id = rule_id
        self.diagnostic = diagnostic
        self.category = category
        self.subject_keys = tuple(subject_keys)
        self.requires = tuple(requires)
        self.predicate = predicate
        self.applicability = applicability
        self.why = why

    def applies(self, world):
        for coordinate in self.requires:
            if not world.has(coordinate):
                return False
        if self.applicability is None:
            return True
        return bool(self.applicability(world))

    def violated(self, world):
        return bool(self.predicate(world))


class Census:
    """Объём осмотренного. Печатается всегда, в том числе на чистом мире.

    Без него «нарушений ноль» неотличимо от «не прочитано ничего», и это
    ровно тот класс, ради которого перепись заведена.
    """

    __slots__ = ("family", "rules_total", "rules_applicable", "violations",
                 "facts_total", "facts_read", "facts_outside", "outside_paths")

    def __init__(self, family):
        self.family = family
        self.rules_total = 0
        self.rules_applicable = 0
        self.violations = []
        self.facts_total = 0
        self.facts_read = 0
        self.facts_outside = 0
        self.outside_paths = []

    def lines(self):
        report = [
            "семейство cg.%s · правил %d · применимо %d · нарушений %d"
            % (self.family, self.rules_total, self.rules_applicable,
               len(self.violations)),
            "фактов мира %d · прочитано %d · вне предмета семейства %d"
            % (self.facts_total, self.facts_read, self.facts_outside),
        ]
        if self.outside_paths:
            report.append(
                "вне предмета cg.%s (судит другое семейство): %s"
                % (self.family, ", ".join(sorted(self.outside_paths)))
            )
        for rule in self.violations:
            report.append("нарушено %s -> %s" % (rule.rule_id, rule.diagnostic))
        return report


def evaluate(family, family_rules, world):
    """Возвращает пару (вердикт, перепись) либо поднимает собственный отказ."""
    census = Census(family)
    census.rules_total = len(family_rules)
    if not family_rules:
        raise outcome.SelfFailure(
            outcome.SELF_REGISTRY_BROKEN,
            "семейство cg.%s не объявило ни одного правила" % family,
        )

    subject = set()
    for rule in family_rules:
        subject.update(rule.subject_keys)

    applicable = []
    for rule in family_rules:
        try:
            if rule.applies(world):
                applicable.append(rule)
        except outcome.SelfFailure:
            raise
        except Exception as error:
            raise outcome.SelfFailure(
                outcome.SELF_RULE_CRASHED,
                "применимость правила %s упала: %r" % (rule.rule_id, error),
            )
    census.rules_applicable = len(applicable)

    if not applicable:
        # «Правил не нашлось» и «нарушений не найдено» — разные вещи.
        # Вторая произносится только после первой, поэтому здесь не GREEN.
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_NOT_JUDGED,
            "ни одно правило семейства cg.%s не применимо к миру %s; "
            "верхнеуровневые координаты мира: %s"
            % (family, world.path, ", ".join(sorted(world.top_keys())) or "(нет)"),
        )

    for rule in applicable:
        try:
            if rule.violated(world):
                census.violations.append(rule)
        except outcome.SelfFailure:
            raise
        except Exception as error:
            raise outcome.SelfFailure(
                outcome.SELF_RULE_CRASHED,
                "правило %s упало на мире %s: %r" % (rule.rule_id, world.path, error),
            )

    _account_facts(family, subject, world, census)

    if census.violations:
        first = census.violations[0]
        return outcome.Outcome(first.category, first.diagnostic), census
    return outcome.green(), census


def _account_facts(family, subject, world, census):
    """Сверяет прочитанное с объявленным предметом — в обе стороны."""
    facts = world.facts()
    census.facts_total = len(facts)

    for path in world.read_prefixes():
        head = _top_segment(path)
        if head not in subject:
            raise outcome.SelfFailure(
                outcome.SELF_RULE_READ_OUTSIDE_SUBJECT,
                "правило семейства cg.%s прочитало %s вне объявленного предмета %s"
                % (family, path, sorted(subject)),
            )

    unread = []
    for path in sorted(facts):
        head = _top_segment(path)
        if head not in subject:
            census.facts_outside += 1
            census.outside_paths.append(path)
            continue
        if world.was_read(path):
            census.facts_read += 1
        else:
            unread.append(path)

    if unread:
        # Факт объявлен миром, входит в предмет семейства и не прочитан ни одним
        # применимым правилом. Вердикт был бы заявлением шире осмотренного.
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_FACT_UNREAD,
            "предмет cg.%s объявляет координаты %s, но факты %s не прочитало ни "
            "одно применимое правило"
            % (family, sorted(subject), unread),
        )
