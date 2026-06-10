# 01 — Services

Каждый сервис: роль, RPC, БД, межсервисные зависимости, Clean-Architecture
слои. Только runtime-сервисы — библиотеки/инфра в README.

## Общие конвенции

Все сервисы:
- Слои: `cmd/<svc>/main.go` (composition root) → `internal/handler` (тонкий
  transport) → `internal/service` (бизнес-логика, port interfaces) →
  `internal/repo` (pgx adapter) + `internal/clients` (gRPC adapter).
- DB: один Postgres на сервис (database-per-service), миграции в
  `internal/migrations/*.sql` (goose-style).
- gRPC server из `kacho-corelib/grpcsrv` (recovery, logging interceptors).
- Public-port: `:9090` (gRPC, регистрируется в api-gateway).
- Internal-port: `:9091` (gRPC, **только** `Internal*Service`'ы).
- API-форма: **плоские ресурсы** (flat message с domain-полями на верхнем
  уровне, без envelope `metadata`/`spec`/`status`). `Get`/`List` — sync;
  `Create`/`Update`/`Delete` и domain-действия — async, возвращают `Operation`.
  Клиент поллит `OperationService.Get(id)` до `done=true`. Watch-стриминга нет —
  опрос `List` (интервал 2–5 с).
- Operations: каждая мутация через `kacho-corelib/operations` — sync создаёт
  Operation, async-worker делает работу.
- Outbox: каждая успешная мутация пишет событие в `<svc>_outbox` в той же
  tx; триггер `pg_notify` — wake-up signal для async-worker'а.

## kacho-iam

**Роль**: владеет иерархией владения **Account → Project** и identity/authz-
моделью. Источник правды для существования account/project для всех остальных
сервисов.

**Ресурсы**: Account, Project, User, ServiceAccount, Group, Role, AccessBinding.

**БД**: `kacho_iam` (`pg-iam` StatefulSet).

**Public RPC** (`:9090`):
- `AccountService` (top-level scope): Get/List/Create/Update/Delete,
  ListOperations.
- `ProjectService` (Account scope): Get/List/Create/Update/Delete,
  ListOperations. Все доменные ресурсы (VPC/Compute/NLB) — project-level,
  ссылаются на `project_id`.
- `UserService`, `ServiceAccountService`, `GroupService`, `RoleService`,
  `AccessBindingService`: Get/List/Create/Update/Delete (+ доменные действия
  привязок) — основа AAA-фазы.

**Internal RPC** (`:9091`):
- `InternalIAMService` (authz-gate): `Check` — per-RPC проверка прав
  (vpc/compute/nlb читают caller-identity из metadata
  `x-kacho-project-id`/`x-kacho-admin`/`x-kacho-actor`).

**Особенности контракта**:
- `Project.UNIQUE(account_id, name)`.
- Иммутабельные поля (`account_id` у Project и т. п.) — отвергаются в
  `Update` через `update_mask`-дисциплину (`"<field> is immutable after
  <R>.Create"`).
- FK от потомков RESTRICT внутри `kacho_iam`; cross-service cascade нет.

**Inter-service**:
- Не делает исходящих gRPC к доменным сервисам (leaf-owner иерархии).
- `ProjectService.Get` зовут все доменные сервисы (existence + account lookup);
  `InternalIAMService.Check` — authz-gate на каждый мутирующий RPC.

## kacho-vpc

**Роль**: control plane сетевых ресурсов **+** kacho-only IPAM (Region/Zone-
ссылки + AddressPool). Самый большой сервис.

**Ресурсы**: Network, Subnet, SecurityGroup, RouteTable, Address, Gateway,
NetworkInterface. Admin-only IPAM: AddressPool.

**БД**: `kacho_vpc` (`pg-vpc` StatefulSet).

**Public RPC** (`:9090`):
- `NetworkService`: Get/List (sync) + Create/Update/Delete (async Operation),
  ListSubnets/ListSecurityGroups/ListRouteTables, ListOperations.
- `SubnetService`: + `:addCidrBlocks`/`:removeCidrBlocks` (принимают
  `v4_cidr_blocks` и `v6_cidr_blocks`), ListUsedAddresses. `v4_cidr_blocks`
  **не обязателен** на `Create`.
- `AddressService`: + GetByValue (lookup по IP). Поддержка internal IPv6
  (`internal_ipv6_address`).
- `RouteTableService`, `SecurityGroupService` (+ UpdateRules / UpdateRule +
  auto-default).
- `GatewayService`.
- `NetworkInterfaceService` (NIC — first-class ресурс): Get/List/Create/Update/
  Delete, ListOperations + `:attachToInstance`/`:detachFromInstance` (ставит/
  чистит `used_by`). REST-префикс `/vpc/v1/networkInterfaces`.

**Internal RPC** (`:9091`, kacho-only admin / IPAM):
- `InternalAddressPoolService` — admin CRUD пулов + bindings (network/address
  override) + diagnostics (Check, ExplainResolution) + observability
  (ListAddresses, GetUtilization).
- `InternalNetworkService` — `SetDefaultSecurityGroupId` (computed-field).
- `InternalAddressService` — AllocateInternalIPv4 / AllocateInternalIPv6 /
  AllocateExternalIP.

**Inter-service**:
- → `kacho-iam.ProjectService.Get` — existence check `project_id` в
  Create/Update мутациях + resolve `project_id` для IPAM-cascade
  (project-selector lookup для external Address).
- → `kacho-iam.InternalIAMService.Check` — authz-gate.
- → `kacho-compute.ZoneService.Get` — валидация `zone_id` при `Create` Subnet
  (Geography/Region/Zone — домен kacho-compute).

**Особенности**:
- Inline IPAM: `AddressService` в worker'е дёргает `AddressAllocator`
  (AllocateExternalIP / Internal).
- Inline default-SG creation: `NetworkService` при создании сети сразу создаёт
  `default-sg-<short_net>`.
- `network_id` **не обязателен** на `Create` SecurityGroup — SG может быть
  project-level / не привязан к сети.
- Outbox `vpc_outbox` + `pg_notify('vpc_outbox', sequence_no)` — wake-up signal
  для async-worker'а.
- CIDR overlap защита: `EXCLUDE USING gist` constraint (`subnets_no_overlap_v4/
  v6`).
- AddressPool — admin-only (Internal*), project-level биндинги.
- FK / dependency-цепочка (всё RESTRICT): `NetworkInterface → Address → Subnet
  → Network`. Удаление снизу-вверх с понятным precondition-error на каждом
  уровне.
- IPAM cascade см. подробно в [03-ipam.md](03-ipam.md).
- Публичная проекция NIC/Address — lean (tenant-facing); инфра-данные — только
  через `Internal*`.

**Слои (внутри `internal/`)**:
```
domain/         flat structs (Network, Subnet, Address, AddressPool,
                NetworkInterface, …) — pure Go, без deps
service/        use-cases:
                  AddressPoolService — CRUD pool + bindings + cascade-resolve
                  AddressAllocator   — pure IP picker + retry on UNIQUE
                  NetworkService     — Create+Update+default-SG inline
                  SubnetService      — Create + AddCidrBlocks
                  AddressService     — Create + inline allocator
                  NetworkInterfaceService — CRUD + attach/detach
                  ...
                  ports:
                    AddressPoolRepo, AddressPoolBindingRepo,
                    NetworkInterfaceRepo, …
                    ProjectClient — iam.ProjectService.Get
                    ZoneClient    — compute.ZoneService.Get
repo/           pgx adapter, реализация ports.* + outbox emit.
clients/        gRPC adapter — ProjectClient (iam), ZoneClient (compute).
handler/        RPC handlers (тонкие, делегируют в service).
```

## kacho-compute

**Роль**: control plane виртуальных машин и блочных дисков **+** Geography
(Region/Zone). Содержит reconciler с симулированным lifecycle.

**Ресурсы**: Instance, Disk, Image, Snapshot, DiskType + Geography (Region,
Zone).

**БД**: `kacho_compute` (`pg-compute` StatefulSet).

**Public RPC** (`:9090`):
- `InstanceService`: Get/List (sync) + Create/Update/Delete (async Operation) +
  domain-действия `Start`/`Stop`/`Restart`/`AttachDisk`/`DetachDisk` (тоже
  возвращают Operation). Reconciler симулирует переходы
  `PROVISIONING → RUNNING ⇆ STOPPING → STOPPED ⇆ STARTING → RUNNING; →
  DELETING → terminal` с задержками 5–30 с.
- `DiskService`: lifecycle `CREATING → READY ⇆ ATTACHING/DETACHING` (симул.).
- `ImageService`: read-only catalog (родительские образы), seed, всегда
  `READY`.
- `SnapshotService`: lifecycle `CREATING (progress%) → READY` (симул.).
- `DiskTypeService`: read-only справочник.
- `RegionService` / `ZoneService` — **public read** (`Get`/`List`) Geography;
  admin CRUD — через `Internal*`-сервисы на `:9091`. REST-префиксы
  `/compute/v1/regions`, `/compute/v1/zones`.

**Internal RPC** (`:9091`):
- `InternalRegionService` / `InternalZoneService` — admin CRUD регионов/зон
  (Zone FK на регион). Инфра-данные Geography — только здесь.

**Cross-service validation при Create Instance**:
- `project_id` → `kacho-iam.ProjectService.Get` (existence) +
  `InternalIAMService.Check` (authz).
- `boot_disk.disk_id` → same-DB FK на `disks`.
- `network_interfaces[].subnet_id` / `security_group_ids` → `kacho-vpc`
  (валидация NIC-spec); IPAM-аллокация Address через
  `AddressService`/`InternalAddressService`.

**Reconciler**: фоновая горутина опрашивает БД на ресурсы с pending-переходом,
берёт `pg_advisory_lock` на `resource_id` (защита multi-replica), выполняет
симулированный переход (`time.Sleep`, реального гипервизора нет),
транзакционно обновляет `status` + outbox-event. Eventually-consistent.

## kacho-nlb

**Роль**: control plane Network Load Balancer (L4).

**Ресурсы**: NetworkLoadBalancer, TargetGroup.

**БД**: `kacho_nlb` (`pg-nlb` StatefulSet).

**Public RPC** (`:9090`):
- `NetworkLoadBalancerService`: Get/List (sync) + Create/Update/Delete (async
  Operation). Lifecycle `CREATING → ACTIVE`. Listeners и attached
  target-groups — inline-поля ресурса.
- `TargetGroupService`: Get/List + Create/Update/Delete. Lifecycle
  `CREATING → READY`.

**Cross-service validation**:
- `project_id` → `kacho-iam.ProjectService.Get` + `InternalIAMService.Check`.
- NLB → `attached_target_groups[].target_group_id` → same-DB FK.
- TargetGroup → `targets[].subnet_id` → `kacho-vpc`;
  `targets[].instance_id` → `kacho-compute` (валидация target).

> Статус: `kacho-nlb` планируется (отдельная доменная фаза). Архитектурные
> точки расширения зарезервированы; control-plane его не блокирует.

## kacho-api-gateway

**Роль**: edge, REST → gRPC, два listener'а (cluster-internal vs external TLS).

**Не имеет своей БД**. Stateless.

**Listener'ы** (`cmd/api-gateway/main.go`):
- `:8080` — plain HTTP/cmux. Cluster-internal (UI, port-forward, admin-tooling).
- `:8443` — TLS HTTPS/cmux (advertised external endpoint для внешних клиентов).

**Mux** (`internal/restmux/mux.go`):
- grpc-gateway-ServeMux с `runtime.JSONPb`: camelCase + EmitUnpopulated.
- Регистрирует `<Service>HandlerFromEndpoint` для всех public-сервисов:
  - IAM (`AccountService`, `ProjectService`, …) → `iam.kacho.svc:9090`.
  - VPC public-сервисы → `vpc.kacho.svc:9090`.
  - Compute public-сервисы (включая public read Geography) →
    `compute.kacho.svc:9090`.
- Регистрирует **`Internal*` admin** → backend `:9091` **только** на
  cluster-internal mux:
  - VPC: `InternalAddressPoolService` → `vpc.kacho.svc:9091`.
  - Compute: `InternalRegionService`/`InternalZoneService` →
    `compute.kacho.svc:9091`.
  - см. [04-api-gateway-routing.md](04-api-gateway-routing.md).
- `OperationService` через `opsproxy` (in-process, fan-out на нужный backend по
  operation-ID prefix).

**Дисциплина Internal-vs-external**: `Internal*`-сервисы и инфра-
чувствительные admin-пути (`/vpc/v1/addressPools`, `/compute/v1/regions`,
`/compute/v1/zones`, …) **не** публикуются на TLS-listener — только
cluster-internal mux (ответственность — агент `api-gateway-registrar`).

## kacho-corelib

**Роль**: переиспользуемые пакеты. Не сервис, библиотека.

**Пакеты**:
- `ids/` — `NewID(prefix string)` — 3-char prefix + 17-char crockford-base32.
- `errors/`, `config/`, `observability/` (slog + json), `db/` (pgxpool +
  transactor), `grpcsrv/`, `grpcclient/`.
- `outbox/`, `selector/`, `filter/`.
- `operations/` — Operations table + Worker + Repo. Каждая мутация =
  Create Operation → `Run(ctx, op, fn)` крутит worker, переводит
  `done=true` с response/error.
- `auth/`, `authz/` — caller-identity-носитель + authz-gate-клиент.
- `retry/`, `shutdown/`, `backoff/` — gRPC retry на Unavailable + graceful
  shutdown.
- `validate/` — `corevalidate.ResourceID`/`UpdateMask`/`PageSize`.
- `migrations/common/` — общие миграции (`operations`,
  `operations_sequence`) → `make sync-migrations` копирует в каждое сервисное
  репо.
- `audit/` — `AuditLogger` (скелет под IAM).

## kacho-ui

**Stack**: Vite + React + TypeScript + TanStack Query + tailwind + shadcn/ui.

**Архитектура**: registry-driven generic-pages.

- `src/lib/resource-registry.ts` — `REGISTRY: Record<id, ResourceSpec>`.
  Spec содержит: apiPath, payloadKey, columns, fields (FormField[]),
  template, sanitize, scope (`account|project|global`).
- `ResourceListPage` — generic table + polling (3 с) + filter + actions.
- `ResourceDetailPage` — generic flat-view + edit/delete + Operations-поллинг
  (`OperationService.Get` до `done`).
- `ResourceFormDialog` — generic Create/Edit с FieldRenderer (string, text,
  enum, ref, array, bool, sg-rules custom).
- Custom pages **только для admin IPAM/Geography**: `AddressPoolDetailPage`
  (utilization + addresses + reverse-lookup project), `SubnetDetailPage`
  (utilization + per-CIDR), `SystemSearchPage` (cross-resource поиск).
- `IpamUtilizationBar` + `CIDRBreakdown` — переиспользуемые viz-компоненты.

**Routes**:
- `/accounts`, `/accounts/:accountId/projects`,
  `/projects/:projectId/{networks|subnets|addresses|route-tables|
  security-groups|network-interfaces}`.
- `/system/{regions|zones|address-pools|search}` — admin (только
  cluster-internal; см. `security.md` ban #6).

**Sidebar**: 2 группы — домены (project-scoped, disabled когда project не
выбран) + System (global admin).

## kacho-deploy

**Роль**: инфра для dev — kind cluster + helm umbrella.

- `kind/kind-config.yaml` — single-node, port-forward.
- Helm umbrella с зависимостями: postgres-per-service (iam, vpc, compute),
  ingress-nginx (для UI / api-gateway).
- Init container `migrate up` для каждого сервиса (отдельный `cmd/migrator`).

**Команды**:
- `make dev-up` / `make dev-down` — kind+helm, ждёт ready.
- `make reload-svc SVC=<vpc|compute|iam>` — docker build →
  `kind load docker-image` → `kubectl rollout restart`.
- `make logs-svc SVC=…`, `make psql SVC=…`.

## kacho-vpc-operator

**Роль**: data-plane sibling VPC — **spec-only**, вне build-графа.
Control-plane его не касается (общение control-plane'а — только по API между
своими сервисами).

- Будущий SRv6/SDN data-plane.
- Spec и проектные документы — в собственном репо (`docs/specs/`).

## kacho-test

**Роль**: сводный e2e/regression стенд через Newman (только HTTP через
api-gateway, black-box).

- Декларативные `cases/*.py` → `gen.py` → Postman-коллекции.
- Каждый кейс ≥1 happy + ≥1 negative; мутации проверяются через поллинг
  `OperationService.Get` до `done`.
- `environments/local.postman_environment.json`.

Подробно — `project/kacho-test` и `tests/newman/` соответствующих сервисов.
