# 08 — Roles & Skills

Описание ролей, нужных для разработки такого приклада, и **концептуальных**
скилов под каждую. Не "знать API X", а "понимать концепт Y" — потому что
библиотеки меняются, а понимание остаётся.

В малой команде один человек закрывает несколько ролей; в полной — это
6-8 человек.

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
verbatim-YC parity vs. свобода kacho-only, sync RPC vs. LRO, polling vs.
push, monorepo vs. polyrepo, in-process vs. broker. Эти решения фиксируются
в `CLAUDE.md` как запреты — они потом не пересматриваются от спринта к
спринту.

**Концептуальные скилы**

- **Distributed system design** — понимание stateful vs stateless сервисов,
  database-per-service, async boundaries (LRO, outbox), failure modes
  (network partition, duplicate request, partial commit).
- **Domain decomposition** — где провести шов между сервисами так, чтобы
  большинство изменений оставались внутри одного сервиса. Когда нужен новый
  сервис, когда хватит нового RPC.
- **Read/Write separation patterns** — sync read vs. eventually-consistent
  read, watch/poll trade-off, кеши и TTL, пользовательский UX при отсутствии
  sub-second consistency.
- **Long-Running Operations** — почему мутации возвращают operationID
  вместо результата, как операции связаны с outbox, как избежать "stuck
  worker" и "ghost operations".
- **Backward compatibility & contract evolution** — как добавить поле в
  proto без поломки клиентов, когда нужен новый major version, что делать
  с deprecated методами.
- **Trade-off thinking** — формулировать решения как "X vs Y, Y победил
  потому что Z" в архитектурных доках, а не как догмы.

**Артефакты, за которые отвечает**

- `CLAUDE.md` (workspace + per-repo) — запреты и принципы.
- `docs/architecture/00..07*.md` — этот пакет.
- `docs/specs/sub-phase-*-acceptance.md` — Given-When-Then для крупных
  фич, до начала кода.

**С кем работает**

- API Designer — фиксирует контракты.
- Backend Lead — даёт rationale для слоёв.
- Platform — оркестрация развертывания.
- PO/TW — переводит бизнес-цели в архитектурные ограничения.

---

## 2. API Designer

**Что делает в проекте**

Проектирует proto — публичный (verbatim YC) и internal (kacho-only). Решает
наименование, oneof vs. отдельные RPC, FieldMask vs. явные поля,
RESTful path schema, как ошибки маппятся на gRPC status и HTTP коды.
Поддерживает контракт стабильным — иначе ломаются клиенты.

**Концептуальные скилы**

- **gRPC + Protobuf** — proto3 семантика, oneof, optional, default values,
  почему бинарный wire-format важен, обратная совместимость.
- **REST/HTTP semantics** — методы (POST для create, PATCH для partial
  update, DELETE), status codes, idempotency, custom verbs (`:action`),
  pagination paradigms (cursor vs offset).
- **Error design** — структурированные ошибки (proto `google.rpc.Status` +
  details), различение precondition vs. validation vs. exhausted ресурсов.
  Когда `NotFound` vs `FailedPrecondition` vs `InvalidArgument`.
- **API parity / drop-in compatibility** — что значит "verbatim" другому
  vendor'у: одинаковые тексты ошибок, одинаковые regex, timestamp
  precision. Как тестировать на parity (см. QA).
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
- PO/TW — определяет что именно копируем у YC.

---

## 3. Backend Engineer (Go, Clean Arch)

**Что делает в проекте**

Реализует сервисы. Каждый — `cmd/<svc>/main.go` (composition root) →
`internal/handler` → `internal/service` (port interfaces) → `internal/repo`
+ `internal/clients`. Большинство задач сводится к "добавить поле в proto,
проросить через все слои, мигрировать БД, написать тест". Это рутина —
делается быстро если структура знакома, медленно если нет.

**Концептуальные скилы**

