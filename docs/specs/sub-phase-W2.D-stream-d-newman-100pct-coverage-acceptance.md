# Sub-phase W2.D — Stream D: Newman 49→100% coverage (13 new case-files) — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: [KAC-170](https://prorobotech.youtrack.cloud/issue/KAC-170) (parent bundle); subtask of master epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134).
> **Author agent**: inline (`claude` — main session, after Tracks A/B parallel dispatch)
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` —
>     - `tests/newman/cases/iam-access-review.py` (NEW, AccessReviewService — 7 RPC)
>     - `tests/newman/cases/iam-authorize.py` (NEW, AuthorizeService — 5 RPC)
>     - `tests/newman/cases/iam-conditions.py` (NEW, ConditionsService — 6 RPC)
>     - `tests/newman/cases/iam-federation-exchange.py` (NEW, FederationExchangeService — 1 RPC)
>     - `tests/newman/cases/iam-gdpr-erasure.py` (NEW, GdprErasureService — 4 RPC)
>     - `tests/newman/cases/iam-internal-authorize.py` (NEW, InternalAuthorizeService — 5 RPC)
>     - `tests/newman/cases/iam-internal-break-glass.py` (NEW, InternalBreakGlassService — 6 RPC)
>     - `tests/newman/cases/iam-internal-user.py` (NEW, InternalUserService — 3 RPC)
>     - `tests/newman/cases/iam-jit-eligibility.py` (NEW, JITEligibilityService — 5 RPC)
>     - `tests/newman/cases/iam-opa-bundle.py` (NEW, OpaBundleService — 3 RPC)
>     - `tests/newman/cases/iam-sa-key.py` (NEW, SAKeyService — 3 RPC)
>     - `tests/newman/cases/iam-trust-policy.py` (NEW, TrustPolicyService — 5 RPC)
>     - `tests/newman/cases/iam-internal-iam-rest.py` (NEW, InternalIAMService — 6 RPC помимо `Check` уже покрытого)
>     - `tests/newman/scripts/run.sh` (расширение — register 13 new suites)
>     - `tests/newman/scripts/gen.py` (no code change — потребляет существующий DSL)
>     - `tests/newman/scripts/coverage.py` (update if needed — verify `--min 100` gate)
>   - **NOT touched (verified)**: `kacho-proto` (no new RPC); `kacho-corelib` (no new helper); `kacho-api-gateway` (catalog assumed in-sync with proto via W2.A); product code (test-only PR per workspace `CLAUDE.md` §Запреты #13).
> **Branch (kacho-iam)**: `KAC-XXX-newman-w2d` (placeholder — agent assigns on impl).
> **Parent plan**: `docs/superpowers/plans/2026-05-23-iam-newman-100-coverage-plan.md` (test-coverage diagnostic) + `docs/superpowers/plans/2026-05-21-iam-newman-test-coverage-list.md` (full 495-case list — source of truth for case IDs).
> **Master plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 2 Stream D.
> **Predecessors** (must be `main`-merged before impl):
> - W2.A — Stream A: gateway permission-catalog unified (else half of new AUTHZ cases would fail on stale catalog entries). Newman expects fail-closed PermissionDenied for unauthorized; stale catalog ⇒ false positives.
> - W2.C — Stream C: API tokens (B.7 catalog includes ApiTokenService; new SA-key cases reference SAKey path which is adjacent — but TokenService cases are separate, see §0.1).
> - W2.B (partial — for cases that exercise enterprise features end-to-end):
>   - B.5 AccessReview workflow → iam-access-review cases (campaign create/list/decide flow)
>   - B.7 GDPR erasure pipeline → iam-gdpr-erasure cases (request/approve/cancel/audit-emit)
>   - B.4 break-glass full → iam-internal-break-glass cases (request/approve A+B/activate/auto-revoke)
>   - B.1 SAML / B.2 SCIM — separate from this scope (B.1/B.2 are wire-protocol features; their **REST** layer testing is mentioned but the bulk of OAuth/SAML/SCIM e2e is out of newman scope; minimal smoke сюда не входит)
>
> **Why W2.D closes coverage gap**: current baseline (2026-05-23 post-KAC-133) = **49%** RPC coverage (10/22 gRPC сервисов имеют case-file; +InternalIAM один из 7 методов). W2.D добавляет **13** новых case-файлов → **22+22=22 уникальных сервисов** в covered set. Per master plan «D: newman 100% (13 новых сюит)». В дополнение к 13 new — refresh existing 12 (если catalog/spec drift сломал какой-то после W2.A merge — отдельные fix-cases, не считаются в 13).

---

## 0. Преамбула — что эта sub-итерация (précis)

W2.D — **test-only** sub-итерация (workspace `CLAUDE.md` §Запреты #13): расширяет newman regression suite kacho-iam до 100% покрытия RPC-surface. **НЕ трогает приклад**: ни product code, ни proto, ни миграции, ни handler-логику. Если в процессе написания RED-case'а обнаруживается баг продукта (TDD-red against existing prod) — заводится отдельный GitHub Issue в `PRO-Robotech/kacho-iam` с меткой `bug` + `verified-by:test`, case остаётся RED со ссылкой `# verifies <issue-url>` (без `pm.test.skip`, без TODO/FIXME). Case переходит в GREEN только когда отдельный PR закрывает finding (см. §«Запреты» #13 root rule).

