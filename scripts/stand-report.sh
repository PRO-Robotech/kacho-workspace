#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# stand-report.sh — суд ОТЧЁТА ПРОГОНА НА ВНЕШНЕМ КЛАСТЕРЕ до CI (ws#1110).
#
# ЗАЧЕМ. Решение владельца 2026-10-16, дословно: «никогда нельзя решать проблемы по
# одному, сначала делается перепись, потом фиксится, потом прогоняется тесты на
# внешнем кластере, потом в master ci». Замер того же дня: kacho#3259 — пять полных
# кругов CI по 52–63 мин, каждый находил корень, который прогон на стенде нашёл бы за
# минуты; чтение CI прерывалось на первом красном. Порядок держит не внимание, а этот
# суд: PR переводится в ready и вливается лишь при коде 0 по отчёту ТОЙ ЖЕ головы
# (`.claude/workflows/wave.js` шаг mech:stand, `landing-precheck.sh --stand-report`).
# Канон — `ai-tooling.md#at-red-ci-one-round`.
#
# ИСПОЛЬЗОВАНИЕ
#   stand-report.sh expect --checkout <копия> --head <sha40> [--base <ref>] > <ожидаемое.json>
#   stand-report.sh check <отчёт.json> --head <sha40> --expect <ожидаемое.json>
#   stand-report.sh check <отчёт.json> --head <sha40> --of <прежний отчёт.json>
# ОЖИДАЕМОЕ выводится НЕ из отчёта (судимый не объявляет свою полноту): `expect` берёт
# задания CI, которые голова обязана пройти на кластере, из закрытой ведомости STAND
# ниже и источника репозитория — kacho: выбор затронутого `.github/scripts/affected.py
# --base <ref> --json` в копии головы ∩ задания стенда; kaname: CI без выбора — все
# задания стенда; kacho-workspace: заданий на кластере у CI нет — ВЫВЕДЕННЫЙ ноль.
# Копия не на голове, репозиторий вне ведомости, задание ведомости не найдено в файле
# workflow головы (ведомость отстала от CI), выбор не выполнился — VOID, не ноль.
# Без --of судится ПОЛНЫЙ прогон (mode full) — единственное основание для ready и
# вливания: каждое ожидаемое задание покрыто набором с этим `job`. С --of — прогон
# «только красное» (mode only-red): в нём обязан быть КАЖДЫЙ набор, красный в прежнем
# отчёте; зелёный only-red — основание лишь для полного прогона, не для CI.
#
# ФОРМА ОТЧЁТА (пишет ci-watcher; JSON-объект):
#   head     — sha40 головы, на которой гнали;          mode — full | only-red;
#   context  — контекст кластера; внешний — суффикс -client (remote-heavy/run.sh);
#              иное — лишь при proof формы журнала слота «local … proof=<…>»;
#   ns       — пространство имён прогона;               residue — остаток переписи после (0);
#   planned  — число наборов отчёта (согласованность, не полнота: полноту судит --expect);
#   suites   — [{name, job, outcome: green|red|not-run, executed, total, quote, root, reason}],
#              job — задание CI «<файл workflow>:<ключ>», которое набор воспроизводит.
#
# ЧТО СУДИТСЯ — строка REASON<TAB><код><TAB><пояснение> на причину:
#   STAND-REPORT-MISSING   — файла нет, он не JSON-объект или без полей формы;
#   STAND-REPORT-STALE     — head отчёта ≠ --head: прогон о другой голове;
#   STAND-EXPECT-STALE     — ожидаемое выведено для другой головы;
#   STAND-REPORT-UNCOVERED — ожидаемое задание CI не покрыто ни одним набором отчёта;
#   STAND-REPORT-NOT-FULL  — без --of отчёт не mode full (only-red основанием CI не служит);
#   STAND-REPORT-TRUNCATED — наборов ≠ planned; у зелёного executed < total, executed >
#                            total либо total < 1: «исполнено N из M»;
#   STAND-REPORT-RED       — набор red (печатается дословная цитата и корень);
#   STAND-REPORT-NO-QUOTE  — у red нет цитаты отказа: класс корня без цитаты — не класс;
#   STAND-REPORT-NOT-RUN   — набор not-run без живого послабления ведомости ниже;
#   STAND-RELAX-EXPIRED    — послабление названо, а его задача закрыта: снять строку;
#   STAND-REPORT-NOTHING-RUN — наборы либо ожидаемое есть, а зелёным исполнено 0;
#   STAND-REPORT-LOCAL     — контекст не внешний и proof не формы журнала слота;
#   STAND-REPORT-RESIDUE   — residue ≠ 0;
#   STAND-REPORT-RED-DROPPED — с --of: красный прежде набор в only-red отсутствует.
#
# ПОСЛАБЛЕНИЯ — закрытая ведомость RELAX ниже: причина not-run → задача, пока открыта.
# Живость спрашивается у площадки (`gh api repos/<репо>/issues/<N>` → state open);
# закрыта — STAND-RELAX-EXPIRED (само истекает, `gate-authoring` §9). «Не выполнилось»
# не зелёное: оно печатается строкой CENSUS поимённо и не засчитывается в исполненное.
#
# ИСХОДЫ: 0 — причин нет; 1 — причины строками REASON; 2 — VOID: довод не тот, нет
# python3, ожидаемого нет либо оно не разбирается, площадка не ответила о послаблении.
# Перепись — строками CENSUS всегда.
# ВХОД ПОДМЕНЯЕМ (scripts/stand-report-inject.sh): STAND_REPORT_GH — вместо `gh`.
set -uo pipefail

