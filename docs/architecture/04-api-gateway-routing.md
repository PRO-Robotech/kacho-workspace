# 04 — API Gateway Routing

## Что делает api-gateway

- Принимает HTTP/REST и gRPC.
- Делит трафик через `cmux` на два внутренних listener'а: gRPC vs HTTP.
- HTTP/REST маршрутизирует через `grpc-gateway` (`runtime.ServeMux`) в
  backend gRPC сервисы.
- gRPC проксирует через `proxy.Director` (header-based routing).
- Дополнительно: in-process `OpsProxy` (один URL `/operations/{id}` на все
  backend operation-tables).

Stateless. Не имеет своей БД. Knows only об адресах backend gRPC сервисов
(env-vars).

## Двойной listener

```mermaid
flowchart LR
  C1[UI / port-forward]:::pub --> L1[plain :8080<br/>cmux]
  C2[yc CLI / external]:::ext --> L2[TLS :8443<br/>cmux]

  L1 -->|content-type: application/grpc| GS1[grpcSrv]
  L1 -->|else| HS1[httpSrv]
  L2 -->|content-type: application/grpc| GS2[grpcSrv same]
  L2 -->|else| HS2[httpSrv same]

  GS1 --> P[proxy.Director]
  GS2 --> P
  HS1 --> M[grpc-gateway mux]
  HS2 --> M

  P --> RM[resource-manager :9090]
  P --> VPC[vpc :9090]
  M --> RM
  M --> VPC
  M --> VPCI[vpc :9091<br/>internal admin]:::admin
  M --> OPS[OperationService<br/>opsproxy in-process]

  classDef pub fill:#e8f5e9,stroke:#2e7d32
  classDef ext fill:#ffebee,stroke:#c62828
  classDef admin fill:#fff8e1,stroke:#f57c00
```

**Текущая дырка**: оба listener'а используют **один и тот же** `httpSrv` mux,
в котором зарегистрированы и admin RPC. На production нужно повесить
middleware на TLS listener, который блокирует admin paths (см. workspace
CLAUDE.md §запрет 6 + kacho-vpc CLAUDE.md §16.x).

## Backend разрешение (env-vars)

`internal/config/config.go`:
```
KACHO_API_GATEWAY_RESOURCEMANAGER_GRPC  default: resource-manager.kacho.svc.cluster.local:9090
KACHO_API_GATEWAY_VPC_GRPC              default: vpc.kacho.svc.cluster.local:9090
KACHO_API_GATEWAY_VPC_INTERNAL_GRPC     default: vpc.kacho.svc.cluster.local:9091
```

`Config.BackendAddrs()` возвращает map → передаётся в `restmux.NewMux(addrs, conns)`.

## restmux: что куда

```go
// internal/restmux/mux.go (упрощённо)

// Public verbatim-YC
rmpb.RegisterCloudServiceHandlerFromEndpoint        → rmAddr
rmpb.RegisterFolderServiceHandlerFromEndpoint       → rmAddr
orgpb.RegisterOrganizationServiceHandlerFromEndpoint → rmAddr (тот же backend)

vpcpb.RegisterNetworkServiceHandlerFromEndpoint        → vpcAddr
vpcpb.RegisterSubnetServiceHandlerFromEndpoint         → vpcAddr
vpcpb.RegisterAddressServiceHandlerFromEndpoint        → vpcAddr
vpcpb.RegisterRouteTableServiceHandlerFromEndpoint     → vpcAddr
vpcpb.RegisterSecurityGroupServiceHandlerFromEndpoint  → vpcAddr
vpcpb.RegisterGatewayServiceHandlerFromEndpoint        → vpcAddr
pepb.RegisterPrivateEndpointServiceHandlerFromEndpoint → vpcAddr

// Admin (kacho-only, не verbatim-YC) — на vpc-internal
if vpcInternalAddr != "" {
    vpcpb.RegisterInternalRegionServiceHandlerFromEndpoint        → vpcInternalAddr
    vpcpb.RegisterInternalZoneServiceHandlerFromEndpoint          → vpcInternalAddr
    vpcpb.RegisterInternalAddressPoolServiceHandlerFromEndpoint   → vpcInternalAddr
    vpcpb.RegisterInternalCloudServiceHandlerFromEndpoint         → vpcInternalAddr
}

// OperationService — in-process через OpsProxy (см. ниже)
operationpb.RegisterOperationServiceHandlerServer(mux, opsproxy.New(conns))
```

