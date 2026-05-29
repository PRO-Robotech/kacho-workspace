# Sub-phase RBAC v2 / W4 — kacho-iam code acceptance

**Tracking**: [[KAC-217]] (parent: [[KAC-214]])
**Repo**: `kacho-iam`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` §3.1-§3.6
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 4
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- `internal/authzmap/fga_types.go` — closed `(module,resource) → fga_object_type` table.
- Rewrite `internal/authzmap/permissions_to_relations.go` — 4-segment parser, `SplitGrants() []Grant`.
- `internal/domain/access_binding_scope.go` — `Scope` type + `ValidateAgainst(resourceType, resourceID)`.
- Plumb `scope` through `internal/repo/kacho/pg/access_binding*.go` (read/write).
- Validate scope at `internal/apps/kacho/api/access_binding/{create,update}.go`.
- Rewrite `internal/service/fga_tuple_writer.go` per design §3.5.
- Delete BG: `internal/service/break_glass_service*.go`, `internal/domain/cluster_break_glass_grant*.go`, `internal/repo/kacho/pg/break_glass_repos.go`.
- Delete SCIM: `internal/apps/kacho/api/scim/`, `internal/repo/kacho/pg/{scim_repos,scim_gdpr_reviews_repos,sso_scim_integration_test}.go`, `internal/domain/scim_user_mapping.go`.
- Delete SAML: `internal/apps/kacho/api/saml/`, `internal/repo/kacho/pg/organization_sso_repos.go`, `internal/clients/jackson_client*.go`, `internal/fuzz/fuzz_saml_assertion_test.go`.
- Strip BG/SCIM/SAML from `cmd/kacho-iam/{serve.go, wiring.go, governance_wiring.go, grpc_register.go, listeners.go}`.
- Regen `internal/apps/kacho/seed/embedded/permission_catalog.json` (4-segment mirror of api-gateway source).

## Scope (out)

- No api-gateway changes ([[KAC-218]]).
- No newman cases beyond unit/integration in this repo.
- No helm changes ([[KAC-220]]).

## Scenarios

### S4.1 — `FGAObjectType` returns correct types for the closed pair set

**Given** a fresh kacho-iam build.
**When** `FGAObjectType("compute", "instance")` is called.
**Then** it returns `("compute_instance", true)`.
**And** the same is true for every pair in the design §3.5 mapping table.
**And** `FGAObjectType("unknown", "thing")` returns `("", false)`.

### S4.2 — `SplitGrants` parses 4-segment permissions into structured Grants

**Given** `permissions = ["compute.instance.inst-abc.read", "vpc.network.*.create", "*.*.*.*"]`.
**When** `SplitGrants(permissions)`.
**Then** it returns:
- Grant{Module:"compute", Resource:"instance", ResourceName:"inst-abc", Verb:"read", Tier:"viewer", FGAType:"compute_instance"}
- Grant{Module:"vpc",     Resource:"network",  ResourceName:"*",        Verb:"create", Tier:"editor", FGAType:"vpc_network"}
- Grant{Module:"*",       Resource:"*",        ResourceName:"*",        Verb:"*",     Tier:"admin",  FGAType:""}

### S4.3 — `SplitGrants` skips malformed entries (least-privilege)

**Given** `permissions = ["compute.instance.read", "compute.instance..read", "compute.instance.*.read"]` (first two malformed).
**When** `SplitGrants(permissions)`.
**Then** the returned slice contains exactly one Grant (for the third entry).

### S4.4 — `PermissionsToRelations` tier-collapses 4-segment input

**Given** `["compute.instance.*.read"]`.
**When** `PermissionsToRelations(...)`.
**Then** it returns `[]Relation{"viewer"}`.

**Given** `["*.*.*.*"]`.
**Then** returns `[]Relation{"admin"}`.

### S4.5 — `Scope.ValidateAgainst` accepts matched pairs, rejects mismatches

**Given** `domain.ScopeCluster.ValidateAgainst("cluster", "cluster_kacho_root")`.
**Then** nil error.

**Given** `domain.ScopeAccount.ValidateAgainst("project", "prj-...")`.
**Then** `errors.Is(err, domain.ErrScopeMismatch)`.

**Given** `domain.ScopeProject.ValidateAgainst("project", "not-prj-prefixed")`.
**Then** `errors.Is(err, domain.ErrScopeMismatch)`.

### S4.6 — AccessBinding repo persists `scope`

**Given** a testcontainers Postgres at migration head (post-0025).
**When** an INSERT through `AccessBindingRepo.Insert` writes `Scope=ScopeAccount` along with `ResourceType=account, ResourceID=acc-...`.
**Then** the row reads back with `Scope == ScopeAccount`.

### S4.7 — AccessBinding handler rejects scope-mismatch on Create

**Given** a Create request `Scope=CLUSTER`, `Resource={type:project, id:prj-X}`.
**When** the handler runs validation.
**Then** the handler returns `codes.InvalidArgument` with a message naming the mismatched field.

### S4.8 — `EmitForBinding` matches the design §3.5 matrix

**Given** subject `user:usr-X`.
**When** binding with `scope=CLUSTER`, `resource_id=cluster_kacho_root`, permission `*.*.*.*`.
**Then** the single emitted tuple is `{object:"cluster:cluster_kacho_root", relation:"system_admin", user:"user:usr-X"}`.

**Given** `scope=ACCOUNT, resource_id=acc-A`, permission `compute.instance.*.read`.
**Then** emitted `{object:"account:acc-A", relation:"viewer", user:"user:usr-X"}`.

**Given** `scope=PROJECT, resource_id=prj-P`, permission `compute.instance.inst-abc.read`.
**Then** emitted `{object:"compute_instance:inst-abc", relation:"viewer", user:"user:usr-X"}`.

**Given** `scope=CLUSTER, resource_id=cluster_kacho_root`, permission `vpc.network.*.create`.
**Then** emitted `{object:"cluster:cluster_kacho_root", relation:"editor", user:"user:usr-X"}`.

### S4.9 — Break-Glass surface fully removed

**Given** a fresh `git grep -i 'break.\\?glass\\|emergency_admin\\|cluster_break_glass'` over `internal/ cmd/`.
**Then** zero matches.

### S4.10 — SCIM surface fully removed

**Given** `git grep -i 'scim'` over `internal/ cmd/`.
**Then** zero matches.

### S4.11 — SAML / jackson surface fully removed

**Given** `git grep -i 'saml\\|boxyhq\\|jackson'` over `internal/ cmd/`.
**Then** zero matches.

### S4.12 — `go build`, `go vet`, `go test ./...` clean

**Given** the W4 branch with all edits.
**When** `go build ./... && go vet ./... && go test -race ./...`.
**Then** exit 0.
**And** no test is skipped (`t.Skip`/`testing.Short`) for BG/SCIM/SAML reasons (those tests are deleted, not skipped).

### S4.13 — `permission_catalog.json` is strictly 4-segment

**Given** the regenerated `internal/apps/kacho/seed/embedded/permission_catalog.json`.
**When** the registry is loaded at startup.
**Then** every entry whose `permission` field is non-empty contains exactly three dots (4 segments).

## Definition of Done

- [ ] Branch `KAC-217-rbac-v2-code` exists; commits per Plan §Wave 4 tasks 4.1..4.10.
- [ ] All unit + integration tests covering S4.1..S4.13 pass; RED→GREEN pair documented in PR body.
- [ ] PR `PRO-Robotech/kacho-iam#<N>` open; CI green.
- [ ] PR URL added to [[KAC-217]] frontmatter `prs:`.
- [ ] [[KAC-217]] → `In Progress` at PR-open; → `Done` after merge.
