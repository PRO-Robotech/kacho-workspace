#!/usr/bin/env bash
# skills-gate #07 — объявленное число ИСПОЛНЯЕТСЯ, а не помнится.
#
# ЧТО УТВЕРЖДАЕТ. Каждая процитированная в `.claude/rulebook/ai-tooling.md`
# команда `git …`, рядом с которой стоит объявленное число (`(**N**)` либо
# «**N** … (предикат: `…`)»), ИСПОЛНЯЕТСЯ, и её вывод равен этому числу.
#
# ПОЧЕМУ ГЕЙТ, А НЕ ПРЕДПИСАНИЕ. Абзац, который этот гейт стережёт, сам велит
# «сверяй предикатами, а не памятью» — и за месяц просрочился ТРИЖДЫ: числа
# правил (11→15, 16→3) и агентов (15→16, 16→17). Дважды это чинили правкой
# числа и дописыванием предписания «прогоняй все три предиката разом»; предписание
# не исполнилось ни разу, потому что у него нет производителя — прогнать предикаты
# может только тот, кто о них вспомнил. Число без держателя стареет МОЛЧА: оно не
# краснеет, оно продолжает читаться как факт.
#
# ЧИТАЕТСЯ ИСПОЛНЯЕМОЕ, А НЕ ТЕКСТ. Команда не разбирается по образцу и не
# сравнивается со списком «известных» — она запускается, и сверяется её ВЫВОД.
# Поэтому смена самой команды (другой каталог, другой фильтр) предмета проверки
# не ломает.
#
# ФОРМ ЗАПИСИ ДВЕ, И ОБЕ ОБЯЗАН ЗНАТЬ РАЗБОР. Число стоит либо ПОСЛЕ команды
# (`… | wc -l` (**14**)), либо ПЕРЕД ней («Счёт: **17** … (предикат: `…`)»).
# Форма, которой разбор не знает, даёт не красное и не зелёное, а МОЛЧАНИЕ —
# поэтому цитата, оказавшаяся вне разбираемой формы, объявляется отдельной
# строкой переписи, а не пропускается.
#
# ПЕРЕНОС СТРОКИ РАЗБОРУ НЕ МЕШАЕТ: пара ищется по соседству ТОКЕНОВ, а не
# построчно. Разделять их разрешено чем угодно, кроме пустой строки, другого
# токена и шестидесяти знаков — иначе в один абзац попали бы четыре команды и
# четыре числа, и пары составились бы наугад.
#
# ЧТО ИСПОЛНЯЕТСЯ — СУЖЕНО СПИСКОМ. Цитата обязана иметь форму `git <подкоманда>`
# с конвейером только из `cut`/`sort`/`grep`/`uniq`/`wc`; знаки подстановки,
# перенаправления и `;`/`&&` запрещены. Документ не должен становиться местом,
# откуда исполняется что угодно, а цитата вне этой формы — находка, а не
# молчание: её разбирает человек.
#
# ПРЕДПОСЫЛКА ГЕЙТА (проверяется здесь же). Основание — что в файле вообще есть
# процитированные команды и хотя бы одна пара. Ноль того или другого — VOID, а
# не успех: «ноль расхождений» и «ноль прочитанного» обязаны различаться.
#
# Коды выхода: 0 — все объявленные числа сошлись; 1 — расхождение либо цитата
# вне разбираемой формы; 2 — VOID.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(skills_gate_workspace_root)"
NAME="07-declared-counts-match-tree"
RULE_REL=".claude/rulebook/ai-tooling.md"

[ -f "$WS/$RULE_REL" ] || { skills_gate_void "$NAME" "нет $RULE_REL — объявлять числа некому"; exit 2; }

out="$(python3 - "$WS" "$RULE_REL" <<'PY'
# -*- coding: utf-8 -*-
import re
import subprocess
import sys

ws, rel = sys.argv[1], sys.argv[2]
text = open("%s/%s" % (ws, rel), encoding="utf-8").read()

CMD = re.compile(r"`(git [^`\n]*)`")
NUM = re.compile(r"\*\*(\d+)\*\*")
# Конвейер сужен намеренно: документ не место, откуда исполняется что угодно.
SAFE = re.compile(r"^git [a-z-]+(?: [^|;&`$()<>*?]+)?"
                  r"(?:\| *(?:cut|sort|grep|uniq|wc)[^|;&`$()<>]*)*$")
