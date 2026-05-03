# Kachō — Развёртывание и эксплуатация

**Документ:** 03 / 5

## 1. Структура репозиториев (polyrepo)

Все репо живут в организации `github.com/PRO-Robotech/`. Локально — соседние папки в workspace:

```
cloud-demo/                              (workspace, не git, рабочая директория)
├── kacho-workspace/                     git: kacho-workspace
│   ├── CLAUDE.md
│   ├── .claude/
│   │   ├── agents/                      ← субагенты (см. CLAUDE.md & agents)
│   │   └── settings.json
│   ├── docs/specs/                      ← эта спека
│   ├── bootstrap.sh
│   ├── sync-all.sh
│   └── go.work.example
├── kacho-proto/                           git: kacho-proto
│   ├── proto/kacho/cloud/<domain>/v1/   ← proto-определения
│   ├── gen/go/kacho/cloud/<domain>/v1/  ← сгенерированные stubs (committed)
│   ├── buf.yaml + buf.gen.yaml + buf.lock
│   └── Makefile
├── kacho-corelib/                       git: kacho-corelib
│   ├── ids/                             ← UUID-helpers
│   ├── errors/                          ← google.rpc.Status mapping
│   ├── db/                              ← pgx pool, transactor
│   ├── selector/                        ← FieldSelector + LabelSelector parser & SQL-builder
│   ├── watch/                           ← in-process Watch Hub
│   ├── outbox/                          ← outbox writer wrappers
│   ├── grpcsrv/                         ← gRPC server bootstrap
│   ├── grpcclient/                      ← gRPC client factory
│   ├── observability/                   ← otel + slog setup
│   ├── config/                          ← envconfig wrapper
│   ├── audit/                           ← AuditLogger (no-op в текущей фазе)
│   └── migrations/common/               ← общие миграции (resource_events, sequence)
├── kacho-api-gateway/                   git: kacho-api-gateway
├── kacho-resource-manager/              git: kacho-resource-manager
├── kacho-vpc/                           git: kacho-vpc
├── kacho-compute/                       git: kacho-compute
├── kacho-loadbalancer/                  git: kacho-loadbalancer
└── kacho-deploy/                        git: kacho-deploy
    ├── kind/                            ← create-cluster.sh, kind-config.yaml
    ├── helm/umbrella/                   ← umbrella chart
    ├── helm/postgres/                   ← общий Postgres-chart (alias-используется per-сервис)
    ├── helm/ingress/                    ← nginx-ingress конфиг
    └── Makefile (dev-up, dev-down, reload-svc)
```

### 1.1 Структура сервисного репо (шаблон)

```
kacho-<svc>/
├── cmd/<svc>/main.go                    ← entry point: subcommand `migrate` и `serve`
├── internal/
│   ├── domain/                          ← доменные типы
│   ├── service/                         ← реализация *ServiceServer из proto
│   ├── repo/                            ← Postgres-репозитории (sqlc + handwritten)
│   │   ├── queries/*.sql                ← аннотированные запросы для sqlc
│   │   ├── gen/                         ← sqlc output (committed)
│   │   └── *.go                         ← handwritten wrappers
│   ├── reconciler/                      ← фоновые воркеры (только compute и loadbalancer)
│   ├── clients/                         ← gRPC-клиенты к peer-сервисам
│   └── config/
├── migrations/                          ← goose .sql + копия common/ из corelib
├── deploy/
│   ├── Chart.yaml + values.yaml + values.dev.yaml
│   └── templates/
│       ├── deployment.yaml              ← initContainer (migrate) + container (serve)
│       ├── service.yaml
│       ├── configmap.yaml
│       ├── secret.yaml
│       └── servicemonitor.yaml          ← закомментирован
├── go.mod / go.sum
├── Dockerfile                           ← multi-stage: builder + FROM scratch
├── Makefile
└── .github/workflows/ci.yaml
```

### 1.2 Тулинг (общий стек)

