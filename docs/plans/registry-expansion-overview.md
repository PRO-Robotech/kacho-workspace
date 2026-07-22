# Kachō Registry — Expansion Overview (alignment doc)

**Status:** draft · alignment only (APPROVED Given-When-Then acceptance + code follow, per ban #1)
**Scope:** the tenant-facing OCI/artifact-registry surface of `kacho-registry` — namespace
(`Registry`) + repositories/tags/artifacts over a **shared, hidden** registry engine backend,
with peer edges to `kacho-iam` (authz / fga-proxy / JWKS), and (proposed) `kacho-geo` (regional
replication). Control-plane + a thin OCI Distribution data-plane auth-proxy.
**Goal:** a full, maximally-flexible **production** OCI registry — push/pull, signing, scanning,
retention, replication, quotas, webhooks, fine-grained RBAC, public/private/anon — **without ever
exposing the backend** (the tenant sees only `namespace/repo/tag` intent+result; the registry
engine pod / object-store bucket / host / placement / numeric infra-id stay `Internal*` on :9091).

All designs obey Kachō conventions: **flat resource message + async `Operation`** (no Watch),
own-product terms only (**no foreign-cloud / foreign-product names**, ban #2 — we describe
*capabilities*, never vendors), DB-level invariants (ban #10), one-owner-per-type + peer-validate
(data-integrity.md), two-projection isolation + existence-hiding (security.md), no broker — reuse
corelib transactional-outbox (ban #7).

---

## 1. Resource model

Legend — **Proj.** column: `Public` = tenant-facing intent+result on external TLS + REST;
`Internal*` = :9091 admin/scheduler only; `Mixed` = one flat resource with a lean public
projection **plus** a separate `Internal*` full projection carrying infra fields.
`⊘` = immutable after Create · `°` = output-only (source-of-truth = backend engine, or derived).
**Kind:** `DB-policy` = flat, DB-owned, async CRUD→Operation · `Projection` = read-only, engine-
backed, materialized on read · `Internal` = admin/infra, never on external · `Envelope` = LRO.

| Resource | Kind | Prefix | Status | Purpose | Key fields (public unless noted) | Proj. |
|---|---|---|---|---|---|---|
| **Registry** | DB-policy | `reg` | live | Tenant namespace over the shared engine | `id⊘, project_id⊘, created_at, name, description, labels, endpoint°, repository_count°, status{ACTIVE\|DELETING}` **+NEW** `visibility{PRIVATE\|PUBLIC}, default_immutability, default_retention_policy_id, quota_id°`. **Internal-only:** engine namespace, bucket prefix, storage-driver | Mixed |
| **Repository** | Projection **→ DB-config overlay** | — | live→**NEW cfg** | An OCI repo inside a namespace | Read: `registry_id, name, tag_count°, size_bytes°, updated_at°, artifact_type°/artifact_types[]°, last_pulled_at°, download_count°`. **+NEW settable overlay:** `description, labels, visibility, immutability_mode, retention_policy_id, scan_policy_id, signing_policy_id` | Public |
| **Tag** | Projection | — | live | Tagged manifest in a repo | `registry_id, repository, tag, digest°, size_bytes°, media_type°, created_at°, architecture°, last_pulled_at°, pushed_by°, download_count°` **+NEW** `immutable°, signed°, scan_summary°{critical,high,…}` | Public |
| **Artifact / Referrer** | Projection | — | **NEW** | OCI referrer graph (signatures / SBOM / attestations / generic) attached to a subject digest | `registry_id, repository, subject_digest, digest°, artifact_type° (media-type facet), size_bytes°, annotations°, created_at°` | Public |
| **RetentionPolicy** | DB-policy | `rtp` | **NEW** | Declarative lifecycle: keep-N / keep-by-age / tag-glob / untagged-prune, per registry or repo | `id⊘, project_id⊘, created_at, name, labels, scope{REGISTRY\|REPOSITORY}, target_id⊘, rules[]{action,keep_n,max_age,tag_glob,untagged}, schedule, status, last_run°{pruned_count,reclaimed_bytes,run_at}` | Public |
| **TagProtectionRule** | DB-policy | `tpr` | **NEW** | Immutable / write-once + delete-protection by tag-glob | `id⊘, project_id⊘, created_at, repository_target⊘, tag_glob, mode{IMMUTABLE\|PROTECTED}, status`. Enforced data-plane push/delete via DB-CAS | Public |
| **ScanPolicy** | DB-policy | `scp` | **NEW** | Scan-on-push + block-on-severity admission | `id⊘, project_id⊘, created_at, name, scope/target_id, on_push{bool}, block_pull_at_severity{NONE\|LOW…CRITICAL}, grace, status` | Public |
| **ScanResult** | Projection | — | **NEW** | Per-digest vulnerability summary + SBOM pointer (SBOM stored as a referrer artifact) | `registry_id, repository, digest, scanned_at°, severities°{critical,high,medium,low}, findings°[]{id,severity,package,fixed_in}, sbom_ref°, status{PENDING\|SCANNED\|FAILED}`. **Internal-only:** scanner engine id, scan-queue, backend host | Mixed |
| **Scanner** | Internal | `scn` | **NEW** | Admin-registered scan engine backend (blind-draw, AddressPool precedent) | *(no public API)* `id, name, kind, endpoint, enabled, capabilities, feed_updated_at` | Internal* |
| **SigningPolicy (Trust)** | DB-policy | `trp` | **NEW** | Required-signers trust anchor; verify-on-pull admission | `id⊘, project_id⊘, created_at, name, scope/target_id, required_signers[]{key_ref/identity}, enforce{WARN\|BLOCK}, status` | Public |
| **Signature** | Projection | — | **NEW** | Detached signature artifact over a subject digest (referrer-stored) | `registry_id, repository, subject_digest, signer°, created_at°, verified°{bool}` | Public |
| **ReplicationRule** | DB-policy | `rpl` | **NEW** | Namespace↔namespace sync / pull-through mirror; outbox-driven worker | `id⊘, project_id⊘, created_at, name, direction{PUSH\|PULL}, source_target, dest_target, filter{repo_glob,tag_glob}, trigger{ON_PUSH\|SCHEDULED}, status, last_sync°`. **Internal-only:** upstream endpoint, credentials-ref, remote-engine addr, placement | Mixed |
| **Quota** | DB-policy | `quo` | **NEW** | Per-project/registry caps; fail-closed push admission | `id⊘, project_id⊘, scope{PROJECT\|REGISTRY}, target_id, limits{storage_bytes,repository_count,tag_count,pull_rate}, used°{…}(DB-materialized counter, not live walk)` | Mixed |
| **WebhookSubscription** | DB-policy | `whk` | **NEW** | Tenant-facing push/pull/delete/scan/sign event delivery (HMAC-signed) | `id⊘, project_id⊘, created_at, name, scope/target_id, events[]{PUSH,PULL,DELETE,SCAN_DONE,SIGN_FAIL,QUOTA}, endpoint_url, secret(write-only, never echoed), active, last_delivery°{code,at}` | Public |
| **AuditEvent** | Projection | — | **NEW** | Per-tenant audit stream (control-plane + data-plane push/pull/delete/grant/policy) | `registry_id, repository°, tag°, digest°, action, actor, at, result`. Per-repo `v_list` row-filter (existence-hiding). **No infra fields** | Public |
| **ServiceAccount robot — NO new entity, NO token scope** | iam identity | — | **AS-IS** *(RG-D3 RESOLVED)* | Robot = existing `ServiceAccount` + SA-key (identity credential only, unchanged). **DECISION (pure-FGA, 2026-07-15):** authorization is 100% AccessBinding/FGA on the SA — NO RobotToken entity AND NO token-level `scope`/`repo_glob`/`verbs`. To get a narrowly-scoped credential you create a **dedicated SA with narrow grants** (one-SA-one-grant). The only registry-specific addition is granular **pull-only / push-only** roles in the iam FGA model (so an admin can grant a SA less than admin/view) — see functionality. Keeps live-FGA-Check + instant revocation; second scoping layer avoided. | iam-owned |
| **RegistryStats** | Internal | — | live | Infra projection (namespace totals) | *(no public API)* `registry_id, repository_count, tag_count, total_size_bytes, blob_count, last_gc_at` | Internal* |
| **Operation** | Envelope | `epd`(reg) | live | Async LRO envelope for every mutation | `id, description, created_at, done, metadata:Any, oneof result{Status error\|Any response}`. Poll `OperationService.Get`; no Watch | Public |

**Two-projection contract (load-bearing isolation rule):** every `Mixed` row ships a lean public
message (id / name / labels / bindings / tenant intent / `status` / result-counts) **and** a
separate `Internal*` message or `internal-only, unset-in-public` fields carrying engine identity /
upstream endpoint / credentials / scan-backend / bucket / host / numeric-infra-id. Precedent
already live: `RegistryStats` + `TriggerGarbageCollection` are `Internal*`-only; the data-plane
reverse-proxies to the engine but leaks **no** engine identity (fixed OCI error bodies only). A
gateway-level projection audit (analogous to `make audit-list-filter`) should gate that no
additively-added field leaks infra data onto the external surface.

---

## 2. Functionality set (grouped capability checklist)

`[x]` live · `[~]` partial · `[ ]` NEW (expansion target).

**Repo-management**
- `[x]` Registry namespace CRUD (async→Operation), register-on-first-push repo lifecycle, unregister-on-last-tag
- `[~]` Repository as read-only projection → `[ ]` first-class per-repo config overlay (description/labels/visibility/immutability/retention/scan/sign bindings)
- `[ ]` Explicit `DeleteRepository` / `RenameRepository` (async), bulk repo delete
- `[ ]` `ListReferrers` + server-side `artifact_type` facet; per-platform child-manifest listing for multi-arch index

**Push / pull (OCI Distribution)**
- `[x]` `docker push`/`pull`, chunked/mounted blob upload, tags/list, catalog (synthesized, authz-filtered), multi-arch index, Docker v2-schema2 + OCI, register-on-first-push authz materialization
- `[x]` Blob-scope (content-addressable dedup leak guard), push-grant/pending-blob bridges for async materialization window
- `[ ]` OCI manifest/blob `DELETE` via data-plane (today hard-405; deletion only via CP `DeleteTag`) — decide per §5
- `[ ]` `GetManifest`/`GetTag` single-item + delete-by-digest CP RPCs

**Signing + verify**
- `[ ]` `SigningPolicy` (required-signers), signatures as referrer artifacts, verify-on-pull admission gate (WARN/BLOCK) in data-plane, `Signature` projection

**Scanning + SBOM**
- `[ ]` `ScanPolicy` (scan-on-push), async scan trigger (Internal LRO worker), `ScanResult` per-digest projection, SBOM as referrer artifact, block-pull-on-severity admission gate

**Retention / GC / immutability**
- `[x]` On-demand admin `TriggerGarbageCollection` (Internal, unreachable-blob reclaim, `GarbageCollectionResult{blobs_removed,bytes_reclaimed}`)
- `[ ]` `RetentionPolicy` (keep-N / age / tag-glob / untagged-prune) + scheduler + dry-run/preview
- `[ ]` Scheduled/automatic GC policy; `TagProtectionRule` (immutable / write-once / delete-protection) enforced by data-plane push/delete DB-CAS

**Replication / cache**
- `[ ]` `ReplicationRule` (namespace↔namespace push/pull sync), pull-through mirror cache, outbox-driven sync worker (no broker), (proposed) region-pinned via `kacho-geo` edge

**OCI artifacts**
- `[x]` Container image, Helm chart, generic OCI artifact classified (`ArtifactType`)
- `[ ]` First-class `Artifact/Referrer` listing RPC, generic-artifact (config/WASM/ML) projection, artifact-type allow/deny on push

**Quotas**
- `[~]` `RegistryStats` totals (Internal, live walk) → `[ ]` `Quota` (storage-bytes / repo-count / tag-count / pull-rate) with DB-materialized `used` counter + fail-closed push admission (413/quota-exceeded)

**Webhooks / events / audit**
- `[ ]` `WebhookSubscription` (push/pull/delete/scan/sign/quota events), HMAC-signed delivery worker (reuse corelib outbox/drainer)
- `[x]` `ListOperations` (CP mutations, per-repo row-filtered) → `[ ]` `AuditEvent` projection (data-plane push/pull/delete + grant/revoke/policy-change), usage/metering surface

**Fine-grained RBAC**
- `[x]` Per-repo verb-relations (`v_get/v_list/v_create/v_update/v_delete`), robot accounts = SA-keys, label-scoping, listauthz row-filter, existence-hiding
- `[ ]` Registry-specific roles (pull-only vs push-only robot) modeled in iam `fga_model` + permission-catalog
- `[ ]` Optional per-tag / tag-glob authz object · **RG-D3 resolved: pure-FGA, one-SA-one-grant — NO RobotToken, NO token-level scope/repo_glob/verbs; narrow credential = a dedicated SA with narrow grants**

**Public / private / anonymous**
- `[ ]` `visibility{PRIVATE|PUBLIC}` on Registry/Repository + FGA public tuple (`user:*`) + data-plane anonymous `v_get` path gated by the public flag — **without** creating an existence oracle

**Rate limiting** *(cross-cut)*
- `[~]` Static DoS caps (catalog page 1000, fan-out 8, body LimitReaders, JWKS kid-refresh throttle) → `[ ]` per-subject/per-token/per-repo token-bucket + 429, policy-driven, fail-closed

---

## 3. Security & isolation — how each new feature preserves the invariant

The non-negotiable invariant: **backend stays `Internal*`-only; tenant sees only namespace/repo/
tag intent+result; every deny is existence-hiding; every infra field lives in the second
projection.** How each expansion feature holds it:

- **Repository config overlay** — adds only tenant-intent fields (visibility / immutability /
  policy bindings). Counts/size/`artifact_type` stay engine-projected; **no** engine path / blob
  layout leaks. Config CRUD is `v_update@repository`; deny→404 (uniform with missing repo).
- **Signing** — `SigningPolicy` carries *tenant* signer identities (intent); signature bytes live
  as **referrer artifacts in the engine**, projected read-only. Verify-on-pull runs in the
  existing data-plane gate that is **already fail-closed** and emits fixed OCI error bodies — no
  engine identity, no signer-backend host on the wire.
- **Scanning + SBOM** — `ScanResult` is tenant-facing (vuln summary = result of their push);
  the **scanner engine id / scan-queue / backend host are `Internal*`-only** (`Scanner` is an
  Internal admin resource, blind-draw à la `AddressPool`/`NodePool`). Scan runs on an Internal LRO
  worker; SBOM stored as a referrer artifact, projected on read. Block-on-severity gate reuses the
  data-plane deny→404/403 shapes.
- **Retention / GC / immutability** — `RetentionPolicy` shows intent + a **result** (`pruned_count`,
  `reclaimed_bytes`) — never physical blob digests/placement. Scheduled runs are **Internal LRO**;
  immutable/protection enforced by **DB-CAS on the data-plane push/delete path** (ban #10, not
  software check-then-act), so a re-push of a protected tag fails uniformly.
- **Replication / cache** — the **isolation-critical** feature. Public `ReplicationRule` shows only
  intent (mirror which repos, direction, schedule) + result (`last_sync` status). The **upstream
  endpoint, credentials-ref, remote-engine address, placement are `Internal*`-only** (second
  projection / Internal admin config; tenant draws a mirrored repo *blind*, exactly as a tenant
  draws an Address from a hidden pool). Sync is an outbox-driven worker (no broker); any cross-
  registry / cross-region edge is recorded **acyclic** in `polyrepo.md` (e.g. `registry→geo`).
- **Quota** — public `limit` + `used` are pure intent+result. `used` is a **DB-materialized CAS
  counter** (not the Internal live namespace walk that `RegistryStats` does), so enforcement never
  exposes blob-count/host walk. Push admission fails closed (413) without revealing the engine.
- **Webhooks** — event payloads carry **tenant-facing fields only** (repo/tag/digest/actor/action)
  — never engine pod / bucket path / host. HMAC `secret` is **write-only** (never echoed).
  Delivery reuses corelib outbox/drainer (ban #7). Tenant-supplied `endpoint_url` needs egress
  policy (SSRF guard) — see §5.
- **AuditEvent** — same per-repo `v_list` row-filter as `ListOperations` (a namespace-viewer must
  not infer a hidden repo/tag from audit history = existence-oracle bypass). No infra fields.
- **Public / anonymous pull** — the sharpest existence-oracle risk. Anonymous `v_get` is served
  **only** for repos with an explicit `visibility=PUBLIC` + FGA `user:*` tuple; every non-public
  repo still returns the **uniform 404** to anon (public-ness must not become a probe that
  distinguishes "private-exists" from "absent"). The public/anon path reuses the existing deny→404
  read shape; misleading comments about it are banned (security.md hardening-inv #5).
- **Cross-cut (unchanged, applies to all new RPCs):** every new mutation is async→`Operation`
  (no Watch); AuthN+AuthZ on **both** listeners (:9090 public + :9091 internal, internal not
  exempt); per-RPC `InternalIAMService.Check` with `scope_extractor` for object-scoped RPCs
  (anti-BOLA); INTERNAL never echoes `err.Error()` (fixed opaque text); no PII in logs;
  permission-catalog stays generated + byte-identical (CI drift-gate). Admin/infra RPCs
  (`Scanner`, scheduled GC/retention runs, replication upstream config, `RegistryStats`) live
  **only** on `Internal*` :9091, never on the external TLS endpoint (ban #6).

---

## 4. Growth areas

- **Placement / multi-region** — Registry is deliberately **not** placement-scoped today (single
  shared engine). Growth: region-pinned or replicated storage via a `registry→geo` edge
  (`RegionService.Get` peer-validate, fail-closed), regional read-replicas, geo-routing of the
  endpoint — all placement/region fields **Internal-only** per security.md.
- **Backend HA / performance** — multi-replica engine (today single StatefulSet), object-store
  offload on by default, dedupe, edge/P2P distribution cache — all behind the same Internal wall.
- **Supply-chain depth** — attestation/provenance graph over referrers, keyless / transparency-log
  signing (own-product terms), an **admission-policy engine** that composes signing + scanning +
  immutability into one push/pull gate.
- **Artifact breadth** — first-class generic artifacts (config, WASM, ML models, bundles) with
  per-type policy; artifact-type allow/deny lists on push.
- **Metering / billing** — usage surface from `download_count` + materialized storage + pull-rate
  (tenant-facing counters only, engine internals hidden).
- **Vanity / custom domains** — per-tenant registry endpoints beyond `registry.kacho.local/<id>`.
- **Consistency hardening (tracked follow-ups)** — reconciler/sweeper for lost first-push register-
  intent (divergence #9); hard write-fence deny-push-while-DELETING for the delete-vs-push TOCTOU
  (divergence #3); periodic materialization of `RegistryStats`/`Quota` counters instead of the
  O(tags) live walk (divergence #10).

---

## 5. Open design decisions (confirm with owner before acceptance docs)

1. **Repository as DB-config overlay vs pure projection.** Per-repo config (visibility /
   immutability / policy bindings) needs a DB-owned `repository_configs` table keyed by
   `(registry_id, repo)`, which breaks today's "repos exist only via register-on-first-push /
   vanish on last-tag." Confirm: introduce explicit `CreateRepository`/`DeleteRepository`, or keep
   config as a sparse overlay that survives an empty repo? (Affects lifecycle + retention.)
2. **Public repos & anonymous pull — do we want them at all?** If yes: per-repo or per-registry
   `visibility`? Who may flip it (project-admin vs platform-admin)? FGA `user:*` tuple governance +
   the anon-path existence-oracle guard are load-bearing.
3. **Token model — RESOLVED (RG-D3, 2026-07-15): PURE FGA, one-SA-one-grant.** NO `RobotToken` entity
   AND NO token-level scoping (`scope`/`repo_glob`/`verbs`/per-key TTL) on the SA-key. Robot = the
   existing `ServiceAccount`; authorization is 100% AccessBinding/FGA grants on that SA. To scope a
   credential narrowly you create a **dedicated SA with narrow grants** (more SAs, not more layers) —
   simpler model, single authorization layer, live-FGA-Check + instant revocation preserved. The ONLY
   registry-specific RG-5 addition is granular **pull-only / push-only** registry roles in the iam
   `fga_model` + permission-catalog (so an admin can grant a SA less than the broad admin/view). No
   SA-key/token changes; no separate registry issuance surface.
4. **Scan/sign engine — build vs pluggable Internal backend.** Own scanner/signer worker, or an
   Internal `Scanner` adapter (blind-draw)? Default `block_pull_at_severity`? SBOM stored referrer-
   only, or also a projected table? WARN vs BLOCK default for trust.
5. **Replication scope — internal-only vs external upstream.** Kachō-namespace↔namespace sync only,
   or pull-through from arbitrary external upstreams (introduces external egress + credential
   storage + placement/region model via `kacho-geo`)? External upstream widens the isolation
   surface most — confirm appetite.
6. **Retention/GC scheduling — in-service scheduler vs Internal admin-triggered only.** corelib-cron
   scheduler in `kacho-registry`, or keep GC/retention runs admin-triggered on :9091? Dry-run/
   preview required before destructive prune?
7. **Quota ownership + dimensions.** Project-admin-settable (public) or platform-admin-only
   (Internal, like `NodePool`)? Which dimensions ship first (storage-bytes / repo-count / tag-count
   / pull-rate)? Enforcement point (push-admission only, or also pull-rate)?
8. **Webhook egress safety.** Allow arbitrary tenant `endpoint_url` (SSRF/egress risk → needs
   allow-list / egress policy), or restrict to vetted destinations? HMAC-only or also mTLS delivery?
9. **Per-tag RBAC — needed or over-engineering?** Is per-repo authz sufficient, or is genuine
   tag-level isolation required (adds an FGA object per tag/glob — cardinality cost)?
10. **Data-plane OCI `DELETE` completeness.** Keep the hard-405 (deletion only via CP `DeleteTag`),
    or implement spec-compliant manifest/blob DELETE (with its own authz + immutability
    interaction)? Affects OCI-conformance claims.
11. **Registry-role modeling location.** Pull-only vs push-only robot roles must be modeled in
    iam's canonical `fga_model` + permission-catalog (not in `kacho-registry`) — confirm the iam
    epic ordering (proto→corelib→iam→registry→gateway) for the RBAC expansion.
