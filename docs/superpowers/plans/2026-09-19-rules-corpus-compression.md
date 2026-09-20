# Сжатие корпуса `.claude/rules` до 200 000 символов — план реализации (ред. 2, вариант iv)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** свести `.claude/rules` с 618 189 до **149 714** символов (÷4,13), оставив только нормы про написание кода, тестирование и доставку, и не потеряв ни одного сторожа качества.

**Architecture:** 17 файлов остаются основой, 13 процессных уезжают в `.claude/backup/` целиком. Из уезжающих спасаются **49 норм класса A, не держащихся ни одним гейтом** — они переселяются в `00-kacho-core.md`. Остальные 56 норм A из процессных файлов держатся названными гейтами: их текст уезжает, механизм остаётся в CI. Каждая норма становится одной строкой `<id> · <императив> · <держатель> · red: <признак>`.

**Tech Stack:** bash + python3 (гейты и приборы), Go-тесты `internal/repohygiene` в `PRO-Robotech/kacho` (только правка координат в комментариях), markdown.

**Spec:** `docs/superpowers/specs/2026-09-19-rules-corpus-compression-design.md`

## Global Constraints

- Потолок: **200 000 символов** на сумму `.claude/rules/*.md`. Символы, не байты: `len(open(f,encoding='utf-8').read())`, не `wc -c` — кириллица в UTF-8 вдвое тяжелее.
- Смета: нормы 138 714 + заголовки/frontmatter/якоря ~11 000 = **149 714**, запас **50 286 (25,1 %)**.
- Форма записи: `<id> · <императив> · <держатель> · red: <признак нарушения>`. Разделитель — ровно ` · ` (пробел, U+00B7, пробел). Без markdown-таблицы: палки стоят 40 % строки (244 симв против 172).
- Слово «держится» в корпусе не пишется **никогда**. Держатель — имя Go-теста, скрипта или команды; если гейта нет — `ЗАВЕСТИ <имя>`.
- **ОСНОВА, 17 файлов:** `00-kacho-core` `api-conventions` `architecture` `data-integrity` `subscription` `polyrepo` `ui` `security` `security-hardening` `security-disclosure` `testing` `testing-verdict` `testing-newman` `testing-load` `e2e-flow` `MANIFEST` `ai-tooling`.
- **ЛЕГАСИ, 13 файлов целиком в `.claude/backup/`:** `multi-agent-flow` `multi-agent-flow-orchestration` `multi-agent-flow-shared-tree` `multi-agent-flow-waiting` `git-issues` `git-issues-branch-audit` `git-issues-ci-runs` `git-issues-issue-lifecycle` `01-wave-contract` `change-graph` `writing` `vault` `rag`.
- Ни одна норма не удаляется безвозвратно: классы C и D базовых файлов — тоже в `.claude/backup/<файл>.md`.
- **Запись, несущая НАЗВАННЫЙ ГЕЙТ, — норма, какой бы класс ей ни присвоила опись.** Таких 93: 52 в классе D и 41 в классе C. Они остаются в корпусе строкой-ссылкой на гейт, а не уезжают. Предикат отбора: `gate` непусто и не `—`.
- **Класс D и C архивируются НЕ механически.** У 236 записей D и 111 записей C нет готовой формы в описи, то есть проверить снимаемое по описи нельзя. Правило разбора при переписывании: абзац в повелительной форме («обязан», «запрещено», «только», «не …ся», «не заводится») остаётся строкой-нормой, даже если опись присвоила ему D или C. Ревью нашло три таких на выборке из шести: `ext-factories` («фабрика обязана читать `error`»), `chk-fk` (отображение инварианта на `FK`/`CHECK`), `sec-nonzero-default-means-dead-guard` (это буквально поле `red:`).
- Работа в worktree `tmp/rules-compress`, ветка `rules/corpus-200k`. **Прямой push в `main` запрещён** (`multi-agent-flow-shared-tree.md §8а`, и защита ветки на origin это подтверждает: `enforce_admins: true`, 9 обязательных проверок). Только PR.
- Опись 1 436 норм: `tmp/rules-compression/inventory-2026-09-19.json`, поля `id`, `src`, `k`, `min`, `form`, `hold`, `gate`, `v`.
- **Нулевой шаг КАЖДОГО вызова Bash** (исполнитель Task 1 закоммитил не в то дерево — цена уже уплачена):

```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/tmp/rules-compress
test "$(git rev-parse --show-toplevel)" = "/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/tmp/rules-compress" || { echo "НЕ ТО ДЕРЕВО"; exit 1; }
```

## Раскладка целевого корпуса

| файл | сейчас | бюджет | A/B | руками | C+D в архив |
|---|---:|---:|---:|---:|---:|
| `testing.md` | 36 040 | **14 937** | 60/17 | 0 | 23 |
| `api-conventions.md` | 37 337 | **14 552** | 63/16 | 7 | 5 |
| `data-integrity.md` | 33 060 | **14 171** | 72/6 | 2 | 26 |
| `00-kacho-core.md` | 22 508 | **12 480** (+49 переселённых) | 28/8 | 1 | 30 |
| `security-hardening.md` | 22 539 | **9 853** | 39/15 | 0 | 15 |
| `e2e-flow.md` | 24 158 | **9 828** | 22/36 | 0 | 50 |
| `testing-verdict.md` | 31 342 | **9 065** | 8/39 | 0 | 10 |
| `security.md` | 23 777 | **8 683** | 35/7 | 0 | 21 |
| `ui.md` | 30 061 | **7 555** | 33/12 | 0 | 25 |
| `subscription.md` | 13 097 | **7 476** | 37/9 | 3 | 6 |
| `polyrepo.md` | 37 860 | **4 881** | 23/7 | 6 | 23 |
| `architecture.md` | 10 205 | **3 829** | 22/6 | 0 | 4 |
| `testing-newman.md` | 7 631 | **3 691** | 16/1 | 0 | 4 |
| `testing-load.md` | 6 282 | **1 531** | 1/6 | 0 | 3 |
| `security-disclosure.md` | 12 216 | **405** | 0/2 | 0 | 25 |
| **ИТОГО 15** | **348 113** | **138 800** | **459/187** | **19** | **270** |

Переселяется норм A без гейта: **49** на 7 000 символов, дом — `00-kacho-core.md` (его читают все 30 агентов).

**Партии переписывания:**

| партия | файлы | бюджет |
|---|---|---:|
| 1 | `testing` `api-conventions` `data-integrity` `00-kacho-core` `security-hardening` | 65 993 |
| 2 | `e2e-flow` `testing-verdict` `security` `ui` `subscription` | 42 607 |
| 3 | `polyrepo` `architecture` `testing-newman` `testing-load` `security-disclosure` | 14 337 |

---

### Task 1: Снять признак доставки корпуса и положить опись — ✅ ВЫПОЛНЕНА (bc26dd9c, 1783cda1)

Опись 1 436 норм положена, перепись 30 скилов без frontmatter снята, негация `!tmp/rules-compression/` в `.gitignore` заведена, задание пробы для владельца записано в `tmp/rules-compression/delivery-probe.md`.

---
### Task 2: Снять легаси — 13 процессных файлов в `.claude/backup/` с тремя механизмами

Самая рискованная задача плана: она рвёт 83 ссылки `skills:` и 50 inline-ссылок диспетчера и трогает `settings.json` и хук. Делается первой, потому что переписывать корпус, из которого ещё не вынуто легаси, — переписывать вдвое.

> [!important] Два файла НЕ уезжают, хотя по предмету процессные — попытка 1 это доказала
> Первая попытка Task 2 вернула BLOCKED: `rules-gate` упал с 5/5 до 1/5. Замер причины:
>
> - **`MANIFEST.md` — не норма, а объявление состава корпуса.** Его читают три проверки:
>   `check-01` (состав ↔ манифест в обе стороны), `check-03` (полнота строки), `check-04`
>   (привязка правило ↔ агент). Координата `.claude/rules/MANIFEST.md` стоит в них дословно
>   **3 раза**, слово `MANIFEST` — **17**. Унести его — сломать механизм, который держит всю
>   доставку правил. Остаётся; реестр сокращается с 30 строк до 17.
> - **`ai-tooling.md` — его перечни машинно несущие.** §«Канонические агенты» и §«Канонические
>   скилы» читают `skills-gate/check-03` и `check-07`: **47 строк на 7 918 символов**. Остаётся;
>   перечни сохраняются ДОСЛОВНО, остальное уезжает в архив при переписывании.
>
> Третья находка попытки 1: тела агентов несут **212** inline-ссылок вида `файл.md §«…»` на
> уезжающие файлы, из них **53 в `dispatcher.md`** — а `check-05` судит именно его ссылки.
> Снятие строк `skills:` их не трогает. Поэтому ниже добавлен Step 2а, и только с ним
> `rules-gate: 0` достижим. Остальные 162 ссылок в прочих агентах не судит никто — их найдёт
> `check-07` (Task 4) и починит Task 5.
>
> Цена решения: корпус 149 714 вместо 133 937, запас 50 286 вместо 66 063. Механизм дороже
> экономии: без `MANIFEST` доставка правил не держится ничем.

