# Kachō — Architecture Documentation

Срез текущей архитектуры Kachō (control-plane only). Срез — на текущий
момент репозитория; обновлять при существенных изменениях контрактов / новых
сервисах.

## Содержание

| # | Документ | О чём |
|---|---|---|
| 00 | [Overview](00-overview.md) | Цель продукта, scope, верхнеуровневая карта репо/сервисов |
| 01 | [Services](01-services.md) | Каждый сервис: роль, RPC, БД, зависимости, Clean-Architecture слои |
| 02 | [Data Flows](02-data-flows.md) | Sequence-диаграммы ключевых сценариев (Org→Cloud→Folder→Network→Address, IPAM allocate, Operations LRO) |
| 03 | [IPAM Model](03-ipam.md) | Region/Zone/Pool/CloudSelector/Cascade — детально с примерами |
| 04 | [API Gateway Routing](04-api-gateway-routing.md) | Как REST маппится на gRPC backend, two-listener model (public + admin) |
| 05 | [Tooling](05-tooling.md) | kachoctl-ipam CLI, kacho-tui, kacho-ui — для чего и как |
| 06 | [Deployment](06-deployment.md) | kind+helm umbrella, миграции, port-forward, build/rollout |
| 07 | [Conventions & Constraints](07-conventions.md) | Naming, запреты, verbatim-YC parity, kacho-only исключения |
| 08 | [Roles & Skills](08-roles-and-skills.md) | Кто нужен в команде, концептуальные скилы по ролям, role-assignment matrix |

## Quick map

```
                ┌──────────────────────────────────────────────────────────┐
                │                       kacho-ui (SPA, React)              │
                │                       kacho-tui (terminal)               │
                │                       kachoctl-ipam (admin CLI)          │
                └────────────────────────┬─────────────────────────────────┘
                                         │ REST (camelCase JSON)
                                         ▼
                ┌──────────────────────────────────────────────────────────┐
                │                    kacho-api-gateway                     │
                │  • cmux: gRPC | HTTP/REST на 8080 (cluster) + 8443 (TLS) │
                │  • restmux: grpc-gateway proxy на backend gRPC           │
                │  • opsproxy: in-process OperationService                 │
                │  • TLS endpoint = external (yc CLI compat); plain = UI   │
                └────────┬───────────────┬──────────────┬──────────────────┘
                         │               │              │
                         │ public gRPC   │ public gRPC  │ admin internal-port
                         │ :9090         │ :9090        │ :9091
                         ▼               ▼              ▼
              ┌──────────────────┐  ┌──────────────────┐
              │ kacho-resource-  │  │   kacho-vpc      │
              │     manager      │  │  Network/Subnet/ │
              │ Org/Cloud/Folder │  │  Address/RT/SG/  │
              │                  │  │  Gateway/PE  +   │
              │   pg-resource-   │  │  Region/Zone/    │
              │     manager      │  │  Pool/CloudSel   │
              └──────────────────┘  │                  │
                         ▲          │   pg-vpc         │
                         │          └──────┬───────────┘
                         │                 │ FolderService.Get
                         │                 │ (для cloud_id resolve в IPAM)
                         └─────────────────┘
```

Заморожены/планируются: `kacho-compute`, `kacho-loadbalancer`, `kacho-yc-shim`.
Spec-only: `kacho-vpc-implement` (data-plane SDN на гипервизорах).

## Принципы (TL;DR)

- **Verbatim YC** для публичного API: тот же proto, те же ошибки, те же
  тексты, те же regex'ы. См. §7.
- **Internal — kacho-only**: всё что не существует в YC (Region/Zone/Pool,
  pool-selector на Cloud, defaultSG, IPAM utilization) — отдельные
  `Internal*Service` сервисы на отдельном порту 9091.
- **Один сервис → один Postgres**: database-per-service, никакого cross-DB
  доступа. Inter-service коммуникация только по gRPC.
- **Operations (LRO)**: все мутации возвращают `Operation`, поллится
  отдельно. Watch RPC выкинут.
- **Outbox + LISTEN/NOTIFY**: для in-process подписки на изменения внутри
  сервиса (используется `InternalWatchService`).
- **Hard delete** + **flat schemas** (без K8s-style envelope) — последствие
  rewrite в фазе 1.0.

См. подробности по каждому принципу в `07-conventions.md`.
