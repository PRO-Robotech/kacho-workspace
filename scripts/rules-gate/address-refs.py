#!/usr/bin/env python3
# Адреса норм: находит ссылки и проверяет, что цель существует.
#   <файл>.md#<id>          — новая форма: id стоит первым полем строки-нормы
#   <файл>.md §«Заголовок»  — прежняя: цель — заголовок раздела
#   <файл>.md §N            — прежняя: цель — заголовок, начинающийся с «N.»
# Области: .claude/agents/**, .claude/rules/**, CLAUDE.md, project/kacho/internal/repohygiene/**.
# Ссылки внутри ``` ограждений игнорируются: там примеры, а не адреса.
import argparse
import glob
import os
import re
import sys

RULES = '.claude/rules'
# Архив — РЕАЛЬНОЕ место, и ссылка в него верна: норма там лежит, а не исчезла.
# Резолвить только корпус значило бы требовать снятия всякой исторической ссылки
# вместе с её предметом — а предмет цел, он переехал (решение владельца 2026-09-20).
ARCHIVE = '.claude/backup'
REF_NAMED = re.compile(r'([a-z0-9][a-z0-9._-]*\.md)`?\s*§\s*«([^»]{1,120})»', re.S)
REF_NUM = re.compile(r'([a-z0-9][a-z0-9._-]*\.md)`?\s*§\s*(\d+[а-яa-z]?)')
REF_ID = re.compile(r'([a-z0-9][a-z0-9._-]*\.md)#([a-z0-9][a-z0-9-]{1,60})')
NORM_ROW = re.compile(r'^([a-z0-9][a-z0-9-]{1,60}) · ')


def strip_fences(text):
    out, fence = [], False
    for line in text.split('\n'):
        if line.lstrip().startswith('```'):
            fence = not fence
            out.append('')
            continue
        out.append('' if fence else line)
    return '\n'.join(out)


def corpus():
    # Цель ссылки в этом корпусе — заголовок ЛИБО выделенное утверждение тела:
    # `**Подписки на операции не существует, …**` адресуется как §«…» наравне с
    # заголовком. Судить только заголовки значило бы обвинять корпус в его же
    # соглашении — замер: так выглядели 11 из 50 «висячих».
    heads, ids = {}, {}
    for f in sorted(glob.glob(RULES + '/*.md')) + sorted(glob.glob(ARCHIVE + '/*.md')):
        b = os.path.basename(f)
        if b in heads:
            continue          # корпус прочитан первым и старше архива
        heads[b], ids[b] = [], []
        for line in open(f, encoding='utf-8'):
            if line.startswith('#'):
                # Заголовки корпуса САМИ несут «§»: `## §1. Вердикт…`. Снимаем его,
                # иначе ссылка `§1` не сойдётся с заголовком `§1. …` — замер: 19 из 50.
                heads[b].append(line.lstrip('#').strip().lstrip('§').strip())

            m = NORM_ROW.match(line)
            if m:
                ids[b].append(m.group(1))
    # ПОЛНЫЙ ТЕКСТ ЦЕЛИ — тоже основание. Ссылка в этом корпусе адресует и
    # выделенное утверждение тела (`**Подписки на операции не существует, …**`),
    # которое законно переносится через строку и потому построчно не ловится.
    # Предмет гейта — «существует ли названный текст в названном файле», а не
    # «заголовок это или нет».
    body = {}
    for f in sorted(glob.glob(RULES + '/*.md')) + sorted(glob.glob(ARCHIVE + '/*.md')):
        b = os.path.basename(f)
        if b in body:
            continue
        raw_b = open(f, encoding='utf-8').read()
        # САМИ ССЫЛКИ ИЗ ТЕКСТА УБИРАЮТСЯ. Иначе ссылка резолвится о саму себя:
        # строка «x.md §«такого раздела нет»» становится частью текста x.md, и гейт
        # находит там цель, которой не существует. Инъекция это и поймала (ось A).
        raw_b = REF_NAMED.sub(' ', raw_b)
        raw_b = REF_ID.sub(' ', raw_b)
        body[b] = nws(raw_b)
    return heads, ids, body


def sources():
    pats = ['.claude/agents/*.md', RULES + '/*.md', 'CLAUDE.md',
            'project/kacho/internal/repohygiene/*.go',
            'project/kacho/internal/repohygiene/**/*.go']
    seen = []
    for p in pats:
        seen += [x for x in glob.glob(p, recursive=True) if os.path.isfile(x)]
    return sorted(set(seen))