## OpsProxy

`internal/opsproxy/proxy.go` — реализует `OperationServiceServer` локально
в api-gateway. На входе `Get(operation_id)`:

1. Смотрит на prefix ID:
   - `opvpc...` → vpc backend
   - `opfo...`, `oporg...`, `opcl...` → resource-manager backend
2. Делегирует на нужный backend gRPC `OperationService.Get`.
3. Возвращает Operation как есть.

Это позволяет иметь **один** path `/operations/{id}` независимо от того,
какой сервис создал операцию.

## JSON-marshalling

```go
runtime.NewServeMux(
  runtime.WithMarshalerOption(runtime.MIMEWildcard, &runtime.JSONPb{
    MarshalOptions: protojson.MarshalOptions{
      UseProtoNames:   false,        // camelCase (verbatim YC)
      EmitUnpopulated: true,         // явные `false`/`""`/`{}` (verbatim YC)
    },
    UnmarshalOptions: protojson.UnmarshalOptions{
      DiscardUnknown: true,           // ignore лишние поля
    },
  }),
)
```

`EmitUnpopulated: true` исторически ломалось из-за `BadRequest.field_violations[]` (Any) без зарегистрированного errdetails. Это починено в `cmd/api-gateway/main.go` через blank-import:

```go
_ "google.golang.org/genproto/googleapis/rpc/errdetails"
```

## Routing-таблица (полная, на текущий момент)

| Method | Path | Backend | Service |
|---|---|---|---|
| `*` | `/organization-manager/v1/organizations*` | rmAddr | OrganizationService |
| `*` | `/resource-manager/v1/clouds*` | rmAddr | CloudService |
| `*` | `/resource-manager/v1/folders*` | rmAddr | FolderService |
| `*` | `/vpc/v1/networks*` | vpcAddr | NetworkService |
| `*` | `/vpc/v1/subnets*` | vpcAddr | SubnetService |
| `*` | `/vpc/v1/addresses*` | vpcAddr | AddressService |
| `*` | `/vpc/v1/routeTables*` | vpcAddr | RouteTableService |
| `*` | `/vpc/v1/securityGroups*` | vpcAddr | SecurityGroupService |
| `*` | `/vpc/v1/gateways*` | vpcAddr | GatewayService |
| `*` | `/vpc/v1/privateEndpoints*` | vpcAddr | PrivateEndpointService |
| `GET` | `/operations/{id}` | opsproxy → vpcAddr/rmAddr | OperationService |
| `GET/POST/PATCH/DELETE` | `/vpc/v1/regions*` | **vpcInternalAddr** | InternalRegionService (admin) |
| `GET/POST/PATCH/DELETE` | `/vpc/v1/zones*` | **vpcInternalAddr** | InternalZoneService (admin) |
| `GET/POST/PATCH/DELETE` | `/vpc/v1/addressPools*` | **vpcInternalAddr** | InternalAddressPoolService (admin) |
| `GET` | `/vpc/v1/addressPools/{id}/utilization` | **vpcInternalAddr** | (admin observability) |
| `GET` | `/vpc/v1/addressPools/{id}/addresses` | **vpcInternalAddr** | (admin observability) |
| `GET/POST/DELETE` | `/vpc/v1/clouds/{id}/poolSelector` | **vpcInternalAddr** | InternalCloudService (admin) |
| `POST/DELETE` | `/vpc/v1/networks/{id}/addressPoolBinding` | **vpcInternalAddr** | InternalAddressPoolService (admin bindings) |
| `POST/DELETE` | `/vpc/v1/addresses/{id}/addressPoolOverride` | **vpcInternalAddr** | InternalAddressPoolService (admin bindings) |

**Bold** = admin-only, не должны попадать на TLS-listener (см. CLAUDE.md
запрет 6).

## Middleware chain

`internal/middleware/`:
- `request_id` — X-Request-ID или generate UUID.
- `recovery` — panic-handler.
- `access_log` — slog запись метода/пути/статуса/duration.
- `idempotency` — idempotency-key header (verbatim YC).
- `auth_noop` — пока заглушка, пропускает всё как `anonymous`.

## Health

`/healthz`, `/readyz` — `internal/health/`. Не используют backend, всегда 200.
