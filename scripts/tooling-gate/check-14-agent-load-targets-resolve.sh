#!/usr/bin/env bash
# check-14 — всё, что тело агента велит ЗАГРУЗИТЬ, существует в дереве.
#
# ЗАЧЕМ. 2026-09-20 сжатие корпуса увело 13 процессных правил в `.claude/backup`
# и сняло их переходники. Триггерные таблицы тридцати агентов продолжали звать
# `Skill rule-<имя>`, которого больше нет. НЕСРАБОТАВШАЯ ЗАГРУЗКА НЕ ПЕЧАТАЕТ
# НИЧЕГО: агент шёл дальше без правила и не узнавал об этом. Прожило сутки,
# затронуло 30 агентов из 32 и 156 вхождений. Молчание среды мы не меняем —
# поэтому дерево обязано краснеть ЗА неё.
#
# ТРИ ОСИ:
#   A  `Skill <имя>` -> каталог `.claude/skills/<имя>/SKILL.md` существует;
#   B  `Read .claude/backup/<файл>.md` -> файл существует;
#   C  ОБРАТНАЯ СТОРОНА: скил, которого не зовёт никто и который не стоит ни в
#      одном `skills:`, — находка другого рода. Не «лишний файл»: это правило,
#      до агента не доезжающее, то есть норма без читателя.
#
# ПРЕДПОСЫЛКА. Ноль тел агентов либо ноль имён к загрузке — код 2, а не зелёное:
# «висячих ноль» на нулевом обходе не утверждает ничего.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${KACHO_WS:-$(cd "$SELF_DIR/../.." && pwd)}"
exec python3 - "$WS" <<'PY'
import glob, io, os, re, sys

ws = sys.argv[1]
NAME = "check-14-agent-load-targets-resolve"


def void(msg):
    print(f"[VOID] {NAME} — {msg}", file=sys.stderr)
    sys.exit(2)


bodies = {}
for path in sorted(glob.glob(os.path.join(ws, ".claude/agents/*.md"))):
    bodies[os.path.relpath(path, ws)] = io.open(path, encoding="utf-8").read()
if not bodies:
    void("тел агентов ноль — загружать нечего, обход беспредметен")

SKILL = re.compile(r"`Skill ([a-z0-9][a-z0-9-]*)`")
ARCH = re.compile(r"`Read (\.claude/backup/[A-Za-z0-9._-]+\.md)`")
FM = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)
PRELOAD = re.compile(r"^\s+-\s+([A-Za-z0-9][A-Za-z0-9-]*)\s*$", re.M)
# ТРЕТЬЯ ЗАКОННАЯ ФОРМА ССЫЛКИ — голое имя в обратных кавычках.
# Первый прогон знал только две (`skills:` и `Skill <имя>`) и объявил
# находкой пять экспертных скилов, на которые тела ссылаются именно так.
# Распознаватель, знающий не все формы, не краснеет и не молчит — он лжёт.
BARE = re.compile(r"`([A-Za-z0-9][A-Za-z0-9-]{2,})`")

skill_calls, arch_reads, preloaded = 0, 0, set()
findings = []

for rel, text in bodies.items():
    fm = FM.match(text)
    if fm:
        for name in PRELOAD.findall(fm.group(1)):
            preloaded.add(name)
            if not os.path.isfile(os.path.join(ws, ".claude/skills", name, "SKILL.md")):
                findings.append(
                    f"ПРЕДЗАГРУЗКА НЕ РАЗРЕШАЕТСЯ: {rel} -> skills: {name} — "
                    f"каталога `.claude/skills/{name}/` нет"
                )
    for name in set(SKILL.findall(text)):
        skill_calls += 1
        if not os.path.isfile(os.path.join(ws, ".claude/skills", name, "SKILL.md")):
            findings.append(
                f"ЗАГРУЗКА НЕ РАЗРЕШАЕТСЯ: {rel} -> `Skill {name}` — каталога "
                f"`.claude/skills/{name}/` нет. Вызов молча ничего не сделает, и "
                f"агент продолжит работу БЕЗ этого правила"
            )
    for target in set(ARCH.findall(text)):
        arch_reads += 1
        if not os.path.isfile(os.path.join(ws, target)):
            findings.append(f"ЧТЕНИЕ НЕ РАЗРЕШАЕТСЯ: {rel} -> `Read {target}` — файла нет")

if skill_calls == 0 and arch_reads == 0 and not preloaded:
    void("ни одного имени к загрузке во всех телах — обход беспредметен")

called, mentioned = set(), set()
for text in bodies.values():
    called.update(SKILL.findall(text))
    mentioned.update(BARE.findall(text))

on_disk = {
    os.path.basename(os.path.dirname(p))
    for p in glob.glob(os.path.join(ws, ".claude/skills/*/SKILL.md"))
}
orphan = sorted(on_disk - called - preloaded - mentioned)
for name in orphan:
    findings.append(
        f"СКИЛ БЕЗ ЧИТАТЕЛЯ: `.claude/skills/{name}/` — ни один агент его не "
        f"зовёт и не несёт в `skills:`. Норма, до агента не доезжающая"
    )

print(
    f"[CENSUS] {NAME}: тел агентов {len(bodies)}; имён в `skills:` {len(preloaded)}; "
    f"вызовов `Skill` {skill_calls}; чтений архива {arch_reads}; скилов на диске "
    f"{len(on_disk)}, из них зовут, предзагружают или называют "
    f"{len(on_disk) - len(orphan)}, "
    f"без читателя {len(orphan)}; находок {len(findings)}"
)

if findings:
    print(f"[FAIL] {NAME} — имя, которое тело велит загрузить, не разрешается:")
    for f in findings:
        print(f"    {f}")
    sys.exit(1)

print(
    f"[PASS] {NAME} — все имена к загрузке разрешаются: скилов {len(on_disk)}, "
    f"вызовов {skill_calls}, чтений архива {arch_reads}, без читателя 0"
)
PY
