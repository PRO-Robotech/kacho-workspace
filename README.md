# kacho-workspace

Корневой workspace-репо проекта Kachō. Содержит общий `CLAUDE.md`, кастомных
субагентов (`.claude/agents/`), спецификации (`docs/specs/`), планы
(`docs/plans/`) и bootstrap-скрипты.

## Структура

```
kacho-workspace/             ← этот репо (git)
├── CLAUDE.md                ← общие правила, naming, запреты
├── .claude/agents/          ← project-level субагенты, видны
│                              из любой подпапки project/ через
│                              parent-walkup discovery Claude Code
├── docs/                    ← specs, plans, qa
├── bootstrap.sh             ← клонирует sibling-репо в ./project/
├── sync-all.sh              ← ff-pull workspace + всех project/*
├── go.work.example          ← копируется в project/go.work
└── project/                 ← gitignore'd; контейнер sibling-репо
    ├── kacho-proto/
    ├── kacho-corelib/
    ├── kacho-vpc/
    └── ... (см. CLAUDE.md §«Структура репозиториев»)
```

`project/` под gitignore — каждое sibling-репо имеет собственный `.git/`
и публикуется отдельно. Workspace знает только список имён через
`bootstrap.sh::REPOS`.

## Развернуть workspace на новой машине

```bash
git clone git@github.com:PRO-Robotech/kacho-workspace.git
cd kacho-workspace
./bootstrap.sh                      # клонирует все sibling в ./project/
cp go.work.example project/go.work  # multi-module Go workspace
cd project/kacho-deploy && make dev-up
```

## Sync

```bash
./sync-all.sh   # ff-pull workspace + всех project/* repo
```
