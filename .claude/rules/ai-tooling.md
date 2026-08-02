# AI-оснастка Kachō: канонический набор и lifecycle

Этот проект разрабатывается, тестируется и сопровождается автономно через Claude
Code. Оснастка — это «команда»: правила (rules), агенты (роли), скилы (экспертиза),
hooks (дисциплина). Принцип: **структурно, не избыточно, заточено под Kachō**.

## Модель распространения: self-sufficient репо + sync из workspace

Оснастка **физически дублируется** в `.claude/` каждой рабочей копии продукта, чтобы репо
был самодостаточен при standalone-клоне (CI, свежий checkout, отдельный контрибьютор):
parent-walkup для `CLAUDE.md` работает только когда Claude запущен ВНУТРИ дерева workspace,
а `settings.json`/hooks вообще не делают parent-walkup (cwd-only). **Источник истины —
`kacho-workspace/.claude/`**; копии генерируются `./sync-tooling.sh` (вшит в `./sync-all.sh`).

> [!warning] Эта модель была объявлена, но НЕ ВЫПОЛНЯЛАСЬ — и невыполнение было ненаблюдаемо
> Замер 2026-08-02: в `project/kacho` (монорепо, где ведётся вся разработка) отслеживалось
> **ноль** файлов `.claude/` — ни правил, ни агентов, ни скилов, ни `CLAUDE.md`. Механизм при
> этом рапортовал успех: `REPOS` нёс одиннадцать имён полирепо, **ни одно** из них не
> пересекалось со склонированным, скрипт печатал одиннадцать «skip» и выходил кодом 0.
> То есть инвариант самодостаточности не выполнялся ни разу за всё время жизни механизма, а
> раскатка «в ноль репозиториев» была неотличима от «всё уже синхронно».
>
> Исправлено тремя вещами, каждая закрывает свою половину:
> 1. **перечень выводится из дерева** (`repos.sh`), а не выписывается — рукописный список жил
>    в трёх копиях и уже разошёлся сам с собой (в `sync-all.sh` не хватало `kacho-geo`);
> 2. **ноль целей — отказ**, а не успех (`sync-tooling.sh`, `sync-all.sh`, оба печатают
>    объём осмотренного, чтобы «ноль находок» было отличимо от «ноль прочитанного»);
> 3. **гейт** `./sync-tooling.sh --check` + `tests/sync-tooling.bats` в CI: репозиторий
>    продукта без оснастки, раскатка в ноль целей и разошедшаяся с источником копия — красное.

- **Правишь generic-оснастку → ТОЛЬКО в `kacho-workspace/.claude/`**, затем
  `./sync-tooling.sh`. Копию в репо руками не редактируй (перетрётся при следующем sync, а
  гейт `--check` покраснеет раньше) — это и есть защита от drift.
- **Единица счёта — ОТСЛЕЖИВАЕМЫЙ git-элемент, не то, что лежит на диске.** Раскатка берёт
  наборы через `git ls-files`, поэтому объявление, `.gitignore` и поведение не могут
  разъехаться молча. Предикаты (сверяй ими, а не памятью):
  `git ls-files .claude/rules/ | cut -d/ -f3 | sort -u | wc -l` (**10**, из них едет **9**),
  `git ls-files .claude/agents/ | wc -l` (**15**),
  `git ls-files .claude/skills/ | cut -d/ -f3 | sort -u | wc -l` (**12**).
  На диске скилов больше — сторонние, установленные рядом, объявлены чужими в `.gitignore`
  и **не** раскатываются.
- **Едет не всё: ассет без ПРЕДМЕТА в целевом репозитории не едет.** Мёртвый ассет — не «про
  запас», он тихо ничего не делает, оставаясь на вид работающим (ровно тот класс, который
  правила запрещают в продуктовом коде). Сегодня не едут три вещи, все про obsidian-vault,
  которого в монорепо нет: `rules/vault.md`, `hooks/vault-reminder.sh`,
  `hooks/vault-stop-check.sh` (замерено исполнением: на воркспейсе последний даёт 614 байт
  вывода, на монорепо — **0 байт**, всегда). Исключение **самоистекает**: появится
  `obsidian/kacho` в целевом репо — `--check` выдаст находку `STALE-EXCLUSION`.