**Files:**
- Move: 13 `.claude/rules/<легаси>.md` → `.claude/backup/<легаси>.md`
- Delete: 13 `.claude/skills/rule-<легаси>/` (каталог с симлинком)
- Modify: `.claude/rules/MANIFEST.md` — снять 13 строк уезжающих, оставить 17; сам файл НЕ уезжает
- Modify: до 30 `.claude/agents/*.md` — 80 строк `skills:` снять; плюс 50 inline-ссылок в `dispatcher.md` (Step 2а)
- Modify: `.claude/settings.json` — `claudeMdExcludes` += `**/.claude/backup/**`
- Modify: `.claude/hooks/docfresh/docfresh.py` — `TRUTH_EXCLUDE` += `:(exclude).claude/backup/`
- Move: `.claude/hooks/rag-freshness.sh` → `.claude/backup/hooks/rag-freshness.sh`
- Create: `.claude/backup/README.md`

**Interfaces:**
- Consumes: перечень легаси из Global Constraints
- Produces: `.claude/rules/` содержит ровно 17 файлов; `rules-gate/run-all.sh` зелёный; ни один агент не остался без правил

- [ ] **Step 1: Снять перепись того, что придётся править**

```bash
LEG="multi-agent-flow multi-agent-flow-orchestration multi-agent-flow-shared-tree multi-agent-flow-waiting git-issues git-issues-branch-audit git-issues-ci-runs git-issues-issue-lifecycle 01-wave-contract change-graph writing vault rag"
for r in $LEG; do printf '%-36s ссылок skills: %s\n' "$r" "$(grep -l "^  - rule-$r\$" .claude/agents/*.md | wc -l)"; done
echo "всего ссылок снять: $(for r in $LEG; do grep -l "^  - rule-$r\$" .claude/agents/*.md; done | wc -l)"
scripts/rules-gate/run-all.sh >/dev/null 2>&1; echo "rules-gate до работы: $?"
```

Ожидается: суммарно **80** ссылок, `rules-gate до работы: 0`.

- [ ] **Step 2: Снять ссылки у агентов, затем строки манифеста, затем симлинки**

Порядок обязателен: `rules-gate/check-04` судит привязку в обе стороны, поэтому агент не должен остаться со ссылкой на снятое правило ни на один коммит.

```bash
LEG="multi-agent-flow multi-agent-flow-orchestration multi-agent-flow-shared-tree multi-agent-flow-waiting git-issues git-issues-branch-audit git-issues-ci-runs git-issues-issue-lifecycle 01-wave-contract change-graph writing vault rag"
for r in $LEG; do sed -i "/^  - rule-$r\$/d" .claude/agents/*.md; done
for r in $LEG; do sed -i "/^| \`$r\.md\` |/d" .claude/rules/MANIFEST.md; done
for r in $LEG; do git rm -r --quiet ".claude/skills/rule-$r"; done
python3 -c "
import glob,re,os
bad=[]
for p in sorted(glob.glob('.claude/agents/*.md')):
    m=re.search(r'(?ms)\A---\n(.*?)\n---\n',open(p,encoding='utf-8').read())
    if not m: continue
    n=re.findall(r'(?m)^\s*-\s*rule-([A-Za-z0-9._-]+)\s*\$',m.group(1))
    if 'skills:' in m.group(1) and not n: bad.append(os.path.basename(p))
print('агентов без единого правила:',len(bad),bad or '')
assert not bad, bad"
```

Ожидается: `агентов без единого правила: 0`.

- [ ] **Step 2а: Починить 50 inline-ссылок `dispatcher.md` на уезжающие файлы**

`check-05` судит ссылки диспетчера и покраснеет на каждой висячей.

```bash
LEG="multi-agent-flow multi-agent-flow-orchestration multi-agent-flow-shared-tree multi-agent-flow-waiting git-issues git-issues-branch-audit git-issues-ci-runs git-issues-issue-lifecycle 01-wave-contract change-graph writing vault rag"
for r in $LEG; do printf '%-36s %s\n' "$r" "$(grep -c "\`\?$r\.md\`\? *§" .claude/agents/dispatcher.md)"; done
echo "всего: $(for r in $LEG; do grep -oE "\`?$r\.md\`? *§" .claude/agents/dispatcher.md; done | wc -l)"
```

Каждую ссылку разобрать поимённо, не шаблоном. Три исхода, других нет:
1. утверждение диспетчера всё ещё нужно → переадресовать на оставшийся файл по предмету
   (норма-преемник ищется в `tmp/rules-compression/relocated-to-core.txt` или в описи по предмету);
2. утверждение уехало вместе с предметом → снять **вместе с утверждением**, а не оставить висеть;
3. ссылка была лишней (предмет назван и без неё) → снять ссылку, утверждение оставить.

Проверка после правки:

```bash
LEG="multi-agent-flow multi-agent-flow-orchestration multi-agent-flow-shared-tree multi-agent-flow-waiting git-issues git-issues-branch-audit git-issues-ci-runs git-issues-issue-lifecycle 01-wave-contract change-graph writing vault rag"
echo "осталось ссылок на уезжающие: $(for r in $LEG; do grep -oE "\`?$r\.md\`? *§" .claude/agents/dispatcher.md; done | wc -l)"   # обязан быть 0
scripts/rules-gate/check-05-dispatcher-routes-every-agent.sh 2>&1 | tail -2
```

- [ ] **Step 3: Переселить 49 норм класса A без гейта в `00-kacho-core.md`**

Они уезжали бы вместе с файлами и потеряли бы единственного сторожа. Список берётся из описи механически:

```bash
python3 - <<'ZZ'
import json,re
BASE={'00-kacho-core','api-conventions','architecture','data-integrity','subscription','polyrepo','ui','security','security-hardening','security-disclosure','testing','testing-verdict','testing-newman','testing-load','e2e-flow','MANIFEST','ai-tooling'}
inv=json.load(open('tmp/rules-compression/inventory-2026-09-19.json',encoding='utf-8'))
def gated(n): return bool(n.get('gate')) and n.get('gate') not in ('—','',None)
sel=[n for n in inv if n['src'][:-3] not in BASE and n['k']=='A' and not gated(n)]
def row(n):
    fm=(n.get('form') or '').strip()
    if not fm or fm=='—': return n['id']+' · ПИСАТЬ РУКАМИ · ЗАВЕСТИ — · red: —'
    p=[x.strip(' `') for x in re.split(r'\s*\|\s*',fm) if x.strip(' `')]
    if len(p)>=4: a,b,c=p[1],p[2],' | '.join(p[3:])
    elif len(p)==3: a,b,c=p[1],p[2],'—'
    elif len(p)==2: a,b,c=p[1],'ЗАВЕСТИ —','—'
    else: a,b,c=p[0],'ЗАВЕСТИ —','—'
    return n['id']+' · '+a+' · '+b+' · red: '+c
out=[row(n) for n in sel]
open('tmp/rules-compression/relocated-to-core.txt','w',encoding='utf-8').write('\n'.join(out)+'\n')
print('переселяется:',len(out),'норм,',sum(len(x)+1 for x in out),'символов')
assert len(out)==49, len(out)
ZZ
```

Эти 49 строк дописываются в `00-kacho-core.md` разделом `## Доставка и общее дерево` в **Task 8** (партия 1), а не здесь: здесь только заготовка, чтобы она не потерялась вместе с файлами.

- [ ] **Step 4: Переезд файлов и три механизма**

