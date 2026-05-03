# Kachō — Дорожная карта и фазирование

**Документ:** 04 / 5

## 1. Логика фазирования

«Текущая фаза» (Bootstrap) описанная в этой спеке слишком велика для одной волны реализации. Разбиваем на 7 sub-итераций. Каждая sub-итерация:

- Начинается с **acceptance-документа на человеко-читаемом языке** (см. §3 ниже), который **утверждается заказчиком до старта кода**.
- Получает свой план реализации (`docs/plans/<sub-phase>-<topic>.md`).
- Реализуется TDD-стилем: тесты пишутся первыми (по acceptance-кейсам), потом код.
- Завершается работающим e2e-сценарием через `grpcurl`.
- Проходит code-review через `superpowers:requesting-code-review` или специализированных агентов.
- Не считается завершённой без integration-тестов и e2e smoke в `kacho-deploy/e2e/`.

Каждая sub-итерация выполняется по дисциплине `superpowers:test-driven-development` + `superpowers:executing-plans` или `superpowers:subagent-driven-development`.

## 2. TDD / BDD workflow per sub-phase

Это **обязательная** последовательность для каждой sub-итерации, нового RPC, нового ресурса. Без неё работа не считается начатой.

### Шаг 1. Acceptance-документ на человеко-читаемом языке

Перед любой строчкой кода — `docs/specs/sub-phase-<X.Y>-<topic>-acceptance.md` в формате Given-When-Then:

```markdown
# Sub-phase 0.4 (compute) — Acceptance

## Сценарий: создание VM с bootDisk

**Given** Folder `default` существует в default-cloud
**And** Image `ubuntu-2204-lts` присутствует в каталоге
**And** Network `internal-net` создана в этом Folder
**And** Subnet `internal-net-subnet-a` создана в Network с CIDR `10.0.0.0/24`

**When** клиент дёргает `POST /v1/compute/instances/upsert` с payload:
  - metadata.name = "test-vm-01"
  - metadata.folderId = <default-folder-uid>
  - spec.platformId = "standard-v3"
  - spec.zoneId = "kacho-zone-a"
  - spec.resources.cores = 2, memory = "4Gi"
  - spec.bootDisk.diskId = <newly-created-disk-uid>
  - spec.networkInterfaces[0].subnetId = <subnet-uid>
  - spec.desiredPowerState = "RUNNING"

**Then** ответ содержит ресурс с заполненными metadata.uid, creationTimestamp, resourceVersion
**And** status.state = "PROVISIONING" в первом ответе
**And** в течение 60 секунд через Watch приходит событие MODIFIED с status.state = "RUNNING"
**And** status.ips.internal не пустой
**And** status.lastTransitionAt больше creationTimestamp

## Сценарий: попытка создания VM в несуществующем Folder
...

## Сценарий: restart VM
**Given** VM `test-vm-01` в состоянии RUNNING
**When** клиент дёргает `POST /v1/compute/instances/restart` с metadata.uid = <uid>
**Then** ответ содержит ресурс с заполненным metadata.restartedAt
**And** через Watch приходят события: MODIFIED (RESTARTING) → MODIFIED (RUNNING)
**And** status.lastRestartCompletedAt равен metadata.restartedAt

## Negative-сценарий: writing status через upsert
**Given** VM `test-vm-01` существует
**When** клиент дёргает `/upsert` с status.state = "STOPPED" в payload
**Then** ответ — INVALID_ARGUMENT с RequestInfo и BadRequest.field_violations[0].field = "status"
```

### Шаг 2. Валидация acceptance-документа

- Pull request с acceptance-документом проходит **review заказчика** (вы) **до** старта кода.
- Замечания → правки документа → новый раунд review.
- Approve = «можно начинать код, контракт зафиксирован».

Acceptance-документ — это **источник истины** для тестов. Если кейс изменился — изменения сначала в документе, потом в тестах, потом в коде.

### Шаг 3. Конвертация в исполняемые тесты

Для каждого сценария — соответствующий тест на Go. Тесты мапятся 1-к-1 на сценарии acceptance-документа:

```go
// internal/service/instance_acceptance_test.go
func TestInstance_CreateWithBootDisk_TransitionsToRunning(t *testing.T) {
    // Given (setup из acceptance-сценария)
    // When (RPC call)
    // Then (assertions)
}

func TestInstance_CreateInNonExistentFolder_ReturnsInvalidArgument(t *testing.T) { ... }

func TestInstance_Restart_PropagatesViaWatch(t *testing.T) { ... }

func TestInstance_UpsertWithStatus_ReturnsInvalidArgument(t *testing.T) { ... }
```

