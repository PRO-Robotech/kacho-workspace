"""cg.diff — владение фактическим diff'ом и пригодность его к convergence.

Приёмка §9 и раздел «Diff ownership, post-diff review и convergence»: actual
changed path/blob set обязан exact-set совпадать с approved implementation diff
set ОДНОГО change, а convergence record несёт «SHA-256 canonical diff set: repo
+ path + file mode + final blob/deletion marker, sorted» — то есть сверяется не
перечень имён, а содержимое.

**Предметов у семейства два, и они разной природы.** Первый — ВЛАДЕНИЕ: что
фактически изменилось, кем это заявлено и не заявлено ли дважды. Второй —
СХОДИМОСТЬ: совпало ли то, что в итоге лежит, с тем, что рецензент смотрел.
Первый отвечает на вопрос «чей это diff», второй — «тот ли это diff, который
одобрили». Смешивать их нельзя: change, чей diff не принадлежит ему целиком, до
вопроса о сходимости ещё не дошёл.

**Отсюда объявленный порядок правил, и он назван, потому что вердикт берётся по
первому нарушению.** Идём от дерева к заявкам и только потом к рецензии:

1. **изменено и не заявлено** — в дереве лежит содержимое, которого не одобрял
   никто; это самый широкий отказ владения, и он не адресуется ни одному change;
2. **заявлено и не изменено** — заявка о том, чего не произошло; она уже, чем
   первое: у неё есть автор, и спрашивать его есть с кого;
3. **заявлено дважды** — владелец есть, но он не один;
4. **разошлось с рецензией** — владение установлено, вопрос о сходимости
   осмыслен только после этого.

Порядок наблюдаем: мир с лишним фактическим путём краснит и первое правило, и
четвёртое (лишний путь не мог быть в reviewed set), перепись называет оба, а
вердикт берётся по первому. Взять его в порядке случайном значило бы менять
диагностику от перестановки строк в файле.

**Сравнение первого правила идёт ПО СОДЕРЖИМОМУ, второго — ПО ПУТИ, и это
решение, а не небрежность.** «Одобрен путь, но не это содержимое» — тоже
неодобренное содержимое, поэтому первое правило судит пару (path, blob): иначе
дрейф blob'а на заявленном пути не судило бы ни одно правило, а его blob'ы
числились бы прочитанными, ничьим предикатом не тронутые. Второе правило судит
членство пути: приёмка называет его «claimed path отсутствует в actual diff»,
и расширь его до пары — один и тот же дрейф blob'а предъявлялся бы ДВАЖДЫ,
двумя разными диагностиками. Односторонность здесь и есть то, что делает
находки непересекающимися.

**Заявка без заявителя заявкой не является.** Правило о двойном владении читает
не только путь второй заявки, но и её значение: запись, не называющая второго
change, ownership неоднозначным не делает — она лишь выглядит заявкой. Поэтому
предикат судит ЗНАЧЕНИЕ, а не наличие ключа.

**Чего это семейство НЕ судит:** post-diff records ролей и запись convergence —
у них свои семейства и свои диагностики; здесь они не дублируются, иначе о том
же предмете говорили бы два места и разошлись бы молча.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "diff"

# Что фактически изменено: путь -> итоговый blob.
ACTUAL = "actual_changed_paths"
# Что заявлено одобренным implementation diff'ом change'а: путь -> blob.
APPROVED = "approved_diff_paths"
# Что видел рецензент: путь -> blob на момент рецензии.
REVIEWED = "reviewed_diff_blobs"
# Пути, заявленные ВТОРЫМ активным change'ом: путь -> идентификатор change'а.
SECOND_CLAIMS = "second_active_change_claims"

SUBJECT_KEYS = (ACTUAL, APPROVED, REVIEWED, SECOND_CLAIMS)

ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _actual_content_unclaimed(world):
    """В дереве лежит содержимое, которого одобренный diff не заявлял.

    Оба отображения читаются целиком: вопрос «всё ли изменённое заявлено» есть
    отношение множеств, и по одной записи он не решается. Сравнение идёт по
    паре (path, blob) — заявлен путь, но не это содержимое, значит содержимое
    не заявлено.
    """
    actual = world.read_all(ACTUAL)
    approved = world.read_all(APPROVED)
    return any(approved.get(path) != blob for path, blob in actual.items())


def _claimed_path_never_changed(world):
    """Change заявил путь, которого в фактическом diff нет вовсе.

    Судится ЧЛЕНСТВО пути, а не пара: дрейф blob'а на заявленном пути уже
    предъявлен правилом выше, и предъявлять его вторично другой диагностикой
    значило бы удваивать одну находку.
    """
    approved = world.read_all(APPROVED)
    actual = world.read_all(ACTUAL)
    return any(path not in actual for path in approved)


def _owner_ambiguous(world):
    """Путь заявлен и нами, и вторым активным change'ом.

    Читается и путь второй заявки, и её значение: запись, не называющая
    второго change, никого вторым владельцем не делает. Пересечение берётся с
    заявкой, а не с фактическим diff'ом, потому что владение — свойство заявок:
    чужая заявка на путь, которого мы не трогали, нашего владения не оспаривает.
    """
    approved = world.read_all(APPROVED)
    second = world.read_all(SECOND_CLAIMS)
    return any(
        path in approved and not _absent(claimant)
        for path, claimant in second.items()
    )


def _final_set_differs_from_reviewed(world):
    """Итоговый diff set не равен тому, который был отрецензирован.

    Сравнивается ФАКТИЧЕСКОЕ с ОТРЕЦЕНЗИРОВАННЫМ, а не заявленное с
    отрецензированным: сходимость требует, чтобы рецензент видел то, что в
    итоге легло. Заявка здесь ни при чём — она может совпадать с рецензией и
    расходиться с деревом одновременно.

    Оба отображения читаются целиком: равенство множеств пар — свойство
    множеств, а не отдельной записи.
    """
    actual = world.read_all(ACTUAL)
    reviewed = world.read_all(REVIEWED)
    return actual != reviewed


RULES = [
    Rule(
        rule_id="diff.path-unclaimed",
        diagnostic="CG_DIFF_PATH_UNCLAIMED",
        category=outcome.CATEGORY_RED,
        subject_keys=(ACTUAL, APPROVED),
        requires=(ACTUAL, APPROVED),
        predicate=_actual_content_unclaimed,
        why="§9 actual changed path/blob set обязан exact-set совпасть с "
            "approved implementation diff set; содержимое, которого не заявлял "
            "никто, не принадлежит ни одному change",
    ),
    Rule(
        rule_id="diff.claim-orphan",
        diagnostic="CG_DIFF_CLAIM_ORPHAN",
        category=outcome.CATEGORY_RED,
        subject_keys=(APPROVED, ACTUAL),
        requires=(APPROVED, ACTUAL),
        predicate=_claimed_path_never_changed,
        why="§9 обратная сторона того же exact-set: заявленный путь без "
            "фактического изменения — заявка о том, чего не произошло",
    ),
    Rule(
        rule_id="diff.owner-ambiguous",
        diagnostic="CG_DIFF_OWNER_AMBIGUOUS",
        category=outcome.CATEGORY_RED,
        subject_keys=(APPROVED, SECOND_CLAIMS),
        requires=(APPROVED, SECOND_CLAIMS),
        predicate=_owner_ambiguous,
        why="§9 у пути ровно один владеющий change; заявка второго активного "
            "change делает владение неоднозначным, и решать его молча нельзя",
    ),
    Rule(
        rule_id="diff.reviewed-set-mismatch",
        diagnostic="CG_REVIEWED_DIFF_SET_MISMATCH",
        category=outcome.CATEGORY_RED,
        subject_keys=(ACTUAL, REVIEWED),
        requires=(ACTUAL, REVIEWED),
        predicate=_final_set_differs_from_reviewed,
        why="§9 convergence eligibility требует, чтобы итоговый canonical diff "
            "set совпадал с отрецензированным; рецензия чужого содержимого "
            "рецензией этого содержимого не является",
    ),
]
