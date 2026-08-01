# AI-оснастка Kachō: канонический набор и lifecycle

Этот проект разрабатывается, тестируется и сопровождается автономно через Claude
Code. Оснастка — это «команда»: правила (rules), агенты (роли), скилы (экспертиза),
hooks (дисциплина). Принцип: **структурно, не избыточно, заточено под Kachō**.

## Модель распространения: self-sufficient репо + sync из workspace

Оснастка **физически дублируется в каждый `project/<repo>/.claude/`**, чтобы репо был
самодостаточен при standalone-клоне (CI, свежий checkout, отдельный контрибьютор):
parent-walkup работает только когда Claude запущен ВНУТРИ дерева workspace, а
`settings.json`/hooks вообще не делают parent-walkup (cwd-only). **Источник истины —
`kacho-workspace/.claude/`**; копии генерируются `./sync-tooling.sh` (вшит в `./sync-all.sh`).

- **Правишь generic-оснастку → ТОЛЬКО в `kacho-workspace/.claude/`**, затем
  `./sync-tooling.sh` раскатывает во все репо. Копию в репо руками не редактируй
  (перетрётся при следующем sync) — это и есть защита от drift.
- **Что синкается** (generic, во все репо): `rules/*` (включая `00-kacho-core.md`),
  13 generic-агентов `agents/*.md`, 10 generic-скилов `skills/*/`, `hooks/*`, `settings.json`.
  > [!warning] `sync-tooling.sh` берёт `ls -1d */` из `.claude/skills/` **без фильтра** —
  > раскатается всё, что лежит в каталоге, включая **неотслеживаемое и игнорируемое**.
  > Единица счёта здесь — **отслеживаемая git директория скила**, предикат:
  > `git ls-files .claude/skills/ | cut -d/ -f3 | sort -u | wc -l`. На диске директорий
  > **больше**, и расхождение не косметическое: то, что `.gitignore` объявил «не частью
  > набора», всё равно **раскатывается по всем репо** — просто без версии и без ревью.
  > Заводя скил, сверяй перечень ниже этим предикатом, а не памятью.
- **Domain-агенты/скилы** (`vpc-*`, `compute-*`, `<svc>-load-testing`) — НАТИВНЫЕ в своём
  репо; sync их не трогает и не перетирает. Имя domain-агента префиксуется доменом.
- **Каждый `project/<repo>/CLAUDE.md`** сам `@import`-ит локальные `.claude/rules/*`
  (включая `00-kacho-core.md`) — поэтому standalone-репо получает identity + правила.

### Механика Claude Code (на чём это держится)
- **CLAUDE.md** — загружается из cwd + parent-walkup; `@import` подтягивает файлы
  (пути относительно импортирующего файла → `@.claude/rules/X` = локальная копия репо).
- **Агенты** — `.claude/agents/<name>.md` (frontmatter `name`/`description`[/`tools`/`model`]); nearest-wins.
- **Скилы** — `.claude/skills/<name>/SKILL.md` (директория!). Frontmatter `name`/`description`.
- **Hooks** — `.claude/settings.json` (cwd-only, без parent-walkup; пути через `$CLAUDE_PROJECT_DIR`).

## Канонические агенты (источник истины — workspace `.claude/agents/`; копии синкаются во все репо)

**Исполнение (task-execution):**
- `acceptance-author` — пишет Given-When-Then acceptance-док (markdown, не код) ПЕРЕД любой новой работой.
- `proto-sync` — синхронизирует/адаптирует `.proto` в `kacho-proto` (envelope flat-resources, package `kacho.cloud.<domain>.v1`).
- `service-scaffolder` — скелет нового сервиса (cmd/internal/migrations/deploy/CI), без бизнес-логики.
- `rpc-implementer` — реализует один RPC end-to-end строгим TDD (proto→migration→repo(sqlc)→handler→outbox→tests); для public RPC зовёт `api-gateway-registrar`.
- `migration-writer` — goose SQL-миграции (JSONB/GIN/UNIQUE/EXCLUDE/CHECK/CAS/triggers); не редактирует применённые.
- `api-gateway-registrar` — регистрирует новый public RPC в api-gateway (никогда Internal.* на external).
- `integration-tester` — конвертит APPROVED-сценарии в падающие integration+e2e тесты (TDD red).

**Ревью (specialist-review):**
- `acceptance-reviewer` — единственный gate APPROVED для acceptance-дока (не заказчик).
- `system-design-reviewer` — распределённые аспекты (dual-write, идемпотентность, OCC, реконсайл, replica-isolation).
- `db-architect-reviewer` — Postgres-схемы/миграции против `data-integrity.md` (FK/partial-UNIQUE/EXCLUDE/CAS/xmin/SKIP-LOCKED).
- `go-style-reviewer` — Go clean-code (error wrapping, ctx, slog, no panic в prod-path, thin handlers) + skill `evgeniy`.
- `proto-api-reviewer` — proto-изменения: package naming, flat-resource envelope, `Get/List` sync + `Create/Update/Delete`→Operation, buf lint/breaking/validate, Internal-vs-public.
- `qa-test-engineer` — расширяет regression-suite (Newman) против acceptance/спеки как источника истины; находки → GitHub Issue + регрессионный тест.

