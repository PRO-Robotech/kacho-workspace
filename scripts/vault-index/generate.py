#!/usr/bin/env python3
"""Собирает машинную часть obsidian/kacho/INDEX.md из самого дерева хранилища.

Зачем генератор, а не рукописный список. Рукописный указатель расходится с
деревом молча и ровно в одну сторону: файл заводят, строку в указатель добавить
забывают. Замер 2026-08-05 на рукописной редакции: из 295 записок четырёх
фактических категорий в указателе не упомянуто 112 — 38 % корпуса. При этом
обратная сторона (ссылки указателя резолвятся) была чистой, поэтому проверка
только одной стороны показывала «указатель в порядке».

Генератор снимает класс by construction: перечень выводится из дерева, а
`--check` роняет сборку, когда файл отстал. Рукописная часть указателя — всё,
что вне маркеров, — генератором не трогается.

Единица счёта — файл `*.md`, отслеживаемый git ЛИБО ещё не добавленный, но не
игнорируемый (`git ls-files --cached --others --exclude-standard`). Причина: с
диска читаются и посторонние файлы, из индекса — не читается записка ровно в тот
день, когда её пишут.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

BEGIN = "<!-- GENERATED:vault-index BEGIN — правится генератором, руками не трогать -->"
END = "<!-- GENERATED:vault-index END -->"

VAULT = "obsidian/kacho"

# Машинная часть живёт в СВОЁМ файле, прозаическая — в своём.
#
# Почему разделено (решение 2026-08-18, задачи #215 и #230). Пока обе части
# лежали одним файлом, каждая параллельная линия правила один и тот же перечень,
# и git обязан был спросить, чью версию взять — при том что верного ответа среди
# двух НЕТ ВОВСЕ: верна третья, полученная пересборкой после слияния. Замер на
# синтетике: две ветки от одной базы, по записке в каждой, — слияние падало
# конфликтом; в форме, где конфликта не возникало (записки в разных категориях),
# указатель молча оставался НЕВЕРНЫМ: «Всего» 650 там, где в дереве 651.
#
# Разделение само по себе конфликт не снимает — оно снимает СМЕШЕНИЕ: посадка
# слияния задаётся файлу целиком, поэтому пока в одном файле лежала и проза, и
# перечень, машинной половине нельзя было назначить посадку, не назначив её
# заодно человеческому тексту, где конфликт осмыслен и обязан остаться. Саму
# посадку несёт `.gitattributes` (`merge=union`), а её действенность проверяет
# `scripts/vault-gate/check-05-index-split-holds.sh`.
INDEX_PROSE = f"{VAULT}/INDEX.md"
INDEX_NOTES = f"{VAULT}/INDEX-notes.md"

# Шапка машинного файла — часть генерируемого текста, а не рукописная преамбула.
# Рукописной строки здесь быть не должно: файл слит посадкой `union`, которая
# человеческий текст молча склеила бы обеими версиями.
HEADER = """---
title: "INDEX-notes — перечень записок, собранный из дерева"
category: hub
status: active
tags:
  - hub
  - index
---

# Перечень записок

> [!warning] Файл собран машиной — правки руками не переживут ближайшую пересборку
> Собирает `./scripts/vault-index/generate.py`, сверяет `--check` (гейт
> `vault-gate` `check-04`). Прозаическая часть указателя — [[INDEX]]; правки
> вводного текста идут туда.
"""

# Категории машинной части: каталог → (заголовок, поле группировки, подпись группы).
CATEGORIES = [
    ("resources", "Ресурсы", "domain", "домен"),
    ("rpc", "gRPC-сервисы", "domain", "домен"),
    ("edges", "Рёбра рантайма", "caller_repo", "вызывающий"),
    ("packages", "Пакеты", "repo", "домен"),
    ("KAC", "Журнал работ (KAC)", None, None),
    ("lessons", "Уроки — классы дефектов", None, None),
    ("legacy", "Записки-переходы прежних репозиториев", None, None),
    ("runbooks", "Операционные процедуры", None, None),
    ("docs", "Руководства (эпоха KAC-127)", None, None),
]


def workspace_root() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def tracked_notes(root: str) -> list[str]:
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", f"{VAULT}/*.md"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    # Сам перечень в перепись не входит: иначе его содержимое зависело бы от его
    # же существования, и первая сборка не была бы неподвижной точкой — файла
    # ещё нет, значит записок 654, а сразу после записи их уже 655, и вторая
    # сборка дала бы другой текст. Самоописание тут ничего не сообщает читателю
    # и стоило бы вечной второй пересборки.
    return sorted(set(out) - {INDEX_NOTES})


def frontmatter(path: str) -> dict[str, str]:
    """Плоский разбор скаляров frontmatter. Списки и вложенность не нужны —
    генератору хватает title/category/status/domain, и собственный разбор
    избавляет от зависимости, которой в среде может не оказаться."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return {}
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    fm: dict[str, str] = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if not m:
            continue
        value = m.group(2).strip().strip('"')
        if value:
            fm[m.group(1)] = value
    if "title" not in fm:
        h1 = re.search(r"^#\s+(.+)$", text[end + 4 :], re.M)
        if h1:
            fm["title"] = h1.group(1).strip()
    return fm


