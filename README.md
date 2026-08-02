# kacho-workspace

Корневой workspace-репо продукта **Kachō** — самостоятельной облачной control-plane
платформы (только control plane, без data plane). Домены: **IAM**
(Account / Project / User / ServiceAccount / Group / Role / AccessBinding), **VPC**
(Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / NetworkInterface),
**Compute** (Instance / Disk / Image / Snapshot / DiskType + Geography Region/Zone).

API — **плоские ресурсы** (flat message с domain-полями на верхнем уровне, без
вложенного envelope) + **асинхронные `Operation`** на каждой мутации. Чтения
(`Get`/`List`) синхронны; мутации (`Create`/`Update`/`Delete` и domain-действия)
возвращают `Operation`, клиент поллит `OperationService.Get(id)` до `done=true`.
Серверного Watch-стриминга нет — клиент опрашивает `List` (2–5 c) и `OperationService.Get`.

Workspace содержит общий `CLAUDE.md`, каноническую AI-оснастку (`.claude/`),
спецификации (`docs/specs/`) и bootstrap/sync-скрипты.

## Структура

```
kacho-workspace/             ← этот репо (git)
├── CLAUDE.md                ← тонкий индекс правил (загружает .claude/rules/*)
├── .claude/                 ← ИСТОЧНИК ИСТИНЫ AI-оснастки:
│   ├── rules/               ← модульные правила (generic)
│   ├── agents/              ← generic-субагенты (роли)
│   ├── skills/              ← generic-скилы (экспертиза)
│   ├── hooks/               ← дисциплинарные hooks
│   └── settings.json        ← permissions + hook-конфиг
├── docs/specs/             ← спека: 00–04 (книга) + acceptance-трейл + CHANGELOG
├── bootstrap.sh             ← клонирует sibling-репо в ./project/
├── sync-all.sh              ← ff-pull workspace + рабочих копий продукта
├── go.work.example          ← копируется в project/go.work
└── project/                 ← gitignore'd; контейнер sibling-репо
    ├── kacho-proto/         ← единственный дом всех .proto + gen-stubs
    ├── kacho-corelib/       ← переиспользуемые Go-пакеты
    ├── kacho-api-gateway/   ← edge: gRPC-proxy + grpc-gateway REST
    ├── kacho-iam/           ← Account/Project/User/SA/Group/Role/AccessBinding
    ├── kacho-vpc/           ← Network/Subnet/SG/RouteTable/Address/Gateway/NIC
    ├── kacho-compute/       ← Instance/Disk/Image/Snapshot/DiskType + Geography
    ├── kacho-nlb/           ← NetworkLoadBalancer/TargetGroup (планируется)
    ├── kacho-ui/            ← Vite + React SPA control plane
    ├── kacho-deploy/        ← dev-стенд (Postgres + ingress) + e2e
    └── kacho-vpc-operator/  ← data-plane sibling (spec-only, вне build-графа)
```

`project/` под gitignore — каждое sibling-репо имеет собственный `.git/` и
публикуется отдельно (`git@github.com:PRO-Robotech/<repo>.git`). Список имён —
в `bootstrap.sh::REPOS`. Build-граф: `kacho-proto → kacho-corelib → сервисы →
kacho-api-gateway → kacho-deploy` (см. `CLAUDE.md` и `.claude/rules/polyrepo.md`).

## AI-оснастка: единственный экземпляр, копий нет

`kacho-workspace/.claude` — **единственное** место, где живут правила, агенты, скилы,
hooks и `settings.json`. Копий в рабочих копиях продукта **не заводится**, раскатки как
механизма **не существует** (решение владельца 2026-08-02).

Прежняя модель дублировала оснастку в каждый `project/<repo>/.claude` и обосновывала это
тем, что hooks якобы не достают до воркспейса из вложенного каталога. **Обоснование
оказалось ложным**: журнал hook'а содержит срабатывания по деревьям, где нет ни своего
`settings.json`, ни своих hooks, — hook следует за **сессией**, а не за деревом файла.
Копии не были нужны ни для чего, и механизм снят целиком вместе со своим обоснованием.

- **Правка оснастки — только здесь.** Больше нигде её нет.
- **Domain-оснастка** (`vpc-*`, `compute-*`, `<svc>-load-testing`) живёт рядом с generic,
  в том же `.claude/`.
- **Отдельно склонированный `PRO-Robotech/kacho` оснастки не несёт и не должен.** Правила —
  инструмент разработки, а не часть поставки продукта. Проверки, обязанные работать в CI
  продукта, живут **в продукте** (`internal/repohygiene`, `tools/`, `scripts/`, Makefile).

## Развернуть workspace на новой машине

```bash
git clone git@github.com:PRO-Robotech/kacho-workspace.git
cd kacho-workspace
./bootstrap.sh                      # клонирует монорепо в ./project/kacho
cd project/kacho/deploy && make dev-up
```

## Sync

```bash
./sync-all.sh   # ff-pull workspace + рабочих копий продукта
```
