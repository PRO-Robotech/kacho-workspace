# Sub-phase RBAC v2 / W6 — kacho-vpc + kacho-compute list-filter audit acceptance

**Tracking**: [[KAC-219]] (parent: [[KAC-214]])
**Repos**: `kacho-vpc`, `kacho-compute`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` §3.3, §3.4
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 6
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- Audit every public `List<Resource>` RPC in `internal/apps/` of both repos.
- Wire `listauthz.Adapter.ListAllowedIDs(subject, action, resource_type)` into every handler missing it.
- Add the empty / two-ids / wildcard-bypass / unavailable matrix tests per handler.
- Add CI gate `make audit-list-filter` script (`tools/audit-list-filter.sh`) — fails if any `List<Resource>` handler is unwired.

## Scope (out)

- No proto changes ([[KAC-215]]).
- No kacho-iam changes ([[KAC-217]]).
- No newman ([[KAC-220]]).

## Per-handler list (audit baseline; final list comes from the inventory commit)

**kacho-vpc** (expected):
- `NetworkService.List`
- `SubnetService.List`
- `AddressService.List`
- `SecurityGroupService.List`
- `RouteTableService.List`
- `GatewayService.List`
- `PrivateEndpointService.List`
- `NetworkInterfaceService.List`
- `AddressPoolService.List` (Internal)

**kacho-compute** (expected):
- `InstanceService.List`
- `DiskService.List`
- `ImageService.List`
- `SnapshotService.List`
- `DiskTypeService.List` (cluster-scoped reference)
- `HypervisorService.List` (Internal; cluster-scoped)

Inventory commit (Task 6.1) produces the authoritative final list — `docs/audit/2026-05-28-list-handlers-{vpc,compute}.md`.

## Scenarios

For each `<Resource>` in the inventory, the following four scenarios MUST hold:

### S6.x.1 — Subject with concrete-resourceName grants sees only those rows

**Given** the IAM ListObjects stub configured: `subject=user:usr-bob, action=<module>.<resource>.*.read, resource_type=<fga_type> → {ids:[<id-A>, <id-B>], wildcard_grant:false}`.
**And** five rows of `<Resource>` seeded: ids `<id-A>..<id-E>`.
**When** `<ResourceService>.List(ctx, &Request{})` is called by `usr-bob`.
**Then** the response items are exactly `{<id-A>, <id-B>}` (order may vary).
**And** the response status code is OK (not PermissionDenied).
**And** the response `total_size` (if present) reflects 2.

### S6.x.2 — Wildcard-grant short-circuits the filter

**Given** ListObjects stub returns `{ids:[], wildcard_grant:true}` for the subject.
**And** the same five rows are seeded.
**When** `List` is called.
**Then** the response items contain all five rows.
**And** the handler did NOT apply `WHERE id = ANY(...)` (verifiable via a counter on the stub or by `wildcard_grant` field being honoured).

### S6.x.3 — Empty grants returns empty list

**Given** ListObjects stub returns `{ids:[], wildcard_grant:false}` for the subject.
**And** five rows seeded.
**When** `List` is called.
**Then** the response items are empty.
**And** the status code is OK (NOT PermissionDenied — resource existence must remain unknowable).
**And** `next_page_token` is empty.

### S6.x.4 — ListObjects unavailable surfaces as Unavailable

**Given** the ListObjects stub returns `error=Unavailable`.
**When** `List` is called.
**Then** the handler returns gRPC `codes.Unavailable`.
**And** the response does NOT leak any row from the DB.

### S6.A — Pagination respects the filter

**Given** seven rows seeded; ListObjects returns ids of five of them; `List(page_size=3)` is called.
**Then** the first page contains 3 of those 5 ids; the `next_page_token` is non-empty; the next call returns the remaining 2 ids; the next-next call returns 0 ids + empty token.
**And** at no point a non-granted id appears in the response.

### S6.B — CI gate `make audit-list-filter` flags an unwired handler

**Given** the repo on the W6 branch with the gate script committed.
**And** a synthetic handler `Bogus.List` is introduced that returns DB rows without consulting `listauthz`.
**When** `make audit-list-filter` runs.
**Then** exit status is non-zero AND the output names `Bogus.List` as missing the filter.
**And** after the synthetic handler is removed, `make audit-list-filter` exits 0.

### S6.C — All-handlers integration matrix passes per repo

**Given** the inventory list of handlers per repo.
**When** the per-repo integration test suite is run.
**Then** every handler has tests S6.x.1..S6.x.4 + S6.A passing.

## Definition of Done

- [ ] Branches `KAC-219-rbac-v2-list-filter` in both `kacho-vpc` and `kacho-compute`.
- [ ] `docs/audit/2026-05-28-list-handlers-{vpc,compute}.md` checked into the workspace repo with the inventory.
- [ ] All four matrix tests + pagination test pass for each handler.
- [ ] `make audit-list-filter` gate added to CI.
- [ ] PRs `PRO-Robotech/kacho-vpc#<N>` and `PRO-Robotech/kacho-compute#<N>` open; CI green.
- [ ] PR URLs added to [[KAC-219]] frontmatter `prs:`.
- [ ] [[KAC-219]] → `In Progress` at PR-open; → `Done` after both merges.
