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
#
# ВЫЗОВ СОСЕДА — ТОЛЬКО ИСПОЛНЕНИЕ, И ПОЗИЦИЯ ИСПОЛНЕНИЯ ВЫВОДИТСЯ ТЕМ ЖЕ СНЯТИЕМ
# ПРЕФИКСОВ, ЧТО У СТРАЖА (`shell_lex.strip_prefixes`: присваивания, `if`/`then`/`{`/…,
# `time`, `env`, `builtin`, `command`, `exec`, `nice`, `timeout`, …). Позиций три:
# слово команды; аргумент `.`/`source`; файл сценария у интерпретатора (`bash`, `sh`,
# `dash`, `zsh`, `ksh`, `python`, `python3` — именем либо переменной, которой присвоено
# `$(command -v <интерпретатор> …)`; опции интерпретатора пропускаются; у `bash -c`
# позиция исполнения — строка команды, у `python -c`/`-m` сценария-файла нет). Всё прочее — упоминание, и провязкой не считается: аргумент
# `echo`/`printf`/`:` (и через обёртку: `command echo`), проверка `[ -x … ]`/`test`,
# аргумент любой другой команды (`cp`, `cat`), тело heredoc, комментарий. Команды
# внутри `$(…)`, обратных кавычек и `<(…)` судятся так же, на любой глубине.
#
# КАТАЛОГ ВЫВОДИТСЯ ИЗ ФАЙЛА, А НЕ ПРЕДПОЛАГАЕТСЯ. Каталог скрипта — `$0`,
# `$BASH_SOURCE`, `${BASH_SOURCE[0]}` под `dirname`, `readlink -f`/`realpath`, `%/*`;
# `$(cd <каталог> && pwd)`; корень воркспейса — `$CLAUDE_PROJECT_DIR` в любой из форм
# выше; переменная — только если ей в этом же файле присвоено одно из этого (прямо, после
# ключевого слова, через `local`/`export`/`readonly`/`declare`/`typeset`, в любом порядке
# присваиваний). Прочая `$ПЕРЕМЕННАЯ` (`$HOME`, `$TMPDIR`) — чужой каталог: ни вызовом
# соседа, ни находкой она не становится и считается переписью отдельно («каталог не
# выводим»). Прежде ЛЮБАЯ `$ИМЯ/` читалась каталогом хуков — `$HOME/bin/x.sh` давал
# ложную ось C, `cp "$TMPDIR/x.sh"` засчитывался провязкой (приёмка ws#714, круг 2).
#
# Не различается и не утверждается: составная строка команды (`bash -c 'a; b'`, `eval`), имя из
# массива, вызов из функции, собранной динамически, объект пути в python — хук на python
# ось C не читает. Замыкание по вызовам — транзитивно, до неподвижной точки.
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
    from shell_lex import ASSIGN, SUBST, simple_commands, strip_prefixes
except Exception as e:  # noqa: BLE001
    print(f"VOID нет разбора оболочки {H}/lib/shell_lex.py ({e!r}) — ни запись, ни вызов не выводимы")
    sys.exit(2)

ROOT = re.compile(r"(?:\./|\$CLAUDE_PROJECT_DIR/|\$\{CLAUDE_PROJECT_DIR(?::?[-=?+][^}]*)?\}/)?"
                  r"(\.claude/hooks/[^\s;|&]+)")
PARAM = re.compile(r"\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*|[0-9])")
REL = re.compile(r"[A-Za-z0-9_.][A-Za-z0-9_./-]*")
SCRIPT = {"0", "BASH_SOURCE", "BASH_SOURCE[0]"}
PROJECT = re.compile(r"CLAUDE_PROJECT_DIR(?::?[-=?+].*)?", re.S)
CUT = re.compile(r"([A-Za-z_][A-Za-z0-9_]*(?:\[0\])?|0)%/\*")
INTERP_SH = {"bash", "sh", "dash", "zsh", "ksh"}
INTERP_PY = {"python", "python3"}
SOURCE = {".", "source"}
DECL = {"local", "export", "readonly", "declare", "typeset"}

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


# ── значение слова: файл, каталог или интерпретатор — выведенные из самого хука ──
def _norm(p):
    p = os.path.normpath(p)
    return None if p == ".." or p.startswith("../") or os.path.isabs(p) else p


