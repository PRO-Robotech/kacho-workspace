#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# stall-census.sh — ЗАСТОЙ полос виден диспетчеру без его вопроса (ws#1001).
#
# # Предмет
#
# Решение владельца 2026-10-11 дословно: «И реши проблему раз и навсегда что
# таски уходят в часовые таймауты и ничего не делают а мы ждем. Нужно что бы
# была максимальная оперативность и минимум простоя». Замер ws#1001 (сессия
# 3f44acf5, 09-20…10-10): простой 605,4 из 1623,8 агент-ч (37 %); диспетчер узнавал
# о застое живого workflow только по goal check-in, отложенному на 30–305 мин.
# Реакция на ЗАВЕРШЕНИЕ workflow причиной не была (1 опоздание из 653) — простой
# возникает, пока процесс жив, но стоит. Этот прибор меряет именно это.
#
# # Что печатает (по журналам ТЕКУЩЕЙ сессии и процессам машины, без сети)
#
#   STALL-AGENT  агент без новой записи user/assistant дольше STALL_AGENT_MIN
#                (15) мин и при этом НЕ завершён: последняя запись — вызов
#                инструмента без результата либо результат без ответа модели.
#                Печатается последний вызов (инструмент и начало команды).
#   STALL-POLL   агент жив, но его последние вызовы (≥ 2 подряд, первый — дольше
#                STALL_POLL_MIN (20) мин назад) — ожидание: цикл until/while со
#                sleep, sleep ≥ 100 с, tail --pid, gh run watch|view, gh pr checks,
#                flock -w ≥ 100. Класс 1–3 замера (429 агент-ч из 605): каждый
#                вызов ≤ 10 мин, поэтому «нет нового вызова» его не видит.
#   STALL-PROC   фоновый процесс-оболочка агента (прямой потомок `claude`,
#                запущенный из shell-snapshot) живёт дольше STALL_PROC_MIN (60) мин.
#   UNREACTED-WF workflow завершён дольше STALL_REACT_MIN (10) мин назад, а у
#                главного потока после этого нет ни одной записи assistant.
#
# Окно — STALL_HORIZON_MIN (360) мин: брошенный журнал убитой сессии старше окна
# не судится, иначе строка печаталась бы вечно и перестала бы читаться.
#
# # Вход (швы инъекции)
#
#   --session <каталог>   каталог сессии `<projects>/<id>/`; рядом — `<id>.jsonl`
#                         главного потока. Без довода — из `transcript_path` JSON
#                         на stdin (хук), иначе — самая свежая сессия проекта.
#   --ps <файл>           вывод `ps -eo pid=,ppid=,etimes=,comm=,args=`; без
#                         довода — снимок машины.
#   --now <epoch>         «сейчас» (для подложенных журналов).
#
# # Коды
#
#   0 — застоя нет, и каждый осмотренный журнал агента дал хотя бы одну
#       разобранную запись (строка CENSUS: сколько осмотрено и прочитано);
#   1 — застой есть: перечень строками STALL-*/UNREACTED-WF (строки UNREAD —
#       рядом, если часть журналов не прочитана);
#   2 — не смог прочитать (каталога сессии нет, журнал главного потока не
#       читается, `ps` отказал, разбор упал, журнал агента старше порога агента
#       без единой разобранной записи) — это НЕ «чисто». Любой иной код
#       интерпретатора сводится к 2: падение прибора не выдаётся за застой.
# Запись журнала — JSON-ОБЪЕКТ; строка, разобранная в иное (`[1,2]`, `42`),
# считается неразобранной, как битая (опыт check-verifier по #1002).
#
# Быстрый: агентский журнал читается хвостом (64 КиБ), главный — хвостом 4 МиБ,
# состояния workflow — только изменённые в окне. Замер на сессии 3f44acf5
# (664 каталога workflow, главный журнал 152 МБ) — в шапке inject-скрипта.
set -uo pipefail

session="" psfile="" now=""
while [ $# -gt 0 ]; do
    case "$1" in
        --session) session="${2:-}"; shift 2 ;;
        --ps) psfile="${2:-}"; shift 2 ;;
        --now) now="${2:-}"; shift 2 ;;
        *) echo "stall-census: VOID — неизвестный довод «$1»" >&2; exit 2 ;;
    esac
done
command -v python3 > /dev/null 2>&1 || { echo "stall-census: VOID — нет python3" >&2; exit 2; }