```bash
mkdir -p .claude/backup/hooks
LEG="multi-agent-flow multi-agent-flow-orchestration multi-agent-flow-shared-tree multi-agent-flow-waiting git-issues git-issues-branch-audit git-issues-ci-runs git-issues-issue-lifecycle 01-wave-contract change-graph writing vault rag"
for r in $LEG; do git mv ".claude/rules/$r.md" ".claude/backup/$r.md"; done
cat > .claude/backup/README.md <<'MD'
# Архив оснастки

Снято решением владельца 2026-09-20: «в `.claude` только те данные, которые используются при
написании кода, тестировании и доставке в k8s».

Здесь лежат 13 файлов правил, чей предмет — процесс вокруг кода (трекер, ветки, PR, волна,
записки, реестр), и классы C/D базовых файлов: исторические замеры, доводы «почему так решили»,
описания отменённых устройств, пересказы соседних правил.

**Это не нормы.** Норма живёт в `.claude/rules/<имя>.md` строкой
`<id> · <императив> · <держатель> · red: <признак>`.

Архив не грузится автоматически (`.claude/settings.json` → `claudeMdExcludes`) и не судится
`docfresh` (`TRUTH_EXCLUDE`): его текст называет координаты, верные на момент снятия.

**49 норм класса A из этих файлов НЕ снято** — они не держались ни одним гейтом и переселены
в `.claude/rules/00-kacho-core.md` §«Доставка и общее дерево». 56 норм A, держащихся названными
гейтами, здесь: механизм остался в CI, уехал только текст.

Возврат нормы в корпус: поимённо, запас 50 286 символа оставлен для этого.
MD
python3 - <<'ZZ'
import json,io
p='.claude/settings.json'
s=json.load(open(p,encoding='utf-8'))
ex=s.setdefault('claudeMdExcludes',[])
if '**/.claude/backup/**' not in ex: ex.append('**/.claude/backup/**')
io.open(p,'w',encoding='utf-8').write(json.dumps(s,ensure_ascii=False,indent=2)+'\n')
print('claudeMdExcludes:',ex)
ZZ
git mv .claude/hooks/rag-freshness.sh .claude/backup/hooks/rag-freshness.sh
printf '\n## hooks\n\n- `rag-freshness.sh` — снят 2026-09-20: в `.claude/settings.json` не провязан ни в одном из 10 вызовов.\n  Возврат: `git mv .claude/backup/hooks/rag-freshness.sh .claude/hooks/`.\n' >> .claude/backup/README.md
```

Правка `docfresh.py`: `TRUTH_EXCLUDE` становится парой, с доводом рядом — одной строкой, в стиле соседних комментариев файла:

```python
# Предмет docfresh — ЖИВОЕ утверждение о дереве. Архив живым не является by construction:
# его текст называет координаты, верные на момент снятия.
TRUTH_EXCLUDE = (":(exclude).claude/hooks/", ":(exclude).claude/backup/")
```

и раскрыть пару во **всех пяти** употреблениях, а не только на `:834`:

| строка | вид | как раскрыть |
|---|---|---|
| `:834` | `"--", *specs, TRUTH_EXCLUDE` | `*TRUTH_EXCLUDE` |
| `:1138` | `*ENV_PATHSPECS, TRUTH_EXCLUDE` | `*TRUTH_EXCLUDE` |
| `:1252` | `*ENV_PATHSPECS, TRUTH_EXCLUDE` | `*TRUTH_EXCLUDE` |
| `:1412` | `excl += [..., TRUTH_EXCLUDE]` | `excl += [..., *TRUTH_EXCLUDE]` — иначе кортеж ляжет внутрь списка и сломает git-вызов |
| `:2002` | `coord, *ENV_PATHSPECS, TRUTH_EXCLUDE` | `*TRUTH_EXCLUDE` |

Проверка: `grep -c 'TRUTH_EXCLUDE' docfresh.py` → 6 (одно определение + пять раскрытых).

- [ ] **Step 5: Доказать и закоммитить**

```bash
ls .claude/rules/*.md | wc -l                                  # обязан быть 17
ls .claude/backup/*.md | wc -l                                 # обязан быть 14 (13 + README)
ls -d .claude/skills/rule-* | wc -l                            # обязан быть 17
python3 -c "
import glob;print('корпус:',sum(len(open(f,encoding='utf-8').read()) for f in glob.glob('.claude/rules/*.md')))"
python3 -c "
import json
ex=json.load(open('.claude/settings.json',encoding='utf-8'))['claudeMdExcludes']
assert '**/.claude/backup/**' in ex and '**/.claude/rules/**' in ex; print('OK claudeMdExcludes')"
grep -c 'exclude).claude/backup/' .claude/hooks/docfresh/docfresh.py   # обязан быть 1
python3 -c "import ast;ast.parse(open('.claude/hooks/docfresh/docfresh.py',encoding='utf-8').read());print('OK docfresh парсится')"
bash .claude/hooks/hooks-wired.sh; echo "hooks-wired: $?"
scripts/rules-gate/run-all.sh; echo "rules-gate: $?"
scripts/skills-gate/run-all.sh; echo "skills-gate: $? (2 = известный VOID 06-docs-layout, краснота базы)"
git add -A .claude .gitignore tmp/rules-compression/
git commit -m "refactor(rules): 15 процессных файлов и сирота-хук в .claude/backup

Решение владельца 2026-09-20: в .claude остаётся только то, что используется при написании
кода, тестировании и доставке. Снято 80 ссылок skills: и 50 inline-ссылок диспетчера, 13 строк MANIFEST, 13 симлинков.
49 норм класса A, не держащихся гейтом, заготовлены к переселению в 00-kacho-core.
Три механизма адреса: claudeMdExcludes, TRUTH_EXCLUDE в docfresh, снятие непровязанного хука."
```

Ожидается: правил **17**, архива 14, симлинков 17, корпус ≈ 390 677, `OK` трижды, `rules-gate: 0`. Если `rules-gate` покраснеет — не коммить, вернуть находку в отчёт.

---

### Task 3: Frontmatter в 17 оставшихся файлов правил

**Files:**
- Modify: 17 `.claude/rules/*.md` — три строки в начало
- Create: `scripts/rules-gate/check-08-rule-frontmatter.sh`, `scripts/rules-gate/inject-08-rule-frontmatter.sh`
- Test: `scripts/rules-gate/run-all.sh`

**Interfaces:**
- Produces: каждый файл правила начинается с `---\nname: rule-<имя>\ndescription: "<фраза>"\n---`; `check-08` судит это в обе стороны

- [ ] **Step 1: Написать падающий гейт**

```bash
cat > scripts/rules-gate/check-08-rule-frontmatter.sh <<'ZZ'
#!/usr/bin/env bash
# check-08 — КАЖДЫЙ ФАЙЛ ПРАВИЛ НЕСЁТ FRONTMATTER, ИМЯ В НЁМ СХОДИТСЯ С ИМЕНЕМ ФАЙЛА.
# Предмет: скил `rule-<имя>` — симлинк на файл правила, и харнесс регистрирует скил по
# frontmatter цели. Файл без frontmatter = правило, которое не доходит до исполнителя:
# автозагрузка снята claudeMdExcludes. Вердикт — в КОДЕ ВЫХОДА.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
rc=0
for f in .claude/rules/*.md; do
  base="$(basename "$f" .md)"
  if [ "$(head -1 "$f")" != '---' ]; then
    printf 'КРАСНОЕ %s — нет frontmatter\n' "$f"; rc=1; continue
  fi
  sed -n '2,6p' "$f" | grep -qxF "name: rule-${base}" || { printf 'КРАСНОЕ %s — нет строки «name: rule-%s»\n' "$f" "$base"; rc=1; continue; }
  sed -n '2,6p' "$f" | grep -q '^description: .' || { printf 'КРАСНОЕ %s — description пуст\n' "$f"; rc=1; }
done
n=$(ls .claude/rules/*.md | wc -l)
printf 'осмотрено файлов правил: %s\n' "$n"
[ "$n" -ge 17 ] || { printf 'КРАСНОЕ — файлов правил меньше 17, обход усечён\n'; rc=1; }
exit "$rc"
ZZ
chmod +x scripts/rules-gate/check-08-rule-frontmatter.sh
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "код выхода: $?"
```

Ожидается: 17 строк `КРАСНОЕ … нет frontmatter`, `осмотрено файлов правил: 17`, `код выхода: 1`.

- [ ] **Step 2: Внести frontmatter**

```bash
python3 - <<'ZZ'
import glob,os,re
for f in sorted(glob.glob('.claude/rules/*.md')):
    base=os.path.basename(f)[:-3]
    t=open(f,encoding='utf-8').read()
    if t.startswith('---\n'): continue
    m=re.search(r'(?m)^#\s+(.+)$', t)
    desc=(m.group(1) if m else base).strip().replace('"','')
    if len(desc)>150: desc=desc[:147].rstrip()+'…'
    fm='---\nname: rule-'+base+'\ndescription: "'+desc+'"\n---\n\n'
    open(f,'w',encoding='utf-8').write(fm+t)
    print(base+': +'+str(len(fm))+' симв')
ZZ
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
```

