# 05 — Tooling

Три взаимодополняющих UI клиента: web UI (общий), TUI (admin/dev), CLI
(admin/scripting).

## kacho-ui (Web SPA)

**Stack**: Vite + React + TypeScript + TanStack Query (polling 3s) +
react-router + tailwind + shadcn/ui-style primitives.

**Архитектура**: registry-driven generic-pages. Один `ResourceSpec` →
автоматически появляется в sidebar + ListPage + DetailPage + Create/Edit
formdialog. Custom-pages пишутся только когда нужно что-то нестандартное.

**Структура `src/`**:
```
api/
  client.ts            REST client + snake↔camel converter
  types.ts             TS-зеркало основных payload-типов
  resources.ts         per-resource API helpers (для ProjectSelector)
lib/
  resource-registry.ts REGISTRY: Record<string, ResourceSpec>  ← single source
  form-schema.ts       FormField type
  use-resource-list.ts useQuery wrapper для list-endpoint + project filter
  use-operation.ts     useInvalidateResourceList, polling Operations
  case.ts              snake↔camel
  project-store.ts     zustand: текущий project для VPC-страниц
  context-store.ts     drill-context
  path.ts              dotted-path getter/setter (form fields)
  toast.ts             toast notifications
components/
  Layout.tsx           sidebar + header + breadcrumb + outlet
  ResourceListPage.tsx generic table
  ResourceDetailPage.tsx generic JSON view + edit/delete
  ResourceFormDialog.tsx generic Create/Edit с FieldRenderer
  ResourceTable.tsx    table primitive
  StatusBadge, CopyableId, BreadcrumbSelector, JsonEditor, JsonView
  IpamUtilizationBar.tsx + CIDRBreakdown   ← NetBox-style viz
pages/
  AddressPoolDetailPage.tsx  custom admin: utilization + addrs + reverse-lookup
  SubnetDetailPage.tsx       custom: utilization + per-CIDR breakdown
  SystemSearchPage.tsx       cross-resource search
```

Все доменные ресурсы — project-level (`projectId`); иерархия владения —
**Account → Project** (домен `kacho-iam`).

**Adding a new resource**:
1. Backend → proto + handler.
2. Зарегистрировать в `kacho-api-gateway/internal/restmux/mux.go`.
3. Добавить запись в `src/lib/resource-registry.ts` (apiPath, columns, fields).
4. Если сложная страница (utilization, кросс-project addresses, …) —
   custom `pages/<Name>Page.tsx` + `App.tsx` route.

**Sidebar группы**:
- **VPC** (project-scoped): Networks, Subnets, Route Tables, Addresses,
  Security Groups. Disabled когда project не выбран в breadcrumb.
- **System** (global admin): Search, Regions, Zones, Address Pools.

**Опрос (polling)**: используется polling 3 сек (см. `useResourceList`) —
read-методы (`Get`/`List`) синхронны, мутации возвращают `Operation`, клиент
поллит `OperationService.Get(id)` до `done=true`. Серверного Watch-стриминга на
публичной поверхности нет — polling проще и для admin UX достаточно.

## kacho-tui (Terminal UI)

**Stack**: Go + `github.com/rivo/tview` + `github.com/gdamore/tcell/v2` (k9s
стек). Standalone binary, не deploy'ится.

**Структура `internal/`**:
```
api/         REST client (snake↔camel)
registry/    Go-зеркало UI registry
discovery/   probe endpoints на старте
app/         tview app:
              app.go          layout (header/body/footer/cmd-bar/history)
              list_view.go    table + polling 3s + filter + actions
              detail_view.go  JSON view + refresh
              form_view.go    tview.Form + dropdowns + ref-loader
              help_view.go    help screen со списком aliases
```

**Hotkeys** (k9s-style):
| Key | Действие |
|---|---|
| `:` | command-bar (`:net` → networks, `:pool` → address-pools, `:ctx`, `:quit`) |
| `/` | filter (substring) |
| `?` | help |
| `r` | refresh |
| `Enter` | drill (account→projects→networks) или detail |
| `v` | view detail (JSON) |
| `a` / `e` / `d` | add / edit / delete |
| `Esc` | back |
| `q` / `Ctrl-C` | quit |