stdin_json=""
if [ -z "$session" ] && [ ! -t 0 ]; then stdin_json="$(timeout 2 cat 2> /dev/null || true)"; fi
if [ -z "$psfile" ]; then
    psfile="$(mktemp)" || { echo "stall-census: VOID — не завёлся файл снимка" >&2; exit 2; }
    trap 'rm -f "$psfile"' EXIT
    ps -eo pid=,ppid=,etimes=,comm=,args= > "$psfile" 2> /dev/null \
        || { echo "stall-census: VOID — ps отказал: процессы не осмотрены" >&2; exit 2; }
fi

python3 - "$session" "$psfile" "$now" "$stdin_json" "${CLAUDE_PROJECT_DIR:-$PWD}" <<'PY'
import calendar, glob, json, os, re, sys, time


def _crash(kind, val, tb):
    # Падение разбора — «не проверено» (код 2), а не «застой» (код 1, которым
    # интерпретатор завершает необработанное исключение).
    print('stall-census: VOID — разбор упал: %s: %s' % (kind.__name__, val), file=sys.stderr)
    os._exit(2)


sys.excepthook = _crash

session, psfile, now_s, stdin_json, projdir = sys.argv[1:6]
AGENT_MIN = int(os.environ.get('STALL_AGENT_MIN', '15'))
PROC_MIN = int(os.environ.get('STALL_PROC_MIN', '60'))
REACT_MIN = int(os.environ.get('STALL_REACT_MIN', '10'))
HORIZON_MIN = int(os.environ.get('STALL_HORIZON_MIN', '360'))
POLL_MIN = int(os.environ.get('STALL_POLL_MIN', '20'))
now = float(now_s) if now_s else time.time()


def void(msg):
    print('stall-census: VOID — ' + msg, file=sys.stderr)
    sys.exit(2)


def ts(s):
    # 2026-10-10T23:42:47.220Z → epoch
    try:
        return calendar.timegm(time.strptime(s[:19], '%Y-%m-%dT%H:%M:%S'))
    except Exception:
        return None


def records(lines):
    """Разобранные записи-объекты; не-JSON и JSON не-объект — пропуск."""
    out = []
    for raw in lines:
        try:
            r = json.loads(raw)
        except Exception:
            continue
        if isinstance(r, dict):
            out.append(r)
    return out


def tail_lines(path, size):
    with open(path, 'rb') as f:
        f.seek(0, 2)
        n = f.tell()
        f.seek(max(0, n - size))
        data = f.read()
    lines = data.split(b'\n')
    if n > size:
        lines = lines[1:]  # первая строка хвоста обрезана
    return [l for l in lines if l.strip()]


# ── Каталог сессии ──────────────────────────────────────────────────────
if not session and stdin_json:
    try:
        tp = json.loads(stdin_json).get('transcript_path') or ''
    except Exception:
        tp = ''
    if tp.endswith('.jsonl'):
        session = tp[:-len('.jsonl')]
if not session:
    slug = projdir.replace('/', '-').replace('.', '-')
    cands = glob.glob(os.path.expanduser('~/.claude/projects/' + slug + '/*.jsonl'))
    if not cands:
        void('журнала сессии проекта нет (' + slug + ')')
    session = max(cands, key=os.path.getmtime)[:-len('.jsonl')]
main = session + '.jsonl'
if not os.path.isfile(main):
    void('журнал главного потока не читается: ' + main)

findings = []


WAIT = re.compile(r'\b(until|while)\b.*\bsleep\b|\bsleep\s+[0-9]{3,}|\btail\b.*--pid|\bgh\s+(run\s+(watch|view)|pr\s+checks)\b|\bflock\b.*-w\s*[0-9]{3,}', re.S)


def poll_run(path, size=262144):
    """Хвост вызовов агента, каждый из которых — ожидание: (число, минут с первого, последний)."""
    calls = []
    for r in records(tail_lines(path, size)):
        if r.get('type') != 'assistant' or not isinstance(r.get('message'), dict):
            continue
        for c in r['message'].get('content') or []:
            if isinstance(c, dict) and c.get('type') == 'tool_use':
                cmd = str((c.get('input') or {}).get('command') or '')
                calls.append((ts(r.get('timestamp', '')), c.get('name', ''), cmd))
    n, first = 0, None
    for t, name, cmd in reversed(calls):
        if name in ('Bash', 'Monitor') and WAIT.search(cmd):
            n, first = n + 1, t
        else:
            break
    if not n or first is None:
        return 0, 0, ''
    return n, (now - first) / 60, ' '.join(calls[-1][2].split())[:160]


