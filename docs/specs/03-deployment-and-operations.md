# Kachō — Развёртывание и эксплуатация

**Документ:** 03 / 5

Архитектура из `01-architecture-and-services.md` (gRPC control plane, async
`Operation`, transactional outbox) и конвенции из `02-data-model-and-conventions.md`
(flat-ресурсы, error-format, ID-prefix) собираются в один развёртываемый стенд. Эта
глава описывает физику: polyrepo-структуру, шаблон сервисного репо, локальную
разработку на kind, helm, Postgres-per-service, CI и наблюдаемость.

## 1. Polyrepo: структура и build-граф

Все репо живут в `github.com/PRO-Robotech/`. Workspace (`kacho-workspace`) — корневой
git-репо; sibling-репо клонируются в `./project/` через `bootstrap.sh` (`project/` под
gitignore, у каждого собственный `.git`). Сервисы — самостоятельные модули: склонировал
→ собрал, между собой связаны только runtime-API.

| Репо | Роль |
|---|---|
| `kacho-workspace` | корень: CLAUDE.md/rules, общие агенты, спеки, `bootstrap.sh`, `sync-tooling.sh` |
| `kacho-proto` | **единственный** дом всех `.proto` (`proto/kacho/cloud/<domain>/v1/`) + commit-нутые Go-stubs (`gen/go/...`) |
| `kacho-corelib` | горизонтальные Go-пакеты (ids / errors / config / observability / db / operations / outbox / …) |
| `kacho-api-gateway` | edge: gRPC-proxy + grpc-gateway REST. БД нет, бизнес-логики нет |
| `kacho-iam` | Account / Project / User / ServiceAccount / Group / Role / AccessBinding (`kacho_iam`) |
| `kacho-vpc` | Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / NetworkInterface (`kacho_vpc`) |
| `kacho-compute` | Instance / Disk / Image / Snapshot / DiskType + Geography Region/Zone (`kacho_compute`) |
| `kacho-nlb` *(планируется)* | NetworkLoadBalancer / TargetGroup (`kacho_nlb`) |
| `kacho-deploy` | dev-стенд (kind + helm + Postgres + ingress) + e2e |
| `kacho-ui` | Vite + React SPA control plane |
| `kacho-vpc-operator` | data-plane sibling VPC — spec-only, вне build-графа control plane |

**Build-граф** (источник истины — `replace github.com/PRO-Robotech/…` в `*/go.mod`):

```
kacho-proto                 ← ни от чего внутри проекта не зависит
  └─ kacho-corelib          ← replace ../kacho-proto
       ├─ kacho-iam         ┐ каждый сервис: replace ../kacho-corelib + ../kacho-proto
       ├─ kacho-vpc         │ между собой сервисы НЕ зависят по build (DB-per-service,
       ├─ kacho-compute     │ общение только по runtime-API)
       └─ kacho-api-gateway ┘ (api-gateway импортирует proto-stubs всех доменов)
kacho-deploy   ← Dockerfile'ы COPY ../kacho-*; build-context = parent dir
kacho-ui       ← зависит от REST api-gateway в runtime (не build)
```

`replace ../` — осознанный выбор для polyrepo-dev в одном дереве; переход на versioned
modules зарезервирован под релизную фазу. Новый `.proto` всегда заводится в `kacho-proto`;
сервисные репо `.proto` не держат, только Go-импорт сгенерированных stubs.

Кросс-репо фича катится топосортом графа: `kacho-proto` → `kacho-corelib` → сервис(ы) →
`kacho-api-gateway` → `kacho-deploy` → `kacho-workspace` (docs). Подробности — в
`.claude/rules/polyrepo.md`.

## 2. Шаблон сервисного репо

Каждый доменный сервис следует Clean Architecture (`.claude/rules/architecture.md`):
`domain ← use-case ← repo/clients/handler`, единственная точка wiring — `cmd`.

