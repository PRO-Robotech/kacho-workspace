# Сжатие корпуса `.claude/rules` до 200 000 символов — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** свести `.claude/rules` с 618 189 до 183 539 символов (÷3,37), оставив все 1 118 норм классов A/B/C в строковой форме, перенеся 318 записей класса D в архив, и закрыв результат двумя новыми осями `scripts/rules-gate/`.

**Architecture:** раскладка файлов НЕ меняется — 30 имён, ноль правок symlink, frontmatter агентов, `MANIFEST.md` и 1 000 координат. Выигрыш берётся содержимым: каждая норма становится одной строкой `<id> · <императив> · <держатель> · red: <признак>`. Порядок обязателен: сначала доказать, что корпус вообще доходит до исполнителя, потом завести гейт на разрешимость адресов, и только потом переносить текст.

**Tech Stack:** bash + python3 (замеры и гейты), Go-тесты `internal/repohygiene` в `PRO-Robotech/kacho` (только правка 4 координат в комментариях), markdown.

**Spec:** `docs/superpowers/specs/2026-09-19-rules-corpus-compression-design.md`

## Global Constraints

- Потолок корпуса: **200 000 символов** на сумму всех `.claude/rules/*.md`. Символы, не байты: `len(open(f,encoding='utf-8').read())`, не `wc -c` — кириллица в UTF-8 вдвое тяжелее.
- Смета: нормы 165 426 + 190 адресуемых заголовков 11 813 + frontmatter 3 600 + якоря 2 700 = **183 539**, запас 16 461 (8,2 %).
- Форма записи: `<id> · <императив> · <держатель> · red: <признак нарушения>`. Разделитель — ровно ` · ` (пробел, U+00B7, пробел). Без markdown-таблицы: палки стоят 40 % строки (244 симв против 148).
- Слово «держится» в корпусе не пишется **никогда**. Держатель — имя Go-теста, скрипта или команды; если гейта нет — `ЗАВЕСТИ <имя>`.
- Ни одна норма не удаляется безвозвратно. Класс D уезжает в `.claude/backup/<файл>.md`.
- Не трогается: `.claude/agents/**`, `MANIFEST.md` (кроме собственного содержимого как файла правил), `.claude/settings.json`, symlink `.claude/skills/rule-*`. Единственное исключение вне `.claude/rules/` — 4 координаты в `internal/repohygiene` и два новых файла в `scripts/rules-gate/`.
- 190 адресуемых заголовков разделов сохраняются дословно: на них стоят 424 ссылки из агентов. 177 неадресуемых схлопываются.
- 46 гейтов на 239 норм класса A без механизма — **не в этом плане**, отдельная линия.
- Опись 1 436 норм с готовыми строками лежит в `tmp/rules-compression/inventory-2026-09-19.json` (поля: `id`, `src`, `k`, `min`, `form`, `hold`, `gate`, `v`).
- Работа в воркспейсе `PRO-Robotech/kacho-workspace`, ветка `issue-<N>` от свежей `main`. Коммит после каждой задачи.

---

### Task 1: Снять признак доставки корпуса и положить опись

Предусловие всей работы: `claudeMdExcludes` снял автозагрузку, а ни один из 30 скилов `rule-*` не несёт YAML-frontmatter. Если харнесс регистрирует скил только по frontmatter, корпус не читается никем, и сжимать нечего.

**Files:**
- Create: `tmp/rules-compression/delivery-probe.md` (протокол и результат пробы)
- Create: `tmp/rules-compression/inventory-2026-09-19.json` (опись, вход для всех задач переписывания)

**Interfaces:**
- Produces: `tmp/rules-compression/inventory-2026-09-19.json` — опись 1 436 норм, вход задач 5 и 7–15
- Produces: `tmp/rules-compression/frontmatter-before.txt` — перепись файлов правил без frontmatter (ожидается 30)
- Produces: `tmp/rules-compression/delivery-probe.md` — признак, дословное задание пробы и место под её исход; Task 2 от исхода НЕ зависит.

> **Ruling контроллера:** пробу «грузится ли корпус» из этой сессии провести нельзя — агенты и скилы
> проекта регистрируются в сессии, открытой В каталоге воркспейса, а обнаружение скилов происходит при
> её старте. Поэтому Task 1 фиксирует структурную улику и дословное задание пробы для владельца,
> а не её исход. Task 2 выполняется независимо: frontmatter обязателен для регистрации скила и
> безвреден, если регистрация и так есть.

- [ ] **Step 1: Записать признак до пробы**

```bash
cd "$(git rev-parse --show-toplevel)"
mkdir -p tmp/rules-compression
for f in .claude/skills/rule-*/SKILL.md; do
  [ "$(head -1 "$f")" = '---' ] || echo "без frontmatter: $f"
done | tee tmp/rules-compression/frontmatter-before.txt | wc -l
```

Ожидается: **30** строк. Ноль означал бы, что находка неверна, и Task 2 отменяется.

- [ ] **Step 2: Снять второй признак — чем отличаются скилы правил от прочих**

```bash
for f in .claude/skills/*/SKILL.md; do
  case "$f" in *rule-*) k=rule;; *) k=обычный;; esac
  printf '%-8s %-12s %s\n' "$k" "$([ -L "$f" ] && echo симлинк || echo файл)" "$(head -1 "$f")"
done | sort | uniq -c | sort -rn
```

Ожидается ровно два класса: 30 строк `rule / симлинк / # <заголовок>` и 14 строк
`обычный / файл / ---`. Если хоть один `rule-*` окажется с `---` — признак неверен,
и Task 2 надо пересмотреть.

- [ ] **Step 3: Записать признак и дословное задание пробы для владельца**

```bash
cat > tmp/rules-compression/delivery-probe.md <<'PROBE'
# Проба доставки корпуса — 2026-09-19

## Признак до пробы
Скилов `rule-*` без YAML-frontmatter: 30 из 30 (`tmp/rules-compression/frontmatter-before.txt`).
Автозагрузка каталога снята: `.claude/settings.json` → `claudeMdExcludes: ["**/.claude/rules/**"]`.

## Задание пробы
<вставить дословно текст задания из Step 2>

## Ответ агента `docs-writer`
<вставить дословно>

## Проба — действие владельца, не этой задачи
Провести в сессии, открытой В каталоге воркспейса (`claude` из корня kacho-workspace), запустив
агента `docs-writer` с дословным заданием:

```
Перечисли заголовки первого уровня всех файлов правил, которые лежат в твоём окне
прямо сейчас. Не читай ничего инструментом Read. Если правил в окне нет — ответь
«правил в окне нет».
```

## Исход пробы
ГРУЗИТСЯ | НЕ ГРУЗИТСЯ  ← вписать после прогона

## Следствие
- ГРУЗИТСЯ → Task 2 была уборкой: frontmatter дал скилу имя и описание.
- НЕ ГРУЗИТСЯ → Task 2 была починкой: с 2026-09-17 исполнители работали без корпуса.
  Записать находку с датой в `.claude/backup/README.md`.

Ни тот, ни другой исход не отменяет Task 2 и не меняет ни одной другой задачи плана.
PROBE
```

- [ ] **Step 4: Положить опись**

```bash
cp /tmp/claude-1000/-home-dk-workspace-github-PRO-Robotech-tmp/c721cc65-88bf-43b1-a380-f7f1a30ca97a/scratchpad/inventory-slim.json \
   tmp/rules-compression/inventory-2026-09-19.json
python3 -c "
import json
d=json.load(open('tmp/rules-compression/inventory-2026-09-19.json',encoding='utf-8'))
print('записей:',len(d))
assert len(d)==1436, len(d)
k={}
for n in d: k[n['k']]=k.get(n['k'],0)+1
print('по классам:',k)
assert k=={'A':565,'B':325,'C':228,'D':318}, k
print('OK')
"
```

Ожидается: `записей: 1436`, `по классам: {'A': 565, 'B': 325, 'C': 228, 'D': 318}`, `OK`.

- [ ] **Step 5: Коммит**

```bash
git add tmp/rules-compression/
git commit -m "probe(rules): доставка корпуса исполнителю — признак, проба, исход"
```

---

### Task 2: Frontmatter в 30 файлов правил

**Files:**
- Modify: все 30 `.claude/rules/*.md` — три строки в начало
- Create: `scripts/rules-gate/check-08-rule-frontmatter.sh`
- Create: `scripts/rules-gate/inject-08-rule-frontmatter.sh`
- Test: `scripts/rules-gate/run-all.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/delivery-probe.md` (Task 1)
- Produces: каждый `.claude/rules/<имя>.md` начинается с `---\nname: rule-<имя>\ndescription: <фраза>\n---`; `check-08` судит это в обе стороны.

- [ ] **Step 1: Написать падающий гейт**

