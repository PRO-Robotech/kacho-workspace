---
title: InternalAuthorizeService
aliases:
  - InternalAuthorize (iam)
  - FGA tuple write
proto_file: kacho/cloud/iam/v1/internal_authorize_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-access-binding]]"
methods_count: 6
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
  - fga
---

# InternalAuthorizeService (iam, internal)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_authorize_service.proto` (Phase 3).
**Backend**: `kacho-iam:9091` — cluster-internal listener.
**Visibility**: **Internal** — admin / control-plane only (workspace `CLAUDE.md` §Запреты #6). НЕ exposed на public TLS / api.kacho.cloud.
**Status**: **Phase 3 planned**. Write-path FGA tuple management + model lifecycle + Rego policy lifecycle.

## Methods (Phase 3, sync)

| Method | Description |
|---|---|
| WriteTuples | bulk INSERT of `(user, relation, object)`. Idempotent (OpenFGA 409 = success). Mostly invoked by FGAOutboxDrainer ([[../packages/iam-jobs]]) — direct admin-tool path. |
| DeleteTuples | bulk DELETE. Idempotent (404 = success). |
| ReadTuples | scan by prefix `(object_type, object_id?)`. Pagination cursor opaque. |
| WriteAuthorizationModel | upload new FGA model version. Returns `model_id` (immutable). Triggered by Phase 3 bundle-signer CI pipeline. |
| RunRegoTest | dry-run новой Rego policy против snapshot test-cases. Возвращает pass/fail + diff. |
| ReloadModel | atomic switch active model_id → new version. Logs prev+next в `audit_outbox`. |

## REST mapping (internal mux only, Phase 3)

| HTTP | Method |
|---|---|
| `POST /iam/v1/internal/authorize/tuples:write` | WriteTuples |
| `POST /iam/v1/internal/authorize/tuples:delete` | DeleteTuples |
| `POST /iam/v1/internal/authorize/tuples:read` | ReadTuples |
| `POST /iam/v1/internal/authorize/model:write` | WriteAuthorizationModel |
| `POST /iam/v1/internal/authorize/model:test` | RunRegoTest |
| `POST /iam/v1/internal/authorize/model:reload` | ReloadModel |

## Notes

- Write-path конкурирует с FGAOutboxDrainer, поэтому WriteTuples делает upsert семантику — повтор существующего tuple → ok.
- Model + Rego артефакты подписываются cosign в CI (Phase 11 supply-chain); ReloadModel валидирует подпись прежде чем switch.
- Phase 3 + Phase 8 связка: ReloadModel emit'ит CAEP `iam.fga.model.changed` event subscribers'у ([[../resources/iam-caep-subscriber]]).
- Прав: только `cluster:cluster_kacho_root#system_admin` может вызывать model write/reload.

## See also

[[iam-authorize-service]] [[iam-opa-bundle-service]] [[iam-conditions-service]] [[../packages/iam-jobs]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #internal #fga
