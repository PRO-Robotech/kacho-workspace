---
title: "iam → caep-subscriber: outbound SET push"
aliases:
  - caep push
  - caep outbound
  - iam caep subscriber
category: edge
caller_repo: kacho-iam
callee_repo: external-rs
sync_async: async
protocol: HTTPS (RFC 8417 SET delivery)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - caep
---

# iam → caep-subscriber: outbound SET push

**Caller**: kacho-iam CAEP drainer (`internal/service/caep_drainer.go`, [[../packages/iam-service-caep]]).
**Callee**: external OAuth Resource Servers / SaaS apps (registered via [[../rpc/iam-caep-subscriber-service]]):
- Salesforce / Okta downstream sessions / Slack / Microsoft 365 / corporate SAML SPs.

**Protocol**: HTTPS POST with signed JWT body (RFC 8417 SET — Security Event Token).
**Sync/Async**: async (outbox pattern из `kacho_iam.caep_outbox`).
**Status**: **Phase 8 planned**. SLO ≤10s revoke propagation.

## Event delivery flow

```
business write-TX                  caep_outbox row              drainer
─────────────────────────         ────────────────              ──────
iam.access_binding.delete   ──>   INSERT caep_outbox        ──> FetchPending(50)
(atomic)                          (event=session.revoked,      ↓
                                   subject=usr_xxx,             For each subscriber per event_type:
                                   subscribers=[ ... ])           HSM.SignSET(payload) →
                                                                  POST https://subscriber/.well-known/sse-rfc8417/event
                                                                  ↓
                                                                  202 → MarkProcessed
                                                                  4xx/5xx → MarkFailed + retry exp-backoff
                                                                  >24h → DLQ + alert
```

## SET (Security Event Token, RFC 8417) format

```jwt
HEADER:  { "alg": "EdDSA", "kid": "caep-set-2026-q2", "typ": "secevent+jwt" }
PAYLOAD:
{
  "iss": "https://api.kacho.cloud",
  "iat": 1734672000,
  "jti": "cev_01HW3X2C8R5M2N7P8Q9R0S1T2U",
  "aud": "https://salesforce.example.com",
  "events": {
    "https://schemas.openid.net/secevent/caep/event-type/session-revoked": {
      "subject": {
        "format": "iss_sub",
        "iss": "https://api.kacho.cloud",
        "sub": "usr_xxx"
      },
      "initiating_entity": "policy",
      "reason_admin": { "en": "AccessBinding revoked by admin" },
      "event_timestamp": 1734672000
    }
  }
}
SIGNATURE: HSM-signed EdDSA (см. [[iam-to-hsm]])
```

## Event types supported (Phase 8)

- `session.revoked` (CAEP standard)
- `iam.token.revoked` (kacho custom — for OAuth revocation propagation)
- `iam.user.disabled` (SCIM deprovision + GDPR)
- `iam.session.changed` (step-up / MFA re-enrollment)
- `iam.role.changed` (admin grant/revoke)
- `iam.fga.model.changed` (Phase 3 model reload)
- `iam.break_glass.activated` (warn downstream apps)
- `iam.federation.policy.revoked` (Phase 5)

## Subscriber endpoint authentication

| Auth type | Description |
|---|---|
| `mtls` | Subscriber TLS cert verified против `caep_subscribers.tls_ca` bundle. |
| `oauth2_client_credentials` | kacho fetches subscriber's OAuth bearer-token (via Hydra outbound). Includes scope `caep.events.receive`. |
| `bearer` | Pre-issued long-lived token (less preferred). |

## SLO (Phase 8)

- p99 propagation ≤5s (kacho event commit → subscriber 2xx ack).
- p999 ≤10s.
- Verified k6 load test (Phase 8 DoD).

## Retry / DLQ

- Retry attempts: 5 immediate (exp-backoff 1s/2s/4s/8s/16s) + 24h tail (every 1h).
- After 24h failed → DLQ Kafka topic `kacho.iam.caep.dlq` + PagerDuty alert.
- Manual replay via [[../rpc/iam-caep-subscriber-service]] ReplayEvent.

## See also

[[../rpc/iam-caep-subscriber-service]] [[../resources/iam-caep-subscriber]] [[iam-to-hsm]] [[iam-to-kafka-audit]] [[../packages/iam-service-caep]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #caep
