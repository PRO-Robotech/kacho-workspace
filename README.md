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
├── CLAUDE.md                ← общий протокол: модель загрузки, контракт возврата; правил НЕ несёт
├── .claude/                 ← ИСТОЧНИК ИСТИНЫ AI-оснастки:
│   ├── rules/               ← корпус; с автозагрузки снят, доезжает закреплением за агентом
│   ├── agents/              ← dispatcher (главный поток) + исполнители (роли)
│   ├── skills/              ← экспертиза + `rule-<имя>/SKILL.md` — ссылки на правила
│   ├── hooks/               ← дисциплинарные hooks
│   └── settings.json        ← permissions + hooks + `agent` + `claudeMdExcludes`
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
- **Domain-оснастка живёт рядом с generic, в том же `.claude/`** — когда она заводится.
  Сейчас её в дереве нет: `ls .claude/agents/ | grep -cE '^(vpc|compute)-'` → 0 и то же по
  `.claude/skills/` → 0. Доменное покрывают generic-агенты и скилы вроде `load-testing-coach`.
- **Отдельно склонированный `PRO-Robotech/kacho` оснастки не несёт и не должен.** Правила —
  инструмент разработки, а не часть поставки продукта. Проверки, обязанные работать в CI
  продукта, живут **в продукте** (`internal/repohygiene`, `tools/`, `scripts/`, Makefile).

## Правила не грузятся сами: диспетчер и закрепление

Решение владельца **2026-09-17** отменяет прежнее («весь корпус каждому агенту, всегда»,
2026-09-13). Каталог правил снят с автозагрузки — `.claude/settings.json` →
`claudeMdExcludes: ["**/.claude/rules/**"]`, и корневой `CLAUDE.md` корпус не импортирует
(`grep -c '^@' CLAUDE.md` → 0). Сам `CLAUDE.md` перестал быть индексом правил: теперь это
общий протокол воркспейса — модель загрузки, контракт возврата, топология.

- **Главный поток — агент `dispatcher`** (`.claude/settings.json` → `agent: "dispatcher"`).
  Его тело `.claude/agents/dispatcher.md` заменяет системный промпт и является единственной
  базой маршрутизации. У диспетчера нет ни `Read`, ни `Bash`, ни `Edit`: всякий факт он
  получает возвратом исполнителя, а сам только решает, кого и в каком порядке запускать.
- **Правило доезжает до агента закреплением.** У правила есть скилл-ссылка
  `.claude/skills/rule-<имя>/SKILL.md → ../../rules/<имя>.md`
  (`find .claude/skills -name SKILL.md -type l | wc -l` → 30 при
  `ls .claude/rules/*.md | wc -l` → 30), агент перечисляет свои правила во frontmatter
  `skills:`, и харнесс грузит их при старте целиком. Нужное лишь при условии берётся
  по триггеру инструментом `Skill`.
- **Объявление и исполнение — разные места.** Объявление — `.claude/rules/MANIFEST.md`,
  колонка «закреплено за агентами»; исполнение — frontmatter агента; сверяет их
  `scripts/rules-gate/`.
- **Исполнители не запускают исполнителей** (`disallowedTools: Agent`): последовательность
  выставляет диспетчер по возврату. Форма возврата — в `CLAUDE.md`.
- **Исполнителей 31** (`ls .claude/agents/*.md | grep -vc dispatcher`) плюс диспетчер.

Цена набора считается **на агента**, а не на волну, и названа в одном месте —
`.claude/rules/01-wave-contract.md` §«Кто какое правило держит»; здесь она не пересказывается.
Сессия без диспетчера, если она нужна человеку: `claude --agent <имя исполнителя>`.

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
