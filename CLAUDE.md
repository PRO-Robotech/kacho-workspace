# Kachō — Workspace CLAUDE.md

Загружается из `kacho-workspace/` и из любой подпапки `project/<repo>/`
(parent-walkup). Тонкий индекс: identity + naming + non-negotiables + `@import`
модульных правил. Подробности — в `.claude/rules/*.md` (импортируются ниже).

## Что это за продукт

**Kachō — самостоятельная облачная control-plane платформа** (только control plane,
без data plane). Домены: **IAM** (Account / Project / User / ServiceAccount / Group /
Role / AccessBinding), **VPC** (Network / Subnet / SecurityGroup / RouteTable / Address /
Gateway / NetworkInterface), **Compute** (Instance / Disk / Image / Snapshot + Geography
Region/Zone). Это собственный продукт со своими требованиями — описывай и проектируй
API в терминах **конвенций Kachō** (см. `@.claude/rules/api-conventions.md`), без
сравнений с чужими облаками.

## Naming convention (обязательно)

| Контекст | Значение |
|---|---|
| Бренд / README / UI | **Kachō** |
| Технические идентификаторы (ASCII) | `kacho` |
| Proto package | `kacho.cloud.<domain>.v1` |
| Имена репо | `kacho-<part>` (дефис) |
| Postgres database / schema | `kacho_<domain>` (подчёркивание) |
| Env-переменные | `KACHO_<DOMAIN>_<NAME>` |
| JSON-поля (REST) | camelCase: `<resource>Id`, `projectId`, `labels`, `createdAt` |

## Non-negotiables (детали — в соответствующих rule-модулях ниже)

1. **Не кодить без APPROVED acceptance-дока** Given-When-Then (gate: `acceptance-reviewer`).
2. **Никаких упоминаний чужих облаков** в коде/доках/комментариях/env/именах (`yandex`, `aws`, …).
3. **Без ORM** — только sqlc + handwritten pgx.
4. **Без каскадного удаления через границу сервиса** (только same-DB FK cascade).
5. **Не редактировать применённую миграцию** — только новая.
6. **`Internal.*` методы не публиковать на external endpoint** (только cluster-internal :9091).
7. **Без брокера** (Kafka/NATS), пока справляется in-process.
8. **Без общих БД** — database-per-service.
9. **Мутации возвращают `Operation`** (async), не ресурс синхронно.
10. **Within-service инварианты — на DB-уровне** (FK/UNIQUE/EXCLUDE/CHECK/CAS), не software check-then-act.
11. **Никакого тех-долга / TODO «на потом»** — закрываем в том же PR.
12. **Строгий TDD** — падающий тест ДО кода; новый RPC/поле/ресурс/багфикс не мёржится без тестов в том же PR.
13. **Test-only PR не трогает прод-код** и не содержит TODO/SKIP/FIXME.

## Модульные правила (@import)

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
- Обновить все репо: `./sync-all.sh`
- Спека (5 docs): `docs/specs/0{0..4}-*.md`

## Permissions

`.claude/settings.json` — `bypassPermissions` (локальная dev-машина) + vault-discipline
hooks (`UserPromptSubmit` / `Stop`, портируемые через `$CLAUDE_PROJECT_DIR`).
