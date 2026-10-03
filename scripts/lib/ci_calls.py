"""ci_calls — вызов скрипта заданием конвейера. ЕДИНСТВЕННЫЙ распознаватель для всех, кто его судит.

ЗАЧЕМ ОДИН. «Конвейер зовёт набор» судили два дома — `scripts/suites-gate/check-04-*`
и `scripts/change-graph-gate/lanes.py` (`check-03`), — и оба искали ПОДСТРОКУ пути в
тексте шага. Круг 1 обошёл обоих четырьмя формами, при которых набор не исполняется
либо его вердикт выброшен: вызов внутри строки `echo "… run-suites.sh …"`, `… || true`,
`continue-on-error: true`, `if: false` у задания. Оба дома молчали одинаково, потому
что устроены одинаково; чинить их по отдельности значило бы завести третий.

ЧТО СЧИТАЕТСЯ ВЫЗОВОМ — и каждое условие называет причину, если не выполнено:
  * путь стоит в ПОЛОЖЕНИИ КОМАНДЫ: первым словом команды (после присваиваний
    окружения) либо аргументом интерпретатора (`bash`/`sh`/`python3` с его
    опциями). Путь аргументом `echo`/`printf` — упоминание, а не вызов, и вызовом
    не является вовсе. Код читается без комментариев и здесь-документов
    (`scripts/lib/shellcode.py`);
  * вердикт вызова ДОХОДИТ до задания: команда не продолжена `||`, `|` (звено не
    последнее — код берётся у последнего), `&` (фон); не под `!`, не условие
    `if`/`while`/`until`. Когда вызов — не последняя команда шага, шаг обязан
    исполняться с `errexit`: оболочка по умолчанию (`bash -e`), `shell: bash` либо
    `sh`, собственная оболочка с `-e`; `set +e` выше вызова это снимает;
  * задание и шаг БЕЗУСЛОВНЫ: `if:` у задания либо шага (любое — условный вызов
    исполняется не всегда, и какое условие «достаточно истинно», распознаватель не
    судит) и `continue-on-error` (кроме явного false) — вызов не засчитывается.

Незасчитанный вызов возвращается С ПРИЧИНОЙ: судящий обязан назвать её находкой, а не
молча считать набор невызванным.

Вызов из python: `from ci_calls import calls; calls(doc, "ci.yaml", rel)` — список
`Call`. Разбор YAML — у вызывающего: он же решает, что делать без разборщика.
"""
import posixpath
import re

import shellcode

INTERPRETERS = ("bash", "sh", "python3", "python")
PREFIXES = ("", "./", "$PWD/", "${PWD}/", "$GITHUB_WORKSPACE/", "${GITHUB_WORKSPACE}/",
            "${{ github.workspace }}/")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Разделители списка команд в МАСКИРОВАННОМ коде (кавычки заменены пробелами).
SEPARATORS = re.compile(r"\|\||&&|\|&|[;|&\n]")


class Call:
    """Одно появление пути в положении команды."""

    def __init__(self, workflow, job, step, args, counted, why):
        self.workflow = workflow
        self.job = job
        self.step = step
        self.args = args
        self.counted = counted
        self.why = why

    @property
    def where(self):
        return "%s/%s" % (self.workflow, self.job)


def _truthy(value):
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    text = str(value).strip()
    return text not in ("false", "False", "${{ false }}", "0", "")


def _unquote(word):
    return word.replace('"', "").replace("'", "")


def _names(word, rel):
    bare = _unquote(word)
    return any(bare == p + rel for p in PREFIXES)


def _words(plain, start, end):
    """Слова оболочки на отрезке [start, end) несмаскированного кода."""
    out = []
    i = start
    while i < end:
        word, j = shellcode.read_word(plain[:end], i)
        if not word or j <= i:
            break
        out.append(word)
        i = j
    return out


def _statements(masked):
    """[(начало, конец, оператор перед, оператор после)] — простые команды кода."""
    out = []
    pos = 0
    before = None
    for m in SEPARATORS.finditer(masked):
        out.append((pos, m.start(), before, m.group(0)))
        before = m.group(0)
        pos = m.end()
    out.append((pos, len(masked), before, None))
    return out


def _errexit(shell_spec):
    """Исполняет ли шаг оболочка с errexit."""
    if shell_spec is None:
        return True                     # по умолчанию на Linux: bash -e {0}
    spec = str(shell_spec).strip()
    if spec in ("bash", "sh"):
        return True                     # bash --noprofile --norc -eo pipefail; sh -e
    words = spec.split()
    return any(re.fullmatch(r"-[A-Za-z]*e[A-Za-z]*", w) for w in words[1:])