void() { printf 'VOID\t%s\n' "$1"; printf 'VERDICT\tunread\tкод 2\n'; exit 2; }
command -v python3 > /dev/null 2>&1 || void "нет python3"
if [ "${1:-}" = expect ]; then
    shift; CO=""; HEAD=""; BASE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --checkout) CO="${2:-}"; shift 2 ;;
            --head) HEAD="${2:-}"; shift 2 ;;
            --base) BASE="${2:-}"; shift 2 ;;
            *) void "неизвестный довод «$1»" ;;
        esac
    done
    [[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || void "--head «$HEAD» не sha40"
    [ -d "$CO" ] || void "копии «$CO» нет"
    got="$(git -C "$CO" rev-parse HEAD 2>/dev/null)" || void "«$CO» не git-копия"
    [ "$got" = "$HEAD" ] || void "копия «$CO» на ${got:0:12}, а не на голове ${HEAD:0:12} — выбор был бы о другой ревизии"
    url="$(git -C "$CO" remote get-url origin 2>/dev/null)" || void "у копии «$CO» нет origin — репозиторий не установить"
    CO="$CO" HEAD="$HEAD" BASE="$BASE" URL="$url" exec python3 - <<'PY'
import json, os, re, subprocess, sys
# Ведомость заданий CI, которые прогон на кластере воспроизводит, по репозиторию:
# source affected — выбор затронутого репозитория ∩ jobs; full — CI без выбора, все jobs;
# none — у CI заданий на кластере нет (выведенный ноль). Задание — «<workflow>:<ключ>».
STAND = {
    'PRO-Robotech/kacho': ('affected', ['ci.yaml:unit-shard', 'ci.yaml:integration', 'e2e-newman.yml:shard',
                                         'console-e2e.yml:probes', 'production-posture.yml:stand']),
    'PRO-Robotech/kaname': ('full', ['ci.yml:unit', 'ci.yml:integration', 'e2e-newman.yml:stand']),
    'PRO-Robotech/kacho-workspace': ('none', []),
}
co, head, base, url = os.environ['CO'], os.environ['HEAD'], os.environ['BASE'], os.environ['URL']


def void(msg):
    print('VOID\t' + msg)
    print('VERDICT\tunread\tкод 2')
    sys.exit(2)


m = re.search(r'github\.com[:/]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$', url)
repo = m.group(1) if m else ''
if repo not in STAND:
    void('репозиторий «%s» (origin %s) вне ведомости STAND — ожидаемое не известно, а не ноль' % (repo, url))
source, jobs = STAND[repo]
try:
    import yaml
except ImportError:
    void('нет python3-yaml — задания ведомости в workflow головы не сверить')
for j in jobs:
    wf, key = j.split(':', 1)
    try:
        doc = yaml.safe_load(open(os.path.join(co, '.github', 'workflows', wf), encoding='utf-8'))
    except (OSError, yaml.YAMLError) as e:
        void('workflow %s головы не читается (%s) — ведомость STAND не сверить' % (wf, e))
    if not (isinstance(doc, dict) and isinstance(doc.get('jobs'), dict) and key in doc['jobs']):
        void('задания %s ведомости STAND нет в .github/workflows/%s головы — ведомость отстала от CI' % (j, wf))
want = list(jobs)
if source == 'affected':
    if not base:
        void('%s выбирает затронутое — нужен --base' % repo)
    p = subprocess.run(['python3', '.github/scripts/affected.py', '--base', base, '--json'],
                       cwd=co, capture_output=True, text=True)
    if p.returncode != 0:
        void('выбор затронутого %s (--base %s) код %d: %s' % (repo, base, p.returncode, (p.stdout + p.stderr).strip()[-200:]))
    try:
        sel = json.loads(p.stdout.splitlines()[0])
        picked = set(sel['jobs'])
    except (ValueError, IndexError, KeyError, TypeError):
        void('выбор затронутого %s не разбирается' % repo)
    want = [j for j in jobs if j in picked]
print(json.dumps({'head': head, 'repo': repo, 'source': source, 'base': base, 'jobs': want}, ensure_ascii=False))
print('CENSUS\tожидаемое %s @%s: источник %s, заданий стенда %d из ведомости %d%s'
      % (repo, head[:12], source, len(want), len(jobs), '' if want else ' — выведенный ноль'), file=sys.stderr)
PY
fi
[ "${1:-}" = check ] || void "первым доводом — check либо expect"
REP="${2:-}"; [ -n "$REP" ] || void "нет пути отчёта"
shift 2
HEAD=""; OF=""; EXP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --head) HEAD="${2:-}"; shift 2 ;;
        --of) OF="${2:-}"; [ -r "$OF" ] || void "прежний отчёт «$OF» не читается"; shift 2 ;;
        --expect) EXP="${2:-}"; [ -r "$EXP" ] || void "ожидаемое «$EXP» не читается — полноту не судить"; shift 2 ;;
        *) void "неизвестный довод «$1»" ;;
    esac
