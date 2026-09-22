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
# ИСКЛЮЧЕНЫ ПО РОЛИ, С ПЕЧАТЬЮ ЧИСЛА — и роль ВЫВОДИТСЯ, а не перечисляется:
#   · `.claude/backup/**` — архив: он называет координаты, верные на момент
#     снятия. Роль объявлена КАТАЛОГОМ, и каталог здесь и есть наблюдаемое.
#   · `*-baseline.txt` — ведомость этого самого долга: её строка
#     `<число> Skill rule-<имя>` синтаксически неотличима от вызова скила, и без
#     исключения база считала бы СЕБЯ ростом долга на каждое имя. Признак обязан
#     исключать себя.
#   · ПРОИЗВОДИТЕЛЬ СИНТЕТИЧЕСКОЙ ФИКСТУРЫ — `builds_fixture_tree()` ниже.
#
# ПОЧЕМУ ПРОИЗВОДИТЕЛЬ БОЛЬШЕ НЕ ПЕРЕЧИСЛЯЕТСЯ ИМЕНАМИ. Здесь стоял закрытый
# список `inject*` и `prove.sh`. Он держался тем, что производители до сих пор
# так назывались, а это не свойство роли, а совпадение имён. 2026-09-21 полоса
# завела производителя ТОЙ ЖЕ РОЛИ под именем `measure-monotonicity.sh`: он
# сажает в своё дерево правило `probe-monotone.md`, гейт прочёл эту координату
# как адрес корпуса и покраснел «НОВАЯ ПОЛОМКА» на фикстуре, правилом не
# являющейся. Список нельзя было дополнить: следующий производитель назвался бы
# третьим именем, и красное пришло бы снова.
#
# НАБЛЮДАЕМОЕ СВОЙСТВО РОЛИ — ТРИ БАРЬЕРА, разобранные в `builds_fixture_tree`:
# файл ИСПОЛНЯЕТСЯ (shebang), он не из домов судимого, и в его ИСПОЛНЯЕМОЙ части
# есть создающий акт над `.claude/` под своим корнем — `mkdir -p "$d/.claude"`,
# `> "$d/.claude/rules/<проба>.md"`, `cp -a "$WS/.claude/rules" "$dir/.claude/"`.
# Обычный файл оснастки `.claude/` только ЧИТАЕТ и АДРЕСУЕТ:
# `RULES_DIR="$WS/.claude/rules"`, `[ -f … ]`,
# `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/…"` — создающего акта в нём нет.
# Ссылка внутри производителя — не адрес, по которому пойдёт читатель, а ВХОД,
# который он же и материализует.
#
# ЧИСЛА ИДУТ С РЕВИЗИЕЙ, ПОТОМУ ЧТО РАСТУТ ОТ САМОЙ ИНЪЕКЦИИ. На голове волны
# 02b3e6f2 создающий акт есть у 12 файлов, и они держат 44 из 359 висячих
# координат; на 153a81a4 тех же координат 45; на этом коммите — 46 из 361.
# Прирост каждый раз один и тот же по природе: у инъекции прибавилось
# синтетическое имя фикстуры. Число без ревизии здесь было бы ложью к следующей
# правке, и ровно поэтому ревизия стоит при КАЖДОМ. Из исключения при этом не
# выпал НИ ОДИН файл, исключавшийся прежде именем: 20 файлов `inject*` и
# `prove.sh` создающего акта не содержат, и висячих координат у них 0 —
# исключение им было не нужно.
#
# ГРАНИЦА ПРИЗНАКА НАЗВАНА ТАКОЙ, КАКАЯ ОНА ЕСТЬ, И ОНА ШИРЕ, ЧЕМ ХОТЕЛОСЬ БЫ.
# Не покрыты ТРИ класса производителей, и все три ошибаются в сторону КРАСНОГО,
# то есть гейт не ослабляют:
#   (1) перечень покрытых форм ЗАМКНУТ — перенаправление, `mkdir`, `cp`-семейство,
#       — и всё, что создаёт иначе, не опознано, хотя роль у него та же. Это не
#       только другой язык: производитель на python с ЯВНЫМ корнем
#       (`open(os.path.join(d, ".claude", …), "w")`, `pathlib.Path(d)/".claude"`)
#       не покрыт — но не покрыт и ОБОЛОЧЕЧНЫЙ, пишущий через `tee`
#       (`printf … | tee "$d/.claude/rules/<проба>.md"`). Перечень расширять НЕ
#       нужно: незакрытая форма краснеет, а не зеленеет;
#   (2) совпадение требует разделителя пути ПЕРЕД `.claude`. Производитель,
#       который сперва зайдёт `cd` в своё дерево и напишет
#       `> .claude/rules/<проба>.md` без корня, неотличим от координаты корпуса —
#       текстом их не различить в принципе;
#   (3) исполняемость берётся по shebang'у; модуль без него, который импортируют
#       и запускают чужим вызовом, роли не получит.
# Исход для всех трёх один и тот же и он дешевле расширения признака: СОБИРАТЬ
# координату фикстуры, а не выписывать её адресом правила.
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


