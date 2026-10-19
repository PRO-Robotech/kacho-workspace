#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""lessons.py — ядро сборщика уроков (ws#1199, новый флоу, часть 8). Зовётся через collect.sh.

Предмет: урок полосы (`ai-tooling.md#at-lane-retro`) доходит до ведомости сам, повтор класса
считается машиной, а не памятью диспетчера. Источники (только чтение):
  * журналы агентов верхнего уровня `<проект>/<сессия>/subagents/agent-*.jsonl` — строка
    «урок:» ПОСЛЕДНЕГО блока «### ВОЗВРАТ» в тексте ответа модели;
  * итоги агентов workflow `<проект>/<сессия>/subagents/workflows/wf_*/journal.jsonl` —
    запись `result`: строка (тот же блок ВОЗВРАТ) либо объект — поле `lesson` (wave.js) и блок
    ВОЗВРАТ в ЛЮБОМ строковом поле на любой глубине (ret, note, notes[], executed, …: перепись
    форм итогов 2026-10-18 — 30 полей); полоса волны (`impl:`) узнаётся по заданию агента —
    путь `wave-*/reports/lessons.md` и префикс «<полоса> · »;
  * главный поток `<проект>/<сессия>.jsonl` — строки «урок диспетчера: <класс> · <где>»
    в тексте ответа модели; ключ — `оркестровка:<класс>`;
  * волны `<WS>/tmp/wave-*/reports/lessons.md` (wave.js, строка «<полоса> · <класс> · <где>»)
    и `<WS>/tmp/wave-*/errors.md` (wave-errors.sh; ключ — `оркестровка:<класс счётчика>`).
Расположение журналов — то же, что читает `scripts/stall-census.sh`.

Первый осмотр файла — ВЕСЬ файл (не хвост: дозапущенный агент пишет ВОЗВРАТ и в начале), но
разбираются лишь строки с байтами признака; бюджет — догоном: смещение сохраняется, хотя бы
один кусок читается за вызов. Урок «—» — не урок. Урок без ключа в тексте (нет ни «·», ни
фразы места PLACE_RE, либо сегмент до них пуст) — БЕЗ КЛЮЧА («урок без места — не урок»): в
счёт классов не идёт, печатается отдельно и держит сигнал, пока ему не дадут ключ
`rekey ?<id> <ключ>` (событие {t:rekey,id,key,ts}; урок с ключом в тексте его не берёт; ключ
с «·», начатый «?» либо пустой — отказ; из нескольких событий одному уроку действует
последнее) либо не снимут `mark ?<id> rejected`.
Ключ класса — первый сегмент до «·» либо ключ события rekey, и ОБА проходят одну функцию
`canon`: нормализация (регистр, кавычки, «ё», пробелы), затем таблица синонимов `aliases.tsv`
(регулярное выражение → ключ; первое совпадение) — пересчётом при каждом чтении.
Ключ СЛИШКОМ ОБЩИЙ (ws#1248) — одно слово (слова делят пробел и дефис, префикс «оркестровка:»
снят) и не итог строки синонима. Такой класс СКЛЕЕН, когда у его уроков (кроме строк счётчика
волны — словарь wave-errors.sh) ≥ 2 разных «где» (текст после первого «·»): в повтор не идёт,
печатается GLUED с id по месту; mark его — отказ, «*» его пропускает; развести — `rekey`
расходящемуся уроку (rekey берёт и урок с общим ключом в тексте; новый ключ из одного слова —
отказ, кроме итога синонима). Порога по числу знаков нет: на живой ведомости 2026-10-19 у
ключей из ≥ 2 слов, кроме синонимов, короче 9 знаков — ни одного.

Ведомость `lessons.jsonl` — ТОЛЬКО дописывается: запись урока {t:lesson,id,…} и событие
статуса {t:status,key,status,ref,ts}. id = sha1(сессия|агент|sha1(строки)) — повторный сбор
той же строки ничего не дописывает. Состояние разбора (смещения файлов, последний сигнал) —
`lessons-scan.json`, кэш: его потеря стоит лишь повторного чтения.