def _join_continuations(lines):
    """Строки кода со сведёнными `\\`-переносами: [(текст маскированный, несмаскированный)]."""
    out = []
    mbuf, pbuf = [], []
    for (_, m), (_, p) in lines:
        ms, ps = m.rstrip(), p.rstrip()
        if ms.endswith("\\") and not ms.endswith("\\\\"):
            mbuf.append(ms[:-1] + " ")
            pbuf.append(ps[:-1] + " ")
            continue
        mbuf.append(m)
        pbuf.append(p)
        out.append(("".join(mbuf), "".join(pbuf)))
        mbuf, pbuf = [], []
    if mbuf:
        out.append(("".join(mbuf), "".join(pbuf)))
    return out


def step_calls(run, rel, shell_spec=None):
    """[(аргументы, засчитан, причина)] — появления `rel` в положении команды в `run`."""
    masked_lines = shellcode.code_lines(run, mask_quotes=True)
    plain_lines = shellcode.code_lines(run)
    logical = _join_continuations(list(zip(masked_lines, plain_lines)))
    found = []
    # Непустые простые команды шага по порядку; последняя — её код и есть код шага.
    flat = []
    set_plus_e = []
    for li, (masked, plain) in enumerate(logical):
        for start, end, before, after in _statements(masked):
            if not masked[start:end].strip():
                continue
            flat.append((li, start, end, before, after, masked, plain))
    for idx, (li, start, end, before, after, masked, plain) in enumerate(flat):
        words = _words(plain, start, end)
        if words[:1] == ["set"] and any(re.fullmatch(r"\+[A-Za-z]*e[A-Za-z]*", w)
                                        for w in words[1:]):
            set_plus_e.append(idx)
        lead = []
        while words and ASSIGN.match(words[0]):
            words = words[1:]
        while words and words[0] in ("!", "if", "while", "until", "elif", "then", "do",
                                     "else", "{", "("):
            lead.append(words[0])
            words = words[1:]
        if not words:
            continue
        args = None
        if _names(words[0], rel):
            args = words[1:]
        elif posixpath.basename(words[0]) in INTERPRETERS:
            rest = words[1:]
            while rest and rest[0].startswith("-"):
                rest = rest[1:]
            if rest and _names(rest[0], rel):
                args = rest[1:]
        if args is None:
            continue
        args = [_unquote(a) for a in args]
        why = None
        if lead and lead[-1] in ("!", "if", "while", "until", "elif"):
            why = "вызов под `%s` — его код условие, а не вердикт шага" % lead[-1]
        elif after == "||":
            why = "за вызовом `||` — отказ заменён исходом другой команды"
        elif after in ("|", "|&"):
            why = "вызов — не последнее звено трубы: код шага берётся у последнего"
        elif after == "&":
            why = "вызов в фоне (`&`) — его код не ждёт никто"
        else:
            if idx != len(flat) - 1:
                if not _errexit(shell_spec):
                    why = ("вызов — не последняя команда шага, а оболочка шага `%s` без "
                           "errexit: отказ не остановит шаг" % shell_spec)
                elif any(i < idx for i in set_plus_e):
                    why = ("вызов — не последняя команда шага после `set +e`: отказ не "
                           "остановит шаг")
        found.append((args, why is None, why))
    return found


def calls(doc, workflow, rel):
    """[Call] — все появления `rel` в положении команды в разобранном процессе `doc`."""
    out = []
    if not isinstance(doc, dict):
        return out
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        return out
    wf_shell = ((doc.get("defaults") or {}).get("run") or {}).get("shell") \
        if isinstance(doc.get("defaults"), dict) else None
    for job_id, job in jobs.items():
        if not isinstance(job, dict):
            continue
        job_shell = ((job.get("defaults") or {}).get("run") or {}).get("shell") \
            if isinstance(job.get("defaults"), dict) else None
        job_why = None
        if "if" in job:
            job_why = "у задания `if: %s` — вызов исполняется не всегда" % job["if"]
        elif _truthy(job.get("continue-on-error")):
            job_why = ("у задания `continue-on-error: %s` — красное задания не роняет "
                       "процесс" % job["continue-on-error"])
        for n, step in enumerate(job.get("steps") or [], 1):
            if not isinstance(step, dict) or not isinstance(step.get("run"), str):
                continue
            shell = step.get("shell", job_shell if job_shell is not None else wf_shell)
            step_why = None
            if "if" in step:
                step_why = "у шага `if: %s` — вызов исполняется не всегда" % step["if"]
            elif _truthy(step.get("continue-on-error")):
                step_why = ("у шага `continue-on-error: %s` — красное шага не роняет "
                            "задание" % step["continue-on-error"])
            for args, ok, why in step_calls(step["run"], rel, shell):
                reason = job_why or step_why or why
                out.append(Call(workflow, str(job_id), n, args, ok and reason is None, reason))
    return out
