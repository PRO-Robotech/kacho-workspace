#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""lessons.py — ядро сборщика уроков (ws#1199, новый флоу, часть 8). Зовётся через collect.sh.

Предмет: урок полосы (`ai-tooling.md#at-lane-retro`) доходит до ведомости сам, повтор класса
считается машиной, а не памятью диспетчера. Источники (только чтение):
  * журналы агентов верхнего уровня `<проект>/<сессия>/subagents/agent-*.jsonl` — строка
    «урок:» ПОСЛЕДНЕГО блока «### ВОЗВРАТ» в тексте ответа модели;
  * итоги агентов workflow `<проект>/<сессия>/subagents/workflows/wf_*/journal.jsonl` —
    запись `result`: строка (тот же блок ВОЗВРАТ) либо объект с полем `lesson` (wave.js);
  * главный поток `<проект>/<сессия>.jsonl` — строки «урок диспетчера: <класс> · <где>»
    в тексте ответа модели; ключ — `оркестровка:<класс>`;
  * волны `<WS>/tmp/wave-*/reports/lessons.md` (wave.js, строка «<полоса> · <класс> · <где>»)
    и `<WS>/tmp/wave-*/errors.md` (wave-errors.sh; ключ — `оркестровка:<класс счётчика>`).
Расположение журналов — то же, что читает `scripts/stall-census.sh`.

Урок «—» — не урок. Урок без «·» — БЕЗ КЛЮЧА («урок без места — не урок»): в счёт классов
не идёт, печатается отдельно и держит сигнал, пока его не снимут `mark ?<id> rejected`.
Ключ класса — первый сегмент до «·», нормализованный (регистр, кавычки, «ё», пробелы), затем
таблица синонимов `aliases.tsv` (регулярное выражение → ключ; первое совпадение).

Ведомость `lessons.jsonl` — ТОЛЬКО дописывается: запись урока {t:lesson,id,…} и событие
статуса {t:status,key,status,ref,ts}. id = sha1(сессия|агент|sha1(строки)) — повторный сбор
той же строки ничего не дописывает. Состояние разбора (смещения файлов, последний сигнал) —
`lessons-scan.json`, кэш: его потеря стоит лишь повторного чтения.