**Domain-specific (в `project/<repo>/.claude/agents/`) — только узкая экспертиза:**
- kacho-vpc: `vpc-cidr-specialist`, `vpc-outbox-watch-engineer`, `vpc-newman-author`, `vpc-load-testing`, `vpc-conventions-auditor` (аудит конвенций Kachō: error-format/regex/status-mapping/timestamp/update_mask/sync-vs-async — НЕ сравнение с чужими облаками).
- kacho-compute: domain-specialists по аналогии (instance-lifecycle, disk-image, conventions-auditor, newman-author, load-testing).

> Распространение: 13 generic-агентов — **источник истины в workspace**, копии
> раскатываются `./sync-tooling.sh` в `project/<repo>/.claude/agents/` (репо самодостаточен
> при standalone-клоне). Правка generic-агента — только в workspace, не в копии.
> В `project/<repo>/.claude/agents/` рядом с синканными generic живут **нативные
> domain-specific** агенты (имя префиксуется доменом: `vpc-*`, `compute-*`) — sync их не трогает.

## Канонические скилы (`.claude/skills/<name>/SKILL.md`)

**Единица перечня — отслеживаемая git директория скила**; предикат пересчёта —
`git ls-files .claude/skills/ | cut -d/ -f3 | sort -u`. Перечень ниже обязан **совпадать** с
его выводом: строка без директории и директория без строки — обе находки. На 2026-08-02
таких директорий **10** (`<svc>-load-testing` живёт в репо сервиса и в этот счёт не входит).

- `evgeniy` (workspace) — Go-архитектура kacho-* (UseCase, CQRS-порты, self-validating domain, DTO, cmd/migrator, 48 правил). Канонический Go-style ruleset.
- `code-authoring` (workspace) — семантика прод-кода в момент написания: отсутствие, представимое отдельно от значения; решение, неотделимое от следствия; классификация чужого отказа без корзины «прочее»; порядок операций внутри запроса и порядок снятия ресурса; значение, выразимое ровно одним способом; унификация по самой узкой семантике; стоимость страницы, принадлежащая запросу; оснастка, судимая по идентичности. Несёт механизм накопления классов с предикатом снятия. Применять ПЕРЕД вводом поля/ручки/ветки/внешнего вызова/миграции.
- `testing-code-coach` (workspace) — практики unit/integration (пирамида, AAA, fakes vs mocks, table-driven, property/mutation/fuzz).
- `testing-product-coach` (workspace) — black-box техники (ECP/BVA/decision-tables/state/pairwise/exploratory/conformance) + применение к Newman.
- `load-testing-coach` (workspace) — методология нагрузки (SLO/SLA, k6/ghz, p50/p95/p99, bottleneck).
- `kacho-docs-writer` (workspace) — регламент документации Kachō: docs-site (Docusaurus 3, эталон kacho-vpc), спека-книга 00-04, own-product тон, сверка фактов с ground-truth, build-гейт 0 broken links, анти-паттерны.
- `hardening-audit-loop` (workspace) — многоагентный итеративный аудит-рефакторинг до сходимости (find → adversarial-verify → TDD-fix → PR/CI/merge → re-check, пока раунд не даст 0 confirmed). 6 дименсий (security/leak/structure/readability/LEAN/concurrency), 9 инвариантов Kachō как определение «дефекта», refute-верификация (отсекает false-positive/LOW), поведенческие regression-тесты. Bundled один-раунд Workflow `references/audit-round.workflow.js`; оркеструется через ultracode. Применять на «массированный аудит»/«довести до 100% чистого и безопасного».
- `measurement-discipline` (workspace) — как получить число или факт о дереве, стенде и чужой работе, который выдержит проверку: единица счёта, ревизия, объём осмотренного, предикат с контролем в обе стороны и зеркальная форма, радиус по имени механизма, перепись по осям, провенанс стенда, живость предмета, атрибуция чужого замера. Применять ПЕРЕД тем как назвать число в отчёте/коммите/приёмке.
- `gate-authoring` (workspace) — как построить проверку, СПОСОБНУЮ упасть (гейт, страж, CI-чек, регрессионный тест, пробу): производитель входа и захват реального сообщения, инъекция настоящим входом с законным близнецом, исход вместо объявления, отрицание только в паре с положительным, детерминизм входа, самоистечение послаблений, фикстура не снисходительнее продукта. Исполняет норму `testing.md` §«Гейт на класс», не переписывает её.
- `verdict-and-landing` (workspace) — как прочесть полученный исход и внести изменение: три категории (зелёный / красный / «не выполнилось»), область зелёного, недействительный прогон против красного, величина в предикате необратимого шага, применённое против исходника, доказательство сохранности работы, expand→migrate→contract, общий клон и параллельные писатели, признак восстановимости публичного текста.
- `<svc>-load-testing` (repo) — конкретные нагрузочные сценарии сервиса.

