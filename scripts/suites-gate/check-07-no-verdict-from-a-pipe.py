#!/usr/bin/env python3
"""check-07 — вердикт не берётся из трубы в `grep -q` под pipefail.

ЧТО УТВЕРЖДАЕТ (ws#395). Ни в одном скрипте оболочки ни одного набора нет звена
трубы `… | grep -q …` (равно `--quiet`, `--silent`, `-m`/`--max-count`) там, где
действует `pipefail`.

МЕХАНИКА КЛАССА. `grep -q` выходит на ПЕРВОМ совпадении. Писатель слева получает
сигнал разорванной трубы, и под `pipefail` труба возвращает отказ — ИМЕННО ТОГДА,
КОГДА ИСКОМОЕ НАЙДЕНО. Проверка отвечает «не нашёл» на входе, где нашла. Локально
расхождение часто не воспроизводится (писатель успевает записать всё в буфер
трубы), а на большом входе или на ранере — проявляется. Класс закрыт в продукте
(kacho#658) и оставался здесь. Что он настоящий, а не теоретический, `inject.sh`
доказывает прогоном самой формы, а не ссылкой.

Законные формы — чтение и поиск разведены: `grep -q -- "$образец" "$файл"`,
`grep -q -- "$образец" <<<"$переменная"`, `[[ $x == *образец* ]]`.

ПОСЛАБЛЕНИЕ ОБЪЯВЛЯЕТСЯ НА МЕСТЕ И ИСТЕКАЕТ САМО. Звено, про которое доказано,
что писатель доживает до конца, помечается на той же строке комментарием
`# pipe-safe: <почему>`. Пометка на строке, где такого звена нет, — находка:
послабление, которому нечего прощать, не истечёт больше никогда.

ГДЕ ДЕЙСТВУЕТ pipefail. В файле, где исполняемый код включает его (`set -o
pipefail`, `set -euo pipefail` и т.п.), и в подключаемых библиотеках набора
(`_*.sh`): их код исполняется в оболочке подключившей проверки. Файлы без
pipefail перечисляются в переписи отдельным числом — там исход трубы равен исходу
`grep`, и класс не действует.

Читается КОД, а не текст (`scripts/lib/shellcode.py`): форма в комментарии или в
строковом литерале находкой не является. Обход — все отслеживаемые `*.sh` всех
наборов на всех уровнях (перепись `scripts/lib/suites.py`); ноль файлов — VOID.

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
PIPEFAIL = re.compile(r"\bset\s+(?:-[A-Za-z]*o\s+pipefail|-o\s+pipefail|.*\bpipefail\b)")
SAFE = re.compile(r"#\s*pipe-safe:\s*\S")


def early_grep(stage):
    """Звено — grep, выходящий на первом совпадении."""
    words = stage.strip().split()
    while words and ("=" in words[0] and not words[0].startswith("-")):
        words = words[1:]          # присваивания окружения перед командой
    if not words or words[0] not in ("grep", "egrep", "fgrep"):
        return False
    for w in words[1:]:
        if w == "--":
            break
        if w in ("--quiet", "--silent") or w.startswith("--max-count"):
            return True
        if re.match(r"^-[A-Za-z]+$", w) and ("q" in w or "m" in w):
            return True
        if re.match(r"^-m\d+$", w):
            return True
    return False


def main():
    ws = _lib.root(__file__)
    names, _ = _lib.suite_census(NAME, ws)
    if not names:
        _lib.void(NAME, "наборов scripts/*/run-all.sh в %s нет — осматривать нечего" % ws)
        return 2
    files = []
    for s in names:
        files += [p for p in _lib.S.suite_files(ws, s) if p.endswith(".sh")]
    if not files:
        _lib.void(NAME, "наборов %d, скриптов *.sh в них 0 — осматривать нечего" % len(names))
        return 2

    findings = []
    judged = 0
    without = 0
    forms = 0
    safe_marks = 0
    for rel in files:
        try:
            with open(os.path.join(ws, rel), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            findings.append("%s — не читается: %s" % (rel, exc))
            continue
        raw = text.split("\n")
        code = shellcode.code_lines(text, mask_quotes=True)
        is_lib = os.path.basename(rel).startswith("_")
        if not is_lib and not any(PIPEFAIL.search(c) for _, c in code):
            without += 1
            continue
        judged += 1
        for n, c in code:
            stages = shellcode.pipe_stages(c)
            hit = any(early_grep(st) for st in stages[1:])
            # Пометка — КОММЕНТАРИЙ строки (всё после исполняемой части), а не
            # текст внутри литерала: строка, которая лишь пишет пометку в файл,
            # сама ничего не помечает.
            comment = raw[n - 1][len(c):] if n - 1 < len(raw) else ""
            marked = bool(SAFE.search(comment))
            if marked:
                safe_marks += 1
            if hit:
                forms += 1
                if not marked:
                    findings.append("%s:%d — вердикт из трубы в grep, выходящий на первом "
                                    "совпадении, под pipefail: `%s` — найденное объявится "
                                    "ненайденным; разведи чтение и поиск (`grep -q … <<<\"$x\"`)"
                                    % (rel, n, raw[n - 1].strip()[:120]))
            elif marked:
                findings.append("%s:%d — пометка `pipe-safe` на строке, где трубы в grep нет: "
                                "послабление без предмета не истечёт никогда" % (rel, n))

    _lib.census(NAME, "наборов %d; скриптов *.sh %d, из них под pipefail судимо %d, без "
                "pipefail %d (там исход трубы равен исходу grep); форм «труба в grep -q» %d, "
                "помечено pipe-safe %d; находок %d"
                % (len(names), len(files), judged, without, forms, safe_marks, len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "мест, где найденное может объявиться ненайденным: %d" % len(findings))
        return 1
    _lib.passed(NAME, "в %d скриптах под pipefail вердикт ни разу не берётся из трубы в grep -q"
                % judged)
    return 0


if __name__ == "__main__":
    sys.exit(main())