def last_message(path):
    """(время, вид, вызов): вид — 'tool' | 'result' | 'done' | 'progress' | None.

    None — в журнале нет ни одной разобранной записи-объекта: журнал НЕ прочитан.
    Хвост растёт (64 КиБ → 1 МиБ → 16 МиБ → весь файл), пока не найдётся запись:
    одна строка результата инструмента бывает длиннее 64 КиБ, и короткий хвост
    иначе выдал бы её за нечитаемый журнал.
    """
    size, n = 65536, os.path.getsize(path)
    while True:
        objs = records(tail_lines(path, size))
        if objs or size >= n:
            break
        size = min(size * 16, n)
    if not objs:
        return None, None, ''
    recs = [r for r in objs if r.get('type') in ('user', 'assistant') and isinstance(r.get('message'), dict)]
    if not recs:
        return None, 'progress', ''
    r = recs[-1]
    t = ts(r.get('timestamp', ''))
    content = r['message'].get('content')
    content = content if isinstance(content, list) else []
    if r['type'] == 'assistant':
        uses = [c for c in content if isinstance(c, dict) and c.get('type') == 'tool_use']
        if not uses:
            return t, 'done', ''
        u = uses[-1]
        if u.get('name') == 'StructuredOutput':
            return t, 'done', ''
        inp = u.get('input') or {}
        what = inp.get('command') or inp.get('description') or inp.get('file_path') or ''
        return t, 'tool', u.get('name', '?') + ': ' + ' '.join(str(what).split())[:160]
    if any(isinstance(c, dict) and c.get('type') == 'tool_result' for c in content):
        return t, 'result', 'ответ модели после результата инструмента'
    return t, 'result', 'ответ модели на сообщение'


# ── Агенты: workflow живые и агенты верхнего уровня ─────────────────────
agents_seen = 0
unread = []  # журналы агентов старше порога без единой разобранной записи
wf_live = 0
state_dir = os.path.join(session, 'workflows')
wf_root = os.path.join(session, 'subagents', 'workflows')
try:
    for wdir in glob.glob(os.path.join(wf_root, 'wf_*')):
        wid = os.path.basename(wdir)
        if os.path.exists(os.path.join(state_dir, wid + '.json')):
            continue  # завершён: состояние записано
        if now - os.path.getmtime(wdir) > HORIZON_MIN * 60 and not any(
                now - os.path.getmtime(f) <= HORIZON_MIN * 60 for f in glob.glob(os.path.join(wdir, 'agent-*.jsonl'))):
            continue
        wf_live += 1
        finished = set()
        jpath = os.path.join(wdir, 'journal.jsonl')
        if os.path.exists(jpath):
            for j in records(tail_lines(jpath, 1 << 20)):
                if j.get('type') == 'result' and j.get('agentId'):
                    finished.add(j['agentId'])
        for apath in glob.glob(os.path.join(wdir, 'agent-*.jsonl')):
            aid = os.path.basename(apath)[len('agent-'):-len('.jsonl')]
            if aid in finished:
                continue
            age_file = now - os.path.getmtime(apath)
            if age_file > HORIZON_MIN * 60:
                continue
            agents_seen += 1
            n, span, last = poll_run(apath)
            if n >= 2 and span >= POLL_MIN:
                findings.append('STALL-POLL %s/%s — ожидание вместо работы: %d вызовов подряд за %d мин; последний: %s' % (wid, aid, n, span, last))
                continue
            if age_file < AGENT_MIN * 60:
                continue
            t, kind, what = last_message(apath)
            if kind is None:
                unread.append('%s/%s' % (wid, aid))
                continue
            if kind == 'done' or t is None:
                continue
            idle = (now - t) / 60
            if idle >= AGENT_MIN:
                label = ''
                meta = apath[:-len('.jsonl')] + '.meta.json'
                try:
                    m = json.load(open(meta))
                    m = m if isinstance(m, dict) else {}
                    label = (m.get('agentType') or '') + ' «' + (m.get('description') or '') + '»'
                except Exception:
                    pass
                findings.append('STALL-AGENT %s/%s %s — без нового вызова %d мин; последний: %s' % (wid, aid, label, idle, what))
    for apath in glob.glob(os.path.join(session, 'subagents', 'agent-*.jsonl')):
        age_file = now - os.path.getmtime(apath)
        if age_file > HORIZON_MIN * 60:
            continue
        agents_seen += 1
        n, span, last = poll_run(apath)
        if n >= 2 and span >= POLL_MIN:
            findings.append('STALL-POLL %s — ожидание вместо работы: %d вызовов подряд за %d мин; последний: %s' % (os.path.basename(apath)[:-6], n, span, last))
            continue
        if age_file < AGENT_MIN * 60:
            continue
        t, kind, what = last_message(apath)
        if kind is None:
            unread.append(os.path.basename(apath)[:-6])
            continue
        if kind == 'done' or t is None:
            continue
        idle = (now - t) / 60
        if idle >= AGENT_MIN:
            findings.append('STALL-AGENT %s — без нового вызова %d мин; последний: %s' % (os.path.basename(apath)[:-6], idle, what))
