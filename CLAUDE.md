# Kachō — Workspace CLAUDE.md

Корневой индекс монорепо-воркспейса. Тонкий: `@import` модульных правил
(`.claude/rules/*.md`) + workspace-операционка (dev-стенд, sync). Identity /
naming / non-negotiables вынесены в `@.claude/rules/00-kacho-core.md`.

## Модель оснастки: self-sufficient репо + sync из workspace

AI-оснастка (rules / agents / skills / hooks / settings) **физически дублируется в
каждом `project/<repo>/.claude/`**, чтобы репо работал и при standalone-клоне (CI,
свежий checkout, отдельный контрибьютор) — `settings.json`/hooks вообще не делают
parent-walkup. **Workspace — единственный источник истины**; копии генерируются
скриптом `./sync-tooling.sh` (вшит в `./sync-all.sh`).

- **Правишь generic-оснастку → только в `kacho-workspace/.claude/`**, затем
  `./sync-tooling.sh` раскатывает во все репо. Копию в репо руками не редактируй.
- **Domain-агенты/скилы** (`vpc-*`, `compute-*`, `<svc>-load-testing`) — нативные в
  своём репо, sync их не трогает.
- Каждый `project/<repo>/CLAUDE.md` сам `@import`-ит локальные `.claude/rules/*`
  (включая `00-kacho-core.md`) — поэтому standalone-репо самодостаточен.
- Подробности модели и канонический список — `@.claude/rules/ai-tooling.md`.

## Модульные правила (@import)

@.claude/rules/00-kacho-core.md
@.claude/rules/api-conventions.md
@.claude/rules/polyrepo.md
@.claude/rules/architecture.md
@.claude/rules/data-integrity.md
@.claude/rules/security.md
@.claude/rules/git-youtrack.md
@.claude/rules/testing.md
@.claude/rules/vault.md
@.claude/rules/ai-tooling.md

## Локальная разработка

- Стенд: `cd project/kacho-deploy && make dev-up` / `make dev-down`
- Перезапуск сервиса: `make reload-svc SVC=<vpc|compute|iam>` · логи: `make logs-svc SVC=…` · psql: `make psql SVC=…`
- Обновить все репо (git pull): `./sync-all.sh` (вызывает `./sync-tooling.sh`)
- Раскатать оснастку в репо вручную: `./sync-tooling.sh`
- Спека (5 docs): `docs/specs/0{0..4}-*.md`

## Permissions

`.claude/settings.json` — `bypassPermissions` (локальная dev-машина) + vault-discipline
hooks (`UserPromptSubmit` / `Stop`, портируемые через `$CLAUDE_PROJECT_DIR`).
Файл синхронизируется в каждый репо `./sync-tooling.sh`.