Create `scripts/rules-gate/check-08-rule-frontmatter.sh`:

```bash
#!/usr/bin/env bash
# check-08 — КАЖДЫЙ ФАЙЛ ПРАВИЛ НЕСЁТ FRONTMATTER, И ИМЯ В НЁМ СХОДИТСЯ С ИМЕНЕМ ФАЙЛА.
# Вердикт стоит в КОДЕ ВЫХОДА. Предмет: скил `rule-<имя>` — симлинк на файл правила,
# и харнесс регистрирует скил по frontmatter цели. Файл без frontmatter = правило,
# которое не доходит до исполнителя: автозагрузка снята claudeMdExcludes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
rc=0
for f in .claude/rules/*.md; do
  base="$(basename "$f" .md)"
  if [ "$(head -1 "$f")" != '---' ]; then
    printf 'КРАСНОЕ %s — нет frontmatter\n' "$f"; rc=1; continue
  fi
  want="name: rule-${base}"
  if ! sed -n '2,6p' "$f" | grep -qxF "$want"; then
    printf 'КРАСНОЕ %s — нет строки «%s» в frontmatter\n' "$f" "$want"; rc=1; continue
  fi
  if ! sed -n '2,6p' "$f" | grep -q '^description: .'; then
    printf 'КРАСНОЕ %s — description пуст или отсутствует\n' "$f"; rc=1
  fi
done
n=$(ls .claude/rules/*.md | wc -l)
printf 'осмотрено файлов правил: %s\n' "$n"
[ "$n" -ge 30 ] || { printf 'КРАСНОЕ — файлов правил меньше 30, обход усечён\n'; rc=1; }
exit "$rc"
```

- [ ] **Step 2: Прогнать и увидеть красное**

```bash
chmod +x scripts/rules-gate/check-08-rule-frontmatter.sh
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "код выхода: $?"
```

Ожидается: 30 строк `КРАСНОЕ … — нет frontmatter`, `осмотрено файлов правил: 30`, `код выхода: 1`.

- [ ] **Step 3: Написать инъекционное доказательство**

Create `scripts/rules-gate/inject-08-rule-frontmatter.sh`:

```bash
#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-08: гейт СПОСОБЕН дать красное на каждой из трёх осей.
# Ось A — frontmatter снят; ось B — имя не сходится с файлом; ось C — description пуст.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/check-08-rule-frontmatter.sh
T=.claude/rules/00-kacho-core.md
cp "$T" /tmp/check08.orig
trap 'cp /tmp/check08.orig "$T"' EXIT
fail=0
probe() { # $1 — имя оси, $2 — ожидаемая подстрока
  if "$G" 2>&1 | grep -q "$2"; then printf 'ось %s: гейт дал красное — OK\n' "$1"
  else printf 'ось %s: гейт МОЛЧИТ — доказательство не прошло\n' "$1"; fail=1; fi
}
sed -i '1,4d' "$T";                       probe A 'нет frontmatter'
cp /tmp/check08.orig "$T"
sed -i '2s/.*/name: rule-wrong/' "$T";    probe B 'нет строки'
cp /tmp/check08.orig "$T"
sed -i '3s/.*/description:/' "$T";        probe C 'description пуст'
cp /tmp/check08.orig "$T"
if "$G" >/dev/null 2>&1; then printf 'ось Z: на целом дереве зелено — OK\n'
else printf 'ось Z: на целом дереве КРАСНОЕ — гейт шумит\n'; fail=1; fi
exit "$fail"
```

- [ ] **Step 4: Внести frontmatter в 30 файлов и увидеть зелёное**

```bash
python3 - <<'PY'
import glob,os,re
# description берётся из первого заголовка H1 файла: он уже есть и уже точен
for f in sorted(glob.glob('.claude/rules/*.md')):
    base=os.path.basename(f)[:-3]
    t=open(f,encoding='utf-8').read()
    if t.startswith('---\n'): continue
    m=re.search(r'(?m)^#\s+(.+)$', t)
    desc=(m.group(1) if m else base).strip().replace('"','')
    if len(desc)>150: desc=desc[:147].rstrip()+'…'
    fm = '---\nname: rule-' + base + '\ndescription: "' + desc + '"\n---\n\n'
    open(f,'w',encoding='utf-8').write(fm + t)
    print(base + ': +' + str(len(fm)) + ' симв')
PY
chmod +x scripts/rules-gate/inject-08-rule-frontmatter.sh
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/inject-08-rule-frontmatter.sh; echo "inject-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 -c "import glob;print('корпус:',sum(len(open(f,encoding='utf-8').read()) for f in glob.glob('.claude/rules/*.md')))"
```

Ожидается: `check-08: 0`, `inject-08: 0` (четыре строки OK), `run-all: 0`, корпус ≈ 621 800 символов (618 189 + ~3 600).

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/ scripts/rules-gate/check-08-rule-frontmatter.sh scripts/rules-gate/inject-08-rule-frontmatter.sh
git commit -m "fix(rules): правило объявляет себя скилу frontmatter'ом — гейт в обе стороны"
```

---

### Task 3: check-07 — разрешимость адреса

Заводится ДО переноса текста: перенос рвёт ссылки молча, и 49 адресов не резолвятся уже сейчас.

**Files:**
- Create: `scripts/rules-gate/check-07-address-resolves.sh`
- Create: `scripts/rules-gate/inject-07-address-resolves.sh`
- Create: `scripts/rules-gate/address-refs.py` (разборщик: находит адреса и проверяет цель)

**Interfaces:**
- Produces: `scripts/rules-gate/address-refs.py --list` печатает `<источник>:<строка>\t<файл>#<id>|§«заголовок»\tOK|ВИСИТ`; `check-07` красный при любом `ВИСИТ` и при неуникальном id. Task 4 потребляет вывод `--list`.

- [ ] **Step 1: Написать разборщик и падающий гейт**

Create `scripts/rules-gate/address-refs.py`:

