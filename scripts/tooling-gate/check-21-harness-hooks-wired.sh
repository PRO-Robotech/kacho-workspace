#!/usr/bin/env bash
# check-21 — ХУКИ ХАРНЕССА ПРОВЯЗАНЫ В `.claude/settings.json` В ОБЕ СТОРОНЫ.
#
# Предмет (ws#801). Пробы и проверки зовут хуки напрямую, поэтому провязку их в
# `.claude/settings.json` не судил никто: снять запись хука из события — и наборы
# остаются зелёными, а хук перестаёт срабатывать молча. Обратное тоже молчит:
# хук зовёт соседний файл, который уехал (ws#710 — `rag-session-start.sh` звал
# `rag-freshness.sh`, снятый в архив, и `SessionStart` выходил кодом 127).
#
# Три оси:
#   A. запись без файла   — команда события называет путь `.claude/hooks/…`,
#                           которого в дереве нет; либо называет `.claude/hooks/`
#                           формой, которую проверка не различает (вердикта по ней
#                           нет — это находка, а не молчание);
#   B. хук без записи      — исполняемый файл верхнего уровня `.claude/hooks/`
#                           (`*.sh`, `*.py`), до которого не доходит ни одна запись:
#                           ни прямо, ни через ВЫЗОВ из провязанного хука;
#   C. вызов без файла     — провязанный (прямо или вызовом) хук зовёт соседний
#                           файл `…/<имя>.sh|py`, которого нет.
#
# Исключения ВЫВОДЯТСЯ из дерева, а не выписываются. «Вспомогательный» — файл, до
# которого провязанный хук доходит ВЫЗОВОМ (замыкание по вызовам). Подкаталоги
# `.claude/hooks/<x>/` в ось B не входят: это разбор, библиотека, пробы и состояние
# хука верхнего уровня, а не точки входа харнесса. Архив (`.claude/backup/`) вне
# `.claude/hooks/` и не судится.
#
# РАЗБОР — ЛЕКСЕРОМ ОБОЛОЧКИ, общим со стражем Bash (`.claude/hooks/lib/shell_lex.py`),
# а не регулярным выражением по тексту. До 2026-09-28 здесь стояли регулярные
# выражения, и приёмка круга 1 нашла у них три слепоты: запись формой
# `./.claude/hooks/…` и `${CLAUDE_PROJECT_DIR:-.}/…` не распознавалась вовсе (ось A
# молчала, а на законной форме краснела ось B); вызов `$(dirname "$(readlink -f "$0")")/x.sh`
# и `${BASH_SOURCE%/*}/x.sh` рвался на первой скобке (ось C молчала); имя соседа в
# строке `echo "…zz-orphan.sh…"` засчитывалось провязкой — «замыкание по имени», чей
# вклад на живом дереве был нулевым (мутант приёмки H5: 14/14 и PASS). Замыкание по
# имени снято вместе с объявлением: доходит только вызов.
#
# Формы записи команды — все законные, и каждая доказана близнецом в inject.sh:
# слово, равное `<корень>.claude/hooks/<файл>`, где корень — пусто, `./`,
# `$CLAUDE_PROJECT_DIR/`, `${CLAUDE_PROJECT_DIR}/`, `${CLAUDE_PROJECT_DIR:-…}/`
# (кавычки сняты разбором: `"$CLAUDE_PROJECT_DIR"/…` — то же слово).
# Вызов соседа в хуке-оболочке — СЛОВО команды или значения присваивания (не аргумент
# `echo`/`printf`, не тело heredoc, не комментарий), равное `<каталог>/<файл>.sh|py`:
# каталог скрипта — `$(dirname …)`, `${BASH_SOURCE%/*}`, `${BASH_SOURCE[0]%/*}`,
# `${0%/*}`, иная переменная `$ИМЯ`/`${ИМЯ}`; корень — формы записи выше. Вызов,
# собранный иначе (имя из переменной целиком, из массива, объект пути в python),
# ось C не различает и этого не утверждает; хук на python ось C не читает.
#
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 отказ (нет настроек, не
# разбираются, ни одной записи хука — судить не о чем, и это не «находок 0»).
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-21-harness-hooks-wired"

set +e
out="$(python3 - "$WS" <<'PY'
import json, os, re, subprocess, sys

ws = sys.argv[1]
S = os.path.join(ws, ".claude", "settings.json")
H = ".claude/hooks"
if not os.path.isfile(S):
    print("VOID нет .claude/settings.json — провязку выводить не из чего")
    sys.exit(2)
try:
    d = json.load(open(S, encoding="utf-8"))
except ValueError as e:
    print(f"VOID .claude/settings.json не разбирается как JSON: {e}")
    sys.exit(2)

sys.path.insert(0, os.path.join(ws, H, "lib"))
try:
    from shell_lex import SUBST, simple_commands
except Exception as e:  # noqa: BLE001
    print(f"VOID нет разбора оболочки {H}/lib/shell_lex.py ({e!r}) — ни запись, ни вызов не выводимы")
    sys.exit(2)

ROOT = re.compile(r"(?:\./|\$CLAUDE_PROJECT_DIR/|\$\{CLAUDE_PROJECT_DIR(?::?[-=?+][^}]*)?\}/)?"
                  r"(\.claude/hooks/[^\s;|&]+)")
DIR_OF_SCRIPT = re.compile(r"\$\{(?:BASH_SOURCE(?:\[0\])?|0)%/\*\}|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?")
CALL_REL = re.compile(r"/([A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:sh|py))")
PRINT = {"echo", "printf", ":"}

records = []    # (событие, путь)
forms = {}
unknown = []
for event, groups in (d.get("hooks") or {}).items():
    for g in groups or []:
        for h in (g or {}).get("hooks") or []:
            cmd = h.get("command") or ""
            try:
                cmds = simple_commands(cmd)
            except ValueError as e:
                unknown.append((event, cmd, f"команда не разбирается ({e})"))
                continue
            for c in cmds:
                for w in c:
                    if ".claude/hooks/" not in w:
                        continue
                    m = ROOT.fullmatch(str(w))
                    if m:
                        records.append((event, m.group(1)))
                        k = str(w)[: len(str(w)) - len(m.group(1))] or "(от корня)"
                        forms[k] = forms.get(k, 0) + 1
                    else:
                        unknown.append((event, cmd, f"слово «{w}»"))
if not records and not unknown:
    print("VOID в .claude/settings.json нет ни одной записи хука `.claude/hooks/…` — судить не о чем")
    sys.exit(2)

tree = set(subprocess.run(["git", "-C", ws, "ls-files", "--cached", "--others", "--exclude-standard", H],
                          capture_output=True, text=True).stdout.split("\n")) - {""}
entry = sorted(p for p in tree if re.fullmatch(r"\.claude/hooks/[^/]+\.(sh|py)", p))


ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\+?=")
DECL = {"local", "export", "readonly", "declare", "typeset"}


def target_of(w, base_dir):
    """Слово — вызов соседа? → нормализованная цель либо None."""
    val = str(w)
    r = ROOT.fullmatch(val)
    if r:
        return os.path.normpath(r.group(1)) if re.search(r"\.(?:sh|py)$", r.group(1)) else None
    if val.startswith(SUBST):
        subs = getattr(w, "subs", ())
        if not subs or not subs[0].strip().startswith("dirname"):
            return None
        rest = val[len(SUBST):]
    else:
        dm = DIR_OF_SCRIPT.match(val)
        if not dm or dm.group(0) in ("$CLAUDE_PROJECT_DIR", "${CLAUDE_PROJECT_DIR}"):
            return None
        rest = val[dm.end():]
    cm = CALL_REL.fullmatch(rest)
    return os.path.normpath(os.path.join(base_dir, cm.group(1))) if cm else None


def calls(src_text, base_dir):
    """Цели вызовов в исполняемой части хука-оболочки: (цель, как записано)."""
    out = []

    def walk(text):
        for words in simple_commands(text):
            for w in words:
                for sub in getattr(w, "subs", ()):
                    walk(sub)
            # Присваивания перед командой и аргументы `local`/`export`/… — значения:
            # путь в них тоже вызов (так хук держит адрес соседа до `. "$x"`).
            i = 0
            while i < len(words) and ASSIGN.match(str(words[i])):
                i += 1
            vals = [(w, ASSIGN.match(str(w)).end()) for w in words[:i]]
            rest = words[i:]
            if rest and str(rest[0]) in PRINT:
                rest = []                      # аргумент печати — текст, не вызов
            elif rest and str(rest[0]) in DECL:
                vals += [(w, m.end()) for w in rest[1:] for m in [ASSIGN.match(str(w))] if m]
                rest = []
            for w, cut in vals:
                v = type(w)(str(w)[cut:])
                v.subs = getattr(w, "subs", ())
                t = target_of(v, base_dir)
                if t:
                    out.append((t, str(w)))
            for w in rest:
                t = target_of(w, base_dir)
                if t:
                    out.append((t, str(w)))

    walk(src_text)
    return out


findings = []
for ev, cmd, why in unknown:
    findings.append(f"A {ev}: запись называет .claude/hooks/ формой, которую проверка не "
                    f"различает ({why}) — вердикта по ней НЕТ: `{cmd}`")
wired = set()
for ev, p in records:
    if p in tree:
        wired.add(p)
    else:
        findings.append(f"A {ev}: запись зовёт {p} — файла в дереве НЕТ; событие обслуживает пустоту")

# Замыкание по ВЫЗОВАМ: провязанный хук-оболочка доходит до соседа, которого зовёт.
reach = set(wired)
frontier = list(wired)
calls_seen = 0
unparsed = []
while frontier:
    f = frontier.pop()
    if not f.endswith(".sh"):
        continue
    try:
        text = open(os.path.join(ws, f), encoding="utf-8").read()
        found = calls(text, os.path.dirname(f))
    except (OSError, UnicodeDecodeError, ValueError) as e:
        unparsed.append(f)
        findings.append(f"C {f}: хук не разбирается ({e}) — его вызовы НЕ судились")
        continue
    for tgt, how in found:
        calls_seen += 1
        if tgt not in tree:
            # `$X/...` может звать не соседа, а чужой каталог: судим только цель внутри хуков.
            if tgt.startswith(H + "/"):
                findings.append(f"C {f}: зовёт {tgt} (`{how}`) — файла НЕТ; хук упадёт на вызове (127)")
            continue
        if tgt not in reach:
            reach.add(tgt)
            frontier.append(tgt)

for e in entry:
    if e not in reach:
        findings.append(f"B {e}: хук верхнего уровня, до которого не доходит НИ ОДНА запись "
                        f".claude/settings.json — ни прямо, ни вызовом; он не срабатывает")

print(f"CENSUS записей хука {len(records)} (событий {len({e for e, _ in records})}; формы: "
      + ", ".join(f"{k} {v}" for k, v in sorted(forms.items())) + f"; не распознано {len(unknown)}), "
      f"файлов верхнего уровня {len(entry)}, провязано прямо {len(wired)}, "
      f"доходит вызовом {len(reach & set(entry)) - len(wired & set(entry))}, "
      f"вызовов соседа прочитано {calls_seen}, хуков не разобрано {len(unparsed)}")
for f in findings:
    print("FIND " + f)
sys.exit(1 if findings else 0)
PY
)"
rc=$?
set -e

while IFS= read -r ln; do
    case "$ln" in
        CENSUS\ *) tooling_gate_census "$NAME: ${ln#CENSUS }" ;;
        FIND\ *)   tooling_gate_fail "$NAME" "${ln#FIND }" ;;
        VOID\ *)   tooling_gate_void "$NAME" "${ln#VOID }" ;;
        *)         [ -n "$ln" ] && echo "$ln" ;;
    esac
done <<< "$out"

case "$rc" in
    0) tooling_gate_pass "$NAME" "каждая запись ведёт в файл, каждый хук верхнего уровня провязан, каждый вызов соседа резолвится"; exit 0 ;;
    1) tooling_gate_fail "$NAME" "провязка хуков харнесса разошлась с деревом"; exit 1 ;;
    2) exit 2 ;;
    *) tooling_gate_void "$NAME" "разбор упал кодом $rc — вердикта нет"; exit 2 ;;
esac