Ожидается: 17 строк `+NNN симв`, `check-08: 0`.

- [ ] **Step 3: Инъекционное доказательство на три оси**

```bash
cat > scripts/rules-gate/inject-08-rule-frontmatter.sh <<'ZZ'
#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-08: гейт СПОСОБЕН дать красное на каждой из трёх осей.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/check-08-rule-frontmatter.sh
T=.claude/rules/00-kacho-core.md
cp "$T" /tmp/check08.orig
trap 'cp /tmp/check08.orig "$T"' EXIT
fail=0
probe() { if "$G" 2>&1 | grep -q "$2"; then printf 'ось %s: красное — OK\n' "$1"
          else printf 'ось %s: МОЛЧИТ\n' "$1"; fail=1; fi; }
sed -i '1,4d' "$T";                    probe A 'нет frontmatter'
cp /tmp/check08.orig "$T"
sed -i '2s/.*/name: rule-wrong/' "$T"; probe B 'нет строки'
cp /tmp/check08.orig "$T"
sed -i '3s/.*/description:/' "$T";     probe C 'description пуст'
cp /tmp/check08.orig "$T"
"$G" >/dev/null 2>&1 && printf 'ось Z: на целом дереве зелено — OK\n' || { printf 'ось Z: КРАСНОЕ — гейт шумит\n'; fail=1; }
exit "$fail"
ZZ
chmod +x scripts/rules-gate/inject-08-rule-frontmatter.sh
scripts/rules-gate/inject-08-rule-frontmatter.sh; echo "inject-08: $?"
```

Ожидается: четыре строки `OK`, `inject-08: 0`.

- [ ] **Step 4: Прогнать набор целиком**

```bash
scripts/rules-gate/run-all.sh; echo "rules-gate: $?"
python3 -c "
import glob;print('корпус:',sum(len(open(f,encoding='utf-8').read()) for f in glob.glob('.claude/rules/*.md')))"
```

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/ scripts/rules-gate/check-08-rule-frontmatter.sh scripts/rules-gate/inject-08-rule-frontmatter.sh
git commit -m "fix(rules): правило объявляет себя скилу frontmatter'ом — гейт в обе стороны"
```

---
### Task 4: `check-07` — разрешимость адреса нормы

Заводится ДО переписывания: перенос текста рвёт ссылки молча, а снятие 15 файлов в Task 2 уже оборвало всё, что на них ссылалось.

**Files:**
- Create: `scripts/rules-gate/address-refs.py`, `check-07-address-resolves.sh`, `inject-07-address-resolves.sh`

**Interfaces:**
- Produces: `address-refs.py --list` печатает `<источник>:<строка>\t<адрес>\tOK|ВИСИТ`; `check-07` красный при любом `ВИСИТ`, при неуникальном id и при пустом обходе. Task 5 потребляет `--list`.

- [ ] **Step 1: Написать разборщик**

```bash
cat > scripts/rules-gate/address-refs.py <<'ZZ'
#!/usr/bin/env python3
# Адреса норм: находит ссылки и проверяет, что цель существует.
#   <файл>.md#<id>          — новая форма, id стоит первым полем строки-нормы
#   <файл>.md §«Заголовок»  — прежняя, цель — заголовок раздела
#   <файл>.md §N            — прежняя, цель — заголовок, начинающийся с «N.»
# Области: .claude/agents/**, .claude/rules/**, CLAUDE.md, ../kacho/internal/repohygiene/**.
# Ссылки внутри ``` ограждений игнорируются: там примеры, а не адреса.
import sys, re, glob, os, argparse

RULES = '.claude/rules'
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
    for f in sorted(glob.glob(RULES + '/*.md')):
        b = os.path.basename(f); heads[b], ids[b] = [], []
        for line in open(f, encoding='utf-8'):
            if line.startswith('#'): heads[b].append(line.lstrip('#').strip())
            m = NORM_ROW.match(line)
            if m: ids[b].append(m.group(1))
    return heads, ids

def sources():
    pats = ['.claude/agents/*.md', RULES + '/*.md', 'CLAUDE.md',
            '../kacho/internal/repohygiene/*.go', '../kacho/internal/repohygiene/**/*.go']
    seen = []
    for p in pats: seen += [x for x in glob.glob(p, recursive=True) if os.path.isfile(x)]
    return sorted(set(seen))

def nws(s): return re.sub(r'\s+', ' ', s).strip().lower()

def check():
    heads, ids = corpus(); rows = []; dangling = 0
    for src in sources():
        raw = open(src, encoding='utf-8', errors='replace').read()
        text = strip_fences(raw)
        for rx, kind in ((REF_ID, 'id'), (REF_NAMED, 'named'), (REF_NUM, 'num')):
            for m in rx.finditer(text):
                f, tgt = m.group(1), m.group(2)
                line = raw[:m.start()].count('\n') + 1
                ok = False
                if f in heads:
                    if kind == 'id': ok = tgt in ids[f]
                    elif kind == 'named': ok = any(nws(tgt) in nws(h) for h in heads[f])
                    else: ok = any(re.match(r'^' + re.escape(tgt) + r'[.\s]', h) for h in heads[f])
                rows.append((src, line, f, kind, tgt, ok))
                if not ok: dangling += 1
    dup = []
    for f, lst in ids.items():
        seen = set()
        for i in lst:
            if i in seen: dup.append(f + '#' + i)
            seen.add(i)
    allids = [i for l in ids.values() for i in l]
    cross = [i for i in set(allids) if allids.count(i) > 1]
    return rows, dangling, dup, cross

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--list', action='store_true')
    a = ap.parse_args()
    rows, dangling, dup, cross = check()
    if a.list:
        for src, line, f, kind, tgt, ok in rows:
            addr = f + '#' + tgt if kind == 'id' else f + ' §' + tgt
            print(src + ':' + str(line) + '\t' + addr + '\t' + ('OK' if ok else 'ВИСИТ'))
    print('осмотрено источников: %d; адресов: %d; ВИСИТ: %d' % (len(sources()), len(rows), dangling))
    print('неуникальных id внутри файла: %d; id в двух файлах: %d' % (len(dup), len(cross)))
    for x in dup[:20]: print('  дубль id:', x)
    for x in cross[:20]: print('  id в двух файлах:', x)
    if not rows:
        print('КРАСНОЕ — адресов не найдено ни одного, обход пуст, вердикт беспредметен'); return 1
    return 1 if (dangling or dup or cross) else 0

if __name__ == '__main__': sys.exit(main())
ZZ
cat > scripts/rules-gate/check-07-address-resolves.sh <<'ZZ'
#!/usr/bin/env bash
# check-07 — АДРЕС НОРМЫ РЕЗОЛВИТСЯ, id УНИКАЛЕН.
# Область шире, чем у skills-gate/check-01: агенты, правила, CLAUDE.md и гейты продукта.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 scripts/rules-gate/address-refs.py
ZZ
chmod +x scripts/rules-gate/address-refs.py scripts/rules-gate/check-07-address-resolves.sh
scripts/rules-gate/check-07-address-resolves.sh; echo "код выхода: $?"
```

Ожидается: `ВИСИТ` больше нуля — Task 2 сняла 15 файлов, и всё, что на них ссылалось, теперь висит. `код выхода: 1`. Ноль означал бы, что разборщик не видит адресов — тогда чинить его, а не корпус.

- [ ] **Step 2: Инъекционное доказательство**

```bash
cat > scripts/rules-gate/inject-07-address-resolves.sh <<'ZZ'
#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-07: висячий заголовок, висячий id, дубль id.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/address-refs.py
T=.claude/rules/testing-load.md
cp "$T" /tmp/check07.orig
trap 'cp /tmp/check07.orig "$T"' EXIT
fail=0
probe() { if python3 "$G" 2>&1 | grep -qE "$2"; then printf 'ось %s: красное — OK\n' "$1"
          else printf 'ось %s: МОЛЧИТ\n' "$1"; fail=1; fi; }
