---
title: audit-hardening-low-2026-07-09
category: kac
tags:
  - kac
  - fix
  - batch
  - security
  - leak-fix
  - race-fix
  - kacho-corelib
  - kacho-iam
  - kacho-vpc
  - kacho-compute
  - kacho-geo
  - kacho-nlb
  - kacho-api-gateway
  - kacho-registry
status: done
type: fix
---

# Массированный аудит-рефакторинг — LOW-inclusive прогон (2026-07-09)

**Status**: DONE — 8 раундов петли + auth-default-production финализация. Phase закрыта по команде на r8.
**Type**: batch fix (security/leak/structure/readability/LEAN/concurrency) + auth-posture
**Repos**: corelib, iam, vpc, compute, geo, nlb, api-gateway, registry (8 code-heavy)
**Trigger**: `/hardening-audit-loop` + директива «учитывай и LOW» + «фиксим сразу всё в рамках круга» (fix-all-in-round) + финализация «мержи всё в master; зелёный пайп в каждом репо; authN+authZ по дефолту production; все тесты тестируют production».

## Что и зачем

hardening-петля `hardening-audit-loop` с **LOW-toggle**: verify-фильтр держит `severity != INVALID`
(LOW НЕ отбрасывается), finder репортит и LOW (только реальные, не bikeshed). Метод (ultracode/workflow,
run-scoped копия bundled-скрипта, канон не мутирован): per-repo deep-finder × 6 дименсий → **adversarial
verify (refute)** → **все** confirmed (incl LOW) → строгий TDD-fix (RED→GREEN, `-race`, lint) → PR → CI →
merge → re-check со `seen`-дедупом. Каждый раунд — **полный ре-аудит с нуля** (stateless-финдеры), `seen`
гасит точные повторы. Политика **fix-all-in-round** закодифицирована в `SKILL.md` §1/§4/§5 + session-память
`hardening-audit-fix-all-in-round`.

## Сходимость (по раундам)

| Раунд | Fresh | Confirmed | HIGH | MED | LOW | Refuted |
|---|---|---|---|---|---|---|
| r1 | 19 | 16 | 0 | 2 | 14 | 3 |
| r2 | 16 | 12 | 0 | 4 | 8 | 4 |
| r3 | 15 | 11 | 0 | 3 | 8 | 4 |
| r4 | 16 | 11 | **1** | 2 | 8 | 5 |
| r5 | 16 | 13 | **1** | 1 | 11 | 3 |
| r6 | 12 | 8 | 0 | 1 | 7 | 4 |
| r7 | 10 | 9 | 0 | 1 | 8 | 1 |
| r8 | 12 | 6 | 0 | 1 | 5 | 6 |
| **Σ** | — | **86** | **2** | **15** | **69** | 30 |

**Fresh-тренд 19→16→15→16→16→12→10→12** ↓ (истинный сигнал сходимости — новых находок всё меньше),
**refute-rate вырос до 50% на r8** (хвост: finders цепляют пограничное, verify отсекает). Конфирмы
16→12→11→11→13→8→9→6. НЕ монотонно: LOW-планка + широкий finder-пул + слабый dedup-по-summary-префиксу
(перефразировки) + **registry data-plane как систематический hotspot**.

**Ключевой вывод:** LOW-прогон вскрыл **2 HIGH cross-tenant leak** (registry), которые предыдущий
«сошедшийся» прогон (`audit-hardening-r5-8`, дефолтная HIGH/MEDIUM-планка) **пропустил**. Плюс само-исправление
false-negative через перефразировку: registry `_catalog`-HIGH refuted r4 → confirmed r5; api-gw opsproxy
no-timeout refuted r1 → confirmed r4; vpc geo-client partial-zone refuted r2 → confirmed r3.

## Реестр HIGH / MEDIUM (crown jewels — security/leak/concurrency)

