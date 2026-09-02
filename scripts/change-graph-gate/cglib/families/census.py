"""cg.census — независимая перепись наследия и её точное множество.

Приёмка §8 объявляет об этом предмете пять разных утверждений, и миры кейсов
§13 приходят пятью РАЗНЫМИ формами — по одной на утверждение. Поэтому правила
здесь не «пять проверок одного мира», а пять непересекающихся полос, каждая со
своей применимостью:

    producer · coverage · etag · timestamp · response_digest · api
        артефакт переписи: кем снят, что покрыл, свеж ли (SDD-1-CENSUS-01..06)
    snapshot · policy_registry
        точное множество registry против снимка      (SDD-1-CENSUS-07..09)
    legacy_change · post_cutover_observed
        неизменность observable contract у route legacy (SDD-1-CENSUS-10..11)
    legacy_change · package_present · package_exact_maps_candidate_diff
        route migrate требует package                 (SDD-1-CENSUS-12..13)
    acceptance · snapshot_open_prs · snapshot_live_issues · backfill_required
        закрытая историческая приёмка не backfill-ится (SDD-1-CENSUS-14)

Полосы разведены `requires`: мир одной формы не поднимает правил другой, и это
не удобство, а условие честности переписи прочитанного — правило, объявившее
координату, которой в мире нет, не применяется и потому ничего не «покрывает».

**Точное множество сравнивается по КООРДИНАТАМ, а не по содержимому записи, и
это решение, а не упрощение.** Значение записи registry в мире кейса — токен
формы `issue+acceptance_path+route`, то есть описание состава. Соблазн
потребовать состав полным (в частности непустой acceptance_path) велик и
неверен: в зарегистрированной политике `docs/changes/policy.yaml` путь приёмки
отсутствует у **57 записей из 60**, и отсутствие там выражено ПЕРВЫМ КЛАССОМ —
`acceptance_path: null` вместе с названным `acceptance_absence_predicate`
(`no-acceptance-document-in-change`), а не пустой строкой. Предикат, требующий
путь непустым, покрасил бы эти 57 записей, при том что приёмка §8 требует от
registry ровно одного — exact-set совпадения со снимком, и объявляет ровно две
диагностики о множестве: пропущенная активная запись и лишняя. Поэтому
контейнеры берутся целиком (`read_all`) и потребляются целиком как множества
координат, а состав записи не судится ни одним правилом этого семейства.

**Свежесть считается от ЗАРЕГИСТРИРОВАННОГО мгновения переписи, а не от
часов машины** — и это тоже решение с названной ценой. Мир несёт ровно один
момент времени (`timestamp`) и имя версионированного предиката
(`freshness_predicate`); точки отсчёта в нём нет. Взять её у системных часов
значило бы завести гейт, чей вердикт есть функция дня прогона: fixture
SDD-1-CENSUS-01 (`2026-09-02T00:00:00Z`) стала бы RED уже 2026-09-04, и это
красное было бы ложным. Landed-перепись — исторический документ, её свежесть
судится в момент её landing, а он зарегистрирован: единственная перепись
названа в policy (`legacy_census.sha256`), и её артефакт объявляет момент
съёмки. Отсюда `REGISTERED_CENSUS_INSTANT`.

Обязанность, которую это создаёт, названа прямо: приземляя НОВУЮ перепись,
двигают и эту константу — иначе новая перепись прочитается устаревшей и даст
RED. Послабление истекает громко, а не молча: красное называет ровно ту запись,
которую забыли обновить. Тот же вид привязки к зарегистрированной истине, что у
`REGISTERED_BOOTSTRAP` в cg.boot.

Порядок правил объявленный, и у каждого шва названа причина: находка, содержащая
в себе другую, стоит раньше неё.
"""

import datetime

from .. import outcome
from ..rules import Rule

FAMILY = "census"

# --- зарегистрированная истина ----------------------------------------------

# Приёмка §8: перепись снимает independent producer.
INDEPENDENT_PRODUCER = "independent"

