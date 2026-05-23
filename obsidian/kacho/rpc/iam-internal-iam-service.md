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
methods_count: 3
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
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

## See also

[[../packages/iam-domain]] [[../resources/iam-access-binding]] [[../resources/iam-user]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam #internal