- **Clean Architecture / Hexagonal** — почему domain не знает о pgx,
  почему service определяет порт-интерфейсы, а не использует репо
  напрямую. Когда добавить новый порт vs расширить существующий.
- **Concurrency without ORM/framework** — `context.Context` propagation,
  cancel/timeout/deadline propagation, goroutine lifecycle, sync.Mutex vs
  channels, race conditions detection.
- **Database access без ORM** — typed prepared statements, transaction
  scoping, connection pooling, понимание "что выполнится одной tx, а что
  двумя". Уверенное чтение pg log'ов.
- **Error handling discipline** — sentinel errors + `errors.Is/As`,
  wrapping vs обертка, когда возвращать `nil, err` а когда — обогащать
  domain-info, как не утечь internal-error на клиента.
- **Idempotency** — операции должны выдерживать повторный вызов с тем же
  ID, retry на Unavailable, дедупликация на UNIQUE constraints.
- **Worker / async pattern** — Long-Running Operation: sync создаёт row,
  goroutine крутит работу, обновляет row, клиент полит. Что делать если
  сервис умер посреди работы.
- **Testing discipline** — unit на mock-портах, integration с
  testcontainers, e2e через Newman; знание границ "что покрывать каким
  уровнем".
- **Rejecting unnecessary abstractions** — когда написать `if err != nil`
  и не делать helper, когда не вводить interface, когда не писать generics.

**Артефакты**

- Все `kacho-<svc>/internal/{domain,service,repo,handler,clients}/`.
- `cmd/<svc>/main.go` wiring.
- Unit + integration тесты.
- Per-resource SQL миграции.

**С кем работает**

- API Designer — proto и его маппинг.
- Data Modeler — схема и инварианты.
- QA — где shipped feature ломает контракт.

---

## 4. Data Modeler / Database Engineer

**Что делает в проекте**

Проектирует схемы БД (одна на сервис), constraints, индексы, миграционную
стратегию. Решает где использовать `JSONB` vs нормализованные колонки,
когда добавить EXCLUDE, какие тригеры писать (например, outbox notify).
Гарантирует что **инвариант жив на DB-уровне**, а не только в коде —
потому что код не единственный путь записи.

**Концептуальные скилы**

- **Relational design** — нормализация vs денормализация, FK constraints,
  partial UNIQUE indices, computed columns, trigger semantics.
- **Postgres-specific advanced** — `EXCLUDE USING gist` для no-overlap
  (CIDR, time ranges); `inet/cidr` типы и операторы (`<<`, `>>=`); `JSONB`
  containment (`@>`, `?`, `jsonb_path_ops` GIN индексы); `xmin` для
  optimistic locking; `LISTEN/NOTIFY` для in-process подписки.
- **Migration strategy** — append-only миграции, как не сломать prod
  при rollout (двухфазный schema change: добавить + начать писать +
  миграция данных + переключить чтение + удалить старое).
- **Outbox pattern** — атомарность доменного INSERT и event в одной tx,
  чтобы не было дубликатов или пропусков; почему это лучше чем "после
  commit отправить в queue".
- **Index design** — когда нужен составной индекс vs два отдельных, когда
  partial vs full, когда GIN vs B-Tree.
- **Concurrency at DB level** — что такое serialization anomaly,
  `SELECT ... FOR UPDATE`, advisory locks, deadlock detection, retry-on-
  conflict patterns.
- **Reading EXPLAIN ANALYZE** — без этого нельзя дебажить slow query.

**Артефакты**

- `internal/migrations/*.sql` — все 22 миграции в kacho-vpc.
- ER-документ (`03-ipam.md`).
- Решения по UNIQUE/EXCLUDE/partial-index.

**С кем работает**

- Backend — на каждом новом поле репо.
- IPAM — для CIDR-overlap, computed columns, JSONB queries.
- Architect — для схемы outbox/operations.

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
- **Label-based routing / selector matching** — k8s-style selectors,
  inverse-containment vs containment, equal-specificity tie-break,
  дет. ordering vs admin-controlled priority.
