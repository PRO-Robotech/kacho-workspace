#!/usr/bin/env bash
# check-19 — НОРМА «НЕ ЖДИ» ДОЕЗЖАЕТ ДО КАЖДОГО АГЕНТА, А ЗАСТОЙ — ДО ДИСПЕТЧЕРА (ws#1001).
#
# ОСНОВАНИЕ. Решение владельца 2026-10-11: «И реши проблему раз и навсегда что
# таски уходят в часовые таймауты и ничего не делают а мы ждем. Нужно что бы была
# максимальная оперативность и минимум простоя». Замер причин простоя — в теле
# задачи ws#1001 (единица и предикат названы там).
#
# ОСИ (каждая — своя находка с координатой):
#   A. каждый `.claude/agents/*.md`, кроме `dispatcher`, несёт ссылку на норму
#      «`CLAUDE.md` «Не жди»» — агент без неё её не видит в своём теле;
#   B. `CLAUDE.md` несёт норму (якорь — фрагмент императива «Ни один вызов не держит
#      ожидание дольше 10» и цитата владельца «ничего не делают а мы ждем»);
#   C. база диспетчера несёт строку сигнала «⏱ ЗАСТОЙ» в §10 и `stall-census.sh`;
#   D. `.claude/settings.json` провязывает `stall-signal.sh` в `Stop` и
#      `UserPromptSubmit`, и сам хук и прибор `scripts/stall-census.sh` есть в дереве;
#   E. (ws#1004) `.claude/settings.json` провязывает `no-wait-guard.sh` в `PreToolUse`
#      с матчером, под который попадает Bash, хук и его разбор есть в дереве; база
#      диспетчера несёт правило полосы о чужих файлах («`blocked` — лишь за файлом
#      соседа»). Отказы стража доказывает `.claude/hooks/no-wait-guard/prove.sh`.
# Свойства самого прибора и хука доказывает `scripts/stall-census-inject.sh`, срок
# шага и чтение CI шаблоном — `scripts/wave-template-inject.sh`; здесь — провязка.
#
# ПРЕДПОСЫЛКА (VOID, код 2): агентов в индексе не ноль, `settings.json` разбирается.
# Коды: 0 — находок нет; 1 — находка с координатой; 2 — предмета нет.
set -uo pipefail

name="$(basename "${BASH_SOURCE[0]}" .sh)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
root="$(tooling_gate_workspace_root)" || exit 2

agents="$(tooling_gate_files "$root" '.claude/agents/*.md')"
python3 - "$root" "$name" "$agents" <<'PY'
import json, os, re, sys
root, name, agents = sys.argv[1], sys.argv[2], [a for a in sys.argv[3].split('\n') if a]
ANCHOR = '`CLAUDE.md` «Не жди»'
NORM = 'Ни один вызов не держит ожидание дольше 10'
QUOTE = 'ничего не делают а мы ждем'


def void(msg):
    print('[VOID] %s — %s' % (name, msg), file=sys.stderr)
    sys.exit(2)


def flat(p):
    # мягкий перенос строки внутри абзаца — не разрыв нормы
    return re.sub(r'\s+', ' ', open(os.path.join(root, p), encoding='utf-8').read())


if not agents:
    void('агентов в индексе нет: судить нечего')
try:
    hooks = json.load(open(os.path.join(root, '.claude/settings.json'))).get('hooks', {})
except Exception as e:
    void('.claude/settings.json не разобран: %s' % e)
finds = []
seen = 0
for a in agents:
    if os.path.basename(a) == 'dispatcher.md':
        continue
    seen += 1
    if ANCHOR not in flat(a):
        finds.append('%s: нет ссылки на норму %s' % (a, ANCHOR))
try:
    cl = flat('CLAUDE.md')
except OSError:
    cl = ''
for frag in (NORM, QUOTE):
    if frag not in cl:
        finds.append('CLAUDE.md: нет «%s»' % frag)
try:
    dp = flat('.claude/agents/dispatcher.md')
except OSError:
    dp = ''
for frag in ('| «⏱ ЗАСТОЙ»', 'stall-census.sh', '`blocked` — лишь за файлом соседа'):
    if frag not in dp:
        finds.append('.claude/agents/dispatcher.md: нет «%s»' % frag)
for ev in ('Stop', 'UserPromptSubmit'):
    if not any('stall-signal.sh' in h.get('command', '') for g in hooks.get(ev, []) for h in g.get('hooks', [])):
        finds.append('.claude/settings.json: stall-signal.sh не провязан в %s' % ev)
if not any(re.fullmatch(g.get('matcher') or '.*', 'Bash') and any('no-wait-guard.sh' in h.get('command', '') for h in g.get('hooks', []))
           for g in hooks.get('PreToolUse', [])):
    finds.append('.claude/settings.json: no-wait-guard.sh не провязан в PreToolUse под Bash')
for p in ('.claude/hooks/stall-signal.sh', 'scripts/stall-census.sh', '.claude/hooks/no-wait-guard.sh', '.claude/hooks/no-wait-guard/guard.py'):
    if not os.path.isfile(os.path.join(root, p)):
        finds.append('%s: файла нет' % p)
print('[CENSUS] %s: агентов-исполнителей осмотрено %d, протокол, база, настройки, хук и прибор — по одному; находок %d' % (name, seen, len(finds)))
if seen == 0:
    void('исполнителей ноль: ось A беспредметна')
for f in finds:
    print('[FAIL] %s — %s' % (name, f), file=sys.stderr)
if finds:
    sys.exit(1)
print('[PASS] %s — норма «Не жди» у %d исполнителей, в протоколе и базе; застой провязан в Stop и UserPromptSubmit, отказ ожиданию — в PreToolUse Bash' % (name, seen))
PY
