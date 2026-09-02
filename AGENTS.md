<!--
  ПОРОЖДЁННЫЙ ФАЙЛ — РУКАМИ НЕ ПРАВИТЬ.
  Источник: канонические входы .claude/ и корневой CLAUDE.md.
  Владение: .claude/adapters.yaml. Генератор: scripts/adapter/generate.py.
  Правка уедет при следующей регенерации; предмет правки — во входе.
-->

# Kachō — Workspace CLAUDE.md

Корневой индекс монорепо-воркспейса. Тонкий: `@import` модульных правил
(`.claude/rules/*.md`) + workspace-операционка (dev-стенд, sync). Identity /
naming / non-negotiables вынесены в `@.claude/rules/00-kacho-core.md`.

## Топология: монорепо `PRO-Robotech/kacho` + этот workspace

Разработка ведётся в **одном** репозитории продукта — `PRO-Robotech/kacho`, клонируется в
`project/kacho`. **Оба репозитория ПУБЛИЧНЫ.** Предшествующие полирепо (`kacho-proto`,
`kacho-<svc>`, …) существуют на GitHub, но разработка в них не ведётся (последний push —
середина июля 2026); `bootstrap.sh` клонирует их только по `KACHO_CLONE_LEGACY_POLYREPOS=1`.
Раскладка каталогов монорепо и что нормативного осталось от полирепо-правил —
`@.claude/rules/polyrepo.md`.

## Модель оснастки: единственный экземпляр в воркспейсе, копий нет

AI-оснастка (rules / agents / skills / hooks / settings) живёт **только** в
`kacho-workspace/.claude/`. Копий в рабочих копиях продукта **не заводится**, и раскатки
как механизма **не существует** (решение владельца 2026-08-02: скрипт раскатки снят вместе
с вызовами из скриптов начальной установки и обновления). Работа ведётся из воркспейса —
оттуда оснастка достаёт и до `project/kacho`.

> [!note] Почему прежняя модель дублирования снята — и почему её обоснование было ложным
> Дублирование обосновывалось допущением: «`settings.json` и hooks не делают parent-walkup,
> поэтому в отдельно склонированном репозитории оснастки не будет». **Допущение опровергнуто
> собственным журналом хука**: в нём срабатывания по деревьям, где нет ни своего
> `settings.json`, ни своих hooks (`/home/dk/wt-onecontainer`, рабочие копии под
> `~/.claude/jobs/`). Хук следует за **сессией**, а не за деревом файла, — значит копии
> не были нужны ни для чего.
>
> Отдельно: модель не выполнялась **ни разу**, и это было ненаблюдаемо. В `project/kacho`
> отслеживалось **ноль** файлов `.claude/`, при том что перечень целей раскатки нёс
> одиннадцать имён полирепо, не пересекавшихся ни с одним склонированным каталогом:
> скрипт печатал одиннадцать «skip» и **выходил успехом**. Раскатка в ноль целей была
> неотличима от «всё синхронно». Механизм снят целиком, а не починен, — чинить было
> нечего: его предмет отсутствовал.

- **Правишь оснастку → только в `kacho-workspace/.claude/`.** Больше нигде её нет,
  поэтому «копию не редактируй» перестало быть правилом: копии не существует.
- **Domain-агенты/скилы** (`vpc-*`, `compute-*`, `<svc>-load-testing`) живут там же,
  рядом с generic; отдельного дома в сервисном каталоге у них нет.
- **Следствие для CI и стороннего клона, названное честно:** отдельно склонированный
  `PRO-Robotech/kacho` оснастки **не несёт** и не должен. Правила — инструмент разработки
  в воркспейсе, а не часть поставки продукта. Проверки, которые обязаны работать в CI
  продукта, живут **в самом продукте** (гейты в `internal/repohygiene`, `tools/`,
  `scripts/`, цели Makefile), а не в `.claude/`.
- Канонический список — `@.claude/rules/ai-tooling.md`.

### Производное для других агентских сред — отслеживаемое, а не временное

Из той же единственной оснастки порождается её проекция для сред, читающих `AGENTS.md`,
`.agents/skills/` и `.codex/`. Проекция — **выход**, а оснастка — **вход**; владение
объявлено ровно в одном месте, `.claude/adapters.yaml`.

