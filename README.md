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
спецификации (`docs/specs/`), планы (`docs/plans/`) и bootstrap/sync-скрипты.

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
├── docs/                    ← specs (00..04), plans, qa
├── bootstrap.sh             ← клонирует sibling-репо в ./project/
├── sync-tooling.sh          ← раскатывает .claude во все project/<repo>
├── sync-all.sh              ← ff-pull workspace + project/* + sync-tooling
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

## AI-оснастка: один источник истины + полные копии в репо

`kacho-workspace/.claude` — **единственный** источник истины для правил, агентов,
скилов, hooks и `settings.json`. Каждый `project/<repo>` получает **полную
самодостаточную копию** этой оснастки, чтобы репо работал при standalone-клоне
(свежий checkout / CI), где parent-walkup до workspace недоступен.

- **Раскатка**: `./sync-tooling.sh` зеркалит `.claude` (rules + generic agents +
  generic skills + hooks + settings.json) во все `project/<repo>/.claude`.
  Идемпотентно; вшит в `./sync-all.sh`.
- **Domain-оснастка** (`<domain>-*` агенты/скилы, напр. `vpc-*`, `compute-*`) —
  нативна в своём репо; sync-скрипт её не трогает. Устаревшие generic-копии — удаляет.
- **Правка generic-оснастки — ТОЛЬКО в `kacho-workspace/.claude`**, затем
  `./sync-tooling.sh`. Копию в репо не редактировать (перетрётся при следующем sync).

## Развернуть workspace на новой машине

```bash
git clone git@github.com:PRO-Robotech/kacho-workspace.git
cd kacho-workspace
./bootstrap.sh                      # клонирует все sibling в ./project/
cp go.work.example project/go.work  # multi-module Go workspace
./sync-tooling.sh                   # раскатать .claude во все репо
cd project/kacho-deploy && make dev-up
```

## Sync

```bash
./sync-all.sh   # ff-pull workspace + всех project/* + sync-tooling.sh
```
