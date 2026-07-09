---
tags: [kac, methodology, audit, security]
type: methodology
status: reference
---

# Массированный аудит-рефакторинг — промт-контур (loop-until-dry)

Переиспользуемый harness автономного аудита kacho-*. Цикл: **find → adversarial-verify →
TDD-fix → PR → CI → merge → re-check**, повторять **пока раунд не даст 0 confirmed**
(сходимость). Так пройдено 11 итераций (10→…→0). Оркестрируется через `Workflow`
(ultracode); каждая фаза — отдельный субагент со своей ролью и схемой вывода.

---

## 0. MASTER-директива (цель цикла — задаётся один раз)

> Сделай полный массированный рефакторинг, затрагивающий **безопасность,
> структурность, читаемость, утечки (ресурсов/данных) и LEAN-чистоту** — чтобы код был
> на 100% чистый и безопасный. На **каждой итерации проверяй заново**; продолжай, пока
> сам не примешь решение, что **хватит и 100% выполнено**. Работай автономно:
> ветка→PR→CI→merge (никакого прямого push в main, никаких attribution-трейлеров).
> Критерий остановки — **раунд, не давший ни одной находки, переживающей
> adversarial-verify** (K=1 «сухой» раунд ⇒ сходимость).

**Инварианты Kachō, которыми аудит меряет «дефект»** (источник истины —
`kacho-workspace/.claude/rules/*`):
1. **AuthN+AuthZ на КАЖДОМ RPC обоих листенеров** (public и internal :9091); «internal =
   trusted» — запрещённое допущение (`security.md`).
2. **Object-scoped authz** там, где метод оперирует конкретным объектом (BOLA /
   existence-oracle / cross-project disclosure — HIGH).
3. **Per-call deadline на КАЖДОМ внешнем вызове** (gRPC/HTTP/DB): `context.WithTimeout`,
   не полагаться на inbound ctx; `retry.OnUnavailable` не ограничивает один зависший вызов.
4. **Никакого leak'а** pgx/SQL-текста в INTERNAL-ошибках; никакой инфра-топологии на
   публичной поверхности (`security.md` §infra-sensitive).
5. **Doc-truthfulness**: комментарий обязан совпадать с кодом; misleading-security-comment
   = trap (будущий контрибьютор «починит код под комментарий» → регресс).
6. **Within-service инвариант — на DB-уровне** (FK/UNIQUE/EXCLUDE/CHECK/CAS), не software
   TOCTOU (`data-integrity.md`).
7. **Ban #2** — ни одного упоминания чужих облаков в коде/доках/env/именах.
8. **Concurrency**: O(N²)/неограниченный рост, гонки, second-writer-wins.
9. **LEAN**: dead/vestigial код, дублирование горизонтали (→ corelib), лишние аллокации.

---

## 1. Оркестрация (Workflow, один раунд)

```
phase('Find')     → per-repo deep-finder × N репо (parallel)         → findings[]
phase('Verify')   → per-finding adversarial refuter (pipeline)       → confirmed[] (survivors)
   dedup vs seen  (по file+summary; НЕ vs confirmed — иначе rejected воскресают)
phase('Fix')      → один агент на репо, строгий TDD (parallel)       → branch pushed
   → gh pr create → CI → gh pr merge --squash
round_confirmed == 0  ⇒  dry++;  dry>=1 ⇒ СХОДИМОСТЬ, стоп
                      иначе       ⇒  следующий раунд
```

Репо-набор (code-heavy): `kacho-corelib · iam · vpc · compute · geo · nlb ·
api-gateway · registry`. Каждый раунд — свежий finder (не помнит прошлых), поэтому
`seen`-set на оркестраторе гасит повторы.

---

## 2. FINDER (per-repo, phase «Find»)

Схема вывода: `{ findings: [{ file, line, dim, sev, summary, why }] }`,
`dim ∈ {security,leak,structure,readability,lean,concurrency}`, `sev ∈ {HIGH,MEDIUM}`.