printf '\ntesting-load.md §«Раздела с таким именем нет нигде»\n' >> "$T"; probe A 'ВИСИТ: [1-9]'
cp /tmp/check07.orig "$T"
printf '\ntesting-load.md#no-such-id-exists\n' >> "$T";                   probe B 'ВИСИТ: [1-9]'
cp /tmp/check07.orig "$T"
printf '\ndup-id-probe · и · ЗАВЕСТИ x · red: п\ndup-id-probe · и · ЗАВЕСТИ x · red: п\n' >> "$T"
probe C 'дубль id'
exit "$fail"
ZZ
chmod +x scripts/rules-gate/inject-07-address-resolves.sh
scripts/rules-gate/inject-07-address-resolves.sh; echo "inject-07: $?"
```

Ожидается: три `OK`, `inject-07: 0`.

- [ ] **Step 3: Снять перепись висячих адресов для Task 5**

```bash
python3 scripts/rules-gate/address-refs.py --list | awk -F'\t' '$3=="ВИСИТ"' > tmp/rules-compression/dangling-after-task2.txt
wc -l < tmp/rules-compression/dangling-after-task2.txt
awk -F'\t' '{split($2,a," ");split(a[1],b,"#");print b[1]}' tmp/rules-compression/dangling-after-task2.txt | sort | uniq -c | sort -rn | head -20
```

- [ ] **Step 4: Прогнать набор**

```bash
scripts/rules-gate/run-all.sh; echo "rules-gate: $? (check-07 красный ожидаем до Task 5)"
```

- [ ] **Step 5: Коммит**

```bash
git add scripts/rules-gate/ tmp/rules-compression/dangling-after-task2.txt
git commit -m "feat(rules-gate): адрес нормы резолвится, id уникален — гейт с доказательством на три оси"
```

---

### Task 5: Починить висячие адреса

**Files:**
- Modify: `.claude/rules/*.md`, `.claude/agents/*.md`, `CLAUDE.md` — только координаты в ссылках
- Modify: `../kacho/internal/repohygiene/{contractadvice.go,contractadvice_injection_test.go,gatecarrierremoval_injection_test.go,probewriteslivetree_test.go}`

**Interfaces:**
- Consumes: `tmp/rules-compression/dangling-after-task2.txt` (Task 4)
- Produces: `check-07` зелёный; дальше все задачи держат его зелёным

- [ ] **Step 1: Разобрать перепись по родам**

```bash
cut -f2 tmp/rules-compression/dangling-after-task2.txt | sed 's/ §.*//;s/#.*//' | sort | uniq -c | sort -rn
```

Три рода и что с каждым делать:
1. **Ссылка на уехавший файл** — цель в `.claude/backup/`. Если утверждение, опирающееся на неё, всё ещё нужно — переадресовать на `#<id>` нормы, которая осталась в корпусе (искать id в описи по предмету). Если утверждение уехало вместе с предметом — снять ссылку **вместе с утверждением**, а не оставить висеть.
2. **Ссылка на заголовок, который схлопнется** в Task 8–10 — переадресовать на `#<id>` заранее.
3. **Ссылка была неверной до начала работы** — 4 координаты в `internal/repohygiene` на `multi-agent-flow.md §13` / `§«НЕПРИКОСНОВЕННОСТЬ ЧУЖОГО СОСТОЯНИЯ»`: раздел жил в `multi-agent-flow-shared-tree.md:273`, а тот теперь в `.claude/backup/`. Норма про неприкосновенность чужого дерева — среди 49 переселённых в `00-kacho-core.md`, значит адрес становится `00-kacho-core.md#<id>`.

```bash
grep -rn 'multi-agent-flow' ../kacho/internal/repohygiene/*.go | head -8
grep -n 'НЕПРИКОСНОВЕННОСТЬ\|silent-corruption\|s-13' tmp/rules-compression/relocated-to-core.txt
```

- [ ] **Step 2: Починить каждый адрес**

Правится **цель**, а не признак: ссылка обязана указывать в существующий адрес либо исчезнуть вместе с утверждением. Работать по переписи сверху вниз, ни одной строки не пропуская.

- [ ] **Step 3: Доказать зелёное**

```bash
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
python3 scripts/rules-gate/address-refs.py --list | awk -F'\t' '$3=="ВИСИТ"' | wc -l   # обязан быть 0
scripts/rules-gate/run-all.sh; echo "rules-gate: $?"
(cd ../kacho && go build ./... && go test ./internal/repohygiene/ -run 'TestContractAdvice|TestGateCarrierRemoval|TestProbeWritesLiveTree' -count=1) 2>&1 | tail -4
```

Ожидается: `check-07: 0`, висячих `0`, `rules-gate: 0`, Go-тесты зелёные (правились только комментарии).

- [ ] **Step 4: Записать, сколько починено**

```bash
printf 'висячих было: %s, стало: %s\n' "$(wc -l < tmp/rules-compression/dangling-after-task2.txt)" "$(python3 scripts/rules-gate/address-refs.py --list | awk -F'\t' '$3=="ВИСИТ"' | wc -l)"
```

- [ ] **Step 5: Два коммита — два репозитория**

```bash
git add .claude CLAUDE.md && git commit -m "fix(rules): висячие адреса приведены к дереву после снятия легаси — check-07 зелёный"
(cd ../kacho && git add internal/repohygiene/ && git commit -m "fix(repohygiene): координата правила в комментарии гейта указывает в существующий адрес")
```

---

### Task 6: Два прибора — объём/форма корпуса и отбор норм из описи

**Files:**
- Create: `scripts/rules-gate/measure.sh`, `scripts/rules-gate/rows-from-inventory.py`

**Interfaces:**
- Produces: `measure.sh` без аргументов — корпус и разбивка; `measure.sh <файл>` — один файл; `measure.sh --form` — доля строк-норм, строки без `red:`, число `ЗАВЕСТИ`, вхождения слова «держится». Код выхода всегда 0: прибор, не гейт.
- Produces: `rows-from-inventory.py <файл.md>…` — строки-нормы в `tmp/rules-compression/rows-<файл>.txt` плюс сводка; `--verify` сверяет, что все id классов A и B есть в корпусе, код 1 при потере. Потребляется задачами 8–11.

- [ ] **Step 1: Прибор объёма и формы**

```bash
cat > scripts/rules-gate/measure.sh <<'ZZ'
#!/usr/bin/env bash
# Прибор объёма и формы корпуса. НЕ гейт: код выхода всегда 0, вердикт — у check-06.
# Символы, не байты: кириллица в UTF-8 вдвое тяжелее, и `wc -c` дал бы вдвое больше.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
case "${1:-}" in
  --form)
    printf 'строк-норм: %s\n' "$(grep -h ' \xc2\xb7 ' .claude/rules/*.md | wc -l)"
    printf 'без поля red: %s (обязан быть 0)\n' "$(grep -h ' \xc2\xb7 ' .claude/rules/*.md | grep -vc 'red:' || true)"
    printf 'ЗАВЕСТИ, различных: %s\n' "$(grep -ho 'ЗАВЕСТИ [A-Za-z0-9_]*' .claude/rules/*.md | sort -u | wc -l)"
    printf 'слово «держится»: %s (обязан быть 0)\n' "$(grep -hc 'держится' .claude/rules/*.md | awk '{s+=$1} END{print s+0}')"
    ;;
  '')
    python3 -c "
import glob,os
rows=[(len(open(f,encoding='utf-8').read()),os.path.basename(f)) for f in sorted(glob.glob('.claude/rules/*.md'))]
for n,b in sorted(rows,reverse=True): print('%8d  %s'%(n,b))
t=sum(n for n,_ in rows)
print('%8d  ИТОГО, потолок 200000, запас %d'%(t,200000-t))"
    ;;
  *) python3 -c "import sys;print(len(open('.claude/rules/'+sys.argv[1],encoding='utf-8').read()))" "$1" ;;
esac
ZZ
chmod +x scripts/rules-gate/measure.sh
scripts/rules-gate/measure.sh | tail -1
scripts/rules-gate/measure.sh --form
```

Ожидается: итог ≈ **390 677**; `строк-норм: **89**` (столько строк с разделителем ` · ` уже есть в прозе 17 файлов — прибор их посчитает нормами, это ожидаемо), `слово «держится»: **69**`. До переписывания так и должно быть.

- [ ] **Step 2: Прибор отбора норм**

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
    if not fm or fm == DASH: return None
    p = [x.strip(' `') for x in re.split(r'\s*\|\s*', fm) if x.strip(' `')]
    if len(p) >= 4: imp, hold, red = p[1], p[2], ' | '.join(p[3:])
    elif len(p) == 3: imp, hold, red = p[1], p[2], DASH
    elif len(p) == 2: imp, hold, red = p[1], GATELESS, DASH
    else: imp, hold, red = p[0], GATELESS, DASH
    return n['id'] + DOT + imp + DOT + hold + DOT + 'red: ' + red


