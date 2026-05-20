---
title: CAEPSubscriberService
aliases:
  - CAEP Subscriber (iam, internal)
proto_file: kacho/cloud/iam/v1/internal_caep_subscriber_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-caep-subscriber]]"
methods_count: 6
async_methods: 4
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
  - caep
---

# CAEPSubscriberService (iam, internal)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_caep_subscriber_service.proto` (Phase 8).
**Backend**: `kacho-iam:9091` — cluster-internal.
**Visibility**: **Internal** — admin / account-owner registers OAuth resource servers (Salesforce / Okta / downstream apps) для CAEP Continuous Access Evaluation Profile push'ей.
**Status**: **Phase 8 planned**. CRUD subscribers + manual replay.

## Methods (Phase 8)

| Method | Sync/Async | Description |
|---|---|---|
| CreateSubscriber | async | INSERT `caep_subscribers` ([[../resources/iam-caep-subscriber]]). Required: `endpoint_url` (https://), `events` ([]event_type), `auth_type` (mtls / oauth2_client_credentials / bearer). |
| GetSubscriber | sync | by id |
| UpdateSubscriber | async | mutable: endpoint_url, events, auth_credentials, enabled. |
| DeleteSubscriber | async | hard-delete + flush pending CAEP outbox rows для этого subscriber. |
| ListSubscribers | sync | per-Account filter. |
| ReplayEvent | async | manual re-push конкретного event_id из `caep_outbox` (debug / recovery). |

## REST mapping (internal mux)

| HTTP | Method |
|---|---|
| `POST /iam/v1/internal/caep/subscribers` | CreateSubscriber |
| `GET /iam/v1/internal/caep/subscribers/{id}` | GetSubscriber |
| `PATCH /iam/v1/internal/caep/subscribers/{id}` | UpdateSubscriber |
| `DELETE /iam/v1/internal/caep/subscribers/{id}` | DeleteSubscriber |
| `GET /iam/v1/internal/caep/subscribers` | ListSubscribers |
| `POST /iam/v1/internal/caep/events/{event_id}:replay` | ReplayEvent |

## Event types (Phase 8 catalog)

- `session.revoked` — kacho-side BCL / forced logout
- `iam.token.revoked` — OAuth client revoke / SA key rotate
- `iam.user.disabled` — soft-disable from SCIM/admin
- `iam.session.changed` — step-up, MFA reset
- `iam.role.changed` — admin grant/revoke
- `iam.fga.model.changed` — Phase 3 model reload
- `iam.break_glass.activated` — operator alert
- `iam.federation.policy.revoked` — Phase 5

## Notes

- Subscriber endpoint: cAEP `Security Event Token` (RFC 8417 SET, signed JWT).
- Auth `mtls` — client cert verified против `caep_subscribers.tls_ca` bundle.
- Auth `oauth2_client_credentials` — subscriber issues bearer via Hydra OAuth (kacho-iam acts as RS), then kacho gateway пушит на subscriber.
- Retry policy: exponential backoff, max 24h. После — DLQ + alert ([[../packages/iam-service-caep]]).

## See also

[[../resources/iam-caep-subscriber]] [[../edges/iam-caep-to-subscriber]] [[../packages/iam-service-caep]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #internal #caep