Статусы класса (закрытый словарь): open → edited (разовая правка) → mechanism (#N) →
landed (PR) → verified (путь инъекции, которая краснеет); rejected — не урок.
Пороги: класс с ≥ THRESHOLD случаями при open|edited — «нужен механизм»; случай позже
landed|verified — «механизм не держит»; open старше суток — «старше суток».

Коды: scan — 0 прочитано, 2 читать нечего (журналов нет: это не «уроков 0»);
status — 0 делать нечего, 1 есть что делать (перечень), 2 читать нечего;
signal — 0 молчать, 1 печатать (строка сигнала на stdout); mark — 0 записано, 1 отказ.
"""
import calendar
import glob
import hashlib
import json
import os
import re
import signal
import sys
import time

THRESHOLD = 2
# Ввод части 8: уроки раньше — история (report их видит), сигнал судит с этой даты.
SINCE = '2026-10-18'
DAY = 86400
STATUSES = ('open', 'edited', 'mechanism', 'landed', 'verified', 'rejected')
HELD = ('landed', 'verified')
RET_RE = re.compile(r'^\s*[-*]?\s*урок:\s*(.+?)\s*$', re.M)
DISP_RE = re.compile(r'^\s*[-*]?\s*урок диспетчера:\s*([^\n]+)', re.M)
# Место без «·»: фраза «Предотвратить …» / «где предотвратить …» после точки — тоже разделитель.
PLACE_RE = re.compile(r'[.;:]\s+(?=(?:где\s+)?предотвра)', re.I)
NOTHING = ('—', '-', '–', '', 'нет', '— нет')
ORCH = 'оркестровка'
TAIL_FIRST = 1 << 18  # агентский журнал при первом осмотре — хвостом: ВОЗВРАТ в конце


def die(msg, code=2):
    print('lessons: VOID — ' + msg, file=sys.stderr)
    sys.exit(code)


def sha(s):
    return hashlib.sha1(s.encode('utf-8')).hexdigest()


def load_aliases(path):
    out = []
    if not path or not os.path.isfile(path):
        return out
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        line = line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) < 2 or not parts[0] or not parts[1].strip():
            die('%s:%d — строка синонима не «регэксп<TAB>ключ»' % (path, n))
        out.append((re.compile(parts[0], re.I), parts[1].strip()))
    return out


def norm(seg):
    s = seg.lower().replace('ё', 'е')
    s = re.sub(r'[`«»"\'*_]', '', s)
    return re.sub(r'\s+', ' ', s).strip(' .,:;—-')


def key_of(raw, aliases):
    """Ключ класса или None (урок без места)."""
    if '·' in raw:
        seg = raw.split('·', 1)[0]
    else:
        m = PLACE_RE.search(raw)
        if not m:
            return None
        seg = raw[:m.start()]
    seg = norm(seg)
    if not seg:
        return None
    for rx, canon in aliases:
        if rx.search(seg):
            return canon
    return seg[:80]


def lesson_of(text):
    """Строка «урок:» последнего блока ВОЗВРАТ; None — блока нет или урок «—»."""
    i = text.rfind('### ВОЗВРАТ')
    if i < 0:
        return None
    m = None
    for m in RET_RE.finditer(text, i):
        pass
    if not m:
        return None
    v = m.group(1).strip()
    return None if v in NOTHING or v.startswith('—') else v


def texts(rec):
    m = rec.get('message')
    if rec.get('type') != 'assistant' or not isinstance(m, dict):
        return []
    c = m.get('content')
    if isinstance(c, str):
        return [c]
    return [x.get('text') or '' for x in c or [] if isinstance(x, dict) and x.get('type') == 'text']


def epoch(s):
    try:
        return float(calendar.timegm(time.strptime(s[:19], '%Y-%m-%dT%H:%M:%S')))
    except Exception:
        return None


class Store:
    def __init__(self, d):
        self.dir = d
        self.ledger = os.path.join(d, 'lessons.jsonl')
        self.statef = os.path.join(d, 'lessons-scan.json')
        self.lessons, self.status, self.ids = [], {}, set()
        if os.path.isfile(self.ledger):
            for raw in open(self.ledger, encoding='utf-8'):
                try:
                    r = json.loads(raw)
                except Exception:
                    continue
                if not isinstance(r, dict):
                    continue
                if r.get('t') == 'lesson' and r.get('id'):
                    if r['id'] in self.ids:
                        continue
                    self.ids.add(r['id'])
                    self.lessons.append(r)
                elif r.get('t') == 'status' and r.get('key'):
                    self.status.setdefault(r['key'], []).append(r)
        try:
            self.state = json.load(open(self.statef, encoding='utf-8'))
            if not isinstance(self.state, dict):
                self.state = {}
        except Exception:
            self.state = {}
        self.state.setdefault('files', {})
        self.new = []

    def add(self, sid, agent, src, ts, raw, key):
        lid = sha('%s|%s|%s' % (sid, agent, sha(raw)))
        if lid in self.ids:
            return False
        self.ids.add(lid)
        r = {'t': 'lesson', 'id': lid, 'sid': sid, 'agent': agent, 'src': src,
             'ts': ts, 'key': key, 'raw': raw[:600]}
        self.lessons.append(r)
        self.new.append(r)
        return True

    def flush(self):
        os.makedirs(self.dir, exist_ok=True)
        if self.new:
            with open(self.ledger, 'a', encoding='utf-8') as f:
                for r in self.new:
                    f.write(json.dumps(r, ensure_ascii=False) + '\n')
            self.new = []
        tmp = self.statef + '.tmp.%d' % os.getpid()
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(self.state, f, ensure_ascii=False)
        os.replace(tmp, self.statef)

    def mark(self, key, st, ref, now):
        os.makedirs(self.dir, exist_ok=True)
        r = {'t': 'status', 'key': key, 'status': st, 'ref': ref, 'ts': now}
        with open(self.ledger, 'a', encoding='utf-8') as f:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
        self.status.setdefault(key, []).append(r)


def new_lines(store, path, first_tail, deadline):
    """Новые полные строки файла с прошлого смещения (bytes); смещение двигается до конца
    последней полной строки. Первый осмотр — с хвоста first_tail (0 — весь файл)."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return []
    st = store.state['files'].get(path)
    off = st if isinstance(st, int) else None
    if off is not None and off > size:
        off = None  # файл переписан
    if off is None:
        off = max(0, size - first_tail) if first_tail else 0
        skip_first = off > 0
    else:
        skip_first = False
    if off == size:
        return []
    out = []
    with open(path, 'rb') as f:
        f.seek(off)
        chunk = 1 << 24
        while True:
            data = f.read(chunk)
            if not data:
                break
            cut = data.rfind(b'\n')
            if cut < 0:
                if len(data) < chunk:
                    break  # хвост без перевода строки — дописывается
                f.seek(off)
                chunk *= 2
                continue
            body = data[:cut]
            lines = body.split(b'\n')
            if skip_first:
                lines, skip_first = lines[1:], False
            out.extend(lines)
            off += cut + 1
            f.seek(off)
            if time.time() > deadline:
                break
    store.state['files'][path] = off
    return out


def scan(store, proj, waves, aliases, deadline, census):
    sessions = sorted(d for d in glob.glob(os.path.join(proj, '*')) if os.path.isdir(d))
    mains = sorted(glob.glob(os.path.join(proj, '*.jsonl')))
    agents, wfj = [], []
    for s in sessions:
        agents += glob.glob(os.path.join(s, 'subagents', 'agent-*.jsonl'))
        wfj += glob.glob(os.path.join(s, 'subagents', 'workflows', 'wf_*', 'journal.jsonl'))
    wl = sorted(glob.glob(os.path.join(waves, 'wave-*', 'reports', 'lessons.md')))
    we = sorted(glob.glob(os.path.join(waves, 'wave-*', 'errors.md')))
    census['files'] = len(mains) + len(agents) + len(wfj) + len(wl) + len(we)
    if not (mains or agents or wfj or wl or we):
        return False
    # Свежие — первыми: при исчерпании бюджета догоняются в следующий раз.
    def fresh(p):
        try:
            return -os.path.getmtime(p)
        except OSError:
            return 0
    for p in sorted(agents, key=fresh):
        if time.time() > deadline:
            census['deferred'] += 1
            continue
        sid = os.path.basename(os.path.dirname(os.path.dirname(p)))
        aid = os.path.basename(p)[len('agent-'):-len('.jsonl')]
        for ln in new_lines(store, p, TAIL_FIRST, deadline):
            if 'ВОЗВРАТ'.encode() not in ln:
                continue
            try:
                r = json.loads(ln)
            except Exception:
                continue
            if not isinstance(r, dict):
                continue
            for t in texts(r):
                v = lesson_of(t)
                if v:
                    census['read'] += store.add(sid, aid, 'agent', epoch(r.get('timestamp') or '') or os.path.getmtime(p), v, key_of(v, aliases))
        census['agents'] += 1
    for p in sorted(wfj, key=fresh):
        if time.time() > deadline:
            census['deferred'] += 1
            continue
        wdir = os.path.dirname(p)
        sid = os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(wdir))))
        for ln in new_lines(store, p, 0, deadline):
            try:
                r = json.loads(ln)
            except Exception:
                continue
            if not isinstance(r, dict) or r.get('type') != 'result' or not r.get('agentId'):
                continue
            res, v = r.get('result'), None
            if isinstance(res, dict):
                v = res.get('lesson')
                v = v.strip() if isinstance(v, str) and v.strip() not in NOTHING else None
            elif isinstance(res, str):
                v = lesson_of(res)
            if v:
                af = os.path.join(wdir, 'agent-%s.jsonl' % r['agentId'])
                ts = os.path.getmtime(af) if os.path.exists(af) else os.path.getmtime(p)
                census['read'] += store.add(sid, r['agentId'], 'workflow', ts, v, key_of(v, aliases))
        census['agents'] += 1
    for p in sorted(mains, key=fresh):
        if time.time() > deadline:
            census['deferred'] += 1
            continue
        sid = os.path.basename(p)[:-len('.jsonl')]
        for ln in new_lines(store, p, 0, deadline):
            if 'урок диспетчера:'.encode() not in ln:
                continue
            try:
                r = json.loads(ln)
            except Exception:
                continue
            if not isinstance(r, dict):
                continue
            for t in texts(r):
                for m in DISP_RE.finditer(t):
                    v = m.group(1).strip()
                    if v in NOTHING:
                        continue
                    k = key_of(v, aliases)
                    k = k if k is None or k == ORCH or k.startswith(ORCH + ':') else ORCH + ':' + k
                    census['read'] += store.add(sid, 'dispatcher', 'dispatcher', epoch(r.get('timestamp') or '') or os.path.getmtime(p), v, k)
        census['mains'] += 1
    for p in wl:
        wave = os.path.basename(os.path.dirname(os.path.dirname(p)))
        for ln in new_lines(store, p, 0, deadline):
            s = ln.decode('utf-8', 'replace').strip()
            if not s or s.startswith('#'):
                continue
            lane, _, rest = s.partition(' · ')
            v = rest.strip() if rest else s
            if v in NOTHING:
                continue
            census['read'] += store.add(wave, lane.strip(), 'wave', os.path.getmtime(p), v, key_of(v, aliases))
    for p in we:
        wave = os.path.basename(os.path.dirname(p))
        for ln in new_lines(store, p, 0, deadline):
            cells = [c.strip() for c in ln.decode('utf-8', 'replace').split('|')]
            if len(cells) != 8 or cells[1] in ('когда (UTC)', '') or set(cells[1]) <= set('-'):
                continue
            when, lane, step, cls, _h, note = cells[1:7]
            v = '%s · %s: %s' % (cls, step, note)
            census['read'] += store.add(wave, lane, 'wave-errors', epoch(when.replace('Z', ':00')) or os.path.getmtime(p), v, ORCH + ':' + norm(cls)[:80])
    return True