def nws(s):
    # Ссылка законно переносится через строку, и в Go-комментарии внутрь попадает
    # продолжение `// ` (а в markdown-цитате — `> `). Без снятия этих маркеров
    # цель выходит вида «Гейт\n// на класс», и гейт обвинял бы дерево в том, что
    # сам не умеет читать перенос. Замер: так выглядели 17 из 65 «висячих».
    s = re.sub(r'\n\s*(?://+|#+|\*|>)\s*', ' ', s)
    # Кавычки корпуса разнотипны: «», „", "", ''. Ссылка и заголовок законно
    # расходятся формой кавычки при одном и том же тексте — замер: 1 из 50.
    s = re.sub(r'[«»„“”"\u201a\u2018\u2019\']', '"', s)
    # Пунктуация внутри заголовка косметична: заголовок «Production-mode —
    # ОБЯЗАТЕЛЕН ВЕЗДЕ» и ссылка §«Production-mode обязателен ВЕЗДЕ» называют один
    # предмет, и тире между ними — не расхождение. Снимаем тире, запятые, двоеточия.
    s = re.sub(r'[\u2014\u2013,:;]', ' ', s)
    return re.sub(r'\s+', ' ', s).strip().lower()


def check():
    heads, ids, body = corpus()
    rows, dangling = [], 0
    for src in sources():
        raw = open(src, encoding='utf-8', errors='replace').read()
        text = strip_fences(raw)
        for rx, kind in ((REF_ID, 'id'), (REF_NAMED, 'named'), (REF_NUM, 'num')):
            for m in rx.finditer(text):
                f, tgt = m.group(1), m.group(2)
                # ПРЕДМЕТ ГЕЙТА — адреса В КОРПУС И АРХИВ, и только они. Ссылка на
                # `docs/specs/04-roadmap-and-phasing.md §2` — верный адрес чужого
                # документа; судить её этим гейтом значило бы обвинять дерево в том,
                # что оно не корпус. Такие ссылки держит `skills-gate/check-01`.
                if f not in heads:
                    continue
                line = raw[:m.start()].count('\n') + 1
                ok = False
                if True:
                    if kind == 'id':
                        ok = tgt in ids[f]
                    elif kind == 'named':
                        # Ссылка сама несёт «§» внутри кавычек: §«§1. Вердикт…».
                        # Сверка обязана быть симметричной снятию § у заголовка.
                        q = nws(tgt).lstrip('§').strip()
                        # Ссылка законно СОКРАЩАЕТ свой хвост многоточием:
                        # §«Контроль, действующий на ВЫДАЧЕ…». Требовать полного
                        # совпадения значило бы запретить это соглашение.
                        q = re.sub(r'\s*(?:\.\.\.|…)\s*$', '', q)
                        ok = (any(q in nws(h) for h in heads[f])
                              or (len(q) >= 12 and q in body.get(f, '')))
                    else:
                        ok = any(re.match(r'^' + re.escape(tgt) + r'[.\s]', h) for h in heads[f])
                tgt = re.sub(r'\s+', ' ', re.sub(r'\n\s*(?://+|#+|\*|>)\s*', ' ', tgt)).strip()
                rows.append((src, line, f, kind, tgt, ok))
                if not ok:
                    dangling += 1
    dup = []
    for f, lst in ids.items():
        seen = set()
        for i in lst:
            if i in seen:
                dup.append(f + '#' + i)
            seen.add(i)
    allids = [i for l in ids.values() for i in l]
    cross = [i for i in set(allids) if allids.count(i) > 1]
    return rows, dangling, dup, cross


def baseline(p='scripts/rules-gate/address-baseline.txt'):
    if not os.path.exists(p):
        return set()
    return {l.strip() for l in open(p, encoding='utf-8')
            if l.strip() and not l.startswith('#')}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--baseline', default='scripts/rules-gate/address-baseline.txt')
    a = ap.parse_args()
    rows, dangling, dup, cross = check()
    known = baseline(a.baseline)
    fresh = sorted({(f + '#' + t) if k == 'id' else (f + ' \u00a7' + t)
                    for _, _, f, k, t, ok in rows if not ok} - known)
    resolved_now = sorted(known & {(f + '#' + t) if k == 'id' else (f + ' \u00a7' + t)
                                   for _, _, f, k, t, ok in rows if ok})
    if a.list:
        for src, line, f, kind, tgt, ok in rows:
            addr = f + '#' + tgt if kind == 'id' else f + ' §' + tgt
            print('%s:%d\t%s\t%s' % (src, line, addr, 'OK' if ok else 'ВИСИТ'))
    print('осмотрено источников: %d; адресов: %d; ВИСИТ: %d (из них в объявленной базе %d)'
          % (len(sources()), len(rows), dangling, dangling - len(fresh)))
    print('неуникальных id внутри файла: %d; id в двух файлах: %d' % (len(dup), len(cross)))
    for x in fresh[:20]:
        print('  КРАСНОЕ новая поломка адреса:', x)
    for x in resolved_now[:20]:
        print('  КРАСНОЕ адрес из базы зажил — убрать его из address-baseline.txt:', x)
    for x in dup[:20]:
        print('  дубль id:', x)
    for x in cross[:20]:
        print('  id в двух файлах:', x)
    if not rows:
        print('КРАСНОЕ — адресов не найдено ни одного, обход пуст, вердикт беспредметен')
        return 1
    return 1 if (fresh or resolved_now or dup or cross) else 0


if __name__ == '__main__':
    sys.exit(main())
