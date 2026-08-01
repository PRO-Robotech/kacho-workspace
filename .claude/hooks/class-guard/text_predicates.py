"""Предикаты классов B (shell/Makefile), C (newman), D (YAML), E (markdown),
F (TypeScript) для class-guard.

Почему здесь всюду СНАЧАЛА снимаются комментарии, литералы и тела heredoc:
замер по kacho@5af959db — первая выборка текстового предиката по newman дала
3 комментария из 5 попаданий (60 % ложных), причём комментарии обсуждали УЖЕ
ПОЧИНЕННЫЙ дефект. Предикат, не различающий код и прозу о коде, «подтверждает»
класс, которого в дереве нет, и повторяет ровно ту ошибку, которую ловит
(testing.md §«Гейт на класс» п.4).

Контракт модуля: каждая функция-предикат принимает подготовленный ``Source`` и
возвращает список ``Finding``. Каждая ОБЯЗАНА отметить рассмотренных кандидатов
через ``src.note(<класс>)`` — иначе её ноль неотличим от «ничего не читал».
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Находка
# ---------------------------------------------------------------------------


@dataclass
class Finding:
    cls: str
    title: str
    file: str
    line: int
    symbol: str
    why: str
    fix: str
    section: str


# ---------------------------------------------------------------------------
# Подготовка исходника: код отдельно от прозы
# ---------------------------------------------------------------------------


@dataclass
class Source:
    path: str
    raw: str
    code_lines: list[str]  # 0-based; проза заменена пробелами, номера строк сохранены
    considered: dict[str, int] = field(default_factory=dict)
    declared_skips: list[str] = field(default_factory=list)

    def note(self, cls: str, n: int = 1) -> None:
        self.considered[cls] = self.considered.get(cls, 0) + n

    def declare_skip(self, msg: str) -> None:
        """Объявленный пропуск. Молчаливого пропуска у гейта быть не может:
        неразобранный вход — это факт о входе, и он обязан быть виден."""
        self.declared_skips.append(msg)

    @property
    def code(self) -> str:
        return "\n".join(self.code_lines)

    def each(self):
        for i, ln in enumerate(self.code_lines, start=1):
            yield i, ln


_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_shell(text: str) -> list[str]:
    """Снимает `#`-комментарии (вне кавычек) и ТЕЛА heredoc.

    Тело heredoc — это данные, а не исполняемая часть: сообщение коммита,
    справка, YAML-манифест. Предикат, читающий его как код, найдёт `|| true`
    в тексте справки, объясняющей, почему `|| true` запрещён.
    """
    out: list[str] = []
    pending: list[str] = []  # ожидаемые терминаторы heredoc
    active: str | None = None
    for raw in text.split("\n"):
        if active is not None:
            if raw.strip() == active:
                active = None
            out.append("")
            continue
        line = _strip_hash_outside_quotes(raw)
        for m in _HEREDOC.finditer(line):
            pending.append(m.group(2))
        out.append(line)
        if pending:
            active = pending.pop(0)
    return out


def _strip_hash_outside_quotes(line: str) -> str:
    sq = dq = False
    for i, ch in enumerate(line):
        if ch == "'" and not dq:
            sq = not sq
        elif ch == '"' and not sq:
            dq = not dq
        elif ch == "#" and not sq and not dq and (i == 0 or line[i - 1] in " \t;&|("):
            return line[:i] + " " * (len(line) - i)
    return line


def strip_hash(text: str) -> list[str]:
    """`#`-комментарии для Python/YAML. Плюс, для Python, `//` внутри строковых
    литералов с JS-кодом (newman-кейсы носят JS в питоновских строках, и
    закомментированная там петля — не петля)."""
    return [_strip_hash_outside_quotes(l) for l in text.split("\n")]


_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def strip_c_like(text: str) -> list[str]:
    """Снимает `/* */`, `//` и содержимое строковых литералов у TS/JS."""
    text = _BLOCK_COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)
    out = []
    for line in text.split("\n"):
        res: list[str] = []
        i, n = 0, len(line)
        quote = None
        while i < n:
            ch = line[i]
            if quote:
                res.append(" " if ch != quote else ch)
                if ch == quote and line[i - 1 : i] != "\\":
                    quote = None
                i += 1
                continue
            if ch in "\"'`":
                quote = ch
                res.append(ch)
                i += 1
                continue
            if ch == "/" and line[i + 1 : i + 2] == "/":
                res.append(" " * (n - i))
                break
            res.append(ch)
            i += 1
        out.append("".join(res))
    return out


_FENCE = re.compile(r"^\s*(```|~~~)")


def strip_md(text: str) -> list[str]:
    """Снимает огороженные блоки кода и инлайн-код у markdown: ссылка на норму
    номером строки внутри примера кода — это пример, а не ссылка."""
    out, infence = [], False
    for line in text.split("\n"):
        if _FENCE.match(line):
            infence = not infence
            out.append("")
            continue
        if infence:
            out.append("")
            continue
        out.append(re.sub(r"`[^`]*`", lambda m: " " * len(m.group(0)), line))
    return out


# ---------------------------------------------------------------------------
# B. shell / Makefile
# ---------------------------------------------------------------------------

RUNNER = re.compile(
    r"\b(go\s+test|newman\s+run|newman\b|pytest|ginkgo|golangci-lint\s+run|govulncheck|"
    r"helm\s+test|buf\s+(lint|breaking)|make\s+[a-zA-Z0-9_.-]*(gate|test|newman|e2e|audit|check))"
)
# Роль пути: файл, чья работа — выносить вердикт. Предпосылка предикатов B4/B8/B15
# и она объявлена: вне этой роли те же формы законны.
GATE_ROLE = re.compile(r"(gate|check|assert|audit|verify|run\.sh|/hooks/|\.github/workflows/)", re.I)

# --- B5: авторитет цели -----------------------------------------------------
#
# Имя контекста — ярлык, который выбирает автор kubeconfig. Авторитетом является
# то, что переименованием не подделывается: адрес apiserver'а активного контекста,
# материал CA кластера, адрес, который движок выдаёт про себя сам.
_CLUSTER_IDENTITY = re.compile(
    r"clusters\[[^\]]*\]\.cluster\.server"     # адрес apiserver'а из kubeconfig
    r"|\.cluster\.server\b"
    r"|certificate-authority-data"             # материал CA самого кластера
    r"|kind\s+get\s+kubeconfig"                # адрес, который kind выдаёт про себя
)
# Коммит вместе с настройками, задаваемыми на команду: `git -c user.email=… commit`
# — та же команда, и подстрока «git commit» её не видит.
_GIT_COMMIT = re.compile(r"\bgit\b(\s+-c\s+\S+)*\s+commit\b")

# Окно, в котором ищется авторитет. Выбрано ОКНОМ, а не файлом целиком: файл с
# честным стражем наверху и небрежной сверкой имени внизу иначе оправдывался бы
# первым. Граница объявлена и проверена на дереве — в четырёх законных местах
# авторитет отстоит от имени на 2…9 строк, поэтому 25 берёт их все с запасом и не
# смыкает два независимых стража одного файла (в `deploy/Makefile` они разнесены
# на 51 строку).
_B5_WINDOW = 25


def b_shell(src: Source) -> list[Finding]:
    f: list[Finding] = []
    code = src.code
    role = bool(GATE_ROLE.search(src.path))
    has_pipefail = "pipefail" in code or "PIPESTATUS" in code

    for ln, line in src.each():
        run_m = RUNNER.search(line)

        # B1 — код возврата вердикта теряется в конвейере
        if run_m and re.search(r"[^|]\|[^|]", line):
            src.note("B1")
            if not has_pipefail:
                f.append(Finding(
                    "B1", "код возврата вердикта теряется в конвейере", src.path, ln,
                    line.strip()[:110],
                    "вердикт берётся с ПОСЛЕДНЕГО звена конвейера; упавший прогон, чей вывод "
                    "прошёл через фильтр, печатает успех",
                    "set -o pipefail либо явный exit \"${PIPESTATUS[0]}\"",
                    "verdict-and-landing §«Три категории исхода: зелёный · красный · не выполнилось»",
                ))

        # B2 — `|| true` на команде-вердикте. Форма — само проглатывание; различитель —
        # ЧТО проглочено. Отметка кандидата стоит на форме, поэтому уборочные `|| true`
        # (247 строк в 56 файлах дерева) видны в переписи как оправданные, а не
        # молчаливо отсутствуют.
        if re.search(r"\|\|\s*true\b", line):
            src.note("B2")
            if run_m:
                f.append(Finding(
                    "B2", "отказ вердикта проглочен", src.path, ln, line.strip()[:110],
                    "команда, ради ответа которой шаг существует, не может провалить шаг",
                    "снять `|| true`; уборочные команды — отдельной строкой, где проглатывание законно",
                    "verdict-and-landing §«Три категории исхода: зелёный · красный · не выполнилось»",
                ))

        # B3 — `tail`/`head` уничтожает имя падения. Форма — позиционный срез;
        # различитель — срезан ли вывод ПРОГОНЩИКА.
        if re.search(r"\|\s*(tail|head)\b", line):
            src.note("B3")
            if run_m:
                f.append(Finding(
                    "B3", "имя падения срезано позиционным фильтром", src.path, ln, line.strip()[:110],
                    "вердикт остаётся, а разбор невозможен: срез по позиции не сохраняет ИМЯ упавшего",
                    "писать полный вывод в файл, затем грепать ПО СОДЕРЖАНИЮ (^--- FAIL|^FAIL)",
                    "verdict-and-landing §«Три категории исхода: зелёный · красный · не выполнилось»",
                ))

        # B5 — цель пинится по ИМЕНИ, и авторитета рядом нет.
        #
        # Предикат спрашивает ОТСУТСТВИЕ авторитетной сверки, а не наличие сверки
        # по имени. Первая редакция спрашивала обратное и сработала на 6 кандидатах
        # из 6, из которых 4 законны: они отсеивают по имени ПЕРВЫМ проходом (чтобы
        # дать оператору внятный совет), а решает у них адрес движка ниже — и
        # комментарий прямо над строкой это называет. Отрицательный близнец у той
        # редакции был СИНТЕТИЧЕСКИЙ: фикстура читала только адрес и имени контекста
        # не звала вовсе, тогда как живой код зовёт ОБА. Сопутствующего элемента,
        # который у настоящих данных есть, фикстуре не хватало — и гейт советовал
        # снять ВЕРНУЮ проверку.
        if "current-context" in line:
            src.note("B5")
            lo, hi = max(0, ln - 1 - _B5_WINDOW), ln + _B5_WINDOW
            if not _CLUSTER_IDENTITY.search("\n".join(src.code_lines[lo:hi])):
                f.append(Finding(
                    "B5", "цель пинится по имени контекста, авторитета рядом нет", src.path, ln,
                    line.strip()[:110],
                    "имя контекста — локальный ярлык, который выбирает автор kubeconfig: одноимённый "
                    "контекст уже вёл в другой кластер, и страж пропускал действие туда, куда его не "
                    "пускали. Сверки, которую переименованием не подделать, в пределах "
                    f"{_B5_WINDOW} строк нет",
                    "сверить адрес apiserver'а активного контекста "
                    "(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}') с адресом, "
                    "который движок выдаёт про себя сам (kind get kubeconfig --name …); имя контекста "
                    "оставить первым отсевом ради внятного совета оператору",
                    "code-authoring §«Инвариант и оснастка — это тоже прод-код» → «Гейт / страж сверяет ИМЯ, а не идентичность»",
                ))

        # B6 — гейт посадки читает ОБЪЯВЛЕНИЕ, а не исход.
        #
        # Форма — чтение поля объекта кластера через jsonpath (36 строк дерева);
        # различитель — спрашивают ли им про ПОСАДКУ. Прежняя редакция и отмечала, и
        # решала одним условием, поэтому 31 законное чтение (имя пода, момент старта,
        # материал секрета) в переписи не значилось вовсе, и ноль предиката был
        # неотличим от «ничего не читал». Форму пишем без привязки к позиции флагов:
        # `kubectl -n "$NS" get cm …` — та же команда, а прежний `kubectl\s+get` её
        # не видел.
        if re.search(r"\bkubectl\b.*\bget\b", line) and "jsonpath" in line:
            src.note("B6")
        if re.search(r"\bkubectl\b.*\bget\b\s+(cm|configmap|deploy|deployment|sts|statefulset|ds|daemonset)\b", line) \
           and "jsonpath" in line and re.search(r"(AUTH_MODE|auth_mode|sslmode|SSLMODE|[mM][tT][lL][sS]|production)", line):
            f.append(Finding(
                "B6", "посадка проверена по объявлению, а не по процессу", src.path, ln, line.strip()[:110],
                "настройки через envFrom читаются ОДИН раз при старте: правка объявления не "
                "перекатывает под, и живой процесс остаётся в прежней посадке при зелёном гейте",
                "спрашивать посадку, ОБЪЯВЛЕННУЮ процессом при старте (лог пода), и независимое "
                "подтверждение со стороны БД (pg_stat_ssl); плюс checksum/config на шаблоне пода",
                "gate-authoring §«Гейт читает ИСХОД, а не объявление»",
            ))

        # B7 — состав дерева взят с диска, а не из индекса.
        #
        # Форма — перечисление файлов через `find`; различитель — спрашивают ли им про
        # СОСТАВ (индекс git это знает) или про то, чего индекс не знает вовсе: время
        # правки, размер, удаление. Живой отрицательный близнец в дереве есть —
        # `.claude/hooks/vault-stop-check.sh` спрашивает `find -mmin -60`; прежняя
        # редакция ставила отметку ПОСЛЕ различителя, поэтому близнец в переписи не
        # значился и предикат читался как «3 из 3, оправданных нет».
        if re.search(r"(\$\(\s*find\s|`\s*find\s|^\s*find\s+\S+.*\|\s*(while|xargs))", line):
            src.note("B7")
            if not re.search(r"-(mmin|mtime|newer|size|atime|ctime|delete|exec)\b", line):
                f.append(Finding(
                    "B7", "состав дерева взят с диска, а не из индекса", src.path, ln, line.strip()[:110],
                    "перечисление с диска несёт неотслеживаемое (артефакты сборки, чужие черновики, "
                    "кэш) и молча меняет объём осмотренного между машинами",
                    "состав — из индекса ревизии: `git ls-files`. Каталог соседнего репозитория "
                    "своим индексом не покрыт (в этом дереве `project/` вообще под игнором), "
                    "поэтому у чужого дерева спрашивать его собственный индекс: "
                    "`git -C \"$REPO\" ls-files`; отсутствие там `.git` — отказ гейта, "
                    "а не повод вернуться к обходу диска",
                    "gate-authoring §«Читать исполняемое, а не текст; состав дерева — из индекса git»",
                ))

        # B9 — сторож находит сам себя. Форма — поиск процесса по шаблону командной
        # строки; различитель — крутится ли на нём ОЖИДАНИЕ (разовый `pgrep` в отчёте
        # себя не ловит, потому что ничего не ждёт).
        if re.search(r"\b(pgrep|pkill)\s+(-\w+\s+)*-\w*f", line):
            src.note("B9")
            if re.search(r"\b(until|while)\b", line):
                f.append(Finding(
                    "B9", "сторож находит сам себя", src.path, ln, line.strip()[:110],
                    "шаблон поиска совпадает с командой самого сторожа — условие не станет ложным никогда",
                    "ждать по ЗАХВАЧЕННОМУ идентификатору процесса (PID=$!; kill -0 \"$PID\")",
                    "verdict-and-landing §«Общий клон, изоляция, параллельные писатели»",
                ))

        # B10 — цепочка со сменой каталога. Форма — уход и возврат в одной цепочке;
        # различитель — ЧЬЯ это оболочка. В рецепте Makefile каждая строка исполняется
        # своей, и `cd .. && docker build` смещения не оставляет (6 таких строк в 5
        # файлах дерева) — поэтому отметка стоит на форме, а роль файла решает после.
        if re.search(r"\bcd\s+(?!\.\.|-)\S+.*&&", line) and re.search(r"&&.*\bcd\s+(\.\.|-)", line):
            src.note("B10")
            if src.path.endswith((".sh", ".bash")):
                f.append(Finding(
                    "B10", "возврат из каталога стоит за конъюнкцией", src.path, ln, line.strip()[:110],
                    "падение середины цепочки оставляет рабочий каталог смещённым, и следующие шаги "
                    "исполняются не там, где написано",
                    "подоболочка (cd X && …) либо make -C X",
                    "verdict-and-landing §«Применённое ≠ исходник»",
                ))

        # B11 — обратные кавычки в сообщении коммита. Форма — сообщение, заданное
        # `-m` в двойных кавычках; различитель — есть ли внутри обратная кавычка.
        # `git -c user.email=… commit` — та же команда, поэтому форма пишется регулярным
        # выражением, а не подстрокой «git commit».
        if _GIT_COMMIT.search(line) and re.search(r"-m\s+\"", line):
            src.note("B11")
            if re.search(r"-m\s+\"[^\"]*`", line):
                f.append(Finding(
                    "B11", "обратные кавычки в сообщении коммита исполняются", src.path, ln, line.strip()[:110],
                    "содержимое между обратными кавычками выполняется оболочкой и ИСЧЕЗАЕТ из "
                    "сообщения молча; коммит уходит запушенным с вырезанным идентификатором",
                    "git commit -F - <<'EOF' … EOF; проверить %B до пуша",
                    "verdict-and-landing §«Публичный текст об изменении»",
                ))

        # B14 — величина ожидания
        m = re.search(r"\bsleep\s+(\d+)\b", line)
        if m:
            src.note("B14")
            if int(m.group(1)) > 60:
                f.append(Finding(
                    "B14", "ожидание длиннее бюджета проверки", src.path, ln, line.strip()[:110],
                    f"{m.group(1)}s фиксированного ожидания: проверка перестаёт быть проверкой и "
                    "становится задержкой, а её отказ — неотличим от «не дождались»",
                    "ждать ПРЕДИКАТ (until <условие>) с назначенным сроком, а не время",
                    "measurement-discipline §«Диагностические ходы, экономящие часы»",
                ))

        # B15 — область зелёного сужена. Форма — прогон с сужающим флагом;
        # различитель — РОЛЬ файла. `-short` в локальном ускорителе (`project/kacho`
        # Makefile, цели быстрой петли) законен и живёт в дереве — отметка стоит на
        # форме, чтобы эти строки были видны в переписи как оправданные.
        if "go test" in line and re.search(r"(^|\s)-short(\s|$)", line):
            src.note("B15")
            if role:
                f.append(Finding(
                    "B15", "финальный гейт объявляет зелёное о меньшем", src.path, ln, line.strip()[:110],
                    "-short выключает часть набора; вердикт относится к меньшему, чем читается, и "
                    "регрессия проезжает под словом «зелёный»",
                    "полный прогон в гейте; -short — только в локальном ускорителе",
                    "verdict-and-landing §«Область зелёного — отдельное утверждение»",
                ))

    # B4 — «ноль находок» не отличимо от «ноль прочитанного»
    if role and re.search(r"\bfor\s+\w+\s+in\b", code):
        src.note("B4")
        # Признак переписи — ЧИСЛО рассмотренного, а не любая проверка на пустоту:
        # `-z "$var"` есть почти в каждом скрипте и превратил бы предикат в немой.
        counted = re.search(r"(-gt\s+0|\bcount\b|\bscanned\b|\bexamined\b|\btotal\b|осмотрен|перепись|рассмотрен)", code)
        if not counted:
            f.append(Finding(
                "B4", "перепись осмотренного не заявлена", src.path, 1, "перечисление без счётчика",
                "гейт печатает исход, не назвав, сколько предметов он рассмотрел: «ноль находок» "
                "неотличимо от «ноль прочитанного», и первая же смена расположения делает его немым",
                "счётчик рассмотренного + отказ, когда рассматривать оказалось нечего",
                "gate-authoring §«Гейт заявляет предпосылку и объём осмотренного»",
            ))

    # B8 — гейт грепает сырой текст там, где нужен разбор.
    #
    # Предпосылка (роль файла) объявлена: вне гейта тот же греп законен. Форма —
    # текстовый поиск, ОГРАНИЧЕННЫЙ кодом на Go; различитель — ищут ли им КОДОВЫЙ
    # ТОКЕН (в образце есть `(` или `.`) либо прозаическое слово, которому разбор не
    # нужен. Отметка стоит на форме, чтобы «оправданных нет» означало факт о дереве,
    # а не порядок условий в предикате.
    if role:
        for ln, line in src.each():
            if re.search(r"\bgrep\b", line) and re.search(r"(--include=\*?\.?go|\*\.go|\.go['\"]?\s*$)", line):
                src.note("B8")
                if re.search(r"grep[^|]*[(.]", line):
                    f.append(Finding(
                        "B8", "гейт читает текст там, где нужен разбор", src.path, ln, line.strip()[:110],
                        "поиск по тексту находит своё слово в комментарии, ОБЪЯСНЯЮЩЕМ эту же защиту, "
                        "и остаётся зелёным при снятой защите",
                        "разбор дерева (go/ast) либо go list -deps; текстовый поиск — только вне кода",
                        "gate-authoring §«Читать исполняемое, а не текст; состав дерева — из индекса git»",
                    ))

    # B12 — снятие изменений без охраны. Форма — `git stash` в скрипте; различитель —
    # безусловен ли возврат.
    if "git stash" in code:
        src.note("B12")
        if "stash pop" in code and not re.search(r"(diff\s+--quiet|--porcelain|stash\s+list)", code):
            f.append(Finding(
                "B12", "снятие изменений условно, возврат безусловен", src.path,
                _first(src, "git stash"), "git stash … git stash pop",
                "на чистом дереве снятие МОЛЧА не создаёт записи, а возврат достаёт ЧУЖУЮ — "
                "в общем клоне это вносит соседскую работу в твоё дерево",
                "проверять, что запись создана (git diff --quiet перед; возврат только если создана); "
                "в общем клоне не пользоваться вовсе",
                "verdict-and-landing §«Общий клон, изоляция, параллельные писатели»",
            ))

    # B13 — посев правит отслеживаемое. Форма — скрипт, который сам индексирует и
    # коммитит; различитель — забирает он ВСЁ дерево или названные пути. Подстрока
    # «git commit» форму не покрывает: `git -c user.email=… commit -m init` — та же
    # команда, и именно так она написана в живой фикстуре дерева (`tests/test_helper.bash`),
    # которая как раз индексирует названный путь и служит законным близнецом.
    if _GIT_COMMIT.search(code) and re.search(r"\bgit\s+add\b", code):
        src.note("B13")
        m = re.search(r"git\s+add\s+(-A\b|--all\b|\.\s*$|\.\s)", code)
        if m:
            f.append(Finding(
                "B13", "коммит забирает всё дерево, а не названные пути", src.path,
                _first(src, "git add"), m.group(0).strip(),
                "сорванный посев обнуляет значения в отслеживаемых файлах, и они уезжают в коммит "
                "вместе с полезной правкой — как «побочный эффект», которого никто не называл",
                "перечислить пути явно и проверить их на пустые значения перед коммитом",
                "verdict-and-landing §«git читается артефактом, а не намерением»",
            ))
    return f


def _first(src: Source, needle: str) -> int:
    for ln, line in src.each():
        if needle in line:
            return ln
    return 1


# ---------------------------------------------------------------------------
# C. newman (Python-исходники кейсов)
# ---------------------------------------------------------------------------

_SELF_RETRY = re.compile(r"setNextRequest\(\s*pm\.info\.requestName\s*\)")
_BUSY_WAIT = re.compile(r"while\s*\(\s*Date\.now\(\)\s*-\s*_")
# Курсорный обход — ЗАКОННЫЙ близнец: следующий раунд идёт с новым токеном
# страницы, прогресс гарантирован по построению, ждать нечего. Опрос состояния —
# наоборот, повторяет ОДИН И ТОТ ЖЕ вопрос, и без ожидания петля на 30 итераций
# покрывает доли секунды. В kacho@5af959db единственные 2 петли без ожидания из
# 3534 — именно курсорный обход (iam-authz-grant-check-propagation), поэтому без
# этого различения предикат отчитался бы о дефекте, которого нет.
_CURSOR_ADVANCE = re.compile(r"(nextPageToken|pageToken|page_token)")


def js_view(text: str) -> list[str]:
    """Строки Python-файла, оставляющие ТОЛЬКО содержимое строковых литералов,
    не являющихся docstring'ами.

    Зачем так, а не построчным поиском: newman-кейсы носят JS внутри питоновских
    строк, а рядом лежат docstring'и и комментарии, ОБСУЖДАЮЩИЕ эту же петлю.
    Построчный предикат на kacho@5af959db дал 10 попаданий, из которых 8 —
    docstring'и и константы-иголки («вот такую строку мы ищем»). Разбор дерева
    Python оставляет только исполняемую часть; номера строк сохраняются.
    """
    import ast as _ast

    try:
        tree = _ast.parse(text)
    except SyntaxError:
        return []  # вход не разобрался — вызывающий объявит пропуск
    doc_nodes: set[int] = set()
    for node in _ast.walk(tree):
        if isinstance(node, (_ast.Module, _ast.FunctionDef, _ast.AsyncFunctionDef, _ast.ClassDef)):
            body = getattr(node, "body", [])
            if body and isinstance(body[0], _ast.Expr) and isinstance(body[0].value, _ast.Constant) \
               and isinstance(body[0].value.value, str):
                doc_nodes.add(id(body[0].value))
    lines = [""] * (len(text.split("\n")) + 1)
    for node in _ast.walk(tree):
        if not isinstance(node, _ast.Constant) or not isinstance(node.value, str):
            continue
        if id(node) in doc_nodes:
            continue
        ln = getattr(node, "lineno", 0)
        if 0 < ln < len(lines):
            lines[ln] = (lines[ln] + " " + node.value.replace("\n", " ")).strip()
    return lines[1:]


def c_newman(src: Source, from_json: bool = False) -> list[Finding]:
    """C1 — самоповтор без реального ожидания.

    Исполнитель вызывает переход СИНХРОННО, до любого отложенного вызова, поэтому
    занятое ожидание — единственный способ реально разнести раунды.
    """
    if from_json:
        lines = src.raw.split("\n")  # JSON комментариев не имеет: сырой текст И ЕСТЬ код
    else:
        lines = js_view(src.raw)
        if not lines:
            src.declare_skip(f"C1 не прогнан: {src.path} не разобрался как Python")
            return []
    f: list[Finding] = []
    for i, line in enumerate(lines):
        if not _SELF_RETRY.search(line):
            continue
        # Литерал, который лишь НАЗЫВАЕТ вызов («иголка» генератора), исполняемым
        # кодом не является: у исполняемого рядом стоит терминатор оператора.
        if not from_json and ";" not in line:
            continue
        src.note("C1")
        window = "\n".join(lines[max(0, i - 4): i + 1])
        if _BUSY_WAIT.search(window):
            continue
        if _CURSOR_ADVANCE.search(window):
            continue
        f.append(Finding(
            "C1", "самоповтор без реального ожидания", src.path, i + 1, line.strip()[:110],
            "исполнитель вызывает переход СИНХРОННО, до любого отложенного вызова: петля на "
            "30 итераций покрывает доли секунды вместо секунд, и «поллер сдался» читается как "
            "отказ предмета, хотя проба вообще не ждала",
            "занятое ожидание НЕПОСРЕДСТВЕННО перед переходом; величину размерять от cap петли "
            "(30000/cap, зажать в 100..500 мс), а не константой",
            "gate-authoring §«Вход гейта детерминирован; часы пробы управляемы» · testing.md §«Newman e2e»",
        ))
    return f


# ---------------------------------------------------------------------------
# D. YAML
# ---------------------------------------------------------------------------


def d_yaml(src: Source, yaml_mod) -> list[Finding]:
    f: list[Finding] = []

    # D1 — дублирующийся ключ в ОДНОМ маппинге: побеждает второй, и дифф этого не
    # показывает. Предпосылка предиката — что вход вообще является YAML.
    if yaml_mod is None:
        src.declare_skip("D1 не прогнан: разборщик YAML недоступен")
    elif re.search(r"\{\{|\{%", src.raw):
        # Шаблон — не YAML. Это НАСТРОЙКА входа, а не сбой, и она объявляется.
        src.declare_skip(f"D1 не прогнан: {src.path} — шаблон, YAML-разбором не читается")
    else:
        class DupLoader(yaml_mod.SafeLoader):
            pass

        dups: list[tuple[str, int]] = []

        def _mapping(loader, node, deep=False):
            seen = set()
            for k, _ in node.value:
                key = loader.construct_object(k, deep=deep)
                if isinstance(key, (str, int)) and key in seen:
                    dups.append((str(key), k.start_mark.line + 1))
                seen.add(key)
            return yaml_mod.SafeLoader.construct_mapping(loader, node, deep)

        DupLoader.add_constructor(
            yaml_mod.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _mapping)
        try:
            list(yaml_mod.load_all(src.raw, Loader=DupLoader))
            src.note("D1")
            for key, ln in dups:
                f.append(Finding(
                    "D1", "побеждающее значение не то, что читает глаз", src.path, ln, key,
                    "второй одноимённый ключ в том же маппинге ТИХО побеждает первый; проверка, "
                    "читающая объявление, видит проигравшее значение",
                    "снять дубль; гейт спрашивать про побеждающее значение, а не про наличие ключа",
                    "gate-authoring §«Гейт читает ИСХОД, а не объявление»",
                ))
        except Exception as e:  # noqa: BLE001 — вход не разобрался; это факт о входе
            src.declare_skip(f"D1 не прогнан: {src.path} не разобрался как YAML ({type(e).__name__})")

    # D2 — плавающая зависимость
    for ln, line in src.each():
        if re.search(r"\bimage:\s*\S", line):
            src.note("D2")
            if re.search(r"image:\s*[\"']?[^\s\"']+:latest", line):
                f.append(Finding(
                    "D2", "плавающая зависимость под прибитой предпосылкой", src.path, ln,
                    line.strip()[:110],
                    "движущийся тег делает прогон невоспроизводимым: вердикт относится к образу, "
                    "который завтра будет другим, а перемер сравнит две неизвестные",
                    "прибить версию либо digest (@sha256:…)",
                    "verdict-and-landing §«Применённое ≠ исходник»",
                ))
        if re.search(r"^\s*version:\s*[\"']?[\^~]", line):
            src.note("D2")
            f.append(Finding(
                "D2", "плавающая зависимость под прибитой предпосылкой", src.path, ln,
                line.strip()[:110],
                "диапазон версий резолвится в момент сборки: два прогона одной ревизии дают разное",
                "точная версия зависимости",
                "verdict-and-landing §«Применённое ≠ исходник»",
            ))
    return f


# ---------------------------------------------------------------------------
# E. markdown
# ---------------------------------------------------------------------------

# Форма — ссылка «файл:строка» в прозе; различитель — НА ЧТО она указывает.
# Норма живёт в `.md`, и её номер строки уезжает от первой же правки соседнего
# абзаца. Координата КОДА (`create.go:435`) — наоборот, обязательна:
# measurement-discipline требует называть место находки. Первая редакция не
# различала и дала 306 срабатываний, из которых 302 были правильной практикой; она
# же ставила отметку кандидата ПОСЛЕ различителя, из-за чего 2515 законных координат
# кода в переписи не значились и предикат читался как «4 из 4, оправданных нет».
_ANY_LINE_REF = re.compile(r"\b([A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,6}):(\d{1,5})\b")
_MD_LINE_REF = re.compile(r"\b([A-Za-z0-9_./-]+\.md):(\d{1,5})\b")


def e_markdown(src: Source) -> list[Finding]:
    f: list[Finding] = []
    for ln, line in src.each():
        if not _ANY_LINE_REF.search(line):
            continue
        src.note("E1")
        m = _MD_LINE_REF.search(line)
        if not m:
            continue
        f.append(Finding(
            "E1", "ссылка на норму номером строки", src.path, ln, m.group(0),
            "номер строки устаревает от первой же правки СОСЕДНЕГО абзаца, и ссылка начинает "
            "указывать на другое место, ничем этого не показывая",
            "ссылаться именем раздела — оно переживает правку и читается без открытия файла",
            "gate-authoring §«Норма и границы»",
        ))
    return f


# ---------------------------------------------------------------------------
# F. TypeScript
# ---------------------------------------------------------------------------

# Форма — перехват отказа; различитель — ПУСТО ли тело. Отметка стоит на форме:
# 119 файлов дерева перехватывают отказ и что-то с ним делают, и без этого числа
# ноль предиката неотличим от «ничего не читал».
_ANY_CATCH = re.compile(r"(\.catch\s*\()|(\bcatch\s*(\([^)]*\))?\s*\{)")
_EMPTY_CATCH = re.compile(
    r"(\.catch\(\s*(?:async\s*)?(?:\(\s*\w*\s*\)|\w+)\s*=>\s*\{\s*\}\s*\))"
    r"|(\.catch\(\s*function\s*\([^)]*\)\s*\{\s*\}\s*\))"
    r"|(\bcatch\s*(?:\([^)]*\))?\s*\{\s*\})"
)


def f_typescript(src: Source) -> list[Finding]:
    f: list[Finding] = []
    for ln, line in src.each():
        if not _ANY_CATCH.search(line):
            continue
        src.note("F1")
        m = _EMPTY_CATCH.search(line)
        if not m:
            continue
        f.append(Finding(
            "F1", "мягкий проход не различает настройку и сбой", src.path, ln, m.group(0)[:80],
            "отказ проглочен целиком: постоянная неправильная настройка (адрес неверен, "
            "эндпоинта нет, ответ не того формата) НАВСЕГДА становится штатным режимом, и "
            "«ноль отказов за всю жизнь» выглядит как исправность",
            "различать настройку и сбой: доказательство «по адресу не тот эндпоинт» — громко; "
            "сетевой отказ может сохранить мягкий проход, но обязан нести счётчик",
            "code-authoring §«Чужой ответ: классификация и бюджет» · security.md §«Hardening-инварианты» п.8",
        ))
    return f