> Ты — **скептик-аудитор** Go-репозитория `${ROOT}/${repo}` (Kachō, облачный
> control-plane). Найди **реальные дефекты** по 6 дименсиям: **security, leak
> (ресурсов/goroutine/данных), structure (нарушение clean-arch / dependency-rule),
> readability (в т.ч. misleading/устаревший комментарий как latent-hazard), lean
> (dead/vestigial/дублирование), concurrency (гонки, O(N²), unbounded)**.
>
> Планка — **HIGH/MEDIUM только**. **Не выдумывай nits / style-only / субъективный
> bikeshed** — если сомневаешься между LOW и «не находка», не репортить. Каждая находка
> обязана нести **конкретный failure-сценарий** (какой вход/состояние → какой вред:
> auth-bypass, cross-project disclosure, goroutine/conn-leak, permanent-hang, гонка,
> регресс), а не «может быть плохо».
>
> Мерь код против инвариантов Kachō (`.claude/rules/*`, перечислены в master-директиве):
> per-RPC authz на обоих листенерах; object-scoped authz (BOLA/existence-oracle);
> per-call `context.WithTimeout` на КАЖДОМ внешнем вызове; no pgx/SQL-leak в INTERNAL;
> no infra-topology на публичной поверхности; comment-must-match-code; DB-level
> инварианты (не TOCTOU); ban #2 (чужие облака); LEAN.
>
> Читай **только узкие файлы** (use-case/handler/clients/repo/interceptors/main-wiring);
> контекст ресурса/edge — из `obsidian/kacho/{resources,rpc,edges}/`, не грузи 50KB README.
> Верни ≤ ~6 сильнейших находок (не разбавляй слабыми). Для каждой: `file:line`, `dim`,
> `sev`, `summary` (одно предложение — суть дефекта), `why` (**конкретный
> failure-сценарий + направление фикса** — на какой sibling равняться, какой инвариант нарушен).

---

## 3. ADVERSARIAL-VERIFY (per-finding, phase «Verify»)

Схема: `{ real: bool, severity: enum[HIGH,MEDIUM,LOW,INVALID], refutation: string }`.
Оркестратор оставляет только `real == true && severity ∉ {LOW, INVALID}`.
(Именно этот фильтр — причина «0 LOW пофикшено»: LOW-вердикты отбрасываются как не-actionable.)

> Тебе дана audit-находка по `${repo}`. Твоя задача — **ОПРОВЕРГНУТЬ** её (refute-режим,
> по умолчанию `real=false`, если не смог твёрдо подтвердить):
>
> `${file}:${line} [${dim}/${sev}] ${summary}` — WHY: `${why}`
>
> Открой реальный код и проверь: (a) существует ли путь, на котором failure-сценарий
> действительно срабатывает; (b) нет ли уже защиты выше по стеку (интерсептор, DB-констрейнт,
> валидация, документированный by-design), которая делает находку **ложной**; (c) верна ли
> заявленная severity (down-grade до LOW, если вреда на HIGH/MEDIUM нет). Если это
> intentional-documented-design или false-positive — верни `real=false` с чётким
> `refutation`. Если дефект **реален** — `real=true`, точная `severity`, и в `refutation`
> запиши, что именно подтвердил (какой конкретно вход даёт вред). Не поддавайся
> красивой формулировке находки — суди по коду.

---

## 4. FIXER (per-repo, phase «Fix») — строгий TDD

Схема: `{ repo, branch, pushed, outcomes:[{file, action:enum[fixed,skipped-false-positive,
skipped-needs-cross-repo], what, test, verify}], verifyLog }`.

