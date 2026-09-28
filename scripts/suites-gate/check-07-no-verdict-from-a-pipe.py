#!/usr/bin/env python3
"""check-07 — вердикт не берётся из трубы в `grep -q` под pipefail.

ЧТО УТВЕРЖДАЕТ (ws#395). Ни в одном отслеживаемом скрипте оболочки под
`scripts/` нет звена трубы `… | grep -q …` (равно `--quiet`, `--silent`,
`-m`/`--max-count`, `-l`/`-L` и их длинных форм — всё, что выходит на первом
совпадении) там, где действует `pipefail`.

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
расширения не несёт). Перепись печатает, сколько файлов под `scripts/`
отслеживается и сколько из них оболочка; ноль файлов оболочки — VOID.

КОНВЕЙЕР — ЛОГИЧЕСКИЙ, А НЕ СТРОКА. Труба, продолженная на следующую строку
(`… |` в конце строки либо `\\`-перенос), — тот же конвейер: звено `grep -q` на
второй строке построчный разбор не видел бы вовсе (так было с семью местами
`scripts/branch-audit-inject.sh`). Координата находки — строка звена-читателя.

ГДЕ ДЕЙСТВУЕТ pipefail — ВЫВОДИТСЯ, А НЕ ПОДРАЗУМЕВАЕТСЯ:
  * файл, чей исполняемый код включает его (`set -o pipefail`, `set -euo pipefail`
    и т.п.);
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
PIPEFAIL = re.compile(r"\bset\s+(?:-[A-Za-z]*o\s+pipefail|-o\s+pipefail|.*\bpipefail\b)")
SAFE = re.compile(r"#\s*pipe-safe:\s*\S")
SHEBANG = re.compile(r"^#!\s*\S*\b(?:env\s+)?(?:ba|da|k|z)?sh\b")
EARLY_LONG = ("--quiet", "--silent", "--files-with-matches", "--files-without-match")


def early_grep(stage):
    """Звено — grep, выходящий на первом совпадении."""
    words = stage.strip().split()
    while words and ("=" in words[0] and not words[0].startswith("-")):
        words = words[1:]          # присваивания окружения перед командой
    while words and words[0] in ("command", "builtin", "exec"):
        words = words[1:]
    if not words:
        return False
    head = words[0].lstrip("\\")
    if head not in ("grep", "egrep", "fgrep"):
        return False
    for w in words[1:]:
        if w == "--":
            break
        if w in EARLY_LONG or w.startswith("--max-count"):
            return True
        if re.match(r"^-[A-Za-z]+$", w) and any(f in w for f in "qmlL"):
            return True
        if re.match(r"^-m\d+$", w):
            return True
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


def main():
    ws = _lib.root(__file__)
    try:
        tracked = _lib.S.tracked(ws, WALK)
    except _lib.S.CensusUnreadable as exc:
        _lib.void(NAME, "перепись %s не снята: %s" % (WALK, exc))
        return 2
    kinds = {}
    for rel in tracked:
        k = is_shell(ws, rel)
        if k:
            kinds[rel] = k
    shells = sorted(kinds)
    if not shells:
        _lib.void(NAME, "под %s в %s отслеживается файлов %d, оболочки среди них 0 — "
                  "осматривать нечего" % (WALK, ws, len(tracked)))
        return 2

    findings = []
    parsed = {}
    for rel in shells:
        try:
            with open(os.path.join(ws, rel), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            findings.append("%s — не читается: %s" % (rel, exc))
            continue
        masked = shellcode.code_lines(text, mask_quotes=True)
        plain = shellcode.code_lines(text)
        loops = shellcode.loop_words(plain)
        targets, unresolved = set(), []
        for n, c in plain:
            for word in shellcode.sourced_words(c):
                hit = shellcode.resolve_sourced(rel, word, shells, loops)
                if hit:
                    targets.update(hit)
                else:
                    unresolved.append((n, word))
        parsed[rel] = {
            "raw": text.split("\n"),
            "masked": masked,
            "own": any(PIPEFAIL.search(c) for _, c in masked),
            "targets": targets,
            "unresolved": unresolved,
        }

    judged = {r for r, p in parsed.items() if p["own"]}
    why = {r: "own" for r in judged}
    changed = True
    while changed:
        changed = False
        for rel, p in parsed.items():
            for t in p["targets"]:
                if rel in judged and t not in judged and t in parsed:
                    judged.add(t)
                    why[t] = "sourced"
                    changed = True
                if t in parsed and parsed[t]["own"] and rel not in judged:
                    judged.add(rel)
                    why[rel] = "sources-pipefail"
                    changed = True

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
        codes = dict(p["masked"])
        marked_lines = set()
        covered = set()
        for pipeline in shellcode.pipelines(p["masked"]):
            lines = {n for n, _ in pipeline}
            first = min(lines)
            last = max(lines)
            span = set(range(first, last + 1))
            hits = [n for n, st in pipeline[1:] if early_grep(st)]
            marked = [n for n in span
                      if n in codes and SAFE.search(raw[n - 1][len(codes[n]):])]
            marked_lines.update(marked)
            if not hits:
                continue
            covered.update(span)
            for n in hits:
                forms += 1
                if n != first:
                    multiline += 1
                if not marked:
                    findings.append("%s:%d — вердикт из трубы в grep, выходящий на первом "
                                    "совпадении, под pipefail: `%s` — найденное объявится "
                                    "ненайденным; разведи чтение и поиск (`grep -q … <<<\"$x\"`)"
                                    % (rel, n, raw[n - 1].strip()[:120]))
        safe_marks += len(marked_lines)
        for n in sorted(marked_lines - covered):
            findings.append("%s:%d — пометка `pipe-safe` на строке, где трубы в grep нет: "
                            "послабление без предмета не истечёт никогда" % (rel, n))
    # Пометка в файле БЕЗ pipefail — тоже послабление без предмета: класс там не
    # действует, прощать нечего.
    for rel in sorted(set(parsed) - judged):
        p = parsed[rel]
        codes = dict(p["masked"])
        for n, code in codes.items():
            if SAFE.search(p["raw"][n - 1][len(code):]):
                findings.append("%s:%d — пометка `pipe-safe` в файле без pipefail: класс здесь "
                                "не действует, послабление без предмета" % (rel, n))

    by_ext = sum(1 for k in kinds.values() if k == "ext")
    own = sum(1 for r in judged if why[r] == "own")
    inherited = len(judged) - own
    _lib.census(NAME, "под %s отслеживается файлов %d; оболочки %d (*.sh %d, по шебангу %d); "
                "под pipefail судимо %d (своим set %d, подключением %d), без pipefail %d (там "
                "исход трубы равен исходу grep); подключений не разрешено %d; форм «труба в "
                "grep -q» %d (из них многострочных %d), помечено pipe-safe %d; находок %d"
                % (WALK, len(tracked), len(shells), by_ext, len(shells) - by_ext,
                   len(judged), own, inherited, len(parsed) - len(judged), unresolved_n,
                   forms, multiline, safe_marks, len(findings)))
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
