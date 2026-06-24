# Kachō — Дорожная карта и процесс

**Документ:** 04 / 5

Главы 01–03 описали архитектуру, модель данных и эксплуатацию платформы Kachō. Эта
глава отвечает на вопрос «как мы это строим»: логика фазирования, обязательный
acceptance-first + строгий TDD lifecycle, уровни тестов, текущее состояние и
будущие фазы. Регламент здесь — нормативный: он повторяет non-negotiables из
`.claude/rules/*` применительно к процессу доставки.

## 1. Логика фазирования

Платформа растёт **доменами** (отдельный сервис = отдельная Postgres-БД,
`.claude/rules/polyrepo.md`), а каждый домен — **фазами** под-итераций. Принципы:

- **Один домен — один сервис — одна БД.** Новый домен не подмешивается в чужую
  схему; он получает собственное репо `kacho-<part>` и схему `kacho_<domain>`.
- **Кросс-репо фича топосортируется по build-графу**: `kacho-proto` → `kacho-corelib`
  → сервис(ы) → `kacho-api-gateway` → `kacho-deploy` → `kacho-workspace` (docs).
  Пока вышестоящий PR не в `main`, нижестоящий CI временно пиннит sibling к
  feature-ветке; после merge — обратно на `ref: main`.
- **Кросс-репо эпик** ведётся как tracking-issue в `kacho-workspace` (метка `epic`)
  + per-repo issue с `Blocked by PRO-Robotech/<repo>#<n>`. В трекере KAC — `[EPIC]`
  + Subtask-иерархия (`.claude/rules/git-youtrack.md`).
- **Каждая под-итерация замкнута**: APPROVED acceptance-док → ветка `KAC-<N>` → RED →
  GREEN → review ролями → integration + newman зелёные → trail в vault + перевод
  тикета в `Done`. Без этого под-итерация не считается завершённой.

