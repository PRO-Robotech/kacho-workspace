# sec-hardening-2026-07-05: cross-repo security/architecture/quality audit + fixes

**Status**: test (все PR открыты, convergence подтверждён, ждут ревью)
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

## Round 1 — HIGH (10/10 адресуемых закрыты, tests-first, contracts frozen)

| repo | PR | что |
|---|---|---|
| kacho-compute | #72 | Instance.Update затирал CAS-статус (drop status из SET) + CI гоняет internal/clients integration |
| kacho-corelib | #30 | negative-тесты breakglass anonymous-bypass guard (isAnonymousSubject) |
| kacho-geo | #8 | OperationService.Get/Cancel → PermissionMap (LRO-polling больше не fail-closed) |
| kacho-nlb | #49 | List fail-closed для system/empty subject; Move авторизует destination-project; + fix drift-теста |
| kacho-registry | #2 | register-drainer не теряет tuples при retry-after-partial-apply |
| kacho-vpc | #26 | NetworkService/List server-side FGA Check (не доверяет x-kacho-admin); Address/NIC/AddressPool CAS |
| kacho-ui | #123 | secure-client (DPoP/step-up) на реальном трафике; bump уязвимых deps (0 vulns) |

Все ветки независимо верифицированы (build+vet+тесты -race, testcontainers): 7/7 PASS.
`git diff` каждой ветки: 0 `*.proto` / `gen/` / миграций → контракт-фриз соблюдён.

## Отложено (документируется, не в этих PR)

- **kacho-proto** InstanceGroupService — 23 RPC без authz-аннотаций. Фикс = правка proto →
  контракт заморожен. Runtime вероятно fail-closed (interceptor денит unmapped RPC). Отдельный
  contract-change тикет. См. [[../rpc/README]].
- **kacho-ui-future** — 263 byte-identical дубля (incl. 2845-строчный resource-registry.tsx).
  Огромный/рискованный дедуп в экспериментальном репо → отдельная задача.
- Прочие needs-contract / large-refactor / deliberate-convention (envconfig) items — в отчёте.

## Round 2 — medium/low sweep (~26 items closed)

10 репо (7 продолжают ветку + iam/api-gateway/deploy новые): safe high-value medium/low tests-first:
- **api-gateway** #109 — step-up (ACR/MFA) gate реально включён (был мёртвый: PermissionLookup unwired + broken REST→FQN mapper).
- **iam** #281 — redact OpenFGA/pgx transport-detail из ошибок (CWE-209), лог swallowed op-persist, dead-dir.
- **deploy** #141 — securityContext на kacho-iam workloads, namespace PSA (warn+audit=restricted), pin init-image, trivy IaC CI-gate.
- **registry** #2 — OperationService owner-scoped GetOwned/CancelOwned (BOLA), JWKS require https в production.
- **ui** #123 — CSP/X-Frame/X-Content-Type/Referrer headers, удалены TODO(KAC-N)+yandex-коммент, gated dead access-token scaffolding.
- **vpc** #26 — production boot-guard require list-filter.enabled (закрывает helm-default fail-open).
- **nlb** #49 — config fail-closed на list-filter, concurrent exactly-once test для target-drain DELETE.
- **corelib** #30 — authz cache lazy-eviction clobber fix (CWE-362), rate-limiter/ListenInvalidator тесты, outbox identifier sanitization.
- **compute** #72 — production-strict TLS gate rewire (был dead cfg.IAMTLS), attached_disks uniqueness race/negative тесты.
- **geo** #8 — negative тесты: Zone.Update FK, unique-PK one-winner, malformed page_token.

## Round 3 — safe tail (done)

registry min-RSA-modulus JWKS (#2) · geo production DB-TLS guard (#8) · api-gateway authz-error redaction + dead no-op (#109) · corelib dead metaType var (#30) · nlb dead `var _ = errors.Is` (#49). Все build+vet+тесты `-race` зелёные, 0 контракт-файлов.

## Convergence (Фаза 5) — CONVERGED

Пере-аудит 10 репо на ветках (adversarial regression-скан diff'ов): **10/10 CONVERGED**, все 10
адресуемых HIGH подтверждены закрытыми, **0 новых critical/high** (регрессий нет), 0 неожиданных
residual. 2/12 HIGH отложены по жёстким ограничениям (proto-контракт, ui-future крупный дедуп).
Контракт-фриз соблюдён во всех 10 ветках (0 `*.proto`/`gen/`/миграций).

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
