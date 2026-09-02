"""cg.holder — provenance машинного держателя.

Приёмка §7 перечисляет, при наличии чего machine holder вообще eligible:
holder ID и owner · exact executable и predicate · subject/input/output SHA-256 ·
stdout и stderr digest · captured category · evidence coordinate. И тут же
называет, что даёт RED: «Executable true, неизвестная команда, отсутствующее
поле или несовпавший digest».

Отсюда ДВА разных вида находки, и смешивать их нельзя, потому что чинятся они
по-разному:

* **манифест неполон** — держатель не назвал то, чем он является (кто он, чей
  он, чем исполняется, что утверждает, каков был исход, где лежит вывод).
  Здесь предикат спрашивает у мира ОДНУ координату и отвечает по её наличию;
* **манифест разошёлся с содержимым** — держатель назвал отпечаток, которого у
  наблюдаемого содержимого нет. Здесь предикат сравнивает ДВЕ координаты, и
  ответ есть отношение между ними, а не свойство одной.

**Почему держатель, названный `true`, отвергается отдельной диагностикой, хотя
он заодно и незарегистрирован.** `true` — команда, которая не может дать иного
исхода, кроме успеха; держатель на ней зелен by construction и неотличим от
отсутствующего. Это находка о ПРИРОДЕ держателя. Незарегистрированная команда —
находка о его происхождении: она могла бы падать, но её никто не объявлял.
Первая содержит в себе вторую (тривиальная команда в перечне тоже не значится),
поэтому в объявленном порядке она стоит раньше — и порядок назван здесь, а не
получается случайно из порядка выхода.

**Отсутствующее поле читается НЕ ЧЕРЕЗ `requires`.** Соблазн объявить
`requires=("holder.id",)` велик и ведёт ровно в обратную сторону: правило о
пропущенном поле стало бы неприменимым именно на том мире, ради которого
написано, и мир остался бы без вердикта вовсе. Поэтому применимость решает
наличие самого манифеста, а отсутствие поля — предикат.

**Перечень зарегистрированных команд читается ЦЕЛИКОМ, и иначе нельзя.** Ключ
перечня содержит точки (`run.py`), а координата правила записывается точками —
такой ключ по частям не адресуется вовсе (`cglib/world.py`). Да и членство в
перечне есть свойство перечня, а не одной его записи.
"""

from .. import outcome
from ..rules import Rule

FAMILY = "holder"

# Предмет семейства: манифест держателя, наблюдаемое содержимое и перечень
# команд, которые платформа вообще объявляла.
SUBJECT_KEYS = ("holder", "observed_content", "registered_commands")
REQUIRES = SUBJECT_KEYS

# Команда, не способная дать иного исхода, кроме успеха. Держатель на ней
# зелен by construction, поэтому «молчал» и «не мог упасть» на нём неразличимы.
TRIVIAL_EXECUTABLES = frozenset((
    "true", "/bin/true", "/usr/bin/true", ":", "exit 0",
))

# Пустое значение обязано означать «пусто»: словарь отсутствия назван явно,
# чтобы «none» не пришлось угадывать по правдоподобию строки.
ABSENT_MARKERS = (None, "", "none", "—")

REGISTERED_MARKER = "registered"


def _absent(value):
    if value in ABSENT_MARKERS:
        return True
    return isinstance(value, str) and not value.strip()


def _optional(world, path):
    """Значение координаты либо None, если мир её не объявлял.

    Отсутствие координаты чтением не является, потому что читать нечего: факта
    с таким путём в мире нет, и перепись его не ждёт.
    """
    if not world.has(path):
        return None
    return world.read(path)


def _field_missing(field):
    def predicate(world):
        return _absent(_optional(world, "holder.%s" % field))
    return predicate


def _hash_mismatch(field):
    """Предмет — ОТНОШЕНИЕ двух координат, поэтому читаются обе.

    Прочитать одну и ответить «сошлось» нельзя: ответ был бы получен, не
    взглянув на то, с чем сравнивают.
    """
    def predicate(world):
        declared = _optional(world, "holder.%s" % field)
        observed = _optional(world, "observed_content.%s" % field)
        return declared != observed
    return predicate


