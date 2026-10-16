#!/usr/bin/env bash
# В хранилище нет учётных данных — во ВСЁМ хранилище, включая замороженный архив.
#
# Хранилище закоммичено и ПУБЛИЧНО: секрет в записке — утечка в момент отправки,
# и заморозка архива (2026-10-16) этого не отменяет — архив читают, а не
# правят. Поэтому, в отличие от check-02 и check-03, предмет здесь — все файлы
# хранилища из индекса git, а не только ведомые `lessons/` и `runbooks/`.
#
# Формы — по классу учётного литерала, а не по словарю имён: заголовок закрытого
# ключа PEM; токен GitHub; JWT из трёх сегментов; токен Slack; присваивание
# учётному ключу (`password`, `secret`, `token`, `api_key`…) литерала из букв И цифр
# длиной от 12. Имя ресурса без цифр (`existingSecret: kacho-db-credentials`) и
# заглушка (`<пароль>`, `{{token}}`, `${VAR}`) — законные близнецы, inject-01.sh.
#
# Исход: 0 — чисто; 1 — находки (файл:строка и форма, само значение НЕ печатается);
# 2 — в индексе git ни одного файла хранилища.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$SCRIPT_DIR" "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" <<'PY'
import os, re, sys
sys.path.insert(0, sys.argv[1])
import vaultlib as V

CHECK = "в хранилище нет учётных данных"
FORMS = [
    ("закрытый ключ PEM", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("токен GitHub", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,})\b")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("токен Slack", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("учётный литерал", re.compile(
        r"(?i)(?:password|passwd|pwd|secret|token|api[_-]?key)[\"']?\s*[:=]\s*[\"']?"
        r"(?=[A-Za-z0-9/+_=.-]*[0-9])(?=[A-Za-z0-9/+_=.-]*[A-Za-z])[A-Za-z0-9/+_=.-]{12,}")),
]

root = V.workspace_root(sys.argv[2])
files = V.vault_files(root)
if not files:
    print(f"[VOID] {CHECK} — в индексе git нет ни одного файла {V.VAULT}/", file=sys.stderr)
    sys.exit(2)

findings, read, lines_n, replaced = [], 0, 0, 0
for rel in files:
    # Байт не из UTF-8 — НЕ повод не читать: PEM в файле с байтом cp1251 иначе
    # проходил бы зелёным. Читается с заменой, и число таких файлов печатается.
    try:
        raw = open(os.path.join(root, V.VAULT, rel), "rb").read()
    except OSError:
        continue
    text = raw.decode("utf-8", errors="replace")
    replaced += "\ufffd" in text and b"\xef\xbf\xbd" not in raw
    read += 1
    for ln, line in enumerate(text.splitlines(), 1):
        lines_n += 1
        for name, rx in FORMS:
            if rx.search(line):
                findings.append(f"{V.VAULT}/{rel}:{ln}: {name}")
                break

scope = (f"осмотрено файлов {read} из {len(files)} (всё хранилище, архив тоже; не UTF-8, прочитано с заменой, {replaced}), "
         f"строк {lines_n}; форм {len(FORMS)}")
if read == 0:
    print(f"[VOID] {CHECK} — {scope}: прочитать не удалось ни одного", file=sys.stderr)
    sys.exit(2)
if findings:
    print(f"[FAIL] {CHECK} — {scope}; находок {len(findings)} (значение не печатается)", file=sys.stderr)
    for f in findings[:40]:
        print(f"        {f}", file=sys.stderr)
    sys.exit(1)
print(f"[PASS] {CHECK} — {scope}; находок 0")
PY
