---
title: kacho-vpc
aliases:
  - kacho-vpc
category: repo
repo: kacho-vpc
go_module: github.com/PRO-Robotech/kacho-vpc
service_type: control-plane
domain: vpc
status: stable
related_packages:
  - [[packages/vpc-domain]]
  - [[packages/vpc-repo-kacho]]
  - [[packages/vpc-cmd-vpc]]
tags:
  - kacho
  - kacho-vpc
  - control-plane
  - grpc
  - cqrs
---

# kacho-vpc

VPC control-plane сервис Kachō — Network/Subnet/Address/RouteTable/SecurityGroup/Gateway/PrivateEndpoint/NetworkInterface + admin AddressPool.

- Repo: `github.com/PRO-Robotech/kacho-vpc`
- Тип: control-plane (data-plane в `kacho-vpc-implement`).
- **Skill `evgeniy` 100% эталон** — все 48 правил applied (CQRS Reader/Writer, repo-leaf entities, self-validating domain, atomic outbox-in-TX, ExecAbstract, schema `kacho_vpc`).

## Public ресурсы (8)

Тонкий wrapper над verbatim YC stylings + KAC-specific structural divergences.

| Resource | ID prefix | Note |
|---|---|---|
| Network | `enp` | Контейнер для подсетей. (Прежнее internal data-plane-id-поле удалено в KAC-36/79/80.) |
| Subnet | `e9b` | EXCLUDE CIDR-overlap, auto-association с RouteTable (DB-trigger). |
| Address | `e9b` | External/Internal IPv4/IPv6; IPAM inline allocate. |
| RouteTable | `enp` | StaticRoutes + auto-association с Subnet'ами. |
| SecurityGroup | `enp` | Rules (oneof source/destination) + OCC через `xmin`. |
| Gateway | `enp` | shared_egress only (frozen scope). Strict-name `NameGateway` (lowercase). |
| PrivateEndpoint | `enp` | object_storage scope; FK на Network/Subnet/Address (inline в baseline `0001_initial.sql` после squash). |
| NetworkInterface | `e9b` | AWS-ENI-style first-class (вариант А, KAC-2). CRUD-ресурс; `AttachToInstance`/`DetachFromInstance` удалены ([[../KAC/KAC-266]] — инстанс без авто-NIC). MAC-allocation retry. v4/v6 cardinality ≤ 1 (CHECK inline в baseline). |

## Admin / Internal ресурсы (2)

Internal-only, exposed только через api-gateway internal mux (НЕ на external TLS endpoint).

| Resource | ID prefix | Note |
|---|---|---|
| **AddressPool** | `apl` | Global infrastructure resource. Family-split (v4_cidr_blocks/v6_cidr_blocks, KAC-71). Cascade 3-step resolve (network_default→zone_default→global_default; override/selector сняты в [[../KAC/KAC-266]]). |
| AddressPoolBinding | — | per-network default binding (`BindAsNetworkDefault`). per-address override удалён [[../KAC/KAC-266]]. |

(`CloudPoolSelector` ресурс + `InternalCloudService` удалены в [[../KAC/KAC-266]].)

## Структура пакетов

