#!/usr/bin/env bash
# check-20 — «`gh api` — ТОЛЬКО GET» ДОЕЗЖАЕТ ДО ЧИТАЮЩИХ АГЕНТОВ, А ОТКАЗ — ДО Bash (ws#1008).
#
# ОСНОВАНИЕ. Агенты ci-watcher, выясняя merge-base, звали
# `gh api repos/<r>/merges -X POST -f base=… -f head=…` — вызов, который ВЛИВАЕТ head
# в base. Так мимо посадки ушли kacho#3142, kacho#3144, kaname#703. Решение
# диспетчера с полномочиями владельца («делай все сам, решения принимаешь сам»):
# норма в телах читающих агентов и отказ хуком PreToolUse.
#
# ОСИ (каждая — своя находка с координатой):
#   A. каждый из читающих агентов (READERS ниже) несёт норму «`gh api` — только GET»
#      вместе с готовой командой merge-base (`…/compare/<base>...<head> --jq
#      .merge_base_commit.sha`) — без команды норма учит запрету, но не чтению, и
#      агент снова изобретает путь; файла агента нет — тоже находка: перечень
#      READERS — утверждение о дереве;
#   B. `.claude/settings.json` провязывает `gh-api-guard.sh` в `PreToolUse` с
#      матчером, под который попадает Bash, и команда исполняет ИМЕННО канонический
#      файл (путь из разобранной команды, `$CLAUDE_PROJECT_DIR` подставлен корнем),
#      он существует и исполним; разбор хука `gh-api-guard/guard.py` и лексер, у
#      которого он его берёт (`no-wait-guard/guard.py`), есть.
# Отказы стража доказывает `.claude/hooks/gh-api-guard/prove.sh` (зовёт
# scripts/hook-proofs.sh); правило вливания в общем задании волны —
# `scripts/wave-template-inject.sh`; здесь — провязка.
#
# ПРЕДПОСЫЛКА (VOID, код 2): `settings.json` разбирается.
# Коды: 0 — находок нет; 1 — находка с координатой; 2 — предмета нет.
set -uo pipefail

name="$(basename "${BASH_SOURCE[0]}" .sh)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
root="$(tooling_gate_workspace_root)" || exit 2

python3 - "$root" "$name" <<'PY'
import json, os, re, shlex, sys
root, name = sys.argv[1], sys.argv[2]
READERS = ('ci-watcher', 'scout', 'check-verifier', 'landing-reviewer', 'wave-reviewer')
NORM = 'Норма «`gh api` — только GET»'
READ = '`gh api repos/<o>/<r>/compare/<base>...<head> --jq .merge_base_commit.sha`'
HOOK = '.claude/hooks/gh-api-guard.sh'
NEEDED = (HOOK, '.claude/hooks/gh-api-guard/guard.py', '.claude/hooks/no-wait-guard/guard.py')
SHELLS = {'bash', 'sh', 'dash', 'zsh', 'ksh'}


def void(msg):
    print('[VOID] %s — %s' % (name, msg), file=sys.stderr)
    sys.exit(2)


def flat(p):
    # мягкий перенос строки внутри абзаца — не разрыв нормы
    return re.sub(r'\s+', ' ', open(os.path.join(root, p), encoding='utf-8').read())


try:
    hooks = json.load(open(os.path.join(root, '.claude/settings.json'))).get('hooks', {})
except Exception as e:
    void('.claude/settings.json не разобран: %s' % e)
finds, seen = [], 0
for a in READERS:
    p = '.claude/agents/%s.md' % a
    try:
        body = flat(p)
    except OSError:
        finds.append('%s: файла нет — перечень читающих агентов разошёлся с деревом' % p)
        continue
    seen += 1
    for frag in (NORM, READ):
        if frag not in body:
            finds.append('%s: нет «%s»' % (p, frag))
CANON = os.path.realpath(os.path.join(root, HOOK))


def script_of(cmd):
    """Файл, который исполнит команда хука: `bash <путь>` либо `<путь>`; None — не разобрано."""
    try:
        argv = shlex.split(cmd)
    except ValueError:
        return None
    if argv and os.path.basename(argv[0]) in SHELLS:
        argv = argv[1:]
        while argv and argv[0].startswith('-'):
            argv = argv[1:]
    if not argv:
        return None
    p = re.sub(r'\$\{CLAUDE_PROJECT_DIR\}|\$CLAUDE_PROJECT_DIR(?![A-Za-z0-9_])', lambda m: root, argv[0])
    if '$' in p or not os.path.isabs(p):
        return None
    return os.path.realpath(p)


wired, hooks_seen = False, 0
for g in hooks.get('PreToolUse', []):
    for h in g.get('hooks', []):
        cmd = h.get('command', '')
        if 'gh-api-guard' not in cmd:
            continue
        hooks_seen += 1
        if not re.fullmatch(g.get('matcher') or '.*', 'Bash'):
            continue
        sp = script_of(cmd)
        if sp != CANON:
            finds.append('.claude/settings.json: PreToolUse под Bash зовёт не канонический хук: «%s» → %s (ожидался %s)'
                         % (cmd, sp or 'путь не разобран', HOOK))
        elif not os.path.isfile(sp) or not os.access(sp, os.X_OK):
            finds.append('.claude/settings.json: PreToolUse под Bash зовёт %s — файла нет или он не исполним' % sp)
        else:
            wired = True
if not wired:
    finds.append('.claude/settings.json: gh-api-guard.sh не провязан в PreToolUse под Bash каноническим путём')
for p in NEEDED:
    if not os.path.isfile(os.path.join(root, p)):
        finds.append('%s: файла нет' % p)
print('[CENSUS] %s: читающих агентов осмотрено %d из %d, записей gh-api-guard в PreToolUse %d, файлов стража %d; находок %d'
      % (name, seen, len(READERS), hooks_seen, len(NEEDED), len(finds)))
for f in finds:
    print('[FAIL] %s — %s' % (name, f), file=sys.stderr)
if finds:
    sys.exit(1)
print('[PASS] %s — «gh api — только GET» с чтением merge-base у %d агентов; отказ провязан в PreToolUse Bash' % (name, seen))
PY