def main(argv):
    verify = '--verify' in argv
    files = [a for a in argv if a != '--verify']
    if not files: print('нужен хотя бы один файл правил'); return 1
    inv = json.load(open(INV, encoding='utf-8'))
    OUT.mkdir(parents=True, exist_ok=True)
    rc = 0
    for f in files:
        ab = [n for n in inv if n['src'] == f and n['k'] in ('A', 'B')]
        cd = [n for n in inv if n['src'] == f and n['k'] in ('C', 'D')]
        if not ab:
            print(f + ': КРАСНОЕ — в описи нет ни одной нормы A/B, отбор пуст'); rc = 1; continue
        if verify:
            have = set()
            for line in open('.claude/rules/' + f, encoding='utf-8'):
                if DOT in line: have.add(line.split(DOT)[0].strip())
            want = {n['id'] for n in ab}
            miss = sorted(want - have)
            size = len(open('.claude/rules/' + f, encoding='utf-8').read())
            print('%s: ожидается %d, найдено %d, ПОТЕРЯНО %d, объём %d' % (f, len(want), len(want & have), len(miss), size))
            if miss: print('   потеряны: ' + ', '.join(miss[:20])); rc = 1
            continue
        rows = [(n['id'], row(n)) for n in ab]
        hand = [i for i, r in rows if not r]
        dst = OUT / ('rows-' + f + '.txt')
        with open(dst, 'w', encoding='utf-8') as out:
            for i, r in rows:
                out.write((r or (i + DOT + HAND + DOT + GATELESS + DOT + 'red: ' + DASH)) + '\n')
        chars = sum(len(r) + 1 for _, r in rows if r) + len(hand) * 160
        print('%s: строк %d, руками %d, в архив %d, символов ~%d -> %s' % (f, len(rows), len(hand), len(cd), chars, dst))
        if hand: print('   руками: ' + ', '.join(hand))
    return rc


