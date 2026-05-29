# Sub-phase RBAC v2 / W5 — kacho-api-gateway acceptance

**Tracking**: [[KAC-218]] (parent: [[KAC-214]])
**Repo**: `kacho-api-gateway`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` §3.6
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 5
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- Regenerate `internal/middleware/embed/permission_catalog.json` (4-segment, source-of-truth mirror of `kacho-proto/gen/permission_catalog.json`).
- Remove SCIM REST mux routes (`/scim/v2/*`).
- Remove SAML REST mux routes (`/saml/acs`, `/saml/slo`, `/saml/metadata`, any `idp/saml` endpoints).
- Remove break-glass REST mux routes (`/iam/v1/breakGlass:approve`, `:deny`, `:list`, `:get`, etc).
- Remove BG/SCIM/SAML methods from `internal/grpcproxy/allowlist.go` (or equivalent allowlist file).

## Scope (out)

- No iam internal-listener changes (those are kacho-iam side, [[KAC-217]]).
- No newman cases ([[KAC-220]] adds list-filter, not removal-assertion-cases).

## Scenarios

### S5.1 — Catalog mirror is strictly 4-segment

**Given** the regenerated `internal/middleware/embed/permission_catalog.json`.
**When** the file is parsed at startup (or in a unit test).
**Then** every entry whose `permission` field is non-empty matches the regex `^(\\*|[a-zA-Z][a-zA-Z0-9_-]*)\\.(\\*|[a-zA-Z][a-zA-Z0-9_-]*)\\.(\\*|[a-zA-Z0-9_-]+)\\.(\\*|[a-z][a-zA-Z0-9_-]*)$`.

### S5.2 — Removed SCIM routes return 404

**Given** the gateway started on the W5 branch.
**When** an HTTP `GET /scim/v2/Users` is issued.
**Then** the response status is `404 Not Found`.
**And** the same for `GET /scim/v2/Groups`, `POST /scim/v2/Users`, `DELETE /scim/v2/Users/<id>`, and any other SCIM-v2 path documented under `obsidian/kacho/rpc/iam-scim-v2.md`.

### S5.3 — Removed SAML routes return 404

**Given** the gateway started on the W5 branch.
**When** HTTP requests are issued against `POST /saml/acs`, `GET /saml/metadata`, `POST /saml/slo`, or any SAML endpoint listed in `obsidian/kacho/rpc/iam-saml-sp.md`.
**Then** the response status is `404 Not Found`.

### S5.4 — Removed Break-Glass routes return 404

**Given** the gateway started on the W5 branch.
**When** HTTP requests are issued against `POST /iam/v1/breakGlass:approve`, `POST /iam/v1/breakGlass:deny`, `GET /iam/v1/breakGlass`, `GET /iam/v1/breakGlass/<id>`.
**Then** the response status is `404 Not Found`.

### S5.5 — Allowlist removal

**Given** the gateway started on the W5 branch.
**And** a synthetic gRPC client invokes any of `kacho.cloud.iam.v1.BreakGlassService/<Method>`, `…ScimUserMapping…`, `…OrganizationSaml…`.
**Then** the gateway rejects the call with `codes.Unimplemented` (or `Unauthenticated` if it never reached method-routing) — never proxies.

### S5.6 — Other public routes remain intact

**Given** the gateway started on the W5 branch.
**When** HTTP `GET /iam/v1/projects` is issued (public ProjectService.List).
**Then** the response status is non-404 (auth-gated paths return 401, but the **route exists**).
**And** the same is true for VPC public routes (`/vpc/v1/networks` etc.) and Compute public routes.

### S5.7 — `go build`, `go vet`, `go test ./...` clean

**Given** the W5 branch.
**When** `go build ./... && go vet ./... && go test ./...`.
**Then** exit 0.

## Definition of Done

- [ ] Branch `KAC-218-rbac-v2-gateway` exists; commits per Plan §Wave 5 tasks 5.1..5.3.
- [ ] Integration tests cover S5.1..S5.7; RED→GREEN pair documented in PR body.
- [ ] PR `PRO-Robotech/kacho-api-gateway#<N>` open; CI green.
- [ ] PR URL added to [[KAC-218]] frontmatter `prs:`.
- [ ] [[KAC-218]] → `In Progress` at PR-open; → `Done` after merge.
