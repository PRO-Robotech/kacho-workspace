# Kachō — Architecture Documentation

Срез текущей архитектуры Kachō (control-plane only). Срез — на текущий
момент репозитория; обновлять при существенных изменениях контрактов / новых
сервисах.

## Содержание

| # | Документ | О чём |
|---|---|---|
| 00 | [Overview](00-overview.md) | Цель продукта, scope, верхнеуровневая карта репо/сервисов |
| 01 | [Services](01-services.md) | Каждый сервис: роль, RPC, БД, зависимости, Clean-Architecture слои |
| 02 | [Data Flows](02-data-flows.md) | Sequence-диаграммы ключевых сценариев (Account→Project→Network→Address, IPAM allocate, Operations LRO) |
| 03 | [IPAM Model](03-ipam.md) | Region/Zone/Pool/ProjectSelector/Cascade — детально с примерами |
| 04 | [API Gateway Routing](04-api-gateway-routing.md) | Как REST маппится на gRPC backend, two-listener model (public + admin) |
| 05 | [Tooling](05-tooling.md) | kachoctl-ipam CLI, kacho-tui, kacho-ui — для чего и как |
| 06 | [Deployment](06-deployment.md) | kind+helm umbrella, миграции, port-forward, build/rollout |
| 07 | [Conventions & Constraints](07-conventions.md) | Naming, запреты, конвенции API Kachō, kacho-only исключения |
| 08 | [Roles & Skills](08-roles-and-skills.md) | Кто нужен в команде, концептуальные скилы по ролям, role-assignment matrix |
| 09 | [Permission Catalog](09-permission-catalog-source-of-truth.md) | Source-of-truth и sync-pipeline permission-каталога (gRPC fqn → permission/relation/scope) |

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
                │  • TLS endpoint = external (внешние клиенты); plain = UI │
                └────────┬───────────────┬──────────────┬──────────────────┘
                         │               │              │
                         │ public gRPC   │ public gRPC  │ admin internal-port
                         │ :9090         │ :9090        │ :9091
                         ▼               ▼              ▼
              ┌──────────────────┐  ┌──────────────────┐
              │    kacho-iam     │  │   kacho-vpc      │
              │  Account/Project │  │  Network/Subnet/ │
              │  User/SA/Group/  │  │  Address/RT/SG/  │
              │  Role/AccessBind │  │  Gateway/NIC  +  │
              │                  │  │  Region/Zone/    │
              │   pg-iam         │  │  Pool/ProjSel    │
              └──────────────────┘  │                  │
                         ▲          │   pg-vpc         │
                         │          └──────┬───────────┘
                         │                 │ ProjectService.Get
                         │                 │ (existence + account lookup)
                         └─────────────────┘
```

Заморожены/планируются: `kacho-compute`, `kacho-nlb`.
Spec-only: `kacho-vpc-operator` (data-plane sibling VPC, вне build-графа).

## Принципы (TL;DR)

- **Собственные конвенции API.** Публичный API проектируется в чистой форме
  под нужды Kachō: единые тексты ошибок, regex'ы, статус-маппинг,
  таймстемпы. Это самостоятельный продукт, без сравнений с чужими облаками.
  См. §7.
- **Internal — kacho-only**: всё что относится к admin-нуждам и инфра-данным
  (Region/Zone/Pool, pool-selector на Project, defaultSG, IPAM utilization) —
  отдельные `Internal*Service` сервисы на отдельном порту 9091.
- **Один сервис → один Postgres**: database-per-service, никакого cross-DB
  доступа. Inter-service коммуникация только по gRPC.
- **Operations (LRO)**: все мутации (`Create`/`Update`/`Delete` и domain-действия)
  возвращают `Operation`, поллится отдельно через `OperationService.Get(id)`
  до `done=true`. `Get`/`List` — sync. Watch RPC не существует (полл List 2–5с).
- **Outbox + LISTEN/NOTIFY**: транзакционный outbox в той же TX, что и мутация,
  как журнал событий и wake-up-сигнал для внутрисервисных подписчиков.
- **Hard delete** + **flat schemas** (плоский message с domain-полями на
  верхнем уровне, без K8s-style envelope `metadata`/`spec`/`status`/
  `resourceVersion`/`generation`/`finalizers`).

См. подробности по каждому принципу в `07-conventions.md`.
</content>
</invoke>