- **Правишь оснастку → перегенерируй проекцию:** `python3 scripts/adapter/generate.py`.
- **Проверить, что производное сходится с деревом:** `./scripts/adapter-gate/run-all.sh`
  (регенерация во временный каталог и побайтовое сравнение).
- **Проекцию руками не правят** — правка уедет при следующей регенерации, а гейт назовёт
  её расхождением. Предмет правки всегда во входе.

Почему выход отслеживаемый, а не порождаемый на лету, и почему имя каталога оснастки в
текстах **не подставляется** на имя второй среды — `@.claude/rules/change-graph.md`
§«Оснастка — ВХОД контура».

## Модульные правила (@import)

@.claude/rules/00-kacho-core.md
@.claude/rules/api-conventions.md
@.claude/rules/polyrepo.md
@.claude/rules/architecture.md
@.claude/rules/data-integrity.md
@.claude/rules/security.md
@.claude/rules/git-issues.md
@.claude/rules/multi-agent-flow.md
@.claude/rules/change-graph.md
@.claude/rules/testing.md
@.claude/rules/subscription.md
@.claude/rules/e2e-flow.md
@.claude/rules/ui.md
@.claude/rules/vault.md
@.claude/rules/writing.md
@.claude/rules/ai-tooling.md

## Локальная разработка

- Стенд: `cd project/kacho/deploy && make dev-up` / `make dev-down`
  (здесь стоял путь к отдельному каталогу развёртывания времён полирепо — такого каталога
  нет; все пять целей проверены в `project/kacho/deploy/Makefile`)
- Перезапуск сервиса: `make reload-svc SVC=<vpc|compute|iam>` · логи: `make logs-svc SVC=…` · psql: `make psql SVC=…`
- Обновить рабочие копии (git pull): `./sync-all.sh` — делает ровно это и ничего больше
- Спека (5 docs): `docs/specs/0{0..4}-*.md`

## Permissions

`.claude/settings.json` — `bypassPermissions` (локальная dev-машина) + hooks:
vault-discipline (`UserPromptSubmit` / `Stop`), `class-guard` (`PostToolUse`, советует
в момент записи файла) и `docfresh` (`PostToolUse` + `Stop`) — сверяет координаты, которые
документ называет, с деревом, и печатает объём осмотренного, чтобы «ноль находок» было
отличимо от «ноль прочитанного». Пути через `$CLAUDE_PROJECT_DIR`. Файл существует **в одном
экземпляре**; в репозитории продукта его нет и не должно быть — `bypassPermissions`,
закоммиченный в публичный репозиторий, принимал бы решение про чужую машину за каждого
клонирующего.

## Роли и экспертиза, доступные в этом дереве

Перечни ВЫВЕДЕНЫ из канонической оснастки при регенерации, а не выписаны: рукописный список расходится с деревом молча.

### Агенты (16)

