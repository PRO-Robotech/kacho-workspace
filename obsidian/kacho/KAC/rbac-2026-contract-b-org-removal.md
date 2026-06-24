---
title: "RBAC Contract-B — full removal of B2B Organization (proto/iam/deploy)"
ticket_id: rbac-2026-contract-b
status: test
type: refactor
repos:
  - kacho-proto
  - kacho-iam
  - kacho-deploy
prs:
  - https://github.com/PRO-Robotech/kacho-proto/pull/86
  - https://github.com/PRO-Robotech/kacho-iam/pull/238
  - https://github.com/PRO-Robotech/kacho-deploy/pull/123
opened: 2026-06-24
tags:
  - kac
  - kacho-proto
  - kacho-iam
  - kacho-deploy
  - refactor
  - proto
  - domain
  - migrations
---

# RBAC Contract-B — full removal of B2B Organization

**Status**: test (3 PRs open; iam/deploy CI pin proto@`rbac-contract-b-org-removal` until proto merges)
**Type**: refactor / breaking removal — RBAC-2026 epic #109, **contract phase** (Contract-A flat model already in main of all repos)
**Acceptance**: `docs/specs/rbac-explicit-model-2026-acceptance.md` — D-12 / **D-12a (Q-1 full-removal, variant A)** / G-01 / G-02 / G-03 / G-05 / P1 / P1b

## Что и зачем

Владелец: «org нет, убрать всё». Полное удаление legacy B2B-ресурса **Organization** из authz-модели и proto-поверхности. Семантика доступа уже плоская (Contract-A); Contract-B убирает мёртвый org-тип целиком.

## Объём по репо

### kacho-proto (PR #86, `feat(proto)!`)
- Удалён `organization.proto` (`Organization` + Create/Update/Delete metadata). `OrganizationService` живым зарегистрированным сервисом никогда не был.
- `Account.organization_id` (tag 7) + `Role.organization_id` (tag 9) дропнуты → **reserved-tombstone** (`reserved 7/9; reserved "organization_id"`). DB-колонки уже дропнуты iam-миграцией 0008.
- `fga_model.fga`: `type organization` + все `… from organization` деривации на `type account` (admin/editor/viewer/billing_admin) + parent-pointer `organization`. Модель плоская: `cluster → account → project`. `openfga model validate` → `is_valid:true`, 0 organization в compiled JSON.
- Удалены осиротевшие dead `compliance_report{,_service}.proto` (`ComplianceReportService` снят в KAC-223, 0 consumers, нёс residual `organization` scope).
- Comment-only org-зачистка в cluster/authorize_service/internal_iam_service/internal_iam_hooks_service/authz_options/access_binding_service/access.proto.
- `buf lint` ✓; `buf generate` стабилен; `scripts/tombstone_enforce.sh` Case 3 добавлен (org_id 7/9 reuse → lint FAIL). `buf breaking` = INTENTIONAL (3 file + 2 field deletions, документировано в buf.yaml + ci.yaml, continue-on-error, F/G-posture).

### kacho-iam (PR #238, `feat(iam)!`, P1b)
- DB-decommission уже сделан в `0008_drop_organizations.sql` (table + accounts/roles organization_id columns + roles_scope_xor rewrite). **Новая миграция НЕ нужна** (ban #5 — 0008 не редактируется).
- `domain.DeriveFromResourceType`: убран мёртвый case `"organization"` → ScopeCluster (теперь default ScopeProject). TDD RED→GREEN на `TestScope_DeriveFromResourceType`.
- Comment-cleanup: cluster.go/role.go/account.go/role_scope.go/config.go/seed/*.go/oidc_jwks_keys_repos.go + negative-test garbage subject_type.
- `go build`/`vet`/`gofmt` ✓ против Contract-B proto. CI пинит proto-ветку.

### kacho-deploy (PR #123, `chore(deploy)!`)
- `openfga-model-stub-configmap.yaml` регенерирован `make openfga-model-json` из canonical Contract-B fga (D-13). Compiled model.json: 0 organization. Header-комментарий чарта поправлен.
- Удалён dead OPA guardrail `deny_org_scim_mismatch.rego` (`resource_type == "organization"`, никогда не матчит) + его wiring.
- Comment-cleanup stale `organizations`/`organizations_users.json` в deny_prod_out_of_hours.rego (live, логика без изменений) + opa-bundle/fallback configmaps.
- newman-e2e пинит REF_PROTO + REF_IAM на Contract-B ветки.

## grep-0 (G-03)

0 *живых* organization-ссылок в proto/iam/deploy коде/схеме. Остаются: reserved-tombstone statements + removal-documentation комментарии + immutable migration 0008 (канонический schema-removal record) + accurate KAC-223 test-doc history.

## Затронутые сущности vault

- [[resources/iam-account]] (organization_id поле снято)
- [[resources/iam-role]] (organization_id поле снято, scope = {account,project})
- [[rpc/iam-access-binding-service]] (ScopeGroup enum: SYSTEM/ACCOUNT/PROJECT, без ORGANIZATION)
- [[rbac-explicit-model-2026]] (эпик-anchor)
- [[rbac-2026-contract-a-fix-iam-content-forward]] (предшествующая фаза)

## DoD-чеклист

- [x] proto: organization.proto + поля + FGA type/derivations удалены, reserved-tombstone
- [x] FGA model validate is_valid:true, 0 organization compiled
- [x] iam build/vet/gofmt clean против Contract-B proto; TDD RED→GREEN
- [x] deploy configmap regen (0 organization), dead guardrail dropped, helm template clean
- [x] grep-0 (G-03) — 0 live org refs
- [x] 3 PRs открыты, CI-пины проставлены
- [ ] review: proto-api-reviewer (#86) + db-architect (миграция-контекст 0008) + acceptance-reviewer
- [ ] coordinated merge proto → iam → deploy → revert CI-пины на main
- [ ] gateway: НЕ требует изменений (живого iam OrganizationService route не было; org-refs относятся к retired resourcemanager + load-bearing security-тест блокировки)

## Связанные

- Эпик: RBAC-2026 #109 (GitHub)
- Предшественник: Contract-A (flat FGA, в main всех репо)
