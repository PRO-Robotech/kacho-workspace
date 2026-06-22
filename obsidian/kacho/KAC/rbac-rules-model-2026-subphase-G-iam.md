---
title: RBAC rules-model 2026 — sub-phase G (Permission Catalog) — proto/iam/gateway/ui
ticket_id: rbac-rules-model-2026-G-iam
status: done
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-ui
prs:
  - "PRO-Robotech/kacho-proto#78"
  - "PRO-Robotech/kacho-iam#208"
  - "PRO-Robotech/kacho-api-gateway#94"
  - "PRO-Robotech/kacho-ui#106"
yt_url: ""
opened: 2026-06-22
tags:
  - kac
  - kacho-iam
  - kacho-proto
  - kacho-api-gateway
  - kacho-ui
  - feature
  - usecase
  - handler
  - proto
  - authz
  - done
---

# RBAC rules-model 2026 — sub-phase G (Permission Catalog) — proto/iam/gateway/ui

**Status**: **done** — merged to main 2026-06-22. Cross-repo chain (topo): proto **#78** → iam **#208** → api-gateway **#94** → ui **#106**.
**Type**: feature — epic «RBAC rules-model 2026», sub-phase G = backend-driven permission catalog.
**Acceptance**: `docs/specs/rbac-rules-model-2026-G-permission-catalog-acceptance.md` (APPROVED round 3, 2026-06-22).

## Merge (2026-06-22)

- **proto #78** — `PermissionCatalogService.ListPermissionCatalog` + tombstone `RunRegoTest`/`ListPermissions`.
- **iam #208** — handler/usecase (projection `authzmap.Catalog()`+`TypeHasVerbRelations`+`domain.ClosedVerbs`+curated `hasListEndpoint`); also bundled this session's prod-readiness cleanup (CRITICAL ledger-fix mig 0032, AccessBinding dedup, dead-code/stub removal, fail-closed parseMode). docs-site split out → iam issue #209 (trivy KSV-0118).
- **api-gateway #94** — public-mux + allowlist + route-table registration; resync embedded `permission_catalog.json` (288→287).
- **ui #106** — `usePermissionCatalog` (live RPC), RulesEditor dropdowns from catalog + resourceNames real-instance picker; hardcoded `permissionCatalog.ts` retired. e2e walkthrough mock added (`_mocks.ts`).
- **Cross-repo lesson**: proto tombstone temporarily broke iam-main build; the catalog newman suite (in iam) runs in every umbrella e2e and needs the gateway route → merge order proto→iam→gateway, then re-run consumer e2e. `hasListEndpoint` truth = external-mux registration, not proto RPC existence.
- Consumer review follow-ups merged same day: vpc **#163** (ListByIDs test coverage), nlb **#37** (name-parser unify + authzfilter tests). Follow-ups: nlb #38 (cache-copy), iam #209 (docs-site).

## Что и зачем

Делает grantable role-rule dropdown'ы backend-driven вместо UI-hardcode. Один публичный
sync read `PermissionCatalogService.ListPermissionCatalog` отдаёт grantable-таксономию
(modules→resources + per-type флаги) + closed verbs + wildcard policy — проекция из кода
(`authzmap` + `domain`), НЕ из БД. UI грузит опции из живого RPC (отдельная ui-фаза).

## Part 1 — drop tombstoned stubs (proto removed → iam follows)

- **`InternalIAMService.ListPermissions`** (false-assurance :9091 stub) — удалён целиком:
  `internal/apps/kacho/api/internal_iam/list_permissions.go` + test + embedded
  `permission_catalog.json` + handler-метод + doc-comment; authzguard `ReadFloorRPCs()` entry
  снят (+ membership-тест); caller_policy doc-comment поправлен; newman LISTPERMS cases
  (`IAM-INT-OK-INT-LISTPERMS` / `IAM-INT-NEG-EXT-IAM-LISTPERMS`) удалены, collection регенерена.
- **`InternalAuthorizeService.RunRegoTest`** — был только embedded-Unimplemented (нет explicit impl);
  proto-tombstone убрал типы. Снят из authzguard `GatewayFrontedInternalRPCs()` (+ membership-тест),
  doc-comment в internal_authorize/handler.go обновлён. `go build ./...` зелёный после Part 1.