- `acceptance-author` — Use FIRST in any new sub-iteration, new RPC, or new feature before any code is written — writes a Given-When-Then acceptance document (markdown only, never code) into kacho-workspace/docs/specs/sub-phase-X.Y-<topic>-acceptance.md; work stops until acceptance-reviewer marks it APPROVED.
- `acceptance-reviewer` — Единственный gate APPROVED для acceptance-дока (Given-When-Then) ПЕРЕД любым кодом — проверяет покрытие спеки, полноту сценариев (positive/negative/edge), traceability, реализм и scope; возвращает ✅ APPROVED либо ❌ CHANGES REQUESTED. Запускай ПОСЛЕ acceptance-author, до plan/implementation.
- `api-gateway-registrar` — Регистрирует новый public RPC на крае (каталог gateway/ монорепо): allowlist + gRPC-роутер + REST mux; никогда не публикует Internal.* на external endpoint. Запускать после rpc-implementer на public RPC.
- `class-exposure-analyst` — Запускай ПЕРЕД первой строкой кода — когда есть APPROVED acceptance, план правки или сформулированный замысел (новое поле/ручка/ветка/запасной путь/внешний вызов/асинхронный путь/sentinel/миграция с обратным заполнением/сведение N реализаций в одну), но кода ещё нет. Читает замысел и отвечает двумя списками — какие классы дефектов он может задеть и ЧТО ДОЛЖНО БЫТЬ ВЕРНО В КОДЕ, чтобы не задел; плюс какие числа о дереве нужно измерить, чтобы решение опиралось на факт, а не на догадку. Кода не пишет и не ревьюит — его предмет то, чего ещё нет. Не для готового диффа (это go-style-reviewer / system-design-reviewer / db-architect-reviewer) и не для коммита-мёржа-выкатки (это landing-reviewer).
- `convergence-reviewer` — Единственная роль, создающая финальную запись схождения изменения — перед посадкой, после того как профильные пост-дифф ревью собраны. Сверяет применимые роли точным множеством, требует подтверждающего внешнего события, фиксирует точные отпечатки изменения, полные SHA базы и источника каждого репозитория и SHA-256 канонического набора диффа. Судит СОДЕРЖИМОЕ, а не тождество коммита: схлопывание и перенос с тем же применённым содержимым посадку разрешают, расхождение содержимого её обесценивает. Запускать ПОСЛЕ профильных ревью и ДО посадки. Кода не пишет и профильных ревью не подменяет.
- `db-architect-reviewer` — Use to review Postgres schemas and goose migrations against data-integrity.md — FK/partial-UNIQUE/EXCLUDE/CHECK, atomic CAS vs TOCTOU, xmin OCC, FOR UPDATE SKIP LOCKED, no cross-service FK, no editing applied migrations, and SQLSTATE→gRPC mapping. Invoke when migration-writer or rpc-implementer produces new migrations or schema changes.
- `go-style-reviewer` — Go clean-code review of any kacho-* service — error wrapping, context propagation, slog, no panic in prod paths, thin handlers, generics justification, no init() side-effects, clean-arch import-graph. Invoke after rpc-implementer completes and before merge.
- `integration-tester` — Конвертит APPROVED Given-When-Then acceptance-сценарии в падающие integration + e2e тесты (TDD red); не реализует RPC.
- `landing-reviewer` — Запускай ПЕРЕД посадкой изменения — коммит, мёрж, squash, cherry-pick, push, выкатка, закрытие тикета — и при чтении отчёта прогона или вывода гейта, прежде чем назвать его зелёным или красным. Разделяет три категории исхода (зелёный · красный · «не выполнилось»), устанавливает ОБЛАСТЬ зелёного, отличает недействительный прогон от красного, связывает напечатанную величину с необратимым шагом, сверяет ПРИМЕНЁННОЕ против исходника, доказывает сохранность работы содержимым, ведёт expand→migrate→contract с посверкой по каждому ресурсу, разводит параллельных писателей в общем клоне и проверяет публичный текст на восстановимость. Кода не пишет. Не для конструкции проверки (это integration-tester / qa-test-engineer) и не для замысла до кода (это class-exposure-analyst).
- `migration-writer` — Use when a new goose SQL migration is needed for any kacho-* service — new table, new column, index, constraint, trigger, or seed. Writes correct goose migrations (JSONB/GIN/UNIQUE/EXCLUDE/CHECK/CAS/triggers) for schema-per-service flat tables; never edits an already-applied migration.
- `proto-api-reviewer` — Use to review any .proto change in kacho-proto/proto/ — package naming, flat-resource form, Get/List sync + Create/Update/Delete→Operation, buf lint/breaking/validate, Internal-vs-public separation. Invoke after proto-sync or when rpc-implementer adds new proto messages/RPCs.
- `proto-sync` — Use when synchronizing or adapting existing .proto definitions into kacho-proto (from another domain's proto, a draft, or an older revision) — normalizes package/go_package, conforms messages to the Kachō flat-resource + Operations envelope, and runs buf lint/breaking/generate. Not for writing brand-new proto from scratch (that's rpc-implementer / service-scaffolder).
- `qa-test-engineer` — Расширяет black-box Newman regression-suite против APPROVED acceptance-дока / спеки как источника истины; каждое расхождение или баг фиксирует исполняемым кейсом, баги продукта → GitHub Issue + регрессионный тест, который красный до фикса. Прод-код не трогает.
- `rpc-implementer` — Use after an acceptance doc is APPROVED to implement one RPC end-to-end by strict TDD. Workflow — write failing integration tests first (RED), then proto-stubs → migration → repo(sqlc/pgx) → use-case → handler → outbox-in-tx (GREEN), then refactor. Calls api-gateway-registrar for public RPC. Never code without an APPROVED acceptance doc.
- `service-scaffolder` — Use when bootstrapping a brand-new service directory services/<svc>/ inside the kacho monorepo — creates the full Clean-Architecture skeleton (cmd/internal/deploy/Dockerfile/Makefile), stub files only, no business logic. Invoke before rpc-implementer.
- `system-design-reviewer` — Распределённые аспекты дизайна Kachō — dual-write/атомарность, идемпотентность, OCC/CAS, polling-модель без Watch, координация async-worker'ов и reconciler-реплик, replica state isolation, ацикличность cross-domain графа. Запускать перед мерджем значимого архитектурного изменения или когда rpc-implementer спрашивает про distributed-паттерн.

