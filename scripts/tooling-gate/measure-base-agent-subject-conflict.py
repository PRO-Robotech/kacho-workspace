#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Расхождение базы маршрутизации и тела агента в том, ЧТО агент делает.

ПРЕДМЕТ. База (`.claude/agents/dispatcher.md`) для каждого исполнителя несёт
строку `Когда:` — предметы, ради которых его запускают. Тело того же агента
несёт во frontmatter `НЕ запускать:` — предметы, ради которых его запускать
НЕЛЬЗЯ. Находка — предмет, стоящий в обоих списках: база велит запускать ради
того, ради чего сам агент запрещает себя запускать. Читающий агент выбирает
между двумя инструкциями, и выигрывает последняя прочитанная.

ЕДИНИЦА СЧЁТА — пара (клауза `Когда:`, клауза `НЕ запускать:`) одного агента.
Клаузы — куски строки между `;` и `·`.

ПРИЗНАК СОВПАДЕНИЯ ПРЕДМЕТА — не точная фраза (её не бывает: стороны писаны
разными руками), а пересечение ОСНОВ слов: >= MIN_OVERLAP общих основ длиной
>= 4. Основа получается снятием русского окончания и усечением до 5 знаков.

ПОЛЯРНОСТЬ ОБЯЗАТЕЛЬНА, И БЕЗ НЕЁ ПРИБОР ВРЁТ. Замер 2026-09-21 без неё дал
3 находки, из которых 2 ложные: «нет действующего одобрения» против «есть
действующее одобрение» — это НЕ противоречие, а ровно согласие, записанное с
двух сторон. Стороны совпадают по предмету и расходятся по отрицанию. Поэтому
находкой считается только пара с ОДИНАКОВОЙ чётностью отрицаний.

ТРИ ИСХОДА:
  0 — предмет есть, противоречий нет;
  1 — находки, каждая названа координатой и обеими цитатами;
  2 — ПРЕДМЕТА НЕТ (база без записей либо агенты без `НЕ запускать:`) — это не
      зелёное: «ноль находок» тогда означало бы «ноль прочитанного».

ПОЧЕМУ ЕЩЁ НЕ В `run-all.sh`. На дереве прибор даёт 1 находку —
`acceptance-author`, — и она не чинится, пока владелец не решит, какая из двух
сторон права: основание, на которое ссылается база (§12 «Ролей автора замысла…
НЕ заводим»), в дереве не найдено — ни даты, ни цитаты, ни автора, тогда как
преамбула того же §12 требует источник. Вписать прибор в набор сейчас значит
покрасить ствол на предмете, который решает не оснастка. Провязка — одна строка
в `scripts/tooling-gate/run-all.sh`, и она ставится тем же изменением, что и
правка стороны, признанной неверной.
"""

import glob
import os
import re
import sys

MIN_OVERLAP = 3
STEM_LEN = 5
WS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE_REL = ".claude/agents/dispatcher.md"
AGENTS_GLOB = ".claude/agents/*.md"

SUFFIXES = (
    "ами", "ями", "ого", "его", "ому", "ему", "ыми", "ими", "ать", "ять",
    "ует", "ся", "ов", "ев", "ий", "ый", "ая", "яя", "ое", "ее", "ые", "ие",
    "ам", "ям", "ах", "ях", "ом", "ем", "ой", "ей", "ую", "юю", "ин",
    "ы", "и", "а", "я", "о", "е", "у", "ю", "ь",
)

# Служебные слова: они стоят в обеих половинах почти всегда и предмета не несут.
STOP = set(
    "нужен нужна нужно нужны есть нет или для по на при про уже ещё его их её "
    "там тот та то те это этом этой когда где как что чем чего либо же бы ли "
    "да сам сама само сами быть было были".split()
)

NEG = re.compile(r"(?<![а-яё])(не|нет|без|ни)(?![а-яё])")


def stem(word):
    """Основа слова: снятое окончание, усечение до STEM_LEN."""
    word = word.strip("«»\"'(),.;:!?—–-`*")
    for suffix in SUFFIXES:
        if len(word) > len(suffix) + 3 and word.endswith(suffix):
            word = word[: -len(suffix)]
            break
    return word[:STEM_LEN]


def stems_of(text):
    text = re.sub(r"`[^`]*`", " ", text.lower())
    out = set()
    for word in re.findall(r"[а-яёa-z]{4,}", text):
        if word in STOP:
            continue
        candidate = stem(word)
        if len(candidate) >= 4:
            out.add(candidate)
    return out


def clauses_of(text):
    return [c.strip() for c in re.split(r"[;·]", text) if len(c.strip()) > 8]


def polarity(text):
    return len(NEG.findall(text.lower())) % 2


def read_base(path):
    """Записи базы: имя исполнителя -> строка `Когда:`."""
    entries = {}
    current = None
    fenced = False
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line.lstrip().startswith("```"):
                fenced = not fenced
                continue
            if fenced:
                continue
            head = re.match(r"^### ([a-z][a-z0-9-]*)\s*$", line)
            if head:
                current = head.group(1)
                entries.setdefault(current, "")
                continue
            if current:
                when = re.match(r"^Когда: (.*)$", line)
                if when:
                    entries[current] = when.group(1)
    return entries


FRONTMATTER = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)


def read_agent_forbidden(path):
    """Клаузы `НЕ запускать:` из frontmatter агента."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    matched = FRONTMATTER.match(text)
    if not matched:
        return None
    found = re.search(r"НЕ запускать:(.*?)(?:\.\s|\"\s*$|\n)", matched.group(1), re.S)
    if not found:
        return None
    return found.group(1)


