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
- Operations: каждая мутация через `kacho-corelib/operations` — sync создаёт
  Operation, async-worker делает работу.
- Outbox: каждая успешная мутация пишет событие в `<svc>_outbox` в той же
  tx; триггер `pg_notify` → `Internal*WatchService` стримит подписчикам.

## kacho-resource-manager

**Роль**: владеет иерархией Organization → Cloud → Folder. Источник правды
для существования folder/cloud/org для всех остальных сервисов.

**БД**: `kacho_resourcemanager` (sb-config: `pg-resource-manager` StatefulSet).

**Public RPC** (verbatim YC):
- `OrganizationService` (Cluster scope): Get/List/Create/Update/Delete,
  ListOperations.
- `CloudService` (Org scope): Get/List/Create/Update/Delete, Move,
  ListOperations.
- `FolderService` (Cloud scope): Get/List/Create/Update/Delete, Move,
  ListAccessBindings/SetAccessBindings/UpdateAccessBindings (stub).

**Особенности контракта**:
- `Cloud.UNIQUE(organization_id, name)` — миграция 0007.
- `Folder.cloud_id` — иммутабельно через Update; Move → отдельный RPC.
- Hard-delete; FK от потомков RESTRICT (нельзя удалить Cloud с Folder'ами).

**Inter-service**:
- Не знает ни о чём другом. Не делает исходящих gRPC.
- Outbox `rm_outbox` — наблюдают (потенциально) другие сервисы.

## kacho-vpc

**Роль**: VPC ресурсы (verbatim YC) **+** kacho-only IPAM (Region/Zone/Pool).
Самый большой сервис.

**БД**: `kacho_vpc` (`pg-vpc` StatefulSet).

**Public RPC** (verbatim YC): `:9090`
- `NetworkService` (10): Get/List/Create/Update/Delete, ListSubnets,
  ListSecurityGroups, ListRouteTables, ListOperations, Move.
- `SubnetService` (11): + AddCidrBlocks/RemoveCidrBlocks, Relocate,
  ListUsedAddresses.
- `AddressService` (9): + GetByValue (lookup по IP).
- `RouteTableService` (7), `SecurityGroupService` (9): UpdateRules /
  UpdateRule + auto-default.
- `GatewayService` (7), `PrivateEndpointService` (6).

**Internal RPC** (kacho-only): `:9091`
- `InternalRegionService` (5) — admin CRUD регионов.
- `InternalZoneService` (5) — admin CRUD зон (FK на регион).
- `InternalAddressPoolService` (13) — admin CRUD пулов + bindings (network/
  address override) + diagnostics (Check, ExplainResolution) + observability
  (ListAddresses, GetUtilization).
- `InternalCloudService` (3) — admin SetPoolSelector/Unset/Get на Cloud.
- `InternalNetworkService` (1) — `SetDefaultSecurityGroupId` (computed-field).
- `InternalAddressService` (3) — AllocateInternalIP/AllocateExternalIP +
  legacy SetIP.
- `InternalWatchService` (1) — outbox stream через LISTEN/NOTIFY.

**Inter-service**:
- → `kacho-resource-manager.FolderService.Get` — для:
  - existence check `folder_id` в Create/Update мутациях (verbatim YC text
    `"Folder with id X not found"`);
  - resolve `folder_id → cloud_id` для IPAM cascade Step 3 (cloud-selector
    lookup для external Address).

**Особенности**:
- Inline IPAM: AddressService.doCreate **в worker'е** дёргает `AddressAllocator.AllocateExternalIP/Internal` — было выкинуто из отдельного
  `kacho-vpc-controllers` процесса (он удалён, см. CLAUDE.md kacho-vpc).
- Inline default-SG creation: NetworkService.doCreate сразу создаёт `default-sg-<short_net>`.
- Outbox `vpc_outbox` + `pg_notify('vpc_outbox', sequence_no)` для Watch.
- CIDR overlap защита: `EXCLUDE USING gist` constraint (`subnets_no_overlap_v4/v6`, миграция 0007).
- AddressPool — глобальный (нет folder/cloud/org); Region/Zone — глобальные.
- IPAM cascade см. подробно в [03-ipam.md](03-ipam.md).

**Слои (внутри `internal/`)**:
```
domain/         flat structs (Network, Subnet, Address, AddressPool,
                Region, Zone, CloudPoolSelector, …) — pure Go, без deps
service/        use-cases:
                  AddressPoolService — CRUD pool + bindings + cascade-resolve
                  AddressAllocator   — pure IP picker + retry on UNIQUE
                  NetworkService     — Create+Update+default-SG inline
                  SubnetService      — Create + AddCidrBlocks + Relocate
                  AddressService     — Create + inline allocator
                  RegionService, ZoneService — admin CRUD
                  ...
                  ports:
                    AddressPoolRepo, AddressPoolBindingRepo,
                    CloudPoolSelectorRepo, RegionRepo, ZoneRepo, …
                    FolderClient — resourcemanager.Folder.Get
repo/           pgx adapter, реализация ports.* + outbox emit.
clients/        gRPC adapter — FolderClient (resourcemanager).
handler/        RPC handlers (тонкие, делегируют в service).
```

## kacho-api-gateway

**Роль**: edge, REST → gRPC, два listener'а (cluster vs external TLS).

**Не имеет своей БД**. Stateless.

**Listener'ы** (`cmd/api-gateway/main.go`):
- `:8080` — plain HTTP/cmux. Cluster-internal (UI, port-forward, kacho-tui).
- `:8443` — TLS HTTPS/cmux (опционально, advertised endpoint для `yc` CLI).

**Mux** (`internal/restmux/mux.go`):
- grpc-gateway-ServeMux с `runtime.JSONPb`: camelCase + EmitUnpopulated.
- Регистрирует `<Service>HandlerFromEndpoint` для всех publicсервисов:
  - `OrganizationService`, `CloudService`, `FolderService` → `rm.kacho.svc:9090`.
  - 7 publicVPC → `vpc.kacho.svc:9090`.
- Регистрирует **`Internal*` admin** (Region, Zone, AddressPool, Cloud) →
  `vpc.kacho.svc:9091` (см. [04-api-gateway-routing.md](04-api-gateway-routing.md)).
- `OperationService` через `opsproxy` (in-process, fan-out на нужный backend
  по operation-ID prefix).

**Текущая дырка**: TLS-listener использует тот же mux, что cluster-listener.
Production-готовность требует middleware `BlockAdminPaths` на TLS-уровне
(`/vpc/v1/regions`, `/vpc/v1/zones`, `/vpc/v1/addressPools`,
`/vpc/v1/networks/*/addressPoolBinding`, `/vpc/v1/addresses/*/addressPoolOverride`).
TODO в `kacho-vpc/CLAUDE.md` §16.x.

## kacho-corelib

**Роль**: переиспользуемые пакеты. Не сервис, библиотека.

**Пакеты** (по фазам):
- `ids/` — `NewID(prefix string)` — 3-char prefix + 17-char base32 (verbatim YC).
- `errors/`, `config/` (envconfig), `observability/` (slog + json), `db/` (pgxpool +
  transactor), `grpcsrv/`, `grpcclient/`.
- `outbox/`, `selector/`.
- `operations/` — Operations table + Worker + Repo. Каждая мутация =
  Create Operation → `Run(ctx, op, fn)` крутит worker, переводит
  done=true с response/error.
- `retry/`, `shutdown/`, `backoff/` — gRPC retry на Unavailable + graceful
  shutdown.
- `migrations/common/` — общие миграции (`operations`, `operations_sequence`)
  → `make sync-migrations` копирует в каждое сервисное репо.
- `audit/` — `AuditLogger` (no-op, скелет под IAM).

## kacho-ui

**Stack**: Vite + React + TypeScript + TanStack Query + tailwind + shadcn/ui.

**Архитектура**: registry-driven generic-pages.

- `src/lib/resource-registry.ts` — `REGISTRY: Record<id, ResourceSpec>`.
  Spec содержит: apiPath, payloadKey, columns, fields (FormField[]),
  template, sanitize, scope (`global|folder|cloud|org`).
- `ResourceListPage` — generic table + polling 3 sec + filter + actions.
- `ResourceDetailPage` — generic JSON-view + edit/delete.
- `ResourceFormDialog` — generic Create/Edit с FieldRenderer (string, text,
  enum, ref, array, bool, sg-rules custom).
- Custom pages **только для admin IPAM**: `AddressPoolDetailPage` (utilization
  + addresses + reverse-lookup folder→cloud→org), `SubnetDetailPage`
  (utilization + per-CIDR), `SystemSearchPage` (cross-resource поиск).
- `IpamUtilizationBar` + `CIDRBreakdown` — переиспользуемые viz-компоненты
  (NetBox-style цветовая кодировка).

**Routes**:
- `/organizations`, `/organizations/:orgId/clouds`, `/clouds/:cloudId/folders`,
  `/folders/:folderId/{networks|subnets|addresses|route-tables|security-groups}`.
- `/system/{regions|zones|address-pools|search}` — admin (см. CLAUDE.md
  workspace §запрет 6).

**Sidebar**: 2 группы — VPC (folder-scoped, disabled когда folder не выбран)
+ System (global admin).

## kacho-tui

**Stack**: Go + `rivo/tview` + `gdamore/tcell/v2` (тот же стек, что k9s).

**Архитектура**:
- `internal/registry/specs.go` — Go-зеркало UI registry.
- `internal/api/client.go` — REST к api-gateway, snake↔camel converter.
- `internal/discovery/` — runtime probe всех endpoint'ов при старте.
- `internal/app/` — Layout (header/body/footer), command-bar (`:`),
  history-стек, ListView/DetailView/FormView/HelpView.

**Hotkeys** (k9s-style): `:` cmd, `/` filter, `?` help, `r` refresh,
`Enter` drill, `v` view, `a` add, `e` edit, `d` delete, `Esc` back.

**Запуск**: `kachoctl-ui ... ` нет — `kacho-tui --addr http://localhost:18080`.

## kacho-deploy

**Роль**: инфра для dev — kind cluster + helm umbrella.

- `kind/kind-config.yaml` — single-node, port-forward 28080.
- Helm umbrella с зависимостями: postgres-per-service (resourcemanager,
  vpc), ingress-nginx (для UI), netbox (legacy, не используется).
- Init container `migrate up` для каждого сервиса.

**Команды**:
- `make dev-up` — kind+helm, ждёт ready.
- `make reload-svc SVC=vpc` — docker build → `kind load docker-image` →
  `kubectl rollout restart`.
- `make logs-svc SVC=vpc`, `make psql SVC=vpc`.

## kacho-test

**Роль**: e2e regression через Newman.

- `collections/kacho-vpc.postman_collection.json` — master, single source.
- `scripts/build-suite.py` генерирует ro/light/seq из master по quota-aware
  3-suite split.
- `environments/{local,yc}.postman_environment.json`.
- 3-suite split:
  | Suite | Запросов | Delay | Назначение |
  |---|---|---|---|
  | ro | ~30 | 50ms | read-only smoke |
  | light | ~70 | 250ms | light mutations |
  | seq | ~10 | 1500ms | heavy/sequential |

Подробно в `project/kacho-vpc/CLAUDE.md` §14.3.

## Замороженные / spec-only

| Репо | Что | Как присоединить |
|---|---|---|
| `kacho-compute` | Instance, Disk, Image, Snapshot | proto + service + reconciler-loop, ref на VPC через gRPC |
| `kacho-loadbalancer` | NLB, TargetGroup | proto + service, ссылается на VPC.Address |
| `kacho-yc-shim` | Adapter если нужен YC-compat | пока не нужно |
| `kacho-vpc-implement` | Data-plane SDN | spec-only, см. `docs/specs/` и `docs/specs-oss-stack/` в репо |
