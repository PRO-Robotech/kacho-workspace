# Kachō — ядро: продукт, naming, non-negotiables

Базовый, всегда-загруженный модуль. Импортируется как корневым workspace
`CLAUDE.md`, так и `CLAUDE.md` каждого сервисного репо (self-sufficient: репо
работает и при standalone-клоне, без workspace-родителя). Источник истины —
workspace; копии во всех репо синхронизируются `./sync-tooling.sh` — **не
редактировать копию в репо**, правка только в `kacho-workspace/.claude/rules/`.

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

## Non-negotiables (детали — в соответствующих rule-модулях)

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
14. **Всегда production-grade, НИКОГДА MVP.** Не строим «минимальную рабочую версию, потом допилим». Каждый ресурс/RPC/фича — сразу в полной production-форме: полный error-handling + фикс. тон ошибок, authz/security на каждом RPC, DB-инварианты, two-projection, observability, тесты, конвенции. Запрещены stub/skeleton, «happy-path пока», «hardening/authz/тесты позже», «временное упрощение». Урезание объёма допустимо ТОЛЬКО как осознанная декомпозиция на под-фазы, где **каждая под-фаза сама production-complete** (полностью реализована+протестирована+безопасна в своих границах, отложенное явно вынесено в `Out-of-scope` следующей под-фазы) — это НЕ понижение качества, а сужение scope. «MVP/прототип/потом доделаем» как обоснование неполноты — нарушение (тесно с ban #11 тех-долг).
15. **Внешняя/URL-адресация — ТОЛЬКО по immutable `id`, НИКОГДА по `name`.** Любая внешне-адресуемая идентичность ресурса — сегмент публичного URL / pull-пути (эталон: **`$domain/$registryId/$repository:$tag`**, как DockerHub/Quay), cross-service ссылка (`projectId`/`zoneId`/`registryId`/…), grant-scope / authz-target, любая durable-координата — привязывается к **неизменяемому `id`** ресурса, не к мутабельному `name`/label. `id` присваивается на Create и **неизменяем на всю жизнь ресурса**: операции смены id НЕ существует (никакого «rename id», никакого `:rename`, меняющего адресуемую идентичность), `id` **глобально-уникален by construction** (crockford-base32) — коллизий между тенантами нет. Человекочитаемое `name` — косметический project-scoped label (`UNIQUE(project,name)`, может меняться свободно), который **НИКОГДА не попадает в URL/pull-путь/ссылку** и не несёт адресацию. Причина: имена меняются и глобально коллизят → URL/гранты/ссылки ломались бы; id-адресация стабильна навсегда и бесконфликтна. Эталоны: GEO (Region/Zone immutable id), registry (`$domain/$registryId/$repo:$tag`, `id` prefix `reg`). Rename `name` (где ресурс его допускает) — чисто косметическая мутация, не затрагивающая ни одной внешней привязки. Деривация «глобального человекочитаемого слага» в URL (вместо id) — **запрещена** (вводит name-в-URL через заднюю дверь и rename-ломкость).
16. **Production-mode ВЕЗДЕ (включая dev/локальный стенд) + iam-единый-фасад-к-Hydra.** Любой РАЗВЁРНУТЫЙ стенд (kind/CI/local/prod) работает в **production-security-posture** (`authMode=production` + mTLS ВЕЗДЕ + `sslmode=require` + Hydra-RS256); dev-insecure posture (anonymous→full, HS256-stand-in, plaintext) — security-долг, ЗАПРЕЩЁн на поднятом кластере (допустим ТОЛЬКО в in-process unit/integration-фикстурах). «Зелёный dev» НЕ доказывает production-готовность (dev маскирует authz-bypass/неверифицированный-mTLS/обойдённые-boot-guards). **Каждый сервис ОБЯЗАН нести production boot-guard** (`Config.Validate()` fail-closed → refuse-to-start при insecure config; `AuthMode` declared-never-read = запрещённый мёртвый guard). **`values.prod` ОБЯЗАН реально boots** (helm-install+rollout-ready в production-mode, не только `helm template`). **iam — единственный фасад к Hydra**: клиенты/сервисы/e2e идут в iam (JWKS-proxy `:9097`, token via `UserToken/SAKey.Issue`, docker-token `/iam/token`), прямой Hydra-dial в обход iam (JWKS `:4444`, admin `/admin/clients`) — нарушение унификации (iam→Hydra ВНУТРИ фасада — легитимно; допустимо-прямое — только OAuth2 `client_assertion→JWT` exchange). Детали и регрессии — `@.claude/rules/security.md` §«Production-mode обязателен ВЕЗДЕ». Выведено из production-mode валидации 2026-07 (storage без boot-guard, gateway internal-listener не-boots, gateway JWKS Hydra-direct).