def current(store, key):
    ev = store.status.get(key) or []
    return (ev[-1]['status'], ev[-1].get('ref', ''), ev[-1]['ts']) if ev else ('open', '', 0)


def held_since(store, key):
    """Время первого landed|verified после последнего open (механизм влит)."""
    t = None
    for e in store.status.get(key) or []:
        if e['status'] in HELD and t is None:
            t = e['ts']
        elif e['status'] in ('open', 'edited', 'mechanism'):
            t = None
    return t


def class_of(r, aliases):
    """Ключ случая — ПЕРЕСЧЁТОМ из строки по текущей таблице синонимов: новая строка
    `aliases.tsv` сводит и прежние случаи. Ключ счётчика волны — как записан."""
    if r.get('src') == 'wave-errors':
        k = r.get('key')
    else:
        k = key_of(r.get('raw', ''), aliases)
        if k is not None and r.get('src') == 'dispatcher' and not (k == ORCH or k.startswith(ORCH + ':')):
            k = ORCH + ':' + k
    return k if k else '?' + r['id'][:8]


def analyse(store, now, aliases, since=0.0):
    # Случай — различная СТРОКА урока: та же строка из двух источников (итог workflow и
    # lessons.md той же волны) — один случай, а не повтор.
    by, seen = {}, set()
    for r in store.lessons:
        if (r.get('ts') or 0) < since:
            continue
        k = class_of(r, aliases)
        rh = (k, sha(re.sub(r'\s+', ' ', r.get('raw', '')).strip()))
        if rh in seen:
            continue
        seen.add(rh)
        by.setdefault(k, []).append(r)
    need, fails, stale, unkeyed, fresh = [], [], [], [], 0
    for k, rs in sorted(by.items()):
        st, ref, _ = current(store, k)
        if st == 'rejected':
            continue
        if k.startswith('?'):
            unkeyed.append((k, rs))
            continue
        if st == 'open':
            fresh += len(rs)
        if len(rs) >= THRESHOLD and st in ('open', 'edited'):
            need.append((k, rs, st))
        hs = held_since(store, k)
        if st in HELD and hs is not None:
            late = [r for r in rs if (r.get('ts') or 0) > hs]
            if late:
                fails.append((k, late, ref))
        if st == 'open' and min((r.get('ts') or now) for r in rs) < now - DAY:
            stale.append((k, rs))
    return by, need, fails, stale, unkeyed, fresh


