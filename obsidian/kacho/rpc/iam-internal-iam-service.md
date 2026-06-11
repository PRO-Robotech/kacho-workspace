---
title: InternalIAMService
aliases:
  - InternalIAMService (iam)
proto_file: kacho/cloud/iam/v1/internal_iam_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-access-binding]]"
methods_count: 9
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[SEC-A-proto-fga-proxy]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
---

# InternalIAMService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto`
**Backend**: `kacho-iam:9091` (**internal-only**; запрет #6 — НЕ публиковать на external TLS `api.kacho.local:443`)
**Visibility**: internal — REST зарегистрирован в `api-gateway/internal mux` под `/iam/v1/internal/...`.
**Status**: backend в [[KAC-112]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| LookupSubject | LookupSubjectRequest | LookupSubjectResponse | sync | oneof key: external_id / id / email (case-insensitive); используется E2 auth-interceptor |
| ListPermissions | ListPermissionsRequest | ListPermissionsResponse | sync | aggregate permissions (subject + groups) на конкретный resource; E0 — простая DB-aggregate, E3 → OpenFGA Check |
| PollSubjectChanges | PollSubjectChangesRequest | PollSubjectChangesResponse | sync | **WS-2.3 ([[KAC-WS23]])** — курсорный (`id > since_id`, ascending, limit-clamped) дренаж `subject_change_outbox`; возвращает `head_id`. api-gateway poll-loop зовёт это для инвалидации authz decision-cache. gRPC-only (НЕ в restmux). |
| Check | CheckRequest | CheckResponse | sync | per-RPC authz-gate (vpc/compute зовут перед мутацией). REST: `POST /iam/v1/internal/check`. |
| WriteCreatorTuple | WriteCreatorTupleRequest | WriteCreatorTupleResponse | sync | запись creator-owner-tuple; пустой response; gRPC-only (нет `google.api.http`). |
| GetJWKSStatus | (Empty) | JWKSStatusResponse | sync | per-alg статус активных signing-ключей (`oidc_jwks_keys`, KAC-127 Phase 2). |
| ForceLogout | ForceLogoutRequest | ForceLogoutResponse | sync | принудительный logout субъекта. |
| RegisterResource | RegisterResourceRequest | RegisterResourceResponse | sync | **FGA-proxy ([[SEC-A-proto-fga-proxy]])** — записать owner-hierarchy-tuple (`subject_id`/`relation`/`object` + опц. `trace_id`) в FGA от имени модуля. **Internal-only :9091, нет `google.api.http`** (ban #6). authz `<exempt>` в каталоге; least-priv энфорсится в handler (SEC-C) через ReBAC `fga_writer` @ `iam_fgaproxy:system`. **Идемпотентно** (повтор → OK, не AlreadyExists) — at-least-once outbox-retry (SEC-D). Пустой response. |
| UnregisterResource | UnregisterResourceRequest | UnregisterResourceResponse | sync | **FGA-proxy ([[SEC-A-proto-fga-proxy]])** — снять owner-tuple (поля идентичны Register). Internal-only :9091, нет `google.api.http`. authz `<exempt>` + ReBAC `fga_writer` @ `iam_fgaproxy:system`. **Идемпотентно** (снятие отсутствующего → OK, не NotFound). Пустой response. |

## REST mapping (internal mux only)

| HTTP | Method |
|---|---|
| `POST /iam/v1/internal/subjects:lookup` | LookupSubject |
| `POST /iam/v1/internal/permissions:list` | ListPermissions |

## Notes

- Newman E0 кейс `iam-internal-only-check` проверяет, что `/iam/v1/internal/*` **НЕ отвечает** на external TLS listener.
- E0 `ListPermissions` — простая агрегация по `access_bindings` + transitive через `group_members`; wildcards в permissions хранятся as-is, без expansion.
- E2 auth-interceptor `api-gateway` будет звать `LookupSubject` для резолва JWT → Principal.
- E3 переключит `ListPermissions` на OpenFGA `Check`/`ListObjects` (см. [[../edges/iam-to-openfga-check]]).
- `PollSubjectChanges` (WS-2.3) — read-only, по слоям Clean Arch: port `service.SubjectChangeReader` + pg-адаптер `internal/repo/kacho/pg/subject_change_repo.go`. Источник строк — `subject_change_outbox`, куда пишут `AccessBinding.Create/Delete` (см. [[../resources/iam-access-binding]]). Потребитель — [[../edges/api-gateway-to-iam-subject-change]].
- `RegisterResource`/`UnregisterResource` ([[SEC-A-proto-fga-proxy]]) — **proto + buf only** в SEC-A (нет Go-handler в этой подфазе; контракт верифицирован descriptor-assert `kacho-proto/internal/conformance/`). Это FGA-proxy: vpc/compute/nlb перестают писать owner-tuple в OpenFGA напрямую (эпик #6) и декларируют намерение через IAM. Реализация handler — SEC-C; transactional-outbox drainer в модулях (at-least-once) — SEC-D. Вызывающие рёбра: [[../edges/vpc-to-iam-fgaproxy]], [[../edges/compute-to-iam-fgaproxy]] (planned). Эпик: [[../KAC/EPIC-SEC-mtls-iam-authz]].

## See also

[[../packages/iam-domain]] [[../resources/iam-access-binding]] [[../resources/iam-user]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam #internal
