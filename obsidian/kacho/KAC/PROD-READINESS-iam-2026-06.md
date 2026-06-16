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
  - "PRO-Robotech/kacho-iam#120,121,123,124,125,126,127,128,129,130,131,133,135,136"
  - "PRO-Robotech/kacho-api-gateway#77,78,79"
  - "PRO-Robotech/kacho-corelib#22"
  - "PRO-Robotech/kacho-deploy#88,89,90"
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
- **Периметр Wave-17:** hooks (:9092) + metrics (:9095) HTTP-listener'ы были plaintext →
  per-edge server-side mTLS (default-OFF dev/newman byte-identical, prod-ON через
  `values.prod.yaml` `mtls.httpListeners`, переиспользует SEC-F server-cert), fail-closed
  Validate(), `RequireAndVerifyClientCert` (iam#136 + deploy#89). gosec G304 trusted-CA-read
  suppress. newman E2E зелёный (gate инертен default-off).

## Остаток (трекнут в #122)
- **(a) cert-aware периметр — ЗАКРЫТО:** hooks :9092 + /metrics :9095 plaintext→mTLS (Wave-17, iam#136+deploy#89);
  `values.prod.yaml` production-strict + fail-closed (deploy#88). Остаётся только EPIC-SEC SEC-G operator-edge финализация (вне этого sweep).
- **(b) P2 — В РАБОТЕ:** internal-reads per-RPC `system_viewer`-floor — acceptance sub-phase 5.1 APPROVED, реализация
  (worktree, TDD, default-off prod-mode, Check-PDP исключён, SEC-C seed migration 0014). `required_acr_min` не энфорсится
  на internal-пути (нужен acr-metadata plumbing gateway→corelib) — следующая волна.
- **(c) test-debt:** AuthorizeService BatchCheck/ListObjects/ListSubjects/Expand + ConditionsService newman
  (PR #134 закрыт — слепые кейсы 44 fail); InternalCluster/InternalAuthorize newman — careful CI-validated re-attempt.

## Затронутые сущности vault
[[../resources/iam-access-binding-condition]] (whitelist 7→5, jit/break-glass dropped) ·
[[../edges/api-gateway-to-iam-authorize]] (Bug C RequiredRelation) · [[SEC-L-rest-internal-isolation]] ·
[[EPIC-SEC-mtls-iam-authz]] (периметр-residual).

## Round-5 аудит (RLM, 7 finder'ов → adversarial verify → 21 подтверждено)
Полный список + волновой план — [kacho-iam#122 comment](https://github.com/PRO-Robotech/kacho-iam/issues/122).
- **P0 (FIXED, deploy#90):** Wave-17 `httpListeners:true` в prod → `RequireAndVerifyClientCert` ломает Ory-вебхуки
  (HMAC, без client-cert) + Prometheus scrape → all-auth-break. Gate OFF; capability в коде; дизайн → [[#137]].
  Побочно: helm value-override-layering на umbrella недетерминирован → render-guard через grep шаблона.
- **Wave T** — timestamp truncate-to-sec конформанс (8 мест, реальные µs-leak в Operation/SAKey/InternalAuthorize/ForceLogout/SessionRevocations).
- **Wave A** — `audit_outbox` пропущен на мутациях (cluster-admin/session-revoke/Account/Project/User/SA/Group/Role/SAKey; только AccessBinding пишет) — P1 compliance.
- **Wave R** — `InternalUserService.OnRecoveryCompleted` proto-defined но Unimplemented (Kratos recovery сломан).
- **Wave D** — дроп 3 осиротевших таблиц (squash KAC-193: fga_model_version/watch_cursors/refresh_token_counters).
- **Wave Q** — тест-долг (ConditionsService.Evaluate, InternalAuthorize ReloadModel/GetFGAStoreInfo).

## DoD — ✅ ЗАКРЫТО (2026-06-16, ~40 PR merged)
- [x] Все in-IAM P0/P1 закрыты; Round-2..5 + **Round-6 FINAL (RLM 13 агентов): все core-волны verified SOUND, 0 регрессий**.
- [x] cert-aware периметр: hooks/metrics mTLS capability (#136) + prod-gate-coherence (#90) + prod-strict values (#88) + transport server-tls-only #137 (iam#150/deploy#92).
- [x] CI integrity: integration был фиктивным (continue-on-error) → hard-gate + `./...` full scope (#139/#142) + #140 latent cluster-тесты.
- [x] internal-reads `system_viewer`-floor (#138).
- [x] Wave A audit_outbox — ВСЕ мутации (cluster+session #141, CRUD #144, SAKey #145, **Conditions #151**).
- [x] Wave T timestamp truncate + DRY (#143/#151).
- [x] Wave R OnRecoveryCompleted + SAVEPOINT degradation (#147).
- [x] Wave Q test-debt (#148) + Wave D dead-tables (свёрнуто в #151 cleanup / по факту orphan-tables — отдельный low-prio, не блокер).
- [x] acr-on-internal end-to-end (corelib#23 / iam#149 / gw#80) — cluster-admin acr=2 реально энфорсится.
- [ ] **Tracked OUT-of-scope** (не in-iam-код): deploy#91 (Kratos provision routing drift, live-stand), deploy#93 (newman bootstrap-race flakiness), #137 live-Ory E2E (render+unit-validated). #146 closed (5.3-09 reconciled).

**Итог:** prod-readiness ~6→~9/10. Все P0/P1 in-IAM закрыты; остаток — infra/deploy/live-stand, не код.
