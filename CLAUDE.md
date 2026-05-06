# Kachō — Workspace CLAUDE.md

Этот файл загружается Claude Code при работе из самого `kacho-workspace/`
и **из любой подпапки `kacho-workspace/project/<repo>/`** благодаря
parent-walkup discovery (см. §«Структура репозиториев»).

## Что это за проект

Kachō — облачная управляющая платформа (control plane), реализующая подмножество доменов Yandex Cloud по verbatim YC API контракту (proto-форма, error texts, status codes, regex'ы, behavioural semantics). Только control plane, никакого реального data plane.

Полная спека: `kacho-workspace/docs/specs/00-overview-and-scope.md` и далее.

## Naming convention (обязательно)

| Контекст | Значение |
|---|---|
| Бренд / README / UI | **Kachō** |
| Технические идентификаторы (ASCII) | `kacho` |
| Proto package | `kacho.cloud.<domain>.v1` |
| Имена репо | `kacho-<part>` (с дефисом) |
| Postgres database / schema | `kacho_<domain>` (с подчёркиванием) |
| Env-переменные | `KACHO_<DOMAIN>_<NAME>` |

## Структура репозиториев (polyrepo)

Workspace — корневой репо. Все sibling-репо клонируются в `./project/`
скриптом `bootstrap.sh`. `project/` под gitignore — каждое sibling-репо
имеет собственный `.git/` и публикуется отдельно.

```
kacho-workspace/             ← корневой git-репо (этот файл — здесь)
├── CLAUDE.md                ← общие правила (видны из project/* через parent-walkup)
├── .claude/agents/          ← project-level субагенты — видны из всех project/*
├── docs/                    ← specs, plans, qa
└── project/                 ← gitignore'd
    ├── kacho-proto/         ← собственный git
    ├── kacho-corelib/       ← собственный git
    ├── kacho-vpc/           ← собственный git
    └── ...
```

**Discovery субагентов:** Claude Code при запуске из
`project/kacho-vpc/` поднимается вверх по дереву и находит
`kacho-workspace/.claude/agents/` — поэтому общие 13 агентов
автоматически доступны во всех sibling-репо без дублирования.
Service-specific агенты живут в `project/<repo>/.claude/agents/`
рядом с кодом (override workspace-копию при совпадении имён).

| Репо | Роль |
|---|---|
| `kacho-workspace` | корень: CLAUDE.md, общие агенты, спеки, bootstrap-скрипты |
| **`kacho-proto`** | **единая центральная директория для всех `.proto`-определений Kachō** (от всех бекендов, всех доменов). Структура: `proto/kacho/cloud/<domain>/v1/*.proto`. Сгенерированные Go-stubs commit-ятся в `gen/go/...`. Импорт сервисов: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/<domain>/v1` |
| `kacho-corelib` | переиспользуемые Go-пакеты (см. ниже) |
| `kacho-api-gateway` | edge: gRPC-proxy + grpc-gateway REST |
| `kacho-resource-manager` | Organization / Cloud / Folder |
| `kacho-vpc` | Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / PrivateEndpoint |
| `kacho-vpc-controllers` | reconciler-loop'ы для VPC (default SG creation, NetBox sync) |
| `kacho-compute` | Instance / Disk / Image / Snapshot |
| `kacho-loadbalancer` | NLB / TargetGroup |
| `kacho-deploy` | dev-стенд (Postgres + ingress) + e2e-сценарии |
| `kacho-ui` | Vite + React SPA для control plane |
| `kacho-test` | сводный e2e/regression стенд |
| `kacho-yc-shim` | adapter-слой (если нужен для миграции данных/совместимости) |

**Куда складывать новый `.proto`:** ВСЕГДА в `kacho-proto/proto/kacho/cloud/<domain>/v1/`. Сервисные репо НЕ содержат `.proto`-файлов — только Go-импорт сгенерированных stubs из `kacho-proto`. Это упрощает breaking-change detection (один `buf breaking` на всё), синхронизацию версий между сервисами и подключение клиентских SDK.

## Чистая архитектура (Clean Architecture)

Каждый сервис организован по слоям Clean Architecture (Uncle Bob). **Строгое dependency rule:**

```
handler ─┐
         ├─→ service ─→ domain
repo ────┤              ↑
clients ─┘              │
                  (только структуры)
```

Структура `internal/`:
- `domain/` — entities (чистый Go-тип, импортирует ТОЛЬКО stdlib и `kacho-proto`)
- `service/` — use-cases (бизнес-логика); определяет port-интерфейсы (`<Resource>Repo`, `<Peer>Client`); импортирует ТОЛЬКО `domain`
- `repo/` — adapter: реализует port-интерфейсы из service, импортирует pgx + domain
- `clients/` — adapter: реализует port-интерфейсы из service, импортирует grpc-stubs + domain
- `handler/` — тонкий transport-слой: parse-request → service.Foo() → format-response. **Никакой бизнес-логики.**
- `cmd/<svc>/main.go` — **единственное** место wiring (composition root)

**Запрещено:**
- `domain/` или `service/` импортируют `pgx`, grpc-stubs, sqlc-types — это утечка adapter в use-case
- Бизнес-логика в `handler/` (валидация полей, ветвления по domain-state, расчёты)
- Глобальные синглтоны (`var globalPool`, `init()`-side-effects) вне `cmd/`

Тесты следуют слоям: unit-тесты `service/` через mock port-интерфейсов; integration-тесты через testcontainers; e2e через api-gateway. Если service-тест требует Postgres — это сигнал об утечке adapter в use-case.

## Git / коммиты

- Коммиты — Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `ci:`, `refactor:`).
- Подпись коммитов — git-config-имя (`user.name` / `user.email` репозитория).
- **НЕ добавлять** `Co-Authored-By: Claude ...` или похожие attribution-trailers — это локальный проект, не open-source с многоавторством.
- Не использовать `--no-verify` для скипа pre-commit hooks без явной просьбы.
- Не делать `git push --force` на `main` — только новые коммиты.

## Принцип переиспользования через `kacho-corelib`

**Всё, что может быть вынесено в общий компонент для переиспользования в нескольких сервисах — выносится в `kacho-corelib/<package>/`.**

В `kacho-corelib` живут:

- `ids/`, `errors/`, `config/`, `observability/`, `db/` (pgx pool + transactor), `grpcsrv/` (server bootstrap), `grpcclient/` (client factory) — sub-phase 0.1.
- `outbox/`, `selector/` — sub-phase 0.2 (Watch pattern был в `watch/`, удалён в 1.0).
- `operations/` — sub-phase 1.0: Operations table (long-running async ops) + Worker (перевод done=false→true) + Repo. Используется всеми сервисами для возврата `Operation` из мутаций.
- `retry/`, `shutdown/`, `backoff/` — gRPC retry + graceful shutdown helpers.
- `migrations/common/` — общие миграции (`operations` table, `operations_sequence`); синхронизируются в каждое сервисное репо через `make sync-migrations`.
- `audit/` — `AuditLogger` (no-op в текущей фазе, скелет под AAA).

**Перед написанием новой утилиты в сервисном репо** — проверь, есть ли уже подходящий пакет в `kacho-corelib`. Если нет, но логика **будет нужна 2+ сервисам** — оформляй сразу в `kacho-corelib`, не дублируй per-service.

**Исключение:** бизнес-логика конкретного домена (Compute reconciler, VPC ref-validation, NLB target-deregister finalizer) живёт в сервисном репо. В corelib — только горизонтальные cross-cutting concerns.

## Запреты (обязательно соблюдать)

1. **НЕ начинать кодирование** до **APPROVED** acceptance-документа Given-When-Then в `docs/specs/sub-phase-X.Y-<topic>-acceptance.md`. Approve выставляет агент `acceptance-reviewer` (а НЕ заказчик — он проверяет только итоговый smoke). См. `04-roadmap-and-phasing.md` §2.
2. **НЕ упоминать «yandex»** в handwritten-коде, README, комментариях, env-name, именах функций.
3. **НЕ использовать ORM** (gorm, ent, bun). Только sqlc + handwritten pgx.
4. **НЕ делать каскадное удаление через границу сервиса** (только same-DB FK cascade).
5. **НЕ редактировать применённую миграцию.** Только новая миграция.
6. **НЕ маршрутизировать `Internal.*` методы** через api-gateway наружу.
7. **НЕ вводить broker** (Kafka/NATS) до тех пор, пока in-process реализация справляется.
8. **НЕ создавать новые единые БД** — только database-per-service.
9. **НЕ возвращать ресурс синхронно из мутирующих RPC.** Все мутации (`Create/Update/Delete/Start/Stop/Restart`) возвращают `Operation` (long-running async). Клиент поллит `OperationService.Get(id)` до `done=true`. См. ниже «API contract — flat resources + Operations».

## API contract — flat resources + Operations (с фазы 1.0)

**Каждый ресурс — плоский message** с domain-полями на верхнем уровне:
```protobuf
message Instance {
  string id = 1;
  string folder_id = 2;
  google.protobuf.Timestamp created_at = 3;
  string name = 4;
  string description = 5;
  map<string,string> labels = 6;
  string zone_id = 7;
  Status status = 10;       // enum, не nested message
  // ...domain-specific fields плоско
}
```

**Service шаблон:**
```protobuf
service InstanceService {
  rpc Get(GetInstanceRequest) returns (Instance);                  // sync read
  rpc List(ListInstancesRequest) returns (ListInstancesResponse);  // sync read
  rpc Create(CreateInstanceRequest) returns (operation.Operation); // async
  rpc Update(UpdateInstanceRequest) returns (operation.Operation); // async
  rpc Delete(DeleteInstanceRequest) returns (operation.Operation); // async
}
```

**Operation message** в `kacho.cloud.operation.v1`:
```protobuf
message Operation {
  string id = 1;
  string description = 2;
  google.protobuf.Timestamp created_at = 3;
  bool done = 6;
  google.protobuf.Any metadata = 7;     // {instance_id} для CreateInstanceMetadata
  oneof result {
    google.rpc.Status error = 8;
    google.protobuf.Any response = 9;   // Instance
  }
}
```

**Что выкинуто (deprecated с 1.0):**
- Watch RPC — больше не существует. Клиент использует List-polling 2-5 сек или Operations.Get(id) для in-flight задач.
- `kacho-corelib/watch/` package — удалён.
- gRPC server-streaming через grpc-gateway / WebSocket для Watch — выкинут.

## Локальная разработка (быстрые команды)

Все команды относительно корня workspace (где этот файл). Сервисы — в `project/`.

- Развернуть стенд: `cd project/kacho-deploy && make dev-up`
- Снести стенд: `cd project/kacho-deploy && make dev-down`
- Перезапустить один сервис: `cd project/kacho-deploy && make reload-svc SVC=compute`
- Логи сервиса: `cd project/kacho-deploy && make logs-svc SVC=compute`
- Открыть psql сервиса: `cd project/kacho-deploy && make psql SVC=compute`
- Обновить все репо: `./sync-all.sh` (или `cd <workspace> && ./sync-all.sh`)

## Спецификация (5 документов)

1. `docs/specs/00-overview-and-scope.md` — обзор и принципы
2. `docs/specs/01-architecture-and-services.md` — граф сервисов, RPC
3. `docs/specs/02-data-model-and-conventions.md` — data model, schemas, naming
4. `docs/specs/03-deployment-and-operations.md` — deployment, operations, CLAUDE.md иерархия
5. `docs/specs/04-roadmap-and-phasing.md` — sub-итерации 0.1–0.7, TDD-workflow

## Subagents (`.claude/agents/`)

**Workspace-level (видны из любого `project/<repo>/` через parent-walkup
discovery — Claude Code поднимается по дереву от cwd до первого `.claude/agents/`):**

**Task-execution (7):** `acceptance-author`, `proto-sync`, `service-scaffolder`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester`.

**Specialist-review (6):** `acceptance-reviewer`, `system-design-reviewer`, `db-architect-reviewer`, `go-style-reviewer`, `proto-api-reviewer`, `qa-test-engineer`.

**Service-specific (живут в `project/<repo>/.claude/agents/`):**

Если домен требует узкоспециализированной экспертизы (verbatim-parity, специфические инварианты, regression-tooling) — создавай агентов **в самом сервисном репо**, не в workspace. Эталонный пример — `kacho-vpc/.claude/agents/` (sub-phase 0.3 завершён):
- `vpc-yc-parity-auditor` — аудит verbatim YC parity (regex, error texts, status codes, timestamp).
- `vpc-cidr-specialist` — CIDR (host-bits, EXCLUDE constraint, overlap, internal IP).
- `vpc-outbox-watch-engineer` — outbox + LISTEN/NOTIFY + InternalWatchService.
- `vpc-newman-author` — Newman regression suites (quota-aware 3-suite split).

При совпадении имён project-level override-ит workspace-level (Claude Code находит ближайший `.claude/agents/` первым).

**Использовать готовые (не создавать заново):** `Explore`, `Plan`, `general-purpose`, `superpowers:code-reviewer`, `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:requesting-code-review`.

> Напоминание: `Internal.*` методы сервисов не должны попадать в api-gateway. Это ответственность `api-gateway-registrar`.

## Permissions

`.claude/settings.json` использует `bypassPermissions` для локальной dev-машины. Можно ужесточить позже.