# СОЗДАЮЩИЙ АКТ над деревом `.claude/` под чужим корнем — наблюдаемое свойство
# роли «производитель синтетической фикстуры». Три формы, и все три создают:
#   · перенаправление  `> "$d/.claude/rules/<проба>.md"`, `>> "$d/.claude/…"`;
#   · заведение каталога `mkdir -p "$d/.claude"`;
#   · перенос содержимого `cp`/`mv`/`ln`/`install`/`rsync` в `…/.claude/`.
# Разделитель пути перед `.claude` обязателен: он и есть «корень не наш».
MAKES_TREE = re.compile(r"""(?: >>?\s*"?[^"\s|]*/\.claude/
                             | mkdir\s+(?:-\S+\s+)*"?[^"\s]*/\.claude
                             | \b(?:cp|mv|ln|install|rsync)\b[^\n]*"?[^"\s]*/\.claude/
                             )""", re.X)


COMMENT = re.compile(r"^\s*#")

# РАЗМЕТКА. Формат, а не место: роль производителя ей не выдаётся НИКОГДА —
# см. барьер 2 в `builds_fixture_tree`.
MARKUP = (".md", ".markdown")


def _starts_with_shebang(root, p):
    try:
        with open(root / p, encoding="utf-8", errors="replace") as fh:
            return fh.read(2) == "#!"
    except (OSError, IsADirectoryError):
        return False