def line_of(need, fails, stale, unkeyed, fresh):
    s = '📚 УРОКИ: новых %d · классов с повтором без задачи %d · старше суток %d' % (fresh, len(need), len(stale))
    if fails:
        s += ' · механизм не держит %d' % len(fails)
    if unkeyed:
        s += ' · без ключа %d' % len(unkeyed)
    return s


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    a = sys.argv[1:]
    if not a:
        die('нет команды: scan | status | signal | mark <ключ> <статус> <ссылка> | report', 1)
    cmd, a = a[0], a[1:]
    opts = {'--projects-dir': os.environ.get('LESSONS_PROJECTS_DIR', ''),
            '--waves-dir': os.environ.get('LESSONS_WAVES_DIR', ''),
            '--dir': os.environ.get('LESSONS_DIR', ''),
            '--aliases': os.environ.get('LESSONS_ALIASES', ''),
            '--budget': '5', '--now': '', '--since': os.environ.get('LESSONS_SINCE', SINCE)}
    rest = []
    while a:
        if a[0] in opts and len(a) > 1:
            opts[a[0]] = a[1]
            a = a[2:]
        else:
            rest.append(a.pop(0))
    now = float(opts['--now']) if opts['--now'] else time.time()
    if not opts['--dir']:
        die('каталог ведомости не задан (LESSONS_DIR)')
    store = Store(opts['--dir'])
    aliases = load_aliases(opts['--aliases'])

    if cmd == 'mark':
        if len(rest) != 3 or rest[1] not in STATUSES:
            print('lessons: ОТКАЗ — mark <ключ> <%s> <ссылка>' % '|'.join(STATUSES), file=sys.stderr)
            sys.exit(1)
        k, st, ref = rest
        if st == 'mechanism' and not re.search(r'#\d+', ref):
            print('lessons: ОТКАЗ — mechanism без задачи «<репо>#N»', file=sys.stderr)
            sys.exit(1)
        if st == 'verified' and not (ref.endswith('.sh') and os.path.isfile(os.path.join(os.environ.get('WS', '.'), ref))):
            print('lessons: ОТКАЗ — verified только с путём инъекции, которая краснеет (scripts/…inject.sh)', file=sys.stderr)
            sys.exit(1)
        if k == '*':
            # Остаток пачки: все ОТКРЫТЫЕ классы окна разом (разовая правка либо «не урок»).
            if st not in ('edited', 'rejected'):
                print('lessons: ОТКАЗ — «*» только для edited|rejected', file=sys.stderr)
                sys.exit(1)
            since = calendar.timegm(time.strptime(opts['--since'], '%Y-%m-%d')) if opts['--since'] else 0.0
            keys = sorted(x for x in analyse(store, now, aliases, since)[0] if current(store, x)[0] == 'open')
        else:
            keys = [k]
            if k not in {class_of(r, aliases) for r in store.lessons}:
                print('lessons: ОТКАЗ — класса «%s» в ведомости нет' % k, file=sys.stderr)
                sys.exit(1)
        for x in keys:
            store.mark(x, st, ref, now)
        print('lessons: %s → %s %s (классов %d)' % (k, st, ref, len(keys)))
        return 0

    census = {'files': 0, 'agents': 0, 'mains': 0, 'read': 0, 'deferred': 0}
    if cmd in ('scan', 'signal'):
        proj = opts['--projects-dir']
        if not proj:
            die('каталог журналов проекта не задан')
        deadline = time.time() + float(opts['--budget'])
        ok = scan(store, proj, opts['--waves-dir'] or '/nonexistent', aliases, deadline, census)
        store.flush()
        if not ok and not store.lessons:
            if cmd == 'scan':
                die('журналов нет: %s — читать нечего, это не «уроков 0»' % proj)
            return signal_out(store, 'void', '📚 УРОКИ НЕ СОБРАНЫ: журналов нет (%s) → tooling-maintainer; это не «уроков 0».' % proj, now)
        if cmd == 'scan':
            print('[CENSUS] lessons: файлов %d (агентов %d, главных %d), новых уроков %d, отложено бюджетом %d; в ведомости %d'
                  % (census['files'], census['agents'], census['mains'], census['read'], census['deferred'], len(store.lessons)))
            return 0
    since = calendar.timegm(time.strptime(opts['--since'], '%Y-%m-%d')) if opts['--since'] else 0.0
    by, need, fails, stale, unkeyed, fresh = analyse(store, now, aliases, since)
    if cmd == 'report':
        rep = sum(1 for k, rs in by.items() if not k.startswith('?') and len(rs) >= THRESHOLD)
        held = [k for k in by if current(store, k)[0] in HELD]
        bad = [k for k, _, _ in fails]
        print('[CENSUS] lessons%s: уроков %d, классов %d, с повтором (≥%d) %d, без ключа %d; механизмов влито %d, из них не держат %d (%s)'
              % (' с ' + opts['--since'] if since else '', sum(len(v) for v in by.values()), len([k for k in by if not k.startswith('?')]), THRESHOLD, rep, len(unkeyed),
                 len(held), len(bad), ('доля %.0f %%' % (100.0 * len(bad) / len(held))) if held else 'доли нет'))
        for k, rs in sorted(by.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            st, ref, _ = current(store, k)
            print('%3d  %-10s %-14s %s' % (len(rs), st, ref, k))
        return 0
    if cmd not in ('status', 'signal'):
        die('неизвестная команда «%s»' % cmd, 1)
    if not store.lessons and cmd == 'status' and not os.path.isfile(store.ledger):
        die('ведомости нет: %s — сбор не вёлся' % store.ledger)
    head = line_of(need, fails, stale, unkeyed, fresh)
    body = []
    for k, rs, st in need:
        body.append('NEED-MECHANISM %s — случаев %d (%s): %s' % (k, len(rs), st, rs[-1]['raw'][:140]))
    for k, late, ref in fails:
        body.append('MECHANISM-FAILS %s — повтор после %s: %d, последний: %s' % (k, ref, len(late), late[-1]['raw'][:140]))
    for k, rs in stale:
        body.append('STALE %s — открыт дольше суток: %s' % (k, rs[0]['raw'][:140]))
    for k, rs in unkeyed:
        body.append('UNKEYED %s — урок без «·» (без места): %s/%s: %s' % (k, rs[0]['sid'][:8], rs[0]['agent'], rs[0]['raw'][:140]))
    todo = bool(need or fails or stale or unkeyed)
    if cmd == 'status':
        print('[CENSUS] lessons: уроков %d, классов %d' % (len(store.lessons), len([k for k in by if not k.startswith('?')])))
        if todo:
            print(head)
            print('\n'.join(body))
            return 1
        print('lessons: делать нечего')
        return 0
    if not todo:
        store.state.pop('signal', None)
        store.flush()
        return 0
    sig = sha('\n'.join(sorted(b.split(' — ')[0] for b in body)))
    return signal_out(store, sig, head + '\n' + '\n'.join(body[:12]), now)


def signal_out(store, sig, text, now):
    """Печатать только новое: тот же перечень повторяется не чаще раза в сутки."""
    last = store.state.get('signal') or {}
    if last.get('sig') == sig and now - float(last.get('ts') or 0) < DAY:
        return 0
    store.state['signal'] = {'sig': sig, 'ts': now}
    store.flush()
    print(text)
    return 1


if __name__ == '__main__':
    sys.exit(main())
