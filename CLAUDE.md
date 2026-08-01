# Kachō — Workspace CLAUDE.md

Корневой индекс монорепо-воркспейса. Тонкий: `@import` модульных правил
(`.claude/rules/*.md`) + workspace-операционка (dev-стенд, sync). Identity /
naming / non-negotiables вынесены в `@.claude/rules/00-kacho-core.md`.

## Топология: монорепо `PRO-Robotech/kacho` + этот workspace

Разработка ведётся в **одном** репозитории продукта — `PRO-Robotech/kacho`, клонируется в
`project/kacho`. **Оба репозитория ПУБЛИЧНЫ.** Предшествующие полирепо (`kacho-proto`,
`kacho-<svc>`, …) существуют на GitHub, но разработка в них не ведётся (последний push —
середина июля 2026); `bootstrap.sh` клонирует их только по `KACHO_CLONE_LEGACY_POLYREPOS=1`.
Раскладка каталогов монорепо и что нормативного осталось от полирепо-правил —
`@.claude/rules/polyrepo.md`.

## Модель оснастки: self-sufficient репо + sync из workspace

AI-оснастка (rules / agents / skills / hooks / settings) **физически дублируется** в
`.claude/` каждой рабочей копии продукта, чтобы репо работал и при standalone-клоне (CI,
свежий checkout, отдельный контрибьютор) — `settings.json`/hooks вообще не делают
parent-walkup. **Workspace — единственный источник истины**; копии генерируются
скриптом `./sync-tooling.sh` (вшит в `./sync-all.sh`).

> [!warning] До 2026-08-02 эта модель не выполнялась ни разу, и это было ненаблюдаемо
> В `project/kacho` отслеживалось **ноль** файлов `.claude/` и не было корневого `CLAUDE.md`,
> при том что перечень целей раскатки нёс одиннадцать имён полирепо, не пересекавшихся ни с
> одним склонированным каталогом: скрипт печатал одиннадцать «skip» и **выходил успехом**.
> Раскатка в ноль целей была неотличима от «всё синхронно». Теперь перечень **выводится из
> дерева** (`repos.sh`), пустое множество — **отказ**, а `./sync-tooling.sh --check` — гейт
> (репо продукта без оснастки / ноль целей / копия разошлась с источником = красное).
> Разбор — `@.claude/rules/ai-tooling.md`.

- **Правишь generic-оснастку → только в `kacho-workspace/.claude/`**, затем
  `./sync-tooling.sh`. Копию в репо руками не редактируй — `--check` покраснеет.
- **Едет не всё**: ассет, у которого в целевом репозитории нет предмета, не едет (сегодня —
  `rules/vault.md` и два vault-хука: vault живёт только здесь). `settings.json` едет без
  блока `permissions` — посадка прав не навязывается публичному репозиторию.
- **Domain-агенты/скилы** (`vpc-*`, `compute-*`, `<svc>-load-testing`) — нативные в
  своём репо, sync их не трогает.
- `project/kacho/CLAUDE.md` сам `@import`-ит локальные `.claude/rules/*` (включая
  `00-kacho-core.md`) — поэтому standalone-клон самодостаточен; гейт сверяет соответствие
  импортов приехавшему набору в обе стороны.
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

- Стенд: `cd project/kacho/deploy && make dev-up` / `make dev-down`
  (здесь стоял `project/kacho-deploy` — каталог, которого нет; все пять целей проверены
  в `project/kacho/deploy/Makefile`)
- Перезапуск сервиса: `make reload-svc SVC=<vpc|compute|iam>` · логи: `make logs-svc SVC=…` · psql: `make psql SVC=…`
- Обновить рабочие копии (git pull): `./sync-all.sh` (вызывает `./sync-tooling.sh`)
- Раскатать оснастку вручную: `./sync-tooling.sh` · проверить без записи: `./sync-tooling.sh --check`
- Спека (5 docs): `docs/specs/0{0..4}-*.md`

## Permissions

`.claude/settings.json` — `bypassPermissions` (локальная dev-машина) + vault-discipline
hooks (`UserPromptSubmit` / `Stop`, портируемые через `$CLAUDE_PROJECT_DIR`).
Файл синхронизируется в каждый репо `./sync-tooling.sh`.