W2.D — 13 новых case-файлов (declarative `cases/*.py`), каждый генерит соответствующий `collections/*.postman_collection.json` через `gen.py`. Каждый файл декларирует **минимум 1 happy + 1 negative** на каждый RPC сервиса. Authz-gated RPC дополнительно — **anon-deny** + **foreign-deny** кейсы (parity с baseline W1.* anti-anon enforcement). Полный list of case-IDs — в `docs/superpowers/plans/2026-05-21-iam-newman-test-coverage-list.md` (495 cases total для всего IAM; W2.D — ~190 из них на 13 new services).

### 0.1 W2.D НЕ включает

- **Product code changes** — ни одной строки в `internal/`, `cmd/`, `migrations/`, `*.go`. Bugs found while writing RED → finding-issue в kacho-iam, не fix.
- **ApiTokenService cases** — это часть W2.C (Block F); там case-file `iam-api-token.py` создаётся вместе с feature. W2.D — только existing-RPC cases.
- **SAML/SCIM full e2e** — wire-protocol (SAML AuthnResponse XML, SCIM RFC 7644 conformance) — лучше через специализированный тест-tooling, не newman. Newman cases для них в scope только в smoke level (B.1/B.2 acceptance декларирует). W2.D добавляет smoke: `iam-federation-exchange.py` (1 RPC = exchange token) — proxy для SSO smoke.
- **Refresh baseline 12 suites** — если W2.A merge ломает любой existing case (например, изменён error-text формат) — это **fix** в том же W2.A PR, не W2.D. W2.D добавляет ТОЛЬКО new suites.
- **Load testing** — newman ≠ k6/ghz; нагрузочные сценарии — отдельный track (master plan Future-track / KAC-future).
- **Chaos testing** — out of scope.
- **Performance assertions** (response-time bounds) — out of scope newman; covered by k6 load.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** | gate данного doc; impl стартует только после APPROVED. |
| **Запрет #2** | в test-files не упоминается «yandex». Проверка `grep -ri yandex tests/newman/cases/iam-*.py` зелёная. |
| **Запрет #6** | Internal* сервисы тестируются **через cluster-internal listener (9091)**, НЕ через public TLS (`api.kacho.local:443`); newman scripts настраивают base URL отдельно для каждой группы (см. §4.2). Tенант-видимые cases не должны мочь хитнуть Internal*-RPC: для них кейс `*-AUTHZ-EXTERNAL-DENY` (если RPC ошибочно exposed → 404 NotFound). |
| **Запрет #9** | мутации идут через Operation; cases для async RPC polls operation до done=true с timeout (60s default) — pattern из baseline suites. |
| **Запрет #11** (no TODO / no tech debt — root rule, 2026-05-24) | в diff W2.D PR НЕ ДОЛЖНО быть НИ ОДНОГО `TODO`, `FIXME`, `pm.test.skip`, закомментированного assertion, `// will fix later`. TDD-red против бага продукта → GitHub Issue + `# verifies <url>` (см. §0). |
| **Запрет #12** (test-first STRICT) | каждый новый case (без exception) пишется RED-first → прогон через `./run.sh <suite>` показывает FAIL → затем (если RED по causes-of-test-completeness, не от prod-бага) уточняется/упрощается case до first-greens → commit. Pair RED→GREEN в PR-описании. |
| **Запрет #13** (test-only PR — NO product fix + NO TODO) | **корень scope** этой sub-фазы: PR содержит ТОЛЬКО `tests/newman/cases/iam-*.py`, `tests/newman/scripts/run.sh`, `coverage.py` (если правка нужна), и опционально `docs/specs/sub-phase-W2.D-…-acceptance.md` self-update. **НИ ОДНОГО** изменения в `internal/`, `cmd/`, `migrations/`, `proto`. Reviewer rejects PR с product-changes. |
| **CLAUDE.md §«Принцип переиспользования через kacho-corelib»** | newman scripts (`run.sh`, `gen.py`, `coverage.py`) — generic, существуют. W2.D **не вводит** новых scripts; только новые declarative cases. |
| **CLAUDE.md §«Vault discipline»** | обновляются: `obsidian/kacho/packages/iam-tests-newman.md` (NEW — если ещё не существует), `obsidian/kacho/KAC/KAC-XXX.md` (trail). Не дублируем case-IDs из 2026-05-21 plan — только short summary + ссылка. |