def builds_fixture_tree(root, p):
    """Файл САМ создаёт дерево `.claude/` — значит координаты в нём входы, не адреса.

    ТРИ БАРЬЕРА, И КАЖДЫЙ ЗАКРЫВАЕТ СВОЙ СПОСОБ СОЛГАТЬ.

    1. РОЛЬ ЕСТЬ ТОЛЬКО У ТОГО, ЧТО ИСПОЛНЯЕТСЯ. Производитель — файл, который
       ЗАПУСКАЮТ, и который в этом запуске создаёт дерево. Разметка не
       запускается никогда, поэтому держать роль не может в принципе. Признак —
       shebang первой строкой, и он же делает барьер 3 ЗАКОННЫМ: `#` открывает
       комментарий ровно в тех языках, которые так и запускаются. Взят shebang, а
       НЕ бит исполнимости в индексе: `inject-11-*.sh` подключается точкой и
       лежит с правами 100644 — по биту он не производитель, по shebang'у
       производитель, и верно второе. Замер: все 12 производителей дерева несут
       shebang, из 1309 файлов области его несут 138.

    2. РАЗМЕТКА НЕ ЯВЛЯЕТСЯ СКРИПТОМ, ЧТО БЫ НИ СТОЯЛО В ЕЁ ПЕРВОЙ СТРОКЕ. Барьер
       отдельный, и предмет у него отдельный: `#!` в первых двух байтах — не
       доказательство исполнимости, а всего лишь два байта, и разметка их
       подделывает даром. Здесь судится ФОРМАТ ФАЙЛА, а не его место.

       ДО 2026-09-22 ЗДЕСЬ СТОЯЛ ПЕРЕЧЕНЬ КАТАЛОГОВ — `.claude/rules/` и
       `.claude/agents/`, — и это была ровно та форма, которую отменяет вся
       остальная работа: закрытый список имён сменился закрытым списком мест.
       Измерено приёмкой: `.claude/skills/rule-*/SKILL.md` и корневой `CLAUDE.md`
       со строкой запуска и создающим актом РОЛЬ ПОЛУЧАЛИ (код 0), а перепись
       продолжала печатать «домов 50» — файл уходил из-под суда молча, и о
       заведении четвёртого дома не сказало бы ничто. Незащищённого было:
       навыки — 33 файла и 35 адресов, корневой протокол — 3 адреса, прочая
       разметка области — 43 файла и 41 адрес; висячих среди них ноль, поэтому
       ущерба не случилось, но защиты не было вовсе.

       ДОВОД ОТ КОТОРОГО ПРИЗНАК И ВЗЯТ: разметка не запускается НИКОГДА, значит
       держать роль не может В ПРИНЦИПЕ. Это свойство файла, и потому барьер
       закрывает оба прежних дома, навыки, корневой протокол и любой будущий
       пятый — ОДНИМ условием, которое не придётся править при заведении дома.
       Замер: в области 124 файла разметки, и ни один не начинается с `#!`;
       строка запуска встречается только у `.sh` (101), `.py` (36) и одного
       файла без расширения.

    3. ЧИТАЕТСЯ ИСПОЛНЯЕМАЯ ЧАСТЬ, А НЕ ТЕКСТ: строка-комментарий отбрасывается.
       Иначе создающий акт, ПРОЦИТИРОВАННЫЙ в пояснении, давал бы файлу роль — и
       этот самый распознаватель, объясняющий признак примерами, исключил бы СЕБЯ
       (`.claude/rules/testing.md`, gate-reads-code-not-text).

    ЧЕМ ЭТО БЫЛО ДО 2026-09-22 И ПОЧЕМУ ИСПРАВЛЕНО. Барьер 3 стоял ОДИН, и в
    разметке он не значит ничего: `#` там заголовок, а не комментарий, поэтому
    ИСПОЛНЯЕМОЙ ЧАСТЬЮ считалась вся проза. Измерено приёмкой и воспроизведено
    здесь: у агента ломается одна строка `skills:` — код 1, «НОВАЯ ПОЛОМКА»;
    в тот же файл дописывается ОДНА СТРОКА ПРОЗЫ с командой копирования каталога
    правил — код 0, «долг не вырос», а перепись молча падает с 315 по 22 до
    306 по 22. Сломанная привязка правила к агенту при этом жива. Ни один файл
    корпуса и ни один агент под ПРЕЖНИМ признаком — закрытым списком имён —
    исключить себя не мог; дыру открыло именно выведение роли, и закрывают её
    барьеры 1 и 2, а не возврат к списку.
    """
    if pathlib.PurePath(p).suffix.lower() in MARKUP:   # барьер 2
        return False
    try:
        text = (root / p).read_text(encoding="utf-8", errors="replace")
    except (OSError, IsADirectoryError):
        return False
    if not text.startswith("#!"):                       # барьер 1
        return False
    return any(MAKES_TREE.search(line) for line in text.split("\n")
               if not COMMENT.match(line))