if __name__ == '__main__': sys.exit(main(sys.argv[1:]))
ZZ
chmod +x scripts/rules-gate/rows-from-inventory.py
python3 scripts/rules-gate/rows-from-inventory.py testing-load.md
python3 scripts/rules-gate/rows-from-inventory.py --verify testing-load.md; echo "verify до переписывания: $? (ожидается 1)"
```

Ожидается: `testing-load.md: строк 7, руками 0, в архив 3, символов ~1531`, `verify … 1`.

- [ ] **Step 3: Точка отсчёта**

```bash
scripts/rules-gate/measure.sh > tmp/rules-compression/measure-before.txt
scripts/rules-gate/measure.sh --form >> tmp/rules-compression/measure-before.txt
cat tmp/rules-compression/measure-before.txt
```

- [ ] **Step 4: Отобрать строки для всех 15 файлов сразу**

```bash
python3 scripts/rules-gate/rows-from-inventory.py $(cd .claude/rules && ls *.md | tr '\n' ' ')
ls tmp/rules-compression/rows-*.txt | wc -l   # обязан быть 17
```

- [ ] **Step 5: Коммит**

```bash
git add scripts/rules-gate/measure.sh scripts/rules-gate/rows-from-inventory.py tmp/rules-compression/
git commit -m "feat(rules-gate): два прибора — объём и форма корпуса, отбор норм из описи"
```

---

### Task 7: Архив классов C и D базовых файлов, 17 якорей

**Files:**
- Create: `.claude/backup/<17 базовых>.md`
- Modify: 17 `.claude/rules/*.md` — по строке-якорю

**Interfaces:**
- Produces: у каждого базового файла есть архивный близнец и строка `archive · доводы, замеры и снятые редакции — .claude/backup/<файл>.md`

- [ ] **Step 1: Завести архивные близнецы**

```bash
for f in .claude/rules/*.md; do
  b=$(basename "$f")
  [ -f ".claude/backup/$b" ] && { echo "уже есть: $b"; continue; }
  printf '# Архив: %s\n\nСнято 2026-09-20. Норма живёт в `.claude/rules/%s`.\nЗдесь: классы C (процесс) и D (замеры, доводы, отменённое, пересказы).\n' "$b" "$b" > ".claude/backup/$b"
done
ls .claude/backup/*.md | wc -l   # обязан быть 31 (13 легаси + 17 базовых + README)
```

- [ ] **Step 2: Вписать якорь в каждый базовый файл**

```bash
python3 - <<'ZZ'
import glob,os
for f in sorted(glob.glob('.claude/rules/*.md')):
    b=os.path.basename(f)
    line='archive · доводы, замеры и снятые редакции — .claude/backup/'+b+'\n'
    t=open(f,encoding='utf-8').read()
    if line in t: continue
    i=t.index('\n---\n',4)+5
    open(f,'w',encoding='utf-8').write(t[:i]+'\n'+line+t[i:])
    print(b,'+',len(line))
ZZ
```

- [ ] **Step 3: Прогнать гейты**

```bash
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "rules-gate: $?"
scripts/rules-gate/measure.sh | tail -1
```

Ожидается: все гейты 0. Объём чуть вырос — якоря; переписывание идёт дальше.

- [ ] **Step 4: Коммит**

```bash
git add .claude/backup/ .claude/rules/
git commit -m "feat(rules): архивные близнецы 15 базовых файлов и якоря"
```

---
### Task 8: Переписать партию 1 — `testing`, `api-conventions`, `data-integrity`, `00-kacho-core`, `security-hardening`

Всего 151484 → **65993** символов (÷2.3), норм A/B 262/62, без готовой строки 10.

**Особое в этой партии:** в `00-kacho-core.md` дописывается раздел `## Доставка и общее дерево` — 49 норм класса A, переселённых из снятых файлов (`tmp/rules-compression/relocated-to-core.txt`, 7 279 символов). Без них эти нормы теряют единственного сторожа: гейта у них нет.

**Files:**
- Modify: `.claude/rules/testing.md` — 36040 → **14937** симв, норм 60/17, руками 0
- Modify: `.claude/backup/testing.md` — принимает 23 записей классов C и D
- Modify: `.claude/rules/api-conventions.md` — 37337 → **14552** симв, норм 63/16, руками 7
- Modify: `.claude/backup/api-conventions.md` — принимает 5 записей классов C и D
- Modify: `.claude/rules/data-integrity.md` — 33060 → **14171** симв, норм 72/6, руками 2
- Modify: `.claude/backup/data-integrity.md` — принимает 26 записей классов C и D
- Modify: `.claude/rules/00-kacho-core.md` — 22508 → **12480** симв, норм 28/8, руками 1
- Modify: `.claude/backup/00-kacho-core.md` — принимает 30 записей классов C и D
- Modify: `.claude/rules/security-hardening.md` — 22539 → **9853** симв, норм 39/15, руками 0
- Modify: `.claude/backup/security-hardening.md` — принимает 15 записей классов C и D
- Test: `scripts/rules-gate/measure.sh`, `rows-from-inventory.py --verify`, `run-all.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/rows-<файл>.md.txt` (Task 6) и `relocated-to-core.txt` (Task 2)
- Produces: 324 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Точка отсчёта**

```bash
for f in testing.md api-conventions.md data-integrity.md 00-kacho-core.md security-hardening.md; do printf '%-28s %s\n' "$f" "$(scripts/rules-gate/measure.sh $f)"; done
```

Ожидается: `testing.md` 36040, `api-conventions.md` 37337, `data-integrity.md` 33060, `00-kacho-core.md` 22508, `security-hardening.md` 22539.

- [ ] **Step 2: Переписать каждый файл партии**

Сохранить: frontmatter (Task 3), строку-якорь (Task 7) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.md.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы. **Два исключения, обязательных:**
1. запись несёт непустой `gate` — остаётся строкой-ссылкой на гейт (таких 93 по корпусу);
2. абзац в повелительной форме («обязан», «запрещено», «только», «не …ся») — остаётся строкой-нормой, даже если класс D или C.
После переноса прогнать: `grep -nE 'обязан|запрещ|только |не заводится' .claude/backup/<файл>.md` — каждое попадание разобрать и решить, не норма ли это.

Строки с пометкой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст, свести
к четырём полям. Ориентир 172 символа; строка, из которой нельзя вывести вердикт, не годится, даже
если короткая.

- [ ] **Step 3: Прогнать замер и гейты**

```bash
for f in testing.md api-conventions.md data-integrity.md 00-kacho-core.md security-hardening.md; do printf '%-28s %s\n' "$f" "$(scripts/rules-gate/measure.sh $f)"; done
scripts/rules-gate/measure.sh --form
python3 scripts/rules-gate/rows-from-inventory.py --verify testing.md api-conventions.md data-integrity.md 00-kacho-core.md security-hardening.md
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
```

Ожидается: каждый файл в бюджете (`testing` ≤ 14937, `api-conventions` ≤ 14552, `data-integrity` ≤ 14171, `00-kacho-core` ≤ 12480, `security-hardening` ≤ 9853),
`ПОТЕРЯНО 0` в каждой строке сверки, `без поля red: 0`, все гейты 0.

- [ ] **Step 4: Проверить, что «держится» не осталось**

```bash
grep -n 'держится' .claude/rules/testing.md .claude/rules/api-conventions.md .claude/rules/data-integrity.md .claude/rules/00-kacho-core.md .claude/rules/security-hardening.md || echo "слова «держится» в партии нет — верно"
```

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/testing.md .claude/rules/api-conventions.md .claude/rules/data-integrity.md .claude/rules/00-kacho-core.md .claude/rules/security-hardening.md .claude/backup/testing.md .claude/backup/api-conventions.md .claude/backup/data-integrity.md .claude/backup/00-kacho-core.md .claude/backup/security-hardening.md
git commit -m "refactor(rules): партия 1 сведена к строкам-нормам, доводы в архив"
```

---

### Task 9: Переписать партию 2 — `e2e-flow`, `testing-verdict`, `security`, `ui`, `subscription`

Всего 122435 → **42607** символов (÷2.9), норм A/B 135/103, без готовой строки 3.

**Files:**
- Modify: `.claude/rules/e2e-flow.md` — 24158 → **9828** симв, норм 22/36, руками 0
- Modify: `.claude/backup/e2e-flow.md` — принимает 50 записей классов C и D
- Modify: `.claude/rules/testing-verdict.md` — 31342 → **9065** симв, норм 8/39, руками 0
- Modify: `.claude/backup/testing-verdict.md` — принимает 10 записей классов C и D
- Modify: `.claude/rules/security.md` — 23777 → **8683** симв, норм 35/7, руками 0
- Modify: `.claude/backup/security.md` — принимает 21 записей классов C и D
- Modify: `.claude/rules/ui.md` — 30061 → **7555** симв, норм 33/12, руками 0
- Modify: `.claude/backup/ui.md` — принимает 25 записей классов C и D
- Modify: `.claude/rules/subscription.md` — 13097 → **7476** симв, норм 37/9, руками 3
- Modify: `.claude/backup/subscription.md` — принимает 6 записей классов C и D
- Test: `scripts/rules-gate/measure.sh`, `rows-from-inventory.py --verify`, `run-all.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/rows-<файл>.md.txt` (Task 6)
- Produces: 238 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Точка отсчёта**

```bash
for f in e2e-flow.md testing-verdict.md security.md ui.md subscription.md; do printf '%-28s %s\n' "$f" "$(scripts/rules-gate/measure.sh $f)"; done
```

Ожидается: `e2e-flow.md` 24158, `testing-verdict.md` 31342, `security.md` 23777, `ui.md` 30061, `subscription.md` 13097.

- [ ] **Step 2: Переписать каждый файл партии**

Сохранить: frontmatter (Task 3), строку-якорь (Task 7) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.md.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы. **Два исключения, обязательных:**
1. запись несёт непустой `gate` — остаётся строкой-ссылкой на гейт (таких 93 по корпусу);
2. абзац в повелительной форме («обязан», «запрещено», «только», «не …ся») — остаётся строкой-нормой, даже если класс D или C.
После переноса прогнать: `grep -nE 'обязан|запрещ|только |не заводится' .claude/backup/<файл>.md` — каждое попадание разобрать и решить, не норма ли это.

Строки с пометкой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст, свести
к четырём полям. Ориентир 172 символа; строка, из которой нельзя вывести вердикт, не годится, даже
если короткая.

- [ ] **Step 3: Прогнать замер и гейты**

```bash
for f in e2e-flow.md testing-verdict.md security.md ui.md subscription.md; do printf '%-28s %s\n' "$f" "$(scripts/rules-gate/measure.sh $f)"; done
scripts/rules-gate/measure.sh --form
python3 scripts/rules-gate/rows-from-inventory.py --verify e2e-flow.md testing-verdict.md security.md ui.md subscription.md
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
```

Ожидается: каждый файл в бюджете (`e2e-flow` ≤ 9828, `testing-verdict` ≤ 9065, `security` ≤ 8683, `ui` ≤ 7555, `subscription` ≤ 7476),
`ПОТЕРЯНО 0` в каждой строке сверки, `без поля red: 0`, все гейты 0.

- [ ] **Step 4: Проверить, что «держится» не осталось**

```bash
grep -n 'держится' .claude/rules/e2e-flow.md .claude/rules/testing-verdict.md .claude/rules/security.md .claude/rules/ui.md .claude/rules/subscription.md || echo "слова «держится» в партии нет — верно"
```

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/e2e-flow.md .claude/rules/testing-verdict.md .claude/rules/security.md .claude/rules/ui.md .claude/rules/subscription.md .claude/backup/e2e-flow.md .claude/backup/testing-verdict.md .claude/backup/security.md .claude/backup/ui.md .claude/backup/subscription.md
git commit -m "refactor(rules): партия 2 сведена к строкам-нормам, доводы в архив"
```

---

### Task 10: Переписать партию 3 — `polyrepo`, `architecture`, `testing-newman`, `testing-load`, `security-disclosure`

Всего 74194 → **14337** символов (÷5.2), норм A/B 62/22, без готовой строки 6.

**Files:**
- Modify: `.claude/rules/polyrepo.md` — 37860 → **4881** симв, норм 23/7, руками 6
- Modify: `.claude/backup/polyrepo.md` — принимает 23 записей классов C и D
- Modify: `.claude/rules/architecture.md` — 10205 → **3829** симв, норм 22/6, руками 0
- Modify: `.claude/backup/architecture.md` — принимает 4 записей классов C и D
- Modify: `.claude/rules/testing-newman.md` — 7631 → **3691** симв, норм 16/1, руками 0
- Modify: `.claude/backup/testing-newman.md` — принимает 4 записей классов C и D
- Modify: `.claude/rules/testing-load.md` — 6282 → **1531** симв, норм 1/6, руками 0
- Modify: `.claude/backup/testing-load.md` — принимает 3 записей классов C и D
- Modify: `.claude/rules/security-disclosure.md` — 12216 → **405** симв, норм 0/2, руками 0
- Modify: `.claude/backup/security-disclosure.md` — принимает 25 записей классов C и D
- Test: `scripts/rules-gate/measure.sh`, `rows-from-inventory.py --verify`, `run-all.sh`

**Interfaces:**
- Consumes: `tmp/rules-compression/rows-<файл>.md.txt` (Task 6)
- Produces: 84 строк-норм в форме `<id> · <императив> · <держатель> · red: <признак>`; классы C и D — в `.claude/backup/`

- [ ] **Step 1: Точка отсчёта**

```bash
for f in polyrepo.md architecture.md testing-newman.md testing-load.md security-disclosure.md; do printf '%-28s %s\n' "$f" "$(scripts/rules-gate/measure.sh $f)"; done
```

Ожидается: `polyrepo.md` 37860, `architecture.md` 10205, `testing-newman.md` 7631, `testing-load.md` 6282, `security-disclosure.md` 12216.

- [ ] **Step 2: Переписать каждый файл партии**

Сохранить: frontmatter (Task 3), строку-якорь (Task 7) и **только адресуемые заголовки** — их печатает
`python3 scripts/rules-gate/address-refs.py --list | grep '<файл>'`. Тело заменить строками из
`tmp/rules-compression/rows-<файл>.md.txt`, сгруппировав их под сохранёнными заголовками.
Классы C и D перенести в `.claude/backup/<файл>.md`, каждую запись — с id нормы. **Два исключения, обязательных:**
1. запись несёт непустой `gate` — остаётся строкой-ссылкой на гейт (таких 93 по корпусу);
2. абзац в повелительной форме («обязан», «запрещено», «только», «не …ся») — остаётся строкой-нормой, даже если класс D или C.
После переноса прогнать: `grep -nE 'обязан|запрещ|только |не заводится' .claude/backup/<файл>.md` — каждое попадание разобрать и решить, не норма ли это.

Строки с пометкой `ПИСАТЬ РУКАМИ` дописать по координате из описи: прочитать исходный текст, свести
к четырём полям. Ориентир 172 символа; строка, из которой нельзя вывести вердикт, не годится, даже
если короткая.

- [ ] **Step 3: Прогнать замер и гейты**

```bash
for f in polyrepo.md architecture.md testing-newman.md testing-load.md security-disclosure.md; do printf '%-28s %s\n' "$f" "$(scripts/rules-gate/measure.sh $f)"; done
scripts/rules-gate/measure.sh --form
python3 scripts/rules-gate/rows-from-inventory.py --verify polyrepo.md architecture.md testing-newman.md testing-load.md security-disclosure.md
scripts/rules-gate/check-07-address-resolves.sh; echo "check-07: $?"
scripts/rules-gate/check-08-rule-frontmatter.sh; echo "check-08: $?"
scripts/rules-gate/run-all.sh; echo "run-all: $?"
```

Ожидается: каждый файл в бюджете (`polyrepo` ≤ 4881, `architecture` ≤ 3829, `testing-newman` ≤ 3691, `testing-load` ≤ 1531, `security-disclosure` ≤ 405),
`ПОТЕРЯНО 0` в каждой строке сверки, `без поля red: 0`, все гейты 0.

- [ ] **Step 4: Проверить, что «держится» не осталось**

```bash
grep -n 'держится' .claude/rules/polyrepo.md .claude/rules/architecture.md .claude/rules/testing-newman.md .claude/rules/testing-load.md .claude/rules/security-disclosure.md || echo "слова «держится» в партии нет — верно"
```

- [ ] **Step 5: Коммит**

```bash
git add .claude/rules/polyrepo.md .claude/rules/architecture.md .claude/rules/testing-newman.md .claude/rules/testing-load.md .claude/rules/security-disclosure.md .claude/backup/polyrepo.md .claude/backup/architecture.md .claude/backup/testing-newman.md .claude/backup/testing-load.md .claude/backup/security-disclosure.md
git commit -m "refactor(rules): партия 3 сведена к строкам-нормам, доводы в архив"
```

---

### Task 11: `check-06` — потолок корпуса 200 000 символов

Заводится последним: гейт, красный в момент заведения, не судит, а шумит.

**Files:**
- Create: `scripts/rules-gate/check-06-corpus-ceiling.sh`, `corpus_ceiling.py`, `inject-06-corpus-ceiling.sh`
- Modify: `scripts/rules-gate/run-all.sh` — включить check-06, check-07, check-08 и их inject

**Interfaces:**
- Consumes: корпус после задач 8–10
- Produces: `check-06` красный при сумме > 200 000 и при усечённом обходе; `run-all.sh` гоняет восемь проверок вместо пяти

- [ ] **Step 1: Убедиться, что объём под потолком**

```bash
scripts/rules-gate/measure.sh | tail -1
scripts/rules-gate/measure.sh --form
python3 scripts/rules-gate/rows-from-inventory.py --verify $(cd .claude/rules && ls *.md | tr '\n' ' ') | grep -v 'ПОТЕРЯНО 0' || echo "потерь нет ни в одном файле"
```

Ожидается: итог ≈ **149 714**, запас ≈ 50 286; `без поля red: 0`; `слово «держится»: 0`; потерь нет. Если выше 200 000 — вернуться к партии, чей файл вышел за бюджет. Гейт не заводить.

- [ ] **Step 2: Написать гейт**

```bash
cat > scripts/rules-gate/corpus_ceiling.py <<'ZZ'
#!/usr/bin/env python3
import glob, sys
CAP = 200000
files = sorted(glob.glob('.claude/rules/*.md'))
if len(files) < 17:
    print('КРАСНОЕ — файлов правил %d, ожидалось не меньше 17: обход усечён, вердикт беспредметен' % len(files))
    sys.exit(1)
sizes = {f: len(open(f, encoding='utf-8').read()) for f in files}
tot = sum(sizes.values())
print('осмотрено файлов: %d; корпус: %d символов; потолок: %d; запас: %d' % (len(files), tot, CAP, CAP - tot))
if tot > CAP:
    print('КРАСНОЕ — корпус выше потолка на %d' % (tot - CAP))
    for f, n in sorted(sizes.items(), key=lambda kv: -kv[1])[:5]: print('   %8d  %s' % (n, f))
    sys.exit(1)
sys.exit(0)
ZZ
cat > scripts/rules-gate/check-06-corpus-ceiling.sh <<'ZZ'
#!/usr/bin/env bash
# check-06 — КОРПУС ПРАВИЛ НЕ ВЫШЕ 200 000 СИМВОЛОВ (решение владельца 2026-09-19).
# Символы, не байты: `wc -c` дал бы вдвое больше на кириллице и потолок не судил бы.
# Обход усечён -> красное: «ноль находок» обязано быть отличимо от «ноль прочитанного».
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 scripts/rules-gate/corpus_ceiling.py
ZZ
chmod +x scripts/rules-gate/check-06-corpus-ceiling.sh
scripts/rules-gate/check-06-corpus-ceiling.sh; echo "check-06: $?"
```

Ожидается: `осмотрено файлов: 17; корпус: ~133937; потолок: 200000; запас: ~66063`, `check-06: 0`.

- [ ] **Step 3: Инъекционное доказательство на две оси**

```bash
cat > scripts/rules-gate/inject-06-corpus-ceiling.sh <<'ZZ'
#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-06: перебор потолка и усечённый обход.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
G=scripts/rules-gate/check-06-corpus-ceiling.sh
T=.claude/rules/testing-load.md
mkdir -p /tmp/check06hide
cp "$T" /tmp/check06.orig
restore() { cp /tmp/check06.orig "$T" 2>/dev/null || true; mv /tmp/check06hide/*.md .claude/rules/ 2>/dev/null || true; }
trap restore EXIT
fail=0
python3 -c "open('$T','a',encoding='utf-8').write('x'*70000)"
"$G" 2>&1 | grep -q 'выше потолка' && echo 'ось A (перебор потолка): красное — OK' || { echo 'ось A: МОЛЧИТ'; fail=1; }
cp /tmp/check06.orig "$T"
mv .claude/rules/testing-load.md .claude/rules/testing-newman.md /tmp/check06hide/
"$G" 2>&1 | grep -q 'обход усечён' && echo 'ось B (усечённый обход): красное — OK' || { echo 'ось B: МОЛЧИТ'; fail=1; }
mv /tmp/check06hide/testing-load.md /tmp/check06hide/testing-newman.md .claude/rules/
"$G" >/dev/null 2>&1 && echo 'ось Z (целое дерево): зелено — OK' || { echo 'ось Z: КРАСНОЕ — гейт шумит'; fail=1; }
exit "$fail"
ZZ
chmod +x scripts/rules-gate/inject-06-corpus-ceiling.sh
scripts/rules-gate/inject-06-corpus-ceiling.sh; echo "inject-06: $?"
```

Ожидается: три `OK`, `inject-06: 0`.

- [ ] **Step 4: Включить три проверки в набор и прогнать всё**

```bash
grep -n 'check-0' scripts/rules-gate/run-all.sh
# дописать в перечень прогона: check-06, check-07, check-08 и inject-06, inject-07, inject-08
scripts/rules-gate/run-all.sh; echo "run-all: $?"
scripts/skills-gate/run-all.sh; echo "skills-gate: $? (2 = известный VOID 06-docs-layout)"
scripts/rules-gate/measure.sh | tail -1
scripts/rules-gate/measure.sh --form
```

Ожидается: `run-all: 0` на восьми проверках, корпус ≤ 200 000.

- [ ] **Step 5: Коммит**

```bash
git add scripts/rules-gate/
git commit -m "feat(rules-gate): потолок корпуса 200 000 символов держится гейтом, а не вниманием"
```

---

## Что остаётся после этого плана

- **Вторая волна: тела агентов.** Опись готова (458 разделов, R 302 · D 124 · W 15 · H 17). Пол класса R — **158 987** символов против 496 135 сейчас; цена запуска агента падает с медианы 146 117 до **36 838**. Все 16 проверенных снятий ниже этого пола скептики отклонили, поэтому 60 000 берётся только резкой по role-essential — решение принято держать пол.
- **46 гейтов на 239 норм класса A без механизма** — отдельная линия. Число различных `ЗАВЕСТИ` печатает `measure.sh --form`: это и есть названный числом долг.
- **Печать хуков** — 62 259 байт на коммит, вдвое больше августовской. В контекст хуки не грузятся, но их печать грузится. Отдельная работа, и она даст больше, чем любая редактура текста.
- **Находка вне области:** `scripts/rules-gate/*` и `scripts/skills-gate/*` шесть раз ссылаются на `.claude/rulebook/` — каталог эксперимента 09-08…09-13, которого в дереве нет.
- **PR, а не push:** `main` защищён (`enforce_admins: true`, `required_pull_request_reviews: true`, 9 обязательных проверок), и `multi-agent-flow-shared-tree.md §8а` запрещает прямой push без исключений. Ветка `rules/corpus-200k` уходит в PR.
