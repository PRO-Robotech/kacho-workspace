"""cg.hash — привязка вердикта к отпечатку.

Приёмка §3 и §9: у каждого artifact есть три координаты, и они РАЗНЫЕ:

    manifest_hashes[a]        что манифест утверждает о содержимом
    content_hashes[a]         каково содержимое на самом деле
    approval_bound_subject[r] к какому отпечатку привязан вердикт роли r

Диагностика выбирается не тем, «что не сошлось», а тем, КАКАЯ ИЗ ТРЁХ
координат оказалась в стороне от двух других. Различение несущее, потому что
условие «манифест не равен содержимому» истинно и там, где предмет —
испорченный манифест, и там, где предмет — уехавшее содержимое при живом
вердикте. Одно и то же неравенство, два разных дефекта:

    манифест ≠ содержимое, манифест ≠ вердикт  -> манифест выдумал отпечаток
    манифест = вердикт, оба ≠ содержимому      -> вердикт устарел вместе с ним

Отдельно стоит корень: acceptance — начало жизненного цикла, поэтому его
дрейф инвалидирует ВЕСЬ downstream, а не один вердикт. Это находка, содержащая
в себе устаревший вердикт acceptance, поэтому в объявленном порядке она стоит
раньше — и порядок назван здесь, а не получается случайно.

Роль вердикта связывается с artifact ОТБРАСЫВАНИЕМ суффикса роли, и это
единственное место, где связь выводится из имени. Вывод из имени в этом корпусе
запрещён как приём (`data-integrity.md`) именно потому, что он молча возвращает
пустоту; здесь он ГРОМКИЙ: роль, которая ни к какому объявленному artifact не
приводится, — собственный отказ испытуемого, а не тихо пропущенная запись.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "hash"

APPROVAL_ROLE_SUFFIX = "-reviewer"
ROOT_ARTIFACT = "acceptance"


def _artifact_of_role(role, known_artifacts):
    if not isinstance(role, str) or not role.endswith(APPROVAL_ROLE_SUFFIX):
        return None
    artifact = role[: -len(APPROVAL_ROLE_SUFFIX)]
    if artifact not in known_artifacts:
        return None
    return artifact


def _coordinates(world):
    """Сводит три координаты по каждому artifact. Читает все три отображения."""
    manifest = world.read_all("manifest_hashes")
    content = world.read_all("content_hashes")
    approvals = world.read_all("approval_bound_subject")

    artifacts = set(manifest) | set(content)
    bound = {}
    for role in sorted(approvals):
        artifact = _artifact_of_role(role, artifacts)
        if artifact is None:
            raise outcome.SelfFailure(
                outcome.SELF_APPROVAL_ROLE_UNRESOLVED,
                "роль вердикта %r не приводится ни к одному объявленному "
                "artifact %s — связь ролью и artifact'ом не установлена, и "
                "молча пропустить запись значило бы не проверить вердикт"
                % (role, sorted(artifacts)),
            )
        bound.setdefault(artifact, []).append(approvals[role])
    return {
        "manifest": manifest,
        "content": content,
        "bound": bound,
        "artifacts": artifacts,
    }


def _manifest_hash_is_the_outlier(world):
    """Манифест назвал отпечаток, которого нет ни у содержимого, ни у вердикта."""
    coordinates = _coordinates(world)
    for artifact in sorted(coordinates["artifacts"]):
        declared = coordinates["manifest"].get(artifact)
        actual = coordinates["content"].get(artifact)
        if declared == actual:
            continue
        if declared in coordinates["bound"].get(artifact, []):
            # Манифест согласен с вердиктом — в стороне содержимое, а это
            # предмет других правил этого же семейства.
            continue
        return True
    return False


def _acceptance_drift_invalidates_downstream(world):
    """Содержимое корня уехало из-под вердикта, а downstream-вердикты живы."""
    coordinates = _coordinates(world)
    if ROOT_ARTIFACT not in coordinates["artifacts"]:
        return False
    root_content = coordinates["content"].get(ROOT_ARTIFACT)
    root_bound = coordinates["bound"].get(ROOT_ARTIFACT, [])
    if not root_bound or all(subject == root_content for subject in root_bound):
        return False
    downstream = [
        artifact for artifact in coordinates["bound"]
        if artifact != ROOT_ARTIFACT
    ]
    return bool(downstream)


def _approval_bound_to_stale_subject(world):
    """Вердикт привязан к отпечатку, который уже не является содержимым."""
    coordinates = _coordinates(world)
    for artifact in sorted(coordinates["bound"]):
        actual = coordinates["content"].get(artifact)
        for subject in coordinates["bound"][artifact]:
            if subject != actual:
                return True
    return False


def _design_revalidation_is_stale(world):
    """Ревалидация привязана к отпечатку design, который уже сменился.

    Приёмка §3 и §5: initial class-exposure analysis привязан к acceptance и
    переживает правку design; revalidation привязана к design и не переживает.
    Здесь судится только вторая половина — первая принадлежит cg.class.
    """
    digest = world.read("design_content_digest")
    bound_digest = world.read("revalidation_bound_design_hash")
    role = world.read("revalidation_role")
    records = world.read_all("records")
    declared = bool(role) and bool(records)
    return declared and bound_digest != digest


HASH_COORDINATE_KEYS = (
    "manifest_hashes", "content_hashes", "approval_bound_subject",
)
REVALIDATION_KEYS = (
    "design_content_digest", "revalidation_bound_design_hash",
    "revalidation_role", "records",
)

RULES = [
    Rule(
        rule_id="hash.manifest-outlier",
        diagnostic="CG_CONTENT_HASH_MISMATCH",
        category=outcome.CATEGORY_RED,
        subject_keys=HASH_COORDINATE_KEYS,
        requires=HASH_COORDINATE_KEYS,
        predicate=_manifest_hash_is_the_outlier,
        why="§3 manifest hashes обязаны равняться content hashes",
    ),
    Rule(
        rule_id="hash.acceptance-root-drift",
        diagnostic="CG_DOWNSTREAM_STALE_FROM_ACCEPTANCE",
        category=outcome.CATEGORY_RED,
        subject_keys=HASH_COORDINATE_KEYS,
        requires=HASH_COORDINATE_KEYS,
        predicate=_acceptance_drift_invalidates_downstream,
        why="§5 и §9 правка acceptance инвалидирует class exposure, design, "
            "tasks, RED и convergence; находка содержит в себе устаревший "
            "вердикт самого acceptance и потому объявлена раньше него",
    ),
    Rule(
        rule_id="hash.approval-stale",
        diagnostic="CG_APPROVAL_SUBJECT_STALE",
        category=outcome.CATEGORY_RED,
        subject_keys=HASH_COORDINATE_KEYS,
        requires=HASH_COORDINATE_KEYS,
        predicate=_approval_bound_to_stale_subject,
        why="§4 и §9 вердикт связан с конкретным subject digest; новый subject "
            "получает новый artifact, а старый вердикт не переносится",
    ),
    Rule(
        rule_id="hash.design-revalidation-stale",
        diagnostic="CG_DESIGN_REVALIDATION_STALE",
        category=outcome.CATEGORY_RED,
        subject_keys=REVALIDATION_KEYS,
        requires=REVALIDATION_KEYS,
        predicate=_design_revalidation_is_stale,
        why="§3 revalidation хранится по design digest; §5 правка design "
            "инвалидирует revalidation и последующие stages, сохраняя initial "
            "acceptance-bound analysis",
    ),
]