Под-итерация **не стартует без APPROVED acceptance-дока** (ban #1). Это входной
gate всей работы — детали в §2.

## 2. Acceptance-first + строгий TDD lifecycle

Это **обязательная** последовательность для каждой под-итерации, нового RPC, нового
поля, нового ресурса и для багфикса. Без неё работа не считается начатой.

### 2.1. Шаг 1 — acceptance-документ (Given-When-Then)

Перед любой строчкой кода — `docs/specs/<sub-phase>-acceptance.md` в формате
Given-When-Then. Сценарии формулируются в терминах **текущего контракта Kachō**:
плоский ресурс, мутации возвращают `Operation`, клиент поллит `OperationService.Get`
до `done=true` (Watch RPC не существует).

```markdown
# Sub-phase 0.4 (compute) — Acceptance

## Сценарий: создание Instance с boot_disk

**Given** Project `prj-…` существует (kacho-iam)
**And** Image `fd8…` присутствует в каталоге (status READY)
**And** Subnet `sub-…` создана в Network (kacho-vpc) в зоне `ru-central1-a`

**When** клиент дёргает `POST /compute/v1/instances` с payload:
  - projectId      = "prj-…"
  - name           = "test-vm-01"
  - zoneId         = "ru-central1-a"
  - platformId     = "standard-v3"
  - resourcesSpec  = { cores: 2, memory: "4Gi" }
  - bootDiskSpec   = { diskSpec: { imageId: "fd8…", size: "20Gi", typeId: "network-ssd" } }
  - networkInterfaces[0] = { subnetId: "sub-…" }

**Then** ответ — `Operation` с `id` (prefix `epd`), `done=false`
**And** `GET /compute/v1/operations/{operationId}` в пределах разумного poll-окна → `done=true`
**And** `operation.response` — Instance с `status = RUNNING`, заполненными `id`/`createdAt`
**And** `GET /compute/v1/instances/{instanceId}` возвращает тот же Instance (sync read)
**And** у Instance есть `networkInterfaces[0].primaryV4Address` (IPAM-аллокация в kacho-vpc)

## Negative-сценарий: создание Instance в несуществующем Project

**Given** Project с id `prj-DOESNOTEXIST00000` отсутствует
**When** клиент дёргает `POST /compute/v1/instances` с этим `projectId`
**Then** возвращается ошибка `NOT_FOUND` с message `"Project with id prj-DOESNOTEXIST00000 not found"`
**And** ресурс не создан (cross-domain существование валидируется в worker'е Create
        через `kacho-iam.ProjectService.Get`; peer недоступен → `UNAVAILABLE`, fail-closed)

## Negative-сценарий: Update immutable-поля

**Given** Instance `epd…` существует
**When** клиент дёргает `PATCH /compute/v1/instances/{id}` с `update_mask = "zoneId"`
**Then** возвращается `INVALID_ARGUMENT` с message `"zoneId is immutable after Instance.Create"`
```

Acceptance-документ — **единственный источник истины** для тестов. Изменился кейс —
правка сначала в документе, потом в тестах, потом в коде. В нём нет места устаревшим
конструкциям K8s-envelope (вложенные `spec`/`status`-as-message и служебные поля
версии/жизненного цикла), оптимистичной replace-семантике мутаций, записи `status`
через тело мутации, серверному стриму изменений. Контракт строго плоский: domain-поля
на верхнем уровне, `status` — enum-поле, мутации возвращают `Operation`.

### 2.2. Шаг 2 — gate `acceptance-reviewer`

- `acceptance-author` помечает документ «Draft, на ревью».
- Документ проходит **review агента `acceptance-reviewer`** — это единственный
  владелец вердикта APPROVED (не заказчик). Критерии — в `.claude/agents/acceptance-reviewer.md`.
- Замечания → правка автором → новый раунд. Цикл итеративный, обычно сходится за 1–3
  раунда.
- `✅ APPROVED` = «контракт зафиксирован, можно начинать код».
- Эскалация заказчику — только при (a) ≥3 раундах без сходимости (ambiguity в спеке,
  нужно человеческое решение) либо (b) scope-конфликте acceptance со спекой.

### 2.3. Шаг 3 — конвертация в исполняемые тесты (RED)

Каждый сценарий мапится 1-к-1 на тест. Имена тест-функций соответствуют именам
сценариев — это даёт трассируемость acceptance ↔ test.

```go
func TestInstance_CreateWithBootDisk_OperationCompletesRunning(t *testing.T) { /* Given/When/Then */ }
func TestInstance_CreateInNonExistentProject_ReturnsNotFound(t *testing.T)    { ... }
func TestInstance_UpdateImmutableZone_ReturnsInvalidArgument(t *testing.T)    { ... }
```

`integration-tester` пишет тесты **первыми** и **прогоняет их до кода** — все падают
(RED). Это подтверждает, что тест проверяет реальное поведение, а не опечатку. LRO в
unit-тестах дожидаются детерминированно (`AwaitOpDone`), не `time.Sleep`.

### 2.4. Шаг 4 — реализация до GREEN

Минимальная реализация, чтобы каждый тест прошёл — по одному тесту за раз. Чанк из
нескольких изменений: все падающие тесты пишутся первыми (RED по всем), затем
чиним по одному в GREEN. В PR/отчёте показывается пара «RED → GREEN»; без неё заявлять
о готовности нельзя (ban #12).

Кодинг идёт по чистой архитектуре (`domain ← use-case ← repo/clients/handler`,
`cmd` — composition root) и DB-инвариантам (within-service целостность — только на
уровне Postgres: FK / partial-UNIQUE / EXCLUDE / CHECK / атомарный CAS / xmin-OCC /
`FOR UPDATE SKIP LOCKED`, не software check-then-act). Каждая мутация атомарно пишет
запись в `operations` + транзакционный outbox в той же TX; worker исполняет
state-машину (`.claude/rules/data-integrity.md`).

### 2.5. Шаг 5 — review ролями + рефакторинг

При работающих тестах — рефакторинг (любая регрессия ловится тестами) и review
специалист-агентами per-RPC: `proto-api-reviewer`, `db-architect-reviewer`,
`go-style-reviewer`, `system-design-reviewer`; конвенции — `<svc>-conventions-auditor`.

### 2.6. Шаг 6 — финальная верификация и trail

Перед merge: `go test ./... -race` + `golangci-lint run` + `govulncheck` +
`make audit-list-filter` (каждый public `List` фильтрует через listauthz) + newman
зелёные. После merge — обновить trail в vault (resources/rpc/packages/edges/KAC) и
перевести тикет `Test → Done` со всеми артефактами (PR-URL, лог тестов, кросс-репо
ссылки).

> «План реализации» (декомпозиция APPROVED-дока на файлы/шаги) — опциональный
> вспомогательный артефакт под крупную под-итерацию; источник истины контракта —
> сам acceptance-документ.

## 3. Уровни тестов

Acceptance-документ покрывается **двумя независимыми путями** — integration и
newman-e2e (один сценарий → один integration-тест + один newman-кейс). Это даёт
валидацию с одной точкой истины и два разных слоя поимки регрессий.

| Уровень | Где живёт | Что проверяет | Инфра |
|---|---|---|---|
| **unit** | `internal/apps/kacho/api/<resource>/*_test.go`, `internal/handler/*_test.go` | чистая use-case логика; mock port-интерфейсов (`repomock`/`kachomock`); LRO через `AwaitOpDone` | без БД (мс) |
| **integration** | `internal/repo/*integration_test.go` | SQL-сторона: CRUD, FK/UNIQUE/EXCLUDE/CHECK, outbox-транзакционность, CAS/OCC/SKIP-LOCKED **races** (concurrent goroutines) | testcontainers Postgres 16 |
| **e2e / newman** | `tests/newman/cases/*.py` → `gen.py` → коллекции | black-box через api-gateway (HTTP); ≥1 happy + ≥1 negative на RPC; conformance к acceptance/спеке | поднятый стенд |

Правила, которые держат пирамиду честной:

- Если service-тест требует Postgres — это утечка adapter в use-case (`architecture.md`).
- Concurrent-race-сценарий для любого CAS/UNIQUE/EXCLUDE-пути обязателен на
  integration-уровне (race не ловится unit-тестом — реальный инцидент NIC-attach
  2026-05-14, `.claude/rules/data-integrity.md`).
- Newman/integration-тест, написанный уже **после** кода, — нарушение TDD (даже если
  зелёный). Workflow нового кейса: `validate-cases.py` (уникальность + CASES-INDEX) →
  `gen.py`. Коллекции `collections/*.postman_collection.json` руками не правятся.
- **Test-only PR** (дописать тесты под существующий функционал) не трогает прод-код и
  не содержит TODO/FIXME/`skip` (ban #13). TDD-red против реального бага прода = finding:
  GitHub Issue (`bug` + `verified-by:test`) + аннотация `# verifies <url>` в кейсе.

Методология — skills `testing-code-coach` (unit/integration), `testing-product-coach`
(black-box техники), `load-testing-coach` / `<svc>-load-testing` (нагрузка, k6/ghz).

## 4. Текущее состояние

Базовый control-plane по доменам IAM / VPC / Compute собран; edge и стенд работают.

| Сервис | Состояние | Содержимое |
|---|---|---|
| `kacho-api-gateway` | работает | edge: gRPC-proxy + grpc-gateway REST; two-listener (external TLS + cluster-internal :9091); backend gRPC :9090 |
| `kacho-iam` | в активной работе | Account, Project, User, ServiceAccount, Group, Role, AccessBinding; OIDC + explicit-RBAC authz (per-object материализация, плоский FGA-индекс), cluster-admin, audit-pipeline (эпик AAA) |
| `kacho-vpc` | работает | Network, Subnet, SecurityGroup, RouteTable, Address, Gateway, NetworkInterface; built-in IPAM; `AddressPool` admin-only (Internal*) |
| `kacho-compute` | работает | Instance, Disk, Image, Snapshot, DiskType; reconciler с `pg_advisory_lock` (Geography вынесена в `kacho-geo`, эпик #82) |
| `kacho-geo` | **в работе** (эпик #82) | Region, Zone (Geography — platform-топология, leaf-домен как iam); БД `kacho_geo`; public read + admin-CRUD через Internal* |
| `kacho-deploy` | работает | dev-стенд (kind + helm + Postgres + ingress) + e2e |
| `kacho-ui` | работает | Vite + React SPA control plane (polling-модель: List + OperationService.Get) |
| `kacho-nlb` | **планируется** | NetworkLoadBalancer, TargetGroup; БД `kacho_nlb` |

Поддерживающие репо: `kacho-corelib` (горизонтальные пакеты: `ids`/`errors`/`config`/
`observability`/`db`/`operations`/`outbox`/…), `kacho-proto` (единственный дом всех
`.proto` + сгенерированные stubs), `kacho-vpc-operator` (data-plane sibling VPC,
spec-only, **вне build-графа** control-plane).

**Кросс-доменные runtime-рёбра** (синхронный gRPC service→service, не через api-gateway
наружу; циклов нет):

- `kacho-vpc → kacho-geo` — валидация `zone_id` Subnet/AddressPool (`geo.v1.ZoneService.Get`).
- `kacho-compute → kacho-geo` — валидация `Instance.zone_id` (`geo.v1.ZoneService.Get`).
- `kacho-nlb → kacho-geo` — валидация `region_id` LoadBalancer/TargetGroup (`geo.v1.RegionService.Get`, sync precheck).
- `kacho-nlb → kacho-compute` — резолв Instance-таргетов (`compute.v1.InstanceService.Get`); только Instance, НЕ geography.
- `kacho-compute → kacho-vpc` — валидация NIC-spec (Subnet/SecurityGroup) + IPAM-аллокация Address.
- `* → kacho-iam` — `ProjectService.Get` (existence + account lookup) + `InternalIAMService.Check` (authz-gate); `kacho-geo` — обычный leaf-консумер iam.

> Geography (Region/Zone) вынесена из `kacho-compute` в leaf-сервис `kacho-geo` (эпик #82,
> `docs/specs/sub-phase-6.0-kacho-geo-extraction-acceptance.md`). Ложные «ради geography» рёбра
> `vpc→compute (zone)` и `nlb→compute (region)` удалены; consumer'ы ходят прямо в `geo`. `geo` — leaf
> (как iam): никого, кроме iam (authz-Check), не зовёт, поэтому ацикличность сохранена.

## 5. Будущие фазы

Каждая фаза проходит тот же lifecycle (§2): APPROVED acceptance → TDD → review → trail.
Порядок — по приоритету; внутри фазы детализация под-итераций — отдельные
acceptance-доки `docs/specs/*-acceptance.md`.

### Фаза AAA — IAM, authn/authz, audit (в работе)

- IAM-домен: subjects (User, ServiceAccount, Group), Role (system + custom; единица
  авторизации — `rules[]`), AccessBinding; иерархия владения Account → Project
  (folder/organization в модели нет).
- AuthN: OIDC-федерация (внешний IdP), коротко-живущие токены, principal-propagation
  из JWT в `operations`.
- AuthZ: **explicit RBAC** — грант `(subjects, role, scope)` материализуется
  reconciler'ом в явные **per-object** FGA-tuple внутри границы scope (GLOBAL /
  ACCOUNT / PROJECT); OpenFGA — плоский индекс без hierarchy-каскада. Единственное
  исключение из per-object — cluster super-admin (одно cluster-relation +
  Check short-circuit). Per-RPC Check на каждом мутирующем RPC
  (`InternalIAMService.Check`, peer-call из vpc/compute/geo); публичный `List`
  фильтруется listauthz (CI-гейт). Подробности модели —
  `kacho-iam/docs/architecture/explicit-rbac-model.md`.
- Audit: structured audit-события на каждый мутирующий путь, audit-pipeline-сервис
  поверх транзакционного outbox.
- Транспортная защита: mTLS внутри кластера, TLS на edge.

### Фаза Observability

- Логи (`slog` → агрегатор), метрики (Prometheus + ServiceMonitor), tracing
  (OpenTelemetry SDK → backend).
- Алерты на ключевые сигналы: lag reconciler'а, backlog outbox-drainer'а, ошибки БД,
  длительность операций.

### Фаза HA / Production-readiness

- Postgres replication (primary + реплики) per-сервис; PITR/backup.
- Multi-replica на сервис; reconciler координируется через `pg_advisory_lock` (одна
  реплика обрабатывает операцию — без двойного исполнения).
- Секреты через external-secrets-мост, persistent storage вместо emptyDir, реальный
  ingress с управляемыми сертификатами.

### Фаза расширения доменов

Каждый домен — отдельный сервис/БД/полный цикл. Порядок — по реальному запросу:

- **Load Balancer** (`kacho-nlb`): NetworkLoadBalancer, TargetGroup; БД `kacho_nlb`.
  Cross-domain рёбра: nlb → vpc (Subnet/Address) + nlb → compute (Instance-таргеты),
  nlb → iam (Project). Удаление таргетируемого Instance переживается грациозно
  (dangling-ref → деградированный статус, без cross-service cascade).
- **DNS** (зоны, записи).
- **Object Storage** (S3-совместимый API + control plane).
- Далее по запросу: Managed Databases, Cloud Functions, Container Registry,
  Managed Kubernetes — каждый своим сервисом и фазой.

### Фаза Multi-region

Только когда single-region вырастет: multi-region-топология с межрегиональной
репликацией метаданных control-plane. Архитектурные точки расширения (per-service `operations`,
транзакционный outbox, отсутствие внешнего брокера) зарезервированы заранее, но не
вводятся, пока in-process реализация справляется (ban #7).

---

На этом спека замыкается: глава 00 задаёт scope и принципы, 01–03 — архитектуру,
данные и эксплуатацию, 04 — процесс и дорожную карту. Источник истины по конвенциям
и инвариантам — `.claude/rules/*` и per-repo `docs/architecture/`; эта глава на них
ссылается, а не дублирует.
