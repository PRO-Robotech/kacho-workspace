#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Предмет: СТАРТОВОЕ ОКНО каждого агента не выше своего потолка (ws#1084).

ЧТО МЕРЯЕТСЯ. Решение владельца 2026-10-14: «сами рулы ограничивать в
размересовакупном нету смысла вопрос какие скилы будут существовать и какими
рулами будут обладать». Токенами платится не корпус, а то, что агент получает
при запуске: `CLAUDE.md` (кроме агента с `omitClaudeMd: true`), файл агента и
каждый скилл из его `skills:` целиком (харнесс грузит их при старте). Это и есть
СТАРТ, и он судится потолком ЭТОГО агента из ведомости `agent-window-budget.tsv`.
Потолки `CLAUDE.md` и тела `dispatcher.md`, прежде стоявшие в check-02, сняты
оттуда (решение диспетчера по ws#1084, вариант 2): `CLAUDE.md` входит в старт
каждого агента, `dispatcher.md` — в старт диспетчера, и их рост краснеет здесь.

ПОДГРУЗКА ПО ТРИГГЕРУ (`Skill <имя>` в теле, имени нет в `skills:`) считается
ОТДЕЛЬНО, печатается и НЕ ограничивается: она приезжает лишь при условии, и её
цена — свойство задачи, а не агента.

FRONTMATTER РАЗБИРАЕТСЯ YAML-ПАРСЕРОМ (`yaml.safe_load`), а не образцом строки:
законных форм `skills:` три — блочная с отступом, блочная в колонке 0 и поточная
`[a, b]`, — и распознаватель, знающий не все, давал «skills: 0» при четырёх
скиллах (возврат check-verifier). Нет PyYAML — отказ (код 2), а не догадка.
Находки разбора: frontmatter не YAML · `skills:` не список и не строка · ключ
`skills:` непуст, а имён разобрано 0.

ВНЕ СЧЁТА, и это граница прокси: системный промпт харнесса, описания инструментов
и чужих агентов, личная память пользователя (`MEMORY.md` лежит вне дерева, CI её
не видит). Единица — символ в NFC.

ТОКЕНЫ — ОЦЕНКА, ВЕРДИКТ — ПО СИМВОЛАМ. Коэффициент `CHARS_PER_TOKEN` = 2,1
символа на токен: замер разведчика 2026-10-14 (`tok.py`, 317 пар «символы
промпта → usage» журналов сессии 3f44acf5), разброс 2,09–2,16. Прежняя оценка
3,3 занижала токены в 1,57 раза.

ВЕДОМОСТЬ — ХРАПОВИК. Строка: `<агент>\\t<потолок, символов>\\t<основание>`.
Основание обязано нести замер: `старт <N> @<ревизия>`. Потолок — не выше
N × 1,10 (запас не больше 10 %, владелец 2026-10-14), и N сверяется с ЗАМЕРОМ
старта на ревизии основания тем же счётом по истории git (репозиторий самого
гейта, шов `RULES_GATE_WINDOW_HISTORY`). Рост потолка — только новым основанием
(свежая ревизия и её замер). Находки: старт выше потолка · агент без строки ·
строка без агента · строка без числа или без основания · основание без замера ·
ревизии основания нет в истории · N не равен замеру на ревизии («основание
ложно») · потолок выше N × 1,10 («основание устарело») · скилл из `skills:`,
которого нет в дереве (харнесс пропустил бы его молча). Запас больше 10 % от
ТЕКУЩЕГО старта печатается напоминанием опустить число, но не краснеет: сжатие
правила, общего для тридцати агентов, не обязано красить их всех.

ОТКАЗ (код 2): нет PyYAML, `CLAUDE.md`, каталога агентов, ведомости, истории
git для сверки оснований, либо в ведомости ни одной строки — судить нечего.
"""
import glob
import os
import posixpath
import re
import subprocess
import sys
import unicodedata

FORM = 'NFC'
CHARS_PER_TOKEN = 2.1     # основание — в шапке (замер разведчика, 317 пар usage)
RATCHET_NUM, RATCHET_DEN = 11, 10      # потолок ≤ старт × 1,10, целочисленно вниз
LEDGER_DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              'agent-window-budget.tsv')
SKILL_RE = re.compile(r'\bSkill\s+`?([A-Za-z0-9][A-Za-z0-9:_-]*)')
BASIS_RE = re.compile(r'старт\s+(\d+)\s+@([0-9a-f]{7,40})\b')
KEY_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_-]*\s*:')


def nfc(text):
    return unicodedata.normalize(FORM, text)


def read(path):
    with open(path, encoding='utf-8') as fh:
        return nfc(fh.read())


def workspace_root(argv):
    if len(argv) > 1 and argv[1]:
        return os.path.abspath(argv[1])
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
    from gate_root import gate_root  # noqa: E402
    return gate_root('RULES_GATE_ROOT', __file__)


class FsTree:
    """Дерево на диске: корень гейта."""

    def __init__(self, root):
        self.root = root

    def agents(self):
        return sorted(os.path.splitext(os.path.basename(p))[0]
                      for p in glob.glob(os.path.join(self.root, '.claude/agents/*.md')))

    def text(self, rel):
        p = os.path.join(self.root, rel)
        return read(p) if os.path.isfile(p) else None


class GitTree:
    """То же дерево на ревизии `rev` из истории git: символьные ссылки
    разрешаются так же, как их разрешил бы диск (скилл `rule-*` — ссылка)."""

    def __init__(self, repo, rev):
        self.repo, self.rev, self.blobs = repo, rev, {}
        out = subprocess.run(['git', '-C', repo, 'ls-tree', '-r', '-z', rev, '--',
                              'CLAUDE.md', '.claude/agents', '.claude/skills', '.claude/rules'],
                             capture_output=True)
        if out.returncode != 0:
            raise LookupError(out.stderr.decode('utf-8', 'replace').strip()[:200])
        for rec in out.stdout.split(b'\0'):
            if not rec:
                continue
            meta, path = rec.split(b'\t', 1)
            mode, _typ, sha = meta.split()
            self.blobs[path.decode('utf-8')] = (mode.decode(), sha.decode())
        self.cache = {}

    def _blob(self, sha):
        out = subprocess.run(['git', '-C', self.repo, 'cat-file', 'blob', sha],
                             capture_output=True, check=True)
        return out.stdout.decode('utf-8')

    def agents(self):
        return sorted(posixpath.splitext(posixpath.basename(p))[0] for p in self.blobs
                      if posixpath.dirname(p) == '.claude/agents' and p.endswith('.md'))

    def text(self, rel, hops=0):
        if rel in self.cache:
            return self.cache[rel]
        ent = self.blobs.get(rel)
        if ent is None or hops > 8:
            return None
        mode, sha = ent
        data = self._blob(sha)
        if mode == '120000':
            target = posixpath.normpath(posixpath.join(posixpath.dirname(rel), data.strip()))
            val = self.text(target, hops + 1)
        else:
            val = nfc(data)
        self.cache[rel] = val
        return val


def frontmatter(text):
    """(текст frontmatter, тело) — frontmatter между первыми двумя `---`."""
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        return None, text
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            return '\n'.join(lines[1:i]), '\n'.join(lines[i + 1:])
    return None, text


def skills_raw(fm):
    """Написанное под ключом `skills:` — его строка и продолжение до следующего
    ключа колонки 0; пусто, если ключа нет либо значение пустое."""
    lines, out, inside = fm.split('\n'), [], False
    for line in lines:
        if re.match(r'^skills\s*:', line):
            inside = True
            out.append(line.split(':', 1)[1])
            continue
        if inside:
            if KEY_RE.match(line):
                break
            out.append(line)
    return '\n'.join(out).strip()


def requote(fm):
    """Однострочные скалярные значения ключей колонки 0 — в двойные кавычки."""
    out = []
    for line in fm.split('\n'):
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s+(\S.*)$', line)
        if m and m.group(2)[0] not in '[{"\'|>&*!':
            v = m.group(2).replace('\\', '\\\\').replace('"', '\\"')
            line = '%s: "%s"' % (m.group(1), v)
        out.append(line)
    return '\n'.join(out)


def parse_agent(yaml, text):
    """(skills, omitClaudeMd, тело, ошибка разбора|None)."""
    fm, body = frontmatter(text)
    if fm is None:
        return [], False, body, None
    try:
        meta = yaml.safe_load(fm)
    except yaml.YAMLError as exc:
        # Харнесс, не разобрав frontmatter, закавычивает однострочные значения
        # ключей колонки 0 и разбирает снова (так грузится `dispatcher.md`, чей
        # `description:` несёт «: »). Повтор тот же; списки и `[…]` не трогаются.
        try:
            meta = yaml.safe_load(requote(fm))
        except yaml.YAMLError:
            return [], False, body, 'frontmatter не YAML: %s' % str(exc).split('\n')[0]
    if meta is None:
        meta = {}
    if not isinstance(meta, dict):
        return [], False, body, 'frontmatter не словарь, а %s' % type(meta).__name__
    val = meta.get('skills')
    if val is None:
        skills = []
    elif isinstance(val, str):
        skills = [x.strip() for x in val.split(',') if x.strip()]
    elif isinstance(val, list) and all(isinstance(x, str) for x in val):
        skills = [x.strip() for x in val if x.strip()]
    else:
        return [], False, body, 'skills: не список имён и не строка, а %r' % (val,)
    err = None
    raw = skills_raw(fm)
    if not skills and raw:
        err = 'ключ skills: непуст («%s»), а имён разобрано 0' % raw.replace('\n', '⏎')[:60]
    return skills, meta.get('omitClaudeMd') in (True, 'true'), body, err


def start_of(yaml, tree, name, base):
    """(старт, предзагружено, по триггеру [(имя, символов)], пропавшие, ошибка)."""
    text = tree.text('.claude/agents/%s.md' % name)
    pre, omit, body, err = parse_agent(yaml, text)
    start = len(text) + (0 if omit else base)
    missing = []
    for s in pre:
        t = tree.text('.claude/skills/%s/SKILL.md' % s)
        if t is None:
            missing.append(s)
        else:
            start += len(t)
    trig = []
    for s in sorted(set(SKILL_RE.findall(body)) - set(pre)):
        t = tree.text('.claude/skills/%s/SKILL.md' % s)
        if t is not None:
            trig.append((s, len(t)))
    return start, pre, trig, missing, err


def load_ledger(path):
    """{агент: (потолок|None, основание, номер строки)} и список отказов формы."""
    rows, bad = {}, []
    for n, line in enumerate(read(path).split('\n'), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        cells = line.split('\t')
        name = cells[0].strip()
        num = cells[1].strip() if len(cells) > 1 else ''
        why = cells[2].strip() if len(cells) > 2 else ''
        if not re.fullmatch(r'[0-9]+', num) or not why:
            bad.append('%s:%d: «%s» — нужно «агент<TAB>потолок<TAB>основание»' % (
                os.path.basename(path), n, line[:80]))
            rows[name] = (None, why, n)
            continue
        rows[name] = (int(num), why, n)
    return rows, bad


def history_repo():
    """Репозиторий истории для сверки оснований: шов либо репозиторий гейта."""
    seam = os.environ.get('RULES_GATE_WINDOW_HISTORY')
    here = seam or os.path.dirname(os.path.abspath(__file__))
    out = subprocess.run(['git', '-C', here, 'rev-parse', '--show-toplevel'],
                         capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def main():
    root = workspace_root(sys.argv)
    try:
        import yaml  # noqa: E402
    except ImportError:
        print('[VOID] ОТКАЗ — нет PyYAML: frontmatter агентов разбирается только им, '
              'разбор образцом строки слеп к законным формам skills:')
        return 2
    ledger_path = os.environ.get('RULES_GATE_WINDOW_BUDGET') or LEDGER_DEFAULT
    tree = FsTree(root)
    claude = tree.text('CLAUDE.md')
    agents = tree.agents()
    if claude is None:
        print('[VOID] ОТКАЗ — в корне %s нет CLAUDE.md: старт без него не посчитать' % root)
        return 2
    if not agents:
        print('[VOID] ОТКАЗ — в %s/.claude/agents нет ни одного агента: судить нечего' % root)
        return 2
    if not os.path.isfile(ledger_path):
        print('[VOID] ОТКАЗ — ведомости потолков %s нет: сверять не с чем' % ledger_path)
        return 2
    ledger, bad = load_ledger(ledger_path)
    if not ledger:
        print('[VOID] ОТКАЗ — в ведомости %s ни одной строки' % ledger_path)
        return 2
    repo = history_repo()
    if repo is None:
        print('[VOID] ОТКАЗ — истории git для сверки оснований нет '
              '(репозиторий гейта либо RULES_GATE_WINDOW_HISTORY)')
        return 2

    base = len(claude)
    report = [(name,) + start_of(yaml, tree, name, base) for name in agents]

    # Сверка оснований: замер старта на ревизии основания тем же счётом.
    revs, basis = {}, {}
    for name, (cap, why, n) in ledger.items():
        m = BASIS_RE.search(why)
        if cap is None or not m:
            basis[name] = ('нет', None, None)
            continue
        claimed, rev = int(m.group(1)), m.group(2)
        if rev not in revs:
            try:
                gt = GitTree(repo, rev)
                revs[rev] = (gt, len(gt.text('CLAUDE.md') or ''), set(gt.agents()))
            except LookupError:
                revs[rev] = None
        if revs[rev] is None:
            basis[name] = ('ревизии', claimed, rev)
            continue
        gt, gbase, gagents = revs[rev]
        if name not in gagents:
            basis[name] = ('агента', claimed, rev)
            continue
        measured = start_of(yaml, gt, name, gbase)[0]
        basis[name] = ('ok', claimed, rev, measured)

    print('корень %s; агентов осмотрено: %d; строк ведомости: %d; CLAUDE.md: %d символов; '
          'единица — символ NFC, токены ≈ символы / %.1f; разбор frontmatter — yaml.safe_load; '
          'история оснований — %s, ревизий %d'
          % (root, len(agents), len(ledger), base, CHARS_PER_TOKEN, repo, len(revs)))
    starts = sorted(r[1] for r in report)
    top = max(report, key=lambda r: r[1])
    print('старт: максимум %d (%s, ≈%d ток.), медиана %d (≈%d ток.)'
          % (top[1], top[0], top[1] / CHARS_PER_TOKEN, starts[len(starts) // 2],
             starts[len(starts) // 2] / CHARS_PER_TOKEN))
    rc = 0
    for name, start, pre, trig, missing, err in report:
        cap = ledger.get(name, (None, '', 0))[0]
        tsum = sum(n for _, n in trig)
        print('  %-24s старт %7d / потолок %7s · skills: %d · по триггеру +%d (%d, не ограничено)'
              % (name, start, cap if cap is not None else '—', len(pre), tsum, len(trig)))
        if err:
            rc = 1
            print('КРАСНОЕ разбор — %s: %s; старт посчитан без скиллов и неверен' % (name, err))
        if missing:
            rc = 1
            print('КРАСНОЕ скилл — %s: в skills: %s, в .claude/skills их нет' % (name, ', '.join(missing)))
        if name not in ledger:
            rc = 1
            print('КРАСНОЕ ведомость — у агента %s нет потолка: строка «%s\\t%d\\t<основание>»'
                  % (name, name, start))
            continue
        if cap is None:
            continue
        if start > cap:
            rc = 1
            print('КРАСНОЕ окно — %s: старт %d, потолок %d, перевес %d (≈%d ток.)'
                  % (name, start, cap, start - cap, (start - cap) / CHARS_PER_TOKEN))
        b = basis[name]
        if b[0] == 'нет':
            rc = 1
            print('КРАСНОЕ основание — %s: в основании нет замера «старт <N> @<ревизия>»' % name)
        elif b[0] == 'ревизии':
            rc = 1
            print('КРАСНОЕ основание — %s: ревизии %s нет в истории %s' % (name, b[2], repo))
        elif b[0] == 'агента':
            rc = 1
            print('КРАСНОЕ основание — %s: на ревизии %s такого агента нет' % (name, b[2]))
        else:
            _, claimed, rev, measured = b
            if claimed != measured:
                rc = 1
                print('КРАСНОЕ основание ложно — %s: в основании старт %d @%s, замер на ней %d'
                      % (name, claimed, rev, measured))
            lim = measured * RATCHET_NUM // RATCHET_DEN
            if cap > lim:
                rc = 1
                print('КРАСНОЕ основание устарело — %s: потолок %d выше замера %d @%s × 1,10 = %d; '
                      'рост — только новым основанием (свежая ревизия и её замер)'
                      % (name, cap, measured, rev, lim))
        if start and cap > start * RATCHET_NUM // RATCHET_DEN:
            print('  храповик: у %s запас %.0f%% больше 10%% — опустить потолок до %d'
                  % (name, 100.0 * (cap - start) / start, start * RATCHET_NUM // RATCHET_DEN))
    for line in bad:
        rc = 1
        print('КРАСНОЕ форма ведомости — %s' % line)
    for name in sorted(set(ledger) - set(agents)):
        rc = 1
        print('КРАСНОЕ ведомость — строка %d о «%s»: такого агента нет, запись пережила предмет'
              % (ledger[name][2], name))
    return rc


if __name__ == '__main__':
    sys.exit(main())