except OSError as e:
    void('журналы агентов не читаются: %s' % e)

# ── Завершённые workflow без реакции главного потока ────────────────────
wf_done = 0
try:
    last_asst = None
    for r in reversed(records(tail_lines(main, 4 << 20))):
        if r.get('type') == 'assistant':
            last_asst = ts(r.get('timestamp', ''))
            break
    for sp in glob.glob(os.path.join(state_dir, 'wf_*.json')):
        if now - os.path.getmtime(sp) > HORIZON_MIN * 60:
            continue
        try:
            s = json.load(open(sp))
        except Exception:
            continue  # пишется прямо сейчас
        if not isinstance(s, dict):
            continue
        end = ts(s.get('timestamp', '') or '')
        if end is None:
            continue
        wf_done += 1
        if now - end >= REACT_MIN * 60 and (last_asst is None or last_asst < end):
            findings.append('UNREACTED-WF %s «%s» — завершён (%s) %d мин назад, диспетчер после этого не отвечал'
                            % (s.get('runId', os.path.basename(sp)[:-5]), s.get('workflowName', ''), s.get('status', '?'), (now - end) / 60))
except OSError as e:
    void('журнал главного потока не читается: %s' % e)

# ── Фоновые процессы агентов ────────────────────────────────────────────
procs = {}
try:
    for line in open(psfile, encoding='utf-8', errors='replace'):
        p = line.split(None, 4)
        if len(p) < 4 or not p[0].isdigit():
            continue
        procs[p[0]] = (p[1], int(p[2]) if p[2].isdigit() else 0, p[3], p[4].strip() if len(p) > 4 else '')
except OSError as e:
    void('снимок процессов не читается: %s' % e)
if not procs:
    void('снимок процессов пуст: процессы не осмотрены')
shells = 0
for pid, (ppid, et, comm, args) in procs.items():
    parent = procs.get(ppid)
    if not parent or parent[2] != 'claude' or 'shell-snapshots/' not in args:
        continue
    shells += 1
    if et >= PROC_MIN * 60:
        cmd = args.split("eval '", 1)[-1] if "eval '" in args else args
        findings.append('STALL-PROC pid %s (claude %s) — живёт %d мин: %s' % (pid, ppid, et / 60, ' '.join(cmd.split())[:160]))

print('CENSUS stall-census: сессия %s; workflow живых %d, завершённых в окне %d; агентов осмотрено %d, из них без единой разобранной записи %d; фоновых оболочек агентов %d из процессов %d; пороги агент %d мин, опрос %d мин, процесс %d мин, реакция %d мин, окно %d мин'
      % (os.path.basename(session), wf_live, wf_done, agents_seen, len(unread), shells, len(procs), AGENT_MIN, POLL_MIN, PROC_MIN, REACT_MIN, HORIZON_MIN))
for f in findings:
    print(f)
for u in unread:
    print('UNREAD %s — журнал агента без единой разобранной записи: застой по нему не судим' % u)
if findings:
    sys.exit(1)
if unread:
    # Ноль прочитанного — не «застоя нет».
    print('stall-census: VOID — журналов агентов не прочитано %d из %d: %s' % (len(unread), agents_seen, ', '.join(unread[:5])), file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PY
rc=$?
# Код интерпретатора вне {0,1,2} (сигнал, отказ запуска) — тоже «не проверено».
case "$rc" in
    0 | 1 | 2) exit "$rc" ;;
    *) echo "stall-census: VOID — разбор завершился кодом $rc: не проверено" >&2; exit 2 ;;
esac
