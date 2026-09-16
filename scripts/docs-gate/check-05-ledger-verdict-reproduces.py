#!/usr/bin/env python3
"""check-05 — ведомость приёмок продукта воспроизводит вердикт КАЖДОЙ записи.

ЗАЧЕМ ЭТА ПРОВЕРКА СУЩЕСТВУЕТ

Приёмки живут здесь, а кодируют под них в дереве продукта, и гейт продукта
прочитать их вердикт не может by construction. Перенос вердикта туда —
`PRO-Robotech/kacho:docs/acceptance-ledger.yaml`: запись говорит, какой вердикт
стоял в шапке приёмки на названной ревизии ЭТОГО дерева.

Утверждение это ничем не держалось. Ведомость объявляла рецептом воспроизведения
НОМЕР СТРОКИ — `sed -n 3p`, — и на записи NLB-4.0 он давал врезку о суперсежении
части VIP-контракта, тогда как состояние стоит девятнадцатой строкой
(`PRO-Robotech/kacho#2664`). Читатель, проверявший запись рецептом, получал не
вердикт; сама запись при этом верную строку НАЗЫВАЛА прозой — то есть рецепт уже
расходился со своей ведомостью, и расхождение было записано словами.

ПОЧЕМУ ПРОВЕРКА ЖИВЁТ ЗДЕСЬ, А НЕ В ДЕРЕВЕ ПРОДУКТА

Распознаватель вердикта один на оба дома приёмок и живёт здесь (`_lib.verdict`).
Второй, заведённый в дереве продукта, был бы вторым местом об одном предмете:
законных написаний шапки больше десятка — метка по-русски и по-английски, с
цитатой и без, двоеточие внутри выделения и снаружи, — и две реализации
разошлись бы молча ровно там, где обе отвечают «вердикт прочитан».

Второе: документы, о которых говорит ведомость, лежат в ЭТОМ дереве. Проверке
нужны оба, и только здесь оба под рукой: своё дерево читается своим git, дерево
продукта — как чужое, стволом (`_lib.monorepo`).

ЧТО ЧИТАЕТСЯ ГДЕ

Ведомость — из СТВОЛА продукта (`_lib.trunk_show`), как и весь второй дом: копия
рядом общая и отстаёт, и прочитанная в ней ведомость отвечает о другом коммите.
Приёмка — из ЭТОГО дерева на ревизии, которую называет сама запись: она может
лежать на ветке ревью, а не в стволе, и это штатно (круг записывает вердикт на
свою ветку). Поэтому читается ревизия, а не ссылка.

ТРЕТЬЯ КАТЕГОРИЯ НАЗВАНА ПОСТРОЧНО, А НЕ СВЁРНУТА В ВЕРДИКТ

Записей у ведомости несколько, и «не выполнилось» бывает у ОДНОЙ из них: ревизия
ветки ревью в этой копии не выложена. Такая запись не находка и в проверенные не
засчитывается — она называется своей строкой, и итог печатает обе величины.
Ноль проверенных при непустой ведомости — VOID, а не проход: «спросить было не у
кого» обязано быть отличимо от «сошлось».

Исходы: 0 — вердикт воспроизведён у каждой проверенной записи; 1 — есть запись,
чей объявленный вердикт распознаватель не воспроизводит; 2 — проверять нечем.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-05-ledger-verdict-reproduces"

# LEDGER — координата ведомости в дереве продукта.
LEDGER = "docs/acceptance-ledger.yaml"


def parse_ledger(text):
    """[(приёмка, вердикт, ревизия)] — записи ведомости.

    Разбор построчный и НАМЕРЕННО без сторонней библиотеки: у набора зависимостей
    нет, а предмет — три скалярных поля записи. Форма ведомости закреплена её
    собственным гейтом в дереве продукта; здесь читаются ровно те поля, о которых
    проверка говорит.
    """
    entries, cur = [], None
    for raw in text.split("\n"):
        line = raw.rstrip()
        stripped = line.strip()
        if stripped.startswith("- acceptance:"):
            if cur:
                entries.append(cur)
            cur = {"acceptance": stripped.split(":", 1)[1].strip(), "verdict": "", "revision": ""}
            continue
        if cur is None:
            continue
        if stripped.startswith("verdict:"):
            cur["verdict"] = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("workspace_revision:"):
            cur["revision"] = stripped.split(":", 1)[1].strip().strip('"')
    if cur:
        entries.append(cur)
    return [(e["acceptance"], e["verdict"], e["revision"]) for e in entries]


def show_here(revision, rel):
    """Содержимое файла ЭТОГО дерева на названной ревизии; None — не прочитано."""
    root = _lib.workspace_root()
    import subprocess
    try:
        return subprocess.run(
            ["git", "-C", root, "show", "%s:%s" % (revision, rel)],
            capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, OSError):
        return None


def main():
    root = _lib.workspace_root()
    repo = _lib.monorepo(root)
    if repo is None:
        _lib.void(NAME, "дерево продукта не найдено (ни KACHO_MONOREPO, ни "
                        "project/kacho) — ведомость приёмок читать не в чем")
        return 2

    prov = _lib.provenance(repo)
    ref = prov["ref"]
    if not ref:
        _lib.void(NAME, "ствол дерева продукта (%s) не резолвится в клоне %s — ведомость "
                        "читать не по чему. Условие создаётся так: git -C %s fetch origin main"
                        % (_lib.TRUNK_REF, repo, repo))
        return 2

    text = _lib.trunk_show(repo, ref, LEDGER)
    if text is None:
        _lib.void(NAME, "ведомость %s в стволе продукта (%s) не прочитана — предмета "
                        "проверки в этом дереве нет" % (LEDGER, _lib.provenance_line(repo, prov)))
        return 2

    entries = parse_ledger(text)
    if not entries:
        _lib.census("%s: ведомость %s прочитана (%d строк), записей в ней 0"
                    % (NAME, LEDGER, len(text.split("\n"))))
        _lib.passed(NAME, "записей ведомости нет, и обход это УСТАНОВИЛ: ведомость "
                          "прочитана целиком")
        return 0

    findings, voids, checked = [], [], 0
    for acceptance, declared, revision in entries:
        rel = "docs/specs/" + acceptance
        doc = show_here(revision, rel)
        if doc is None:
            voids.append("%s @ %s — ревизии в этой копии нет (ветка ревью не выложена?); "
                         "вердикт по записи НЕ вынесен" % (acceptance, revision))
            continue
        got, line = _lib.verdict(doc)
        if got is None:
            voids.append("%s @ %s — вердикт в шапке не объявлен (строка: %s); распознавателю "
                         "нечего воспроизводить" % (acceptance, revision, line or "нет"))
            continue
        checked += 1
        if got != declared:
            findings.append("%s @ %s: ведомость объявляет %r, распознаватель шапки даёт %r "
                            "(строка: %s) — рецепт воспроизведения не воспроизводит вердикт, "
                            "и запись лжёт ровно тому читателю, который её проверяет"
                            % (acceptance, revision, declared, got, line))

    _lib.census("%s: дерево продукта %s; записей ведомости %d; вердикт воспроизведён у %d; "
                "не выполнилось у %d"
                % (NAME, _lib.provenance_line(repo, prov), len(entries), checked, len(voids)))
    for v in voids:
        _lib.census("%s: НЕ ВЫПОЛНИЛОСЬ — %s" % (NAME, v))

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        return 1

    if checked == 0:
        _lib.void(NAME, "ни одна из %d записей не проверена — вердикт выносить не по чему"
                        % len(entries))
        return 2

    _lib.passed(NAME, "вердикт воспроизведён у всех %d проверенных записей из %d"
                      % (checked, len(entries)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
