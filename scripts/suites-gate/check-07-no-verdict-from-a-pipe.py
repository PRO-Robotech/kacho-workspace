#!/usr/bin/env python3
"""check-07 — вердикт не берётся из трубы в `grep -q` под pipefail.

ЧТО УТВЕРЖДАЕТ (ws#395). Ни в одном отслеживаемом скрипте оболочки под
`scripts/` нет звена трубы `… | grep -q …` (равно `--quiet`, `--silent`,
`-m`/`--max-count`, `-l`/`-L`, их длинных форм и однозначных сокращений длинных —
`--quie`, `--max` — всё, что выходит на первом совпадении) там, где действует
`pipefail`.

ФОРМЫ ЗВЕНА — все законные записи одного устройства (круг 1 нашёл восемь слепых):
grep по пути (`/usr/bin/grep`); под обёрткой, исполняющей команду с тем же stdin
(`env`, `timeout`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `exec`, `time`,
`sudo` — с их опциями и аргументами); в группе (`{ grep -q …; }`, `( grep -q … )`);
под `!` и условием `if`/`while`/`until`; с присваиваниями окружения перед командой.
Разбор связки коротких опций знает опции с аргументом (`-e`, `-f`, `-A`…): `-eq` —
образец «q», а не `-q`. `xargs grep` звеном-читателем не является: `xargs` дочитывает
вход сам. Строка-комментарий и пустая строка после `|` в конце строки звена не
обрывают — оболочка их пропускает.

МЕХАНИКА КЛАССА. `grep -q` выходит на ПЕРВОМ совпадении. Писатель слева получает
сигнал разорванной трубы, и под `pipefail` труба возвращает отказ — ИМЕННО ТОГДА,
КОГДА ИСКОМОЕ НАЙДЕНО. Проверка отвечает «не нашёл» на входе, где нашла. Локально
расхождение часто не воспроизводится (писатель успевает записать всё в буфер
трубы), а на большом входе или на ранере — проявляется. Класс закрыт в продукте
(kacho#658) и оставался здесь. Что он настоящий, а не теоретический, `inject.sh`
доказывает прогоном самой формы, а не ссылкой.

Законные формы — чтение и поиск разведены: `grep -q -- "$образец" "$файл"`,
`grep -q -- "$образец" <<<"$переменная"`, `[[ $x == *образец* ]]`.

ОБХОД — ВСЕ ОТСЛЕЖИВАЕМЫЕ ФАЙЛЫ ОБОЛОЧКИ ПОД `scripts/` (решение диспетчера
2026-09-28), а не только файлы наборов: класс не знает, чей это файл, и прибор
вне наборов (`merge-readiness.sh`, `branch-audit*`, `scripts/hooks/*`) ошибается
так же. Файл оболочки — `*.sh` либо файл с шебангом оболочки (`scripts/hooks/pre-push`
расширения не несёт). Судится и файл ВНЕ `scripts/`, если его подключает файл
обхода: его код исполняется в оболочке подключившего. Перепись печатает, сколько
файлов под `scripts/` отслеживается и сколько из них оболочка; ноль файлов
оболочки — VOID.

ВНЕ ОБХОДА — НЕ СУДИТСЯ, НО СЧИТАЕТСЯ. Остальное дерево (`.claude/hooks`, `tests/`…)
разбирается тем же распознавателем, и отдельная строка переписи называет число
файлов оболочки, файлов под pipefail и непомеченных форм там — по каталогам. Без
неё «находок 0 под scripts/» читалось бы как «класс закрыт в дереве», а форм вне
обхода не видел бы никто: знаменатель называется, а не выпадает молча. Судить их
здесь — значит править файлы других областей; где они закрываются, решает не
этот набор.

КОНВЕЙЕР — ЛОГИЧЕСКИЙ, А НЕ СТРОКА. Труба, продолженная на следующую строку
(`… |` в конце строки либо `\\`-перенос), — тот же конвейер: звено `grep -q` на
второй строке построчный разбор не видел бы вовсе (так было с семью местами
`scripts/branch-audit-inject.sh`). Координата находки — строка звена-читателя.

ГДЕ ДЕЙСТВУЕТ pipefail — ВЫВОДИТСЯ, А НЕ ПОДРАЗУМЕВАЕТСЯ:
  * файл, чей исполняемый код включает его (`set -o pipefail`, `set -euo pipefail`,
    `shopt -so pipefail`, `shopt -s -o pipefail` — `scripts/lib/shellcode.py`,
    `pipefail_switches`); `set +o pipefail` и `shopt -uo pipefail` — ВЫКЛЮЧЕНИЕ,
    а не упоминание: от него до следующего включения звенья не судятся (прежде
    файл с `set +o pipefail` судился как файл под pipefail). Выше первого `set`
    файл судится тоже: функция, объявленная до `set -o pipefail`, зовётся после;
  * файл, ПОДКЛЮЧАЕМЫЙ (`.`/`source`) файлом под pipefail: его код исполняется в
    оболочке подключившего и наследует её режимы. Подключение разрешается в файл
    дерева по слову-аргументу — путь после последней подстановки, от корня
    (`scripts/…`) либо от каталога подключающего; переменная цикла — по словам
    её перечня (`for part in "$HERE"/inject-*.sh; do . "$part"`), глоб — по
    переписи. Прежде признаком «подключаемого» было имя `_*.sh`, и часть
    `rules-gate/inject-07-*.sh`, подключаемая циклом, выпадала из судимых;
  * файл, подключивший файл, который сам включает pipefail: после подключения
    подключивший исполняется под ним.
Выводится до неподвижной точки. Подключение из файла под pipefail, которое не
разрешилось ни в один файл дерева, — НАХОДКА: под каким режимом исполняется
подключаемое, прибор не знает, и «судимо N» было бы неполным молча. Файлы без
pipefail перечисляются в переписи отдельным числом — там исход трубы равен исходу
`grep`, и класс не действует.

ПОСЛАБЛЕНИЕ ОБЪЯВЛЯЕТСЯ НА МЕСТЕ И ИСТЕКАЕТ САМО. Звено, про которое доказано,
что писатель доживает до конца, помечается на строке конвейера комментарием
`# pipe-safe: <почему>`. Пометка на строке, где такого конвейера нет, — находка:
послабление, которому нечего прощать, не истечёт больше никогда.

Читается КОД, а не текст (`scripts/lib/shellcode.py`): форма в комментарии, в
строковом литерале или в здесь-документе находкой не является.

Коды: 0 — формы нет; 1 — находка; 2 — осматривать нечего.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import shellcode  # noqa: E402

NAME = "check-07-no-verdict-from-a-pipe"
WALK = "scripts/"
SAFE = re.compile(r"#\s*pipe-safe:\s*\S")
SHEBANG = re.compile(r"^#!\s*\S*\b(?:env\s+)?(?:ba|da|k|z)?sh\b")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

GREPS = ("grep", "egrep", "fgrep")
# Длинные опции GNU grep: ранние (выход на первом совпадении) и прочие. getopt_long
# принимает ОДНОЗНАЧНЫЙ префикс (`--quie`, `--max`), поэтому сокращение ранней
# опции узнаётся по тому, что оно — префикс ранней и не префикс прочей.
EARLY_LONG = ("quiet", "silent", "max-count", "files-with-matches", "files-without-match")
OTHER_LONG = ("after-context", "basic-regexp", "before-context", "binary", "binary-files",
              "byte-offset", "color", "colour", "context", "count", "dereference-recursive",
              "devices", "directories", "exclude", "exclude-dir", "exclude-from",
              "extended-regexp", "file", "fixed-strings", "group-separator", "help",
              "ignore-case", "include", "initial-tab", "invert-match", "label",
              "line-buffered", "line-number", "line-regexp", "no-filename",
              "no-group-separator", "no-ignore-case", "no-messages", "null", "null-data",
              "only-matching", "perl-regexp", "recursive", "regexp", "text", "version",
              "with-filename", "word-regexp")
ARG_LONG = ("regexp", "file", "after-context", "before-context", "context", "label",
            "binary-files", "directories", "devices", "include", "exclude", "exclude-from",
            "exclude-dir", "group-separator")
SHORT_EARLY = set("qlLm")
SHORT_ARG = set("efABCdD")          # остаток связки либо следующее слово — аргумент
# Обёртки исполняют команду после своих опций с тем же stdin: `env grep -q`,
# `timeout 5 grep -q` — то же звено. (опции с аргументом, позиционных перед командой)
WRAPPERS = {
    "env": ({"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}, 0),
    "timeout": ({"-s", "--signal", "-k", "--kill-after"}, 1),
    "nice": ({"-n", "--adjustment"}, 0),
    "nohup": (set(), 0),
    "stdbuf": ({"-i", "-o", "-e", "--input", "--output", "--error"}, 0),
    "command": (set(), 0),
    "builtin": (set(), 0),
    "exec": ({"-a"}, 0),
    "time": (set(), 0),
    "sudo": ({"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "--user", "--group"}, 0),
}
# Слова, после которых звено продолжается командой: группы и зарезервированные.
LEAD = ("{", "(", "!", "if", "while", "until", "elif")


def grep_is_early(args):
    """Аргументы grep содержат опцию выхода на первом совпадении."""
    i = 0
    while i < len(args):
        w = args[i]
        if w == "--":
            return False
        if w.startswith("--") and len(w) > 2:
            name = w[2:].split("=", 1)[0]
            early = any(o.startswith(name) for o in EARLY_LONG)
            other = any(o.startswith(name) for o in OTHER_LONG)
            if early and not other:
                return True
            if "=" not in w and any(o.startswith(name) for o in ARG_LONG):
                i += 2
                continue
            i += 1
            continue
        if w.startswith("-") and len(w) > 1 and not w[1:].isdigit():
            body = w[1:]
            for j, ch in enumerate(body):
                if ch in SHORT_EARLY:
                    return True
                if ch in SHORT_ARG:
                    if j == len(body) - 1:
                        i += 1          # аргумент — следующее слово
                    break
        i += 1
    return False


def skip_wrapper(head, rest):
    """Слова после обёртки `head`, с которых начинается исполняемая ею команда."""
    argopts, positional = WRAPPERS[head]
    i = 0
    while i < len(rest):
        w = rest[i]
        if head == "env" and ASSIGN.match(w):
            i += 1
            continue
        if w == "--":
            i += 1
            break
        if w.startswith("-") and len(w) > 1:
            i += 2 if ("=" not in w and w in argopts) else 1
            continue
        break
    return rest[i + positional:]


def early_grep(stage):
    """Звено — grep, выходящий на первом совпадении: сам, под обёрткой (`env`,
    `timeout`, `nice`, `stdbuf`, `command`, `exec`, `time`, `sudo`, `nohup`), в группе
    (`{ …; }`, `( … )`), под `!` либо условием `if`/`while`, по пути (`/usr/bin/grep`)."""
    words = stage.split()
    for _ in range(32):
        while words and ASSIGN.match(words[0]):
            words = words[1:]          # присваивания окружения перед командой
        while words and words[0] in LEAD:
            words = words[1:]
        if words and words[0][:1] in "({" and len(words[0]) > 1:
            words = [words[0][1:]] + words[1:]
            continue
        if not words:
            return False
        head = words[0].lstrip("\\").rsplit("/", 1)[-1]
        if head in WRAPPERS:
            if head == "command" and words[1:2] and words[1] in ("-v", "-V"):
                return False           # `command -v` печатает путь, а не исполняет
            words = skip_wrapper(head, words[1:])
            continue
        if head in GREPS:
            return grep_is_early(words[1:])
        return False
    return False


def is_shell(ws, rel):
    if rel.endswith(".sh"):
        return "ext"
    try:
        with open(os.path.join(ws, rel), "rb") as fh:
            first = fh.readline(256).decode("utf-8", "replace")
    except OSError:
        return None
    return "shebang" if SHEBANG.match(first) else None


def active_lines(masked, start):
    """{номер строки: действует ли pipefail} — по порядку текста: состояние меняют
    `set`/`shopt` (`shellcode.pipefail_switches`), действие — со строки после.
    Начало — `start`: у файла под pipefail (своим `set` либо унаследованным) —
    True, чтобы функция, объявленная выше `set -o pipefail` и зовущаяся ниже, не
    выпала из судимых; изъята только область после явного выключения."""
    state = start
    out = {}
    for n, code in masked:
        out[n] = state
        sw = shellcode.pipefail_switches(code)
        if sw:
            state = sw[-1]
    return out


def main():
    ws = _lib.root(__file__)
    try:
        everything = _lib.S.tracked(ws, ".")
    except _lib.S.CensusUnreadable as exc:
        _lib.void(NAME, "перепись дерева не снята: %s" % exc)
        return 2
    tracked = [r for r in everything if r.startswith(WALK)]
    kinds = {}
    for rel in everything:
        k = is_shell(ws, rel)
        if k:
            kinds[rel] = k
    shells = sorted(r for r in kinds if r.startswith(WALK))
    if not shells:
        _lib.void(NAME, "под %s в %s отслеживается файлов %d, оболочки среди них 0 — "
                  "осматривать нечего" % (WALK, ws, len(tracked)))
        return 2
    all_shells = sorted(kinds)

    findings = []
    parsed = {}
    for rel in all_shells:
        try:
            with open(os.path.join(ws, rel), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            if rel.startswith(WALK):
                findings.append("%s — не читается: %s" % (rel, exc))
            continue
        masked = shellcode.code_lines(text, mask_quotes=True)
        plain = shellcode.code_lines(text)
        loops = shellcode.loop_words(plain)
        targets, unresolved = set(), []
        for n, c in plain:
            for word in shellcode.sourced_words(c):
                hit = shellcode.resolve_sourced(rel, word, all_shells, loops)
                if hit:
                    targets.update(hit)
                else:
                    unresolved.append((n, word))
        parsed[rel] = {
            "raw": text.split("\n"),
            "masked": masked,
            "own": any(True in shellcode.pipefail_switches(c) for _, c in masked),
            "targets": targets,
            "unresolved": unresolved,
        }

    # Под pipefail — выводится до неподвижной точки по ВСЕМУ дереву: свой `set`,
    # подключение файлом под pipefail, подключение файла со своим `set`.
    pf = {r for r, p in parsed.items() if p["own"]}
    why = {r: "own" for r in pf}
    changed = True
    while changed:
        changed = False
        for rel, p in parsed.items():
            for t in p["targets"]:
                if rel in pf and t not in pf and t in parsed:
                    pf.add(t)
                    why[t] = "sourced"
                    changed = True
                if t in parsed and parsed[t]["own"] and rel not in pf:
                    pf.add(rel)
                    why[rel] = "sources-pipefail"
                    changed = True
    # Судимо: обход и всё, что обход подключает (код подключённого исполняется в
    # оболочке подключившего, где бы ни лежал файл).
    reach = set(r for r in parsed if r.startswith(WALK))
    frontier = list(reach)
    while frontier:
        r = frontier.pop()
        for t in parsed[r]["targets"]:
            if t in parsed and t not in reach:
                reach.add(t)
                frontier.append(t)
    judged = pf & reach
    outside = sorted(pf - reach)

    def forms_of(rel):
        """[(строка читателя, помечена ли, строки пометок, строки охвата)] для файла."""
        p = parsed[rel]
        active = active_lines(p["masked"], True)
        codes = dict(p["masked"])
        hits, marked_lines, covered = [], set(), set()
        for pipeline in shellcode.pipelines(p["masked"]):
            lines = {n for n, _ in pipeline}
            first, last = min(lines), max(lines)
            span = set(range(first, last + 1))
            marked = [n for n in span
                      if n in codes and SAFE.search(p["raw"][n - 1][len(codes[n]):])]
            marked_lines.update(marked)
            found = [n for n, st in pipeline[1:] if early_grep(st) and active.get(n, True)]
            if not found:
                continue
            covered.update(span)
            for n in found:
                hits.append((n, bool(marked), n != first))
        return hits, marked_lines, covered

    forms = 0
    multiline = 0
    safe_marks = 0
    unresolved_n = 0
    for rel in sorted(judged):
        p = parsed[rel]
        raw = p["raw"]
        for n, word in p["unresolved"]:
            unresolved_n += 1
            findings.append("%s:%d — подключение %s не разрешено ни в один файл оболочки "
                            "дерева: под каким режимом исполняется подключаемое, не "
                            "выводится, и «судимо» было бы неполным молча" % (rel, n, word))
        hits, marked_lines, covered = forms_of(rel)
        for n, marked, multi in hits:
            forms += 1
            multiline += 1 if multi else 0
            if not marked:
                findings.append("%s:%d — вердикт из трубы в grep, выходящий на первом "
                                "совпадении, под pipefail: `%s` — найденное объявится "
                                "ненайденным; разведи чтение и поиск (`grep -q … <<<\"$x\"`)"
                                % (rel, n, raw[n - 1].strip()[:120]))
        safe_marks += len(marked_lines)
        for n in sorted(marked_lines - covered):
            findings.append("%s:%d — пометка `pipe-safe` на строке, где трубы в grep нет "
                            "(под действующим pipefail): послабление без предмета не "
                            "истечёт никогда" % (rel, n))
    # Пометка в файле БЕЗ pipefail — тоже послабление без предмета: класс там не
    # действует, прощать нечего.
    for rel in sorted(set(parsed) - pf):
        if not rel.startswith(WALK):
            continue
        p = parsed[rel]
        codes = dict(p["masked"])
        for n, code in codes.items():
            if SAFE.search(p["raw"][n - 1][len(code):]):
                findings.append("%s:%d — пометка `pipe-safe` в файле без pipefail: класс здесь "
                                "не действует, послабление без предмета" % (rel, n))

    # Вне обхода — не судится, но СЧИТАЕТСЯ: знаменатель назван, а не выпал молча.
    out_forms = {}
    for rel in outside:
        n = sum(1 for _, marked, _ in forms_of(rel)[0] if not marked)
        if n:
            top = "/".join(rel.split("/")[:2]) if rel.count("/") >= 2 else rel.split("/")[0]
            out_forms[top] = out_forms.get(top, 0) + n
    out_shells = sum(1 for r in all_shells if not r.startswith(WALK) and r not in reach)

    by_ext = sum(1 for r in shells if kinds[r] == "ext")
    own = sum(1 for r in judged if why[r] == "own")
    inherited = len(judged) - own
    in_walk_judged = sum(1 for r in judged if r.startswith(WALK))
    _lib.census(NAME, "под %s отслеживается файлов %d; оболочки %d (*.sh %d, по шебангу %d); "
                "под pipefail судимо %d (своим set %d, подключением %d; вне %s, подключённых "
                "обходом, %d), без pipefail %d (там исход трубы равен исходу grep); подключений "
                "не разрешено %d; форм «труба в grep -q» %d (из них многострочных %d), помечено "
                "pipe-safe %d; находок %d"
                % (WALK, len(tracked), len(shells), by_ext, len(shells) - by_ext,
                   len(judged), own, inherited, WALK, len(judged) - in_walk_judged,
                   len(shells) - in_walk_judged, unresolved_n, forms, multiline, safe_marks,
                   len(findings)))
    _lib.census(NAME, "ВНЕ ОБХОДА (вне %s и не подключены из него) — не судится, считается: "
                "файлов оболочки %d, из них под pipefail %d; форм «труба в grep -q» без "
                "пометки %d%s" % (WALK, out_shells, len(outside), sum(out_forms.values()),
                                  " (%s)" % ", ".join("%s %d" % kv for kv in sorted(out_forms.items()))
                                  if out_forms else ""))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "мест, где найденное может объявиться ненайденным или прибор не знает "
                  "режима: %d" % len(findings))
        return 1
    _lib.passed(NAME, "в %d скриптах под pipefail вердикт ни разу не берётся из трубы в grep, "
                "выходящий на первом совпадении" % len(judged))
    return 0


if __name__ == "__main__":
    sys.exit(main())
