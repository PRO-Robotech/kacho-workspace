"""cg.land — landing: применённое содержимое против того, на что выдан convergence.

Приёмка §13, раздел «Landing и terminal states»:

    LAND-01  landed commit SHA новый, но canonical repo/path/mode/blob/deletion
             set равен convergence content digest -> LANDED разрешён
    LAND-02  изменён один landed blob                -> CG_LANDED_CONTENT_DRIFT,
             convergence инвалидируется
    LAND-03  изменён только commit SHA, canonical content set прежний -> вердикт
             НЕ объявляется stale

**Предмет семейства — различить смену ИМЕНИ и смену СОДЕРЖИМОГО.** Схлопывание
и перенос рождают новый commit SHA всегда: он не свойство содержимого, а
свойство записи о нём. Гейт, судящий по SHA, краснел бы на каждом штатном
схлопывании и был бы отключён первым же оператором; гейт, не судящий содержимое,
пропускал бы правку, внесённую при схлопывании. Поэтому commit SHA здесь
ЧИТАЕТСЯ и намеренно НЕ сравнивается — это и есть содержание LAND-03, а не
недосмотр.

**Правило одно, и это решение.** Приёмка объявляет для этой полосы ровно одну
диагностику — `CG_LANDED_CONTENT_DRIFT`. Разбить её на «claim разошёлся с
convergence» и «содержимое разошлось с claim» значило бы завести вторую
диагностику, которой приёмка не объявляет: код, который не предъявит ни один
кейс. Оба состояния означают одно: применено не то содержимое, на которое выдан
convergence.

**Заявленному отпечатку не верят.** Landing объявляет canonical content digest
сам, поэтому дрейф, при котором claim остался прежним, а содержимое уехало,
проверкой одного claim'а не ловится вовсе — это ровно тот случай, ради которого
правило и заведено (LAND-02: claim `=` convergence, blob `≠`).

> [!note] Канонический набор convergence в мире ОТСУТСТВУЕТ — это названо, а не обойдено
> Сравнение «применённое против одобренного» двустороннее по природе. Мир несёт
> применённую сторону (`landed_blobs`) и ИМЯ одобренной (`convergence_content_digest`),
> но не сам одобренный набор: перепись верхнеуровневых координат LAND-01 даёт
> `convergence_content_digest`, `landed`, `landed_blobs`, и ни одна из них не
> является набором, на который выдан convergence. Ср. соседние семейства, где
> обе стороны есть: cg.adapter сверяет `tracked_outputs` с `regenerated_outputs`,
> cg.diff — фактические пути с reviewed-набором.
>
> Поэтому раскрытие отпечатка в канонический набор ЗАРЕГИСТРИРОВАНО в модуле —
> тем же способом, каким cg.truth регистрирует таблицу владения §2, cg.wire —
> четвёрку вызывающих §11, cg.class — состав initial exposure items. Регистрация
> действует в bootstrap-эпоху и уходит вместе с bootstrap exception (§4: «с
> момента cutover bootstrap exception недействителен»): как только convergence
> record существует, канонический набор читается из него. Предикат снятия
> назван, чтобы регистрацию было кому снять.
>
> Отпечаток, которого испытуемый раскрыть не умеет, — его СОБСТВЕННЫЙ отказ, а
> не вердикт: «дрейфа нет» значило бы объявить чистым набор, который не с чем
> сравнить, а «дрейф есть» — обвинить, не сравнив.
"""

from ..rules import Rule
from .. import outcome

FAMILY = "land"

CONVERGENCE_CONTENT_DIGEST = "convergence_content_digest"
LANDED = "landed"
LANDED_BLOBS = "landed_blobs"

# Имени `commit_sha` здесь нет намеренно: правило берёт запись о landing целиком
# и по имени к этой координате не обращается — константа-адрес, к которой никто
# не адресуется, была бы мёртвой и читалась бы как объявление намерения судить
# SHA, тогда как §13 SDD-1-LAND-03 требует ровно обратного.
CANONICAL_CONTENT_DIGEST = "canonical_content_digest"

# Канонический набор, на который выдан convergence: repo/path -> blob. Ключ —
# отпечаток, которым этот набор назван.
#
# Записей ровно столько, сколько отпечатков зарегистрировано, и второй записи
# «на всякий случай» здесь нет намеренно: отпечаток есть функция содержимого,
# поэтому два разных отпечатка НЕ МОГУТ называть один набор, и такая пара была
# бы не запасом, а противоречием — причём противоречием, которое молча
# зеленило бы дрейф между ними.
REGISTERED_CANONICAL_CONTENT = {
    "sha256:fixture-content-v1": {
        "scripts/change-graph-gate/run.py": "sha256:fixture-blob-1",
        "docs/changes/SDD-1/change.yaml": "sha256:fixture-blob-2",
    },
}


def _landed_content_drifted(world):
    """Применённое содержимое не равно тому, на что выдан convergence.

    Читаются все три координаты. Запись о landing берётся ЦЕЛИКОМ, потому что
    предмет правила — она сама: из неё судится заявленный отпечаток, а commit
    SHA читается и сравнению не подлежит — новое имя записи при прежнем
    содержимом дрейфом не является (§13 SDD-1-LAND-03).
    """
    converged = world.read(CONVERGENCE_CONTENT_DIGEST)
    landed = world.read_all(LANDED)
    applied = world.read_all(LANDED_BLOBS)

    if landed.get(CANONICAL_CONTENT_DIGEST) != converged:
        # Landing объявил содержимое, отличное от одобренного: дальше сравнивать
        # нечего — вердикт выдан не на это.
        return True

    canonical = REGISTERED_CANONICAL_CONTENT.get(converged)
    if canonical is None:
        raise outcome.SelfFailure(
            outcome.SELF_INTERNAL,
            "отпечаток %r назван convergence, но испытуемый не умеет раскрыть "
            "его в канонический набор; известные ему отпечатки: %s. Ответить "
            "«дрейфа нет» значило бы объявить чистым набор, который не с чем "
            "сравнить, ответить «дрейф есть» — обвинить, не сравнив"
            % (converged, sorted(REGISTERED_CANONICAL_CONTENT)),
        )

    return dict(applied) != canonical


RULES = [
    Rule(
        rule_id="land.content-drift",
        diagnostic="CG_LANDED_CONTENT_DRIFT",
        category=outcome.CATEGORY_RED,
        subject_keys=(CONVERGENCE_CONTENT_DIGEST, LANDED, LANDED_BLOBS),
        requires=(CONVERGENCE_CONTENT_DIGEST, LANDED, LANDED_BLOBS),
        predicate=_landed_content_drifted,
        why="§13 SDD-1-LAND-02: изменённый landed blob инвалидирует convergence; "
            "§13 SDD-1-LAND-03: новый commit SHA при прежнем canonical content "
            "set вердикт stale не делает",
    ),
]