- **`settings.json` едет БЕЗ блока `permissions`.** `defaultMode: bypassPermissions` — выбор
  про конкретную машину; закоммиченный в **публичный** репозиторий, он принял бы этот выбор
  за каждого, кто сделает свежий клон. Место такого выбора — `.claude/settings.local.json`
  (git-ignored). Портируемая часть — провязка хуков — едет, и гейт проверяет, что **каждый**
  провязанный хук в назначении существует (провязка в пустоту = та же форма без содержания).
- **Domain-агенты/скилы** (`vpc-*`, `compute-*`, `<svc>-load-testing`) — НАТИВНЫЕ в своём
  репо; sync их не трогает и не перетирает. На монорепо перечень доменов **выводится** из
  `services/*`, а не выписывается.
- **Каждая рабочая копия несёт корневой `CLAUDE.md`**, который `@import`-ит локальные
  `.claude/rules/*` (включая `00-kacho-core.md`) — поэтому standalone-репо получает identity
  + правила. Гейт сверяет это в обе стороны: приехавшее правило обязано импортироваться
  (`NO-IMPORT`), импортируемое — приезжать (`DANGLING-IMPORT`).

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

**Domain-specific (в `project/kacho/.claude/agents/`) — только узкая экспертиза:**
- домен vpc: `vpc-cidr-specialist`, `vpc-outbox-watch-engineer`, `vpc-newman-author`, `vpc-load-testing`, `vpc-conventions-auditor` (аудит конвенций Kachō: error-format/regex/status-mapping/timestamp/update_mask/sync-vs-async — НЕ сравнение с чужими облаками).
- домен compute: domain-specialists по аналогии (instance-lifecycle, disk-image, conventions-auditor, newman-author, load-testing).

> Распространение: **15** generic-агентов (предикат: `git ls-files .claude/agents/ | wc -l` —
> не память, перечень выше и это число обязаны совпадать) — **источник истины в workspace**,
> копии раскатываются `./sync-tooling.sh` в `.claude/agents/` каждой рабочей копии продукта
> (репо самодостаточен при standalone-клоне). Правка generic-агента — только в workspace, не в
> копии: `--check` покраснеет находкой `DRIFT`. Рядом с синканными generic живут **нативные
> domain-specific** агенты, имя которых префиксуется доменом (`vpc-*`, `compute-*`, …; на
> монорепо перечень доменов выводится из `services/*`) — sync их не трогает и не вычищает.

## Канонические скилы (`.claude/skills/<name>/SKILL.md`)

**Единица перечня — отслеживаемая git директория скила**; предикат пересчёта —
`git ls-files .claude/skills/ | cut -d/ -f3 | sort -u`. Перечень ниже обязан **совпадать** с
его выводом: строка без директории и директория без строки — обе находки. На 2026-08-02
перечень называет **11** имён, отслеживаемых директорий в дереве **12**; двенадцатая —
`godzila` (подраздел ниже: решение о её версии за владельцем), и `check-03` остаётся на ней
красным намеренно. `<svc>-load-testing` живёт в репо сервиса и в этот счёт не входит.

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
- `security-surface` (workspace) — поверхность безопасности сервиса: что приезжает вместе с новым RPC, списком, слушателем, записью каталога прав, профилем развёртывания, отношением модели, кэшем вердиктов, внешним вызовом, полем со ссылкой на чужой объект, и что ломается при снятии доступа. 33 класса из корпуса находок за всё время, у каждого признак · противоядие · чем держится; запреты `security.md` не переизлагает — ссылается по названию раздела. Применять при ЗАВЕДЕНИИ нового сервиса и при доработке существующего.
- `<svc>-load-testing` (repo) — конкретные нагрузочные сценарии сервиса.

> Пять скилов делят один шов и **не пересекаются по построению**: `code-authoring` отвечает
> «что этот код будет **утверждать**» (момент — рука на клавиатуре, не-тестовый исходник),
> `measurement-discipline` — «что верно о мире **сейчас**» (срок годности = ревизия),
> `gate-authoring` — «что покраснеет **завтра**, на коде, которого ещё нет»,
> `verdict-and-landing` — «что означает **полученный** исход и как внести изменение»,
> `security-surface` — «какая **поверхность периметра** заводится этим изменением». Первые
> четыре нарезаны по инженерному ДЕЙСТВИЮ, пятый — по ПОВЕРХНОСТИ, поэтому ось у него
> ортогональна, а не вложена. Спорный
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