def _parent(kind, p):
    q = _norm(os.path.join(p, "..")) if kind == "dir" else _norm(os.path.dirname(p) or ".")
    return {("dir", q)} if q else set()


def _args(argv):
    return [a for a in argv[1:] if not str(a).startswith("-")]


class Hook:
    """Один хук-оболочка: переменные и вызовы, выведенные из его текста."""

    def __init__(self, path, text):
        self.path = path
        self.cmds = []                 # все простые команды, вложенные подстановки тоже
        self._collect(text)
        self.vars = {}
        # Присваивания — до неподвижной точки: порядок записи в файле значения не имеет
        # (функция объявлена выше переменной, которую она читает).
        assigns = [a for c in self.cmds for a in self._assigns(c)]
        for _ in range(8):
            changed = False
            for name, val in assigns:
                v = self.value(val)
                if v - self.vars.get(name, set()):
                    self.vars[name] = self.vars.get(name, set()) | v
                    changed = True
            if not changed:
                break

    def _collect(self, text):
        for words in simple_commands(text):
            self.cmds.append(words)
            for w in words:
                for sub in getattr(w, "subs", ()):
                    self._collect(sub)

    @staticmethod
    def _assigns(words):
        argv, _env, _ = strip_prefixes(list(words), "/")
        pre = list(words[: len(words) - len(argv)])
        if argv and str(argv[0]) in DECL:
            pre += [w for w in argv[1:] if not str(w).startswith("-")]
        out = []
        for w in pre:
            m = ASSIGN.fullmatch(str(w)) and re.match(r"([A-Za-z_][A-Za-z0-9_]*)\+?=", str(w))
            if m:
                v = type(w)(str(w)[m.end():])
                v.subs = getattr(w, "subs", ())
                out.append((m.group(1), v))
        return out

    def _param(self, m):
        c = m.group(1) if m.group(1) is not None else m.group(2)
        if c in SCRIPT:
            return {("file", self.path)}
        if PROJECT.fullmatch(c):
            return {("dir", ".")}
        cut = CUT.fullmatch(c)
        if cut:
            base = {("file", self.path)} if cut.group(1) in SCRIPT else self.vars.get(cut.group(1), set())
            return {x for k, p in base if k in ("file", "dir") for x in _parent(k, p)}
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", c):
            return set(self.vars.get(c, set()))
        return set()

    def _sub(self, src):
        try:
            cmds = simple_commands(src)
        except ValueError:
            return set()
        if cmds and len(cmds[0]) >= 3 and str(cmds[0][0]) == "command" and str(cmds[0][1]) in ("-v", "-V") \
                and all(str(c[0]) in ("true", ":") for c in cmds[1:]):
            n = os.path.basename(str(cmds[0][2]))
            return {("interp", n)} if n in INTERP_SH | INTERP_PY else set()
        stripped = [strip_prefixes(list(c), "/")[0] for c in cmds]
        if len(stripped) == 1 and stripped[0]:
            a = stripped[0]
            head, args = str(a[0]), _args(a)
            if head == "dirname" and len(args) == 1:
                return {x for k, p in self.value(args[0]) if k in ("file", "dir") for x in _parent(k, p)}
            if head in ("readlink", "realpath") and len(args) == 1:
                return {(k, p) for k, p in self.value(args[0]) if k in ("file", "dir")}
        if len(stripped) == 2 and stripped[0] and stripped[1] \
                and str(stripped[0][0]) == "cd" and str(stripped[1][0]) == "pwd" \
                and len(_args(stripped[0])) == 1:
            return {(k, p) for k, p in self.value(_args(stripped[0])[0]) if k == "dir"}
        return set()

    def value(self, w):
        s = str(w)
        subs = getattr(w, "subs", ())
        if s.startswith(SUBST):
            base, rest = (self._sub(subs[0]) if subs else set()), s[1:]
        else:
            m = PARAM.match(s)
            if m:
                base, rest = self._param(m), s[m.end():]
            else:
                r = ROOT.fullmatch(s)
                if r:
                    p = _norm(r.group(1))
                    return {("file", p)} if p else set()
                n = os.path.basename(s)
                return {("interp", n)} if s and n in INTERP_SH | INTERP_PY else set()
        if not rest:
            return base
        if not rest.startswith("/") or not REL.fullmatch(rest[1:]):
            return set()
        out = set()
        for k, p in base:
            if k == "dir":
                q = _norm(os.path.join(p, rest[1:]))
                if q:
                    out.add(("file" if re.search(r"\.(?:sh|py)$", q) else "dir", q))
        return out

    def is_interp(self, w):
        return any(k == "interp" for k, _ in self.value(w))

    def call_words(self, words):
        """→ (слова в позиции исполнения, прочие слова команды)."""
        argv, _env, _ = strip_prefixes(list(words), "/")
        if not argv:
            return [], []
        # Позиций исполнения три, и других нет: слово команды, аргумент `.`/`source`,
        # файл сценария интерпретатора. Аргумент `echo`, `[`, `cp`, `local` и любой
        # другой команды — упоминание по построению, отдельного списка «не вызовов»
        # не нужно (мутанты приёмки «печать — вызов» и «проверка — вызов» тому
        # эквивалентны: путь в аргументе и так не в позиции исполнения).
        head = str(argv[0])
        if head in SOURCE:
            return argv[1:2], argv[2:]
        if self.is_interp(argv[0]):
            fam_py = any(p in INTERP_PY for k, p in self.value(argv[0]) if k == "interp")
            with_arg = {"-W", "-X"} if fam_py else {"-o", "+o", "-O", "+O"}
            i = 1
            while i < len(argv) and str(argv[i]).startswith(("-", "+")) and str(argv[i]) not in ("-", "--"):
                a = str(argv[i])
                # `python -c <код>` / `-m <модуль>` — сценария-файла нет: аргумент — код.
                # `bash -c <команда>` — аргумент ИСПОЛНЯЕТСЯ командой: путь соседа в нём —
                # вызов (`bash -c "$(dirname …)/x.sh"`).
                if fam_py and a in ("-c", "-m"):
                    return [], argv[1:]
                if not fam_py and a == "-c":
                    return argv[i + 1:i + 2], argv[1:i + 1] + argv[i + 2:]
                i += 2 if a in with_arg else 1
            if i < len(argv) and str(argv[i]) == "--":
                i += 1
            return argv[i:i + 1], argv[1:i] + argv[i + 1:]
        return argv[:1], argv[1:]

    def calls(self):
        """→ (вызовы: [(цель, как записано)], каталог не выводим: N, упоминаний соседа: N)."""
        out, dark, mention = [], 0, 0
        for words in self.cmds:
            pos, rest = self.call_words(words)
            for w in pos:
                files = [p for k, p in self.value(w) if k == "file"]
                if files:
                    out += [(p, str(w).replace(SUBST, "$(…)")) for p in files]
                elif re.search(r"\.(?:sh|py)$", str(w)) and ("$" in str(w) or SUBST in str(w)):
                    dark += 1
            for w in rest:
                if any(k == "file" and p.startswith(H + "/") for k, p in self.value(w)):
                    mention += 1
        return out, dark, mention


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

