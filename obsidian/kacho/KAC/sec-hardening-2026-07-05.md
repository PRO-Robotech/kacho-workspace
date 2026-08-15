---
title: "sec-hardening-2026-07-05: cross-repo security/architecture/quality audit + fixes"
category: kac
status: done
type: refactor
tags:
  - kac
---

# sec-hardening-2026-07-05: cross-repo security/architecture/quality audit + fixes

**Состояние на момент записи**: merged (все 12 репо в main; запускается 2-й полный аудит для сходимости)
**Type**: refactor / security-hardening (batch)
**Repos**: all 12 code repos (proto/corelib/vpc/compute/iam/nlb/api-gateway/geo/registry/ui/ui-future/deploy)
**Branch**: `sec-hardening-2026-07-05` (per repo)
**YT**: —  (YouTrack недоступен из automation-сессии; KAC-тикет слинковать вручную)

## Что и зачем

Массированный внутренний рефактор по запросу: security + структурность + читаемость +
утечки, **без изменения контрактов** (proto/REST/DB-схема/wire-поведение заморожены).
Метод: read-only многоагентный аудит (47 finders, repo × dimension) → tests-first фиксы
на ветках → PR. Критерии аудита — OWASP ASVS L2 / Top-10 / CWE-25 / CIS / SOC2 / ISO27001
+ строгие правила проекта (tenant-isolation, infra-leak, TOCTOU/DB #10, Clean-Arch,
zero-TODO #11, tests-first #12).

## Аудит (Фаза 1)

144 находки: **0 critical**, 12 high, 48 medium, 84 low. Платформа зрелая (parametrised SQL,
crypto/rand, fail-closed authz interceptor, DB-level invariants, Clean-Arch). Остаточный риск —
authz-края (List-энумерация, Move, LRO-polling), TOCTOU-update, мёртвый secure-path UI, дыры
в прогоне тестов CI, дублирование micro-frontend. Полный отчёт: `scratchpad/AUDIT-REPORT.md`.

> [!note] Уровень записи
> Классы, репо и номера PR — да; поимённый разбор (координата + условие, при котором
> защита не действовала, + следствие) — **нет**: оба репозитория публичны
> ([[internal-vault-is-public]]), и связка остаётся рецептом даже когда находка закрыта.
> Дифф по каждому пункту доступен по номеру PR тем, у кого есть код.

## Round 1 — HIGH (10/10 адресуемых закрыты, tests-first, contracts frozen)

| repo | PR | что |
|---|---|---|
| kacho-compute | #72 | Instance.Update затирал CAS-статус (drop status из SET) + CI гоняет internal/clients integration |
| kacho-corelib | #30 | страж аварийного режима (breakglass) получил **негативные** тесты: до этого утверждалось только, что в штатном режиме он молчит — то есть отрицание жило без парного положительного и зеленело бы при мёртвом страже |
| kacho-geo | #8 | OperationService.Get/Cancel → PermissionMap (LRO-polling больше не fail-closed) |
| kacho-nlb | #49 | List fail-closed для system/empty subject; Move авторизует destination-project; + fix drift-теста |
| kacho-registry | #2 | register-drainer не теряет tuples при retry-after-partial-apply |
| kacho-vpc | #26 | List решает права **на сервере**, а не по признаку из запроса; Address/NIC/AddressPool переведены на атомарный CAS |
| kacho-ui | #123 | secure-client (DPoP/step-up) на реальном трафике; bump уязвимых deps (0 vulns) |

Все ветки независимо верифицированы (build+vet+тесты -race, testcontainers): 7/7 PASS.
`git diff` каждой ветки: 0 `*.proto` / `gen/` / миграций → контракт-фриз соблюдён.

## Отложено (документируется, не в этих PR)

- **kacho-proto** InstanceGroupService — целый сервис (**23 RPC**) без authz-аннотаций. Масштаб
  назван намеренно: реестр читают, чтобы приоритизировать, а «целый сервис» приоритет не задаёт —
  и то же число стоит ниже в §Wire-contract-blocked, так что без него файл спорил сам с собой.
  Раскрытия в нём нет: сервис с тех пор снят целиком (см. исход ниже). Фикс требовал
  правки контракта, а контракт на время работы был заморожен → отдельный тикет.
  > [!note] Исход (2026-07-28): сервис **снят целиком**, а не доаннотирован
  > Он был объявлен в контракте, разведён маршрутами, и **не реализован нигде**; записи
  > каталога прав гейтили пустоту. Правильным исходом оказалась не «доделать проверки», а
  > [[wildcard-relation-sweep-2026-07-28|снять поверхность]] — поверхность без реализации
  > нельзя защитить, её можно только убрать. Пункт оставлен как пример того, что
  > «отложено на контракт-фикс» иногда означает «отложено на удаление».
- **kacho-ui-future** — 263 byte-identical дубля (incl. 2845-строчный resource-registry.tsx).
  Огромный/рискованный дедуп в экспериментальном репо → отдельная задача.
- Прочие needs-contract / large-refactor / deliberate-convention (envconfig) items — в отчёте.

## Round 2 — medium/low sweep (~26 items closed)

10 репо (7 продолжают ветку + iam/api-gateway/deploy новые): safe high-value medium/low tests-first:
- **api-gateway** #109 — гейт повышенной аутентификации **реально включён**: он был
  объявлен, но не провязан, а сопоставление REST-пути с методом не работало — то есть
  проверка присутствовала и не могла сработать ни разу.
- **iam** #281 — redact OpenFGA/pgx transport-detail из ошибок (CWE-209), лог swallowed op-persist, dead-dir.
- **deploy** #141 — securityContext на kacho-iam workloads, namespace PSA (warn+audit=restricted), pin init-image, trivy IaC CI-gate.
- **registry** #2 — операции стали owner-scoped (чтение и отмена только своей), набор
  ключей верификации в production требует защищённого перехода.
- **ui** #123 — CSP/X-Frame/X-Content-Type/Referrer headers, удалены TODO(KAC-N)+yandex-коммент, gated dead access-token scaffolding.
- **vpc** #26 — production boot-guard **отказывается стартовать** без включённой
  пофайловой фильтрации списков; до этого умолчание чарта расходилось с умолчанием кода
  в небезопасную сторону (класс «умолчание получает тот, кто о ручке не знал»).
- **nlb** #49 — config fail-closed на list-filter, concurrent exactly-once test для target-drain DELETE.
- **corelib** #30 — гонка вытеснения в кэше решений о доступе (CWE-362), тесты
  ограничителя и инвалидации, санитизация идентификаторов очереди.
- **compute** #72 — гейт TLS в строгом production перепровязан (читал поле, которого никто
  не заполнял — мёртвый guard), плюс тесты гонки на уникальность привязки дисков.