Имена тест-функций соответствуют именам сценариев — это даёт **трассируемость** acceptance ↔ test.

### Шаг 4. Тесты падают (red)

Запускаем — все тесты fail (нет реализации). Это подтверждает, что тесты реально проверяют что-то.

### Шаг 5. Implement minimum to pass (green)

Минимальная реализация, чтобы каждый тест прошёл. По одному тесту за раз — `superpowers:test-driven-development` дисциплина.

### Шаг 6. Refactor

Убираем дублирование, улучшаем структуру кода **при работающих тестах**. Любое регрессивное изменение ловится тестами.

### Шаг 7. e2e через grpcurl

Тот же набор сценариев из acceptance-документа реализуется как bash-скрипты в `kacho-deploy/e2e/<sub-phase>/<scenario>.sh`. Это финальная проверка — реальный gRPC через api-gateway против работающего сервиса в kind.

### Уровни тестов и их назначение

| Уровень | Где живёт | Что проверяет | Длительность |
|---|---|---|---|
| Unit | `internal/<pkg>/*_test.go` | чистая логика без БД | мс |
| Integration | `internal/service/*_acceptance_test.go` + testcontainers-Postgres | RPC handler + repo + outbox в одной транзакции | секунды |
| E2E (smoke) | `kacho-deploy/e2e/<sub-phase>/*.sh` | реальный gRPC через api-gateway против kind | минуты |

**Acceptance-документ покрывается тестами Integration-уровня и Е2Е-уровня одновременно** (один acceptance-сценарий → один integration-тест + один e2e-bash-сценарий). Это даёт два независимых пути валидации с одной point-of-truth.

## 3. Sub-итерации текущей фазы

### Sub-итерация 0.1 — Bootstrap (foundation)