GAP = 60

tokens = []
for m in CMD.finditer(text):
    tokens.append(("cmd", m.start(), m.end(), m.group(1)))
for m in NUM.finditer(text):
    tokens.append(("num", m.start(), m.end(), m.group(1)))
tokens.sort(key=lambda t: t[1])


def line_of(pos):
    return text.count("\n", 0, pos) + 1


def joins(a_end, b_start):
    """Соседние токены считаются парой, если между ними нет пустой строки и не
    больше GAP знаков. Пустая строка — граница абзаца: за ней стоит уже другое
    утверждение, и пара через неё была бы составлена наугад."""
    gap = text[a_end:b_start]
    return len(gap) <= GAP and "\n\n" not in gap and "\n>\n" not in gap


findings = []
n_cmd = n_paired = n_bare = 0

for i, tok in enumerate(tokens):
    if tok[0] != "cmd":
        continue
    n_cmd += 1
    declared = None
    if i + 1 < len(tokens) and tokens[i + 1][0] == "num" \
            and joins(tok[2], tokens[i + 1][1]):
        declared = tokens[i + 1][3]
    elif i > 0 and tokens[i - 1][0] == "num" \
            and joins(tokens[i - 1][2], tok[1]):
        declared = tokens[i - 1][3]
    if declared is None:
        n_bare += 1
        continue
    n_paired += 1
    command, line = tok[3], line_of(tok[1])
    if not SAFE.match(command):
        findings.append(
            "%s:%d — цитата `%s` объявлена с числом %s, но её форма вне разбора: "
            "расширь разбор ОСОЗНАННО либо перепиши цитату. Молчать здесь нельзя — "
            "непрочитанная цитата неотличима от сошедшейся"
            % (rel, line, command, declared))
        continue
    try:
        got = subprocess.run(["bash", "-c", command], cwd=ws, capture_output=True,
                             text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as exc:
        findings.append("%s:%d — цитата `%s` не исполняется: %s" % (rel, line, command, exc))
        continue
    if got.returncode != 0:
        findings.append(
            "%s:%d — цитата `%s` отказывает (код %d): «%s». Команда, которую негде "
            "выполнить, не предикат, а тупик для того, кто ей поверил"
            % (rel, line, command, got.returncode, got.stderr.strip().splitlines()[0]
               if got.stderr.strip() else ""))
        continue
    actual = got.stdout.strip()
    if not actual.isdigit():
        findings.append(
            "%s:%d — цитата `%s` объявлена числом %s, а её вывод числом не является: «%s»"
            % (rel, line, command, declared, actual.replace("\n", " ")[:80]))
        continue
    if int(actual) != int(declared):
        findings.append(
            "%s:%d — объявлено %s, предикат `%s` даёт %s"
            % (rel, line, declared, command, actual))

print("ПЕРЕПИСЬ|процитировано команд %d; из них с объявленным числом %d, без числа %d; "
      "расхождений %d" % (n_cmd, n_paired, n_bare, len(findings)))
if n_cmd == 0:
    print("VOID|в %s не процитировано ни одной команды `git …` — форма сменилась, "
          "гейт без предмета" % rel)
elif n_paired == 0:
    print("VOID|ни одна цитата не объявлена рядом с числом — сверять нечего")
for f in findings:
    print("НАХОДКА|%s" % f)
PY
)"
rc_py=$?

if [ "$rc_py" -ne 0 ]; then
    skills_gate_void "$NAME" "разбор не выполнился (код $rc_py)"
    exit 2
fi

printf '%s\n' "$out" | sed -n 's/^ПЕРЕПИСЬ|/перепись: /p'

if printf '%s\n' "$out" | grep -q '^VOID|'; then
    skills_gate_void "$NAME" "$(printf '%s\n' "$out" | sed -n 's/^VOID|//p' | head -1)"
    exit 2
fi

if printf '%s\n' "$out" | grep -q '^НАХОДКА|'; then
    printf '%s\n' "$out" | sed -n 's/^НАХОДКА|/  /p' >&2
    skills_gate_fail "$NAME" "объявленное число разошлось с предикатом"
    exit 1
fi

skills_gate_pass "$NAME" "каждое объявленное число исполнено и сошлось"
exit 0