```
kacho-<svc>/
├── cmd/
│   ├── <svc>/main.go               ← composition root: serve (gRPC :9090 + :9091, health :8080)
│   └── migrator/main.go            ← отдельный CLI миграций (goose, cobra)
├── internal/
│   ├── domain/                     ← entities + Validate(); только stdlib + kacho-proto
│   ├── apps/kacho/api/<resource>/  ← use-cases (per-RPC); определяют port-интерфейсы
│   ├── apps/kacho/config/          ← viper YAML config
│   ├── repo/                       ← adapter: pgx + sqlc (queries/*.sql → gen/), CQRS Reader/Writer
│   ├── clients/                    ← adapter: gRPC-клиенты к peer-сервисам (iam/vpc/compute)
│   ├── handler/                    ← тонкий gRPC transport: parse → use-case → format
│   ├── tenant/                     ← нейтральный носитель caller-identity (для authz)
│   └── migrations/                 ← goose .sql (embed.FS); схема kacho_<domain>
├── deploy/
│   ├── Chart.yaml + values.yaml + values.dev.yaml
│   └── templates/                  ← deployment (initContainer migrate + serve), service, configmap, secret
├── tests/newman/                   ← cases/*.py → gen.py → коллекции (black-box через api-gateway)
├── go.mod / go.sum
├── Dockerfile                      ← multi-stage builder + минимальный runtime-образ
├── Makefile
└── .github/workflows/ci.yaml
```

Запреты слоёв: `domain`/use-case не импортируют pgx/grpc-stubs/sqlc-типы; бизнес-логика
не живёт в `handler`; глобальные синглтоны — только в `cmd`. Конфиг — **YAML через viper**
(не struct-tag-конфиг), секреты приходят из env поверх YAML. Каноничный Go-style ruleset —
skill `evgeniy`.

### Общий стек

- Go 1.25 · `google.golang.org/grpc` + `grpc-ecosystem/grpc-gateway/v2`.
- `buf` (lint / breaking / generate) — в `kacho-proto`.
- `jackc/pgx/v5` + `sqlc` (типизированные запросы) + `pressly/goose` (миграции). Без ORM.
- `log/slog` + OpenTelemetry SDK (логи / метрики / трейсы).
- `spf13/viper` (YAML-config) · `testify` + `testcontainers-go` + Newman (тесты).
- Docker · Helm · kind · `golangci-lint` · `govulncheck`.

## 3. Локальная разработка

### 3.1 Bootstrap

Разработчик клонирует workspace и разворачивает siblings одним скриптом:

```bash
git clone git@github.com:PRO-Robotech/kacho-workspace.git
cd kacho-workspace
./bootstrap.sh          # клонирует все kacho-* репо в ./project/
cp go.work.example go.work   # объединяет репо в Go workspace (не коммитится)
```

`go.work` — локальный артефакт для кросс-репо навигации/сборки в одном дереве.
`./sync-tooling.sh` (вшит в `./sync-all.sh`) раскатывает generic AI-оснастку (rules /
агенты / скилы / hooks) из `kacho-workspace/.claude/` в каждый `project/<repo>/.claude/`,
чтобы репо был самодостаточен при standalone-клоне; источник истины — workspace, копии в
репо руками не редактируются.

### 3.2 Поднятие стенда

```bash
cd project/kacho-deploy
make dev-up      # kind create cluster → build образов → kind load → helm install → wait ready
make dev-down    # kind delete cluster
```

`make dev-up` (после `preflight`-проверки тулинга): создаёт kind-кластер, собирает
docker-образы сервисов (build-context = parent dir, Dockerfile `COPY ../kacho-*`),
загружает их в кластер через `kind load`, ставит umbrella-chart с `values.dev.yaml`,
ждёт ready всех Pod-ов и печатает endpoint api-gateway. Для REST-доступа host добавляет
запись в `/etc/hosts`.

### 3.3 Итерация по одному сервису

| Цель | Что делает |
|---|---|
| `make reload-svc SVC=<iam\|vpc\|compute\|nlb>` | rebuild образа → `kind load` → `kubectl rollout restart` → wait ready |
| `make logs-svc SVC=<svc>` | `kubectl logs -f` нужного deployment |
| `make psql SVC=<svc>` | psql внутрь Postgres-пода схемы `kacho_<domain>` |
| `make e2e-test` | newman/grpcurl против REST api-gateway (port-forward → `localhost:18080`) |

Integration-тесты (testcontainers Postgres) гоняются локально в каждом сервисном репо
(`make test`), без kind. Методология тестов — `.claude/rules/testing.md`.

## 4. kind cluster + helm umbrella

### 4.1 kind config

