---
name: hardening-audit-loop
description: Многоагентный итеративный аудит-рефакторинг kacho-* до сходимости — find → adversarial-verify → TDD-fix → PR/CI/merge → re-check, повторять пока раунд не даст 0 подтверждённых находок. Применять на запрос «массированный/полный аудит», «доведи код до 100% чистого и безопасного», «пройди по безопасности/утечкам/структуре/читаемости», hardening-sweep, security-audit целого репо или всего полирепо. Кодифицирует 6 дименсий (security/leak/structure/readability/LEAN/concurrency), 9 инвариантов Kachō как определение «дефекта», refute-верификацию (отсекает false-positive и LOW), поведенческие regression-тесты. Оркеструется через Workflow (ultracode); есть готовый bundled-скрипт одного раунда. НЕ для точечного багфикса (это обычный TDD-флоу) и НЕ для feature-work (нужен APPROVED acceptance-док).
metadata:
  type: technique
---

# Skill: hardening-audit-loop — массированный аудит до сходимости

Выработан на реальном прогоне: **11 итераций, кривая `10→5→2→1→0`** подтверждённых
находок по 8 code-heavy репо. Нашёл+починил HIGH BOLA (cross-project disclosure),
cache-poisoning, existence-oracle'ы, класс «missing per-call deadline» во всех
peer-клиентах, doc-truthfulness-ловушки, чужой-облако имя, stdlib-vuln, O(N²)-кэш.
Это нормативный harness: аудируй ТАК; отклонение — осознанно.

Companion-конспект (прозой): `obsidian/kacho/KAC/audit-loop-prompt.md`.
Готовый один-раунд Workflow: [`references/audit-round.workflow.js`](references/audit-round.workflow.js).

## 0. Когда применять / когда НЕТ

**Применять:**
- «Сделай полный/массированный аудит-рефакторинг», «доведи до 100% чистого и
  безопасного», «пройди по безопасности/утечкам/структуре/читаемости».
- Периодический hardening-sweep репо или всего полирепо перед релизом.
- После крупного мёржа — проверить, не внесён ли класс дефектов из инвариантов ниже.