---

## 2. Глоссарий

- **`tests/newman/cases/iam-<svc>.py`** — declarative Python module: список `Case(method, path, body, expects)` структур; запускается `gen.py` → выдаёт postman_collection.json.
- **`gen.py`** — generator: читает cases/*.py → ёлкает `.postman_collection.json` с `pm.test()` assertions per case.
- **`run.sh <suite>`** — wrapper newman CLI: setup fixtures (account/project/users/SA), запускает collection, парсит результат в `summary.txt`.
- **`coverage.py --min 100`** — gate: для каждого RPC в `kacho-proto/proto/kacho/cloud/iam/v1/*.proto` (через protoc reflection) — есть ≥1 case в `cases/`. Иначе `exit 1` (fails CI).
- **Case-ID format** — `IAM-<SVC>-<RPC>-<CLASS>[-detail]` (см. `2026-05-21-iam-newman-test-coverage-list.md` §0).
- **Class**: `CRUD` (happy) · `NEG` (negative — NotFound/InvalidArgument/FailedPrecondition) · `AUTHZ` (grant/deny/anon/foreign) · `BVA` (boundary value) · `IDEM` (idempotency) · `SEC` (injection) · `FLOW` (stateful multi-step).
- **TDD-red against prod bug** — case корректен по контракту, но product implementation несоответствует → case краснит, заводится finding-issue, case остаётся RED + `# verifies <url>`. После fix product — case зеленеет automatically.

---

## 3. Decisions (приняты)

| ID | Решение |
|---|---|
| W2.D-D1 | Coverage gate `coverage.py --min 100` — required для CI; никакой service не пропускается. ApiToken (W2.C feature) — отдельный case-file, считается отдельно. |
| W2.D-D2 | Internal* сервисы тестируются через `BASE_URL_INTERNAL=http://kacho-iam.kacho.svc:9091` (cluster-internal). Если этот URL недоступен (running outside cluster) — suite skips с warning, **не FAIL** (отдельный flag `--include-internal`). На CI (kind/umbrella) — always available. |
| W2.D-D3 | Authz-gated cases используют 4 fixture users: `bootstrap` (cluster-admin), `alice` (account-admin), `bob` (project-member), `carol` (stranger — no access). Setup в `scripts/setup.sh`. Pre-existed; reuse. |
| W2.D-D4 | TDD-red против prod-бага: case остаётся в diff (не commented out), `# verifies KAC-N / kacho-iam#NN` tag в case-описании, `RESULTS.md` §«Known failing tests — product bugs» обновляется со ссылкой. После prod fix — case → GREEN автоматом, RESULTS обновляется. |
| W2.D-D5 | Performance-assertions (response-time) — OUT of scope newman cases; k6 load script — отдельно. Newman cases assertЯт только корректность (status code, body shape, side-effect verified by subsequent GET). |

---

## 4. Open questions

| ID | Вопрос | Рекомендация |
|---|---|---|
| OQ-W2.D-1 | InternalIAM-rest 6 methods кроме Check — какие именно? (Initialize, SyncFGA, ListPermissions, …) — verify proto | Извлечь из `kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto` на момент impl. Default — все non-Check public methods. |
| OQ-W2.D-2 | FederationExchangeService — 1 RPC (`Exchange external token → kacho`) — fixture для external token? | Использовать stub IdP (Kratos) если deployed; иначе hardcoded test JWT signed by test key. |
| OQ-W2.D-3 | OpaBundleService — 3 RPC (List/Get/Reload?) — bundle storage в test setup? | Bundle fixtures в `tests/newman/fixtures/opa-bundles/`. |
| OQ-W2.D-4 | GdprErasure — `RequestErasure` returns Operation; `Cancel*Request` requires anti-anon allowlist updated (W1.6 #43). Verify W1.6 merged before impl start? | Yes — pre-condition. Acceptance-reviewer проверяет timeline. |
| OQ-W2.D-5 | InternalBreakGlassService — нужна ли проверка cluster_admin_grants table side-effect через psql? Иначе case "pass'нул, а grant не записан" возможен. | Yes — post-step через `psql` (через `kubectl exec`) проверка `SELECT * FROM cluster_admin_grants WHERE ...`. Existing newman suite уже использует этот pattern для drainer-tests. |

---

## 5. Implementation steps

### 5.1 Bootstrap (one-time per case file)

Для каждого нового `cases/iam-<svc>.py`:

1. Скопировать skeleton из `cases/iam-account.py` (существующий, smallest example).
2. Заменить `RESOURCE = "account"` → `RESOURCE = "<svc>"`.
3. Удалить existing cases.
4. Для каждого RPC сервиса — добавить блок cases (см. §5.2).
5. Запустить `gen.py` → проверить generated json.
6. Run `./run.sh iam-<svc>` → ожидать FAIL (cases пока пустые) → ожидать PASS после заполнения.
7. `coverage.py` показывает service теперь covered.

### 5.2 Case-template per RPC

```python
# Минимум на RPC:
Case(
    id="IAM-<SVC>-<RPC>-CRUD-OK",
    method="POST",
    path="/iam/v1/<svc>:<verb>" if verb else "/iam/v1/<svc>",
    body={...},  # valid
    expects=Expects(status=200, has_operation=True),  # async
),
Case(
    id="IAM-<SVC>-<RPC>-NEG-NOTFOUND",
    method="GET",
    path="/iam/v1/<svc>/non-existent-id",
    expects=Expects(status=404, body_contains="not found"),
),
# Authz-gated — добавить (per W1.3 fail-closed + W1.6 anti-anon allowlist):
Case(
    id="IAM-<SVC>-<RPC>-AUTHZ-ANON-DENY",
    auth=None,  # no token
    expects=Expects(status=401, body_contains="authentication required"),
),
# Если RPC scoped per-resource:
Case(
    id="IAM-<SVC>-<RPC>-AUTHZ-FOREIGN-DENY",
    auth="carol",  # stranger
    expects=Expects(status=404, body_contains="not found"),  # anti-info-leak per KAC-122 §5
),
```

### 5.3 Полный per-service case-set (extract из 2026-05-21 plan)

> Source-of-truth = `docs/superpowers/plans/2026-05-21-iam-newman-test-coverage-list.md` §3.1 (AuthorizeService), §3.2 (Conditions), §4 (Federation/Tokens), §5 (Phase 7/7b), §6 (Internal). Ниже — резюме per file для каждого из 13:

#### 5.3.1 `iam-access-review.py` (AccessReviewService — 7 RPC) — ~30 cases
- CreateCampaign, ListCampaigns, GetCampaign, DecideReviewItem, ApproveReviewItem (W1.6 #35 reviewer-from-principal), RevokeReviewItem, AddReviewer

#### 5.3.2 `iam-authorize.py` (AuthorizeService — 5 RPC) — ~25 cases
- Check, BatchCheck, Expand, ListObjects, ListSubjects

#### 5.3.3 `iam-conditions.py` (ConditionsService — 6 RPC) — ~25 cases
- Create, Get, List, Update, Delete, Evaluate

#### 5.3.4 `iam-federation-exchange.py` (FederationExchangeService — 1 RPC) — ~6 cases
- Exchange (smoke: stub IdP → kacho-token; negative: invalid JWT signature, expired, wrong audience)

#### 5.3.5 `iam-gdpr-erasure.py` (GdprErasureService — 4 RPC) — ~18 cases
- RequestErasure, ListErasureRequests, GetErasureRequest, CancelErasureRequest (W1.6 #43 anti-anon allowlist)

#### 5.3.6 `iam-internal-authorize.py` (InternalAuthorizeService — 5 RPC) — ~25 cases
- WriteTuple, DeleteTuple, ListTuples, ListRelationships, Resolve

#### 5.3.7 `iam-internal-break-glass.py` (InternalBreakGlassService — 6 RPC) — ~25 cases
- RequestBreakGlass, ApproveBreakGlassA, ApproveBreakGlassB, DenyBreakGlass, ListPending, GetGrant

#### 5.3.8 `iam-internal-user.py` (InternalUserService — 3 RPC) — ~12 cases
- UpsertFromIdentity (KAC-107 path), GetByExternalSubject, ListByEmail

#### 5.3.9 `iam-jit-eligibility.py` (JITEligibilityService — 5 RPC) — ~22 cases
- CreateEligibility (W1.6 #39 created_by-from-principal), GetEligibility, ListEligibilities, UpdateEligibility, DeleteEligibility

#### 5.3.10 `iam-opa-bundle.py` (OpaBundleService — 3 RPC) — ~12 cases
- ListBundles, GetBundle, RebuildBundle (W3.1 #25 ReloadModel related; this is bundles, distinct)

#### 5.3.11 `iam-sa-key.py` (SAKeyService — 3 RPC) — ~15 cases
- IssueKey (W1.6 #53 created_by-from-principal + #11 secret-redaction-after-Get), RevokeKey, ListKeys
- **Critical regression test for #11**: Issue → Get operation → assert `response.client_secret` exists; second Get → assert `response.client_secret == "<redacted>"`.

#### 5.3.12 `iam-trust-policy.py` (TrustPolicyService — 5 RPC) — ~22 cases
- CreateTrustPolicy, GetTrustPolicy, ListTrustPolicies, UpdateTrustPolicy, DeleteTrustPolicy

#### 5.3.13 `iam-internal-iam-rest.py` (InternalIAMService — 6 RPC помимо Check) — ~25 cases
- Initialize (bootstrap), SyncFGA, ListPermissions (#49 — verify implemented in some prior chunk), GetSubjectChange (W1.2), AcknowledgeSubjectChange, DrainSubjectChanges

### 5.4 Update `run.sh`

```bash
# Register 13 new suites in run-all:
SUITES_NEW="iam-access-review iam-authorize iam-conditions iam-federation-exchange \
            iam-gdpr-erasure iam-internal-authorize iam-internal-break-glass \
            iam-internal-user iam-jit-eligibility iam-opa-bundle iam-sa-key \
            iam-trust-policy iam-internal-iam-rest"

SUITES="$SUITES_EXISTING $SUITES_NEW"
```

### 5.5 Update `coverage.py`

Verify `--min 100` gate fails if any of 13 new services lack case-file. If existing gate already proto-reflective, no code change needed — only confirm config.

---

## 6. Given-When-Then scenarios (acceptance-level, not per-case)

### 6.1 Positive — coverage gate passes

**Given** все 13 case-файлов созданы; `gen.py` сгенерил 13 новых collections; existing 12 suites не сломаны.
**When** запускается `./scripts/coverage.py --min 100`.
**Then** exit code 0; stdout: `coverage: 113/113 RPC covered (100%)`; нет warnings про uncovered.

### 6.2 Positive — happy-path cases все зелёные

**Given** kind cluster + helm umbrella развёрнут; kacho-iam pod ready; fixtures setup (`./scripts/setup.sh`) выполнен.
**When** запускается `./scripts/run.sh <each-of-13-new-suites>`.
**Then** `summary.txt` показывает `0 FAILED` для всех 13 suites; total assertions ≥ 200 PASSED.

### 6.3 Negative — anti-anon enforcement validated

**Given** kacho-iam W1.6 deployed (allowlist read-only RPCs; default-deny anonymous для mutations).
**When** anonymous newman case вызывает любую из mutations: `RequestBreakGlass`, `IssueKey`, `Approve*`, `Decide*`, `Cancel*Request`, `RequestErasure`, `Rebuild*`, `WriteTuple`, `DeleteTuple`.
**Then** response = 401 Unauthenticated с `WWW-Authenticate: Bearer` header; body matches `authentication required`. **НЕ** 403 (это другой класс — authenticated-but-not-authorized).

### 6.4 Negative — foreign-subject denied

**Given** alice owns Account A; carol is stranger (no AB on Account A).
**When** carol authenticated calls `GetAccessReviewCampaign(id-in-A)`, `GetEligibility(id-in-A)`, `GetTrustPolicy(id-in-A)`, etc.
**Then** response = 404 NotFound (anti-info-leak per KAC-122 §5). НЕ 403 (info-leak preventing — 404 indistinguishable from «doesn't exist»).

### 6.5 Edge — TDD-red против бага продукта

**Given** case `IAM-SAKEY-IS-FLOW-REDACT-AFTER-FIRST-GET` (W1.6 #11 regression) написан и прогоняется до W1.6 merge.
**When** kacho-iam build НЕ имеет #11 fix.
**Then** case краснит — `client_secret` не редактится. Action: открыть `kacho-iam#NN` finding-issue с label `bug verified-by:test`; в case добавить `# verifies https://github.com/PRO-Robotech/kacho-iam/issues/NN`; в `RESULTS.md` записать в «Known failing — product bugs»; case **остаётся** в diff. **НЕТ** `pm.test.skip()`, **НЕТ** TODO. После merge W1.6 → case → GREEN автоматически; RESULTS обновляется.

### 6.6 Edge — Internal-listener-only RPC из внешней зоны → 404

**Given** Internal*-сервисы доступны ТОЛЬКО на 9091; client пытается их хитнуть через TLS-внешний api.kacho.local:443.
**When** anonymous (или authenticated) запрос на `/internal/iam/v1/users:upsertFromIdentity` через external URL.
**Then** 404 NotFound (gateway public mux не регистрирует Internal*-paths per §запрет 6). НЕ 401, НЕ 403 — это публично «нет такого endpoint».

### 6.7 Edge — concurrent case run (suite isolation)

**Given** 13 suites runs могут пересекаться (CI parallelism).
**When** 2+ suites параллельно создают фикстурный Account / Project.
**Then** suite-level setup гарантирует unique-suffix имён (e.g. `acc-${SUITE}-${RANDOM}`); cases НЕ предполагают global state; cleanup в `teardown.sh` per-suite.

---

## 7. Test plan

### 7.1 Distribution: case-files → covered findings

| case-file | RPC | cases | covers W1.* findings |
|---|---|---|---|
| iam-access-review.py | 7 | ~30 | W1.6 #35 (reviewer from principal) — regression test |
| iam-authorize.py | 5 | ~25 | W1.3 fail-closed surface — Check returns 401 anonymous (post-fail-closed) |
| iam-conditions.py | 6 | ~25 | — (no prior fix; baseline coverage) |
| iam-federation-exchange.py | 1 | ~6 | W2.B.1 SAML smoke (1 case for happy-path token exchange) |
| iam-gdpr-erasure.py | 4 | ~18 | W1.6 #43 anti-anon (Cancel*Request in allowlist) |
| iam-internal-authorize.py | 5 | ~25 | W1.5 fga grant-write atomic (WriteTuple/DeleteTuple — post-conditions) |
| iam-internal-break-glass.py | 6 | ~25 | W1.6 #43 (Approve*BreakGlass in allowlist) |
| iam-internal-user.py | 3 | ~12 | W1.4 principal propagation (UpsertFromIdentity propagates caller from gateway) |
| iam-jit-eligibility.py | 5 | ~22 | W1.6 #39 (created_by from principal — regression) |
| iam-opa-bundle.py | 3 | ~12 | — (W3.1 #25/#26 ReloadModel/RunRegoTest — adjacent; bundle CRUD distinct) |
| iam-sa-key.py | 3 | ~15 | **W1.6 #53 + #11 regression** — see 6.5 |
| iam-trust-policy.py | 5 | ~22 | — (baseline) |
| iam-internal-iam-rest.py | 6 | ~25 | W1.2 subject_change_outbox (GetSubjectChange/Acknowledge) — verify drain works |

**Total**: ~262 new cases (≥1 happy + 1 negative + authz-pair per RPC, плюс flow/idem где нужно).

### 7.2 RED→GREEN evidence per case-file

PR description обязан содержать для каждого нового case-file:

```
### iam-access-review.py
- 30 new cases
- Pre-W2.D run: ./run.sh iam-access-review → "suite not found" (file doesn't exist)
- After cases written, pre-impl: ./run.sh iam-access-review → 30 FAIL (collection runs, all expected-status mismatches because dependencies)
- After fixture+dependencies wired: 30 PASS
- ./scripts/coverage.py → AccessReviewService now covered
```

Без подобного блока — reviewer rejects.

### 7.3 Negative-class case verification

Reviewer проверяет (random sample 3 case-files):
- В каждом case-file ≥ 30% cases класса NEG/AUTHZ (не только happy-path)
- AUTHZ-cases используют 4 fixture users (bootstrap/alice/bob/carol)
- IDEM/FLOW cases присутствуют где имеет смысл (Invite, AddMember, multi-step Approve)

### 7.4 «Known failing — product bugs» section в RESULTS.md

После merge W2.D — если cases остались RED по причине prod-багов (не infrastructure / not test-mistake), `tests/newman/RESULTS.md` обновляется section'ом:

```markdown
## Known failing tests — product bugs (W2.D baseline)

| case-id | finding-issue | status |
|---|---|---|
| IAM-XXX-YYY-CLASS | kacho-iam#NN | RED — blocked by KAC-MM |
```

Acceptable count: ≤ 5% от total cases (i.e. ≤ 13 from ~262). Больше — defer-этап-W3 для product fix sprint.

---

## 8. Definition of Done

- [ ] 13 case-файлов созданы в `tests/newman/cases/`
- [ ] `gen.py` запущен; 13 новых `tests/newman/collections/iam-*.postman_collection.json` сгенерированы и committed
- [ ] `./scripts/run.sh <suite>` для каждого из 13 — exit 0 (либо RED с явной `# verifies <finding-url>` ссылкой)
- [ ] `./scripts/coverage.py --min 100` exit 0; report 100% coverage
- [ ] `./scripts/run.sh --all` summary: ≤ 5% known-failing-product-bugs (документировано в RESULTS.md)
- [ ] **НИ ОДНОГО** `TODO`, `FIXME`, `pm.test.skip`, commented-out assertion в diff
- [ ] **НИ ОДНОГО** изменения в `internal/`, `cmd/`, `migrations/`, `proto/` (verified `git diff --stat`)
- [ ] PR description содержит RED→GREEN evidence per case-file (см. §7.2)
- [ ] CI зелёный: build (no product changes — passes), newman-e2e (включая 13 новых suites)
- [ ] `RESULTS.md` обновлён до новой версии
- [ ] `CASES-INDEX.md` / `TEST-PLAN.md` / `TAXONOMY.md` / `PRODUCT-REQUIREMENTS.md` синхронизированы (если applicable для kacho-iam — verify их существование)
- [ ] Vault: `obsidian/kacho/packages/iam-tests-newman.md` обновлён (раздел «13 new W2.D suites»)
- [ ] Vault: `obsidian/kacho/KAC/KAC-XXX.md` (trail) — DoD checklist отмечен; PR-URL добавлен
- [ ] PR merged → main

---

## 9. Vault discipline

| Что | Узкий файл (1-3KB) |
|---|---|
| **NEW (if not exists)** `obsidian/kacho/packages/iam-tests-newman.md` | Описание structure tests/newman, 13 new case-files, ссылка на 2026-05-21 plan как source of truth case-IDs |
| **UPDATE** `obsidian/kacho/rpc/iam-*.md` (где RPC получил новые newman cases) | поле `newman_cases: covered (W2.D)` в frontmatter |
| **NEW** `obsidian/kacho/KAC/KAC-XXX.md` (на новом impl-ticket) | trail per workspace `CLAUDE.md` §«Vault discipline» |
| **НЕТ изменений** | `resources/`, `edges/` — test-only PR не меняет ресурсную модель / runtime-graph |

---

## 10. Sign-off

- **acceptance-reviewer**: ⏳ pending — оценивает scope coverage (13 files, ≥1 happy + 1 neg per RPC), test-only discipline (`grep -E '(TODO|FIXME|skip|XXX|FIXIT)' tests/newman/cases/iam-*.py` empty), realism (fixture availability), traceability (cases mapping to RPCs in proto)
- **qa-test-engineer** (review supporting): ⏳ pending — оценивает test-design quality (BVA boundaries chosen; equivalence partitioning; error-guessing for AuthZ matrix)
- **rpc-implementer** (impl): после APPROVED; assigns KAC-XXX, branch, writes 13 files

Status flow: DRAFT → REVIEW → APPROVED → IMPL ASSIGNED → IN PROGRESS → TEST → DONE.