# Приёмка §8: snapshot открытых PR обоих repo и Issues с live in-progress.
REQUIRED_COVERAGE = frozenset(
    ("workspace-open-prs", "product-open-prs", "live-in-progress-issues")
)

# Момент съёмки зарегистрированной переписи
# docs/changes/census/1c85491a8335882c7abc47a690a267d0464f19623348e15f552e2644a89a45b0.yaml
# (её же координата названа в docs/changes/policy.yaml, legacy_census.sha256).
REGISTERED_CENSUS_INSTANT = "2026-09-02T11:06:27Z"

# Версионированные предикаты свежести: имя -> горизонт. Имя, которого здесь нет,
# испытуемый оценить не может и молчать об этом не вправе.
FRESHNESS_HORIZONS = {
    "captured-within-24h": datetime.timedelta(hours=24),
}

INSTANT_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

AVAILABLE = "available"

ROUTE_LEGACY = "legacy"
ROUTE_MIGRATE = "migrate"

ACCEPTANCE_CLOSED = "closed"

# Пустое значение обязано означать «пусто»: словарь отсутствия назван явно,
# чтобы «нет отпечатка» не пришлось угадывать по правдоподобию строки.
ABSENT_MARKERS = (None, "", "none", "—")


def _absent(value):
    return value in ABSENT_MARKERS


def _instant(text, coordinate):
    """Мгновение из мира. Неразбираемое — собственный отказ, а не вердикт."""
    try:
        return datetime.datetime.strptime(str(text), INSTANT_FORMAT)
    except (TypeError, ValueError):
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_MALFORMED,
            "координата %s несёт неразбираемое мгновение %r; ожидается форма %s"
            % (coordinate, text, INSTANT_FORMAT),
        )


# --- полоса артефакта переписи (SDD-1-CENSUS-01..06) -------------------------


def _producer_unavailable(world):
    """§8: refs/API unavailable — NOT_EXECUTED, и это не «нарушений нет»."""
    return world.read("api.availability") != AVAILABLE


def _census_artifact_incomplete(world):
    """§8: перепись обязана нести producer, exact queries, ETag и digest.

    Читаются все четыре координаты, потому что предмет правила — ПОЛНОТА
    артефакта, а не одна её составляющая: ответ «перепись полна» нельзя дать,
    не взглянув на каждую.
    """
    producer = world.read("producer")
    coverage = world.read_all("coverage")
    etag = world.read("etag")
    digest = world.read("response_digest")
    if producer != INDEPENDENT_PRODUCER:
        return True
    if set(coverage) != set(REQUIRED_COVERAGE):
        return True
    if any(_absent(coverage[name]) for name in sorted(coverage)):
        return True
    return _absent(etag) or _absent(digest)


def _census_stale(world):
    """§8: stale snapshot — RED. Точка отсчёта зарегистрирована, а не «сейчас»."""
    predicate_id = world.read("freshness_predicate")
    captured = _instant(world.read("timestamp"), "timestamp")
    horizon = FRESHNESS_HORIZONS.get(predicate_id)
    if horizon is None:
        raise outcome.SelfFailure(
            outcome.SELF_WORLD_MALFORMED,
            "мир объявил предикат свежести %r, которого испытуемый не знает; "
            "известны %s — оценить свежесть нечем, и молчание было бы вердиктом "
            "о том, чего не проверяли"
            % (predicate_id, sorted(FRESHNESS_HORIZONS)),
        )
    registered = _instant(REGISTERED_CENSUS_INSTANT, "REGISTERED_CENSUS_INSTANT")
    return abs(captured - registered) > horizon


# --- полоса точного множества registry (SDD-1-CENSUS-07..09) -----------------


def _registry_sets(world):
    """Оба множества координат. Читаются ОБА: предмет — их отношение.

    Содержимое записи не судится намеренно — см. разбор в шапке модуля.
    """
    snapshot = world.read_all("snapshot")
    registry = world.read_all("policy_registry")
    return set(snapshot), set(registry)


def _registry_misses_active(world):
    """§8: координата снимка, которой нет в registry, уходит из графа вовсе."""
    snapshot, registry = _registry_sets(world)
    return bool(snapshot - registry)