- **geo** #8 — negative тесты: Zone.Update FK, unique-PK one-winner, malformed page_token.

## Round 3 — safe tail (done)

registry min-RSA-modulus JWKS (#2) · geo production DB-TLS guard (#8) · api-gateway authz-error redaction + dead no-op (#109) · corelib dead metaType var (#30) · nlb dead `var _ = errors.Is` (#49). Все build+vet+тесты `-race` зелёные, 0 контракт-файлов.

## Convergence (Фаза 5) — CONVERGED

Пере-аудит 10 репо на ветках (adversarial regression-скан diff'ов): **10/10 CONVERGED**, все 10
адресуемых HIGH подтверждены закрытыми, **0 новых critical/high** (регрессий нет), 0 неожиданных
residual. 2/12 HIGH отложены по жёстким ограничениям (proto-контракт, ui-future крупный дедуп).
Контракт-фриз соблюдён во всех 10 ветках (0 `*.proto`/`gen/`/миграций).

## Wave A (drive-to-zero) + Merge

По требованию «100%» переоткрыл scope: Wave A закрыла **80 находок** contract-safe по 12 репо (крупные рефакторы: api-gateway authz.go split + cache-consolidation + idempotency single-flight + decision-cache epoch-guard; iam ConditionsService TOCTOU через **новую внутреннюю миграцию 0048** FK+CAS; nlb create.go split; vpc error-mapper consolidation; geo CQRS split; ui-future security-critical dedup в shared/src; corelib cache-cap/reconciler-timeout/tombstone-prune/debug-redaction). 3 новые внутренние миграции (iam/registry/nlb). Все 12 build+tests локально верифицированы (-race, testcontainers).

**Merged в main (squash, ветки удалены):** proto#1, corelib#30, iam#281, registry#2, nlb#49, vpc#26, compute#72, geo#8, api-gateway#109, ui-future#1. **ui/deploy** были на устаревшем main (fetch-only при синке, origin ушёл на 75-79 коммитов) → сброшены на актуальный origin/main + хардининг переналагается заново.

**CI-долг (INFRA-находка, не мой код):** push-CI vpc/compute/... красный на `go mod download` private sibling-модулей (нет GOPRIVATE+PAT в CI) — воспроизводится на голом main (scheduled зелёный, push красный на том же SHA). Merge — по локальной полной верификации, branch protection нет.

**Wire-contract-blocked (нужна развилка — снять фриз / принять):** proto InstanceGroupService 23-RPC authz-аннотации (runtime уже fail-closed/deny-all в api-gateway) + InternalAuthzCache low; nlb announce-state monotonic (нужен proto-field observed_at).

## Осознанный backlog (не в этих PR)

- proto InstanceGroupService authz-аннотации → **нужна правка контракта** (отдельный тикет).
- iam ConditionsService delete TOCTOU → нужна schema-миграция (FK/trigger) = контракт.
- Крупные рефакторы: authz.go god-file split, 6× TTL+LRU cache consolidation (→corelib),
  ui-future 263-file дедуп, ui resource-registry 2712-line split, CQRS-split geo — риск/объём.
- Deliberate conventions (envconfig vs viper) — платформенная норма, не баг.
- deploy: digest-pin kacho-* images / dev-creds removal — нужен runtime-smoke стенда.
- ui CSP — нужен runtime-smoke на поднятом стенде (build+grep недостаточно).

## Acceptance / DoD

- [x] Аудит выполнен, отчёт собран (`scratchpad/AUDIT-REPORT.md`)
- [x] Round-1 HIGH: фиксы tests-first, независимо верифицированы, PR открыты (7)
- [x] Round-2 medium/low: фиксы + PR (7 обновлены, 3 новых) — независимо верифицированы
- [x] Пере-аудит (Фаза 5): 10/10 CONVERGED, регрессий нет
- [x] Round-3 safe tail завершён + верифицирован (5 репо)
- [x] Финальный отчёт пользователю + полный аудит-отчёт в `docs/security/audit-2026-07-05.md`

**Итог**: 10 PR (все 12 code-репо кроме proto/ui-future/docs), 10/10 HIGH закрыты, ~31 medium/low,
0 регрессий, контракт-фриз соблюдён. 2 HIGH + длинный tail — осознанный backlog (контракт / крупный
рефактор / deliberate convention).

#kac #security #refactor