```
cmd/
├── vpc/main.go            — gRPC API server (serve only)
└── migrator/main.go       — cobra CLI миграций (up/down/status/create + --dialect)

internal/
├── domain/                — Pure domain types (Network, Subnet, ..., 11 entities + nested).
│   ├── types.go              RcNameVPC / RcDescription / RcLabels (newtypes + Validate).
│   ├── constants.go          ShortIDLen, TruncateID, status enums.
│   ├── equal.go              Equal-методы (D.10).
│   └── security_group_builders.go   NewDefaultSecurityGroup / Rules / Name.
├── repo/                  — Persistence layer.
│   ├── helpers/              SQL helpers (cols, scan, payload, errors, jsonb, outbox).
│   ├── kacho/                CQRS Reader/Writer (Repository / RepositoryReader / RepositoryWriter).
│   │   ├── iface*.go           per-resource interfaces.
│   │   ├── entity_*.go         Record-структуры (domain.X + CreatedAt).
│   │   ├── pg/                 pgxpool-impl (master/slave-pool wiring).
│   │   └── kachomock/          in-memory mock с TX-семантикой.
│   ├── repomock/             узкие mock'и для unit-тестов use-case'ов.
│   └── cqrsadapter/          adapter helpers.
├── apps/kacho/
│   ├── api/                  — Use-case packages по ресурсу:
│   │   ├── network/            CreateNetworkUseCase + CreateDefaultSGUseCase (composition).
│   │   ├── subnet/, address/, routetable/, securitygroup/, gateway/,
│   │   ├── privateendpoint/, networkinterface/
│   │   └── addresspool/        admin AddressPool use-cases.
│   ├── services/             — Admin/internal сервисы:
│   │   ├── addressref/         referrer-tracking.
│   │   └── networkinternal/    InternalNetworkService (SetDefaultSGId, etc).
│   ├── shared/               — общие helpers (macutil, serviceerr).
│   └── config/               — viper YAML config + Mode enum + defaults.
├── dto/                    — table-driven generic DTO (Transferrable sum-type).
│   ├── base.go               Interface[F,T], RegTransfer, FindTransfer, Transfer.
│   └── toproto/              per-resource `toPb` functions + `init()` registrations.
├── clients/                — peer-service gRPC clients (folder, compute) через H-BF/corlib/client/grpc.
├── handler/                — Internal admin gRPC handlers (на cluster-internal listener).
└── migrations/             — goose-миграции (единая baseline `0001_initial.sql`
                              после squash 0001..0034 → 0001, ветка
                              `chore/squash-migrations`, KAC-111).
```

## RPC: public (8 сервисов × ~5-7 методов)

- `NetworkService.{Get,List,Create,Update,Delete,ListOperations}` + `SubnetService` etc. (`Move`/Subnet `Relocate` удалены в [[../KAC/KAC-266]]).
- NIC: публичный `NetworkInterfaceService` CRUD; `AttachToInstance`/`DetachFromInstance` удалены ([[../KAC/KAC-266]] — инстанс без авто-NIC).
- Все мутации возвращают `*operation.Operation` (async LRO).
- Watch RPC удалён в 1.0 rewrite (использовать List-polling 2-5s).

## RPC: internal (cluster-internal только, port 9091)

- `InternalAddressService.{AllocateInternalIP,AllocateExternalIP,FreeIP}` — IPAM (вызывается in-process из `address.go`).
- `InternalNetworkService.SetDefaultSecurityGroupId` — admin Network (default-SG management).
- `InternalAddressPoolService` — admin CRUD + `BindAsNetworkDefault`/`Unbind`. (`Check`/`ExplainResolution`/per-Address override удалены в [[../KAC/KAC-266]].)
- ~~`InternalCloudService`~~ — удалён целиком в [[../KAC/KAC-266]] (IPAM-cascade: network_default→zone_default→global_default).
- `InternalWatchService` — outbox stream через LISTEN/NOTIFY.

## Cross-repo runtime edges

- → `kacho-iam`: `ProjectService.Get` для project existence на async-path Create (через `ProjectClient`, `internal/clients/iam_client.go`; было `kacho-resource-manager.FolderService.Get` до KAC-106/124). DB-колонка `folder_id` = id владельца-проекта (legacy-имя, source of truth = ProjectService).
- → `kacho-compute`: `ZoneService.Get` для zone validation в Subnet/Address spec (после KAC-15 Geography moved).
- ← `kacho-compute`: `NetworkInterface` validation, IPAM-allocate ephemeral Address.
  (Прежнее ребро ← `kacho-vpc-implement` NI dataplane writeback удалено в KAC-36/79/80.)

## Эпики / тикеты

- **KAC-111** — squash migrations 0001..0034 → 0001 (greenfield) ✅.
- **KAC-94** — skill evgeniy 100% эталон ✅ (18 PR'ов + cleanup PR'ов).
- **KAC-2** — NetworkInterface first-class ресурс ✅.
- **KAC-71** — AddressPool v4/v6 split ✅.
- **KAC-52** — NIC attach-race fix ✅.
- **KAC-15** — Geography moved to compute ✅.

См. [[../architecture]] для cross-repo графа.

#kacho #vpc #control-plane #grpc #cqrs