def _registry_has_extra(world):
    """§8: запись registry, которой нет в снимке, — лишняя."""
    snapshot, registry = _registry_sets(world)
    return bool(registry - snapshot)


# --- полоса observable contract (SDD-1-CENSUS-10..11) ------------------------


def _route_is_legacy(world):
    return world.read("legacy_change.route") == ROUTE_LEGACY


def _legacy_contract_changed(world):
    """§8: route legacy допускает только НЕИЗМЕНЁННЫЙ observable contract.

    Сверяются обе половины пары — приёмка и наблюдаемый контракт: изменение
    любой из них означает, что зарегистрированный legacy перестал быть тем, что
    зарегистрировали, и требует route migrate.
    """
    registered = (
        world.read("legacy_change.acceptance_hash"),
        world.read("legacy_change.observable_contract_hash"),
    )
    observed = (
        world.read("post_cutover_observed.acceptance_hash"),
        world.read("post_cutover_observed.observable_contract_hash"),
    )
    return registered != observed


# --- полоса explicit migration (SDD-1-CENSUS-12..13) -------------------------


def _route_is_migrate(world):
    return world.read("legacy_change.route") == ROUTE_MIGRATE


def _migration_package_missing(world):
    """§8: change требует route migrate + package.

    Package, не отображающий candidate diff точно, — тот же дефект, что его
    отсутствие: обещанного package у изменения нет. Отдельной диагностики
    приёмка на это не объявляет, и заводить её значило бы положить в дерево код,
    который не предъявит ни один кейс.
    """
    present = world.read("package_present")
    exact = world.read("package_exact_maps_candidate_diff")
    return not present or not exact


# --- полоса закрытой исторической приёмки (SDD-1-CENSUS-14) ------------------


def _closed_acceptance_backfilled(world):
    """§8: closed historical acceptance не backfill-ятся.

    Требование registry entry для того, чего снимок не несёт, и есть лишняя
    запись — поэтому здесь стоит та же диагностика, что у полосы точного
    множества, а не выдуманная пятая. Читаются обе половины снимка: «отсутствует
    среди open PR И live in-progress» — утверждение о ДВУХ наборах, и ответить
    на него, заглянув в один, нельзя.
    """
    state = world.read("acceptance.state")
    closed_before = world.read("acceptance.closed_before_census")
    open_prs = world.read_all("snapshot_open_prs")
    live_issues = world.read_all("snapshot_live_issues")
    demanded = world.read("backfill_required")
    historical = state == ACCEPTANCE_CLOSED and bool(closed_before)
    outside_snapshot = not open_prs and not live_issues
    return bool(demanded) and historical and outside_snapshot


ARTIFACT_KEYS = (
    "producer", "coverage", "etag", "timestamp", "freshness_predicate",
    "response_digest", "api",
)
REGISTRY_KEYS = ("snapshot", "policy_registry")
CONTRACT_KEYS = ("legacy_change", "post_cutover_observed")
MIGRATION_KEYS = (
    "legacy_change", "package_present", "package_exact_maps_candidate_diff",
)
BACKFILL_KEYS = (
    "acceptance", "snapshot_open_prs", "snapshot_live_issues", "backfill_required",
)

