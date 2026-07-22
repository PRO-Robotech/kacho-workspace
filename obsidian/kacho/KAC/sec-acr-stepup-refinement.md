---
tags: [kac, security, iam, gateway, authz, phase-c]
status: landed
type: security-model-refinement
repos: [kacho (redesign/integration)]
---

# SEC-acr-stepup-refinement — narrow required_acr_min to 41-set

**Status:** impl landed + deployed (redesign/integration). **Issues:** #59 (production-newman Phase C), #60 (SA-caller user-token seed). **Acceptance:** `docs/specs/sub-phase-SEC-acr-stepup-refinement-acceptance.md` (R3, APPROVED — acceptance-reviewer + system-design-reviewer).

## Что и зачем

Сузили per-RPC step-up MFA floor `required_acr_min="2"` (AAL2) с blanket **372/438** RPC до ровно **41** posture-changing операций (credential mint/destroy + privilege-grant + tenancy-root destroy, domain-agnostic per RFC 9470 + NIST 800-63B). Остальные **332** non-exempt → `"1"` (AAL1 routine); **65** exempt → `""`. End-state: 41 + 332 + 65 = 438. Обе embedded-копии каталога byte-identical.

Мотив: blanket-`"2"` требовал интерактивную MFA на КАЖДОМ рутинном `Get`/`List`/`Create` — ломал non-interactive automation и весь production-newman user-subject поток (#59). Step-up по RFC 9470 — исключение для sensitive-операций, не дефолт.

## Sensitive-41 (categories A–H)

A credential (UserToken/SAKey Issue+Revoke, 4) · B AccessBinding Create/Update/Delete/Revoke (4; Create = exempt-permission + acr=2 **net-strengthening**) · C 22 compute Set/UpdateAccessBindings (non-iam grant surface) · D Group AddMember/RemoveMember/**Delete** (3; Delete = revoke-by-all, R3/B-2) · E Role Update/Delete · F Conditions Update/Delete · G InternalCluster Grant/RevokeAdmin · H Account/Project Delete.

## Реализация (TDD RED→GREEN)

- proto: 332 routine методов → явный `="1"`; 40 sensitive-с-permission → `="2"`; `AccessBindingService/Create` → `="2"` ADDED (permission остаётся `<exempt>` — ортогонально).
- каталог: regen обеих копий byte-identical; `make permission-catalog-check` green.
- 3 godoc-truthfulness фикса: `stepup_gate.go` (fail-open на пустом, не «default ACR=2»), `acr_floor.go` («SAME» → два отдельных table'а), `pkg/grpcsrv/acr.go` («SHARED … never drift» → iam-side only).
- lock-тесты: catalog 41-set invariant+complement+counts+byte-identity; routine-unblock/AAL1-floor/sensitive-blocks wiring; verdict-parity двух реальных entrypoint'ов (StepUpGate.Check ↔ grpcsrv.ACRSatisfies) над полной матрицей; iam floor Get=1/GrantAdmin=2; generator exempt→empty vs non-exempt→"2".
- Верификация: `go test` (authoritative, на deployed каталоге) + vet + golangci-lint + `-race` — все green.

## Live-verify

Refined каталог развёрнут на gateway через file-override (`KACHO_API_GATEWAY_PERMISSION_CATALOG_FILE` + ConfigMap `acr-refined-catalog`) — pod serving 41×"2"+332×"1" (verified in-pod). Bootstrap-admin RS256 → gateway 200.

## Блокер production-newman (Phase C, НЕ acr)

Live user-subject newman **всё ещё заблокирован** отдельными RS256-seed-гэпами, downstream от acr:
1. iam `UserTokenService.Issue` НЕ whitelist'ит api-audience на provisioned Hydra-клиенте → `client_credentials` exchange 400 (обошёл hydra-admin PATCH).
2. `client_credentials`-токен — машинный: `acr=None`, `kacho_principal_type=None`, `sub=client_id` → SA-классифицируется (acr-EXEMPT, O-1) → структурно НЕ тестирует user-acr=1 step-up. Нужен настоящий user-login токен (Kratos/OIDC с acr), которого seed не производит.

→ Эти гэпы принадлежат #59/#60, решаются отдельно; acr-floor (предмет этой под-фазы) — done+deployed.

## Затронутые сущности vault

- rpc: gateway StepUpGate, iam authzguard.ACRFloor, permission_catalog (обе копии)
- packages: `pkg/grpcsrv` (acr.go), `gateway/internal/middleware` (stepup_gate, permission_catalog_embed)
- edges: gateway→iam (:9091 acr-floor parity)
- docs: `gateway/docs/architecture/acr-stepup-floor.md`