**Скоуп:**
- `kacho-workspace`-репо: CLAUDE.md, .claude/agents/*.md, .claude/settings.json, bootstrap.sh, sync-all.sh, go.work.example, README.md.
- `kacho-proto`-репо: каркас (`buf.yaml`, `buf.gen.yaml`, Makefile, gen/-структура), пока без proto-файлов конкретных сервисов. Только common-типы: ResourceMeta-helper, Selector, FieldSelector, ResourceRef, эвенты Watch.
- `kacho-corelib`-репо: ids/ (UUID), errors/, db/ (pool, transactor), config/, grpcsrv/, observability/. Без watch/ и outbox/ (это в 0.2).
- `kacho-deploy`-репо: kind/, helm/umbrella/ скелет, ingress, postgres-charts. Без сервисных deps (добавятся по мере появления).
- Скрипт `make dev-up` — поднимает kind с пустым кластером + ingress + 4 пустых Postgres-инстанса (БД созданы, схем нет).

**Acceptance:**
- `cd cloud-demo && git clone .../kacho-workspace && ./kacho-workspace/bootstrap.sh` клонирует все репо как заглушки.
- `cd kacho-deploy && make dev-up` поднимает кластер за < 5 минут.
- `kubectl get pods -n kacho` показывает 4 ready postgres-инстанса.
- `~/.claude/CLAUDE.md` ничего не трогает; новый chat в `cloud-demo/` видит workspace-CLAUDE.md и агентов.

### Sub-итерация 0.2 — Resource Manager + Watch infrastructure

**Скоуп:**
- `kacho-corelib/watch/` — In-process Watch Hub с outbox-чтением, NOTIFY wake-up, ring buffer, fan-out.
- `kacho-corelib/outbox/` — wrapper над transactor для атомарной записи resource + event.
- `kacho-corelib/selector/` — парсер FieldSelector + LabelSelector, генератор SQL-WHERE.
- `kacho-corelib/migrations/common/` — `resource_events` table, `resource_version_seq`, cleanup-функция.
- `kacho-proto/proto/kacho/cloud/resourcemanager/v1/` — Organization, Cloud, Folder с RPC: Upsert, Delete, List, Watch.
- `kacho-resource-manager`-репо: реализация (cmd, internal/service, internal/repo, миграции, deploy/).
- bootstrap данных: при первом старте создаётся default Org → Cloud → Folder.

**Acceptance:**
- `grpcurl -plaintext api.kacho.local:80 kacho.cloud.resourcemanager.v1.OrganizationService/List` возвращает default-org.
- `Upsert` создаёт Cloud в default-Org → `List` показывает.
- `Watch` стрим получает `ADDED` event при `Upsert`, `MODIFIED` при изменении labels, `DELETED` при `Delete`.
- Watch с устаревшим `resourceVersion` получает `Gone 410`.
- Integration-тест на testcontainers-Postgres проверяет атомарность outbox+resource в транзакции.

### Sub-итерация 0.3 — VPC

**Скоуп:**
- `kacho-proto/proto/kacho/cloud/vpc/v1/` — Network, Subnet, SecurityGroup, SecurityGroupRule, RouteTable, StaticRoute, Address. Все RPC + internal Exists.
- `kacho-vpc`-репо: реализация. Без reconciler-а (lifecycle минимальный, переходы синхронные).
- Cross-service validation: vpc → resource-manager (`Folder.Internal.Exists`).

**Acceptance:**
- Создание Network, потом Subnet с указанием networkId.
- Удаление Network с зависимым Subnet → `FAILED_PRECONDITION` с указанием blockers.
- Watch на Subnet показывает события при их создании.

### Sub-итерация 0.4 — Compute (с reconciler-ом)

**Скоуп:**
- `kacho-proto/proto/kacho/cloud/compute/v1/` — Instance, Disk, Image, Snapshot. Все RPC + Restart + internal.
- `kacho-compute`-репо: реализация **с reconciler-ом**. Симулированный lifecycle Instance (5–30с задержки). Симулированный disk attach. Симулированный snapshot progress.
- Seed-таблицы: zones, disk_types, platforms, images_catalog (`0002_seed_catalogs.sql`).
- Cross-service: compute → resource-manager + compute → vpc (subnet validation).
- Finalizer на Instance: `compute.kacho.io/disk-detach`.

**Acceptance:**
- Создание Instance с bootDisk + secondaryDisks → видны переходы PROVISIONING → RUNNING через Watch.
- `Restart` на Instance → видна цепочка событий через Watch (RESTARTING → RUNNING) + `status.lastRestartCompletedAt = metadata.restartedAt`.
- `spec.desiredPowerState = STOPPED` → reconciler переводит status → STOPPED.
- Удаление Instance с прикреплённым Disk: finalizer срабатывает, диск отвязывается, потом Instance удаляется.

### Sub-итерация 0.5 — Load Balancer

**Скоуп:**
- `kacho-proto/proto/kacho/cloud/loadbalancer/v1/` — NetworkLoadBalancer, TargetGroup. Все RPC.
- `kacho-loadbalancer`-репо: реализация с reconciler-ом.
- Cross-service: loadbalancer → resource-manager + loadbalancer → vpc + loadbalancer → compute.
- Finalizer на Instance: `loadbalancer.kacho.io/target-deregister`.

**Acceptance:**
- Создание TargetGroup с targets, ссылающимися на существующие Instance + Subnet.
- Создание NetworkLoadBalancer с listenerами + attachedTargetGroups.
- Удаление Instance, входящего в TargetGroup: finalizer вычищает target из группы.

### Sub-итерация 0.6 — API Gateway (соединяем всё)

**Скоуп:**
- `kacho-api-gateway`-репо: реализация.
- gRPC-proxy через `mwitkow/grpc-proxy`.
- REST mux через grpc-gateway, регистрирующий все 4 сервиса.
- `cmux` для разделения gRPC и REST на одном порту.
- Allowlist-фильтр: `Internal.*` методы НЕ маршрутизируются.
- Health probes, request-id, recovery, slog access log.
- Ingress в helm/umbrella/ привязан к api-gateway.

**Acceptance:**
- `grpcurl -plaintext api.kacho.local:80 ... InstanceService/Upsert` работает (раньше шли напрямую на сервис, теперь через gateway).
- `curl -X POST http://api.kacho.local/v1/instances/list -d '{}'` работает (REST через grpc-gateway).
- Попытка дёрнуть `/v1/instances/upd-status` снаружи возвращает `NotFound` (отфильтровано allowlist-ом).

### Sub-итерация 0.7 — End-to-end (smoke + docs)

**Скоуп:**
- `kacho-deploy/e2e/`-набор bash-скриптов на grpcurl: создаёт полный сценарий «Org → Cloud → Folder → Network → Subnet → Instance → NLB», верифицирует через List/Watch.
- CI (GitHub Actions) запускает e2e на kind в matrix-job.
- Документация в каждом репо: обновлённый CLAUDE.md, README, примеры grpcurl-команд.
- Финальный smoke-pass.

**Acceptance:**
- `make e2e-test` зелёный.
- CI всех репо зелёный.
- README в `kacho-workspace` содержит «как поднять стенд за 5 минут».

## 4. Будущие фазы (вне scope текущей)

Каждая получит свой brainstorming → spec → plan → implementation цикл.

### Фаза 1 — AAA (auth, authorization, audit)

- IAM: subjects (User, ServiceAccount), federation через OIDC, выдача коротко-живущих токенов.
- Authorization: role-based access control привязанный к иерархии Org/Cloud/Folder.
- Audit: structured audit-events emitted каждым сервисом, отдельный `kacho-audit`-сервис с outbox (тот же Watch-механизм поверх своих событий).
- mTLS внутри cluster (cert-manager + per-service Certificate, монтируется в pod).
- TLS на edge через ingress.
- gRPC interceptor в каждом сервисе для проверки subject + permissions.

### Фаза 2 — Production observability

- Loki + Grafana для логов.
- Prometheus + ServiceMonitor (раскомментировать заглушки).
- Tempo для tracing.
- Алерты на ключевые метрики (reconciler lag, watch backlog, БД ошибки).

### Фаза 3 — HA / Production-readiness

- Postgres replication (primary + replicas) per-сервис.
- Multi-replica для каждого сервиса с advisory-lock-координацией reconciler-ов.
- External Secrets Operator + Vault.
- PVC вместо emptyDir.
- Real ingress с cert от Let's Encrypt.
- Backup/PITR для Postgres.
- Multi-zone топология (когда появится k8s-cluster с zonal nodes).

### Фаза 4 — Расширение Watch-инфраструктуры

Только если упрёмся в лимиты in-process Watch Hub. Триггер: > 100k concurrent watchers, > 10k events/sec на сервис.

- Добавление NATS JetStream между outbox и Watch Hub.
- Watch Hub становится тонким адаптером NATS → gRPC stream.
- Outbox остаётся как источник истины + recovery-буфер publisher-а.
- API контракт не меняется.

### Фаза 5 — Дополнительные домены (последовательно)

Каждый — свой полный цикл:
- DNS (zones, records).
- Object Storage (S3-compatible API + control plane).
- Managed Databases (PostgreSQL, ClickHouse, Redis).
- Cloud Functions (serverless runtime).
- Container Registry (OCI registry + control plane).
- Managed Kubernetes (control plane для k8s-кластеров).

Порядок — по реальному запросу пользователей платформы.

### Фаза 6 — Multi-region

Только когда single-region вырастет: multi-region active-active с CockroachDB или sharded Postgres + cross-region replication для metadata.

## 5. Что обязательно делать перед каждой sub-итерацией

1. **Brainstorm** для уточнения деталей (`superpowers:brainstorming`), если в этой спеке не хватает конкретики.
2. **Spec** в `kacho-workspace/docs/specs/sub-phase-X.Y-<topic>.md`.
3. **Acceptance-документ** в `kacho-workspace/docs/specs/sub-phase-X.Y-<topic>-acceptance.md` в формате Given-When-Then (см. §2). **Утверждается заказчиком до старта кода.**
4. **Plan** в `kacho-workspace/docs/plans/sub-phase-X.Y-<topic>-plan.md` (`superpowers:writing-plans`). План пишется **после approve acceptance-документа** и опирается на него: каждый шаг плана связан с одним или несколькими сценариями.
5. **Worktree** через `superpowers:using-git-worktrees` для изоляции (особенно если работают несколько потоков).
6. **TDD** через `superpowers:test-driven-development` — конвертация acceptance-сценариев в исполняемые тесты, потом код. Без сюрпризов: контракт зафиксирован на шаге 3.
7. **Code review** через `superpowers:requesting-code-review` + кастомные специалист-агенты.

## 6. Что обязательно делать после каждой sub-итерации

1. **Все сценарии из acceptance-документа** покрыты integration-тестами и e2e-bash-сценариями, оба зелёные.
2. CI на каждом затронутом репо зелёный.
3. README/CLAUDE.md обновлены.
4. `kacho-workspace/docs/specs/CHANGELOG.md` пополнен.
5. Тег версии: `kacho-<svc>:0.<sub-phase>.0` (например, `kacho-resource-manager:0.2.0`).

## 7. Декомпозиция в подплан

Когда переходим к sub-итерации 0.1 (Bootstrap):
- Brainstorm не нужен (в этой спеке всё детализировано).
- **Шаг 1 — acceptance-документ** `sub-phase-0.1-bootstrap-acceptance.md` в формате Given-When-Then. Утверждается заказчиком.
- **Шаг 2 — `superpowers:writing-plans`** с acceptance-документом + этой спекой как входом. План связывает каждый сценарий со списком конкретных файлов для создания.
- **Шаг 3 — реализация** через `superpowers:executing-plans` или `superpowers:subagent-driven-development`. TDD-дисциплина: каждый сценарий сначала становится падающим тестом, потом проходящим.