Статусы класса (закрытый словарь): open → edited (разовая правка) → mechanism (#N) →
landed (PR) → verified (путь инъекции, которая краснеет); rejected — не урок.
Случай — урок одного агента: одна строка у двух РАЗНЫХ агентов — два случая; сводятся лишь
повторный сбор того же агента (id) и пара «итог workflow ↔ строка lessons.md той же волны и
полосы»; урок пересказчика (задание называет журнал другого агента) при том же тексте у
автора — не случай. Пороги: класс с ≥ THRESHOLD случаями при open|edited — «нужен механизм»; случай позже
landed|verified — «механизм не держит»; open старше суток — «старше суток».

Коды: scan — 0 прочитано, 2 читать нечего (журналов нет: это не «уроков 0»);
status — 0 делать нечего, 1 есть что делать (перечень), 2 читать нечего; `status <ключ>` судит один
класс: 0 — закрыт исходом, 1 — есть что делать, 2 — класса нет, 64 — ключей больше одного (ws#1250);
signal — 0 молчать, 1 печатать (строка сигнала на stdout); mark, rekey — 0 записано, 1 отказ;
3 — сбой сборщика (неразобранный синоним, исключение): хук печатает «НЕ СОБРАНЫ».
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
# «урок:» — с начала строки либо после «;»/«·» (ВОЗВРАТ, сжатый в одну строку поля итога).
RET_RE = re.compile(r'(?:^\s*[-*]?|[;·])\s*урок:\s*(.+?)\s*$', re.M)
# Блок без заголовка (заголовок в другом поле итога): начало — поле контракта ВОЗВРАТ.
FIELD_RE = re.compile(r'^\s*[-*]\s*(?:статус|вердикт|исход проверок|посылка|артефакты|факты|нужен следующий|вопросы владельцу|затронуто в vault):', re.M)
# Пересказчик: задание агента называет журнал другого агента («верни дословно его ВОЗВРАТ»).
RELAY_RE = re.compile(r'subagents/(?:workflows/wf_[^/\s]+/)?(?:journal|agent-[0-9a-f]+)\.jsonl')
LANE_RE = re.compile(r'(wave-[^/\s`]+)/reports/lessons\.md`? с префиксом «([^«»\s]+) · »')
DISP_RE = re.compile(r'^\s*[-*]?\s*урок диспетчера:\s*([^\n]+)', re.M)
# Место без «·»: фраза «Предотвратить …» / «где предотвратить …» после точки — тоже разделитель.
PLACE_RE = re.compile(r'[.;:]\s+(?=(?:где\s+)?предотвра)', re.I)
NOTHING = ('—', '-', '–', '', 'нет', '— нет')
ORCH = 'оркестровка'
CHUNK = int(os.environ.get('LESSONS_CHUNK') or 1 << 24)  # шов пробы догона: размер куска чтения


def die(msg, code=2):
    # 2 — читать нечего; 3 — сбой сборщика (хук: «НЕ СОБРАНЫ»).
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
        try:
            out.append((re.compile(parts[0], re.I), parts[1].strip()))
        except re.error as e:
            die('%s:%d — регэксп синонима не разобран: %s' % (path, n, e), 3)
    return out


def norm(seg):
    s = seg.lower().replace('ё', 'е')
    s = re.sub(r'[`«»"\'*_]', '', s)
    return re.sub(r'\s+', ' ', s).strip(' .,:;—-')


def canon(seg, aliases):
    """Ключ класса из сырого ключа — ОДНА функция для всех путей задания ключа (сегмент текста
    урока, событие rekey): нормализация, затем синонимы. None — ключ пуст."""
    seg = norm(seg or '')
    if not seg:
        return None
    for rx, c in aliases:
        if rx.search(seg):
            return c
    return seg[:80]


def general(k, aliases):
    """Ключ слишком общий: одно слово (пробел и дефис делят слова; префикс «оркестровка:»
    снят вместе с пробелом за двоеточием) и не итог строки синонима aliases.tsv (её завели
    решением свести)."""
    inner = (k[len(ORCH) + 1:] if k.startswith(ORCH + ':') else k).strip()
    return inner not in {c for _, c in aliases} and not re.search(r'[\s-]', inner)


def where_of(raw):
    """«Где предотвратить» урока — текст после первого «·» либо после фразы места."""
    if '·' in raw:
        return norm(raw.split('·', 1)[1])
    m = PLACE_RE.search(raw)
    return norm(raw[m.end():]) if m else ''


def glued(k, rs, aliases):
    """Класс, склеенный общим ключом: {место: уроки} при ≥ 2 разных местах, иначе пусто.
    Строки счётчика волны не судятся: их класс — из словаря wave-errors.sh."""
    if k.startswith('?') or not general(k, aliases):
        return {}
    ws = {}
    for r in rs:
        if r.get('src') != 'wave-errors':
            ws.setdefault(where_of(r.get('raw', '')), []).append(r)
    return ws if len(ws) >= 2 else {}


def glue_ids(g):
    """Перечень склейки: id первого урока каждого места и начало места в его записи."""
    def place(raw):
        return re.sub(r'\s+', ' ', raw.split('·', 1)[1] if '·' in raw else raw).strip()[:48]
    return ' · '.join('?%s «%s»' % (rs[0]['id'][:8], place(rs[0].get('raw', ''))) for _, rs in sorted(g.items(), key=lambda x: x[1][0]['id']))


def key_of(raw, aliases):
    """Ключ класса из текста урока или None (урок без места)."""
    if '·' in raw:
        seg = raw.split('·', 1)[0]
    else:
        m = PLACE_RE.search(raw)
        if not m:
            return None
        seg = raw[:m.start()]
    return canon(seg, aliases)


def lesson_of(text):
    """Строка «урок:» последнего блока ВОЗВРАТ; None — блока нет или урок «—». Блок без
    заголовка «### ВОЗВРАТ» — от последнего слова ВОЗВРАТ, иначе от первого поля контракта."""
    i = text.rfind('### ВОЗВРАТ')
    if i < 0:
        i = text.rfind('ВОЗВРАТ')
    if i < 0:
        m = FIELD_RE.search(text)
        if not m:
            return None
        i = m.start()
    m = None
    for m in RET_RE.finditer(text, i):
        pass
    if not m:
        return None
    v = m.group(1).strip()
    return None if v in NOTHING or v.startswith('—') else v


def lessons_in(o, out):
    """Уроки итога workflow: поле `lesson` и блок ВОЗВРАТ в любом строковом поле, рекурсивно."""
    if isinstance(o, str):
        v = lesson_of(o)
        if v and v not in out:
            out.append(v)
    elif isinstance(o, dict):
        v = o.get('lesson')
        if isinstance(v, str) and v.strip() not in NOTHING and not v.strip().startswith('—') and v.strip() not in out:
            out.append(v.strip())
        for k, x in o.items():
            if k != 'lesson':
                lessons_in(x, out)
    elif isinstance(o, list):
        for x in o:
            lessons_in(x, out)
    return out


def prompt_of(af):
    """Задание агента — первая строка его журнала (≤ 1 МиБ)."""
    try:
        with open(af, 'rb') as f:
            return f.readline(1 << 20).decode('utf-8', 'replace')
    except OSError:
        return ''


def lane_of(af):
    """(волна, полоса) агента волны по его заданию."""
    m = LANE_RE.search(prompt_of(af))
    return (m.group(1), m.group(2)) if m else (None, None)


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
        self.lessons, self.status, self.ids, self.rekeys = [], {}, set(), {}
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
                elif r.get('t') == 'rekey' and r.get('id') and r.get('key'):
                    self.rekeys[r['id']] = r['key']  # последнее событие выигрывает
        try:
            self.state = json.load(open(self.statef, encoding='utf-8'))
            if not isinstance(self.state, dict):
                self.state = {}
        except Exception:
            self.state = {}
        self.state.setdefault('files', {})
        self.new = []

    def add(self, sid, agent, src, ts, raw, key, wave=None, lane=None, relay=False):
        lid = sha('%s|%s|%s' % (sid, agent, sha(raw)))
        if lid in self.ids:
            return False
        self.ids.add(lid)
        r = {'t': 'lesson', 'id': lid, 'sid': sid, 'agent': agent, 'src': src,
             'ts': ts, 'key': key, 'raw': raw[:600]}
        if wave and lane:
            r['wave'], r['lane'] = wave, lane
        if relay:
            r['relay'] = True
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

    def rekey(self, lid, key, now):
        os.makedirs(self.dir, exist_ok=True)
        with open(self.ledger, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'t': 'rekey', 'id': lid, 'key': key, 'ts': now}, ensure_ascii=False) + '\n')
        self.rekeys[lid] = key

    def mark(self, key, st, ref, now):
        os.makedirs(self.dir, exist_ok=True)
        r = {'t': 'status', 'key': key, 'status': st, 'ref': ref, 'ts': now}
        with open(self.ledger, 'a', encoding='utf-8') as f:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
        self.status.setdefault(key, []).append(r)


