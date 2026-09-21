#!/usr/bin/env python3
# АДРЕС ПРАВИЛА И СКИЛА-ПРИВЯЗКИ РЕЗОЛВИТСЯ ТАМ, ГДЕ ОН НАПИСАН.
#
# ЧЕМ ЭТО ОТЛИЧАЕТСЯ ОТ СОСЕДНЕГО check-07, И ПОЧЕМУ ОДНОГО НЕ ХВАТИЛО.
# check-07 судит АДРЕС РАЗДЕЛА (`<файл>.md §«Заголовок»`) и резолвит его ПО
# БАЗОВОМУ ИМЕНИ, считая архив `.claude/backup/` настоящим местом нормы. Решение
# верное для своего предмета: норма переехала, а не исчезла. Но следствие у него
# такое: ссылка на путь корпуса для файла, который лежит в архиве, резолвится у
# него по базовому имени об архивный — и гейт печатает «ВИСИТ 0» о пути, которого
# в дереве нет.
# Замер 2026-09-21: check-07 -> «адресов 379; ВИСИТ 0», при 422 ссылках, чей
# путь или имя скила в дереве не существуют. Ноль был правдой о базовых именах и
# ложью о путях.
#
# ЗДЕСЬ СУДИТСЯ НАПИСАННОЕ. Четыре формы, и все четыре — рабочие адреса, по
# которым читающий пойдёт:
#   `.claude/rules/<имя>.md`      — путь к файлу правила;
#   `Skill rule-<имя>`            — вызов скила-привязки из «Правил по триггеру»;
#   `- rule-<имя>` в `skills:`    — предзагрузка во frontmatter агента;
#   `.claude/skills/rule-<имя>`   — путь к каталогу скила.
# Цель обязана существовать РОВНО ПО ЭТОМУ адресу. Архив целью не считается: его
# файл не грузится (`claudeMdExcludes`) и `Skill` его не откроет, значит ссылка
# туда путём корпуса — не «переехало», а неисполнимо.
#
# ОБЛАСТЬ — ОСНАСТКА, И ГРАНИЦА ОБЪЯВЛЕНА. `.claude/**`, `scripts/**`, корневой
# `CLAUDE.md`: здесь ссылка ОПЕРАТИВНА — по ней пойдёт агент или харнесс.
# `docs/**` и `obsidian/**` не судятся: там ссылка — проза о прошлом, и владелец
# у неё другой (`docs-writer`, `vault-scribe`). Их число ПЕЧАТАЕТСЯ переписью:
# «вне области 0» обязано быть отличимо от «область не читали».
#
# ИСКЛЮЧЕНЫ ПО РОЛИ, С ПЕЧАТЬЮ ЧИСЛА: `.claude/backup/**` (архив называет
# координаты, верные на момент снятия), `inject*` и `prove.sh` (строят дефект
# синтетическими именами `probe.md`, `rule-poddelka` — это ВХОД пробы, а не
# ссылка) и `*-baseline.txt` (строка объявленного долга неотличима по форме от
# вызова скила, и без исключения база считала бы саму себя).
#
# БАЗА ТОЛЬКО СОКРАЩАЕТСЯ, и краснеет в трёх случаях:
#   (1) имя, которого в базе нет, — новая поломка;
#   (2) вхождений больше, чем в базе, — долг вырос;
#   (3) запись базы, которой нечего исключать, — зажило, обязано быть убрано.
# Третье и есть самоистечение: база не переживает свой предмет.
import argparse, collections, pathlib, re, subprocess, sys

RULE_PATH = re.compile(r"\.claude/rules/([A-Za-z0-9_.\-]+)\.md")
SKILL_CALL = re.compile(r"Skill\s+(rule-[A-Za-z0-9_.\-]+)")
SKILL_PATH = re.compile(r"\.claude/skills/(rule-[A-Za-z0-9_.\-]+)")
FM_ITEM = re.compile(r"^\s*-\s+(rule-[A-Za-z0-9_.\-]+)\s*$")

AREA = (".claude/", "scripts/")
OUTSIDE = ("docs/", "obsidian/", "tmp/", "project/")


def tracked(root):
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"],
        capture_output=True, text=True, check=True).stdout.split("\n")
    return [p for p in out if p]


def in_area(p):
    return p == "CLAUDE.md" or p.startswith(AREA)


def excluded(p):
    base = pathlib.PurePath(p).name
    # `*-baseline.txt` исключены ПО РОЛИ, и это не удобство: строка долга
    # `<число> Skill rule-<имя>` синтаксически неотличима от самого
    # вызова скила, и база считала бы СЕБЯ ростом долга на каждое имя — гейт
    # краснел бы ровно оттого, что долг объявлен. Признак обязан исключать себя.
    return (p.startswith(".claude/backup/")
            or base.startswith("inject")
            or base == "prove.sh"
            or base.endswith("-baseline.txt"))