- **Cascade / fallback design** — упорядоченный набор правил с явным
  matched_via для observability; explainability ("почему этот IP, а не
  тот"); runner-up для "что бы было если бы первого не было".
- **Tenant separation** — разница между client-owned (folder→subnet→
  internal IP) и system-owned (pool→external IP, выдаваемый клиенту).
  Cross-tenant lookup только для admin.
- **Exhaustion handling** — `ResourceExhausted` с осмысленным сообщением,
  early warning через utilization metrics, capacity planning hints.
- **NetBox-style observability** — utilization bars, per-CIDR breakdown,
  reverse-lookup от IP к клиенту, прогноз заполнения.

**Артефакты**

- `kacho-vpc/internal/service/address_pool_service.go` — cascade.
- `address_allocate.go` — picker + retry.
- Documentation в `03-ipam.md`.
- Семантика `cloud_pool_selector` — admin переключает routing.

**С кем работает**

- Data Modeler — схема pool/zone/cidr.
- Backend — интеграция в AddressService.
- Frontend — utilization viz.

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
- **Migration discipline** — почему init-container, как не выкатить код
  до миграции, как откатывать.

**Артефакты**

- `kacho-deploy/{kind,helm,Makefile}`.
- Dockerfile'ы во всех сервисах.
- Init container с `migrate up`.

**С кем работает**

- Backend — env vars, health endpoints.
- Architect — границы сервисов в k8s.
- QA — стабильность стенда.

---

## 7. Frontend Engineer (Web)

**Что делает в проекте**

Реализует SPA на React + TS. Большая часть страниц — generic (registry-
driven), пишутся декларативно через `ResourceSpec`. Кастомные страницы
(IPAM utilization, Search) — отдельно. Думает про state management, polling,
форм-валидацию, error UX, breadcrumb-навигацию.

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
  Operation polling до `done=true`, как не "переписать" пользовательский
  ввод во время refetch (snapshot template ref в нашем
  `ResourceFormDialog`).
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

Реализует terminal-admin tool в стиле k9s (`kacho-tui`). Понимает
event-driven UI, cell-based rendering, keyboard navigation, headless
testing. Использует тот же registry, что web-UI, но на Go.

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

- `kacho-tui/internal/{app,api,registry,discovery}/`.
- `tools/snap_png.py` — headless screenshot.

**С кем работает**

- Backend — для admin RPC (через api-gateway REST).
- Frontend (web) — для синхронизации registry-метаданных.

---

## 9. QA / Contract-Test Engineer

**Что делает в проекте**

Гарантирует что verbatim-YC parity не ломается. Пишет Newman-collection
тесты, поддерживает 3-suite split (ro/light/seq) под quota-aware прогон
против реального YC. Знает что такое `pending-parity` registry — перечень
кейсов где Kachō явно расходится с YC.

**Концептуальные скилы**

- **Contract testing vs unit/integration** — что проверяет каждый
  уровень, почему unit не достаточно для verbatim-parity.
- **API testing tooling** — Postman/Newman, JSON-path assertions,
  pre/post-scripts, environment variables, parametrized runs.
- **Quota awareness** — реальный provider имеет rate-limits и квоты;
  тесты должны быть rate-throttled и cleanup-after-each.
- **Test data hygiene** — каждый кейс работает в своём изолированном
  scope (preflight создаёт Org/Cloud/Folder, teardown удаляет в local;
  в prod skip cleanup).
- **Regression registry** — `PARITY.md` с двумя списками (`pending-parity`,
  `kacho-only`); как новый кейс попадает в один из списков.
- **Reading API errors** — diff между YC и Kachō response (статус, текст,
  details) — основная работа.

**Артефакты**

- `kacho-test/` (когда заполнится) — общие сценарии.
- Per-service Newman: `kacho-vpc/newman/`.
- `PARITY.md` — registry расхождений.

**С кем работает**

- API Designer — что считать "контракт".
- Backend — где исправлять расхождения.

---

## 10. Security / Admin-Boundary Engineer

**Что делает в проекте**

Защищает границу между internal-admin и external-public API. Понимает
почему `/vpc/v1/regions` нельзя выставлять на TLS endpoint, как сделать
TLS middleware который блокирует admin paths, как организовать
аудит-логи и (в будущем) IAM.

**Концептуальные скилы**

- **TLS / certificate management** — server certs, mTLS, cert rotation,
  TLS handshake debugging.
- **Authentication patterns** — bearer tokens, IAM tokens, OAuth scopes;
  почему noop-auth годится для dev и нельзя для prod.
- **Authorization model** — что такое "admin" vs "user" границу в API
  layer (path-based) vs в service-layer (role check). Какую защиту
  обходить нельзя даже из-за уязвимости в одном слое.
- **Network segmentation** — почему internal-port (9091) не должен быть
  экспонирован наружу; ingress-only-via-gateway pattern.
- **Audit log discipline** — что логировать (actor, action, resource id,
  timestamp), что **не** логировать (passwords, секреты, PII), как
  обеспечить tamper-evident logs.
- **Threat modeling** — STRIDE: что плохого может сделать клиент с этим
  API, что — admin, что — компрометация одного сервиса.

**Артефакты**

- TLS-listener middleware (TODO в `04-api-gateway-routing.md`).
- `kacho-corelib/audit/` (скелет, заполнить).
- IAM scope в auth_noop → реальный.

**С кем работает**

- Architect — границы доверия.
- API Designer — что Internal, что Public.
- Platform — TLS termination.

---

## 11. Product Owner / Tech Writer

**Что делает в проекте**

Определяет scope: что копируем у YC verbatim, что упрощаем, что добавляем
своё. Пишет acceptance-документы Given-When-Then до старта реализации.
Поддерживает CLAUDE.md и architecture/* в актуальном состоянии — это
"документация для следующего разработчика" (включая AI-agent'ов).

**Концептуальные скилы**

- **Vendor API understanding** — читать чужие API-доки, выделять
  паттерны (LRO, FieldMask, idempotency-key) и переносить на свой
  продукт.
- **Scope discipline** — отличать "must-have для совместимости" от
  "nice-to-have", резать без сожалений второе.
- **Specification writing** — Given-When-Then для acceptance, без
  размытых "система должна корректно обрабатывать". Каждое условие —
  тестируемое.
- **Architectural decision records (ADR)** — фиксировать "X vs Y, выбрали
  Y, причина Z" — иначе через полгода никто не помнит, почему так.
- **Reading and summarizing code** — для PO/TW важно уметь прочитать
  существующее и переписать концептуально для не-разработчика.
- **Pragmatic prioritization** — балансировать "правильно" vs "сейчас
  работает". Когда написать TODO, когда зафиксировать в gotchas, когда
  блокировать merge.

**Артефакты**

- `CLAUDE.md` (workspace + per-repo).
- `docs/specs/sub-phase-*-acceptance.md`.
- `docs/architecture/*` (этот пакет).
- `TODO.md` в каждом репо.
- `PARITY.md` в kacho-vpc.

**С кем работает**

- Со всеми. Это hub-роль.

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
| Новый sidebar пункт TUI | TUI Engineer | (registry sync с web) |
| Новая миграция БД | Data Modeler | Backend (для использования) |
| Зафиксить verbatim-YC расхождение | QA | Backend |
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
  jsonb-операции, и вы проигрываете в performance/корректности.
- **"PO напишет тикет, разберёмся"** — без acceptance-документа любой
  PR превращается в "вроде это работает".
- **"QA после"** — verbatim-parity невозможно проверить пост-фактум, она
  должна быть в каждом PR.
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