> Чинишь **verified** находки (прошли adversarial-verify) в `${ROOT}/${repo}`. Для каждой —
> concrete failure-сценарий + направление фикса.
>
> `${findingsText}`
>
> **ПРАВИЛА (Kachō, non-negotiable):**
> - **Строгий TDD**: на каждый фикс СНАЧАЛА падающий regression-тест (unit — mock-порты /
>   fake-ctx / table-driven), прогнать → RED **по нужной причине**, затем фикс → GREEN.
>   Security/leak-фикс фиксирует **наблюдаемое** поведение: scrubbed-principal → system/empty;
>   error-code retriable (Unavailable), а не PermissionDenied; per-call deadline применён.
>   Concurrency/timeout-фикс: fake, который блокирует → вызов возвращается ~ за
>   configured-timeout, не висит (`-race`).
> - **Root cause по направлению фикса.** Missing-per-call-deadline: обернуть внешний вызов в
>   `context.WithTimeout(ctx, <configured-timeout>)` по образцу sibling'а, который уже так
>   делает (тот же источник/имя таймаута); применить ко ВСЕМ sibling-методам клиента для
>   консистентности. Doc-truthfulness: привести комментарий В СООТВЕТСТВИЕ коду **И** починить
>   код до корректного поведения (не «переписать комментарий под баг»).
> - Если при глубоком разборе находка — **false-positive** / intentional-design: не ломать,
>   `action=skipped-false-positive` + обоснование. Если корректный фикс требует **другого репо**
>   (proto/corelib): `action=skipped-needs-cross-repo` + что/где; in-repo-часть сделать.
> - **Никакого нового tech-debt / TODO.** No pgx/SQL-leak в INTERNAL. Изменения — минимальные,
>   хирургические.
>
> **VERIFY перед завершением:** `go build ./...`, `go test` затронутых пакетов (с `-race` для
> concurrency), `golangci-lint run` затронутых пакетов — всё зелёное. Затем из `${ROOT}/${repo}`:
> ветка `fix/audit-rN` от `origin/main`, застейджить ТОЛЬКО свои файлы, коммит
> (Conventional Commit `fix(...)`/`refactor(...)`, **без Co-Authored-By/attribution**),
> `git push -u origin fix/audit-rN`. PR **не** открывать (оркестратор откроет). Верни
> структурный результат.

Оркестратор после fix-фазы: `gh pr create` → дождаться CI → `gh pr merge --squash
--delete-branch` → обновить `seen` → следующий раунд.

---

## 5. Сходимость и отчёт

- **Стоп-критерий**: раунд с **0 confirmed** после verify (K=1 сухой раунд). Достигнутая
  кривая: `10 → 5 → 2 → 1 → 0` (последние 5 раундов сессии; всего ~11 итераций с ранними).
- **Разбивка по severity** (что реально мержится): считать `1 HIGH + N MEDIUM`; **LOW = 0
  by-design** (verify-фильтр отбрасывает LOW/INVALID; finder'ам сказано skip nits).
- **Trail**: `obsidian/kacho/KAC/audit-hardening-*.md` — таблица сходимости по раундам,
  список PR по репо, «Затронутые сущности vault», DoD. Каждый merge → обновить.
- **Финальная верификация**: все core-`ci` мастера GREEN + vault-trail merged ⇒ декларация
  «хватит, 100% выполнено».

---

## 6. Тонкости harness (грабли, на которых уже наступали)

- `Workflow.args` приходит **строкой**, не массивом → в скрипте:
  `const groups = (typeof args === 'string' ? JSON.parse(args) : args) || []`.
- `dedup vs seen`, **НЕ vs confirmed** — иначе verify-отклонённые находки воскресают каждый
  раунд и цикл не сходится.
- Finder читает узкие vault-файлы, **не** 50KB README (дисциплина `vault.md`).
- CI-флейки (golangci-lint-action 429, proxy.golang.org stream error, testcontainers
  pull-timeout) — это **не** находки: `gh run rerun --failed`, не путать с дефектом кода.
- commitlint: тест-комментарии не должны матчить `#\d` (issue-ref regex) — формулировать словами.