- **Go 1.22+**
- **buf** (lint, breaking, generate)
- **`google.golang.org/grpc`** + **`grpc-ecosystem/grpc-gateway/v2`**
- **`mwitkow/grpc-proxy`** (для api-gateway)
- **`jackc/pgx/v5`** + **`sqlc`**
- **`pressly/goose`** (миграции)
- **`log/slog`** (логирование)
- **OpenTelemetry SDK**
- **`kelseyhightower/envconfig`** (конфиг)
- **`testify/require`** + **`testcontainers-go`** (тесты)
- **`golangci-lint`** (линтер)
- **Helm**, **kind**, **kubectl**, **docker**

## 2. Локальная разработка

### 2.1 Bootstrap

Разработчик начинает с пустой директории `cloud-demo/`:

```bash
cd cloud-demo
git clone git@github.com:PRO-Robotech/kacho-workspace.git
./kacho-workspace/bootstrap.sh
# Скрипт клонирует все kacho-* репо как соседние папки.
cp kacho-workspace/go.work.example go.work
# go.work не коммитится, локальный артефакт.
```

В результате `cloud-demo/` содержит все репо как siblings, `go.work` объединяет их в Go workspace для локальной кросс-репо разработки.

### 2.2 Поднятие dev-стенда

```bash
cd kacho-deploy
make dev-up
```

Цепочка:
1. `kind create cluster --config kind/kind-config.yaml --name kacho`.
2. `kubectl apply -f` для namespace `kacho`.
3. `helm dependency update` в `helm/umbrella/`.
4. Сборка docker-images каждого сервиса (`make docker` в каждом репо), загрузка через `kind load docker-image`.
5. `helm install kacho-umbrella helm/umbrella/ -n kacho -f helm/umbrella/values.dev.yaml`.
6. Ожидание ready-status всех Pod-ов.
7. Вывод сообщения «доступно на http://api.kacho.local» с напоминанием добавить запись в `/etc/hosts`.

`make dev-down` — `kind delete cluster --name kacho`.

### 2.3 Hot-reload одного сервиса

```bash
make reload-svc SVC=compute
```

Цепочка:
1. `cd ../kacho-compute && docker build -t kacho-compute:dev .`
2. `kind load docker-image kacho-compute:dev --name kacho`
3. `kubectl rollout restart -n kacho deployment/compute`
4. Ожидание ready.

### 2.4 Прочие make-цели

| Цель | Что делает |
|---|---|
| `make logs-svc SVC=compute` | `kubectl logs -f deploy/compute -n kacho` |
| `make psql SVC=compute` | подключиться к pg-compute (psql внутри pod-а) |
| `make integration-test` | поднимает testcontainers-Postgres локально (не kind), прогоняет integration-тесты |
| `make e2e-test` | grpcurl/curl против `api.kacho.local`, проверяет основные сценарии |

## 3. kind cluster config

`kacho-deploy/kind/kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
```

`/etc/hosts` host-машины:

```
127.0.0.1 api.kacho.local kacho.local
```

## 4. Helm umbrella chart

`kacho-deploy/helm/umbrella/Chart.yaml`:

```yaml
apiVersion: v2
name: kacho-umbrella
version: 0.1.0
dependencies:
  - name: ingress-nginx
    version: 4.x
    repository: https://kubernetes.github.io/ingress-nginx
  - name: postgresql
    alias: pg-resource-manager
    version: 13.x
    repository: https://charts.bitnami.com/bitnami
  - name: postgresql
    alias: pg-vpc
    ...
  - name: postgresql
    alias: pg-compute
    ...
  - name: postgresql
    alias: pg-loadbalancer
    ...
  - name: api-gateway
    version: 0.1.0
    repository: file://../../../kacho-api-gateway/deploy
  - name: resource-manager
    version: 0.1.0
    repository: file://../../../kacho-resource-manager/deploy
  - name: vpc
    version: 0.1.0
    repository: file://../../../kacho-vpc/deploy
  - name: compute
    version: 0.1.0
    repository: file://../../../kacho-compute/deploy
  - name: loadbalancer
    version: 0.1.0
    repository: file://../../../kacho-loadbalancer/deploy
```

`templates/ingress.yaml` маршрутизирует `api.kacho.local` → service `api-gateway:8080`.