def excluded(root, p):
    base = pathlib.PurePath(p).name
    return (p.startswith(".claude/backup/")
            or base.endswith("-baseline.txt")
            or builds_fixture_tree(root, p))


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
    # САМОИМЯ ГЕЙТА ПРИХОДИТ ИЗ ИМЕНИ ЕГО ФАЙЛА, А НЕ ИЗ ЛИТЕРАЛА ЗДЕСЬ.
    # Разборщик общий, зовут его из `check-NN-rule-address-exists-as-written.sh`,
    # и своего номера он знать не может. Вписанный литерал пережил бы
    # переномерацию МОЛЧА: файл с одним номером печатал бы вердикт с другим, и
    # читающий пошёл бы искать гейт, которого в наборе нет. Умолчание — имя
    # ЭТОГО файла: что бы ни напечаталось, это имя существующего файла, а не
    # выдуманное. Признак проверяется переименованием, а не чтением.
    ap.add_argument("--gate", default=pathlib.Path(__file__).stem)
    ap.add_argument("--root", default=".")
    ap.add_argument("--baseline")
    ap.add_argument("--emit-baseline", action="store_true")
    args = ap.parse_args()
    gate = args.gate
    root = pathlib.Path(args.root).resolve()

    try:
        all_paths = tracked(root)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"[VOID] {gate} — индекс git не читается, состав дерева не выведен", file=sys.stderr)
        return 2

    area = [p for p in all_paths if in_area(p)]
    producers = [p for p in area if not p.startswith(".claude/backup/")
                 and not pathlib.PurePath(p).name.endswith("-baseline.txt")
                 and builds_fixture_tree(root, p)]
    # Роль применима не ко всему обходу, и это печатается: разметка её держать не
    # может, поэтому «производителей 0» обязано быть отличимо от «роль некому было
    # выдать». Оба числа ВЫВОДЯТСЯ из свойства файла: перечня каталогов здесь нет,
    # и заведение нового дома правки этой строки не потребует.
    runnable = [p for p in area if pathlib.PurePath(p).suffix.lower() not in MARKUP
                and _starts_with_shebang(root, p)]
    markup = [p for p in area if pathlib.PurePath(p).suffix.lower() in MARKUP]
    subject = [p for p in area if not excluded(root, p)]
    outside = [p for p in all_paths if p.startswith(OUTSIDE)]
    if not subject:
        print(f"[VOID] {gate} — файлов оснастки не найдено, судить нечего", file=sys.stderr)
        return 2

    refs, files_read, lines_read = scan(root, subject)
    if not refs:
        print(f"[VOID] {gate} — обход прошёл, но ни одной ссылки на правило или скил "
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

    # КОРЕНЬ — ПЕРВОЕ ЧИСЛО ПЕРЕПИСИ, А НЕ УМОЛЧАНИЕ. Все прочие величины —
    # утверждения о ДЕРЕВЕ, и без имени дерева они не читаются: два прогона одного
    # файла с разным cwd давали разные числа и оба звались `[PASS]`.
    print(f"[CENSUS] {gate}: корень {root}")
    print(f"[CENSUS] {gate}: файлов оснастки {files_read} "
          f"(исключено по роли и архиву {len(area) - len(subject)}, из них "
          f"производителей синтетического дерева {len(producers)} — признак выведен, "
          f"не перечислен); роль применима к {len(runnable)} скриптам, "
          f"разметке ({len(markup)} файлов) — никогда, чем бы ни начинался файл; "
          f"строк {lines_read}; "
          f"ссылок {len(refs)}; висячих {len(dangling)} по {len(now)} именам; "
          f"в объявленном долге {sum(known.values())} по {len(known)}")
    print(f"[CENSUS] {gate}: вне области набора (docs/**, obsidian/**, tmp/**, project/**) — "
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
        print(f"[FAIL] {gate} — адрес правила или скила не резолвится там, где написан",
              file=sys.stderr)
        for f in findings:
            print(f"       {f}", file=sys.stderr)
        for form, nameref, rel, i in dangling[:40]:
            if (form, nameref) not in known or now[(form, nameref)] > known.get((form, nameref), 0):
                print(f"       └ {rel}:{i}: {form} {nameref}", file=sys.stderr)
        return 1

    print(f"[PASS] {gate} — новых висячих адресов нет; объявленный долг "
          f"{sum(known.values())} вхождений по {len(known)} именам не вырос")
    return 0


if __name__ == "__main__":
    sys.exit(main())