**НЕ применять:**
- Точечный известный багфикс → обычный TDD-флоу (RED→GREEN), не весь harness.
- Новая фича/RPC/ресурс → сначала APPROVED Given-When-Then (`acceptance-author` →
  `acceptance-reviewer`), это другой флоу (ban #1).
- Нужен < 1 раунда работы (один файл, одна строка) → просто почини, не разворачивай цикл.

**Требует ultracode** (Workflow-оркестрация). Если ultracode выключен — методологию
всё равно применяй, но фазы гоняй последовательными `Agent`-вызовами, а не Workflow.

## 1. Harness — петля до сходимости

```
┌─ round N ───────────────────────────────────────────────┐
│ Find     per-repo deep-finder × 6 дименсий (parallel)    │ → findings[]
│ dedup    fresh = findings \ seen   (по repo:file:summary) │
│ Verify   per-finding refuter (parallel, barrier)         │ → confirmed[]
│          keep real==true && severity ∉ {LOW,INVALID}     │
│ ── 0 confirmed?  → dry раунд → СХОДИМОСТЬ, стоп ──────────│
│ Fix      1 агент на репо, строгий TDD, push ветку        │ → branches[]
└──────────────────────────────────────────────────────────┘
   → PR → CI (green) → merge → seen ∪= newSeenKeys → round N+1
```

**Стоп-критерий**: один «сухой» раунд (0 confirmed после verify) ⇒ сходимость.
Финдеры каждый раунд свежие (без памяти) — поэтому `seen`-множество на оркестраторе
гасит повторы и заставляет цикл двигаться к хвосту.

**Критично для сходимости**: дедуп новых находок против **`seen`** (всё, что уже
видели), а НЕ против `confirmed`. Иначе verify-отклонённые находки всплывают каждый
раунд и петля не сходится.

**Fix-all-in-round (non-negotiable)**: все `confirmed` находки раунда чинятся **сразу
в этом же раунде** — Fix-фаза берёт ВСЁ подтверждённое (все репо, все дименсии, и LOW
когда включён LOW-toggle, §4). Никакого частичного фикса, никакого «follow-up-тикет /
out-of-scope / на потом» — отложить подтверждённый дефект = внести тех-долг (ban #11).
Единственная легитимная отсрочка — фикс, физически требующий другого репо
(proto/corelib): `action=skipped-needs-cross-repo`, и он берётся **следующим раундом**
по build-графу (`polyrepo.md`), а не откладывается бессрочно; in-repo-часть такого
фикса всё равно делается сразу. Стоп только по «сухому» раунду, а не «нашли, но часть
оставили».

## 2. Как запускать

Один раунд = один вызов bundled-Workflow; **внешнюю петлю ведёт main-loop** (ты),
потому что между раундами нужны PR / ожидание CI / merge и решение о сходимости.

**Шаг за шагом (main-loop):**

1. Инициализация: `seen = []`, `round = 1`, `confirmedAll = []`.
2. Запусти раунд:
   ```
   Workflow({ scriptPath: '<skill>/references/audit-round.workflow.js',
              args: { root: '<abs>/project', repos: [<code-heavy репо>], seen, round } })
   ```
   (single-repo standalone: `root: '.'`, `repos: ['.']`.)
3. Прочитай результат `{ round, dry, confirmed, branches, newSeenKeys }`.
   `seen = newSeenKeys`; `confirmedAll.push(...confirmed)`.
4. Если `dry === true` → **сходимость достигнута**, перейди к §5 (отчёт). Стоп.
5. Иначе для каждой `branches[i].pushed`: `gh pr create` → дождись CI зелёным
   (`gh run watch` / поллинг) → `gh pr merge --squash --delete-branch`.
   Флейки CI (rate-limit 429, proxy stream error, testcontainers pull-timeout) —
   `gh run rerun --failed`, это **не** находка.
6. `round++`, вернись к шагу 2.

**Репо-набор (code-heavy):** `kacho-corelib · iam · vpc · compute · geo · nlb ·
api-gateway · registry`. Deploy/ui/proto — по необходимости отдельно.

## 3. Девять инвариантов Kachō — определение «дефекта»

Финдер меряет код против них (источник истины — `.claude/rules/*`). Находка обязана
привязываться к одному из них + нести **конкретный failure-сценарий**:

1. **AuthN+AuthZ на КАЖДОМ RPC обоих листенеров** (public и :9091); «internal =
   trusted» — запрещённое допущение (`security.md`).
2. **Object-scoped authz** там, где метод оперирует конкретным объектом по
   caller-supplied id (BOLA / existence-oracle / cross-project disclosure — HIGH).
3. **Per-call deadline на КАЖДОМ внешнем вызове** — `context.WithTimeout`, не полагаться
   на inbound ctx; `retry.OnUnavailable` не ограничивает один зависший вызов
   (`architecture.md`). Все sibling-методы клиента — один configured-timeout.
4. **No leak**: pgx/SQL-текст в INTERNAL → фикс. opaque-текст; инфра-топология — только
   в `Internal*` (`security.md`).
5. **Doc-truthfulness**: комментарий обязан совпадать с кодом;
   misleading-security-comment = trap (`architecture.md`).
6. **Within-service инвариант — на DB-уровне** (FK/UNIQUE/EXCLUDE/CHECK/CAS/xmin/
   SKIP-LOCKED), не software TOCTOU (`data-integrity.md`).
7. **Ban #2** — ни одного упоминания чужих облаков в коде/доках/env/именах.
8. **Concurrency**: гонки, second-writer-wins, wg-drain, O(N²)/unbounded рост.
9. **LEAN**: dead/vestigial код/ветки/типы — удалять вместе с тестами (ban #11).

## 4. Три роли (дословные промты — в bundled-скрипте)

- **FINDER** (phase Find, per-repo): скептик-аудитор, 6 дименсий, **только HIGH/MEDIUM**,
  «не выдумывай nits/style-only», обязателен конкретный failure-сценарий + direction фикса.
  Читает узкие файлы + `obsidian/kacho/{resources,rpc,edges}/`, не 50KB README.
- **VERIFY** (phase Verify, per-finding): **refute-режим** — default `real=false`, если не
  подтвердил по коду; проверяет, нет ли защиты выше по стеку / by-design; правит severity.
  Фильтр оркестратора отбрасывает `LOW`/`INVALID` — **поэтому LOW by-design не чинятся**.
- **FIXER** (phase Fix, per-repo): **строгий TDD** — падающий regression **по нужной
  причине** (RED) → root-cause фикс → GREEN. Security/leak/concurrency локать на уровне
  **наблюдаемого** (scrubbed principal; retriable code, не PermissionDenied; per-call
  deadline применён; вызов возвращается ~ за timeout под fake-блокером `-race`), не только
  gRPC-код (`testing.md`). Doc-truth: комментарий И код к корректному поведению. Чинит
  **ВСЕ** переданные confirmed находки своего репо в одном PR (fix-all-in-round, §1) — не
  выбирает подмножество и не откладывает; только false-positive/cross-repo — пометить
  (`skipped-*`), не форсить. Ветка `fix/audit-rN`, push, PR не открывать.

Промты параметризованы в скрипте — правь их там, единый источник.

**Severity floor / LOW-toggle**: по умолчанию verify-фильтр держит `severity ∉
{LOW,INVALID}` — LOW by-design не чинятся (экономия на мелочах, дефолтный harness). Когда
заказчик просит «учитывать и LOW» / «вычистить всё, включая мелочи» — прогнать
**LOW-inclusive** вариант: (а) в схеме находки `sev` enum += `LOW`; (б) finder-промт
репортит LOW-дефекты, но только РЕАЛЬНЫЕ (конкретное, пусть мелкое, следствие — не
bikeshed/форматирование/вкусовщина); (в) verify-фильтр держит `severity !== 'INVALID'`
(LOW остаётся), а false-positive парковать в `INVALID`/`real=false`, **не** в LOW;
(г) `severityFloor='LOW'`. Канонический bundled-скрипт **не мутировать** — сделать
run-scoped копию (job-tmp) с этими правками и запустить её (`scriptPath` на копию).
Fix-all-in-round (§1) действует и на LOW: включил LOW → чинишь и LOW сразу.

## 5. Сходимость и отчёт

- Декларация «хватит / 100% выполнено» — **только** после `dry`-раунда (0 confirmed на
  максимальной планке) И все затронутые core-`ci` мастера GREEN.
- **Severity-разбивка**: считать `H HIGH + M MEDIUM` подтверждённых (`+ L LOW`, если
  включён LOW-toggle §4). При дефолтной планке LOW = 0 by-design (verify-фильтр) — не
  выдавать LOW-охват за то, чего не было; при LOW-toggle — честно назвать и LOW-число.
- **Trail** (обязателен, `vault.md`): `obsidian/kacho/KAC/audit-hardening-<date>.md` —
  таблица сходимости по раундам, PR-список по репо, «Затронутые сущности vault», DoD.
  Обновлять после каждого merge.
- **Абсолютная «100%-чистота» асимптотична** — честная формулировка: «systematic
  adversarially-verified аудит сошёлся к нулю находок на максимальной планке», а не
  «дефектов больше не существует».

## 6. Грабли harness

- `Workflow.args` может прийти **строкой** → в скрипте:
  `const a = (typeof args === 'string' ? JSON.parse(args) : args) || {}`.
- Дедуп vs **seen**, не vs confirmed (см. §1) — иначе не сходится.
- Финдер читает узкие vault-файлы, не 50KB README (`vault.md`).
- Флейки CI ≠ находка: `gh run rerun --failed` (429 golangci-action, proxy.golang.org
  stream error, testcontainers pull-timeout).
- commitlint: тест-комментарии/сообщения не должны матчить `#\d` (issue-ref regex) —
  формулировать словами.
- Фикс-агент трогает **только прод-код своего репо**; cross-repo-фикс (proto/corelib) —
  `action=skipped-needs-cross-repo`, отдельным раундом по build-графу (`polyrepo.md`).
- Никаких `Co-Authored-By`/attribution-трейлеров; никакого прямого push в `main`
  (`git-youtrack.md`).

## 7. Single-repo режим (standalone-клон)

Скил синкается в каждый репо. В отдельном репо без `project/`-дерева:
`args: { root: '.', repos: ['.'], seen: [], round: 1 }` — финдер/verify/fix работают по
cwd. Внешняя петля и стоп-критерий те же; PR/CI/merge — в текущем origin.
