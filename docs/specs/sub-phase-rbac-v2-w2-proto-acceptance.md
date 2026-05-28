# Sub-phase RBAC v2 / W2 — kacho-proto acceptance

**Tracking**: [[KAC-215]] (parent: [[KAC-214]])
**Repo**: `kacho-proto`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` §3.2 (Scope), §3.3 (list-filter contract / `wildcard_grant`), §3.6 (removal scope), §4 (component map)
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 2
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- `proto/kacho/cloud/iam/v1/access_binding.proto` — additive `Scope` enum + `scope` field 15.
- `proto/kacho/cloud/iam/v1/authorize_service.proto` — additive `wildcard_grant` (bool, field 4) on `ListObjectsResponse`.
- `proto/kacho/cloud/iam/v1/fga_model.fga` — drop `emergency_admin`, drop `break_glass_window` condition, collapse `any_admin` to `system_admin`.
- DELETE `proto/kacho/cloud/iam/v1/break_glass_service.proto`.
- DELETE `proto/kacho/cloud/iam/v1/cluster_break_glass_grant.proto`.
- DELETE `proto/kacho/cloud/iam/v1/scim_user_mapping.proto`.
- Strip `BreakGlass*` RPCs from `proto/kacho/cloud/iam/v1/internal_iam_service.proto`.
- Regenerate go-stubs under `gen/go/kacho/cloud/iam/v1/`.

## Scope (out)

- No Go code consumer cleanup (that's [[KAC-217]]).
- No api-gateway route changes (that's [[KAC-218]]).
- No helm/deploy changes.
- No newman/integration tests.

## Scenarios

### S2.1 — Additive `Scope` enum + `scope` field is non-breaking

**Given** kacho-proto on `main` is at the current commit.
**And** the branch `KAC-215-rbac-v2-proto` is forked from `main`.
**When** `Scope` enum + `scope = 15` are added to `AccessBinding`.
**Then** `buf breaking --against '.git#branch=main'` produces zero output.
**And** existing wire payloads parsed with the new schema preserve all field values; the new `scope` field deserializes as `SCOPE_UNSPECIFIED` for legacy serialized rows.

### S2.2 — Additive `wildcard_grant` is non-breaking

**Given** the same branch baseline.
**When** `bool wildcard_grant = 4` is added to `ListObjectsResponse`.
**Then** `buf breaking` produces zero output.
**And** consumers (kacho-vpc, kacho-compute) that ignore the new field continue to behave identically.

### S2.3 — `fga_model.fga` removes emergency_admin without breaking referenced relations

**Given** the FGA model currently defines `emergency_admin: [user with break_glass_window]` and `any_admin: system_admin or emergency_admin`.
**When** both are removed and `any_admin: system_admin` substituted.
**Then** `openfga model validate --file fga_model.fga` (or `make openfga-model-validate`) exits 0.
**And** no other relation in the file references `emergency_admin` or `break_glass_window` (grep yields zero lines).

### S2.4 — Proto deletions are visible and intentional

**Given** the branch contains the proto deletions.
**When** `buf breaking --against '.git#branch=main'` is run.
**Then** the breaking-output lists exactly:
- removal of `kacho.cloud.iam.v1.BreakGlassService`
- removal of `kacho.cloud.iam.v1.ClusterBreakGlassGrant`
- removal of `kacho.cloud.iam.v1.ScimUserMapping`
- removal of any `BreakGlass*` RPC on `kacho.cloud.iam.v1.InternalIAMService`
**And** no other deletions are present.

### S2.5 — Regenerated go-stubs build

**Given** the proto changes from S2.1..S2.4 are applied.
**When** `make gen && go build ./...` is run inside kacho-proto.
**Then** the build is clean (the standalone `gen/go/` packages compile without consumers).
**And** the go-stubs for `iamv1.AccessBinding` carry the `Scope` enum + `GetScope()` accessor.
**And** the go-stubs for `iamv1.ListObjectsResponse` carry `GetWildcardGrant()`.
**And** files `iamv1/break_glass_service*.go`, `iamv1/cluster_break_glass_grant*.go`, `iamv1/scim_user_mapping*.go` are absent.

### S2.6 — Downstream consumer breakage is bounded to deleted surface

**Given** `kacho-iam/go.mod` pinned to kacho-proto via `replace ../kacho-proto` on the W2 branch.
**When** `go build ./...` is run in kacho-iam.
**Then** the only compile errors are import-cycle/missing-symbol errors on files slated for deletion in [[KAC-217]]: `internal/service/break_glass_service.go`, `internal/repo/kacho/pg/{scim,break_glass}_repos.go`, `internal/clients/jackson_client.go`, etc.
**And** no compile errors appear outside that set.

### S2.7 — `buf lint` stays clean

**Given** the W2 branch.
**When** `buf lint` is run.
**Then** exit 0; no diagnostics.

## Definition of Done

- [ ] Branch `KAC-215-rbac-v2-proto` exists; commits per Plan §Wave 2 tasks 2.1..2.4.
- [ ] All scenarios S2.1..S2.7 verified manually.
- [ ] PR `PRO-Robotech/kacho-proto#<N>` open with body listing each scenario + the buf-breaking expected output (intentional deletions).
- [ ] PR body shows the RED→GREEN baseline evidence required by workspace CLAUDE.md §«Запреты» #12: clean `buf breaking --against '.git#branch=main'` BEFORE any change on the branch, then the expected intentional-deletions output AFTER all changes.
- [ ] PR URL added to [[KAC-215]] frontmatter `prs:`.
- [ ] [[KAC-215]] → `In Progress` in YouTrack at PR-open; → `Test` when PR is review-ready; → `Done` after merge.