def main():
    base_abs = os.path.join(WS, BASE_REL)
    if not os.path.isfile(base_abs):
        print(f"[VOID] базы нет: {BASE_REL} — предмета нет", file=sys.stderr)
        return 2

    entries = read_base(base_abs)
    agent_files = sorted(glob.glob(os.path.join(WS, AGENTS_GLOB)))

    pairs_checked = 0
    agents_with_both = 0
    agents_total = 0
    findings = []
    skipped = []          # (агент, почему НЕ осмотрен) — печатается поимённо

    for path in agent_files:
        name = os.path.basename(path)[:-3]
        if name == "dispatcher":
            continue
        agents_total += 1
        forbidden_raw = read_agent_forbidden(path)
        when_raw = entries.get(name, "")
        if not when_raw and not forbidden_raw:
            skipped.append((name, "нет ни `Когда:` в базе, ни `НЕ запускать:`"))
            continue
        if not when_raw:
            skipped.append((name, "в базе нет строки `Когда:`"))
            continue
        if not forbidden_raw:
            skipped.append((name, "во frontmatter нет `НЕ запускать:`"))
            continue
        agents_with_both += 1
        for when in clauses_of(when_raw):
            when_stems = stems_of(when)
            when_pol = polarity(when)
            for forbidden in clauses_of(forbidden_raw):
                pairs_checked += 1
                overlap = when_stems & stems_of(forbidden)
                if len(overlap) < MIN_OVERLAP:
                    continue
                if polarity(forbidden) != when_pol:
                    continue
                findings.append((name, when, forbidden, sorted(overlap)))

    # ПЕРЕПИСЬ НАЗЫВАЕТ НЕОСМОТРЕННОЕ ПОИМЁННО. «Находок ноль» без знаменателя
    # обхода читается как утверждение обо ВСЕХ агентах, и разница между «предмет
    # чист» и «предмет не смотрели» пропадает. Поэтому пропущенные перечисляются
    # с причиной, а не сворачиваются в разность двух чисел.
    print(
        f"[CENSUS] base-agent-subject-conflict: записей `### агент` в базе "
        f"{len(entries)}; определений агентов (без диспетчера) {agents_total}, "
        f"из них осмотрено {agents_with_both}, НЕ осмотрено {len(skipped)}; "
        f"пар клауз сверено {pairs_checked}; порог общих основ {MIN_OVERLAP}; "
        f"находок {len(findings)}"
    )
    if skipped:
        print("[CENSUS] НЕ осмотрены (предмета для сверки нет):")
        for name, why in skipped:
            print(f"    {name} — {why}")
    print(
        "[CENSUS] вне обхода по построению: `.claude/backup/**` (архив), тела "
        "агентов вне frontmatter, тексты заданий агентам — последние в дереве "
        "не живут и проверены быть не могут вовсе"
    )

    if agents_with_both == 0 or pairs_checked == 0:
        print(
            "[VOID] base-agent-subject-conflict — ни одной пары клауз не "
            "сверено: у базы нет строк `Когда:` либо у агентов нет "
            "`НЕ запускать:`. «Ноль находок» здесь означало бы «ноль "
            "прочитанного», и это НЕ зелёное",
            file=sys.stderr,
        )
        return 2

    if findings:
        print(
            f"[FAIL] base-agent-subject-conflict — база и тело агента расходятся "
            f"в том, ЧТО агент делает: {len(findings)}"
        )
        for name, when, forbidden, overlap in findings:
            print(f"\n  {name}")
            print(f"    {BASE_REL} `Когда:`        {when}")
            print(f"    .claude/agents/{name}.md `НЕ запускать:`  {forbidden}")
            print(f"    общий предмет (основы): {' '.join(overlap)}")
        print(
            "\n  Правится ОДНА из сторон, и какая — решение владельца, "
            "а не оснастки: у стороны, признанной неверной, обязано быть "
            "основание с датой и цитатой."
        )
        return 1

    print(
        "[PASS] base-agent-subject-conflict — ни один предмет не стоит "
        "одновременно в `Когда:` базы и в `НЕ запускать:` самого агента"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