### Скилы (14)

- `change-graph` — Как вести изменение по контуру Kachō Change Graph — порядок фаз и что каждая обязана оставить после себя; что именно открывает переход к написанию реализации и почему «красное» этого само по себе не делает; чем честный красный отличается от поломки прогона, сломанной фикстуры и несозданного условия; почему вердикт привязан к отпечатку содержимого, а не к имени документа, и что из этого следует при правке уже одобренного; почему отрицательный кейс меняет ровно один факт против положительного близнеца; почему у держателя ровно один исход и «нет вывода» — тоже исход; почему оснастка это вход контура, а производное для других агентских сред — его отслеживаемый выход. Применять ПЕРЕД правкой приёмки (вердикт привязан к отпечатку), ПЕРЕД первой строкой реализации (открыт ли переход), при чтении красного прогона до вывода о причине, при заведении машинного держателя или фикстуры кейса, и при правке любого канонического входа адаптера. НЕ про конструкцию проверки вообще (gate-authoring), не про чтение вердикта и посадку (verdict-and-landing), не про получение числа о дереве (measurement-discipline), не про долговечность утверждения в документе (doc-truthfulness).
- `code-authoring` — Как написать прод-код, который не придётся переделывать через неделю — Go, proto, миграцию, чарт, приёмку. Отсутствие, представимое отдельно от значения; решение, неотделимое от своего следствия; классификация чужого отказа без корзины «прочее»; порядок операций внутри запроса и порядок снятия ресурса; контракт, в котором значение выразимо ровно одним способом; унификация, берущая самую узкую семантику; стоимость страницы, принадлежащая запросу; собственная оснастка, судимая по идентичности, а не по имени. Применять ПЕРЕД тем как ввести поле, ручку, ветку, запасной путь, внешний вызов, асинхронный путь, sentinel-значение, миграцию с обратным заполнением, или свести N реализаций в одну. Содержит механизм накопления новых классов с предикатом снятия. НЕ про раскладку слоёв и стиль (evgeniy), не про готовый текст кода и шаблоны (godzila), не про конструкцию проверки (gate-authoring), не про получение числа о дереве (measurement-discipline), не про чтение вердикта и посадку (verdict-and-landing).
- `doc-truthfulness` — Как написать документ, комментарий, правило или число так, чтобы они не стали ложью, и как распознать, что они ей уже стали. Утверждение, пережившее свой предмет; два места об одном предмете, где одно верно; число, верное для другого предиката или другой ревизии; проверка, объявляющая «ноль находок» и не читающая целый вид предмета; исключение, которому нечего исключать; документ, описывающий владение снятым; ссылка в место, которого нет или которое публично, хотя названо внутренним; документ, устаревший в сторону «сложнее, чем есть»; команда, которая не выполнится или выполнится не там. Применять ПЕРЕД правкой правила, README, страницы сайта документации, приёмки, KAC-записки, комментария у гейта, шапки функции; ПРИ УДАЛЕНИИ поля, RPC, ресурса, скрипта, ручки — чтобы найти всех, кто про них написал; ПЕРЕД тем как действовать по чужому документу («принято», «известно», «невозможно»); и перед словами «доки обновлены». НЕ про форму и тон страницы, MDX, mermaid, структуру сайта документации и спека-книги (kacho-docs-writer), не про конструкцию проверки (gate-authoring), не про получение числа о дереве (measurement-discipline), не про чтение вердикта прогона (verdict-and-landing).
- `evgeniy` — Архитектурный регламент для kacho-vpc (и других kacho-* go-сервисов) на основе ревью @EvgenyGRI / @pointpu (PR PRO-Robotech/kacho-vpc#52, 2026-05-14). Применять при ЛЮБОМ рефакторинге, новом сервисе, новом ресурсе, новом domain-типе. Запрещает «толстые сервисы» / голые string-типы / inline-validation / envconfig в struct tags / smashed cmd-binary. Требует UseCase pattern, CQRS-разделённые порты, self-validating domain, DTO-таблицы, YAML-config через viper/koanf, отдельный cmd/migrator. Содержит 48 правил из ревью + step-by-step migration plan для kacho-vpc.
- `gate-authoring` — Как построить проверку, СПОСОБНУЮ упасть — гейт, страж, CI-чек, регрессионный тест, пробу. Производитель входа и захват реального сообщения; инъекция настоящим входом из дерева с законным близнецом; исход вместо объявления; отрицание только в паре с положительным; отношение, выполнимое подстановкой, не сужает ничего; пустой вход как всеразрешение; детерминизм входа и управляемые часы; самоистечение послаблений; разбор существующего красного до его ослабления; фикстура не снисходительнее продукта. Применять при написании ЛЮБОЙ проверки, при разборе «почему это зелёное», перед снятием или ослаблением существующей и при заведении нового сервиса. НЕ про технику дизайна кейса (testing-*-coach), не про чтение вердикта прогона (verdict-and-landing), не про число о дереве и выбор единицы счёта (measurement-discipline).
- `godzila` — Use when writing, refactoring, or reviewing a Go API in the "kachō-style" Clean-Architecture stack — slice-per-RPC use-case layout, thin gRPC handler, CQRS Repository with Reader/Writer transaction split, async Operation LRO envelope, atomic Writer-TX with outbox-emit, atomic-CAS / xmin-OCC for within-service invariants, DB-level FK / CHECK / EXCLUDE / partial-UNIQUE instead of software refcheck, UpdateMask discipline, self-validating domain newtypes, sentinel-based error mapping, generic DTO registry, peer-clients with TTL+LRU cache, LISTEN/NOTIFY event streaming on a dedicated connection. Triggers on: new resource, new RPC, new use-case, new migration, new peer-call, refactor of a fat "Service" into use-cases, design review of any of the above.
- `hardening-audit-loop` — Многоагентный итеративный аудит-рефакторинг kacho-* до сходимости — find → adversarial-verify → TDD-fix → PR/CI/merge → re-check, повторять пока раунд не даст 0 подтверждённых находок. Применять на запрос «массированный/полный аудит», «доведи код до 100% чистого и безопасного», «пройди по безопасности/утечкам/структуре/читаемости», hardening-sweep, security-audit целого репо или всего полирепо. Кодифицирует 6 дименсий (security/leak/structure/readability/LEAN/concurrency), 9 инвариантов Kachō как определение «дефекта», refute-верификацию (отсекает false-positive и LOW), поведенческие regression-тесты. Оркеструется через Workflow (ultracode); есть готовый bundled-скрипт одного раунда. НЕ для точечного багфикса (это обычный TDD-флоу) и НЕ для feature-work (нужен APPROVED acceptance-док).
- `kacho-docs-writer` — Регламент написания/правки документации Kachō — сайт документации компонента (Docusaurus 3, каталог docs у gateway и каждого сервиса), его инженерная часть, спека-книга docs/specs 00…04, README. Применять при любой задаче «написать/обновить/вычитать документацию»; кодифицирует own-product тон (без сравнений с чужими облаками), сверку фактов с ground-truth, валидность MDX/mermaid, build-гейт (0 broken links) и связность глав. Vault-записки — НЕ сюда (это .claude/rules/vault.md).
- `load-testing-coach` — Use when designing or extending performance/load/stress/soak/spike/breakpoint tests using k6 or equivalent tooling. Owns benchmarking methodology, SLO/SLA definition, capacity planning, bottleneck identification (CPU/memory/network/DB-pool/connection-limit), result analysis (p50/p95/p99/error rate/RPS curve), reproducibility, comparison between runs. Separates load testing from functional tests (newman) and from production observability. Defers product-functional tests to testing-product-coach and code-level benchmarking to testing-code-coach.
- `measurement-discipline` — Как получить число или факт о дереве, стенде и чужой работе, который выдержит проверку. Применять ПЕРЕД тем как назвать число в отчёте, коммите, приёмке или ответе владельцу; при установлении радиуса правки; при выяснении состояния стенда; при пересказе чужого замера; при оценке заявления «мёртво / принято / невозможно / уже проверено». Владею единицей счёта, ревизией, объёмом осмотренного, предикатом с контролем в обе стороны, разбором совпадений по референту, радиусом, переписью по осям, провенансом стенда, живостью предмета, атрибуцией чужого замера. НЕ про конструкцию проверки, способной упасть (gate-authoring), и НЕ про чтение вердикта и посадку изменения (verdict-and-landing).
- `security-surface` — Поверхность безопасности сервиса — что появляется вместе с новым RPC, списком, слушателем, записью каталога прав, профилем развёртывания, отношением модели, кэшем вердиктов, внешним вызовом, полем со ссылкой на чужой объект, и что ломается при снятии доступа. Каталог классов из корпуса находок за всё время: у каждого признак, противоядие и чем он держится. Применять при ЗАВЕДЕНИИ нового сервиса и при доработке существующего — до первой строки поверхности, а не на ревью. НЕ переизлагает запреты `security.md` (ссылка по названию раздела), не про конструкцию проверки (gate-authoring), не про семантику прод-кода вообще (code-authoring), не про число о дереве (measurement-discipline), не про чтение вердикта и посадку (verdict-and-landing).
- `testing-code-coach` — Use when designing, writing, or reviewing tests for production code (unit, integration, contract, e2e through bufconn). Applies to Go services in Kachō (kacho-vpc, kacho-api-gateway, kacho-corelib). Knows Clean Architecture layering — which layer gets which test type, what mocks are allowed where, and how to detect adapter leakage into use-cases. Owns test pyramid, time budgets, naming conventions, AAA structure, and 13 anti-patterns. Defers product-level QA (Newman, conformance, exploratory) to testing-product-coach.
- `testing-product-coach` — Use when designing or extending product-level tests against the deployed Kachō stack — Newman/Postman regression suites, conformance vs the Kachō spec/acceptance docs, exploratory sessions, performance/load/soak/chaos. Treats the service as a black box reachable only through public gRPC/REST/UI. Owns formal test design techniques (ECP, BVA, decision tables, state transition, pairwise, use-case, error guessing, property-based, risk-based). Knows case taxonomy (CRUD-/BVA-/VAL-/NEG-/IDM-/CONC-/CONF-). Defers white-box / unit work to testing-code-coach.
- `verdict-and-landing` — Как прочесть полученный исход и внести изменение, не разрушив чужое и не солгав о сделанном. Три категории исхода (зелёный / красный / «не выполнилось»), область зелёного, недействительный прогон против красного, связывание напечатанной величины с необратимым действием, провенанс применённого против исходника, доказательство сохранности работы, expand→migrate→contract с посверкой по каждому ресурсу, общий клон и параллельные писатели, признак восстановимости публичного текста и вопрос, который задают перед ИЗЪЯТИЕМ уже опубликованного. Применять при чтении отчёта прогона или вывода гейта, при коммите/мёрже/выкатке, при оркестрации параллельных агентов, при написании сообщения коммита. НЕ про конструкцию проверки (gate-authoring) и НЕ про получение числа или факта о дереве и стенде (measurement-discipline).

Полные пакеты скилов лежат рядом, в `.agents/skills/<имя>/`; источник — `.claude/skills/<имя>/`.
