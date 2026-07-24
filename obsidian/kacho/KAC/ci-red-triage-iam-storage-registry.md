---
title: CI e2e-newman red-triage — iam/storage/registry (post geo-seed)
category: kac
tags: [kacho-iam, kacho-storage, kacho-registry, kacho-deploy, kac, fix, testing]
ticket_id: TBD
status: in-progress
type: fix
repos: [kacho (monorepo)]
opened: 2026-07-24
---

# CI red-triage iam/storage/registry — 6 root-cause категорий (после geo-seed win)

> [!success] Контекст: geo-seed разблокировал 4 домена
> CI run 30063062957 (redesign/integration): geo-seed фикс → **vpc/compute/nlb/geo GREEN**.
> Остались red iam(~50)/storage(74)/registry(4) — хвост редизайна, НЕ geo-related. 7-агентный
> `ci-red-triage` workflow категоризировал → 6 non-masking фиксов (commit `05dc544`).

## 6 root-cause категорий + фиксы

1. **storage VOL-OBJSELF (74 assert, все 401 "token validation failed")** — `fixture`. Storage
   newman-env нёс **stale committed RS256 `jwtProjectEditorA`** (alg RS256, kid 3be4ab72, iss Hydra);
   dev-mode HS256-gateway его отвергает. `storage-fixtures.json` (в отличие от registry/nlb) НЕ
   переминчивал jwtProjectEditorA. Fix: засеять fresh HS256 storage project-editor субъект
   (`USER_STO_EA`) + editor-binding на изолированный `STORAGE_HOME` + emit в storage-fixtures.json
   (setup.sh). Без v_create (objself лишь Get/Update/Delete existing volume). Green зависит от
   #71 storage_volume FGA-wiring (в ветке: migration 0060 + feed_registry.go).
2. **registry REPO-CR-OK (repo-create→404)** — `test-ec-retry`. Первый CreateRepository под
   свежесозданным parent-registry 404-ит (handler `registryGate(v_create)` existence-hiding), пока
   owner-tuple parent'а не материализуется; последующие → 200. Fix: обернуть repo-create POST в
   `retry_until_authorized` (gate ДО use-case → denied attempt ничего не создаёт → re-POST безопасен).