## Part 2 — new public PermissionCatalogService.ListPermissionCatalog

- **NO DB / NO migration / NO repo** — projection from code.
- `internal/authzmap/fga_types.go` — **новый exported `Catalog() []CatalogEntry`** (ordered
  `(module,resource)` из closed `objectTypes`; single source — `objectTypes` остаётся unexported).
- `internal/apps/kacho/api/permission_catalog/` — use-case (`ListPermissionCatalogUseCase`,
  anti-anon `authzguard.RequireAuthenticated` первым стейтментом) + curated `hasListEndpoint`
  DENY-set (`has_list_endpoint.go`: false только для `vpc.addressPool` + `iam.condition`) +
  thin handler (DTO→proto). Clean-arch: импортит только `domain`/`authzmap`/`authzguard`, НЕ pgx/grpc-stubs в use-case.
- Зарегистрирован на **PUBLIC** listener: `cmd/kacho-iam/grpc_register.go` →
  `registerPublicServices` → `iamv1.RegisterPermissionCatalogServiceServer` (рядом с Role/Conditions);
  wiring в `cmd/kacho-iam/wiring.go` (`permissionCatalogHandler`). gateway-каталог marks `<exempt>` (auth-floor, no FGA Check).

## RED→GREEN

- Go unit/handler (no Postgres) `internal/apps/kacho/api/permission_catalog/usecase_test.go`:
  RED = пакет/accessor отсутствуют (build failed: undefined Handler/NewHandler/NewListPermissionCatalogUseCase/authzmap.Catalog) →
  GREEN = 10 тестов (G-01/04/05/06/07/08/08b/09/02) PASS.
  - G-04 two-way set-equality catalog ↔ `authzmap.Catalog()` + closedVerbs == `domain.ClosedVerbs`.
  - G-05 hasVerbRelations == `TypeHasVerbRelations` per type (account/project=false, leaves=true).
  - G-06 geo.*/compute.diskType absent + no `geo` module. G-07 wildcard flags. G-08 hasListEndpoint table.
  - G-08b `vpc.addressPool` hasVerbRelations==true && hasListEndpoint==false (SECURITY anchor). G-02 anonymous → PermissionDenied.
- newman `tests/newman/cases/iam-permission-catalog.py`: `CONF-G-01-catalog-happy` (authed GET 200,
  modules/closedVerbs/wildcardPolicy/addressPool-false/no-geo) + `NEG-G-02-catalog-anonymous-unauthenticated`
  (401/code16, no-leak). validate+gen зелёные; suite registered in run.sh.

## Verify

- `go build ./...` / `go vet ./...` clean; `gofmt -l` clean.
- `go test ./... -short -count=1` GREEN (incl cmd wiring); `-race` clean on affected no-DB pkgs.
- golangci-lint 1.59.1 не запускается под go1.26 (env version mismatch — не дефект кода); govulncheck не установлен в среде.

## Затронутые сущности vault

- [[iam-permission-catalog-service]] — **новый** публичный sync read RPC.
- [[iam-internal-iam-service]] — `ListPermissions` row/REST/notes удалены (stub снят).
- [[iam-role-service]] — role-rule editor консумит каталог (ui-фаза).
- [[rbac-rules-model-2026-subphase-F-iam]] — предшествующая (stacks on F).

## Осталось (НЕ в этих PR)

- kacho-api-gateway: register `GET /iam/v1/permissionCatalog` на public mux (`api-gateway-registrar`).
- kacho-ui: react-query catalog-hook + RulesEditor dropdowns + resourceNames-picker; retire `permissionCatalog.ts` + drift-test (отдельная ui-фаза).
- reviewer gates (proto-api-reviewer / go-style-reviewer / system-design-reviewer).

## DoD

- [x] Part 1: tombstoned stubs dropped; `go build ./...` green.
- [x] Part 2: PermissionCatalogService projection + public registration; RED→GREEN Go + newman.
- [x] go build/vet/gofmt clean; `-short` + `-race` green.
- [ ] api-gateway / ui (отдельные фазы).
- [ ] reviewer gates.

#kac #kacho-iam #kacho-proto #feature #usecase #handler #proto #authz
