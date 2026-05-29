# Sub-phase RBAC v2 / W8 — vault refresh + epic close acceptance

**Tracking**: [[KAC-221]] (parent: [[KAC-214]])
**Repo**: `kacho-workspace`
**Design**: `docs/superpowers/specs/2026-05-28-rbac-redesign-and-iam-cleanup-design.md`
**Plan**: `docs/superpowers/plans/2026-05-28-rbac-redesign-and-iam-cleanup-plan.md` Wave 8
**Status**: DRAFT — awaiting acceptance-reviewer

## Scope (in)

- Update `obsidian/kacho/resources/iam-access-binding.md` — add `scope` to field table; KAC-214 link.
- Update `obsidian/kacho/resources/iam-role.md` — note 4-segment grammar; KAC-214 link.
- Update `obsidian/kacho/rpc/iam-authorize-service.md` — note `wildcard_grant`; KAC-214 link.
- Update `obsidian/kacho/edges/vpc-to-iam-listobjects.md` and `compute-to-iam-listobjects.md` — note mandatory wiring + CI gate.
- Mark deprecated (frontmatter `status: deprecated` + body warning callout):
  - `obsidian/kacho/resources/iam-scim-user-mapping.md`
  - `obsidian/kacho/resources/iam-cluster-break-glass-grant.md`
  - `obsidian/kacho/rpc/iam-saml-sp.md`
  - `obsidian/kacho/rpc/iam-scim-v2.md`
  - `obsidian/kacho/edges/iam-to-jackson-saml.md`
  - `obsidian/kacho/edges/iam-to-scim-azure.md`
  - `obsidian/kacho/edges/iam-to-scim-google.md`
  - `obsidian/kacho/edges/iam-to-scim-okta.md`
- Update all wave-KAC notes ([[KAC-215]]..[[KAC-220]]) — frontmatter `prs:` filled with merged PR URLs; `status: done`.
- Update [[KAC-214]] — final PR list comment + `status: done`.
- Close YouTrack epic (`KAC-214` → Done) + subtasks (KAC-215..KAC-221 → Done).

## Scenarios

### S8.1 — Updated vault entries reference KAC-214

**Given** the workspace W8 commits applied.
**When** `grep -l 'KAC-214' obsidian/kacho/{resources,rpc,edges}/iam-access-binding.md` etc.
**Then** the four "updated" vault entries each contain a `KAC-214` link in body or `related_tickets`.

### S8.2 — Deprecated vault entries carry warnings

**Given** the workspace W8 commits applied.
**When** the eight deprecated files are read.
**Then** each frontmatter shows `status: deprecated`.
**And** each body opens with a callout `> [!warning] Removed in [[KAC-214]] (2026-05-28).` (or similar) explaining the removal.

### S8.3 — Each wave-KAC note carries its PR URL

**Given** [[KAC-215]] through [[KAC-220]] vault notes after W8.
**When** the YAML frontmatter `prs:` field is parsed.
**Then** each note has a non-empty `prs:` list pointing to the merged PR(s).
**And** the `status:` field is `done`.

### S8.4 — YouTrack epic + subtasks are closed

**Given** the W8 work merged + YT API queried (`GET /api/issues/KAC-214?fields=resolved,customFields(name,value)`).
**When** the issue is fetched.
**Then** the State field is `Done` for `KAC-214` and for each of `KAC-215..KAC-221`.
**And** the epic body / a comment contains the merged-PR URLs for every wave.

### S8.5 — INDEX/Bases coherent after edits

**Given** the deprecation flags applied in vault.
**When** `obsidian/kacho/resources/all-resources.base` is loaded.
**Then** the table view shows the deprecated rows with the `deprecated` tag (no orphans).
**And** [[INDEX]] still alphabetically lists all current files (kepano discipline).

## Definition of Done

- [ ] Branch `KAC-221-rbac-v2-vault-close` exists in `kacho-workspace`; commits per Plan §Wave 8 tasks 8.1..8.4.
- [ ] All scenarios S8.1..S8.5 verified.
- [ ] PR `PRO-Robotech/kacho-workspace#<N>` open + merged (workspace doc-only PR).
- [ ] PR URL added to [[KAC-221]] frontmatter `prs:`.
- [ ] [[KAC-214]] → `Done` in YouTrack with final comment listing every PR + design + plan path.
- [ ] [[KAC-221]] → `Done`.