**Запуск**:
```bash
# Default endpoint http://localhost:18080 (port-forward)
./bin/kacho-tui

# Override
./bin/kacho-tui --addr http://localhost:18080
KACHO_API_ADDR=http://api.kacho.local ./bin/kacho-tui
```

**Service discovery**: при старте параллельный `GET` на каждый list-endpoint
из registry → `disco N/M ok` в шапке. Доступные ресурсы видны в command-bar.

**Headless screenshot**: `tools/snap_png.py` — pty + pyte + PIL для CI/PR
скриншотов без TTY.

## kachoctl-ipam (Admin CLI)

**Цель**: admin operations через гpc к internal-port (9091). Минималистичный
flag-based CLI без cobra.

**Команды**:
```bash
# AddressPool CRUD
kachoctl-ipam pool create --kind EXTERNAL_PUBLIC --zone-id region-a-zone-a \
  --cidr 198.51.100.0/24 --is-default --name default-zone-a [--selector k=v --priority N]
kachoctl-ipam pool list [--zone-id Z] [--kind K]
kachoctl-ipam pool get <pool_id>
kachoctl-ipam pool delete <pool_id>

# AddressPool bindings
kachoctl-ipam pool bind-network --network N --pool P
kachoctl-ipam pool unbind-network --network N
kachoctl-ipam pool bind-address --address A --pool P
kachoctl-ipam pool unbind-address --address A

# Project-pool-selector (admin)
kachoctl-ipam project set-pool-selector --project P --selector k=v [--set-by S]
kachoctl-ipam project unset-pool-selector --project P
kachoctl-ipam project get-pool-selector --project P

# Region/Zone CRUD
kachoctl-ipam region create --id R --name "Name"
kachoctl-ipam region list|get <id>|update --id R --name "Name"|delete <id>
kachoctl-ipam zone create --id Z --region-id R --name "..."
kachoctl-ipam zone list [--region-id R]|get|update|delete

# Diagnostics
kachoctl-ipam ipam check [--zone Z]                    # ambiguous configs
kachoctl-ipam ipam explain --address A | --network N   # cascade explain
```

**Endpoint**: default `localhost:9091` (port-forward на vpc internal-port),
override через `--addr` или `KACHO_VPC_INTERNAL_ADDR`.

**Зачем существует** при наличии REST в api-gateway: kachoctl исторически
делает gRPC напрямую (быстрее, типобезопасней). Сейчас можно было бы
переписать на REST, но не нужно.

## Внешние клиенты (REST / gRPC)

Публичная поверхность Kachō — собственный REST/gRPC API через `kacho-api-gateway`.
Любой HTTP/gRPC-клиент (curl, Postman, сгенерированный из `kacho-proto` SDK)
работает с ним напрямую:

```bash
# REST через api-gateway
curl http://api.kacho.local/vpc/v1/networks?projectId=pj-...

# gRPC напрямую по сгенерированным stubs из kacho-proto
grpcurl api.kacho.local:443 kacho.cloud.vpc.v1.NetworkService/List
```

REST-пути — `/<service>/v1/<resource>`, suffix-actions через `:verb`
(`/subnets/{id}:addCidrBlocks`). Read-методы (`Get`/`List`) синхронны; мутации
возвращают `Operation` — клиент поллит `OperationService.Get(id)` до `done=true`.
Текущий стенд TLS-listener'а не запускает (env-vars не заданы), поэтому внешние
gRPC-клиенты используют `--insecure` либо включают TLS в helm-чарте.

## Что выбрать когда

| Сценарий | Tool |
|---|---|
| День-в-день admin осмотр | kacho-tui (быстрый старт) |
| Сложная навигация / детальные модалки | kacho-ui |
| Admin scripting (autoseed, миграция project-selector'ов) | kachoctl-ipam в bash |
| Regression / контракт-тесты API | Newman (kacho-test) |
| Быстрый ad-hoc curl | прямо REST на api-gateway |