## 5. Postgres per service (dev)

Каждая БД — отдельный StatefulSet через Bitnami Postgres chart:

| Alias | БД | User | Password |
|---|---|---|---|
| `pg-resource-manager` | `kacho_resource_manager` | `resource_manager` | dev-cred (генерится umbrella) |
| `pg-vpc` | `kacho_vpc` | `vpc` | dev-cred |
| `pg-compute` | `kacho_compute` | `compute` | dev-cred |
| `pg-loadbalancer` | `kacho_loadbalancer` | `loadbalancer` | dev-cred |

Persistence: **emptyDir** (в `values.dev.yaml`). Данные пропадают при `dev-down` — это сознательно, для воспроизводимости тестов.

Production (вне scope текущей фазы): PVC + replication + backup.

Креденциалы хранятся в k8s `Secret <svc>-db-credentials` (генерируются helm-init-job-ом). Каждый сервис монтирует только свой Secret через `valueFrom.secretKeyRef`.

## 6. Сервисный helm-chart (детали)

`kacho-<svc>/deploy/templates/deployment.yaml` (упрощённо):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: kacho
spec:
  replicas: {{ .Values.replicas }}
  template:
    spec:
      initContainers:
        - name: migrate
          image: "{{ .Values.image }}"
          command: ["/usr/local/bin/{{ .Values.name }}", "migrate", "up"]
          env:
            - name: KACHO_{{ .Values.name | upper }}_DB_DSN
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.name }}-db-credentials
                  key: dsn
      containers:
        - name: {{ .Values.name }}
          image: "{{ .Values.image }}"
          command: ["/usr/local/bin/{{ .Values.name }}", "serve"]
          ports:
            - name: grpc
              containerPort: 9090
            - name: rest
              containerPort: 8080
            - name: metrics
              containerPort: 9091
          readinessProbe:
            httpGet: { path: /readyz, port: 8080 }
          livenessProbe:
            httpGet: { path: /healthz, port: 8080 }
          env:
            - name: KACHO_{{ .Values.name | upper }}_DB_DSN
              valueFrom: { secretKeyRef: { ... } }
            - name: KACHO_{{ .Values.name | upper }}_GRPC_PORT
              value: "9090"
            - name: KACHO_{{ .Values.name | upper }}_REST_PORT
              value: "8080"
```

`Service` экспонирует `9090` (gRPC) и `8080` (REST/health). API-gateway ходит на `9090`. Ingress (на api-gateway) ходит на `8080`.

## 7. Конвенции CI per repo

Каждое сервисное репо имеет `.github/workflows/ci.yaml` (упрощённо):

```yaml
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_USER: test, POSTGRES_PASSWORD: test, POSTGRES_DB: test }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - run: make lint
      - run: make test
      - run: make integration-test
  build:
    needs: test
    steps:
      - run: make docker
      - run: docker push prorobotech/kacho-<svc>:${{ github.sha }}