```python
#!/usr/bin/env python3
"""Адреса норм: находит ссылки и проверяет, что цель существует.

Две формы адреса:
  <файл>.md#<id>          — новая, id стоит первым полем строки-нормы
  <файл>.md §«Заголовок»  — прежняя, цель — заголовок раздела
  <файл>.md §N            — прежняя, цель — заголовок, начинающийся с «N.»

Области поиска: .claude/agents/**, .claude/rules/**, CLAUDE.md,
и (если каталог есть) ../kacho/internal/repohygiene/**.
Ссылки внутри ``` ограждений игнорируются: там примеры, а не адреса.
"""
import sys, re, glob, os, json, argparse

RULES_DIR = '.claude/rules'
REF_NAMED = re.compile(r'([a-z0-9][a-z0-9._-]*\.md)`?\s*§\s*«([^»]{1,120})»', re.S)
REF_NUM   = re.compile(r'([a-z0-9][a-z0-9._-]*\.md)`?\s*§\s*(\d+[а-яa-z]?)')
REF_ID    = re.compile(r'([a-z0-9][a-z0-9._-]*\.md)#([a-z0-9][a-z0-9-]{1,60})')
NORM_ROW  = re.compile(r'^([a-z0-9][a-z0-9-]{1,60}) · ')

def strip_fences(text):
    out, fence = [], False
    for line in text.split('\n'):
        if line.lstrip().startswith('```'):
            fence = not fence; out.append(''); continue
        out.append('' if fence else line)
    return '\n'.join(out)

def corpus():
    heads, ids = {}, {}
    for f in sorted(glob.glob(RULES_DIR + '/*.md')):
        b = os.path.basename(f)
        heads[b], ids[b] = [], []
        for line in open(f, encoding='utf-8'):
            if line.startswith('#'):
                heads[b].append(line.lstrip('#').strip())
            m = NORM_ROW.match(line)
            if m:
                ids[b].append(m.group(1))
    return heads, ids

def sources():
    pats = ['.claude/agents/*.md', RULES_DIR + '/*.md', 'CLAUDE.md',
            '../kacho/internal/repohygiene/*.go', '../kacho/internal/repohygiene/**/*.go']
    seen = []
    for p in pats:
        seen += [x for x in glob.glob(p, recursive=True) if os.path.isfile(x)]
    return sorted(set(seen))

def norm_ws(s):
    return re.sub(r'\s+', ' ', s).strip().lower()

def check():
    heads, ids = corpus()
    rows, dangling = [], 0
    for src in sources():
        raw = open(src, encoding='utf-8', errors='replace').read()
        text = strip_fences(raw)
        for rx, kind in ((REF_ID, 'id'), (REF_NAMED, 'named'), (REF_NUM, 'num')):
            for m in rx.finditer(text):
                f, tgt = m.group(1), m.group(2)
                line = raw[:m.start()].count('\n') + 1
                ok = False
                if f in heads:
                    if kind == 'id':
                        ok = tgt in ids[f]
                    elif kind == 'named':
                        ok = any(norm_ws(tgt) in norm_ws(h) for h in heads[f])
                    else:
                        ok = any(re.match(r'^' + re.escape(tgt) + r'[.\s]', h) for h in heads[f])
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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--list', action='store_true')
    a = ap.parse_args()
    rows, dangling, dup, cross = check()
    if a.list:
        for src, line, f, kind, tgt, ok in rows:
            print(f"{src}:{line}\t{f}#{tgt}" if kind == 'id' else f"{src}:{line}\t{f} §{tgt}",
                  end='\t')
            print('OK' if ok else 'ВИСИТ')
    print(f"осмотрено источников: {len(sources())}; адресов: {len(rows)}; ВИСИТ: {dangling}")
    print(f"неуникальных id внутри файла: {len(dup)}; id, встречающихся в двух файлах: {len(cross)}")
    for x in dup[:20]:
        print('  дубль id:', x)
    for x in cross[:20]:
        print('  id в двух файлах:', x)
    if not rows:
        print('КРАСНОЕ — адресов не найдено ни одного, обход пуст, вердикт беспредметен')
        return 1
    return 1 if (dangling or dup or cross) else 0

if __name__ == '__main__':
    sys.exit(main())
```

Create `scripts/rules-gate/check-07-address-resolves.sh`:

```bash
#!/usr/bin/env bash
# check-07 — АДРЕС НОРМЫ РЕЗОЛВИТСЯ, И id УНИКАЛЕН.
# Предмет: перенос текста между файлами рвёт ссылку молча. Область шире, чем у
# skills-gate/check-01: агенты, правила, CLAUDE.md и гейты продукта.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 scripts/rules-gate/address-refs.py
```

- [ ] **Step 2: Прогнать и увидеть красное на существующих висячих адресах**

```bash
chmod +x scripts/rules-gate/check-07-address-resolves.sh scripts/rules-gate/address-refs.py
scripts/rules-gate/check-07-address-resolves.sh; echo "код выхода: $?"
python3 scripts/rules-gate/address-refs.py --list | awk -F'\t' '$3=="ВИСИТ"' | head -20
```

Ожидается: `ВИСИТ` больше нуля (по замеру 2026-09-19 — порядка 49 до чистки разборщиком от переносов строк), `код выхода: 1`. Ноль означал бы, что разборщик не видит адресов — тогда сначала починить его, а не корпус.

- [ ] **Step 3: Написать инъекционное доказательство**

Create `scripts/rules-gate/inject-07-address-resolves.sh`:

```bash
#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-07 по четырём осям: висячий заголовок, висячий id,
# дубль id внутри файла, пустой обход.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/address-refs.py
T=.claude/rules/vault.md
cp "$T" /tmp/check07.orig
trap 'cp /tmp/check07.orig "$T"' EXIT
fail=0
probe() {
  if python3 "$G" 2>&1 | grep -q "$2"; then printf 'ось %s: красное — OK\n' "$1"
  else printf 'ось %s: МОЛЧИТ — доказательство не прошло\n' "$1"; fail=1; fi
}
printf '\nvault.md §«Раздела с таким именем нет нигде»\n' >> "$T"; probe A 'ВИСИТ: [1-9]'
cp /tmp/check07.orig "$T"
printf '\nvault.md#no-such-id-exists\n' >> "$T";                   probe B 'ВИСИТ: [1-9]'
cp /tmp/check07.orig "$T"
printf '\ndup-id-probe · императив · ЗАВЕСТИ x · red: признак\ndup-id-probe · императив · ЗАВЕСТИ x · red: признак\n' >> "$T"
probe C 'дубль id'
cp /tmp/check07.orig "$T"
printf 'ось Z: прогон на целом дереве — вердикт %s (ожидается 1, пока висячие адреса не починены Task 4)\n' "$(python3 "$G" >/dev/null 2>&1; echo $?)"
exit "$fail"
```

- [ ] **Step 4: Прогнать доказательство**

```bash
chmod +x scripts/rules-gate/inject-07-address-resolves.sh
scripts/rules-gate/inject-07-address-resolves.sh; echo "inject-07: $?"
```

Ожидается: три строки `ось A|B|C: красное — OK`, `inject-07: 0`.

- [ ] **Step 5: Коммит**

```bash
git add scripts/rules-gate/address-refs.py scripts/rules-gate/check-07-address-resolves.sh scripts/rules-gate/inject-07-address-resolves.sh
git commit -m "feat(rules-gate): адрес нормы резолвится, id уникален — гейт с доказательством на четыре оси"
```

---

### Task 4: Починить висячие адреса, которые нашёл check-07

**Files:**
- Modify: `.claude/rules/*.md`, `.claude/agents/*.md`, `CLAUDE.md` — только координаты в ссылках
- Modify: `../kacho/internal/repohygiene/contractadvice.go:112`, `contractadvice_injection_test.go:17`, `gatecarrierremoval_injection_test.go:34`, `probewriteslivetree_test.go:31`
- Test: `scripts/rules-gate/check-07-address-resolves.sh`

**Interfaces:**
- Consumes: `python3 scripts/rules-gate/address-refs.py --list` (Task 3)
- Produces: `check-07` зелёный. Все последующие задачи держат его зелёным.

- [ ] **Step 1: Снять перепись висячих адресов**

```bash
python3 scripts/rules-gate/address-refs.py --list | awk -F'\t' '$3=="ВИСИТ"{print}' \
  | tee tmp/rules-compression/dangling-before.txt | wc -l
```

- [ ] **Step 2: Починить каждый адрес — цель, а не ссылку**

Правило разбора каждой строки переписи: найти, где раздел живёт сейчас, и исправить **имя файла** в ссылке. Известные случаи:

```bash
# `multi-agent-flow.md §13` и §«НЕПРИКОСНОВЕННОСТЬ ЧУЖОГО СОСТОЯНИЯ»
# → раздел живёт в multi-agent-flow-shared-tree.md:273
grep -rln 'multi-agent-flow\.md`\? *§\(13\|«НЕПРИКОСНОВЕННОСТЬ\)' .claude ../kacho/internal/repohygiene
sed -i 's/multi-agent-flow\.md` §13/multi-agent-flow-shared-tree.md` §13/g; \
        s/multi-agent-flow\.md` §«НЕПРИКОСНОВЕННОСТЬ ЧУЖОГО СОСТОЯНИЯ»/multi-agent-flow-shared-tree.md` §«НЕПРИКОСНОВЕННОСТЬ ЧУЖОГО СОСТОЯНИЯ»/g' \
  ../kacho/internal/repohygiene/contractadvice.go \
  ../kacho/internal/repohygiene/contractadvice_injection_test.go \
  ../kacho/internal/repohygiene/gatecarrierremoval_injection_test.go \
  ../kacho/internal/repohygiene/probewriteslivetree_test.go

# ссылка на 08-known-divergences.md — файла в корпусе нет вовсе:
# найти источник и заменить на действующую координату либо снять ссылку
grep -rn '08-known-divergences' .claude CLAUDE.md
```

Для каждого остального адреса из переписи: если цель — заголовок, который схлопнется в Task 6–14, ссылку перевести на будущий `#<id>` из описи; если цель не существует нигде — ссылку снять вместе с утверждением, которое на неё опиралось.

- [ ] **Step 3: Прогнать гейт и увидеть зелёное**

```bash
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
(cd ../kacho && go build ./... && go test ./internal/repohygiene/ -run 'TestContractAdvice|TestGateCarrierRemoval|TestProbeWritesLiveTree' -count=1)
```

Ожидается: `check-07: 0`, `run-all: 0`, Go-тесты зелёные (правились только комментарии, поведение не менялось).

- [ ] **Step 4: Записать, сколько починено**

```bash
python3 scripts/rules-gate/address-refs.py --list | awk -F'\t' '$3=="ВИСИТ"' | wc -l   # обязан быть 0
wc -l < tmp/rules-compression/dangling-before.txt                                       # сколько было
```

- [ ] **Step 5: Коммит**

Два коммита — два репозитория:

```bash
git add .claude CLAUDE.md tmp/rules-compression/dangling-before.txt
git commit -m "fix(rules): висячие адреса разделов приведены к дереву — check-07 зелёный"
(cd ../kacho && git add internal/repohygiene/ && \
 git commit -m "fix(repohygiene): координата правила в комментарии гейта указывает в существующий раздел")
```

---

### Task 5: Два прибора — объём/форма корпуса и отбор норм из описи

Нужен задачам 7–15: каждая обязана доказать свой бюджет и форму замером, а не на глаз.

**Files:**
- Create: `scripts/rules-gate/measure.sh`
- Create: `scripts/rules-gate/rows-from-inventory.py`
- Test: сами себя — печатают известные значения до переписывания

**Interfaces:**
- Produces: `scripts/rules-gate/measure.sh` без аргументов печатает корпус и разбивку по файлам; `measure.sh <файл>` — один файл; `measure.sh --form` — доля строк-норм и строки без `red:`. Код выхода 0 всегда: это прибор, не гейт.
- Produces: `scripts/rules-gate/rows-from-inventory.py <файл.md>…` — строки-нормы в `tmp/rules-compression/rows-<файл>.txt` плюс сводка; `--verify` сверяет, что все id классов A и B есть в корпусе, код 1 при потере. Потребляется задачами 7–15.

- [ ] **Step 1: Написать прибор**

```bash
cat > scripts/rules-gate/measure.sh <<'SH'
#!/usr/bin/env bash
# Прибор объёма и формы корпуса. НЕ гейт: код выхода всегда 0, вердикт — у check-06.
# Символы, не байты: кириллица в UTF-8 вдвое тяжелее, и `wc -c` дал бы вдвое больше.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
case "${1:-}" in
  --form)
    rows=$(grep -h ' · ' .claude/rules/*.md | wc -l)
    nored=$(grep -h ' · ' .claude/rules/*.md | grep -vc 'red:' || true)
    todo=$(grep -ho 'ЗАВЕСТИ [A-Za-z0-9_]*' .claude/rules/*.md | sort -u | wc -l)
    held=$(grep -hc 'держится' .claude/rules/*.md | awk '{s+=$1} END{print s+0}')
    printf 'строк-норм: %s\nбез поля red: %s (обязан быть 0)\nЗАВЕСТИ, различных: %s\nслово «держится»: %s (обязан быть 0)\n' \
      "$rows" "$nored" "$todo" "$held"
    ;;
  '')
    python3 - <<'PY'
import glob,os
tot=0; rows=[]
for f in sorted(glob.glob('.claude/rules/*.md')):
    n=len(open(f,encoding='utf-8').read()); tot+=n; rows.append((n,os.path.basename(f)))
for n,b in sorted(rows,reverse=True): print(f'{n:>8}  {b}')
print(f'{tot:>8}  ИТОГО, потолок 200000, запас {200000-tot}')
PY
    ;;
  *)
    python3 -c "import sys;print(len(open(sys.argv[1],encoding='utf-8').read()))" ".claude/rules/$1"
    ;;
esac
SH
chmod +x scripts/rules-gate/measure.sh
```

- [ ] **Step 2: Прогнать и сверить с известным значением**

```bash
scripts/rules-gate/measure.sh | tail -1
scripts/rules-gate/measure.sh 00-kacho-core.md
scripts/rules-gate/measure.sh --form
```

Ожидается: итог ≈ **621 800** (618 189 + frontmatter Task 2), `00-kacho-core.md` ≈ 22 630, и в `--form`: `строк-норм: 0`, `без поля red: 0`, `слово «держится»: 92` — до переписывания так и должно быть.

- [ ] **Step 3: Записать точку отсчёта**

```bash
scripts/rules-gate/measure.sh > tmp/rules-compression/measure-before.txt
scripts/rules-gate/measure.sh --form >> tmp/rules-compression/measure-before.txt
cat tmp/rules-compression/measure-before.txt
```

- [ ] **Step 4: Завести второй прибор — отбор строк из описи**

Нужен задачам 7–15: каждая берёт свои нормы из описи и доказывает, что ни одна не потеряна.

```bash
cat > scripts/rules-gate/rows-from-inventory.py <<'ZZ'
#!/usr/bin/env python3
# Отбор норм классов A и B из описи в форму корпуса.
#   rows-from-inventory.py <файл.md> [...]          — сводка + строки в tmp/rules-compression/rows-<файл>.txt
#   rows-from-inventory.py --verify <файл.md> [...] — сверка, что все id A+B есть в корпусе (код 1 при потере)
import json, re, sys, pathlib

INV = 'tmp/rules-compression/inventory-2026-09-19.json'
OUT = pathlib.Path('tmp/rules-compression')
DOT = ' · '
DASH = '—'
GATELESS = 'ЗАВЕСТИ ' + DASH
HAND = 'ПИСАТЬ РУКАМИ'


def row(n):
    fm = (n.get('form') or '').strip()
    if not fm or fm == DASH:
        return None
    p = [x.strip(' `') for x in re.split(r'\s*\|\s*', fm) if x.strip(' `')]
    if len(p) >= 4:
        imp, hold, red = p[1], p[2], ' | '.join(p[3:])
    elif len(p) == 3:
        imp, hold, red = p[1], p[2], DASH
    elif len(p) == 2:
        imp, hold, red = p[1], GATELESS, DASH
    else:
        imp, hold, red = p[0], GATELESS, DASH
    return n['id'] + DOT + imp + DOT + hold + DOT + 'red: ' + red


def main(argv):
    verify = '--verify' in argv
    files = [a for a in argv if a != '--verify']
    if not files:
        print('нужен хотя бы один файл правил')
        return 1
    inv = json.load(open(INV, encoding='utf-8'))
    OUT.mkdir(parents=True, exist_ok=True)
    rc = 0
    for f in files:
        ab = [n for n in inv if n['src'] == f and n['k'] in ('A', 'B')]
        cd = [n for n in inv if n['src'] == f and n['k'] in ('C', 'D')]
        if not ab:
            print(f + ': КРАСНОЕ — в описи нет ни одной нормы A/B, отбор пуст')
            rc = 1
            continue
        if verify:
            have = set()
            for line in open('.claude/rules/' + f, encoding='utf-8'):
                if DOT in line:
                    have.add(line.split(DOT)[0].strip())
            want = {n['id'] for n in ab}
            miss = sorted(want - have)
            size = len(open('.claude/rules/' + f, encoding='utf-8').read())
            print(f'{f}: ожидается {len(want)}, найдено {len(want & have)}, ПОТЕРЯНО {len(miss)}, объём {size}')
            if miss:
                print('   потеряны: ' + ', '.join(miss[:20]))
                rc = 1
            continue
        rows = [(n['id'], row(n)) for n in ab]
        hand = [i for i, r in rows if not r]
        dst = OUT / ('rows-' + f + '.txt')
        with open(dst, 'w', encoding='utf-8') as out:
            for i, r in rows:
                out.write((r or (i + DOT + HAND + DOT + GATELESS + DOT + 'red: ' + DASH)) + '\n')
        chars = sum(len(r) + 1 for _, r in rows if r) + len(hand) * 160
        print(f'{f}: строк {len(rows)}, руками {len(hand)}, в архив {len(cd)}, символов ~{chars} -> {dst}')
        if hand:
            print('   руками: ' + ', '.join(hand))
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
ZZ
chmod +x scripts/rules-gate/rows-from-inventory.py
python3 scripts/rules-gate/rows-from-inventory.py rag.md
python3 scripts/rules-gate/rows-from-inventory.py --verify rag.md; echo "verify до переписывания: $? (ожидается 1 — строк-норм ещё нет)"
```

Ожидается: `rag.md: строк 1, руками 0, в архив 11, символов ~167 -> tmp/rules-compression/rows-rag.md.txt`,
и `verify` красный, потому что корпус ещё не переписан.

- [ ] **Step 5: Коммит**

```bash
git add scripts/rules-gate/measure.sh scripts/rules-gate/rows-from-inventory.py tmp/rules-compression/
git commit -m "feat(rules-gate): два прибора — объём и форма корпуса, отбор норм из описи"
```

---

### Task 6: Архив и 30 строк-якорей

**Files:**
- Create: `.claude/backup/README.md`
- Create: `.claude/backup/<30 файлов>.md`
- Modify: все 30 `.claude/rules/*.md` — по одной строке-якорю
- Modify: `.claude/settings.json` — `claudeMdExcludes` += `**/.claude/backup/**`
- Modify: `.claude/hooks/docfresh/docfresh.py` — `TRUTH_EXCLUDE` += `:(exclude).claude/backup/`
- Modify: `.claude/hooks/rag-freshness.sh` → `.claude/backup/hooks/rag-freshness.sh` (единственный сирота по замеру ссылок)

**Interfaces:**
- Produces: `.claude/backup/<имя>.md` для каждого файла корпуса; в корпусе по строке `archive · доводы, замеры и снятые редакции — .claude/backup/<имя>.md`. Задачи 7–15 при переписывании кладут класс D в соответствующий архивный файл, а не удаляют.

- [ ] **Step 1: Завести архив с объявлением предмета**

```bash
mkdir -p .claude/backup
cat > .claude/backup/README.md <<'MD'
# Архив корпуса правил

Здесь лежит то, что снято с `.claude/rules/` решением владельца 2026-09-19: доводы «почему так
решили», исторические замеры с датами, описания отменённых устройств, пересказы соседних правил.

**Это не нормы.** Норма живёт в `.claude/rules/<имя>.md` строкой
`<id> · <императив> · <держатель> · red: <признак>`. Архив отвечает на вопрос «почему», и его
никто не грузит автоматически: он вне `.claude/`, в бюджет 200 000 символов не входит.

Файл архива называется так же, как файл правила, из которого снято. Каждая запись несёт id нормы,
к которой относится, либо помету `снято целиком` с датой.

Опись, по которой делался разрез: `tmp/rules-compression/inventory-2026-09-19.json`
(1 436 норм; класс D — 318 записей, 193 420 символов).
MD
for f in .claude/rules/*.md; do
  b=$(basename "$f")
  printf '# Архив: %s\n\nСнято 2026-09-19. Норма живёт в `.claude/rules/%s`.\n' "$b" "$b" \
    > ".claude/backup/$b"
done
ls .claude/backup | wc -l   # ожидается 31 (30 + README.md)
```

- [ ] **Step 2: Вписать якорь в каждый файл корпуса**

```bash
python3 - <<'PY'
import glob,os
for f in sorted(glob.glob('.claude/rules/*.md')):
    b=os.path.basename(f)
    line=f'archive · доводы, замеры и снятые редакции — .claude/backup/{b}\n'
    t=open(f,encoding='utf-8').read()
    if line in t: continue
    # якорь идёт сразу после frontmatter, до первого заголовка
    i=t.index('\n---\n',4)+5
    open(f,'w',encoding='utf-8').write(t[:i]+'\n'+line+t[i:])
    print(b,'+',len(line))
PY
```

- [ ] **Step 3: Три механизма, без которых адрес `.claude/backup/` вредит**

Архив лежит ВНУТРИ `.claude/`, поэтому одного каталога недостаточно.

```bash
# (1) страховка от автозагрузки: корпус правил Claude Code грузит из .claude сам
python3 - <<'ZZ'
import json,io
p='.claude/settings.json'
s=json.load(open(p,encoding='utf-8'))
ex=s.setdefault('claudeMdExcludes',[])
if '**/.claude/backup/**' not in ex:
    ex.append('**/.claude/backup/**')
io.open(p,'w',encoding='utf-8').write(json.dumps(s,ensure_ascii=False,indent=2)+'\n')
print('claudeMdExcludes:',ex)
ZZ

# (2) docfresh не должен светиться на архивных координатах.
# docfresh.py:125 обходит .claude целиком, исключая только .claude/hooks/ (TRUTH_EXCLUDE).
# Архивный текст называет координаты, верные НА МОМЕНТ снятия, и давал бы находки на каждой записи.
grep -n 'TRUTH_EXCLUDE' .claude/hooks/docfresh/docfresh.py
```

Правка `docfresh.py`: превратить `TRUTH_EXCLUDE` в пару pathspec'ов и дописать довод рядом —
одной строкой, в стиле соседних комментариев файла:

```python
# Предмет docfresh — ЖИВОЕ утверждение о дереве. Архив живым не является by construction:
# его текст называет координаты, верные на момент снятия, и держать его под тем же судом
# значило бы требовать от истории соответствия сегодняшнему дереву.
TRUTH_EXCLUDE = (":(exclude).claude/hooks/", ":(exclude).claude/backup/")
```

и в вызове на строке ~834 раскрыть пару вместо одиночного значения: `*TRUTH_EXCLUDE`.

```bash
# (3) единственный сирота оснастки по замеру ссылок: хук, не провязанный в settings.json
mkdir -p .claude/backup/hooks
git mv .claude/hooks/rag-freshness.sh .claude/backup/hooks/rag-freshness.sh
printf '\n## hooks\n\n- `rag-freshness.sh` — снят 2026-09-20: в `.claude/settings.json` не провязан ни в одном из 10 вызовов.\n  Возврат: `git mv .claude/backup/hooks/rag-freshness.sh .claude/hooks/`.\n' >> .claude/backup/README.md
```

Доказательство всех трёх:

```bash
python3 -c "
import json
ex=json.load(open('.claude/settings.json',encoding='utf-8')).get('claudeMdExcludes',[])
print('claudeMdExcludes:',ex)
assert '**/.claude/backup/**' in ex and '**/.claude/rules/**' in ex
print('OK (1)')"
grep -c 'exclude).claude/backup/' .claude/hooks/docfresh/docfresh.py   # обязан быть 1
python3 -c "
import ast,sys
ast.parse(open('.claude/hooks/docfresh/docfresh.py',encoding='utf-8').read()); print('OK (2) docfresh парсится')"
test ! -f .claude/hooks/rag-freshness.sh && test -f .claude/backup/hooks/rag-freshness.sh && echo "OK (3) сирота переехал"
python3 -c "
import json,re
s=json.dumps(json.load(open('.claude/settings.json',encoding='utf-8')))
assert 'rag-freshness' not in s, 'хук всё же провязан — вернуть его на место'
print('OK (3) в settings.json на него ссылок нет')"
bash .claude/hooks/hooks-wired.sh; echo "hooks-wired: $?"
```

Ожидается: `OK (1)`, `1`, `OK (2)`, `OK (3)` дважды, и `hooks-wired` не краснеет на снятом хуке.
Если `hooks-wired.sh` покраснеет — хук провязан не через `settings.json`, а иначе: верни его
командой из `README.md` и запиши это находкой в отчёт.

- [ ] **Step 4: Прогнать гейты и прибор**

```bash
scripts/rules-gate/run-all.sh; echo "run-all: $?"
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/measure.sh | tail -1
```

Ожидается: оба гейта 0; итог ≈ 624 500 (+2 700 якорей). Объём пока растёт — переписывание идёт следующими задачами.

- [ ] **Step 5: Коммит**

```bash
git add .claude/backup/ .claude/rules/ .claude/settings.json .claude/hooks/ .gitignore
git commit -m "feat(rules): архив легаси в .claude/backup — якоря, исключения, снятый сирота-хук"
```

---
### Task 7: Переписать партию «ядро и письмо»

читается всеми 30 агентами — форму проверяем здесь первой. Всего 36 086 → **7 645** символов (÷4.7), норм A/B 30/21, без готовой строки 1.

**Files:**
- Modify: `.claude/rules/00-kacho-core.md` — 22 508 → **5 201** симв, норм 28/8, руками 1
- Modify: `.claude/backup/00-kacho-core.md` — принимает классы C и D этого файла (10 968 симв)
- Modify: `.claude/rules/writing.md` — 10 856 → **2 277** симв, норм 1/13, руками 0
- Modify: `.claude/backup/writing.md` — принимает классы C и D этого файла (7 181 симв)
- Modify: `.claude/rules/rag.md` — 2 722 → **167** симв, норм 1/0, руками 0
- Modify: `.claude/backup/rag.md` — принимает классы C и D этого файла (2 547 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['00-kacho-core.md', 'writing.md', 'rag.md'] и `k in ('A','B')`
- Produces: 51 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in 00-kacho-core.md writing.md rag.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `00-kacho-core.md` 22508, `writing.md` 10856, `rag.md` 2722.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py 00-kacho-core.md writing.md rag.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `00-kacho-core.md:108-118`, было 999 символов, стало 129:

```
ban17-ci-job-keys · только латиница · гейт разобранного YAML · red: кириллический ключ: заданий ноль, вместо имени — путь к файлу
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in 00-kacho-core.md writing.md rag.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify 00-kacho-core.md writing.md rag.md
```

Ожидается: каждый файл в своём бюджете (`00-kacho-core.md` ≤ 5201, `writing.md` ≤ 2277, `rag.md` ≤ 167), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/00-kacho-core.md .claude/rules/writing.md .claude/rules/rag.md .claude/backup/00-kacho-core.md .claude/backup/writing.md .claude/backup/rag.md
git commit -m "refactor(rules): партия «ядро и письмо» сведена к строкам-нормам, доводы в архив"
```

---

### Task 8: Переписать партию «контракт и слои»

самая крупная партия класса A. Всего 85 402 → **23 262** символов (÷3.7), норм A/B 108/29, без готовой строки 13.

**Files:**
- Modify: `.claude/rules/api-conventions.md` — 37 337 → **14 552** симв, норм 63/16, руками 7
- Modify: `.claude/backup/api-conventions.md` — принимает классы C и D этого файла (4 695 симв)
- Modify: `.claude/rules/architecture.md` — 10 205 → **3 829** симв, норм 22/6, руками 0
- Modify: `.claude/backup/architecture.md` — принимает классы C и D этого файла (2 553 симв)
- Modify: `.claude/rules/polyrepo.md` — 37 860 → **4 881** симв, норм 23/7, руками 6
- Modify: `.claude/backup/polyrepo.md` — принимает классы C и D этого файла (26 637 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['api-conventions.md', 'architecture.md', 'polyrepo.md'] и `k in ('A','B')`
- Produces: 137 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in api-conventions.md architecture.md polyrepo.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `api-conventions.md` 37337, `architecture.md` 10205, `polyrepo.md` 37860.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py api-conventions.md architecture.md polyrepo.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `api-conventions.md:90-102`, было 1221 символов, стало 230:

```
api-operation-done · = ресурс закоммичен, и только это; запрещено гейтить на видимость downstream (FGA-tuple, зеркало, drain outbox) · TestPublishedResourceIdIsGuardedByOperationOutcome · red: confirm-барьер рождает phantom-ресурс
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in api-conventions.md architecture.md polyrepo.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify api-conventions.md architecture.md polyrepo.md
```

Ожидается: каждый файл в своём бюджете (`api-conventions.md` ≤ 14552, `architecture.md` ≤ 3829, `polyrepo.md` ≤ 4881), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/api-conventions.md .claude/rules/architecture.md .claude/rules/polyrepo.md .claude/backup/api-conventions.md .claude/backup/architecture.md .claude/backup/polyrepo.md
git commit -m "refactor(rules): партия «контракт и слои» сведена к строкам-нормам, доводы в архив"
```

---

### Task 9: Переписать партию «данные и поток»

целостность данных и единственная форма подписки. Всего 46 157 → **21 647** символов (÷2.1), норм A/B 109/15, без готовой строки 5.

**Files:**
- Modify: `.claude/rules/data-integrity.md` — 33 060 → **14 171** симв, норм 72/6, руками 2
- Modify: `.claude/backup/data-integrity.md` — принимает классы C и D этого файла (13 090 симв)
- Modify: `.claude/rules/subscription.md` — 13 097 → **7 476** симв, норм 37/9, руками 3
- Modify: `.claude/backup/subscription.md` — принимает классы C и D этого файла (1 305 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['data-integrity.md', 'subscription.md'] и `k in ('A','B')`
- Produces: 124 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in data-integrity.md subscription.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `data-integrity.md` 33060, `subscription.md` 13097.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py data-integrity.md subscription.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `subscription.md:125-132`, было 629 символов, стало 204:

```
sub-coverage-from-producer · выводи у производителя (`knownKinds` первым кадром, `hub.covers()`), не выписывай перечнем · subscriptionkindvocabulary · red: выписанный перечень разошёлся с владельцем молча
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in data-integrity.md subscription.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify data-integrity.md subscription.md
```

Ожидается: каждый файл в своём бюджете (`data-integrity.md` ≤ 14171, `subscription.md` ≤ 7476), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/data-integrity.md .claude/rules/subscription.md .claude/backup/data-integrity.md .claude/backup/subscription.md
git commit -m "refactor(rules): партия «данные и поток» сведена к строкам-нормам, доводы в архив"
```

---

### Task 10: Переписать партию «тесты»

ни одной нормы без готовой строки — партия механическая. Всего 49 953 → **20 159** символов (÷2.5), норм A/B 77/24, без готовой строки 0.

**Files:**
- Modify: `.claude/rules/testing.md` — 36 040 → **14 937** симв, норм 60/17, руками 0
- Modify: `.claude/backup/testing.md` — принимает классы C и D этого файла (9 268 симв)
- Modify: `.claude/rules/testing-newman.md` — 7 631 → **3 691** симв, норм 16/1, руками 0
- Modify: `.claude/backup/testing-newman.md` — принимает классы C и D этого файла (1 945 симв)
- Modify: `.claude/rules/testing-load.md` — 6 282 → **1 531** симв, норм 1/6, руками 0
- Modify: `.claude/backup/testing-load.md` — принимает классы C и D этого файла (1 527 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['testing.md', 'testing-newman.md', 'testing-load.md'] и `k in ('A','B')`
- Produces: 101 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in testing.md testing-newman.md testing-load.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `testing.md` 36040, `testing-newman.md` 7631, `testing-load.md` 6282.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py testing.md testing-newman.md testing-load.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `testing.md:466-482`, было 1031 символов, стало 187:

```
env-value-asked-not-written · спрашивай у самой полосы, не выписывай литералом · TestQuotaShowPosture_HardcodedDeclaredIsAFinding · red: рядом с литералом комментарий «объявлено посадкой»
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in testing.md testing-newman.md testing-load.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify testing.md testing-newman.md testing-load.md
```

Ожидается: каждый файл в своём бюджете (`testing.md` ≤ 14937, `testing-newman.md` ≤ 3691, `testing-load.md` ≤ 1531), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/testing.md .claude/rules/testing-newman.md .claude/rules/testing-load.md .claude/backup/testing.md .claude/backup/testing-newman.md .claude/backup/testing-load.md
git commit -m "refactor(rules): партия «тесты» сведена к строкам-нормам, доводы в архив"
```

---

### Task 11: Переписать партию «вердикт и e2e»

преобладает класс B — нормы о том, как качество доказывается. Всего 55 500 → **18 893** символов (÷2.9), норм A/B 30/75, без готовой строки 0.

**Files:**
- Modify: `.claude/rules/testing-verdict.md` — 31 342 → **9 065** симв, норм 8/39, руками 0
- Modify: `.claude/backup/testing-verdict.md` — принимает классы C и D этого файла (4 780 симв)
- Modify: `.claude/rules/e2e-flow.md` — 24 158 → **9 828** симв, норм 22/36, руками 0
- Modify: `.claude/backup/e2e-flow.md` — принимает классы C и D этого файла (10 209 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['testing-verdict.md', 'e2e-flow.md'] и `k in ('A','B')`
- Produces: 105 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in testing-verdict.md e2e-flow.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `testing-verdict.md` 31342, `e2e-flow.md` 24158.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py testing-verdict.md e2e-flow.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `testing-verdict.md:141-153`, было 1109 символов, стало 219:

```
cache-restore-save-split-paid-run · разделяй cache/restore и cache/save; сохраняй по признаку полноты от самого шага · TestCacheFillsOnTheRunThatPaidForIt · red: кэш наполняется только прогоном, которому он не был нужен
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in testing-verdict.md e2e-flow.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify testing-verdict.md e2e-flow.md
```

Ожидается: каждый файл в своём бюджете (`testing-verdict.md` ≤ 9065, `e2e-flow.md` ≤ 9828), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/testing-verdict.md .claude/rules/e2e-flow.md .claude/backup/testing-verdict.md .claude/backup/e2e-flow.md
git commit -m "refactor(rules): партия «вердикт и e2e» сведена к строкам-нормам, доводы в архив"
```

---

### Task 12: Переписать партию «безопасность»

`security-disclosure.md` схлопывается до 405 символов: из 19 норм к классам A/B относятся 2. Всего 58 532 → **18 941** символов (÷3.1), норм A/B 74/24, без готовой строки 0.

**Files:**
- Modify: `.claude/rules/security.md` — 23 777 → **8 683** симв, норм 35/7, руками 0
- Modify: `.claude/backup/security.md` — принимает классы C и D этого файла (10 764 симв)
- Modify: `.claude/rules/security-hardening.md` — 22 539 → **9 853** симв, норм 39/15, руками 0
- Modify: `.claude/backup/security-hardening.md` — принимает классы C и D этого файла (7 069 симв)
- Modify: `.claude/rules/security-disclosure.md` — 12 216 → **405** симв, норм 0/2, руками 0
- Modify: `.claude/backup/security-disclosure.md` — принимает классы C и D этого файла (11 161 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['security.md', 'security-hardening.md', 'security-disclosure.md'] и `k in ('A','B')`
- Produces: 98 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in security.md security-hardening.md security-disclosure.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `security.md` 23777, `security-hardening.md` 22539, `security-disclosure.md` 12216.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py security.md security-hardening.md security-disclosure.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `security.md:86-96`, было 950 символов, стало 201:

```
sec-exception-iam-jwks · единственное authN-исключение; на wire только публичный материал · TestProviderSurfaceInjection_OurOwnKeySetPathIsSilent · red: исключение расширено на другой путь или листенер
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in security.md security-hardening.md security-disclosure.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify security.md security-hardening.md security-disclosure.md
```

Ожидается: каждый файл в своём бюджете (`security.md` ≤ 8683, `security-hardening.md` ≤ 9853, `security-disclosure.md` ≤ 405), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/security.md .claude/rules/security-hardening.md .claude/rules/security-disclosure.md .claude/backup/security.md .claude/backup/security-hardening.md .claude/backup/security-disclosure.md
git commit -m "refactor(rules): партия «безопасность» сведена к строкам-нормам, доводы в архив"
```

---

### Task 13: Переписать партию «консоль»

один файл, читают 2 агента. Всего 30 061 → **7 555** символов (÷4.0), норм A/B 33/12, без готовой строки 0.

**Files:**
- Modify: `.claude/rules/ui.md` — 30 061 → **7 555** симв, норм 33/12, руками 0
- Modify: `.claude/backup/ui.md` — принимает классы C и D этого файла (12 818 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['ui.md'] и `k in ('A','B')`
- Produces: 45 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in ui.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `ui.md` 30061.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py ui.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `ui.md:282-294`, было 930 символов, стало 201:

```
ui-probe-lives-in-e2e-specs · кладите в `ui-future/e2e/specs/`; модульная её не замещает · TestConsoleProbeIssueLinks…` обходит `e2e/specs · red: находка закрыта jest-пробой, зовущей компонент функцией
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in ui.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify ui.md
```

Ожидается: каждый файл в своём бюджете (`ui.md` ≤ 7555), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/ui.md .claude/backup/ui.md
git commit -m "refactor(rules): партия «консоль» сведена к строкам-нормам, доводы в архив"
```

---

### Task 14: Переписать партию «волна»

самое сильное сжатие: классы C и D здесь преобладали. Всего 123 739 → **17 469** символов (÷7.1), норм A/B 64/66, без готовой строки 2.

**Files:**
- Modify: `.claude/rules/multi-agent-flow.md` — 32 967 → **2 004** симв, норм 9/5, руками 0
- Modify: `.claude/backup/multi-agent-flow.md` — принимает классы C и D этого файла (27 902 симв)
- Modify: `.claude/rules/multi-agent-flow-orchestration.md` — 35 586 → **5 351** симв, норм 19/23, руками 0
- Modify: `.claude/backup/multi-agent-flow-orchestration.md` — принимает классы C и D этого файла (20 213 симв)
- Modify: `.claude/rules/multi-agent-flow-shared-tree.md` — 22 486 → **5 228** симв, норм 28/11, руками 0
- Modify: `.claude/backup/multi-agent-flow-shared-tree.md` — принимает классы C и D этого файла (10 387 симв)
- Modify: `.claude/rules/multi-agent-flow-waiting.md` — 14 289 → **3 451** симв, норм 8/20, руками 0
- Modify: `.claude/backup/multi-agent-flow-waiting.md` — принимает классы C и D этого файла (7 616 симв)
- Modify: `.claude/rules/01-wave-contract.md` — 18 411 → **1 435** симв, норм 0/7, руками 2
- Modify: `.claude/backup/01-wave-contract.md` — принимает классы C и D этого файла (13 343 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['multi-agent-flow.md', 'multi-agent-flow-orchestration.md', 'multi-agent-flow-shared-tree.md', 'multi-agent-flow-waiting.md', '01-wave-contract.md'] и `k in ('A','B')`
- Produces: 130 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in multi-agent-flow.md multi-agent-flow-orchestration.md multi-agent-flow-shared-tree.md multi-agent-flow-waiting.md 01-wave-contract.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `multi-agent-flow.md` 32967, `multi-agent-flow-orchestration.md` 35586, `multi-agent-flow-shared-tree.md` 22486, `multi-agent-flow-waiting.md` 14289, `01-wave-contract.md` 18411.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py multi-agent-flow.md multi-agent-flow-orchestration.md multi-agent-flow-shared-tree.md multi-agent-flow-waiting.md 01-wave-contract.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `multi-agent-flow-shared-tree.md:88-103`, было 951 символов, стало 144:

```
s-tmpdir-outside-repo · вне ЛЮБОГО репозитория · проба «корень без индекса» проходит · red: находит индекс объемлющего репозитория обходом вверх
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in multi-agent-flow.md multi-agent-flow-orchestration.md multi-agent-flow-shared-tree.md multi-agent-flow-waiting.md 01-wave-contract.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify multi-agent-flow.md multi-agent-flow-orchestration.md multi-agent-flow-shared-tree.md multi-agent-flow-waiting.md 01-wave-contract.md
```

Ожидается: каждый файл в своём бюджете (`multi-agent-flow.md` ≤ 2004, `multi-agent-flow-orchestration.md` ≤ 5351, `multi-agent-flow-shared-tree.md` ≤ 5228, `multi-agent-flow-waiting.md` ≤ 3451, `01-wave-contract.md` ≤ 1435), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/multi-agent-flow.md .claude/rules/multi-agent-flow-orchestration.md .claude/rules/multi-agent-flow-shared-tree.md .claude/rules/multi-agent-flow-waiting.md .claude/rules/01-wave-contract.md .claude/backup/multi-agent-flow.md .claude/backup/multi-agent-flow-orchestration.md .claude/backup/multi-agent-flow-shared-tree.md .claude/backup/multi-agent-flow-waiting.md .claude/backup/01-wave-contract.md
git commit -m "refactor(rules): партия «волна» сведена к строкам-нормам, доводы в архив"
```

---

### Task 15: Переписать партию «трекер и след»

100 норм класса C уезжают в архив целиком. Всего 132 759 → **19 179** символов (÷6.9), норм A/B 40/59, без готовой строки 9.

**Files:**
- Modify: `.claude/rules/git-issues.md` — 33 822 → **4 176** симв, норм 5/16, руками 2
- Modify: `.claude/backup/git-issues.md` — принимает классы C и D этого файла (25 467 симв)
- Modify: `.claude/rules/git-issues-branch-audit.md` — 16 614 → **4 020** симв, норм 15/5, руками 0
- Modify: `.claude/backup/git-issues-branch-audit.md` — принимает классы C и D этого файла (7 761 симв)
- Modify: `.claude/rules/git-issues-ci-runs.md` — 6 252 → **2 083** симв, норм 5/5, руками 0
- Modify: `.claude/backup/git-issues-ci-runs.md` — принимает классы C и D этого файла (2 763 симв)
- Modify: `.claude/rules/git-issues-issue-lifecycle.md` — 12 263 → **1 195** симв, норм 1/5, руками 1
- Modify: `.claude/backup/git-issues-issue-lifecycle.md` — принимает классы C и D этого файла (9 851 симв)
- Modify: `.claude/rules/vault.md` — 6 550 → **859** симв, норм 2/3, руками 1
- Modify: `.claude/backup/vault.md` — принимает классы C и D этого файла (4 773 симв)
- Modify: `.claude/rules/change-graph.md` — 14 694 → **3 358** симв, норм 8/12, руками 0
- Modify: `.claude/backup/change-graph.md` — принимает классы C и D этого файла (8 705 симв)
- Modify: `.claude/rules/ai-tooling.md` — 31 286 → **2 493** симв, норм 4/8, руками 4
- Modify: `.claude/backup/ai-tooling.md` — принимает классы C и D этого файла (27 276 симв)
- Modify: `.claude/rules/MANIFEST.md` — 11 278 → **995** симв, норм 0/5, руками 1
- Modify: `.claude/backup/MANIFEST.md` — принимает классы C и D этого файла (1 086 симв)
- Test: `scripts/rules-gate/measure.sh`, `run-all.sh`, `check-07-address-resolves.sh`, `check-08-rule-frontmatter.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/inventory-2026-09-19.json` — отбор `src` из ['git-issues.md', 'git-issues-branch-audit.md', 'git-issues-ci-runs.md', 'git-issues-issue-lifecycle.md', 'vault.md', 'change-graph.md', 'ai-tooling.md', 'MANIFEST.md'] и `k in ('A','B')`
- Produces: 99 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Снять точку отсчёта**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in git-issues.md git-issues-branch-audit.md git-issues-ci-runs.md git-issues-issue-lifecycle.md vault.md change-graph.md ai-tooling.md MANIFEST.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
```

Ожидается: `git-issues.md` 33822, `git-issues-branch-audit.md` 16614, `git-issues-ci-runs.md` 6252, `git-issues-issue-lifecycle.md` 12263, `vault.md` 6550, `change-graph.md` 14694, `ai-tooling.md` 31286, `MANIFEST.md` 11278.

- [ ] **Step 2: Выбрать нормы партии из описи**

```bash
python3 scripts/rules-gate/rows-from-inventory.py git-issues.md git-issues-branch-audit.md git-issues-ci-runs.md git-issues-issue-lifecycle.md vault.md change-graph.md ai-tooling.md MANIFEST.md
```

Скрипт заводится в Task 7 и печатает на каждый файл: строк, сколько писать руками, сколько в архив, сумма символов; строки кладёт в `tmp/rules-compression/rows-<файл>.txt`.

- [ ] **Step 3: Переписать каждый файл партии**

Сохранить: frontmatter (Task 2), строку-якорь (Task 6) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы.

Нормы с пометой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст,
свести к четырём полям. Ориентир — 172 символа; строка, из которой нельзя вывести вердикт,
не годится, даже если короткая.

Настоящий пример из описи — `git-issues-branch-audit.md:103-111`, было 714 символов, стало 193:

```
ba-seven-signs-table · применять все семь одним инструментом, руками не собирать · ./scripts/branch-audit.sh <репо> · red: вердикт по одному признаку (предок ствола, статус PR, возраст коммита)
```

- [ ] **Step 4: Прогнать замер и гейты**

```bash
for f in git-issues.md git-issues-branch-audit.md git-issues-ci-runs.md git-issues-issue-lifecycle.md vault.md change-graph.md ai-tooling.md MANIFEST.md; do printf '%-40s %s\n' "$f" "$(scripts/rules-gate/measure.sh "$f")"; done
scripts/rules-gate/measure.sh --form
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
python3 scripts/rules-gate/rows-from-inventory.py --verify git-issues.md git-issues-branch-audit.md git-issues-ci-runs.md git-issues-issue-lifecycle.md vault.md change-graph.md ai-tooling.md MANIFEST.md
```

Ожидается: каждый файл в своём бюджете (`git-issues.md` ≤ 4176, `git-issues-branch-audit.md` ≤ 4020, `git-issues-ci-runs.md` ≤ 2083, `git-issues-issue-lifecycle.md` ≤ 1195, `vault.md` ≤ 859, `change-graph.md` ≤ 3358, `ai-tooling.md` ≤ 2493, `MANIFEST.md` ≤ 995), `без поля red: 0`, все гейты 0,
«ни одна норма A/B не потеряна».

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/git-issues.md .claude/rules/git-issues-branch-audit.md .claude/rules/git-issues-ci-runs.md .claude/rules/git-issues-issue-lifecycle.md .claude/rules/vault.md .claude/rules/change-graph.md .claude/rules/ai-tooling.md .claude/rules/MANIFEST.md .claude/backup/git-issues.md .claude/backup/git-issues-branch-audit.md .claude/backup/git-issues-ci-runs.md .claude/backup/git-issues-issue-lifecycle.md .claude/backup/vault.md .claude/backup/change-graph.md .claude/backup/ai-tooling.md .claude/backup/MANIFEST.md
git commit -m "refactor(rules): партия «трекер и след» сведена к строкам-нормам, доводы в архив"
```

---

### Task 16: check-06 — потолок корпуса 200 000 символов

Заводится последним: гейт, красный в момент заведения, ничего не судит — он шумит.

**Files:**
- Create: `scripts/rules-gate/check-06-corpus-ceiling.sh`
- Create: `scripts/rules-gate/inject-06-corpus-ceiling.sh`
- Modify: `scripts/rules-gate/run-all.sh` — включить check-06, check-07, check-08 и их inject-*
- Test: сам набор `scripts/rules-gate/run-all.sh`

**Interfaces:**
- Consumes: корпус после задач 7–15
- Produces: `check-06` красный при сумме > 200 000 и при усечённом обходе; `run-all.sh` гоняет восемь проверок вместо пяти

- [ ] **Step 1: Убедиться, что объём уже под потолком**

```bash
cd "$(git rev-parse --show-toplevel)"
scripts/rules-gate/measure.sh | tail -1
```

Ожидается: итог ≈ **172 863**, запас ≈ 27 137. Если выше 200 000 — вернуться к партии, чей файл вышел за свой бюджет, и дожать её. Гейт не заводить.

- [ ] **Step 2: Написать гейт и увидеть зелёное**

```bash
cat > scripts/rules-gate/check-06-corpus-ceiling.sh <<'ZZ'
#!/usr/bin/env bash
# check-06 — КОРПУС ПРАВИЛ НЕ ВЫШЕ 200 000 СИМВОЛОВ (решение владельца 2026-09-19).
# Символы, не байты: wc -c дал бы вдвое больше на кириллице, и потолок не судил бы.
# Обход усечён -> красное: «ноль находок» обязано быть отличимо от «ноль прочитанного».
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 scripts/rules-gate/corpus_ceiling.py
ZZ
cat > scripts/rules-gate/corpus_ceiling.py <<'ZZ'
#!/usr/bin/env python3
import glob, sys

CAP = 200000
files = sorted(glob.glob('.claude/rules/*.md'))
if len(files) < 30:
    print('КРАСНОЕ — файлов правил ' + str(len(files)) + ', ожидалось не меньше 30: обход усечён, вердикт беспредметен')
    sys.exit(1)
sizes = {f: len(open(f, encoding='utf-8').read()) for f in files}
tot = sum(sizes.values())
print('осмотрено файлов: %d; корпус: %d символов; потолок: %d; запас: %d' % (len(files), tot, CAP, CAP - tot))
if tot > CAP:
    print('КРАСНОЕ — корпус выше потолка на %d' % (tot - CAP))
    for f, n in sorted(sizes.items(), key=lambda kv: -kv[1])[:5]:
        print('   %8d  %s' % (n, f))
    sys.exit(1)
sys.exit(0)
ZZ
chmod +x scripts/rules-gate/check-06-corpus-ceiling.sh
scripts/rules-gate/check-06-corpus-ceiling.sh; echo "check-06: $?"
```

Ожидается: `осмотрено файлов: 30; корпус: ~172863; потолок: 200000; запас: ~27137`, `check-06: 0`.

- [ ] **Step 3: Написать инъекционное доказательство и прогнать**

```bash
cat > scripts/rules-gate/inject-06-corpus-ceiling.sh <<'ZZ'
#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-06 по двум осям: перебор потолка и усечённый обход.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/check-06-corpus-ceiling.sh
T=.claude/rules/rag.md
mkdir -p /tmp/check06hide
cp "$T" /tmp/check06.orig
restore() { cp /tmp/check06.orig "$T" 2>/dev/null || true
            mv /tmp/check06hide/*.md .claude/rules/ 2>/dev/null || true; }
trap restore EXIT
fail=0
python3 -c "open('.claude/rules/rag.md','a',encoding='utf-8').write('x'*40000)"
if "$G" 2>&1 | grep -q 'выше потолка'; then echo 'ось A (перебор потолка): красное — OK'
else echo 'ось A: МОЛЧИТ — доказательство не прошло'; fail=1; fi
cp /tmp/check06.orig "$T"
mv .claude/rules/rag.md .claude/rules/vault.md /tmp/check06hide/
if "$G" 2>&1 | grep -q 'обход усечён'; then echo 'ось B (усечённый обход): красное — OK'
else echo 'ось B: МОЛЧИТ — доказательство не прошло'; fail=1; fi
mv /tmp/check06hide/rag.md /tmp/check06hide/vault.md .claude/rules/
if "$G" >/dev/null 2>&1; then echo 'ось Z (целое дерево): зелено — OK'
else echo 'ось Z: КРАСНОЕ — гейт шумит'; fail=1; fi
exit "$fail"
ZZ
chmod +x scripts/rules-gate/inject-06-corpus-ceiling.sh
scripts/rules-gate/inject-06-corpus-ceiling.sh; echo "inject-06: $?"
```

Ожидается: три строки OK, `inject-06: 0`.

- [ ] **Step 4: Включить три новые проверки в набор и прогнать всё**

```bash
grep -n 'check-0' scripts/rules-gate/run-all.sh
# дописать в перечень прогона: check-06, check-07, check-08 и inject-06, inject-07, inject-08
scripts/rules-gate/run-all.sh; echo "run-all: $?"
scripts/rules-gate/measure.sh | tail -1
scripts/rules-gate/measure.sh --form
python3 scripts/rules-gate/rows-from-inventory.py --verify $(cd .claude/rules && ls *.md | tr '\n' ' ')
```

Ожидается: `run-all: 0`; корпус ≤ 200 000; `без поля red: 0`; `слово «держится»: 0`; в сверке по всем 30 файлам `ПОТЕРЯНО 0` в каждой строке.

- [ ] **Step 5: Коммит**

```bash
git add scripts/rules-gate/
git commit -m "feat(rules-gate): потолок корпуса 200 000 символов держится гейтом, а не вниманием"
```

---

## Что остаётся после этого плана

- **46 гейтов на 239 норм класса A без механизма** — отдельная линия, в этот план не входит. До неё у такой нормы в корпусе стоит `ЗАВЕСТИ <имя>` и заведённая задача. Число различных `ЗАВЕСТИ` печатает `measure.sh --form`: это и есть названный числом долг.
- **Классы C и D в архиве** — 546 записей, 305 660 символов в `.claude/backup/`. Если процессный отказ начнёт повторяться, норму возвращают в корпус поимённо; запас 27 137 символов оставлен ровно для этого.
- **Замер цены набора после работы:** медиана 135 060 → 33 613, максимум 163 004 → 58 733, сумма по 30 агентам 3 565 283 → 980 772. Перемерить предикатом из §8 спеки.
