# kacho-iam → production-ready (Full-scope, kind-deploy) — Master Plan

> **For agentic workers:** REQUIRED SUB-SKILL — superpowers:subagent-driven-development или
> superpowers:executing-plans для исполнения per-Wave детальных под-планов. Этот файл — master
> tracker; bite-sized шаги — в `2026-05-23-iam-prod-ready-wave<N>.md` (W0 готов; W1-W3 — заготовки
> acceptance-doc-stubs, детальные планы пишутся в начале исполнения каждого Wave).

**Goal:** Довести kacho-iam до DoD «все функциональности реализованы, newman 100% root-cause-fix,
deploy на kind работает» — full-scope (Блок A authz-remediation + Блок B Enterprise + Блок F
API-tokens + Блок D AuthZ-инфра + Блок E удаление заглушек), per `2026-05-21-product-completion-freeze-plan.md`.

**Architecture:** Hybrid critical-path + parallel waves (Approach C из брейнсторма). W0 prep
(newman gate + OpenFGA HA-mini) → W1 critical-path (fga_outbox-drainer + cache invalidation +
Remediation Chunks 1+2) → W2 параллельно 4 потока (gateway/spec-drift + Enterprise + API tokens +
newman добор) → W3 финал (federation/SSO + observability + freeze).

**Tech Stack:** Go (Clean Architecture), kacho-corelib (outbox/operations/observability),
OpenFGA (ReBAC), ORY Hydra/Kratos, Postgres + goose + sqlc, gRPC + grpc-gateway, buf,
Newman (Postman) E2E, testcontainers-go, kind + helm umbrella, VictoriaMetrics+Logs+Traces,
SPIRE+Cilium ServiceMesh, vector.dev.

---

## Baseline (2026-05-23 после KAC-133)