`kacho-deploy/kind/kind-config.yaml` поднимает single-node control-plane с
ingress-ready node-label и проброшенным портом 80:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - { containerPort: 80, hostPort: 80, protocol: TCP }
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
```

Все рабочие нагрузки — в namespace `kacho`. REST-доступ снаружи — через ingress на
api-gateway по hostname, прописанному в `/etc/hosts` host-машины.

### 4.2 Umbrella-chart

`kacho-deploy/helm/umbrella/` агрегирует ingress, по одному Postgres на сервис и сами
сервисы (subchart на каждый домен):

```yaml
apiVersion: v2
name: kacho-umbrella
version: 0.1.0
dependencies:
  - { name: ingress-nginx, repository: "https://kubernetes.github.io/ingress-nginx" }
  - { name: postgresql, alias: pg-iam,     repository: "https://charts.bitnami.com/bitnami" }
  - { name: postgresql, alias: pg-vpc,     repository: "https://charts.bitnami.com/bitnami" }
  - { name: postgresql, alias: pg-compute, repository: "https://charts.bitnami.com/bitnami" }
  - { name: postgresql, alias: pg-nlb,     repository: "https://charts.bitnami.com/bitnami" }
  - { name: api-gateway, repository: "file://../../../kacho-api-gateway/deploy" }
  - { name: iam,         repository: "file://../../../kacho-iam/deploy" }
  - { name: vpc,         repository: "file://../../../kacho-vpc/deploy" }
  - { name: compute,     repository: "file://../../../kacho-compute/deploy" }
  - { name: nlb,         repository: "file://../../../kacho-nlb/deploy" }   # планируется
```

Ingress маршрутизирует внешний REST-трафик на api-gateway. Внутрисервисные gRPC-вызовы
идут напрямую (см. §6), не через ingress.

## 5. Postgres-per-service (dev)

Database-per-service (ban #8): у каждого домена своя БД и схема `kacho_<domain>` —
общих БД нет, кросс-сервисных FK/cascade нет. В dev каждая БД — отдельный StatefulSet
Bitnami Postgres-chart:

| Alias | БД | Схема |
|---|---|---|
| `pg-iam` | `kacho_iam` | `kacho_iam` |
| `pg-vpc` | `kacho_vpc` | `kacho_vpc` |
| `pg-compute` | `kacho_compute` | `kacho_compute` |
| `pg-nlb` *(планируется)* | `kacho_nlb` | `kacho_nlb` |

Persistence в `values.dev.yaml` — эфемерная: данные пропадают при `dev-down` (сознательно,
для воспроизводимости тестов). Креды живут в k8s `Secret <svc>-db-credentials`; сервис
монтирует только свой Secret через `secretKeyRef`. Production-вариант (PVC + replication +
backup, External Secrets) — вне scope текущей фазы (см. `04-roadmap-and-phasing.md`).

Схема накатывается init-контейнером сервиса (`cmd/migrator`, goose, embed.FS) до старта
`serve`; применённые миграции не редактируются (ban #5) — только новая.

## 6. Сервисный helm-chart и порты

`kacho-<svc>/deploy/templates/deployment.yaml` (упрощённо) — initContainer прогоняет
миграции, основной контейнер обслуживает запросы:

```yaml
spec:
  template:
    spec:
      initContainers:
        - name: migrate
          image: "{{ .Values.image }}"
          command: ["/usr/local/bin/migrator", "up"]
          env:
            - name: KACHO_{{ .Values.name | upper }}_DB_DSN
              valueFrom: { secretKeyRef: { name: "{{ .Values.name }}-db-credentials", key: dsn } }
      containers:
        - name: {{ .Values.name }}
          image: "{{ .Values.image }}"
          command: ["/usr/local/bin/{{ .Values.name }}", "serve"]
          ports:
            - { name: grpc,          containerPort: 9090 }   # backend gRPC (external surface)
            - { name: grpc-internal, containerPort: 9091 }   # Internal.* (cluster-only)
            - { name: health,        containerPort: 8080 }   # healthz/readyz + /metrics
          readinessProbe: { httpGet: { path: /readyz,  port: 8080 } }
          livenessProbe:  { httpGet: { path: /healthz, port: 8080 } }
          env:
            - name: KACHO_{{ .Values.name | upper }}_DB_DSN
              valueFrom: { secretKeyRef: { ... } }