def _executable_is_trivial(world):
    executable = _optional(world, "holder.executable")
    if _absent(executable):
        # Отсутствующая команда тривиальной не является: её нет вовсе, и это
        # находка о происхождении, которую объявляет следующее правило.
        return False
    return str(executable).strip() in TRIVIAL_EXECUTABLES


def _executable_unregistered(world):
    """Команда обязана значиться в перечне объявленных платформой.

    Перечень потребляется целиком. Отдельно названо, что незаданная команда
    тоже не зарегистрирована, — иначе пустая строка проходила бы как
    объявленная.
    """
    executable = _optional(world, "holder.executable")
    registered = world.read_all("registered_commands")
    if _absent(executable):
        return True
    return registered.get(str(executable).strip()) != REGISTERED_MARKER


def _missing_field_rule(field, diagnostic, human):
    return Rule(
        rule_id="holder.%s-missing" % field.replace("_", "-"),
        diagnostic=diagnostic,
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_field_missing(field),
        why="§7 machine holder eligible только при наличии %s; отсутствующее "
            "поле даёт RED" % human,
    )


def _hash_rule(field, diagnostic, human):
    return Rule(
        rule_id="holder.%s-mismatch" % field.replace("_", "-"),
        diagnostic=diagnostic,
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_hash_mismatch(field),
        why="§7 %s манифеста обязан совпасть с наблюдаемым содержимым; "
            "несовпавший digest даёт RED" % human,
    )


# ОБЪЯВЛЕННЫЙ ПОРЯДОК повторяет §7: чем держатель себя называет (ID, owner) ->
# чем исполняется -> что утверждает -> отпечатки -> исход -> координата вывода.
# Порядок назван здесь, потому что вердикт берётся по ПЕРВОМУ нарушению: на
# тривиальной команде краснеют оба правила об executable, и выбор между ними
# обязан быть объявленным, а не случайным.
RULES = [
    _missing_field_rule("id", "CG_HOLDER_ID_MISSING", "holder ID"),
    _missing_field_rule("owner", "CG_HOLDER_OWNER_MISSING", "holder owner"),
    Rule(
        rule_id="holder.executable-trivial",
        diagnostic="CG_HOLDER_EXECUTABLE_TRIVIAL",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_executable_is_trivial,
        why="§7 executable true даёт RED: держатель на команде, не умеющей "
            "отказать, зелен by construction и неотличим от отсутствующего",
    ),
    Rule(
        rule_id="holder.executable-unregistered",
        diagnostic="CG_HOLDER_EXECUTABLE_UNKNOWN",
        category=outcome.CATEGORY_RED,
        subject_keys=SUBJECT_KEYS,
        requires=REQUIRES,
        predicate=_executable_unregistered,
        why="§7 неизвестная команда даёт RED; находка о тривиальной команде "
            "содержит в себе эту и потому объявлена раньше",
    ),
    _missing_field_rule("predicate", "CG_HOLDER_PREDICATE_MISSING", "predicate"),
    _hash_rule("subject_sha256", "CG_HOLDER_SUBJECT_HASH_MISMATCH",
               "subject SHA-256"),
    _hash_rule("input_sha256", "CG_HOLDER_INPUT_HASH_MISMATCH",
               "input SHA-256"),
    _hash_rule("output_sha256", "CG_HOLDER_OUTPUT_HASH_MISMATCH",
               "output SHA-256"),
    _hash_rule("stdout_digest", "CG_HOLDER_STDOUT_DIGEST_MISMATCH",
               "stdout digest"),
    _hash_rule("stderr_digest", "CG_HOLDER_STDERR_DIGEST_MISMATCH",
               "stderr digest"),
    _missing_field_rule("captured_category", "CG_HOLDER_CATEGORY_MISSING",
                        "captured category"),
    _missing_field_rule("evidence_coordinate",
                        "CG_HOLDER_EVIDENCE_COORDINATE_MISSING",
                        "evidence coordinate"),
]
