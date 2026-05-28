# Sub-phase RBAC v2 / W7 — kacho-deploy acceptance

**Tracking**: [[KAC-220]] (parent: [[KAC-214]])
**Repo**: `kacho-deploy`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md` §3.6
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 7
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- Drop `breakGlass.*`, `scim.*`, `saml.*` from `helm/kacho-iam/values.yaml` (+ any per-env override files).
- Drop FGA bootstrap-job tuples writing `emergency_admin`, `break_glass_window` (typically in `helm/openfga/templates/bootstrap-job.yaml` or `kacho-iam-fga-seed.yaml`).
- Remove any jackson-saml Deployment / ConfigMap if present.
- Delete newman cases for SCIM/SAML/BG (`tests/newman/cases/iam-scim-*.py`, `iam-saml-*.py`, `iam-break-glass-*.py`); regen newman collections.
- Add newman list-filter regression matrix per (service × resource) cell.
- `make dev-up && make newman-iam-list-filter` green.

## Scope (out)

- No proto / Go code changes.
- No vault changes ([[KAC-221]]).

## Scenarios

### S7.1 — Helm template renders zero SCIM/SAML/BG strings

**Given** the W7 branch.
**When** `helm template kacho-iam helm/kacho-iam | grep -i 'breakGlass\\|scim\\|saml\\|emergency_admin\\|break_glass_window'` is run.
**Then** zero matches.
**And** the same is true for `helm template openfga helm/openfga` (or wherever FGA bootstrap is templated).

### S7.2 — Deploy succeeds end-to-end without removed artifacts

**Given** the W7 branch.
**When** `make dev-up` runs on a fresh kind cluster.
**Then** all kacho-* pods reach Ready within the standard timeout.
**And** `kubectl get pods -n kacho` shows no pods named `*saml*`, `*scim*`, `*jackson*`, `*break-glass*`.

### S7.3 — newman SCIM/SAML/BG cases are gone

**Given** the regenerated newman collections.
**When** `find tests/newman/collections -name '*.json' | xargs jq '.item[].name' | grep -i 'scim\\|saml\\|break.glass'`.
**Then** zero matches.

### S7.4 — newman list-filter regression matrix is GREEN

**Given** the W7 branch with new list-filter newman cases.
**And** the dev-stack is fresh.
**When** the seed script creates two compute Instances (`inst-A`, `inst-B`), two VPC Networks (`net-A`, `net-B`), two IAM Projects (`prj-A`, `prj-B`) under one Account.
**And** a test subject is granted `compute.instance.inst-A.read`, `vpc.network.net-A.read`, `iam.project.prj-A.read` scoped to that Account.
**When** newman runs the list-filter suite.
**Then** the response of `GET /compute/v1/instances` contains exactly `inst-A`; `GET /vpc/v1/networks` contains exactly `net-A`; `GET /iam/v1/projects` contains exactly `prj-A`.
**And** the system_admin subject sees all six rows in the three lists.
**And** an anonymous subject sees Unauthenticated; an authenticated-no-grants subject sees empty lists (OK status).

### S7.5 — Helm + newman together stable across a full `make dev-up && newman`

**Given** the W7 branch + W2..W6 merged.
**When** `make dev-up && make newman-iam-list-filter && make newman-iam-rbac` is run.
**Then** all suites green; no test skipped; no test in the `// verifies <issue>` red-list.

## Definition of Done

- [ ] Branch `KAC-220-rbac-v2-deploy` exists; commits per Plan §Wave 7 tasks 7.1..7.4.
- [ ] All scenarios S7.1..S7.5 verified locally on dev-stack.
- [ ] PR `PRO-Robotech/kacho-deploy#<N>` open; CI green.
- [ ] PR URL added to [[KAC-220]] frontmatter `prs:`.
- [ ] [[KAC-220]] → `In Progress` at PR-open; → `Done` after merge.
