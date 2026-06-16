---
title: "[trail] kacho-iam production-readiness sweep (2026-06-16)"
ticket_id: PROD-READINESS-iam-2026-06
status: in-progress
type: fix
repos:
  - kacho-iam
  - kacho-api-gateway
  - kacho-corelib
  - kacho-deploy
prs:
  - "PRO-Robotech/kacho-iam#120,121,123,124,125,126,127,128,129,130,131,133,135"
  - "PRO-Robotech/kacho-api-gateway#77,78,79"
  - "PRO-Robotech/kacho-corelib#22"
opened: 2026-06-16
tags:
  - kac
  - fix
  - kacho-iam
  - security
  - architecture
---

# kacho-iam production-readiness sweep (2026-06-16)

Автономный sweep: аудит (RLM + спец-ревьюеры, 4 витка) → волнами фиксы строгим TDD →
CI-gate (kind+helm newman + gosec + golangci) → merge. Backlog = GitHub issue
[kacho-iam#122]. Аудит-витки: Round-2 (5-агентный RLM → #122 ~20 находок), Round-3
(верифицировал 7 мёрджей), Round-4 (4 security-критичных мёрджа VERIFIED-SOUND, 0 регрессий).

## Закрыто (19 PR merged)
- **AuthZ-resolution:** SAKey verb-fold (#120), gw RequiredRelation adapter — priv-esc через
  потерянный relation (gw#77), trust-aware principal-extract на :9091 — anti-spoof (#127),
  cluster-admin/ForceLogout in-iam ReBAC `system_admin` depth (#130).
- **Token/session revocation:** session-revocation service Revoke/ForceLogout/GetJWKSStatus был
  unregistered → inert (#125); user-level revocation — ForceLogout/RevokeAll реально отзывают
  live-токены через `user_token_revocations` + refresh-hook auth_time-gate (#128); refresh-hook
  fail-closed на missing jti (#131).
- **Data/audit:** AccessBinding strict-create doc + concurrent race-тест (#121); durable
  `audit_outbox` grant/revoke + AuditEmitterAdapter evt-id CHECK-fix (#126); pgx no-leak в
  INTERNAL (#121).
- **Surface:** ListOperations ×4 реальная реализация (был no-op, #123); dead-code purge
  SCIM/SAML/JIT/governance + CLAUDE.md §1 (#124); JIT_WINDOW deprecate + CHECK migration 0013 (#133);
  **REST Internal*-isolation** — Internal* REST → 404 на external + 4 FQN из allowlist (gw#78);
  PII-debug-print удалён (gw#79).
- **Ops:** Prometheus `/metrics` + authz-Check histogram + gRPC-метрики (#129); prod
  Config.Validate требует AuthN-секреты (#131); `Logger.Level` wired + slog в cmd (corelib#22 + #135).

## Остаток (трекнут в #122 — НЕ in-iam P0/P1)
- **(a) cert-aware периметр (EPIC-SEC SEC-F домен, in-iam-сторона готова):** hooks :9092 + /metrics :9095
  plaintext→mTLS; kacho-deploy `AUTH_MODE=dev`-default + нет `values.prod.yaml` → chart-default fail-closed.
- **(b) P2:** internal CallerPolicy floor-only на internal-reads (per-RPC relation-Check — careful, не сломать
  service-callers); `required_acr_min` не энфорсится на internal-пути (нужен acr-metadata plumbing gateway→corelib).
- **(c) test-debt (нужен живой стенд):** AuthorizeService BatchCheck/ListObjects/ListSubjects/Expand +
  ConditionsService newman (PR #134 закрыт — слепые кейсы 44 fail); InternalCluster/InternalAuthorize newman.

## Затронутые сущности vault
[[../resources/iam-access-binding-condition]] (whitelist 7→5, jit/break-glass dropped) ·
[[../edges/api-gateway-to-iam-authorize]] (Bug C RequiredRelation) · [[SEC-L-rest-internal-isolation]] ·
[[EPIC-SEC-mtls-iam-authz]] (периметр-residual).

## DoD
- [x] Все in-IAM P0/P1 закрыты + Round-4 verified (0 регрессий, 0 новых P0/P1).
- [ ] cert-aware периметр (EPIC-SEC SEC-F finalization).
- [ ] test-debt (live-stand authoring).
- [ ] P2 (internal-reads relation-Check, acr-on-internal).