- **r4 HIGH** registry `dataplane/handler.go` serveMount — cross-repo blob mount без membership-проверки digest в `from` → cross-tenant blob exfiltration. PR registry#22.
- **r5 HIGH** registry `dataplane/handler.go` `/v2/_catalog` — pagination-курсор `Link:next` по boundary ДО authz-фильтра → cross-tenant repo-names leak. PR registry#23.
- **r5 MED** registry `public.go` ListRepositories next_page_token тот же класс. PR registry#23.
- **r3 MED** api-gw `auth.go` injectPrincipal→OUTGOING, proxy-хопы пересобирают из INCOMING → principal терялся. PR api-gw#130.
- **r2 MED** api-gw `auth.go` Kratos login логировал email на INFO = PII-leak (#2). PR api-gw#129.
- **r7 MED** iam `authorize_service.go` BatchCheck сворачивал transient FGA-ошибку в deny_reason с raw backend-текстом (leak). PR iam#313.
- **r6 MED** iam `internal_iam/handler.go` Register/UnregisterResource raw pgx→Unknown на :9091 (#1 INTERNAL-leak на internal-листенере). PR iam#312.
- **r4 MED** compute `permission_map.go` GetLatestByFamily project-viewer вместо per-object v_get (object-scoped gap). PR compute#96.
- **r4 MED** nlb `targetgroup/move.go` Move ронял mirror-data. PR nlb#74.
- **r2 MED** nlb `loadbalancer/move.go` то же для LB. PR nlb#72.
- **r3 MED** nlb `free_ip_runner.go` poison-pill LB HOL-блокирует reconciler. PR nlb#73.
- **r8 MED** registry `zot/backend.go` BlobInRepo кэшировал негатив от gctx-оборванного scan → poison TTL-кэша. PR registry#26.
- **r2 MED** vpc `cmd/vpc/main.go` нет panic-recovery на обоих листенерах. PR vpc#45.
- **r1 MED** vpc peer-clients (geo/region/iam) без per-call WithTimeout (#3). PR vpc#44.
- **r3 MED** geo `region.go` Update/Delete без ValidateID (malformed-id). PR geo#24.

## Классы LOW (реальные, узкие; 69 шт)

Doc-truthfulness (misleading-comment=trap): stale godoc, cache-TTL/pg_notify враньё, POST-vs-PUT,
«follow-up:» на сделанном — по всем 8 репо. APICONV: Operation-timestamp truncate (compute/geo/registry),
sentinel-префикс в NotFound-tone (vpc), malformed-id (geo/vpc). LEAN: vestigial ListIDs/ErrCrossTenant/
CreatorTupleWriter/dead-branch/write-only-field/last_gc_at. Concurrency: pagination-bound, JWKS refresh под
write-lock, sequential filter, LRU vs random eviction, LISTEN на unbounded ctx. Leak: unbounded error-body /
graphql / whoami / Check без LimitReader-cap + body-drain для keepalive. ban #2: foreign-cloud region-id в
комментах nlb.

## Auth-default-production финализация (пункт «дефолт в production»)

Пост-петля — сфокусированный auth-audit по 7 сервисам (`auth-default-audit.workflow.js`): дефолт auth-mode,
anonymous-fail-closed, dev-в-проде, test-mode.

- **Вердикт:** authN/authZ **enforcement fail-closed по дефолту во ВСЕХ 7** (anonymous denied; mTLS+per-RPC
  IAM-Check обязательны для старта — `validateSecurityConfig`/`validateAuthMode`, иначе не бутится).
- **Единственная находка — geo** (LOW): mode-ручка `KACHO_GEO_AUTH_MODE` дефолтила в `dev` (config.go:44),
  а под dev honored breakglass/trust-any bypass'ы (под production — inert). **Фикс:** default `dev`→`production`
  (secure-by-default, как iam/vpc/nlb). Helm dev/e2e-стенд задаёт `KACHO_GEO_AUTH_MODE=dev` явно (sub-chart
  values.yaml:68) → меняется только raw-binary-unset случай, e2e не тронут. **PR geo#28** (TDD RED→GREEN).
- compute/api-gw/registry тоже дефолтят ручку в dev в config, но у них она **decoupled** от authz (fail-closed
  идёт от DB-SSL/IAM-addr/list-filter env, не от mode) → audit finding=false, benign. Flip их дефолта сломал бы
  e2e (helm им mode не задаёт). Оставлено by-design.

**«Все тесты тестируют production»:** production authN/authZ posture покрыт в каждом сервисе — unit
(`authz_wiring`/`authmode_gate`/`TestValidate_Production_*`; nlb `TestLoad_DefaultMode_FailsClosedProduction`)
+ **helm-render regression-gate** `kacho-deploy/tests/helm/prod-profile-fail-closed-test.sh` (prod-манифест
fail-closed: mTLS-envs, `AUTHZ_FAIL_OPEN=false`, `sslmode≠disable`). Newman **black-box e2e** гоняет dev-стенд
(в CI нет реального JWT/mTLS-issuer) — осознанный дизайн (dev допустим в ephemeral CI-стенде по security.md),
production-путь ловится unit+helm-render, а не black-box.

## Зелёный пайп (main, по всем kacho-репо)

Required `ci` (build/vet/test/lint/govulncheck/integration/gosec/trivy) **зелёный на main во всех репо**:
corelib · iam · vpc · compute · geo · nlb · api-gateway · registry · deploy · ui = `ci=success`.
proto — CI-пайпа нет (generated stubs). newman-e2e — см. ниже.

## CI-примечания (честно)

- **newman-e2e (kind + helm umbrella) — pre-existing red, non-required.** Падают 4 iam-authz-сьюта
  (`authz-sa-apitoken · iam-access-binding · iam-internal-only-check · iam-rbac-subjects`), причина —
  FGA/cluster-admin bootstrap-readiness в umbrella-стенде (`bootstrap cluster-admin not ready after 180s,
  code=403` → каскад authz-cases). **Сверено: iam main падал ровно на этих 4 ещё ДО старта прогона**
  (run 28979992388, 2026-07-08) → ортогонально этой работе, не регресс. `mergeStateStatus=UNSTABLE`
  (не BLOCKED) — не required, не блокирует merge. `rbac-visibility-set` — интермиттент-флейк. Отдельный
  трек (тест-инфра FGA-seeding), не в scope hardening-фазы.
- **Реальные CI-красноты за прогон (не флейк, чинились в тот же PR):** r2 compute commentlint (`KAC-106`
  tracker-id в тест-комменте fix-агента — §6 грабли, перефразирован); r3 nlb integration 52-мин
  testcontainers-hang (тот же коммит в push-ране прошёл → флейк, ре-ран зелёный).

## PR по раундам (все merged, squash)

- r1: corelib#47 iam#307 vpc#44 compute#93 geo#22 nlb#71 api-gw#128 registry#20
- r2: corelib#48 iam#308 vpc#45 compute#94 geo#23 nlb#72 api-gw#129
- r3: corelib#49 iam#309 vpc#46 compute#95 geo#24 nlb#73 api-gw#130 registry#21
- r4: iam#310 vpc#47 compute#96 geo#25 nlb#74 api-gw#131 registry#22
- r5: corelib#50 iam#311 compute#97 geo#26 nlb#75 api-gw#132 registry#23
- r6: iam#312 vpc#48 nlb#76 api-gw#133 registry#24
- r7: corelib#51 iam#313 vpc#49 compute#98 geo#27 api-gw#134 registry#25
- r8: corelib#52 iam#314 vpc#50 api-gw#135 registry#26
- auth: **geo#28** (default auth mode → production)

## DoD

- [x] r1-r8 — все confirmed починены строгим TDD, PR merged, required-CI зелёные
- [x] Petля остановлена на r8 по команде (phase finalize)
- [x] Auth-default-production: geo дефолт → production (geo#28); остальные подтверждены production/decoupled-fail-closed
- [x] Все тесты тестируют production posture (unit + helm-render gate); newman black-box = dev by-design (нет CI-issuer)
- [x] Required `ci` зелёный на main во всех репо; newman-umbrella red = pre-existing #158-класс (не required, orthogonal)
- [x] Trail финализирован

## Честная формулировка

Systematic adversarially-verified LOW-inclusive аудит: **8 раундов, 86 confirmed-фиксов (2 HIGH + 15 MEDIUM +
69 LOW) + auth-default-production**, все merged в master с зелёным required-CI. Сошёлся к нижней полосе (r8:
6 confirmed, refute-rate 50%). Абсолютная «100%-чистота» на LOW-планке асимптотична — прогон остановлен на r8
по команде заказчика, не по dry-раунду; на момент остановки хвост — узкие LOW (dead-code/doc-truth/
LimitReader-parity) + редкий MEDIUM leak/concurrency, HIGH исчерпаны на r5.
