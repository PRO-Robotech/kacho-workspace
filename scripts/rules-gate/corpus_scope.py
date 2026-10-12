"""Область «корпус говорит то, что действует» — ОДНА на check-11 и check-12.

Предмет обеих проверок — утверждение корпуса, которое читает исполнитель как
норму: правила, определения агентов, скилы, хуки, форма заданий шаблона волны
(`.claude/workflows/`), общий протокол `CLAUDE.md` и скрипты условий посадки и
плана (`scripts/*precheck*.sh`, `scripts/merge-readiness.sh`). Два перечня одной
области разошлись бы молча, поэтому область живёт здесь, а проверки её читают.

ЧТО НАМЕРЕННО ВНЕ ОБЛАСТИ, И ПОЧЕМУ:
  * `.claude/backup/` — архив доводов и СНЯТЫХ редакций; там дословно лежат
    отменённые нормы с датой решения (например, «ВЛИВАНИЕ — ТОЛЬКО СХЛОПЫВАНИЕМ
    (решение владельца 2026-08-20)»), и судить их как действующие — значит
    требовать переписать историю;
  * символьные ссылки — `rule-*/SKILL.md` указывают на файл правила, и тот же
    текст был бы прочитан дважды: перепись удвоилась бы, а находка печаталась бы
    под двумя адресами.

Единица — отслеживаемый git файл корня (`git ls-files`): диск принёс бы
неотслеживаемые черновики полосы, которые никто не читает как норму.
"""
import os
import subprocess

PATHSPECS = (
    "CLAUDE.md",
    ".claude",
    ":(glob)scripts/*precheck*.sh",
    "scripts/merge-readiness.sh",
    ":(exclude).claude/backup",
)


def files(root):
    """Отслеживаемые файлы области: список относительных путей, либо None — индекса нет."""
    out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--"] + list(PATHSPECS),
                         capture_output=True)
    if out.returncode != 0:
        return None
    rels = []
    for raw in out.stdout.split(b"\0"):
        if not raw:
            continue
        rel = raw.decode("utf-8", "replace")
        p = os.path.join(root, rel)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        rels.append(rel)
    return sorted(rels)


def lines(root, rel):
    """Строки файла текстом; двоичный файл — пустой список (утверждений в нём нет)."""
    data = open(os.path.join(root, rel), "rb").read()
    if b"\0" in data:
        return []
    return data.decode("utf-8", "replace").splitlines()