3. **iam-rbac-scope-grant (7, "Unexpected token p" / plain "404 page not found")** — `test-infra`.
   FGA-Check-проба била **PUBLIC cmux (:18080)**, где `/iam/v1/internal/iam:check` 404-ит by design
   (ban #6). Fix: `_internal_url_override` → роут на internal REST listener (:18081), зеркало
   label-revoke-iam.py. **НЕ «tolerate plain-404»** (было бы false-green — проба вообще не выполнялась).
4. **rbac-subject-channel-equivalence (nonmember/user deny→200 leak)** — `fixture`. `jwtNoBindings`
   **doubly-used**: параллельные ACB-суиты реально грантят `userNOB` view на account-A → 200
   **корректен** (не product-leak). Fix: 2 steady-state deny-пробы → dedicated never-granted
   `jwtPureNoBindings`. Дискриминатор prod-leak vs fixture строг (тело = именно тот account, что
   параллельно грантится userNOB).
5. **iam-authz-grant-check-propagation (delete-check)** — `mixed` (masksBug guard). Readiness-проба
   поллила `editor`, а DELETE-gate энфорсит **`v_delete`** (tier-decoupled: editor НЕ предиктит
   v_delete) → проба никогда не сходится. DELETE несёт `required_acr_min=2` → нужен
   `jwtAccountAdminAStepUp` (был acr<2 → step-up-deny скрыт FGA no-path). Fix: probe→v_delete +
   auth→StepUp. **Корректировки, не маскировка**: если v_delete owner-mat реально не материализуется —
   кейс это ВСКРОЕТ (prod-bug follow-up), а не спрячет.
6. **iam materialization-throughput** (iam-access-binding-redesign 11 / account 3 / rbac-subjects 17,
   create→Get 404) — `mixed`. **НЕ read-lag** (retry уже есть: rya budget + FGA_POLL_CAP=180 красный) —
   **недосходимость** под фоновым backlog. iam-native объекты (project/accessBinding/group-member)
   материализуются FULL EXCLUSIVE `ReconcileObject`/drainer (не additive SHARE-forward как leaf через
   RegisterResource). `newman-parallel.sh` изолирует iam в wave2, но **БЕЗ drain-gate между волнами** →
   wave2 стартует пока wave1 (leaf-регистрации) fga_outbox-backlog ещё голодит iam-материализацию.
   Fix: **inter-wave drain-gate** (drain healthy fga_outbox→0 bounded перед iam-волной). НЕ поднимать
   FGA_POLL_CAP (=180 уже красный — анти-фикс).

## Run #2 (30083782782) + DISCRIMINATOR ВЕРДИКТ (2026-07-24)

CI #2: **storage 74→0** ✅ (token-фикс сработал), geo/compute/nlb green, rbac-subjects 17→8,
channel 4→1, registry-repository 4→0. Осталось red: vpc list-filter-d 3 (регресс), iam
access-binding 14 / grant-check 6 / label-revoke-vpc 10 / rbac-subjects 8, registry-authz/redesign 9.

> [!important] Discriminator: остаток = EC materialization THROUGHPUT, НЕ correctness-bug
> Integration-тест (`TestOwnerIamContent_AccessBindingForward`, синхронный `ReconcileObject`,
> нет EC-окна) **GREEN на v_get/v_update/v_delete** для owner → **эмиссия owner-tuple КОРРЕКТНА**
> (v_delete эмитится DIRECT: feed_registry `iam.accessBinding` verb-bearing → `ResolveVerbsAndTier(["*"])`
> → `[get,list,create,update,delete]` → `ruleObjectTuples` add `v_delete`). e2e-403 = read-your-writes
> materialization lag, НЕ дефект feed/reconcile. **openfga replicaCount=1 + iam replicas=1 УЖЕ**
> (values.dev:1061/1097) → НЕ replica-read-lag → чистый **drainer throughput** (ledger→OpenFGA Write)
> под wave1-конкуренцией (registry 404-after-48s = backlog >48s под --jobs>1).

## Fix (commit `d4970c1`) — test-infra parallel-safety, НЕ prod-change

EC-throughput чинится снижением materialization-contention (legitimate per testing.md — CI валидирует
**correctness** при этой concurrency; prod-scale throughput = отдельный tracked epic):
- **newman-parallel.sh: iam + registry `--jobs 1`** (сериализовать materialization-heavy суиты, как nlb) →
  drainer поспевает → bounded client-retry покрывает read-your-writes окно.
- **setup.sh: grant-materialization drain-gate ПЕРЕД Phase B resource-seeds (block 11-14)** → JWT_AAA
  grants материализованы до subnet/network create (иначе ensure_subnet пусто → `{{subnetVisibleId}}`
  unsubstituted → vpc list-filter red). Fixes vpc seed-flake.

## Follow-up (throughput scalability EPIC — НЕ correctness, НЕ блокер CI-green)

- **iam `forward.go` iam-direct additive forward** (create.go:189/409): brand-new iam-direct объект
  (project/accessBinding) → additive SHARE-lock forward вместо FULL EXCLUSIVE (forward.go:235 делегирует
  iam-direct в full). **Оптимизация throughput** (родствен [[iam-accessbinding-forward-materialization]]),
  НЕ correctness (эмиссия уже верна). Prod-scale concern для high-density; НЕ нужен для CI-green если
  contention-reduction работает. Landing с design+TDD+dual-review — НЕ marathon-end push в критичный
  materialization-путь. Трейл throughput: [[fga-register-throughput-inversion]].

## Skip (не gate-failing)
- **iam-internal-only-check (8 ENOTFOUND api.kacho.local)**: `assert-suites-green.sh` уже вычитает
  ENOTFOUND/EAI_AGAIN (KAC-188) → канонический гейт GREEN на этой суите. Raw .run.failures[] ≠ gate-verdict.

## Затронутые сущности vault
- [[geo-baseline-greenfield-seed-gap]] (geo-seed win, предшествующий) · [[iam-accessbinding-forward-materialization]]
  (родственный forward-паттерн) · [[grant-materialization-omirror-root]] · [[fga-register-throughput-inversion]]
- setup.sh (storage editor seed) · newman-parallel.sh (drain-gate) · iam/registry newman cases

## Status
- [x] geo-seed → vpc/compute/nlb/geo green (run 30063062957)
- [x] 7-агентный триаж → 6 non-masking фиксов (commit `05dc544`)
- [x] CI #2 (30083782782): storage 74→0 ✅; остаток = EC materialization throughput
- [x] **discriminator: v_delete эмиссия КОРРЕКТНА (EC-lag, НЕ correctness-bug)** — integration GREEN
- [x] contention-reduction fix (`d4970c1`): iam+registry --jobs 1 + setup drain-gate
- [ ] CI #3 (30088223667) — подтвердить iam/registry/vpc green при --jobs 1
- [ ] если всё ещё red при serial → throughput floor выше retry → forward.go epic (design+review)

#kacho-iam #kacho-storage #kacho-registry #kacho-deploy #kac #fix #testing