# Порядок ОБЪЯВЛЕННЫЙ. Внутри полосы артефакта: недоступность producer'а
# содержит в себе и полноту, и свежесть — переписи, которой нет, нечем быть
# неполной; неполная перепись содержит в себе свежесть — момент съёмки не того
# снимка ни о чём не говорит. Внутри полосы множества: пропущенная активная
# запись объявлена раньше лишней, потому что она уводит изменение из графа
# целиком, тогда как лишняя лишь заносит в него не то. Полосы между собой не
# пересекаются по применимости, и их взаимный порядок вердикта не решает.
RULES = [
    Rule(
        rule_id="census.producer-unavailable",
        diagnostic="CG_CENSUS_PRODUCER_UNAVAILABLE",
        category=outcome.CATEGORY_NOT_EXECUTED,
        subject_keys=("api",),
        requires=("api.availability",),
        predicate=_producer_unavailable,
        why="§8 API unavailable даёт NOT_EXECUTED, не вердикт о предмете "
            "(SDD-1-CENSUS-02)",
    ),
    Rule(
        rule_id="census.coverage-incomplete",
        diagnostic="CG_CENSUS_COVERAGE_INCOMPLETE",
        category=outcome.CATEGORY_RED,
        subject_keys=("producer", "coverage", "etag", "response_digest"),
        requires=("producer", "coverage", "etag", "response_digest"),
        predicate=_census_artifact_incomplete,
        why="§8 independent producer снимает open PR обоих repo и live "
            "in-progress Issues с exact query, ETag и response digest; "
            "incomplete coverage даёт RED (SDD-1-CENSUS-04..06)",
    ),
    Rule(
        rule_id="census.stale",
        diagnostic="CG_CENSUS_STALE",
        category=outcome.CATEGORY_RED,
        subject_keys=("timestamp", "freshness_predicate"),
        requires=("timestamp", "freshness_predicate"),
        predicate=_census_stale,
        why="§8 stale snapshot даёт RED; предикат свежести версионирован, "
            "точка отсчёта зарегистрирована (SDD-1-CENSUS-03)",
    ),
    Rule(
        rule_id="census.registry-misses-active",
        diagnostic="CG_LEGACY_REGISTRY_MISSING_ACTIVE",
        category=outcome.CATEGORY_RED,
        subject_keys=REGISTRY_KEYS,
        requires=REGISTRY_KEYS,
        predicate=_registry_misses_active,
        why="§8 policy legacy_changes обязан exact-set совпасть со snapshot; "
            "пропущенная активная координата уводит изменение из графа "
            "(SDD-1-CENSUS-08)",
    ),
    Rule(
        rule_id="census.registry-extra-entry",
        diagnostic="CG_LEGACY_REGISTRY_EXTRA_ENTRY",
        category=outcome.CATEGORY_RED,
        subject_keys=REGISTRY_KEYS,
        requires=REGISTRY_KEYS,
        predicate=_registry_has_extra,
        why="§8 exact-set: запись registry вне снимка — лишняя "
            "(SDD-1-CENSUS-09)",
    ),
    Rule(
        rule_id="census.legacy-contract-changed",
        diagnostic="CG_LEGACY_CONTRACT_CHANGED",
        category=outcome.CATEGORY_RED,
        subject_keys=CONTRACT_KEYS,
        requires=(
            "legacy_change.route",
            "legacy_change.acceptance_hash",
            "legacy_change.observable_contract_hash",
            "post_cutover_observed.acceptance_hash",
            "post_cutover_observed.observable_contract_hash",
        ),
        applicability=_route_is_legacy,
        predicate=_legacy_contract_changed,
        why="§8 route legacy допускает только неизменённый observable "
            "contract; изменение требует migration (SDD-1-CENSUS-11)",
    ),
    Rule(
        rule_id="census.migration-package-missing",
        diagnostic="CG_MIGRATION_PACKAGE_MISSING",
        category=outcome.CATEGORY_RED,
        subject_keys=MIGRATION_KEYS,
        requires=(
            "legacy_change.route",
            "package_present",
            "package_exact_maps_candidate_diff",
        ),
        applicability=_route_is_migrate,
        predicate=_migration_package_missing,
        why="§8 change требует route migrate + package, exact-mapped на "
            "candidate diff (SDD-1-CENSUS-13)",
    ),
    Rule(
        rule_id="census.closed-acceptance-backfilled",
        diagnostic="CG_LEGACY_REGISTRY_EXTRA_ENTRY",
        category=outcome.CATEGORY_RED,
        subject_keys=BACKFILL_KEYS,
        requires=(
            "acceptance.state",
            "acceptance.closed_before_census",
            "snapshot_open_prs",
            "snapshot_live_issues",
            "backfill_required",
        ),
        predicate=_closed_acceptance_backfilled,
        why="§8 closed historical acceptance не backfill-ятся: требование "
            "registry entry для того, чего снимок не несёт, есть лишняя запись "
            "(SDD-1-CENSUS-14)",
    ),
]