def grep_lines(store, path, needle, deadline, census):
    """Новые полные строки файла с прошлого смещения, содержащие байты needle (None — все).
    Первый осмотр — с начала файла. Смещение — до конца последней полной прочитанной строки;
    кусок читается хотя бы один за вызов (догон: бюджет не останавливает сбор навсегда),
    недочитанный по бюджету файл — в census['deferred']."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return []
    st = store.state['files'].get(path)
    off = st if isinstance(st, int) and 0 <= st <= size else 0  # больше размера — переписан
    out = []
    if off == size:
        return out
    with open(path, 'rb') as f:
        f.seek(off)
        chunk = CHUNK
        while True:
            if census['progress'] and time.time() > deadline:
                census['deferred'] += 1
                break
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
            census['progress'] = True
            if needle is None:
                out.extend(data[:cut].split(b'\n'))
            else:
                pos = 0
                while True:
                    j = data.find(needle, pos, cut)
                    if j < 0:
                        break
                    e = data.find(b'\n', j, cut + 1)
                    out.append(data[data.rfind(b'\n', 0, j) + 1:e])
                    pos = e + 1
            off += cut + 1
            f.seek(off)
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
        sid = os.path.basename(os.path.dirname(os.path.dirname(p)))
        aid = os.path.basename(p)[len('agent-'):-len('.jsonl')]
        relay = None
        for ln in grep_lines(store, p, 'ВОЗВРАТ'.encode(), deadline, census):
            try:
                r = json.loads(ln)
            except Exception:
                continue
            if not isinstance(r, dict):
                continue
            for t in texts(r):
                v = lesson_of(t)
                if v:
                    if relay is None:
                        relay = bool(RELAY_RE.search(prompt_of(p)))
                    census['read'] += store.add(sid, aid, 'agent', epoch(r.get('timestamp') or '') or os.path.getmtime(p), v, key_of(v, aliases), relay=relay)
        census['agents'] += 1
    for p in sorted(wfj, key=fresh):
        wdir = os.path.dirname(p)
        sid = os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(wdir))))
        for ln in grep_lines(store, p, b'"result"', deadline, census):
            try:
                r = json.loads(ln)
            except Exception:
                continue
            if not isinstance(r, dict) or r.get('type') != 'result' or not r.get('agentId'):
                continue
            res = r.get('result')
            vs = [lesson_of(res)] if isinstance(res, str) else lessons_in(res, [])
            vs = [v for v in vs if v]
            if not vs:
                continue
            af = os.path.join(wdir, 'agent-%s.jsonl' % r['agentId'])
            ts = os.path.getmtime(af) if os.path.exists(af) else os.path.getmtime(p)
            wave, lane = lane_of(af)
            for v in vs:
                census['read'] += store.add(sid, r['agentId'], 'workflow', ts, v, key_of(v, aliases), wave, lane)
        census['agents'] += 1
    for p in sorted(mains, key=fresh):
        sid = os.path.basename(p)[:-len('.jsonl')]
        for ln in grep_lines(store, p, 'урок диспетчера:'.encode(), deadline, census):
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
        for ln in grep_lines(store, p, None, deadline, census):
            s = ln.decode('utf-8', 'replace').strip()
            if not s or s.startswith('#'):
                continue
            lane, _, rest = s.partition(' · ')
            v = rest.strip() if rest else s
            if v in NOTHING:
                continue
            census['read'] += store.add(wave, lane.strip(), 'wave', os.path.getmtime(p), v, key_of(v, aliases), wave, lane.strip())
    for p in we:
        wave = os.path.basename(os.path.dirname(p))
        for ln in grep_lines(store, p, None, deadline, census):
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


def class_of(r, aliases, rekeys=None):
    """Ключ случая — ПЕРЕСЧЁТОМ из строки по текущей таблице синонимов: новая строка
    `aliases.tsv` сводит и прежние случаи. Ключ счётчика волны — как записан. Урок без
    ключа в тексте берёт ключ события `rekey` через ту же `canon`; ключ из текста событие
    не перекрывает."""
    if r.get('src') == 'wave-errors':
        k = r.get('key')
    else:
        k = key_of(r.get('raw', ''), aliases)
        if k is None and rekeys:
            k = canon(rekeys.get(r['id']), aliases)
        elif k is not None and rekeys and r['id'] in rekeys and general(k, aliases):
            k = canon(rekeys[r['id']], aliases)  # общий ключ текста разводится событием
        if k is not None and r.get('src') == 'dispatcher' and not (k == ORCH or k.startswith(ORCH + ':')):
            k = ORCH + ':' + k
    return k if k else '?' + r['id'][:8]


def analyse(store, now, aliases, since=0.0):
    # Случай — урок одного агента (id: сессия, агент, строка). Сводится лишь пара «итог
    # workflow ↔ строка lessons.md той же волны и полосы»; одна строка у РАЗНЫХ агентов — повтор.
    flat = lambda r: re.sub(r'\s+', ' ', r.get('raw', '')).strip()
    authored = {flat(r) for r in store.lessons if not r.get('relay')}
    by, seen = {}, set()
    for r in store.lessons:
        if (r.get('ts') or 0) < since or (r.get('relay') and flat(r) in authored):
            continue
        k = class_of(r, aliases, store.rekeys)
        if r.get('wave') and r.get('lane'):
            rh = (r['wave'], r['lane'], sha(flat(r)))
        else:
            rh = r['id']
        if rh in seen:
            continue
        seen.add(rh)
        by.setdefault(k, []).append(r)
    need, fails, stale, unkeyed, glue, fresh = [], [], [], [], [], 0
    for k, rs in sorted(by.items()):
        st, ref, _ = current(store, k)
        if st == 'rejected':
            continue
        if k.startswith('?'):
            unkeyed.append((k, rs))
            continue
        if st == 'open':
            fresh += len(rs)
        g = glued(k, rs, aliases)
        if g:
            glue.append((k, rs, g))  # склейка — не повтор: ни механизма, ни «не держит»
            continue
        if len(rs) >= THRESHOLD and st in ('open', 'edited'):
            need.append((k, rs, st))
        hs = held_since(store, k)
        if st in HELD and hs is not None:
            late = [r for r in rs if (r.get('ts') or 0) > hs]
            if late:
                fails.append((k, late, ref))
        if st == 'open' and min((r.get('ts') or now) for r in rs) < now - DAY:
            stale.append((k, rs))
    return by, need, fails, stale, unkeyed, glue, fresh


def line_of(need, fails, stale, unkeyed, glue, fresh):
    s = '📚 УРОКИ: новых %d · классов с повтором без задачи %d · старше суток %d' % (fresh, len(need), len(stale))
    if fails:
        s += ' · механизм не держит %d' % len(fails)
    if unkeyed:
        s += ' · без ключа %d' % len(unkeyed)
    if glue:
        s += ' · ключ слишком общий %d' % len(glue)
    return s


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    a = sys.argv[1:]
    if not a:
        die('нет команды: scan | status | signal | mark <ключ> <статус> <ссылка> | rekey ?<id> <ключ> | report', 1)
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
    now = float(opts['--now'] or os.environ.get('LESSONS_NOW') or time.time())
    if not opts['--dir']:
        die('каталог ведомости не задан (LESSONS_DIR)')
    store = Store(opts['--dir'])
    aliases = load_aliases(opts['--aliases'])

    if cmd == 'rekey':
        # Ключ уроку без ключа в тексте: событие ведомости, а не правка записи (ведомость только
        # дописывается). Ключ события — сырой нормализованный: синонимы — пересчётом в class_of.
        if len(rest) != 2 or not re.fullmatch(r'\?[0-9a-f]{4,40}', rest[0]):
            print('lessons: ОТКАЗ — rekey ?<id> <ключ>', file=sys.stderr)
            sys.exit(1)
        pre, key = rest[0][1:], norm(rest[1])
        why = ('несёт «·»' if '·' in rest[1] else 'начат «?»' if key.startswith('?')
               else 'пуст после нормализации' if canon(key, aliases) is None
               else 'из одного слова — слишком общий: склеит несвязанные уроки; нужен ключ из ≥ 2 слов либо итог синонима aliases.tsv'
               if general(canon(key, aliases), aliases) else '')
        if why:
            print('lessons: ОТКАЗ — ключ «%s» %s' % (rest[1], why), file=sys.stderr)
            sys.exit(1)
        hit = [r for r in store.lessons if r['id'].startswith(pre)]
        if len(hit) != 1:
            print('lessons: ОТКАЗ — уроков с id %s…: %d, нужен ровно один' % (pre, len(hit)), file=sys.stderr)
            sys.exit(1)
        r = hit[0]
        tk = key_of(r.get('raw', ''), aliases)
        if r.get('src') == 'wave-errors' or (tk is not None and not general(tk, aliases)):
            print('lessons: ОТКАЗ — у урока %s ключ из текста «%s»; rekey — только уроку без ключа в тексте либо с ключом из одного слова'
                  % (rest[0], class_of(r, aliases)), file=sys.stderr)
            sys.exit(1)
        store.rekey(r['id'], key, now)
        print('lessons: %s → %s' % (rest[0], class_of(r, aliases, store.rekeys)))
        return 0

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
            an = analyse(store, now, aliases, since)
            skip = sorted(x for x, _, _ in an[5] if current(store, x)[0] == 'open')
            keys = sorted(x for x in an[0] if current(store, x)[0] == 'open' and x not in skip)
            if skip:
                print('lessons: пропущено склеенных общим ключом %d: %s' % (len(skip), ', '.join(skip)))
        else:
            keys = [k]
            if k not in {class_of(r, aliases, store.rekeys) for r in store.lessons}:
                print('lessons: ОТКАЗ — класса «%s» в ведомости нет' % k, file=sys.stderr)
                sys.exit(1)
            rs = analyse(store, now, aliases)[0].get(k, [])  # случаи — тем же сведением, что status
            g = glued(k, rs, aliases)
            if g:
                print('lessons: ОТКАЗ — ключ «%s» из одного слова (не синоним aliases.tsv) склеил уроков %d с разными местами (мест %d): %s; развести — rekey ?<id> <ключ из ≥ 2 слов> расходящимся урокам, затем mark'
                      % (k, len(rs), len(g), glue_ids(g)), file=sys.stderr)
                sys.exit(1)
        for x in keys:
            store.mark(x, st, ref, now)
        print('lessons: %s → %s %s (классов %d)' % (k, st, ref, len(keys)))
        return 0

    census = {'files': 0, 'agents': 0, 'mains': 0, 'read': 0, 'deferred': 0, 'progress': False}
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
    by, need, fails, stale, unkeyed, glue, fresh = analyse(store, now, aliases, since)
    if cmd == 'report':
        gk = {k for k, _, _ in glue}
        rep = sum(1 for k, rs in by.items() if not k.startswith('?') and k not in gk and len(rs) >= THRESHOLD)
        held = [k for k in by if current(store, k)[0] in HELD]
        bad = [k for k, _, _ in fails]
        print('[CENSUS] lessons%s: уроков %d, классов %d, с повтором (≥%d) %d, без ключа %d, склеено общим ключом %d; механизмов влито %d, из них не держат %d (%s)'
              % (' с ' + opts['--since'] if since else '', sum(len(v) for v in by.values()), len([k for k in by if not k.startswith('?')]), THRESHOLD, rep, len(unkeyed), len(glue),
                 len(held), len(bad), ('доля %.0f %%' % (100.0 * len(bad) / len(held))) if held else 'доли нет'))
        for k, rs in sorted(by.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            st, ref, _ = current(store, k)
            print('%3d  %-10s %-14s %s' % (len(rs), st, ref, k))
        return 0
    if cmd not in ('status', 'signal'):
        die('неизвестная команда «%s»' % cmd, 1)
    if not store.lessons and cmd == 'status' and not os.path.isfile(store.ledger):
        die('ведомости нет: %s — сбор не вёлся' % store.ledger)
    head = line_of(need, fails, stale, unkeyed, glue, fresh)
    # rows — (ключ, строка): перечень класса берётся по КЛЮЧУ, а не разбором строки — ключ сам
    # может нести « — » (ws#1250 B1: 76 из 1446 ключей живой ведомости 2026-10-19, class_of).
    rows = [(k, 'NEED-MECHANISM %s — случаев %d (%s): %s' % (k, len(rs), st, rs[-1]['raw'][:140])) for k, rs, st in need]
    rows += [(k, 'MECHANISM-FAILS %s — повтор после %s: %d, последний: %s' % (k, ref, len(late), late[-1]['raw'][:140])) for k, late, ref in fails]
    rows += [(k, 'STALE %s — открыт дольше суток: %s' % (k, rs[0]['raw'][:140])) for k, rs in stale]
    rows += [(k, 'UNKEYED %s — урок без ключа в тексте (без места; ключ — rekey %s <ключ>): %s/%s: %s' % (k, k, rs[0]['sid'][:8], rs[0]['agent'], rs[0]['raw'][:140])) for k, rs in unkeyed]
    rows += [(k, 'GLUED %s — ключ из одного слова склеил уроков %d, мест %d (не синоним aliases.tsv); развести — rekey ?<id> <ключ из ≥ 2 слов>: %s' % (k, len(rs), len(g), glue_ids(g))) for k, rs, g in glue]
    body = [b for _, b in rows]
    todo = bool(need or fails or stale or unkeyed or glue)
    if cmd == 'status' and rest:
        # `status <ключ>` судит ОДИН класс (ws#1250): код 0 — закрыт исходом (не open и ни в одном
        # перечне), 1 — ещё есть что делать, 2 — класса в ведомости нет. Чужой остаток не красит.
        # Ключ ОДИН: второй — отказ формы кодом 64, а не 1 «есть что делать» (сводного кода по
        # нескольким классам нет — 0 и 2 рядом не сводятся без потери смысла).
        if len(rest) != 1:
            print('lessons: ОТКАЗ — status [<ключ>]: ключ один, второй ключ «%s» не судится; по классу — отдельный вызов' % rest[1], file=sys.stderr)
            sys.exit(64)
        keys = {class_of(r, aliases, store.rekeys) for r in store.lessons}
        k = rest[0] if rest[0] in keys else canon(rest[0], aliases)
        if k not in keys:
            print('lessons: класса «%s» в ведомости нет — судить нечего' % rest[0])
            return 2
        st, ref, _ = current(store, k)
        why = [b for k2, b in rows if k2 == k]
        if st == 'open' and not why:
            why = ['OPEN %s — исхода нет (mark <ключ> <статус> <ссылка>)' % k]
        print('lessons: класс «%s» — %s%s; случаев %d' % (k, st, ' ' + ref if ref else '', len(by.get(k) or [])))
        if why:
            print('\n'.join(why))
            return 1
        print('lessons: закрыт исходом')
        return 0
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
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException as e:  # сбой — кодом 3, а не кодом 1 «есть что делать» без строки
        die('сбой сборщика: %s: %s' % (type(e).__name__, str(e)[:200]), 3)
