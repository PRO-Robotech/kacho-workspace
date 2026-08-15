# Kachō Cloud Control Plane — Обзор и Scope

**Документ:** 00 / 5
**Дата:** 2026-05-03 (актуализирован 2026-06-10)
**Статус:** Living document

## 1. Что это

Kachō — **собственная** облачная управляющая платформа (control plane) с
декларативным API. Это самостоятельный продукт со своей ресурсной моделью и
конвенциями, удовлетворяющий требованиям проекта; не клон и не реплика какого-либо
стороннего облака. Домены: **IAM** (Account / Project / User / ServiceAccount /
Group / Role / AccessBinding), **VPC** (Network / Subnet / SecurityGroup /
RouteTable / Address / Gateway / NetworkInterface), **Compute** (Instance / Disk /
Image / Snapshot), **Geography** (Region / Zone — leaf-домен `kacho-geo`, эпик #82).

API — **плоские ресурсы** (flat message с domain-полями на верхнем уровне, без
вложенного envelope) + **асинхронные `Operation`** на каждой мутации. Чтения
(`Get`/`List`) синхронны; мутации (`Create`/`Update`/`Delete` и domain-действия)
возвращают `Operation`, клиент поллит `OperationService.Get(id)` до `done=true`.

**Только control plane.** Никаких реальных гипервизоров, SDN, dataplane-агентов.
Lifecycle ресурсов — детерминированная server-side state-машина внутри worker'а
операции (симулированные переходы PROVISIONING → RUNNING), без реального железа.

## 2. Цели

1. **Чистый декларативный API.** Единый предсказуемый паттерн на каждый ресурс:
   `Get`/`List` (sync) + `Create`/`Update`/`Delete` (async через `Operation`) +
   узкий набор domain-действий (`Start`/`Stop`/`AttachDisk`/`:addCidrBlocks`/…).
2. **Практичный состав полей** для облачных доменов (Compute, VPC, IAM): `cores`,
   `memory`, `networkInterfaces`, `bootDisk`, `cidrBlocks`, и т. д. — спроектирован
   под удобство потребителя API, а не под копирование чужой схемы.
3. **Иерархия владения**: Account → Project. Все ресурсы доменов — project-level
   (`project_id` обязателен в `Create`).
4. **Масштабируемость**: архитектура с расчётом на большой объём ресурсов
   (Postgres + транзакционный outbox + per-service `operations`).
5. **Открытость к расширению**: новые домены (DNS, Object Storage, Managed DBs,
   Load Balancer) — отдельные сервисы/фазы; архитектурные точки расширения
   зарезервированы.

## 3. Non-goals (явно вне scope текущей фазы)

- **Реальный data plane**: гипервизоры, VXLAN, eBPF, BGP, SRv6, dataplane-агенты
  (data-plane sibling `kacho-vpc-operator` — вне build-графа control-plane).
- **Биллинг, monitoring-стек, DNS, Object Storage, Managed Databases,
  Functions** — отдельные домены, отдельные фазы.
- **Multi-region active-active, multi-cluster federation** — single region в текущей фазе.
- **Внешний message broker (Kafka/NATS)** — заменён транзакционным outbox; не вводится,
  пока in-process реализация справляется.

> [!note] Отсюда выведены ДВА пункта, и оба — по факту, а не по свежести
> **Квоты.** Требование владельца назвало их предметом работы: «при создании проекта
> должна создаваться квота по всем ресурсам с базовыми значениями; управлять размерами
> должен только администратор облака». Требование **позже** этой строки и её отменяет —
> смена охвата есть заявление владельца, а не вывод, который документ делает за него.
> Предмет заведён приёмкой `sub-phase-quota-v2-materialised-usage-acceptance.md`
> (APPROVED) и предшественником `sub-phase-vpc-quota-resource-count-acceptance.md`;
> величина сдана в `kacho_iam.limits`, каталог видов с носителями учёта — стадией S1.
> Пока строка стояла здесь, APPROVED-спека запрещала ровно то, что предписывает
> APPROVED-приёмка, — два места об одном предмете, из которых верно одно.
>
> **Container Registry.** Пункт пережил свой предмет: `services/registry/` — живой
> сервис. Предикат: `git ls-tree -d --name-only HEAD services/registry` (непусто),
> `git ls-tree --name-only HEAD proto/kacho/cloud/registry/v1/` (контракты на месте),
> `grep -c registry gateway/internal/restmux/mux.go` → **25** маршрутных вхождений на
> крае. Он снят не заодно, а потому, что перечень, часть которого стала ложью, читается
> как действующее ограничение целиком.
>
> Остальные шесть членов перечня проверены и **верны**: каталога сервиса нет ни у
> одного (предикат: `ls -d services/*/` → семь имён, среди них ни billing, ни
> monitoring, ни dns, ни object storage, ни mdb, ни functions).
>
> **Предикат закрытия читает ПУНКТЫ ПЕРЕЧНЯ, а не главу и не раздел.** Эта врезка
> стоит внутри §3 и слово «квоты» содержит — она о том, что они в охвате. Предикат,
> читающий раздел целиком, нашёл бы её и был бы прочитан как незакрытый:
> ```sh
> awk '/^## 3\. Non-goals/,/^## 4\./' docs/specs/00-overview-and-scope.md \
>   | grep '^- ' | grep -icE 'квот|quota'        # → 0
> awk '/^## 3\. Non-goals/,/^## 4\./' docs/specs/00-overview-and-scope.md \
>   | grep '^- ' | grep -icE 'биллинг'           # контроль → 1, предикат не слеп
> awk '/^## 3\. Non-goals/,/^## 4\./' docs/specs/00-overview-and-scope.md \
>   | grep -c '^- '                              # перепись → 4 пункта прочитано
> ```

> **Дизайн-философия.** API проектируется в чистой, удобной форме под нужды Kachō.
> Структура методов и состав ресурсов — собственные (например, `NetworkInterface` —
> first-class ресурс домена kacho-vpc; `AddressPool` — admin-only IPAM-ресурс).
> Стиль сообщений/ошибок/таймстемпов — единые конвенции Kachō
> (`.claude/rules/api-conventions.md` + глава `02`), проверяемые тестами.

## 4. Принципы дизайна

1. **Плоские ресурсы + асинхронные Operations.** Domain-поля на верхнем уровне; все
   мутации — long-running `Operation`. Никаких синхронных возвратов ресурса из мутаций.
2. **Single source of truth.** Postgres — primary store; транзакционный outbox в той же
   TX, что и мутация, — журнал событий. Никаких dual-write race conditions.
3. **Опрос вместо стриминга.** Клиент использует `List`-polling и `OperationService.Get`
   для in-flight задач; серверного Watch-стриминга на публичной поверхности нет.
4. **Инварианты — на уровне БД.** Ссылочная целостность и инварианты внутри одной БД
   сервиса выражаются конструкциями Postgres (FK / partial-UNIQUE / EXCLUDE / CHECK /
   атомарный CAS), а не software-side check-then-act (`.claude/rules/data-integrity.md`).
5. **Service autonomy.** Database-per-service, polyrepo; каждое репо самодостаточно
   (склонировал — собрал). Между сервисами — только API, общих БД нет.
6. **Clean Architecture.** `domain ← use-case ← repo/clients/handler`; `cmd` —
   composition root (`.claude/rules/architecture.md`).
7. **Test-first / BDD.** Каждая итерация начинается с приёмочных Given-When-Then в
   markdown, проходит approve до кодирования; затем — строгий TDD (RED → GREEN).
   Кодинг без утверждённого acceptance запрещён (`04-roadmap-and-phasing.md` §3).

## 5. Сервисы текущей фазы

| Сервис | Ресурсы | Postgres БД |
|---|---|---|
| `kacho-api-gateway` | — (edge: gRPC-proxy + REST-фасад) | — |
| `kacho-iam` | Account, Project, User, ServiceAccount, Group, Role, AccessBinding | `kacho_iam` |
| `kacho-vpc` | Network, Subnet, SecurityGroup, RouteTable, Address, Gateway, NetworkInterface | `kacho_vpc` |
| `kacho-compute` | Instance, Disk, Image, Snapshot, DiskType | `kacho_compute` |
| `kacho-geo` *(в работе, эпик #82)* | Region, Zone (Geography — platform-топология, leaf) | `kacho_geo` |
| `kacho-nlb` *(планируется)* | NetworkLoadBalancer, TargetGroup | `kacho_nlb` |

`kacho-corelib` — переиспользуемые горизонтальные пакеты (ids / errors / config /
observability / db / operations / outbox / …). `kacho-proto` — центральная директория
всех `.proto` + сгенерированных stubs.

## 6. Бренд и naming

- Бренд: **Kachō** (макрон над `ō`).
- ASCII в технических идентификаторах: **`kacho`**.
- Proto package: **`kacho.cloud.<domain>.v1`** (например, `kacho.cloud.compute.v1`).
- Имена репо: **`kacho-<part>`** с дефисом.
- k8s namespace: **`kacho`**.
- Postgres-схемы: **`kacho_<domain>`** с подчёркиванием.

Полная таблица naming convention — в `02-data-model-and-conventions.md`.

## 7. Стек

- **Язык**: Go 1.25.
- **API**: gRPC + grpc-gateway (REST-фасад).
- **Proto**: buf (lint, breaking-change detection, code generation).
- **БД**: Postgres 16, `pgx/v5`, `sqlc` для типизированных запросов, `goose` для миграций.
- **Async**: per-service `operations`-таблица + worker (corelib `operations`) +
  транзакционный outbox с `LISTEN/NOTIFY` как wake-up signal.
- **Логи / metrics / tracing**: `slog`, OpenTelemetry SDK.
- **Контейнеризация и orchestration**: Docker, Helm, kind.
- **Тесты**: `testing` + `testify` + `testcontainers-go` (integration) + Newman (e2e).

## 8. Дорожная карта

**Будущие фазы** (порядок приоритета):

1. AAA — IAM (в работе: `kacho-iam`), mTLS, audit, RBAC.
2. Observability — Loki, Grafana, Tempo, Prometheus.
3. HA / Production — Postgres replication, multi-replica services, External Secrets, real ingress.
4. Расширение доменов — Load Balancer (`kacho-nlb`), DNS, Object Storage, Managed DBs, и далее.

Детализация sub-итераций — `04-roadmap-and-phasing.md`.

## 9. Дальнейшее чтение

- **Архитектура и сервисы** — `01-architecture-and-services.md`
- **Модель данных и конвенции** — `02-data-model-and-conventions.md`
- **Развёртывание и эксплуатация** — `03-deployment-and-operations.md`
- **Дорожная карта и фазирование** — `04-roadmap-and-phasing.md`