| Метрика | Значение |
|---|---|
| Newman GREEN | 1144/1148 (99.7%); **4 intentional RED #37** — починить |
| Сервисы с newman-сюитой | 12/26 IAM (включая внутренний `iam-internal-only-check`) |
| Authz findings closed | 2/44 (#8/#13 в KAC-128/131); 42 не сделаны |
| `fga_outbox` drainer | **не существует** — bootstrap-grant не применяется |
| `subject_change_outbox` (cache invalidation на revoke) | не реализован |
| Gateway authz-middleware fail-closed | выключен на dev; нужно prod-настроить |
| OpenFGA на kind | chart есть (`openfga-0.2.62.tgz`); не bootstrap'ится store/model |
| SPIRE+Cilium+observability на kind | charts есть, разворачиваются; не wired к kacho-iam |
| Enterprise (SAML/SCIM/JIT-activate/CAEP/SPIRE-mTLS) | заглушки / недостижимы |
| API-tokens | симулируются в `authz-sa-apitoken.py`, реальной фичи нет |

## Источники

- `2026-05-21-iam-authz-review-remediation-plan.md` — 44 findings в 5 чанков
- `2026-05-21-iam-newman-test-coverage-list.md` — ~495 newman-кейсов на ~131 RPC
- `2026-05-21-product-completion-freeze-plan.md` — full-scope DoD (Часть 4)
- `2026-05-21-production-launch-plan.md` — деплой/observability/security (WS-2..7)
- `2026-05-23-iam-newman-100-coverage-plan.md` — coverage.py gate + 13 новых сюит

## 25 (+1) gRPC-сервисов IAM scope

Из `kacho-proto/proto/kacho/cloud/iam/v1/*.proto` + Блок F ApiToken:

**Core (7)**: AccountService, ProjectService, UserService, ServiceAccountService, GroupService, RoleService, AccessBindingService.
**Phase 7/7b (6)**: JITEligibilityService, JitPendingService, AccessReviewService, ComplianceReportService, GdprErasureService, BreakGlassService.
**AuthZ (4)**: AuthorizeService, ConditionsService, InternalAuthorizeService, OpaBundleService.
**Federation/Token (3 + 1 new)**: FederationExchangeService, TrustPolicyService, SAKeyService, **ApiTokenService (новый — Блок F)**.
**SSO/Hooks (4)**: BackChannelLogoutService, InternalIamHooksService, SessionRevocationsService, (SCIM/SAML — REST).
**Internal (3)**: InternalIAMService, InternalUserService, **(новый InternalApiTokenService.Resolve)**.

Полное покрытие = ≥1 happy + ≥1 negative + (для authz-gated) +1 authz-кейс per RPC.

---

## Waves overview

| Wave | Срок | Содержание | Detail plan |
|---|---|---|---|
| **W0** prep | ~3 дня | coverage.py gate (RPC→case), wire newman-e2e CI matrix на все 22+ сюит, OpenFGA bootstrap-job (store+model), fail-closed-cтенда baseline | `2026-05-23-iam-prod-ready-wave0.md` |
| **W1** critical-path | ~2 нед | corelib outbox-drainer (LISTEN/NOTIFY + idempotent OpenFGA Write/Delete) + subject_change_outbox + gateway fail-closed enable + Chunk 1 (#8/#16/#47/#48/#50/#51/#52) + Chunk 2 (#9/#11/#12/#13/#35/#36/#37/#39/#43/#53) | `2026-05-23-iam-prod-ready-wave1.md` (TBD — пишется при старте W1) |
| **W2** parallel | ~4-6 нед | Поток A: Chunk 3 (gateway wiring + permission-catalog unification) + Chunk 4 (spec-drift KAC-119/121). Поток B: Enterprise Block B (B.1-B.10). Поток C: Блок F — API tokens. Поток D: newman 100% (13 новых сюит). | `2026-05-23-iam-prod-ready-wave2-stream{A,B,C,D}.md` (TBD) |
| **W3** finalize | ~1-2 нед | Chunk 5 (federation/SSO internals: #21/#23/#25/#26/#40/#42) + observability customisation (dashboards/alerts) + SPIRE+Cilium wiring kacho-iam за SVID + freeze checklist | `2026-05-23-iam-prod-ready-wave3.md` (TBD) |

**Зависимость:** W1 заблокирован W0; W2 заблокирован W1; W3 заблокирован W2. Внутри W2 — 4 потока параллельны.

---

## Decisions (приняты 2026-05-23)

| ID | Решение |
|---|---|
| SCOPE | Full-scope IAM (Блок A+B+D+E+F); VPC/Compute — не в scope этого эпика |
| DEPLOY | kind через kacho-deploy umbrella; OpenFGA HA-mini (2 реплики); БЕЗ внешнего домена/cert-manager/pentest |
| ROOT-CAUSE | Все newman failures — root-cause-fix через backend/proto/fixture; НЕ test-skip / relaxed-assertion; 4 intentional RED #37 — починить |
| APPROACH | Hybrid (W0 prep → W1 critical-path → W2 4 parallel streams → W3 finalize) |
| AUDIT | VictoriaLogs + vector.dev (decision KAC-127 prod-launch §6); НЕ Kafka/ClickHouse/HSM/Merkle |
| SPIRE | В scope (charts есть, wiring остаётся) |
| LOADBALANCER | Вне scope продукта (decision KAC-127 prod-launch §6) |

## Open decisions (нужны до старта релевантного Wave)

| ID | Вопрос | Wave | Рекомендация |
|---|---|---|---|
| OQ-1 | #7: `/iam/v1/roles` anonymous-read — изменить gateway или acceptance? | W2 Поток A (Chunk 4) | Обновить acceptance: catalog-read требует auth (минимальная гигиена) |
| OQ-2 | DECISION-APITOKEN (F.5): token inherits subject rights vs own scope ⊆ subject | W2 Поток C | (b) least-privilege — токен ⊆ subject |
| OQ-3 | #40 SAML: verify-assertion в W2/W3 vs guard ACS (501) | W2 Поток B / W3 | По умолчанию guard в W2, verify в W3 |
| OQ-4 | KAC-эпик в YouTrack — заводить под этот объём? | W0 (теперь) | Завести `KAC-iam-prod-ready` эпик + subtask per Wave |

---

## Definition of Done (final freeze)

- [ ] 0 stub / `Unimplemented` / disabled-by-config на surface (grep подтверждает)
- [ ] Все 44 findings → closed (включая #37) либо `wontfix` с обоснованием в `docs/architecture/`
- [ ] Все Enterprise-фичи (Блок B): подключены к gateway, работают, имеют newman
- [ ] Блок F (API-tokens): proto + migration + usecase + gateway authn + newman
- [ ] `fga_outbox` drainer работает; revoke инвалидирует cache; gateway fail-closed
- [ ] OpenFGA HA-mini + SPIRE+Cilium mesh + observability (VM/VL/VT+alerts) на kind
- [ ] Newman: 22+ сюит в `run.sh`, `coverage.py --min 100` зелёный, root-cause-fix (не test-hacks)
- [ ] Integration ≥80% на новом коде; CI зелёный (build/lint/gosec/trivy/govulncheck/integration/newman-e2e)
- [ ] vault обновлён (resources/rpc/packages/edges + KAC-trail для каждого чанка)
- [ ] kacho-deploy umbrella chart разворачивает всё на kind за `make dev-up`

---

## Execution handoff

После W0 detail-плана — два варианта дальше:

1. **Subagent-driven** (рекомендуется для huge multi-month эпика): per-чанк acceptance-doc → fresh
   subagent (rpc-implementer / migration-writer / integration-tester / qa-test-engineer) с
   two-stage review (specialist + code-review). Соответствует memory
   `feedback-acceptance-tests-only-not-code` (НЕ генерировать prod-код массово).
2. **Inline executing-plans** — для одного Wave в одной сессии; для всего эпика не подходит
   (контекст не помещается).

Старт W0 — после фиксации в YT эпика `KAC-iam-prod-ready` и subtasks W0..W3.