```

**Адресация (cluster-internal):** сервисы зовут друг друга напрямую по
`<svc>.kacho.svc.cluster.local:9090`. Runtime-edges (синхронный gRPC, без циклов;
`.claude/rules/polyrepo.md`):

- `kacho-vpc → kacho-compute` — валидация `zone_id` (`ZoneService.Get`; Geography — домен compute).
- `kacho-compute → kacho-vpc` — валидация NIC-spec (Subnet/SecurityGroup) + IPAM-аллокация Address.
- `* → kacho-iam` — `ProjectService.Get` (existence + account-lookup) + `InternalIAMService.Check` (authz-gate).

**api-gateway — two-listener edge:** external TLS-листенер для внешних клиентов + отдельный
cluster-internal листенер (:9091) для UI/admin-tooling. `Internal.*` методы и `Internal*`-
сервисы (`AddressPool` в kacho-vpc; admin-CRUD `Region`/`Zone`/`DiskType` в kacho-compute)
проксируются **только** на cluster-internal mux и никогда не светятся на external endpoint
(ban #6; `.claude/rules/security.md`). Регистрацию public-RPC в gateway-mux ведёт агент
`api-gateway-registrar`.

## 7. CI per repo

У каждого репо — `.github/workflows/ci.yaml`; джоба `test` поднимает Postgres-service для
integration-тестов, `build` собирает и публикует образ:

```yaml
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres: { image: postgres:16, env: { POSTGRES_USER: test, POSTGRES_PASSWORD: test, POSTGRES_DB: test } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.25' }
      - run: make lint            # golangci-lint
      - run: make test            # unit + integration (testcontainers)
      - run: govulncheck ./...
  build:
    needs: test
    steps:
      - run: make docker
      - run: docker push ghcr.io/pro-robotech/kacho-<svc>:${{ github.sha }}
```

`kacho-proto` дополнительно гоняет `buf lint` + `buf breaking` против предыдущего тега
(защита от ломающих изменений контракта). Сервисы с публичными `List<Resource>` гоняют
CI-гейт `make audit-list-filter` (каждый public List обязан фильтровать результат через
listauthz). Пока вышестоящий репо не в `main`, нижестоящий CI временно пиннит sibling-`ref`
к feature-ветке; после merge — обратно на `main`.

## 8. AI-оснастка (кратко)

Kachō разрабатывается, тестируется и сопровождается автономно через Claude Code. Оснастка —
это «команда» из четырёх слоёв:

- **rules** (`.claude/rules/*.md`) — нормативные правила (naming, api-conventions, polyrepo,
  architecture, data-integrity, security, testing, git-youtrack, vault).
- **agents** (`.claude/agents/*.md`) — роли: task-execution (acceptance-author, rpc-implementer,
  migration-writer, api-gateway-registrar, …) и specialist-review (db-architect-reviewer,
  go-style-reviewer, proto-api-reviewer, …); плюс domain-specific (`vpc-*`, `compute-*`).
- **skills** (`.claude/skills/<name>/SKILL.md`) — экспертиза (`evgeniy` — Go-style, testing-coaches,
  load-testing-coach).
- **hooks** (`.claude/settings.json`) — дисциплина исполнения (cwd-only, без parent-walkup).

Модель распространения — **self-sufficient репо + sync**: источник истины — `kacho-workspace/.claude/`;
generic-оснастка физически дублируется в каждый `project/<repo>/.claude/` через `./sync-tooling.sh`,
поэтому standalone-клон репо остаётся рабочим. Domain-агенты/скилы (`vpc-*`, `compute-*`) —
нативные в своём репо, sync их не трогает. Полный список ролей и lifecycle-гейты (acceptance-first
→ ticket → vault-context → cross-repo order → TDD → review → verify → trail) — в
`.claude/rules/ai-tooling.md`; не дублируется здесь.

## 9. Health и observability

Каждый сервис экспонирует на health-порту (:8080):

- **`/healthz`** — liveness (процесс жив); **`/readyz`** — readiness (pgx-pool поднят,
  миграции применены, peer-клиенты сконфигурированы). Probes в deployment бьют именно их.
- **`/metrics`** — Prometheus-формат через OpenTelemetry SDK: RPC-латентности/коды,
  pgx-pool, длина и лаг outbox/operations-воркера.

**Логи** — структурный `slog` (JSON в кластере), с request-id и caller-identity из
`internal/tenant`. **Трейсы** — OpenTelemetry SDK (gRPC + pgx инструментированы); spans
сшиваются по runtime-edges между сервисами. `INTERNAL`-ошибки наружу отдают фиксированный
текст без leak'а pgx/SQL (`.claude/rules/data-integrity.md`), детальная причина — только в
логах/трейсах.

Полноценный observability-стек (Loki / Grafana / Tempo / Prometheus) разворачивается в HA/
production-фазе; в dev достаточно `/metrics` + `make logs-svc`. Дорожная карта — в
`04-roadmap-and-phasing.md`.
