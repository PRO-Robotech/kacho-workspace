# 08 — Roles & Skills

Описание ролей, нужных для разработки такого приклада, и **концептуальных**
скилов под каждую. Не "знать API X", а "понимать концепт Y" — потому что
библиотеки меняются, а понимание остаётся.

В малой команде один человек закрывает несколько ролей; в полной — это
6-8 человек. Этот проект разрабатывается автономно через Claude Code: каждая
человеческая роль ниже имеет соответствие в наборе AI-агентов/скилов
(см. секцию [AI-оснастка](#ai-оснастка-роли-как-агенты) и `.claude/rules/ai-tooling.md`).

## Содержание

| # | Роль | Сколько FTE для MVP |
|---|---|:---:|
| 1 | [Software Architect](#1-software-architect) | 0.3 |
| 2 | [API Designer](#2-api-designer) | 0.5 |
| 3 | [Backend Engineer (Go, Clean Arch)](#3-backend-engineer-go-clean-arch) | 1.5–2 |
| 4 | [Data Modeler / Database Engineer](#4-data-modeler--database-engineer) | 0.5 |
| 5 | [Networking / IPAM Engineer](#5-networking--ipam-engineer) | 0.5 |
| 6 | [Platform / DevOps Engineer](#6-platform--devops-engineer) | 0.5 |
| 7 | [Frontend Engineer (Web)](#7-frontend-engineer-web) | 1 |
| 8 | [TUI Engineer](#8-tui-engineer) | 0.2 (по запросу) |
| 9 | [QA / Contract-Test Engineer](#9-qa--contract-test-engineer) | 0.5 |
| 10 | [Security / Admin-Boundary Engineer](#10-security--admin-boundary-engineer) | 0.2 |
| 11 | [Product Owner / Tech Writer](#11-product-owner--tech-writer) | 0.3 |

Итого ~6–7 FTE на полноценную команду; MVP можно сделать командой 2–3
сильных fullstack-инженеров с архитектором.

---

## 1. Software Architect

**Что делает в проекте**

Отвечает за общую декомпозицию — какие сервисы существуют, какие границы
владения данных, как сервисы общаются. Принимает решения о fundamentals:
состав ресурсной модели и конвенций Kachō, sync RPC vs. LRO, polling vs.
push, monorepo vs. polyrepo, in-process vs. broker. Эти решения фиксируются
в `.claude/rules/*.md` как запреты — они потом не пересматриваются от спринта к
спринту.

**Концептуальные скилы**

- **Distributed system design** — понимание stateful vs stateless сервисов,
  database-per-service, async boundaries (LRO, outbox), failure modes
  (network partition, duplicate request, partial commit).
- **Domain decomposition** — где провести шов между сервисами так, чтобы
  большинство изменений оставались внутри одного сервиса. Когда нужен новый
  сервис, когда хватит нового RPC.
- **Read/Write separation patterns** — sync read vs. eventually-consistent
  read, polling trade-off, кеши и TTL, пользовательский UX при отсутствии
  sub-second consistency.
- **Long-Running Operations** — почему мутации возвращают `Operation`
  вместо результата, как операции связаны с outbox, как избежать "stuck
  worker" и "ghost operations".
- **Backward compatibility & contract evolution** — как добавить поле в
  proto без поломки клиентов, когда нужен новый major version, что делать
  с deprecated методами.
- **Trade-off thinking** — формулировать решения как "X vs Y, Y победил
  потому что Z" в архитектурных доках, а не как догмы.

**Артефакты, за которые отвечает**

- `CLAUDE.md` + `.claude/rules/*.md` (workspace + per-repo) — запреты и принципы.
- `docs/architecture/00..08*.md` — этот пакет.
- `docs/specs/*-acceptance.md` — Given-When-Then для крупных
  фич, до начала кода.

**С кем работает**

- API Designer — фиксирует контракты.
- Backend Lead — даёт rationale для слоёв.
- Platform — оркестрация развертывания.
- PO/TW — переводит бизнес-цели в архитектурные ограничения.

**AI-соответствие:** `system-design-reviewer` (распределённые аспекты), `acceptance-reviewer` (gate APPROVED).

---

## 2. API Designer

**Что делает в проекте**

Проектирует proto — публичный (lean, tenant-facing) и internal (full, с
инфра-полями). Решает наименование, oneof vs. отдельные RPC, FieldMask vs.
явные поля, RESTful path schema, как ошибки маппятся на gRPC status и HTTP
коды. Поддерживает контракт стабильным — иначе ломаются клиенты. Форма ресурса
— **плоский** message (domain-поля на верхнем уровне, без K8s-envelope
`metadata`/`spec`/`status`/`resourceVersion`/`generation`/`finalizers`); мутации
возвращают `Operation`.

**Концептуальные скилы**

- **gRPC + Protobuf** — proto3 семантика, oneof, optional, default values,
  почему бинарный wire-format важен, обратная совместимость.
- **REST/HTTP semantics** — методы (POST для Create, PATCH/Update,
  DELETE), status codes, idempotency, custom verbs (`:action` —
  `/subnets/{id}:addCidrBlocks`), pagination paradigms (cursor vs offset).
- **Error design** — структурированные ошибки (proto `google.rpc.Status` +
  details), различение precondition vs. validation vs. exhausted ресурсов.
  Когда `NotFound` vs `FailedPrecondition` vs `InvalidArgument`.
- **Конвенции Kachō** — единый и стабильный стиль текстов ошибок, regex,
  timestamp precision (truncate до секунд в proto-ответе), update_mask
  discipline, sync `Get`/`List` vs async `Create`/`Update`/`Delete`→`Operation`.
  Тексты — часть контракта; меняются только осознанно через тикет
  (`.claude/rules/api-conventions.md`). Как тестировать конформность (см. QA).
- **Versioning strategy** — `v1` package, что делать когда нужен `v2`,
  reserved fields для удалённых полей, deprecation lifecycle.
- **API observability** — какие поля делать output-only (computed на
  backend), какие writable; как exposить `Operation` для polling.

**Артефакты**

- `kacho-proto/proto/kacho/cloud/<domain>/v1/*.proto`.
- `google.api.http` аннотации для REST-mapping.
- Разделение public vs. `Internal*` сервисов.

**С кем работает**

- Architect — для согласования контракта.
- Backend — для имплементации с минимальным trade-off.
- QA — для контракт-тестов.
- PO/TW — определяет состав ресурсной модели Kachō.

**AI-соответствие:** `proto-sync` (адаптация `.proto`), `proto-api-reviewer`
(ревью: package naming, flat-resource envelope, sync/async, buf lint/breaking/validate,
Internal-vs-public), `api-gateway-registrar` (регистрация public RPC).

---

## 3. Backend Engineer (Go, Clean Arch)

**Что делает в проекте**

Реализует сервисы. Каждый — `cmd/<svc>/main.go` (composition root) →
`internal/handler` → use-case (`apps/kacho/api/<resource>/`, определяет
port-интерфейсы) → `internal/repo` + `internal/clients`. Большинство задач
сводится к "добавить поле в proto, проросить через все слои, мигрировать БД,
написать тест". Это рутина — делается быстро если структура знакома, медленно
если нет.

**Концептуальные скилы**

- **Clean Architecture / Hexagonal** — почему domain не знает о pgx,
  почему use-case определяет порт-интерфейсы, а не использует репо
  напрямую. Когда добавить новый порт vs расширить существующий.
- **Concurrency without ORM/framework** — `context.Context` propagation,
  cancel/timeout/deadline propagation, goroutine lifecycle, sync.Mutex vs
  channels, race conditions detection.
- **Database access без ORM** — sqlc + handwritten pgx, typed prepared
  statements, transaction scoping, connection pooling, понимание "что
  выполнится одной tx, а что двумя". Уверенное чтение pg log'ов.
- **Error handling discipline** — sentinel errors + `errors.Is/As`,
  wrapping vs обертка, когда возвращать `nil, err` а когда — обогащать
  domain-info, как не утечь internal-error (pgx/SQL) на клиента.
- **Idempotency** — операции должны выдерживать повторный вызов с тем же
  ID, retry на Unavailable, дедупликация на UNIQUE constraints.
- **Worker / async pattern** — Long-Running Operation: мутация sync пишет
  row + outbox-event в одной tx, worker крутит работу, обновляет row,
  клиент полит `OperationService.Get`. Что делать если сервис умер посреди работы.
- **Testing discipline** — unit на mock-портах, integration с
  testcontainers, e2e через Newman; знание границ "что покрывать каким
  уровнем".
- **Rejecting unnecessary abstractions** — когда написать `if err != nil`
  и не делать helper, когда не вводить interface, когда не писать generics.

**Артефакты**

- Все `kacho-<svc>/internal/{domain,repo,handler,clients}/` + `apps/kacho/api/<resource>/` use-cases.
- `cmd/<svc>/main.go` wiring (+ отдельный `cmd/migrator`).
- Unit + integration тесты.
- Per-resource SQL миграции (goose).

**С кем работает**

- API Designer — proto и его маппинг.
- Data Modeler — схема и инварианты.
- QA — где shipped feature ломает контракт.

**AI-соответствие:** `rpc-implementer` (RPC end-to-end строгим TDD),
`service-scaffolder` (скелет нового сервиса), `go-style-reviewer` (clean-code,
skill `evgeniy`); скилы `evgeniy`, `testing-code-coach`.

---

## 4. Data Modeler / Database Engineer

**Что делает в проекте**

Проектирует схемы БД (одна на сервис), constraints, индексы, миграционную
стратегию. Решает где использовать `JSONB` vs нормализованные колонки,
когда добавить EXCLUDE, какие тригеры писать (например, outbox notify).
Гарантирует что **инвариант жив на DB-уровне**, а не только в коде —
потому что код не единственный путь записи (`.claude/rules/data-integrity.md`).

**Концептуальные скилы**

- **Relational design** — нормализация vs денормализация, FK constraints,
  partial UNIQUE indices, computed columns, trigger semantics.
- **Postgres-specific advanced** — `EXCLUDE USING gist` для no-overlap
  (CIDR, time ranges); `inet/cidr` типы и операторы (`<<`, `>>=`); `JSONB`
  containment (`@>`, `?`, `jsonb_path_ops` GIN индексы); `xmin` для
  optimistic locking; `LISTEN/NOTIFY` для in-process wake-up; `FOR UPDATE
  SKIP LOCKED` для уникальной аллокации из пула.
- **Migration strategy** — append-only миграции (применённую не редактируем —
  только новая), как не сломать prod при rollout (двухфазный schema change:
  добавить + начать писать + миграция данных + переключить чтение + удалить старое).
- **Outbox pattern** — атомарность доменного INSERT и event в одной tx,
  чтобы не было дубликатов или пропусков; почему это лучше чем "после
  commit отправить в queue".
- **Index design** — когда нужен составной индекс vs два отдельных, когда
  partial vs full, когда GIN vs B-Tree.
- **Concurrency at DB level** — что такое serialization anomaly,
  `SELECT ... FOR UPDATE`, advisory locks, deadlock detection, атомарный
  CAS (`UPDATE ... WHERE <expected-state> RETURNING`), retry-on-conflict.
- **Reading EXPLAIN ANALYZE** — без этого нельзя дебажить slow query.

**Артефакты**

- `internal/migrations/*.sql` — все миграции сервиса (например, в kacho-vpc).
- ER-документ (`03-ipam.md`).
- Решения по UNIQUE/EXCLUDE/partial-index/CAS.

**С кем работает**

- Backend — на каждом новом поле репо.
- IPAM — для CIDR-overlap, computed columns, JSONB queries.
- Architect — для схемы outbox/operations.

**AI-соответствие:** `migration-writer` (goose SQL-миграции),
`db-architect-reviewer` (Postgres-схемы/миграции против `data-integrity.md`).

---

## 5. Networking / IPAM Engineer

**Что делает в проекте**

Проектирует модель IP allocation. Что такое Region/Zone/Pool, какой cascade
выбирает pool для адреса, как реализовать selector matching без race
conditions, что такое utilization и как её визуализировать. **Самая
нетривиальная фича в проекте**.

**Концептуальные скилы**

- **CIDR math** — как считать total/usable/network/broadcast для IPv4
  (и для /31, /32 — RFC 3021), что такое subnetting, supernetting, как
  делать "longest-prefix match".
- **IP allocation strategies** — random pick vs sequential vs sparse map;
  trade-off между memory и retry rate; почему UNIQUE constraint важнее
  application lock'а.
- **Label-based routing / selector matching** — selector-based matching,
  inverse-containment vs containment, equal-specificity tie-break,
  дет. ordering vs admin-controlled priority.
- **Cascade / fallback design** — упорядоченный набор правил с явным
  matched_via для observability; explainability ("почему этот IP, а не
  тот"); runner-up для "что бы было если бы первого не было".
- **Tenant separation** — разница между client-owned (project→subnet→
  internal IP) и system-owned (pool→external IP, выдаваемый клиенту).
  Cross-tenant lookup только для admin.
- **Exhaustion handling** — `ResourceExhausted` с осмысленным сообщением,
  early warning через utilization metrics, capacity planning hints.
- **IPAM observability** — utilization bars, per-CIDR breakdown,
  reverse-lookup от IP к клиенту, прогноз заполнения.

**Артефакты**

- `kacho-vpc/internal/.../address_pool` — cascade (`AddressPool` —
  admin-only Internal*-ресурс).
- `address_allocate` — picker + retry.
- Documentation в `03-ipam.md`.
- Семантика cloud-pool-selector — admin переключает routing.

**С кем работает**

- Data Modeler — схема pool/zone/cidr.
- Backend — интеграция в AddressService.
- Frontend — utilization viz.

**AI-соответствие:** domain-агент `vpc-cidr-specialist`; поддержка `db-architect-reviewer`.

---

## 6. Platform / DevOps Engineer

**Что делает в проекте**

Поднимает kind+helm dev-стенд, пишет Dockerfile'ы, deployment'ы, init-
container'ы для миграций. Делает `make reload-svc` цикл быстрым (build →
load → rollout). Решает где запускать Postgres (per-service StatefulSet),
как делать port-forward, как организовать ingress.

**Концептуальные скилы**

- **Kubernetes basics, deeply** — Deployment/StatefulSet/Service/
  ConfigMap/Secret, init-container'ы, liveness/readiness, label selector
  vs field selector. **Не** kubectl-команды наизусть, а **что значит**
  rolling update, как сервис себя представляет другим.
- **Container build** — multi-stage Dockerfile, размер образа, кэширование
  слоёв; CGO_ENABLED=0 для статической линковки Go.
- **Helm** — value composition, dependencies (umbrella), umbrella vs sub-
  chart, как делать env-config через templates.
- **Local dev velocity** — kind как быстрая альтернатива minikube/k3d;
  hot reload через `kind load docker-image`; port-forward как
  "production-like access".
- **Observability foundations** — почему slog/JSON, как агрегировать
  логи из подов, готовность под Prometheus/OpenTelemetry без вкручивания
  всего этого сейчас.
- **Migration discipline** — почему init-container / отдельный `cmd/migrator`,
  как не выкатить код до миграции, как откатывать.

**Артефакты**

- `kacho-deploy/{kind,helm,Makefile}`.
- Dockerfile'ы во всех сервисах.
- Init container / `cmd/migrator` с `migrate up`.

**С кем работает**

- Backend — env vars, health endpoints.
- Architect — границы сервисов в k8s.
- QA — стабильность стенда.

**AI-соответствие:** `service-scaffolder` (deploy/CI скелет); скил `load-testing-coach`,
domain-скилы `<svc>-load-testing`.

---

## 7. Frontend Engineer (Web)

**Что делает в проекте**

Реализует SPA на React + TS (`kacho-ui`, Vite). Большая часть страниц —
generic (registry-driven), пишутся декларативно через `ResourceSpec`.
Кастомные страницы (IPAM utilization, Search) — отдельно. Думает про state
management, polling, форм-валидацию, error UX, breadcrumb-навигацию.

**Концептуальные скилы**

- **Composable React** — useState vs Zustand vs context, когда вырывать
  state в global, как избегать prop-drilling без overuse контекста.
- **Server-state separation** — TanStack Query (или аналог) — кеш,
  staleTime, invalidate, polling. Почему server-state ≠ ui-state.
- **Form architecture** — declarative schema (FormField[]), generic
  renderer, validation на уровне поля + cross-field, dirty/touched/submit
  semantics, sanitize перед отправкой (oneof, array flatten).
- **Type safety end-to-end** — описывать payload-типы один раз и
  переиспользовать; снижать `any` к минимуму; protobuf-style имена в TS
  (snake/camel converter).
- **Async UX** — loading states, optimistic updates, error toasts,
  `Operation` polling до `done=true`, List-polling (2–5с) вместо стриминга,
  как не "переписать" пользовательский ввод во время refetch (snapshot
  template ref в нашем `ResourceFormDialog`).
- **Routing & navigation** — иерархия URL'ов как single source of truth
  для drill-context, синхронизация с store, deep-linkable URLs.
- **Visualization basics** — процентные bars, цветовые кодировки (зелёный
  → жёлтый → красный) с accessibility (не только цвет, но и число), per-
  CIDR breakdown как мини-table.
- **Design system discipline** — переиспользовать примитивы (`Button`,
  `Dialog`, `Tabs`), не плодить custom CSS, держать spacing согласованным.

**Артефакты**

- `kacho-ui/src/components/*` — generic primitives.
- `kacho-ui/src/pages/*` — custom (IPAM admin, Search).
- `kacho-ui/src/lib/resource-registry.ts` — single source.

**С кем работает**

- API Designer — paths и формат payload.
- Backend — что вернуть в response для удобства UI.
- IPAM — visualization утилизации.

---

## 8. TUI Engineer

**Что делает в проекте**

Реализует terminal-admin tool в стиле k9s. Понимает event-driven UI,
cell-based rendering, keyboard navigation, headless testing. Использует тот
же registry, что web-UI, но на Go. (Роль "по запросу" — не входит в текущий
состав репо, активируется при необходимости.)

**Концептуальные скилы**

- **Cell-grid rendering** — терминал — 2D массив символов, atomic update.
  Различие screen-redraw vs damage-tracking; почему flicker-free
  обновление сложно.
- **Event loop & input handling** — keyboard event capture, focus chain,
  modal overlays, Ctrl/Esc/Tab semantics в TUI.
- **k9s-style UX patterns** — command bar (`:`), filter (`/`), help (`?`),
  drill-down navigation, history stack для Back. Что делает TUI
  приятным/неприятным в use.
- **Headless testing** — pty + terminal emulator в тестах (pyte/expect),
  снимки экрана для regression. **Без TTY** TUI обычно нельзя запустить —
  это специфика, которую надо знать.
- **Polling в фоне без блокирования UI thread** — горутина + тред-safe
  обновления (`QueueUpdateDraw`), отмена при unmount.

**Артефакты**

- TUI `internal/{app,api,registry,discovery}/` (при активации роли).
- `tools/snap_png.py` — headless screenshot.

**С кем работает**

- Backend — для admin RPC (через api-gateway REST).
- Frontend (web) — для синхронизации registry-метаданных.

---

## 9. QA / Contract-Test Engineer

**Что делает в проекте**

Гарантирует что контракт Kachō (конвенции + acceptance-доки как источник
истины) не ломается. Пишет Newman-collection тесты (декларативные `cases/*.py`
→ `gen.py` → Postman-коллекции), поддерживает black-box regression-suite —
только HTTP через api-gateway. Каждый PR с новым RPC/полем/oneof-case несёт
≥1 happy + ≥1 negative кейс в том же PR.

**Концептуальные скилы**

- **Contract / conformance testing vs unit/integration** — что проверяет
  каждый уровень, почему unit недостаточно для проверки конвенций контракта
  (тексты ошибок, status-mapping, timestamp precision, update_mask discipline).
- **API testing tooling** — Postman/Newman, JSON-path assertions,
  pre/post-scripts, environment variables, parametrized runs.
- **Black-box test design** — ECP/BVA/decision-tables/state-transition/
  pairwise/exploratory; taxonomy кейсов (CRUD-/BVA-/VAL-/NEG-/IDM-/CONC-/CONF-).
- **Test data hygiene** — каждый кейс работает в своём изолированном
  scope (preflight создаёт Account/Project, teardown удаляет).
- **Regression registry** — `CASES-INDEX` (уникальность кейсов), документация
  осознанных by-design отклонений в `docs/architecture/` сервиса.
- **Reading API errors** — diff между ожидаемым контрактом и фактическим
  Kachō response (статус, текст, details) — основная работа; находки →
  GitHub Issue + регрессионный тест.

**Артефакты**

- `kacho-test/` — сводный e2e/regression стенд.
- Per-service Newman: `kacho-vpc/tests/newman/`.
- `docs/architecture/` — записи об осознанных by-design отклонениях.

**С кем работает**

- API Designer — что считать "контракт".
- Backend — где исправлять расхождения.

**AI-соответствие:** `qa-test-engineer` (расширяет Newman regression против
acceptance/спеки), `integration-tester` (конвертит APPROVED-сценарии в падающие
integration+e2e тесты, TDD red), domain-агент `vpc-newman-author`; скил
`testing-product-coach`. Конвенции контракта аудитит domain-агент
`<svc>-conventions-auditor` (error-format/regex/status-mapping/timestamp/
update_mask/sync-vs-async — конвенции Kachō, не сравнение с чужими облаками).

---

## 10. Security / Admin-Boundary Engineer

**Что делает в проекте**

Защищает границу между internal-admin и external-public API. Понимает
почему `/compute/v1/regions` нельзя выставлять на TLS endpoint, как сделать
TLS middleware который блокирует admin paths, как организовать
аудит-логи и (в будущем) IAM. Шире границы методов — следит, чтобы
инфра-чувствительные данные (placement, underlay, wiring, числовой
инфра-id) жили только в `Internal*`-API (`.claude/rules/security.md`).

**Концептуальные скилы**

- **TLS / certificate management** — server certs, mTLS, cert rotation,
  TLS handshake debugging.
- **Authentication patterns** — bearer tokens, IAM tokens, OAuth scopes;
  почему noop-auth годится для dev и нельзя для prod (production-mode →
  anonymous fail-closed).
- **Authorization model** — что такое "admin" vs "user" граница в API
  layer (path-based) vs в service-layer (`InternalIAMService.Check`,
  listauthz-фильтр на `List<Resource>`). Какую защиту обходить нельзя даже
  из-за уязвимости в одном слое.
- **Network segmentation** — почему internal-port (9091) не должен быть
  экспонирован наружу; ingress-only-via-gateway pattern.
- **Audit log discipline** — что логировать (actor, action, resource id,
  timestamp), что **не** логировать (passwords, секреты, PII), как
  обеспечить tamper-evident logs.
- **Threat modeling** — STRIDE: что плохого может сделать клиент с этим
  API, что — admin, что — компрометация одного сервиса (defense-in-depth:
  даже скомпрометированный публичный API не должен раскрыть физическую
  топологию/placement).

**Артефакты**

- TLS-listener middleware + admin-path allowlist в api-gateway (`04-api-gateway-routing.md`).
- `kacho-corelib/audit/`.
- IAM scope в auth_noop → реальный (приходит с интеграцией `kacho-iam`).

**С кем работает**

- Architect — границы доверия.
- API Designer — что Internal, что Public.
- Platform — TLS termination.

**AI-соответствие:** `api-gateway-registrar` (никогда `Internal.*` на external),
поддержка `system-design-reviewer`; CI-гейты `make audit-list-filter`,
`make verify-no-yandex`.

---

## 11. Product Owner / Tech Writer

**Что делает в проекте**

Определяет scope ресурсной модели и конвенций Kachō: что входит в текущую
фазу, что упрощаем, что откладываем в отдельные домены/фазы. Пишет
acceptance-документы Given-When-Then до старта реализации. Поддерживает
`.claude/rules/*.md` и `docs/architecture/*` в актуальном состоянии — это
"документация для следующего разработчика" (включая AI-agent'ов).

**Концептуальные скилы**

- **Domain modeling** — проектировать ресурсную модель и состав полей под
  нужды Kachō (LRO, FieldMask, idempotency-key) в чистой удобной форме, а
  не копируя чужую схему.
- **Scope discipline** — отличать "must-have для текущей фазы" от
  "nice-to-have", резать без сожалений второе.
- **Specification writing** — Given-When-Then для acceptance, без
  размытых "система должна корректно обрабатывать". Каждое условие —
  тестируемое.
- **Architectural decision records (ADR)** — фиксировать "X vs Y, выбрали
  Y, причина Z" — иначе через полгода никто не помнит, почему так.
- **Reading and summarizing code** — для PO/TW важно уметь прочитать
  существующее и переписать концептуально для не-разработчика.
- **Pragmatic prioritization** — балансировать "правильно" vs "сейчас
  работает". Тех-долг не откладывается "на потом" — баг/tech-debt → GitHub
  Issue, фича → APPROVED acceptance + KAC-тикет.

**Артефакты**

- `.claude/rules/*.md` + `CLAUDE.md` (workspace + per-repo).
- `docs/specs/*-acceptance.md`.
- `docs/architecture/*` (этот пакет).
- GitHub Issues (баги/tech-debt) + KAC-тикеты (фичи).

**С кем работает**

- Со всеми. Это hub-роль.

**AI-соответствие:** `acceptance-author` (Given-When-Then до кода),
`acceptance-reviewer` (единственный gate APPROVED).

---

## AI-оснастка: роли как агенты

Проект разрабатывается, тестируется и сопровождается автономно через Claude
Code. Человеческие роли выше реализуются набором **AI-агентов** (роли),
**скилов** (экспертиза), **rules** (правила) и **hooks** (дисциплина).
Полные правила — `.claude/rules/ai-tooling.md`.

**13 generic-агентов** (источник истины — `kacho-workspace/.claude/agents/`):

| Группа | Агенты |
|---|---|
| Исполнение | `acceptance-author`, `proto-sync`, `service-scaffolder`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester` |
| Ревью | `acceptance-reviewer`, `system-design-reviewer`, `db-architect-reviewer`, `go-style-reviewer`, `proto-api-reviewer`, `qa-test-engineer` |

**Domain-агенты** (нативные в своём репо, имя префиксуется доменом):
- kacho-vpc: `vpc-cidr-specialist`, `vpc-outbox-watch-engineer`, `vpc-newman-author`,
  `vpc-load-testing`, `vpc-conventions-auditor` (аудит конвенций Kachō:
  error-format/regex/status-mapping/timestamp/update_mask/sync-vs-async —
  **не** сравнение с чужими облаками).
- kacho-compute: по аналогии (`compute-*` — instance-lifecycle, disk-image,
  `compute-conventions-auditor`, newman-author, load-testing).

**Скилы:** `evgeniy` (Go-архитектура: UseCase, CQRS-порты, self-validating
domain, DTO, `cmd/migrator`), `testing-code-coach` (unit/integration),
`testing-product-coach` (black-box техники), `load-testing-coach` (методология
нагрузки), `<svc>-load-testing` (нагрузочные сценарии сервиса).

**Модель распространения:** оснастка **физически дублируется в каждый**
`project/<repo>/.claude/`, чтобы репо был самодостаточен при standalone-клоне
(CI, свежий checkout). Источник истины — `kacho-workspace/.claude/`; копии
generic-оснастки (rules, 13 generic-агентов, generic-скилы, hooks,
settings.json) генерируются `./sync-tooling.sh` (вшит в `./sync-all.sh`).
Domain-агенты/скилы (`vpc-*`, `compute-*`, `<svc>-load-testing`) — нативные в
своём репо, sync их не трогает. Правка generic-оснастки — **только в workspace**;
копию в репо руками не редактировать (перетрётся при следующем sync).

**Lifecycle-гейты** (ban'ы из `.claude/rules/00-kacho-core.md`): acceptance-first
(APPROVED Given-When-Then) → KAC-тикет + ветка + KAC-trail в vault → контекст из
vault → кросс-репо порядок (proto → corelib → сервис → api-gateway → deploy →
docs) → строгий TDD (RED до кода, integration + newman в том же PR) → ревью
ролями → финальная верификация (`go test ./... -race` + `golangci-lint run` +
`govulncheck` + `make audit-list-filter` + newman) → обновить trail.

---

## Common skills (нужны всем)

Эти скилы не привязаны к роли — без них любой инженер быстро упирается:

- **Reading and writing technical English** — большинство хороших
  материалов и код-комментариев на английском; половина наших комментов —
  гибрид (русский + английские термины).
- **Reading other people's code** — чужой код больше своего; уверенно
  навигировать незнакомый repo, делать "code spelunking" через grep/tree-
  sitter/IDE.
- **Git discipline** — atomic commits, разумные сообщения (Conventional
  Commits), не force-push в main, понимание rebase vs merge.
- **CLI proficiency** — bash/jq/kubectl/curl/psql; уметь отлаживать прод
  через shell, а не только через UI.
- **Reading docs critically** — официальные доки часто устарели или
  неполны; уметь сверять с source.
- **Asking precise questions** — уметь сформулировать "что я хочу,
  что я уже попробовал, что не работает" без лирики.

---

## Quick role assignment matrix

Когда нужно решить кому отдать задачу:

| Задача | Primary | Поддержка |
|---|---|---|
| Новый VPC ресурс с CRUD | Backend | API Designer, Data Modeler |
| Новый internal admin RPC | Backend | API Designer, Security |
| Изменение IPAM cascade | IPAM Engineer | Backend, Data Modeler |
| Новая страница UI | Frontend | API Designer (для path) |
| Новая колонка в таблице UI | Frontend | (только в registry) |
| Новая миграция БД | Data Modeler | Backend (для использования) |
| Зафиксить расхождение с конвенциями контракта | QA | Backend |
| Деплой в новый env | Platform | Architect |
| Прогон newman перед релизом | QA | Backend (если красное) |
| Вынести поле из public в Internal | API Designer | Architect, Security, Backend |
| Поднять стенд после изменения helm | Platform | — |
| Уточнить scope новой фичи | PO/TW | Architect |
| Написать acceptance-doc | PO/TW | Architect |

## Антипаттерны ролевой работы

Чего избегать в команде:

- **"Backend сам решит протокол"** — без API Designer контракт быстро
  превращается в случайность.
- **"Frontend позже"** — UI обнаруживает плохие API-решения. Лучше
  начать рисовать макет вместе с proto.
- **"DBA не нужен, ORM сделает"** — ORM скрывает индексы, EXCLUDE,
  jsonb-операции, и вы проигрываете в performance/корректности (к тому же
  ORM запрещён — только sqlc + handwritten pgx).
- **"PO напишет тикет, разберёмся"** — без acceptance-документа любой
  PR превращается в "вроде это работает".
- **"QA после"** — конформность контракта невозможно проверить пост-фактум,
  тест должен быть в каждом PR (строгий TDD: RED до кода).
- **"Security позже, сейчас MVP"** — admin-paths утечкут на public
  endpoint и через год кто-то найдёт.

---

## Минимальная команда для MVP

3–4 сильных fullstack-инженера + 0.5 PO/TW. Каждый закрывает несколько
ролей, но обязательно должно быть:

1. Один — за **архитектуру + API design + backend lead**.
2. Один — за **frontend + UX**.
3. Один — за **БД + IPAM + платформа**.
4. PO/TW — за **scope + документацию + acceptance**.

QA, security, TUI — на этой стадии распределено по first-three.

С командой 6–8 человек это всё разделяется по ролям выше.