def scan(root, paths):
    """Возвращает список (форма, имя, файл, строка)."""
    refs = []
    files_read = 0
    lines_read = 0
    for rel in paths:
        f = root / rel
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except (OSError, IsADirectoryError):
            continue
        files_read += 1
        lines = text.split("\n")
        lines_read += len(lines)
        # frontmatter агента: `skills:` читается только внутри первого ограждения
        fm = rel.startswith(".claude/agents/") and lines and lines[0].strip() == "---"
        fm_open = fm
        for i, line in enumerate(lines, 1):
            if fm_open and i > 1 and line.strip() == "---":
                fm_open = False
            elif fm_open and i > 1:
                m = FM_ITEM.match(line)
                if m:
                    refs.append(("skills:", m.group(1), rel, i))
            for m in RULE_PATH.finditer(line):
                refs.append(("путь-правила", m.group(1) + ".md", rel, i))
            for m in SKILL_CALL.finditer(line):
                refs.append(("Skill", m.group(1), rel, i))
            for m in SKILL_PATH.finditer(line):
                refs.append(("путь-скила", m.group(1), rel, i))
    return refs, files_read, lines_read


def resolves(root, form, nameref):
    if form == "путь-правила":
        return (root / ".claude" / "rules" / nameref).is_file()
    return (root / ".claude" / "skills" / nameref / "SKILL.md").exists()


def read_baseline(path):
    known = {}
    if not path or not pathlib.Path(path).is_file():
        return known
    for line in pathlib.Path(path).read_text(encoding="utf-8").split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        count, form, nameref = line.split(" ", 2)
        known[(form, nameref)] = int(count)
    return known


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--baseline")
    ap.add_argument("--emit-baseline", action="store_true")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()

    try:
        all_paths = tracked(root)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("[VOID] check-10 — индекс git не читается, состав дерева не выведен", file=sys.stderr)
        return 2

    area = [p for p in all_paths if in_area(p)]
    subject = [p for p in area if not excluded(p)]
    outside = [p for p in all_paths if p.startswith(OUTSIDE)]
    if not subject:
        print("[VOID] check-10 — файлов оснастки не найдено, судить нечего", file=sys.stderr)
        return 2

    refs, files_read, lines_read = scan(root, subject)
    if not refs:
        print("[VOID] check-10 — обход прошёл, но ни одной ссылки на правило или скил "
              "в нём нет: предмета в дереве не осталось", file=sys.stderr)
        return 2

    dangling = [r for r in refs if not resolves(root, r[0], r[1])]
    out_refs, _, _ = scan(root, outside)
    out_dangling = [r for r in out_refs if not resolves(root, r[0], r[1])]

    now = collections.Counter((r[0], r[1]) for r in dangling)
    known = read_baseline(args.baseline)

    if args.emit_baseline:
        for (form, nameref), c in sorted(now.items(), key=lambda x: (x[0][0], x[0][1])):
            print(f"{c} {form} {nameref}")
        return 0

    print(f"[CENSUS] check-10: файлов оснастки {files_read} "
          f"(исключено по роли и архиву {len(area) - len(subject)}); строк {lines_read}; "
          f"ссылок {len(refs)}; висячих {len(dangling)} по {len(now)} именам; "
          f"в объявленном долге {sum(known.values())} по {len(known)}")
    print(f"[CENSUS] check-10: вне области набора (docs/**, obsidian/**, tmp/**, project/**) — "
          f"ссылок {len(out_refs)}, из них висячих {len(out_dangling)}; "
          f"владельцы docs-writer и vault-scribe, гейтом набора не судятся")

    findings = []
    for key, c in sorted(now.items()):
        form, nameref = key
        if key not in known:
            findings.append(f"НОВАЯ ПОЛОМКА: {form} {nameref} — {c} вхождений, в долге не объявлено")
        elif c > known[key]:
            findings.append(f"ДОЛГ ВЫРОС: {form} {nameref} — было {known[key]}, стало {c}")
    for key, c in sorted(known.items()):
        form, nameref = key
        if now.get(key, 0) == 0:
            findings.append(f"ЗАПИСЬ БЕЗ ПРЕДМЕТА: {form} {nameref} — объявлено {c}, "
                            f"в дереве 0; убрать из долга")

    if findings:
        print("[FAIL] check-10 — адрес правила или скила не резолвится там, где написан",
              file=sys.stderr)
        for f in findings:
            print(f"       {f}", file=sys.stderr)
        for form, nameref, rel, i in dangling[:40]:
            if (form, nameref) not in known or now[(form, nameref)] > known.get((form, nameref), 0):
                print(f"       └ {rel}:{i}: {form} {nameref}", file=sys.stderr)
        return 1

    print(f"[PASS] check-10 — новых висячих адресов нет; объявленный долг "
          f"{sum(known.values())} вхождений по {len(known)} именам не вырос")
    return 0


if __name__ == "__main__":
    sys.exit(main())