done
[[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || void "--head «$HEAD» не sha40"
[ -n "$OF" ] || [ -n "$EXP" ] || void "полный прогон судится лишь против --expect (stand-report.sh expect): отчёт свою полноту не объявляет"

REP="$REP" HEAD="$HEAD" OF="$OF" EXP="$EXP" GH="${STAND_REPORT_GH:-gh}" python3 - <<'PY'
import json, os, re, subprocess, sys

# Ведомость послаблений: причина not-run → задача, которая её снимает. Закрыта — истекло.
RELAX = {
    'NO-PR-IMAGES': ('PRO-Robotech/kacho-workspace', '1110',
                     'стенд проб не принимает образы ветки PR (ws#1110 п.1) — newman и консоль ветки до CI не прогнать'),
}
reasons, census = [], []
rep, head, of, gh, exp = os.environ['REP'], os.environ['HEAD'], os.environ['OF'], os.environ['GH'], os.environ['EXP']


def reason(code, text):
    reasons.append((code, text))


def void(msg):
    print('VOID\t' + msg)
    print('VERDICT\tunread\tкод 2')
    sys.exit(2)


def load(path):
    try:
        d = json.load(open(path, encoding='utf-8'))
    except (OSError, ValueError):
        return None
    ok = (isinstance(d, dict) and isinstance(d.get('suites'), list) and isinstance(d.get('head'), str)
          and isinstance(d.get('mode'), str) and all(isinstance(s, dict) for s in d['suites']))
    return d if ok else None


def num(x):
    return x if isinstance(x, int) and not isinstance(x, bool) else -1


expected = None
if exp:
    try:
        e = json.load(open(exp, encoding='utf-8'))
    except (OSError, ValueError):
        e = None
    if not (isinstance(e, dict) and isinstance(e.get('head'), str) and isinstance(e.get('jobs'), list)
            and all(isinstance(j, str) for j in e['jobs'])):
        void('ожидаемое %s не формы stand-report.sh expect (head, jobs) — полноту не судить' % exp)
    expected = e['jobs']
    census.append('ожидаемое %s: %s @%s, источник %s, заданий %d%s' % (exp, e.get('repo', '?'), e['head'][:12], e.get('source', '?'),
                  len(expected), '' if expected else ' — выведенный ноль'))
    if e['head'] != head:
        reason('STAND-EXPECT-STALE', 'ожидаемое выведено для %s, судится %s — выбор о другой голове' % (e['head'][:12], head[:12]))

d = load(rep)
if d is None:
    reason('STAND-REPORT-MISSING', 'отчёта %s нет либо он не объект с полями head, mode, suites — прогона на кластере нет' % rep)
else:
    suites = d['suites']
    census.append('отчёт %s: голова %s, mode %s, контекст %s, ns %s; наборов %d из planned %s'
                  % (rep, d['head'][:12], d['mode'], d.get('context', '?'), d.get('ns', '?'), len(suites), d.get('planned')))
    if d['head'] != head:
        reason('STAND-REPORT-STALE', 'отчёт о голове %s, судится %s — прогон о другой голове' % (d['head'][:12], head[:12]))
    want = 'only-red' if of else 'full'
    if d['mode'] != want:
        reason('STAND-REPORT-NOT-FULL' if not of else 'STAND-REPORT-TRUNCATED',
               'mode %s, нужен %s%s' % (d['mode'], want, '' if of else ' — only-red основанием ready и CI не служит'))
    planned = num(d.get('planned'))
    if planned < 0 or planned != len(suites):
        reason('STAND-REPORT-TRUNCATED', 'исполнено наборов %d из planned %s — перепись обрезана' % (len(suites), d.get('planned')))
    if expected is not None:
        have = {str(s.get('job') or '') for s in suites}
        for j in expected:
            if j not in have:
                reason('STAND-REPORT-UNCOVERED', 'задание CI %s ожидаемо по выбору головы, набора с job %s в отчёте нет' % (j, j))
        extra = sorted(have - set(expected) - {''})
        if extra:
            census.append('наборы сверх ожидаемого: %s' % ', '.join(extra))
    ctx, proof = str(d.get('context') or ''), str(d.get('proof') or '').strip()
    if not ctx.endswith('-client') and not re.match(r'local\b.*\bproof=\S', proof):
        reason('STAND-REPORT-LOCAL', 'контекст «%s» не внешний (-client), proof «%s» не формы журнала слота «local … proof=»' % (ctx, proof[:80]))
    if num(d.get('residue')) != 0:
        reason('STAND-REPORT-RESIDUE', 'остаток переписи после прогона %s, нужен 0' % d.get('residue'))
    green = notrun = 0
    alive = {}
    for s in suites:
        name, out = str(s.get('name') or '?'), s.get('outcome')
        ex, tot = num(s.get('executed')), num(s.get('total'))
        if out == 'green':
            if tot < 1 or ex != tot:
                reason('STAND-REPORT-TRUNCATED', '%s: зелёный при исполнено %s из %s' % (name, s.get('executed'), s.get('total')))
            else:
                green += 1
        elif out == 'red':
            q = str(s.get('quote') or '').strip()
            if not q:
                reason('STAND-REPORT-NO-QUOTE', '%s: красный без дословной цитаты отказа' % name)
            reason('STAND-REPORT-RED', '%s: «%s» · корень: %s' % (name, q[:300], str(s.get('root') or 'не назван')))
        elif out == 'not-run':
            why = str(s.get('reason') or '')
            if why not in RELAX:
                reason('STAND-REPORT-NOT-RUN', '%s: не выполнилось, причина «%s» вне ведомости послаблений' % (name, why))
                continue
            if why not in alive:
                r, n, _ = RELAX[why]
                p = subprocess.run([gh, 'api', 'repos/%s/issues/%s' % (r, n)], capture_output=True, text=True)
                if p.returncode != 0:
                    void('площадка не ответила о задаче послабления %s#%s: %s' % (r, n, p.stderr.strip()[:200]))
                try:
                    alive[why] = json.loads(p.stdout).get('state') == 'open'
                except (ValueError, AttributeError):
                    void('ответ о задаче послабления %s#%s не разбирается' % (r, n))
            if alive[why]:
                notrun += 1
                census.append('не выполнилось (не зелёное): %s — %s, послабление до закрытия %s#%s' % ((name, RELAX[why][2]) + RELAX[why][:2]))
            else:
                reason('STAND-RELAX-EXPIRED', '%s: послабление %s истекло — %s#%s закрыта; снять строку ведомости и прогнать набор' % ((name, why) + RELAX[why][:2]))
        else:
            reason('STAND-REPORT-MISSING', '%s: исход «%s» вне словаря green | red | not-run' % (name, out))
    if (suites or expected) and green == 0:
        reason('STAND-REPORT-NOTHING-RUN', 'зелёным исполнено 0 наборов из %d' % len(suites))
    census.append('исход: зелёных %d · красных %d · не выполнилось %d' % (green, sum(1 for s in suites if s.get('outcome') == 'red'), notrun))
    if of:
        prev = load(of)
        if prev is None:
            void('прежний отчёт %s не разбирается' % of)
        mine = {str(s.get('name')) for s in suites}
        for s in prev['suites']:
            if s.get('outcome') == 'red' and str(s.get('name')) not in mine:
                reason('STAND-REPORT-RED-DROPPED', '%s: красный в %s, в прогоне «только красное» его нет' % (s.get('name'), of))

for c in census:
    print('CENSUS\t' + c)
for code, text in reasons:
    print('REASON\t%s\t%s' % (code, text))
print('VERDICT\t%s\tкод %d; причин %d' % ('green' if not reasons else 'stop', 1 if reasons else 0, len(reasons)))
sys.exit(1 if reasons else 0)
PY