> Четыре скила делят один шов и **не пересекаются по построению**: `code-authoring` отвечает
> «что этот код будет **утверждать**» (момент — рука на клавиатуре, не-тестовый исходник),
> `measurement-discipline` — «что верно о мире **сейчас**» (срок годности = ревизия),
> `gate-authoring` — «что покраснеет **завтра**, на коде, которого ещё нет»,
> `verdict-and-landing` — «что означает **полученный** исход и как внести изменение». Спорный
> вопрос имеет **одного** владельца; остальные ссылаются одной строкой и содержание не
> пересказывают. Одно расхождение объявлено **намеренным** и названо с обеих сторон:
> «неизвестный вход — явный отказ» (`gate-authoring`) против «неклассифицированный ответ —
> состояние, а не политика повтора» (`code-authoring`) — первое про проверки, второе про
> производственный классификатор чужих отказов.

### Лежат в `.claude/skills/`, но в канонический набор НЕ входят

`.gitignore` исключает шесть директорий под заголовком «externally-installed skills (not part
of project's intentional skill set)». Пять из них действительно посторонние
(`defuddle`, `json-canvas`, `obsidian-bases`, `obsidian-cli`, `obsidian-markdown`). Шестая —
**нет**, и это стоит знать, потому что она раскатывается по всем репо наравне с каноническими:

- **`godzila`** — сборник **готовых шаблонов кода** kachō-стиля: тело мутирующего use-case с
  `defer Abort` и outbox в той же транзакции, SQL атомарного CAS и `xmin`-OCC, partial-UNIQUE /
  EXCLUDE / CHECK, карта SQLSTATE→sentinel, обобщённый реестр DTO, построитель peer-клиента с
  TTL+LRU, LISTEN/NOTIFY на выделенном соединении, раскладка `cmd/`, шаблон теста гонки,
  20 анти-паттернов, 12 «красных флагов», чек-листы. Триггеры — новый ресурс · новый RPC ·
  новый use-case · новая миграция · новый вызов соседа. Его §20 целиком про **этот** воркспейс
  (пары с `evgeniy`, vault `obsidian/kacho/kacho-vpc/patterns/`, наши сабагенты, порядок
  загрузки), а приоритет он объявляет сам: нормативная регуляция > локальный `CLAUDE.md` >
  `godzila`, и на конфликте выигрывает `evgeniy`.
  **То есть классификация «externally-installed» фактически неверна**: скил домашний, просто
  неверсионированный. Это расхождение объявления с деревом, а не стиль; решение о версии
  (внести в набор либо оставить вне) — за владельцем, и до тех пор `godzila` цитируется как
  источник **формы кода**, но не как утверждение о текущем состоянии дерева.
  Шов с `code-authoring` проговорён в его §0 и §10: окно срабатывания у них одно, предметы
  разные — «какой код здесь пишут» против «что этот код будет утверждать».

## Lifecycle, который ОБЯЗАН удовлетворяться (gates для автономной разработки)

1. **Acceptance-first** — новая работа (вне `kacho-vpc-implement`) начинается с APPROVED Given-When-Then (`acceptance-author` → `acceptance-reviewer`). Без APPROVED — не кодить (ban #1).
2. **Тикет + ветка** — фича → KAC-тикет + ветка `KAC-<N>` + KAC-trail в vault (см. `git-youtrack.md`, `vault.md`).
3. **Контекст из vault** — перед кодом прочитать узкий `resources/`/`rpc/`/`edges/` файл (`vault.md`).
4. **Кросс-репо порядок** — proto → corelib → сервис → api-gateway → deploy → docs (`polyrepo.md`).
5. **TDD** — RED до кода, integration + newman в том же PR (`testing.md`, ban #12/#13).
6. **Ревью ролями** — perRPC через `proto-api-reviewer`/`db-architect-reviewer`/`go-style-reviewer`/`system-design-reviewer`; конвенции — `<svc>-conventions-auditor`.
7. **Финальная верификация** — `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.
8. **Trail** — обновить vault (resources/rpc/packages/edges/KAC) + перевести тикет в Test→Done с артефактами (`vault.md`, `git-youtrack.md`).

## Сторонние агенты/скилы (использовать, не пересоздавать)

`Explore`, `Plan`, `general-purpose`, `claude-code-guide` (вопросы про Claude Code/SDK/API),
`superpowers:*` (code-reviewer, brainstorming, writing-plans, test-driven-development, systematic-debugging).