# Замыкание по ВЫЗОВАМ — транзитивно, до неподвижной точки: провязанный хук-оболочка
# доходит до соседа, которого зовёт, тот — до своего, и так далее.
reach = set(wired)
frontier = list(wired)
calls_seen = dark_seen = mention_seen = outside = 0
unparsed = []
while frontier:
    f = frontier.pop()
    if not f.endswith(".sh"):
        continue
    try:
        text = open(os.path.join(ws, f), encoding="utf-8").read()
        found, dark, mention = Hook(f, text).calls()
    except (OSError, UnicodeDecodeError, ValueError) as e:
        unparsed.append(f)
        findings.append(f"C {f}: хук не разбирается ({e}) — его вызовы НЕ судились")
        continue
    dark_seen += dark
    mention_seen += mention
    for tgt, how in found:
        calls_seen += 1
        if not tgt.startswith(H + "/"):
            outside += 1               # вызов вне каталога хуков — не сосед, не судится
            continue
        if tgt not in tree:
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
      f"вызовов соседа прочитано {calls_seen} (вне каталога хуков {outside}), "
      f"вызовов с каталогом, не выводимым из файла, {dark_seen}, "
      f"упоминаний соседа не вызовом {mention_seen}, хуков не разобрано {len(unparsed)}")
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