```

`kacho-proto`-репо имеет дополнительный CI-step `buf breaking` против предыдущего тега — защита от breaking changes.

## 8. CLAUDE.md иерархия

Claude Code читает CLAUDE.md по дереву от текущей рабочей папки до `~`:

1. **`~/.claude/CLAUDE.md`** — пользовательские предпочтения (язык ответов, стиль). Не трогаем.
2. **`cloud-demo/kacho-workspace/CLAUDE.md`** — workspace-уровень: общая архитектура, naming, ссылки на документы.
3. **`cloud-demo/kacho-<svc>/CLAUDE.md`** — service-уровень: как собрать, протестировать, миграции, специфика.

`kacho-workspace/CLAUDE.md` содержит executive summary (сводно из этой спеки + ссылки), общие конвенции, запреты («НЕ упоминать yandex в handwritten коде», «НЕ ORM», «НЕ редактировать применённые миграции»), команды для частых задач. См. раздел 7 `kacho-workspace/CLAUDE.md` после первого `make dev-up`.

## 9. Subagents (`.claude/agents/`)

В `kacho-workspace/.claude/agents/` живут 12 кастомных агентов (project-level, видны Claude Code из любой подпапки workspace). Они делятся на task-execution (делают работу — 7 шт) и specialist-review (дают экспертный взгляд — 5 шт).

### 9.1 Task-execution агенты (делают работу)

| Агент | Назначение |
|---|---|
| `acceptance-author` | **Первый агент в любой итерации.** Пишет acceptance-документ на человеко-читаемом языке (Given-When-Then) для нового RPC / sub-фазы / фичи. Использует данные из `02-data-model-and-conventions.md` для понимания, какие сценарии возможны. Output — markdown-файл в `kacho-workspace/docs/specs/`. Передаёт на approve агенту `acceptance-reviewer` (заказчик не подключается) **до** старта кодирования |
| `proto-sync` | синхронизация upstream-источников proto-определений (если будем подсматривать YC); rewrite `yandex.cloud → kacho.cloud` |
| `service-scaffolder` | создание нового сервисного репо из шаблона |
| `rpc-implementer` | реализация одного RPC end-to-end **по утверждённому acceptance-документу**: TDD — сначала исполняемые тесты по сценариям документа (red), затем proto → handler → repo → миграция (green), потом refactor |
| `migration-writer` | написание goose-миграций по конвенциям |
| `api-gateway-registrar` | обновление маршрутизации в api-gateway при добавлении нового сервиса/RPC |
| `integration-tester` | конвертация утверждённого acceptance-документа в исполняемые integration-тесты (`testcontainers-go` + Postgres) и e2e-bash-сценарии (`kacho-deploy/e2e/<sub-phase>/*.sh` через grpcurl). Один сценарий acceptance → один integration-тест + один e2e-сценарий |

### 9.2 Specialist-review агенты (дают экспертный взгляд)

| Агент | Назначение |
|---|---|
| `acceptance-reviewer` | **Approval gate для acceptance-документа.** Ревьюит черновик от `acceptance-author` на coverage спеки, полноту сценариев (positive/negative/edge), traceability, реалистичность scope. Возвращает `✅ APPROVED` или `❌ CHANGES REQUESTED` с конкретными замечаниями. Заказчик не подключается к этому шагу — он проверяет финальный smoke (см. `04-roadmap-and-phasing.md` §2 шаг 2) |
| `system-design-reviewer` | ревью архитектурных решений с точки зрения distributed systems best practices |
| `db-architect-reviewer` | ревью схем и миграций: индексы, FK-стратегия, JSONB vs scalar, OCC, keyset pagination |
| `go-style-reviewer` | Go-специфичный clean code: error handling, context, generics, naming |
| `proto-api-reviewer` | ревью proto-изменений: backward-compat, validation-аннотации, отсутствие `yandex` в `proto/kacho/`, buf-lint clean |

### 9.3 Используем готовые (ничего не настраиваем)

- `Explore`, `Plan`, `general-purpose`
- `superpowers:code-reviewer`, `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:requesting-code-review`

## 10. `.claude/settings.json` workspace-level

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```

Локальная dev-машина — все Bash/Edit/Write автоматически разрешены. Можно ужесточить позже без переписывания агентов.

## 11. Запреты (закреплены в `kacho-workspace/CLAUDE.md`)

- **НЕ начинать кодирование** до утверждения acceptance-документа в формате Given-When-Then (см. `04-roadmap-and-phasing.md` §2). Контракт фиксируется текстом перед кодом, не наоборот.
- НЕ упоминать «yandex» в handwritten-коде, README, комментариях, env-name, именах функций.
- НЕ использовать ORM (gorm, ent, bun). sqlc + handwritten pgx.
- НЕ делать каскадное удаление через границу сервиса (только same-DB FK cascade).
- НЕ редактировать применённую миграцию. Только новая миграция.
- НЕ писать в `status` через `/upsert` handler; только через `/upd-status` (internal).
- НЕ маршрутизировать `Internal.*` методы через api-gateway наружу.
- НЕ вводить broker (Kafka/NATS) до тех пор, пока in-process Watch Hub справляется с нагрузкой.
- НЕ создавать новые «единые» БД — только database-per-service.