# Как читать `status`: три ведра, а не пятнадцать значений. Словарь выведен из
# того, что в корпусе уже используется, — новых синонимов генератор не вводит.
LIVE = {"stable", "active", "done", "implemented"}
HISTORY = {"deprecated", "legacy", "superseded", "removed", "wontfix"}
PLANNED = {"planned", "experimental", "in-progress", "test", "to-do", "reference"}


def bucket(status: str) -> str:
    if status in LIVE:
        return "живо"
    if status in HISTORY:
        return "история"
    if status in PLANNED:
        return "в работе"
    return "—"


def render(root: str) -> str:
    notes = tracked_notes(root)
    by_dir: dict[str, list[tuple[str, dict[str, str]]]] = {}
    for rel in notes:
        parts = rel.split("/")
        sub = parts[2] if len(parts) > 3 else "(корень)"
        by_dir.setdefault(sub, []).append((rel, frontmatter(os.path.join(root, rel))))

    lines: list[str] = [BEGIN, ""]
    lines.append(
        "Ниже — **полный** перечень записок, собранный из дерева хранилища. "
        "Предикат счёта — `git ls-files --cached --others --exclude-standard "
        "'obsidian/kacho/*.md'`; пересобрать — `./scripts/vault-index/generate.py`, "
        "проверить свежесть — `--check`; сам этот файл в перепись не входит. Сколько записок рассмотрено, печатает гейт на каждом прогоне — здесь это число намеренно не записано: хранимое число устаревает молча, измеряемое — нет."
    )
    lines.append("")

    root_items = sorted(by_dir.get("(корень)", []), key=lambda x: x[0])

    # СВОДНЫХ ЧИСЕЛ ЗДЕСЬ НЕТ, и это решение, а не упущение (2026-08-18, #215).
    #
    # Счётчик по категории и «Всего» — единственные строки файла, которые меняет
    # ЛЮБАЯ записка в ЛЮБОЙ категории. Поэтому две линии, никак не пересекавшиеся
    # по предмету, сталкивались на них при каждом слиянии: перечень оказывался
    # либо конфликтным, либо — что хуже — молча неверным. Замер пяти
    # последовательных слияний ствола в ветку на настоящем генераторе: со
    # сводными числами гейт свежести краснел 5 раз из 5, без них — 0 из 5. Строки
    # записок так не сталкиваются: они лежат в разных местах файла, и слияние
    # сводит их само.
    #
    # Перепись не потеряна: её печатает гейт на КАЖДОМ прогоне
    # (`[PASS] … рассмотрено записок N`), и это число всегда свежее любого
    # записанного в текст — потому что оно измеряется, а не хранится.

    for sub, heading, group_key, group_label in CATEGORIES:
        items = [(r, f) for r, f in sorted(by_dir.get(sub, []), key=lambda x: x[0]) if not r.endswith("/README.md")]
        if not items:
            continue
        lines.append(f"### {heading} — `{sub}/`")
        lines.append("")
        if group_key:
            groups: dict[str, list[tuple[str, dict[str, str]]]] = {}
            for rel, fm in items:
                base = os.path.basename(rel)
                key = "витрина категории" if base.startswith(("all-", "_")) else fm.get(group_key, "(не указан)")
                groups.setdefault(key, []).append((rel, fm))
            for gname in sorted(groups):
                lines.append(f"**{group_label}: {gname}**")
                lines.append("")
                lines.append("| Записка | Состояние |")
                lines.append("|---|---|")
                for rel, fm in groups[gname]:
                    link = rel[len(VAULT) + 1 : -3]
                    title = fm.get("title", os.path.basename(link)).replace("|", "\\|")
                    st = fm.get("status", "")
                    lines.append(f"| [[{link}\\|{title}]] | {bucket(st)}{f' ({st})' if st else ''} |")
                lines.append("")
        else:
            lines.append("| Записка | Состояние |")
            lines.append("|---|---|")
            for rel, fm in items:
                link = rel[len(VAULT) + 1 : -3]
                title = fm.get("title", os.path.basename(link)).replace("|", "\\|")
                st = fm.get("status", "")
                lines.append(f"| [[{link}\\|{title}]] | {bucket(st)}{f' ({st})' if st else ''} |")
            lines.append("")

    if root_items:
        lines.append("### Точки входа и полотно — корень хранилища")
        lines.append("")
        lines.append("| Файл | Состояние |")
        lines.append("|---|---|")
        for rel, fm in root_items:
            link = rel[len(VAULT) + 1 : -3]
            title = fm.get("title", link).replace("|", "\\|")
            st = fm.get("status", "")
            lines.append(f"| [[{link}\\|{title}]] | {bucket(st)}{f' ({st})' if st else ''} |")
        lines.append("")

    lines.append(END)
    return HEADER + "\n" + "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="не писать, а упасть, если указатель отстал от дерева")
    ap.add_argument("--outputs", action="store_true",
                    help="напечатать пути, которые этот генератор ПРОИЗВОДИТ, и выйти")
    args = ap.parse_args()

    # Кто производит файл, тот и отвечает на вопрос «производится ли он машинно».
    # Спрашивать об этом перечнем в чужом скрипте значит завести второе место об
    # одном предмете: добавится второй выход — чужой перечень отстанет молча.
    if args.outputs:
        # С 2026-08-18 машинно производится ИМЕННО перечень, а не страница:
        # `INDEX.md` стала прозой и правится человеком, поэтому объявлять её
        # выходом значило бы велеть переписи считать её изменения машинными —
        # то есть списывать со счёта авторскую работу. Ровно тот случай, о
        # котором предупреждает комментарий выше: «добавится второй выход».
        print(f"{INDEX_NOTES}")
        return 0

    # VAULT_GATE_ROOT — тем же способом, что у проверок набора: инъекция гоняет
    # генератор по временному дереву и не трогает рабочее.
    root = os.environ.get("VAULT_GATE_ROOT") or workspace_root()
    notes_path = os.path.join(root, INDEX_NOTES)

    # Ноль записок — НЕ «чисто». Пустая перепись означает, что предмета не
    # нашлось вовсе (каталог переехал, git не отвечает, корень указан не тот), и
    # тогда любое сравнение тривиально сходится: генератор произвёл бы пустой
    # перечень, файл содержал бы пустой перечень, вердикт был бы зелёным. Это и
    # есть «ноль находок», неотличимый от «ноль прочитанного».
    seen = len(tracked_notes(root))
    if seen == 0:
        print(
            f"[VOID] в {root}/{VAULT} не прочитано НИ ОДНОЙ записки — "
            "сверять перечень не с чем; это предпосылка, а не чистое хранилище",
            file=sys.stderr,
        )
        return 2

    new = render(root)

    if args.check:
        try:
            have = open(notes_path, encoding="utf-8").read()
        except OSError:
            # Отсутствие файла — расхождение, а не отсутствие предмета: предмет
            # (записки) прочитан, а его перечня нет. Молчать здесь значило бы
            # зеленеть ровно на удалении машинной половины указателя.
            print(
                f"[FAIL] {INDEX_NOTES} в дереве нет, а записок прочитано {seen} — "
                "пересобрать: ./scripts/vault-index/generate.py",
                file=sys.stderr,
            )
            return 1
        if new != have:
            print(
                f"[FAIL] {INDEX_NOTES} отстал от дерева (прочитано записок {seen}) — "
                "пересобрать: ./scripts/vault-index/generate.py",
                file=sys.stderr,
            )
            return 1
        print(f"[PASS] {INDEX_NOTES} совпадает с деревом — рассмотрено записок {seen}")
        return 0

    os.makedirs(os.path.dirname(notes_path), exist_ok=True)
    open(notes_path, "w", encoding="utf-8").write(new)
    print(f"{INDEX_NOTES} пересобран; записок в дереве {seen}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
