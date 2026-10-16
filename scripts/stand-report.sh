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
#   stand-report.sh check <отчёт.json> --head <sha40> [--of <прежний отчёт.json>]
# Без --of судится ПОЛНЫЙ прогон (mode full) — единственное основание для ready и
# вливания. С --of — прогон «только красное» (mode only-red): в нём обязан быть
# КАЖДЫЙ набор, красный в прежнем отчёте; зелёный only-red — основание лишь для
# полного прогона, не для CI.
#
# ФОРМА ОТЧЁТА (пишет ci-watcher; JSON-объект):
#   head     — sha40 головы, на которой гнали;          mode — full | only-red;
#   context  — контекст кластера; внешний — суффикс -client (remote-heavy/run.sh);
#              иное — лишь при непустом proof (строка «local … proof=» журнала слота);
#   ns       — пространство имён прогона;               residue — остаток переписи после (0);
#   planned  — число наборов переписи (затронутое теми же целями, что CI), ≥ 1;
#   suites   — [{name, outcome: green|red|not-run, executed, total, quote, root, reason}].
#
# ЧТО СУДИТСЯ — строка REASON<TAB><код><TAB><пояснение> на причину:
#   STAND-REPORT-MISSING   — файла нет, он не JSON-объект или без полей формы;
#   STAND-REPORT-STALE     — head отчёта ≠ --head: прогон о другой голове;
#   STAND-REPORT-NOT-FULL  — без --of отчёт не mode full (only-red основанием CI не служит);
#   STAND-REPORT-TRUNCATED — наборов в отчёте ≠ planned, planned < 1, у зелёного
#                            executed < total либо total < 1: «исполнено N из M»;
#   STAND-REPORT-RED       — набор red (печатается дословная цитата и корень);
#   STAND-REPORT-NO-QUOTE  — у red нет цитаты отказа: класс корня без цитаты — не класс;
#   STAND-REPORT-NOT-RUN   — набор not-run без живого послабления ведомости ниже;
#   STAND-RELAX-EXPIRED    — послабление названо, а его задача закрыта: снять строку;
#   STAND-REPORT-NOTHING-RUN — исполнено зелёным 0 наборов;
#   STAND-REPORT-LOCAL     — контекст не внешний и proof пуст;
#   STAND-REPORT-RESIDUE   — residue ≠ 0;
#   STAND-REPORT-RED-DROPPED — с --of: красный прежде набор в only-red отсутствует.
#
# ПОСЛАБЛЕНИЯ — закрытая ведомость RELAX ниже: причина not-run → задача, пока открыта.
# Живость спрашивается у площадки (`gh api repos/<репо>/issues/<N>` → state open);
# закрыта — STAND-RELAX-EXPIRED (само истекает, `gate-authoring` §9). «Не выполнилось»
# не зелёное: оно печатается строкой CENSUS поимённо и не засчитывается в исполненное.
#
# ИСХОДЫ: 0 — причин нет; 1 — причины строками REASON; 2 — VOID: довод не тот, нет
# python3, площадка не ответила о послаблении. Перепись — строками CENSUS всегда.
# ВХОД ПОДМЕНЯЕМ (scripts/stand-report-inject.sh): STAND_REPORT_GH — вместо `gh`.
set -uo pipefail

void() { printf 'VOID\t%s\n' "$1"; printf 'VERDICT\tunread\tкод 2\n'; exit 2; }
[ "${1:-}" = check ] || void "первым доводом — check"
REP="${2:-}"; [ -n "$REP" ] || void "нет пути отчёта"
shift 2
HEAD=""; OF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --head) HEAD="${2:-}"; shift 2 ;;
        --of) OF="${2:-}"; [ -r "$OF" ] || void "прежний отчёт «$OF» не читается"; shift 2 ;;
        *) void "неизвестный довод «$1»" ;;
    esac
done
[[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || void "--head «$HEAD» не sha40"
command -v python3 > /dev/null 2>&1 || void "нет python3"

REP="$REP" HEAD="$HEAD" OF="$OF" GH="${STAND_REPORT_GH:-gh}" python3 - <<'PY'
import json, os, re, subprocess, sys

# Ведомость послаблений: причина not-run → задача, которая её снимает. Закрыта — истекло.
RELAX = {
    'NO-PR-IMAGES': ('PRO-Robotech/kacho-workspace', '1110',
                     'стенд проб не принимает образы ветки PR (ws#1110 п.1) — newman и консоль ветки до CI не прогнать'),
}
reasons, census = [], []
rep, head, of, gh = os.environ['REP'], os.environ['HEAD'], os.environ['OF'], os.environ['GH']


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
    if planned < 1 or planned != len(suites):
        reason('STAND-REPORT-TRUNCATED', 'исполнено наборов %d из planned %s — перепись обрезана' % (len(suites), d.get('planned')))
    ctx, proof = str(d.get('context') or ''), str(d.get('proof') or '').strip()
    if not ctx.endswith('-client') and not proof:
        reason('STAND-REPORT-LOCAL', 'контекст «%s» не внешний (-client), доказательства недоступности (proof) нет' % ctx)
    if num(d.get('residue')) != 0:
        reason('STAND-REPORT-RESIDUE', 'остаток переписи после прогона %s, нужен 0' % d.get('residue'))
    green = notrun = 0
    alive = {}
    for s in suites:
        name, out = str(s.get('name') or '?'), s.get('outcome')
        ex, tot = num(s.get('executed')), num(s.get('total'))
        if out == 'green':
            if tot < 1 or ex < tot:
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
    if suites and green == 0:
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
