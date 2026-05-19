# Sub-phase 3.6 — IAM Enterprise SSO: SCIM 2.0 + SAML bridge + Organization tier (KAC-127 / YT KAC-123) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: [KAC-123](https://prorobotech.youtrack.cloud/issue/KAC-123) — production-ready next-gen IAM (vault-label `KAC-127`).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` §3 «Identity Model (Organization tier)», §13 «Production deployment + observability», §4 «OpenFGA Authorization Model v2» (types `organization`, `account#admin or admin from organization`), §16 «Migration plan / Phase 6».
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — Phase 6 (tasks 6.1-6.7).
> **Phase position**: **Phase 6 of 13** (production edition, NOT MVP).
> **Predecessors (must be merged before Phase 6 code begins)**:
> - **Phase 1 — Foundation** (`sub-phase-3.1-iam-foundation-acceptance.md`): миграции `0011..0014` уже создали таблицы `organizations` (B2B optional tier с domain-claim + SCIM/SAML config) и `scim_user_mappings` (`(organization_id, scim_external_id)` → `user_id` UNIQUE) — Phase 6 пишет в эти таблицы, **не** добавляет их.
> - **Phase 2 — AuthN core** (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`): ORY Kratos session lifecycle, Hydra OIDC token issuance, Kratos OIDC connector wired в config (Jackson выглядит для Kratos как обычный upstream OIDC provider). Webhook hook `post_oidc_registration` уже доступен (используется в JIT для SAML).
> - **Phase 3 — AuthZ core** (`sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`): OpenFGA Authorization Model v2 содержит тип `organization` со связями `owner`, `admin`, `editor`, `viewer`, `billing_admin`, `scim_admin`; cascade `account#admin or admin from organization`. Phase 6 пишет tuples `organization:org_xxx#scim_admin@service_account:sva_scim_xxx` (для SCIM bearer-token subject).
> - **Phase 4 — List filtering** (`sub-phase-3.4-iam-list-filtering-acceptance.md`): `corelib/authz.ListAllowedIDs` готов; `OrganizationService.List` использует ListObjects для cluster-admin sees-all + per-org-admin sees-own.
> - **Phase 5 — Federation Exchange** (`sub-phase-3.5-iam-federation-acceptance.md`, ожидается смержен): `service_account_oauth_clients` row + Hydra static clients pattern переиспользуется Phase 6 для SCIM bearer-token issue (см. §3 P6-D9). НЕ блокер для acceptance-doc — блокер для merge implementation.
> - **KAC-125 baseline** (`sub-phase-2.0-iam-KAC-125-user-invite-flow-acceptance.md`): User per-Account модель (один Kratos identity → N user-rows); Phase 6 расширяет на SCIM-imported per-Org rows.
> **Target repos / merge order (топологическая сортировка graph'а)**:
> 1. `PRO-Robotech/kacho-proto` — `proto/kacho/cloud/iam/v1/organization.proto` (public `Organization` message + `OrganizationService` RPC: `Create/Update/Delete/Get/List/VerifyDomain/IssueSCIMToken/RevokeSCIMToken/UploadSAMLMetadata/RevokeSAMLConfig` — все мутации async через `operation.Operation`), `proto/kacho/cloud/iam/v1/scim_v2.proto` (HTTP-only типы для SCIM endpoints; не gRPC — RFC 7644 диктует REST), `proto/kacho/cloud/iam/v1/saml.proto` (internal `InternalSAMLService` для JIT provisioning callback from Kratos webhook), `proto/kacho/cloud/iam/v1/internal_organization.proto` (`InternalOrganizationService` для admin-UI: `BindAccount`, `UnbindAccount`, `ListAccounts`, `ListPendingDomains`); `buf lint`/`buf breaking` зелёные; `gen/go/...` regenerated and committed.
> 2. `PRO-Robotech/kacho-corelib` — `scim/parser.go` (SCIM filter expression parser per RFC 7644 §3.4.2: `eq/ne/co/sw/ew/gt/ge/lt/le/pr/and/or/not`), `scim/sort.go` (RFC 7644 §3.4.2.3 sort), `scim/pagination.go` (RFC 7644 §3.4.2.4 startIndex+count), `scim/errors.go` (RFC 7644 §3.12 error format with `scimType`), `scim/response.go` (JSON-ld helper с `schemas: ["urn:ietf:params:scim:api:messages:2.0:ListResponse"]`); `dns/txt_resolver.go` (interface + default `net.LookupTXT` impl + mock for tests); integration tests `scim_parser_test.go` (50+ test cases against RFC 7644 §3.4.2 grammar).
> 3. `PRO-Robotech/kacho-iam` — `internal/migrations/0017_kac127_phase6_org_scim_saml.sql` (новые колонки на `organizations`: `domain_claim TEXT NULL UNIQUE`, `domain_verification_state TEXT DEFAULT 'unverified'`, `domain_verification_token TEXT NULL`, `domain_verification_started_at TIMESTAMPTZ NULL`, `domain_verified_at TIMESTAMPTZ NULL`, `default_account_id TEXT NULL REFERENCES accounts(id) ON DELETE RESTRICT`, `saml_metadata_xml TEXT NULL`, `saml_metadata_uploaded_at TIMESTAMPTZ NULL`, `saml_acs_url TEXT NULL`, `saml_entity_id TEXT NULL`, `initial_role_id TEXT NULL REFERENCES roles(id) ON DELETE RESTRICT`, `scim_token_hash BYTEA NULL`, `scim_token_issued_at TIMESTAMPTZ NULL`, `scim_token_revoked_at TIMESTAMPTZ NULL`; новая таблица `organization_domain_proofs` (history of TXT verifications для audit); расширения на `scim_user_mappings`: добавить `scim_active BOOLEAN DEFAULT true`, `scim_meta_resource_type TEXT`, `scim_meta_version TEXT`, `last_scim_sync_at TIMESTAMPTZ`); `internal/apps/kacho/api/organization/` (handlers — `create.go`, `update.go`, `delete.go`, `get.go`, `list.go`, `start_domain_verification.go`, `verify_domain.go`, `revoke_domain_verification.go`, `upload_saml_metadata.go`, `revoke_saml_config.go`, `issue_scim_token.go`, `revoke_scim_token.go`); `internal/apps/kacho/api/scim/` (HTTP handlers; mounted на REST mux под `/scim/v2/` префиксом — `users.go`, `groups.go`, `bulk.go`, `me.go`, `resource_types.go`, `schemas.go`, `service_provider_config.go`); `internal/apps/kacho/api/saml/jit_provision.go` (internal RPC handler, вызывается Kratos webhook'ом после успешного SAML signin); `internal/apps/kacho/auth/scim_bearer_authn.go` (HTTP middleware — извлекает Bearer, hash-compare против `organizations.scim_token_hash`, resolve в `scim_admin` principal scoped к organization_id); `internal/repo/kacho/pg/organization_phase6_repo.go` + `scim_user_mappings_phase6_repo.go` + `organization_domain_proofs_repo.go`; integration tests (testcontainers Postgres + mock DNS resolver) — `organization_phase6_integration_test.go`, `scim_users_integration_test.go`, `scim_groups_integration_test.go`, `scim_bulk_integration_test.go`, `saml_jit_integration_test.go`, `scim_bearer_authn_integration_test.go`, `domain_verification_integration_test.go`, `scim_filter_concurrency_integration_test.go`.
> 4. `PRO-Robotech/kacho-deploy` — `helm/umbrella/templates/jackson-deployment.yaml` (2× HA replicas; Postgres-backed; SAML metadata storage delegated to Jackson DB), `helm/umbrella/templates/jackson-service.yaml`, `helm/umbrella/templates/jackson-ingress.yaml` (path `/api/oauth/saml` + `/api/oauth/saml/sp`), `helm/umbrella/values.dev.yaml` + `values.prod.yaml` (jackson block: image `boxyhq/jackson:latest`, env `JACKSON_API_KEYS=<sealed-secret>`, `DB_URL=postgres://...kacho_jackson_dev`, `IDP_ENABLED=true`, `IDP_DISCOVERY_PATH=/well-known/saml-configuration`, `OIDC_DISCOVERY_PATH=/.well-known/openid-configuration`, `OPENID_RP_SIGNING_ALG=RS256`); Postgres init for `kacho_jackson` DB; ServiceMonitor для Jackson metrics; Kratos OIDC connector config (`kratos_jackson` provider type=generic OIDC, issuer=Jackson URL + `?tenant=<org_id>`); api-gateway REST mux обновление — `/scim/v2/*` → kacho-iam HTTP port; SealedSecret для Kratos OIDC client_secret к Jackson; Cloudflare WAF rule allow `/scim/v2/*` от vendor IP ranges (Okta/Azure).
> 5. `PRO-Robotech/kacho-api-gateway` — `internal/restmux/scim_v2_mount.go` (proxy SCIM endpoints к kacho-iam:9080 — public on TLS endpoint `api.kacho.cloud`; **не** через grpc-gateway transcoding потому что SCIM JSON format — RFC 7644-specific, не protobuf transcoding); `internal/restmux/organization_mount.go` (registers public OrganizationService RPC + internal mounts InternalOrganizationService на `:9091`); `internal/auth/scim_bypass_middleware.go` (для путей `/scim/v2/*` пропускает Hydra-JWT-validation; SCIM bearer-token validation — внутри kacho-iam, см. §5 P6-D9).
> 6. `PRO-Robotech/kacho-ui` — `src/pages/iam/organizations/OrgListPage.tsx`, `OrgDetailPage.tsx`, `OrgSSOConfigPage.tsx` (SAML metadata XML drag-drop + parse + display SP-init URL + ACS URL + entity-id), `DomainVerificationPage.tsx` (DNS-TXT challenge UI: «add this TXT record then click verify»), `SCIMTokenPage.tsx` (issue + show-once + rotate + revoke; clipboard copy; show last-rotated-at + token-fingerprint), `src/hooks/useOrgSSO.ts`, `src/api/iam/organization.ts` (regenerated from proto-gen).
> 7. `PRO-Robotech/kacho-test` — `tests/newman/cases/iam_organization_phase6.py` + `iam_scim_phase6.py` + `iam_saml_phase6.py` + `iam_scim_cross_org_isolation_phase6.py` (15+ cases each); `k6/scim_load_kac127_phase6.js` (SCIM bulk RPS sustained 30min, p95 ≤200ms per RFC 7644 implementation note); `tests/playwright/iam_org_admin_flows.spec.ts` (E2E happy path); `tests/integration/saml_okta_sandbox.spec.ts` (real Okta sandbox SAML SP-init); k6/results/KAC-127-phase6-scim.md + `KAC-127-phase6-saml.md` artifacts.
> 8. `PRO-Robotech/kacho-workspace` — vault: `obsidian/kacho/KAC/KAC-127.md` (update Phase 6 trail), `obsidian/kacho/resources/iam-organization.md` (extend with domain-claim + SCIM/SAML fields), `obsidian/kacho/resources/iam-scim-user-mapping.md` (new), `obsidian/kacho/resources/iam-organization-domain-proof.md` (new), `obsidian/kacho/rpc/iam-organization-service.md` (new), `obsidian/kacho/rpc/iam-scim-v2-service.md` (new — HTTP-only «service», not gRPC), `obsidian/kacho/rpc/iam-internal-saml-service.md` (new), `obsidian/kacho/edges/iam-to-jackson-saml.md` (new), `obsidian/kacho/edges/iam-to-scim-okta.md`, `iam-to-scim-azure.md`, `iam-to-scim-google.md` (3 new edges), `obsidian/kacho/edges/kratos-to-jackson-oidc.md` (new), `obsidian/kacho/packages/iam-apps-scim.md`, `iam-apps-saml.md`, `iam-apps-organization.md` (3 new packages), `obsidian/kacho/packages/corelib-scim.md` (new), `obsidian/kacho/architecture/enterprise-sso-pipeline.md` (new — SP-init + IdP-init + JIT diagrams).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 6 — **шестая code-emitting Phase** под KAC-127. К моменту начала Phase 6 уже есть:

1. **DB-foundation** (Phase 1): таблицы `organizations` (минимальная — id/name/display_name/description/created_at — Phase 6 добавляет domain-claim + SCIM/SAML колонки в `0017`), `scim_user_mappings` (`(organization_id, scim_external_id)` UNIQUE → `user_id` — Phase 6 расширяет meta-колонками + active flag), `roles` multi-scope (Phase 6 использует `organization_id`-scoped roles как `initial_role_id` для JIT).
2. **AuthN plane** (Phase 2): Kratos + Hydra DPoP-bound JWT, Kratos OIDC connector framework готов (Jackson подключается как «yet another generic OIDC provider» для Kratos — это design D-10).
3. **AuthZ plane** (Phase 3): OpenFGA модель v2 с типом `organization` и его cascade (`account#admin or admin from organization`). Phase 6 **пишет tuples**: `organization:<org_id>#scim_admin@service_account:<sva_scim_id>` (per-org SCIM bearer-token subject — service_account row); `organization:<org_id>#owner@user:<user_id>` (first creator).
4. **ListFiltering** (Phase 4): `OrganizationService.List` использует ListObjects API.
5. **Federation Exchange** (Phase 5): паттерн «service_account + oauth_client + token-issuance» переиспользуется Phase 6 для SCIM bearer-token. **Но**: SCIM token — не Hydra OAuth token (RFC 7644 предполагает opaque Bearer); Phase 6 хранит SHA-256 hash в `organizations.scim_token_hash` и валидирует HTTP middleware'ом до того как запрос попадёт в SCIM-handler.

**Что Phase 6 принципиально добавляет**:

- **Organization tier — full B2B integration**. Раньше (Phase 1) `organizations` таблица была skeleton с пустыми колонками для SCIM/SAML config. Phase 6 заполняет: domain claim (verified DNS-TXT), SAML metadata-XML upload + parse, SCIM bearer-token issue/revoke/rotate, default_account_id для JIT provisioning, initial_role_id для post-JIT role assignment.
- **SCIM 2.0 RFC 7644 strict compliance**. Полный `/scim/v2/Users` + `/Groups` + `/Bulk` + `/Me` + `/ResourceTypes` + `/Schemas` + `/ServiceProviderConfig`. Filter parser (eq/ne/co/sw/ew/gt/ge/lt/le/pr/and/or/not) — handwritten в `corelib/scim/parser.go` (нет надёжной OSS Go-библиотеки для SCIM filter parsing на 2026-05). Tested via Okta + Azure AD + Google Workspace sandboxes — RFC conformance.
- **SAML 2.0 via Boxyhq Jackson** (open-source SAML→OIDC bridge). Kachō внутри **consumes only OIDC** — это design D-10 (ORY Kratos OSS не имеет native SAML; Jackson — open-source self-hosted bridge). Sequence: customer admin uploads SAML metadata-XML → Jackson stores it + exposes `/api/oauth/authorize?tenant=<org_id>&product=kacho` → Kratos OIDC connector points к Jackson → SAML SP-init/IdP-init работают transparent для Kratos. Jackson sits в кластере (2+ HA replicas, Postgres-backed).
- **JIT provisioning без pre-SCIM**. Если customer не имеет SCIM-provisioning настроенным, но user уже есть в их IdP — first SAML signin создаёт User row автоматически: Kratos `post_oidc_registration` webhook hits `InternalSAMLService.JITProvision` → resolves Organization by email domain → creates User row в `default_account_id` org'а → assigns `initial_role_id` (configurable per Org) → emits FGA Write `account:<default>#viewer@user:<user_id>` → emits CAEP outbox event `users.provisioned`. **Idempotent**: повторный signin того же user НЕ создаёт дубль (Kratos identity reused; SCIM mapping if applicable).
- **Per-organization scoping и cross-org isolation**. SCIM bearer-token А **не может** оперировать на user'ах Org B (даже если знает их id). `scim_user_mappings` имеет UNIQUE `(organization_id, scim_external_id)` — `externalId` "alice@acme.com" в Org A — это **другой** mapping чем "alice@acme.com" в Org B. SCIM-handler авторизуется по `organizations.id` extracted из token-hash lookup; любая операция верифицирует `target.user.account.organization_id == authenticated_org_id` (DB-level CHECK в queries + service-layer assertion + integration test §6.3.7).
- **SCIM lifecycle webhooks cascade**. `DELETE /scim/v2/Users/{id}` → SCIM-handler **не** удаляет физически (soft-delete) → `users.status = BLOCKED` → cascade `access_bindings` set `status = REVOKED` → FGA outbox emits per-tuple deletion → CAEP outbox emits `users.deactivated` event (Phase 8 picks up и push'ит к registered subscribers); SCIM caller получает `204 No Content`. Restore возможен через POST с тем же `externalId` (UNIQUE constraint matches → resurrect).
- **SAML cert rotation**. Customer IdP updates cert → admin re-uploads metadata XML → kacho-iam parses new cert + replaces `organizations.saml_metadata_xml` → grace period 24h (старый cert тоже принимается) → старый cert окончательно отвергается. (Grace mechanism — Jackson-internal; kacho-iam триггерит Jackson metadata refresh через Jackson Admin API.)
- **Multi-org user**. User может иметь identity в нескольких Org'ах (одна Kratos identity → N user-rows). Phase 6 поддерживает: SCIM `POST /scim/v2/Users` в Org A для existing Kratos user → создаёт **новый** user-row в `Account` of Org A + adds `scim_user_mappings` row → НЕ перезаписывает identity. Same user может independently SCIM'иться в Org B (отдельный mapping). См. §6.9 / GWT 6.9.4.

**Phase 6 НЕ включает** (это Phases 7-13 одного и того же epic'а — НЕ "deferred"):

- ListObjects integration в новых RPC (`OrganizationService.List` всё ещё проходит через corelib/authz `ListAllowedIDs` — `cluster_admin` sees all; per-org admin sees only own org; tenant без org-binding sees none) — паттерн **уже работает** с Phase 4, Phase 6 просто использует.
- JIT/PIM activation flow (`ActivateJIT` RPC, 2-person break-glass approval) — **Phase 7**.
- CAEP push pipeline (drainer, SET signing, subscriber registry) — **Phase 8**. Phase 6 пишет CAEP outbox-rows на `users.provisioned`, `users.deactivated`, `groups.member_added`, `groups.member_removed`, `organization.scim_token_rotated` — **drainer / consumer / external delivery** — Phase 8 (forward-compatible).
- Full audit pipeline (Kafka + ClickHouse + S3 + HSM + Merkle) — **Phase 9**. Phase 6 пишет `audit_outbox` row на каждую SCIM / SAML / Org-mutation; drainer Phase 9 picks up.
- SPIFFE/SPIRE + Cilium mesh — **Phase 10**.
- Multi-region active-active for Jackson + multi-region SCIM endpoint — **Phase 11** (Phase 6 — single region; Phase 11 расширяет).
- OWASP ASVS L3 + SAML fuzzing + Okta/Azure SCIM-conformance external pentest — **Phase 12**.
- Vault closeout (30+ files) — **Phase 13**.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace `CLAUDE.md`) — кодирование только после `acceptance-reviewer` APPROVED | Этот документ — gate; статус остаётся `DRAFT` до APPROVED. |
| **Запрет #2** — НЕ упоминать "yandex" | В коде / proto / Go-имена / env-name / commit-messages / k6-scenarios / SCIM-payloads не упоминается. YC-стилистика error-text (`Organization '<id>' not found`, `<field> is immutable after Organization.Create`) — остаётся для kacho-side; SCIM errors следуют RFC 7644 §3.12 format (`detail`, `status`, `scimType`, `schemas`). |
| **Запрет #3** — НЕ ORM | SCIM filter parser — handwritten state-machine (`corelib/scim/parser.go`); repo-layer — handwritten pgx + sqlc; Jackson — third-party (Postgres-backed, но это his own DB `kacho_jackson_dev`, не kacho-iam). |
| **Запрет #4** — НЕ каскад через границу сервиса | SCIM DELETE → cascade `access_bindings.status=REVOKED` + FGA outbox + CAEP outbox — всё внутри **kacho-iam DB** (одна schema; allowed FK + same-TX writes). Cross-service эффекты (vpc/compute видят deactivated user → теряют access) — реактивны через FGA tuple removal + LISTEN-invalidate (Phase 4 механика); это **не** cross-DB FK cascade. Org `DELETE` — пресекается FK `accounts_organization_fk ON DELETE RESTRICT` (если есть accounts) — operator должен сам unbind/delete accounts. |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 1 миграции `0011..0014` НЕ редактируются. Phase 6 добавляет **новую** миграцию `0017_kac127_phase6_org_scim_saml.sql` в kacho-iam (extend `organizations` + extend `scim_user_mappings` + new `organization_domain_proofs`). Если в реализации выявится missing column / index — **открывается новая** `0018_...`, не правка `0017`. |
| **Запрет #6** — `Internal.*` НЕ на external endpoint | `InternalOrganizationService` (`BindAccount`, `UnbindAccount`, `ListAccounts`, `ListPendingDomains`) и `InternalSAMLService.JITProvision` — Internal-only; регистрируются через `restmux.RegisterInternal()` на cluster-internal listener `:9091`. **НЕ** доступны на `api.kacho.cloud:443`. SCIM endpoint `/scim/v2/*` — **public** на external endpoint (это требование RFC 7644 для inbound provisioning от Okta/Azure/Google), но защищён per-Org SCIM bearer-token (НЕ Hydra JWT; см. §5 P6-D9). |
| **Запрет #7** — НЕ broker | Jackson — это OIDC bridge (HTTP/REST), не broker. SCIM lifecycle webhooks → CAEP outbox row (Postgres NOTIFY) — Phase 6 не запускает Kafka. Drainer / consumer / external SET delivery — Phase 8 (когда выстроим Kafka). |
| **Запрет #8** — DB-per-service | kacho-iam владеет `organizations`, `scim_user_mappings`, `organization_domain_proofs`, `users`, `accounts`, `roles`, `access_bindings`; Jackson владеет **своей** DB `kacho_jackson` (отдельный logical DB на том же Postgres-кластере — но logically separate; никаких cross-DB FK). Communication kacho-iam ↔ Jackson — только HTTP API (Jackson Admin API для metadata-upload + Kratos OIDC connector для signin). |
| **Запрет #9** — async-only мутации | `OrganizationService.Create/Update/Delete/StartDomainVerification/VerifyDomain/UploadSAMLMetadata/IssueSCIMToken/RevokeSCIMToken/RevokeSAMLConfig/RevokeDomainVerification` — все возвращают `operation.Operation` (long-running async); клиент поллит `OperationService.Get(id)`. SCIM `/scim/v2/*` — **синхронный** (RFC 7644 жёстко требует sync 200/201/204/409 etc.; нет Operations envelope). Это — единственное по-design исключение от запрета #9; обосновано RFC 7644 §3.7 «implementations MUST return appropriate HTTP status codes»; SCIM не Kachō-API, а internet standard. |
| **Запрет #10** — within-service refs на DB-уровне | `scim_user_mappings.user_id → users.id ON DELETE CASCADE` (SCIM mapping умирает с user); `scim_user_mappings.organization_id → organizations.id ON DELETE RESTRICT`; `organizations.default_account_id → accounts.id ON DELETE RESTRICT` (Org нельзя удалить если есть accounts; default_account нельзя удалить если ссылается Org). `organization_domain_proofs.organization_id → organizations.id ON DELETE CASCADE` (history dies с org'ом). SCIM externalId uniqueness — `UNIQUE (organization_id, scim_external_id)` (partial UNIQUE — `WHERE scim_active = true` для resurrect-restore паттерна). SCIM `PATCH /Users` со «replace name» — атомарный single-statement `UPDATE users SET ... WHERE id=$1` (single-row CAS не нужен — RFC 7644 PATCH семантика last-writer-wins; SCIM ETag/If-Match для OCC — out-of-scope этого Phase, future improvement). |
| **Запрет #11** — тесты в том же PR | Каждый PR Phase 6 содержит: kacho-corelib — unit `scim/parser_test.go` (50+ filter expressions), `scim/pagination_test.go`, `scim/sort_test.go`; kacho-iam — integration `organization_phase6_integration_test.go`, `scim_users_integration_test.go`, `scim_groups_integration_test.go`, `scim_bulk_integration_test.go`, `domain_verification_integration_test.go`, `saml_jit_integration_test.go`, `scim_bearer_authn_integration_test.go`, **`scim_filter_concurrency_integration_test.go`** (concurrent SCIM POST same `externalId` — verify ровно одна транзакция выигрывает, остальные получают `409 Conflict`); kacho-test — newman cases (`iam_organization_phase6.py`, `iam_scim_phase6.py`, `iam_saml_phase6.py`, `iam_scim_cross_org_isolation_phase6.py`) + k6 SLA + Playwright E2E. Все «happy + ≥1 negative» в одном PR. |

> **Дополнительное правило Phase 6 — backward-compat НЕ требуется** (user feedback round 2, 2026-05-19). Если paradigm `Organization` существовал в Phase 1 как skeleton-только-с-id-name — Phase 6 свободно расширяет (`0017` миграция добавляет много колонок без backfill потому что таблица пуста; первый Org создаётся уже с новой схемой). SCIM endpoint — новый; нет old endpoint для совместимости. SAML — новый; backwards-compat irrelevant.

---

## 2. Глоссарий / доменная модель Phase 6 (нормативно)

### 2.1 Сущности и API, **используемые** в Phase 6 (от Phase 1/2/3/4/5 — read-only здесь)

- **`organizations` table** (Phase 1 created; Phase 6 extends). Phase 1 columns: `id` (`org_<20hex>`), `name` (UNIQUE), `display_name`, `description`, `created_at`. Phase 6 ALTER adds 13 columns (см. §1 «target repos / merge order», step 3) + new partial UNIQUE indexes.
- **`scim_user_mappings` table** (Phase 1 created skeleton; Phase 6 extends + actively writes). Phase 1 columns: `id`, `organization_id`, `scim_external_id`, `user_id`, UNIQUE(`organization_id`, `scim_external_id`), `created_at`. Phase 6 ALTER adds `scim_active`, `scim_meta_resource_type`, `scim_meta_version`, `last_scim_sync_at`; rewrites UNIQUE как partial `(organization_id, scim_external_id) WHERE scim_active = true` (для resurrect).
- **`accounts` table** (KAC-124 existing; Phase 1 added `organization_id` NULL FK). Phase 6 не меняет structure, но `Organization.default_account_id → accounts.id` ссылается; bind/unbind через `InternalOrganizationService`.
- **`users` table** (KAC-125 existing). Phase 6 пишет в неё через JIT: `INSERT ... ON CONFLICT (kratos_identity_id, account_id) DO NOTHING RETURNING *`.
- **`roles` table** (Phase 1 multi-scope). Phase 6 ссылается через `Organization.initial_role_id` — должна быть role с `account_id = NOT NULL AND project_id IS NULL` (account-scoped) **OR** `organization_id = <self> AND ...` (org-scoped). CHECK на ALTER в `0017` enforces.
- **`access_bindings` table** (Phase 3 existing). Phase 6 пишет через JIT (создаёт `account:<default>#viewer@user:<user_id>` row) и через SCIM DELETE cascade (set `status = REVOKED`).
- **`audit_outbox` + `caep_outbox`** (Phase 1 created; drainer — Phase 8/9 forward-compatible). Phase 6 пишет rows in-TX.
- **Boxyhq Jackson** (third-party, deployed in Phase 6 step 4 — kacho-deploy). API: Admin API `/api/v1/sso/connections` для metadata-upload; OIDC discovery `/.well-known/openid-configuration?tenant=<org_id>`; SAML ACS endpoint `/api/oauth/saml`. Database `kacho_jackson` — Jackson-owned, kacho-iam **не** трогает Jackson schema.
- **ORY Kratos** (Phase 2 deployed). OIDC connector pointing к Jackson (`kacho_jackson_provider` в Kratos config; `provider_id` derived from Organization). Webhook `post_oidc_registration` calls kacho-iam `InternalSAMLService.JITProvision` (Phase 6 new).
- **OpenFGA Authorization Model v2** (Phase 3 deployed). Phase 6 пишет tuples: `organization:<org_id>#scim_admin@service_account:<sva_id>` (на SCIM-token issue); `organization:<org_id>#owner@user:<creator_id>` (на Org create); `account:<default_acc_id>#viewer@user:<jit_user_id>` (на JIT provision).
- **`corelib/authz.ListAllowedIDs`** (Phase 4 deployed). `OrganizationService.List` использует с `objectType=organization`, `relation=viewer`. Cluster-admin sees all; per-org admin sees only own; non-org-bound user sees none.

### 2.2 Сущности, **добавляемые** в Phase 6

#### 2.2.1 DB-changes (kacho-iam migration `0017_kac127_phase6_org_scim_saml.sql`)

**`organizations` ALTER** (extend Phase 1 skeleton):

```sql
ALTER TABLE kacho_iam.organizations
  ADD COLUMN domain_claim TEXT NULL,
  ADD COLUMN domain_verification_state TEXT NOT NULL DEFAULT 'unverified'
       CHECK (domain_verification_state IN ('unverified','pending','verified','revoked')),
  ADD COLUMN domain_verification_token TEXT NULL,
  ADD COLUMN domain_verification_started_at TIMESTAMPTZ NULL,
  ADD COLUMN domain_verified_at TIMESTAMPTZ NULL,
  ADD COLUMN default_account_id TEXT NULL REFERENCES kacho_iam.accounts(id) ON DELETE RESTRICT,
  ADD COLUMN saml_metadata_xml TEXT NULL,
  ADD COLUMN saml_metadata_uploaded_at TIMESTAMPTZ NULL,
  ADD COLUMN saml_acs_url TEXT NULL,
  ADD COLUMN saml_entity_id TEXT NULL,
  ADD COLUMN initial_role_id TEXT NULL REFERENCES kacho_iam.roles(id) ON DELETE RESTRICT,
  ADD COLUMN scim_token_hash BYTEA NULL,
  ADD COLUMN scim_token_issued_at TIMESTAMPTZ NULL,
  ADD COLUMN scim_token_revoked_at TIMESTAMPTZ NULL,
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- domain_claim уникален когда state ∈ {pending, verified} (revoked может быть повторно claimed
-- если challenge token regenerated; unverified — пустое значение):
CREATE UNIQUE INDEX organizations_domain_claim_uniq
  ON kacho_iam.organizations (domain_claim)
  WHERE domain_claim IS NOT NULL AND domain_verification_state IN ('pending','verified');

-- scim_token_hash уникален per organization (один active token per Org одновременно;
-- rotate revoke'ит старый):
CREATE UNIQUE INDEX organizations_scim_token_hash_uniq
  ON kacho_iam.organizations (scim_token_hash)
  WHERE scim_token_hash IS NOT NULL AND scim_token_revoked_at IS NULL;

-- domain_verification_state transitions (sanity check, не enforce — это в service-layer):
-- unverified → pending : StartDomainVerification (sets token + started_at)
-- pending → verified   : VerifyDomain (DNS-TXT match; sets verified_at)
-- verified → revoked   : RevokeDomainVerification (admin manual)
-- pending → unverified : RevokeDomainVerification (admin manual; clears token)
-- revoked → pending    : StartDomainVerification (re-challenge)
```

**`scim_user_mappings` ALTER** (extend Phase 1 skeleton):

```sql
ALTER TABLE kacho_iam.scim_user_mappings
  ADD COLUMN scim_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN scim_meta_resource_type TEXT NOT NULL DEFAULT 'User',
  ADD COLUMN scim_meta_version TEXT NULL,
  ADD COLUMN last_scim_sync_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- replace Phase 1 UNIQUE (organization_id, scim_external_id) с partial:
ALTER TABLE kacho_iam.scim_user_mappings
  DROP CONSTRAINT scim_user_mappings_organization_external_uniq;

CREATE UNIQUE INDEX scim_user_mappings_org_external_active_uniq
  ON kacho_iam.scim_user_mappings (organization_id, scim_external_id)
  WHERE scim_active = true;

-- Inactive entries (после SCIM DELETE) сохраняются для audit + restore;
-- restore (POST с тем же externalId) → INSERT ... ON CONFLICT (через row search WHERE active=false)
-- → UPDATE scim_active=true + create new bindings.
```

**`organization_domain_proofs` table** (new, audit history):

```sql
CREATE TABLE kacho_iam.organization_domain_proofs (
    id TEXT PRIMARY KEY CHECK (id ~ '^odp[0-9a-z]{17}$'),
    organization_id TEXT NOT NULL REFERENCES kacho_iam.organizations(id) ON DELETE CASCADE,
    domain TEXT NOT NULL,
    challenge_token TEXT NOT NULL,
    verification_method TEXT NOT NULL DEFAULT 'dns-txt'
        CHECK (verification_method IN ('dns-txt')),  -- future: 'http-meta', 'email'
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    verified_at TIMESTAMPTZ NULL,
    failed_at TIMESTAMPTZ NULL,
    failure_reason TEXT NULL,
    requested_by_user_id TEXT NOT NULL,
    txt_record_observed TEXT NULL  -- the TXT value seen at verify-time
);

CREATE INDEX organization_domain_proofs_org_started_idx
    ON kacho_iam.organization_domain_proofs (organization_id, started_at DESC);
```

#### 2.2.2 proto messages (`kacho-proto/proto/kacho/cloud/iam/v1/`)

**`organization.proto`** (public):

```protobuf
syntax = "proto3";
package kacho.cloud.iam.v1;

import "google/protobuf/timestamp.proto";
import "google/protobuf/field_mask.proto";
import "kacho/cloud/operation/v1/operation.proto";

message Organization {
  string id = 1;
  string name = 2;
  string display_name = 3;
  string description = 4;
  google.protobuf.Timestamp created_at = 5;
  google.protobuf.Timestamp updated_at = 6;

  string domain_claim = 10;
  enum DomainVerificationState {
    DOMAIN_VERIFICATION_STATE_UNSPECIFIED = 0;
    UNVERIFIED = 1;
    PENDING = 2;
    VERIFIED = 3;
    REVOKED = 4;
  }
  DomainVerificationState domain_verification_state = 11;
  string domain_verification_challenge = 12;  // shown only when state=pending
  google.protobuf.Timestamp domain_verified_at = 13;
  string default_account_id = 14;
  string initial_role_id = 15;

  bool saml_configured = 20;  // output-only; computed from saml_metadata_xml IS NOT NULL
  string saml_acs_url = 21;
  string saml_entity_id = 22;
  google.protobuf.Timestamp saml_metadata_uploaded_at = 23;

  bool scim_enabled = 30;  // output-only; computed from scim_token_hash IS NOT NULL
                           // AND scim_token_revoked_at IS NULL
  google.protobuf.Timestamp scim_token_issued_at = 31;
}

message CreateOrganizationRequest {
  string name = 1;
  string display_name = 2;
  string description = 3;
}

message UpdateOrganizationRequest {
  string id = 1;
  google.protobuf.FieldMask update_mask = 2;
  string display_name = 3;
  string description = 4;
  string default_account_id = 5;
  string initial_role_id = 6;
  // name + domain_claim — IMMUTABLE через Update; используй отдельные RPC.
}

message DeleteOrganizationRequest { string id = 1; }

message GetOrganizationRequest { string id = 1; }

message ListOrganizationsRequest {
  int32 page_size = 1;
  string page_token = 2;
  string filter = 3;  // name=foo, name=co=foo
  string order_by = 4;  // createdAt desc, name asc
}

message ListOrganizationsResponse {
  repeated Organization organizations = 1;
  string next_page_token = 2;
}

message StartDomainVerificationRequest {
  string organization_id = 1;
  string domain_claim = 2;  // e.g. "acme.com"
}

message VerifyDomainRequest {
  string organization_id = 1;
}

message RevokeDomainVerificationRequest {
  string organization_id = 1;
}

message UploadSAMLMetadataRequest {
  string organization_id = 1;
  string saml_metadata_xml = 2;  // raw XML; service parses + extracts ACS / entity-id
}

message RevokeSAMLConfigRequest {
  string organization_id = 1;
}

message IssueSCIMTokenRequest {
  string organization_id = 1;
}

message IssueSCIMTokenResponse {
  string organization_id = 1;
  string scim_bearer_token = 2;  // shown ONLY in this response (one-time); not persisted plain
  google.protobuf.Timestamp issued_at = 3;
  string base_url = 4;  // e.g. "https://api.kacho.cloud/scim/v2"
}

message RevokeSCIMTokenRequest {
  string organization_id = 1;
}

service OrganizationService {
  rpc Get(GetOrganizationRequest) returns (Organization);
  rpc List(ListOrganizationsRequest) returns (ListOrganizationsResponse);
  rpc Create(CreateOrganizationRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc Update(UpdateOrganizationRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc Delete(DeleteOrganizationRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc StartDomainVerification(StartDomainVerificationRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc VerifyDomain(VerifyDomainRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc RevokeDomainVerification(RevokeDomainVerificationRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc UploadSAMLMetadata(UploadSAMLMetadataRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc RevokeSAMLConfig(RevokeSAMLConfigRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc IssueSCIMToken(IssueSCIMTokenRequest) returns (IssueSCIMTokenResponse);  // sync return (one-time secret)
  rpc RevokeSCIMToken(RevokeSCIMTokenRequest) returns (kacho.cloud.operation.v1.Operation);
}
```

> **Note re запрет #9**: `IssueSCIMToken` возвращает sync `IssueSCIMTokenResponse` (не Operation). Это design exception: bearer-token raw-value показывается клиенту **только в этот раз** (one-time secret); persisting в Operation.metadata.response — leak в audit logs, retry-able fetch, etc. Sync return + audit log of «token issued for org X by user Y» (без plaintext value) — security-preferred. Documented в proto comment.

**`internal_organization.proto`** (internal-only, admin-UI):

```protobuf
service InternalOrganizationService {
  rpc BindAccount(BindAccountRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc UnbindAccount(UnbindAccountRequest) returns (kacho.cloud.operation.v1.Operation);
  rpc ListAccounts(ListOrganizationAccountsRequest) returns (ListOrganizationAccountsResponse);
  rpc ListPendingDomains(ListPendingDomainsRequest) returns (ListPendingDomainsResponse);
  rpc ListSCIMMappings(ListSCIMMappingsRequest) returns (ListSCIMMappingsResponse);
  rpc ListDomainProofs(ListDomainProofsRequest) returns (ListDomainProofsResponse);
}
```

**`internal_saml.proto`** (internal-only, Kratos webhook):

```protobuf
message JITProvisionRequest {
  string kratos_identity_id = 1;
  string email = 2;
  string saml_assertion_attrs_json = 3;  // raw SAML claims for audit
  string source_ip = 4;
  string user_agent = 5;
}

message JITProvisionResponse {
  string user_id = 1;
  string account_id = 2;
  string organization_id = 3;
  bool created_now = 4;  // false если user already existed (idempotent reuse)
  repeated string assigned_role_ids = 5;
}

service InternalSAMLService {
  rpc JITProvision(JITProvisionRequest) returns (JITProvisionResponse);
}
```

**`scim_v2.proto`** (HTTP-only, types only — нет RPC потому что RFC 7644 диктует REST):

```protobuf
// SCIM 2.0 RFC 7644 messages (used in HTTP handlers; не gRPC service).
// Schemas:
// "urn:ietf:params:scim:schemas:core:2.0:User"
// "urn:ietf:params:scim:schemas:core:2.0:Group"
// "urn:ietf:params:scim:api:messages:2.0:ListResponse"
// "urn:ietf:params:scim:api:messages:2.0:Error"
// "urn:ietf:params:scim:api:messages:2.0:PatchOp"
// "urn:ietf:params:scim:api:messages:2.0:BulkRequest"
// "urn:ietf:params:scim:api:messages:2.0:BulkResponse"

message SCIMUser {
  repeated string schemas = 1;
  string id = 2;
  string external_id = 3;
  string user_name = 4;
  message Name {
    string family_name = 1;
    string given_name = 2;
    string formatted = 3;
  }
  Name name = 5;
  bool active = 6;
  message Email {
    string value = 1;
    string type = 2;
    bool primary = 3;
  }
  repeated Email emails = 7;
  message Meta {
    string resource_type = 1;
    string created = 2;
    string last_modified = 3;
    string version = 4;
    string location = 5;
  }
  Meta meta = 8;
}

message SCIMGroup {
  repeated string schemas = 1;
  string id = 2;
  string external_id = 3;
  string display_name = 4;
  message Member {
    string value = 1;  // user id
    string display = 2;
    string type = 3;  // User | Group
  }
  repeated Member members = 5;
  SCIMUser.Meta meta = 6;
}

message SCIMError {
  repeated string schemas = 1;
  int32 status = 2;
  string scim_type = 3;  // invalidFilter | invalidSyntax | uniqueness | mutability | sensitive | tooMany
  string detail = 4;
}

message SCIMListResponse {
  repeated string schemas = 1;
  int32 total_results = 2;
  int32 items_per_page = 3;
  int32 start_index = 4;
  repeated bytes resources = 5;  // JSON-marshalled SCIMUser | SCIMGroup
}
```

#### 2.2.3 corelib packages

- **`corelib/scim/parser.go`** — SCIM 2.0 filter expression parser (RFC 7644 §3.4.2.2). Grammar:
  ```ebnf
  filter      = expression *( logExp expression )
  expression  = attrExp / "(" filter ")" / notOp filter
  attrExp     = attrPath SP "pr" / attrPath SP compOp SP compValue
  compOp      = "eq" | "ne" | "co" | "sw" | "ew" | "gt" | "ge" | "lt" | "le"
  logExp      = "and" | "or"
  notOp       = "not"
  attrPath    = attrName [ "." subAttr ]
  compValue   = string | number | boolean | null  (JSON quoting)
  ```
  Output: AST representable as Go struct tree; evaluator visits AST + SQL-builder (for repo-layer) или in-memory match-helper (для unit tests).

- **`corelib/scim/pagination.go`** — RFC 7644 §3.4.2.4. Query params: `startIndex` (1-based; default 1), `count` (default 100; max 1000 enforced by ServiceProviderConfig). Response: `totalResults` (int), `startIndex`, `itemsPerPage`, `Resources`.

- **`corelib/scim/sort.go`** — RFC 7644 §3.4.2.3. Query params: `sortBy` (attribute path; whitelisted set: `userName`, `name.familyName`, `name.givenName`, `meta.created`, `meta.lastModified`, `externalId`), `sortOrder` (`ascending` | `descending`; default ascending).

- **`corelib/scim/errors.go`** — RFC 7644 §3.12. Returns JSON body `{"schemas":["urn:ietf:params:scim:api:messages:2.0:Error"],"status":"<HTTP>","scimType":"<scim_type>","detail":"..."}`. `scimType` mapping: filter parse error → `invalidFilter`; bad JSON → `invalidSyntax`; duplicate externalId → `uniqueness`; PATCH on immutable attr → `mutability`; sensitive attr in filter → `sensitive`; max bulk ops exceeded → `tooMany`.

- **`corelib/scim/response.go`** — JSON-ld response helper; sets `Content-Type: application/scim+json` per RFC 7644 §3.1.

- **`corelib/dns/txt_resolver.go`** — interface + default `net.LookupTXT` impl + mock-resolver-for-tests:
  ```go
  type TXTResolver interface {
      LookupTXT(ctx context.Context, domain string) ([]string, error)
  }
  type defaultResolver struct{}
  func (d *defaultResolver) LookupTXT(ctx context.Context, domain string) ([]string, error) {
      return net.DefaultResolver.LookupTXT(ctx, domain)
  }
  ```
  Mock-resolver используется в integration tests чтобы не зависеть от реального DNS.

#### 2.2.4 kacho-iam apps

- **`internal/apps/kacho/api/organization/`** — gRPC handlers для `OrganizationService` + `InternalOrganizationService`.
- **`internal/apps/kacho/api/scim/`** — HTTP handlers для `/scim/v2/Users/{,id}`, `/Groups/{,id}`, `/Bulk`, `/Me`, `/ResourceTypes`, `/Schemas`, `/ServiceProviderConfig`. Mounted на REST mux под `/scim/v2/` prefix; **не** через grpc-gateway transcoding (SCIM JSON format не транслируется чисто из protobuf).
- **`internal/apps/kacho/api/saml/jit_provision.go`** — handler `InternalSAMLService.JITProvision`; called Kratos webhook'ом после OIDC registration (Jackson translated SAML response to OIDC ID-token for Kratos).
- **`internal/apps/kacho/auth/scim_bearer_authn.go`** — HTTP middleware. Извлекает `Authorization: Bearer <token>` header; computes SHA-256; SELECTs `organizations WHERE scim_token_hash=$1 AND scim_token_revoked_at IS NULL`; устанавливает `request.ctx.scim_org_id = <id>` + `principal.type = service_account; principal.id = sva_scim_<org_id>; principal.subject_relation = scim_admin`. Возвращает 401 при no-match.
- **`internal/repo/kacho/pg/organization_phase6_repo.go`** + `scim_user_mappings_phase6_repo.go` + `organization_domain_proofs_repo.go` — pgx + sqlc repo layer.

### 2.3 Identifiers / ID prefixes

| Сущность | ID prefix | Pattern | Allocation |
|---|---|---|---|
| Organization | `org` | `org[0-9a-z]{17}` | Existing (Phase 1) |
| Account | `acc` | `acc[0-9a-z]{17}` | Existing |
| User | `usr` | `usr[0-9a-z]{17}` | Existing |
| ServiceAccount (SCIM auto-created) | `sva` | `sva[0-9a-z]{17}` (specifically `svascimXXXXXXXX`) | Phase 6 (one per Org on first IssueSCIMToken) |
| Role | `rol` | `rol[0-9a-z]{17}` | Existing |
| AccessBinding | `abd` | `abd[0-9a-z]{17}` | Existing |
| **SCIMUserMapping** | `sum` | `sum[0-9a-z]{17}` | **Phase 6** |
| **OrganizationDomainProof** | `odp` | `odp[0-9a-z]{17}` | **Phase 6** |
| **Operation** (per-RPC) | `opi` | `opi[0-9a-z]{17}` (existing for iam) | Existing |

SCIM user resource id in SCIM responses — equal to underlying `users.id` (e.g. `usr00000abc123...`); SCIM consumers treat it as opaque string per RFC 7644 §3.1.

### 2.4 Принципалы и RBAC

| Принципал | Откуда токен | Кто проверяет |
|---|---|---|
| **Кластер-админ (system_admin)** | Hydra JWT с `acr` ≥ `aal2`; resolver проверяет FGA tuple `cluster:cluster_kacho_root#system_admin@user:<id>` | Hydra middleware → corelib/authz Check для OrganizationService мутаций |
| **Org admin (`organization#admin`)** | Hydra JWT обычного user; FGA `organization:<org_id>#admin@user:<id>` | corelib/authz Check на `OrganizationService.Update/Delete/StartDomainVerification/...` |
| **SCIM bearer principal** | Opaque token `Authorization: Bearer <40-byte hex>`; HTTP middleware resolves к `service_account:sva_scim_<org_id>` | `scim_bearer_authn.go` middleware; устанавливает principal с FGA tuple `organization:<org>#scim_admin@service_account:sva_scim_<org>` |
| **SAML-authenticated user** | Hydra JWT issued by Hydra после Kratos OIDC flow → Kratos OIDC connector → Jackson → SAML IdP | Phase 2 standard JWT validation; pre-JIT первый signin создаёт User row + Hydra token issued по существующему flow |
| **Cluster admin operating on Org admin-UI** | Hydra JWT acr=aal2 + FGA `cluster#system_admin` | `InternalOrganizationService.*` методы — internal-only mount, Hydra-JWT + FGA cluster_admin check |

### 2.5 SCIM bearer token — secret lifecycle

1. **Issue**: `OrganizationService.IssueSCIMToken(org_id)` — handler:
   1. Authn: caller — cluster-admin OR organization#admin для org_id (FGA Check).
   2. Generate `secret := crypto/rand 32 bytes → hex encode (64 chars; like Okta API tokens)`.
   3. `hash := sha256(secret)`.
   4. TX: `UPDATE organizations SET scim_token_hash=$1, scim_token_issued_at=now(), scim_token_revoked_at=NULL WHERE id=$2`. Если ранее был issued (scim_token_hash IS NOT NULL AND scim_token_revoked_at IS NULL) — операция **overwrite**'ит (rotate); старый hash больше не валиден. Audit row `iam.scim_token_rotated|issued`.
   5. Emit FGA Write: `organization:<org_id>#scim_admin@service_account:sva_scim_<org_id>` (idempotent; might already exist).
   6. CAEP outbox: `organization.scim_token_rotated` event.
   7. Return `IssueSCIMTokenResponse{scim_bearer_token: <secret>, base_url: "https://api.kacho.cloud/scim/v2", issued_at}` **sync** (one-time response).
2. **Use**: SCIM clients (Okta provisioning agent, etc.) send `Authorization: Bearer <secret>`.
3. **Validate** (per request): middleware SHA-256s the header, SELECTs `organizations WHERE scim_token_hash=$1 AND scim_token_revoked_at IS NULL`. If no row → `401 Unauthorized` (SCIM-format error JSON). If found → principal scoped к этой org.
4. **Rotate**: повторный `IssueSCIMToken` — overwrite hash (старый Bearer становится invalid; нет grace period в этом релизе — клиент должен немедленно переключиться на новый).
5. **Revoke**: `RevokeSCIMToken` — `UPDATE organizations SET scim_token_revoked_at=now()`; old hash остаётся для audit но WHERE-условие в lookup отвергает.

### 2.6 SAML SP-init vs IdP-init

- **SP-init**: user opens `https://app.kacho.cloud/iam/login`, types corporate email `alice@acme.com`. UI calls `iam-public.LookupOrganizationByDomain(domain=acme.com)`. Returns `org_id` если `domain_verification_state=verified` AND `saml_configured=true`. UI redirects browser to `https://api.kacho.cloud/oidc/auth?org=<org_id>` → Kratos OIDC selector → Kratos calls Jackson `/api/oauth/authorize?tenant=<org_id>&product=kacho` → Jackson generates SAMLRequest → POST к Customer IdP (Okta/Azure) → Customer IdP authenticates → POST SAMLResponse → Jackson ACS endpoint `/api/oauth/saml` → Jackson validates assertion + extracts attrs → Jackson issues OIDC ID-token к Kratos → Kratos completes signin → Hydra issues access token.

- **IdP-init**: customer admin sets up Okta dashboard tile «Kachō»; tile target = `https://api.kacho.cloud/api/oauth/saml-idp-init?tenant=<org_id>`. User clicks tile → Okta IdP starts session → POST SAMLResponse к Jackson — без preceding SAMLRequest. Jackson supports IdP-init mode (per Boxyhq documentation); validates RelayState if provided; issues OIDC ID-token to Kratos same as SP-init.

В обоих flow'ах Kratos `post_oidc_registration` webhook hits `InternalSAMLService.JITProvision` if Kratos identity не существовала ранее. **Существующая Kratos identity** (повторный signin same user) — JIT skips create user-row если scim_user_mappings уже есть; если нет — создаёт user-row в default_account (это «SCIM-less JIT» path).

### 2.7 Domain claim DNS-TXT verification flow

1. Org admin calls `StartDomainVerification(org_id, domain_claim="acme.com")`:
   1. Validate domain syntax (RFC 1035 + IDNA: lowercase, ≤253 chars, only `[a-z0-9.-]`, no leading/trailing dot).
   2. Check partial UNIQUE `organizations_domain_claim_uniq` — если другой Org уже claimed `acme.com` со state ∈ {pending, verified} → `ALREADY_EXISTS`.
   3. Generate `challenge := "kacho-domain-verification=" + crypto/rand 32 hex chars`.
   4. UPDATE org: `domain_claim=$1, domain_verification_state='pending', domain_verification_token=$2, domain_verification_started_at=now()`.
   5. INSERT `organization_domain_proofs` row (history).
   6. Return Operation.Done with `OrgPhase6.Organization` showing `domain_verification_state=PENDING` + `domain_verification_challenge="kacho-domain-verification=ABC123..."`. UI shows: «Add this TXT record to `_kacho-verify.acme.com`: `kacho-domain-verification=ABC123...`; then click Verify».
2. Org admin sets DNS TXT record at customer DNS.
3. Org admin calls `VerifyDomain(org_id)`:
   1. Pre-check: state == pending; not expired (verification_started_at within 7 days; otherwise re-Start).
   2. `corelib/dns.LookupTXT("_kacho-verify." + domain_claim)` — lookup at TTL-cached resolver.
   3. Match: any returned TXT value == stored `domain_verification_token`.
      - Match → `UPDATE organizations SET domain_verification_state='verified', domain_verified_at=now()`; INSERT proof history `verified_at=now(), txt_record_observed=<value>`; emit audit; Operation done success.
      - No match → INSERT proof history `failed_at=now(), failure_reason='no_match'`; Operation done with error `FAILED_PRECONDITION: domain TXT record not found or does not match challenge`.
4. Once verified, SP-init lookup `LookupOrganizationByDomain(domain="acme.com")` returns Organization (см. §6.6.1 SAML lookup path).
5. `RevokeDomainVerification` — admin manually unsets (e.g. domain sold); state → revoked; future SP-init by that domain → `NOT_FOUND` (effective).

### 2.8 SCIM lifecycle webhook cascade (RFC 7644 §3.6 + Phase 6 design)

SCIM `DELETE /scim/v2/Users/{id}`:

1. Middleware: bearer-authn → principal = `service_account:sva_scim_<org_id>`; scope = `scim_admin@organization:<org_id>`.
2. Handler:
   1. Look up `scim_user_mappings WHERE organization_id=$1 AND user_id=$2 AND scim_active=true` → если no row → `404 Not Found` (SCIM error).
   2. Verify `users.account.organization_id == authenticated_org_id` (cross-org isolation; см. §6.3.7) — defence-in-depth.
   3. TX:
      ```sql
      UPDATE users SET status='BLOCKED', updated_at=now() WHERE id=$1;
      UPDATE scim_user_mappings SET scim_active=false, last_scim_sync_at=now() WHERE id=$2;
      UPDATE access_bindings SET status='REVOKED', revoked_at=now() WHERE subject_user_id=$1 AND status='ACTIVE';
      INSERT INTO caep_outbox (event_type, payload_json) VALUES ('users.deactivated', '{...}');
      INSERT INTO audit_outbox (event_type, actor_id, target_id, ...) VALUES ('iam.scim.user_deleted', ...);
      INSERT INTO fga_outbox (op, tuple_json) VALUES ('delete', '{...}'), ('delete', ...);  -- one per revoked binding
      ```
   4. Outbox drainer (Phase 1 mechanism) → FGA Write delete tuples → LISTEN/NOTIFY → corelib/authz cache invalidate.
3. Response: `204 No Content`.
4. Restore: `POST /scim/v2/Users` с тем же `externalId` → handler looks up inactive mapping (`WHERE organization_id=$1 AND scim_external_id=$2 AND scim_active=false`) → если найдено → UPDATE `scim_active=true, last_scim_sync_at=now()` + UPDATE `users.status='ACTIVE'`; **не** создаёт новый user-row.

---

## 3. Decision Log (Phase 6)

| # | Решение | Обоснование |
|---|---|---|
| **P6-D1** | **Organization tier — optional, NOT mandatory** | `accounts.organization_id` остаётся `NULL`-able (Phase 1 D-4). Personal-account signups (Phase 2/E4) не требуют Org; Phase 6 не enforce-ит миграцию existing accounts в Org. B2B customer пути: cluster-admin создаёт Org → bind-ит accounts → opt-in. |
| **P6-D2** | **SCIM 2.0 RFC 7644 strict compliance** | Cardinal требование от enterprise customers (Okta, Azure AD, Google Workspace, Ping, OneLogin); deviations break vendor integrations. Phase 6 не позволяет себе custom-SCIM. Tested via vendor sandboxes (Okta + Azure + Google) перед merge'ом. |
| **P6-D3** | **SAML 2.0 via Boxyhq Jackson — НЕ native SAML в kacho-iam** | ORY Kratos OSS не имеет native SAML SP support; Jackson — open-source self-host SAML→OIDC bridge (Apache 2.0 licensed, actively maintained на 2026-05). Kachō внутри consumes только OIDC — это упрощает Kratos config (один adapter type — generic OIDC) и изолирует SAML complexity в Jackson. Альтернативы (Keycloak — слишком heavy; gosaml2 Go-lib — стало бы тащить SAML XML signature validation сам — security risk) — отвергнуты. |
| **P6-D4** | **Per-Org SCIM bearer token (rotatable + revokable)** | Vendor SCIM clients требуют per-tenant Bearer token. Hash в `organizations.scim_token_hash` (SHA-256), plaintext показывается только в IssueSCIMToken response (one-time). Token = opaque 32-byte hex (Okta-format-compatible 64 chars). Rotate = overwrite hash (no grace period — простота >> seamless rotation; customer должен update Okta config). Future improvement (Phase 11+): dual-token grace window (`scim_token_hash_current` + `scim_token_hash_previous`). |
| **P6-D5** | **SCIM externalId scoped by organization_id (cross-org isolation)** | UNIQUE `(organization_id, scim_external_id) WHERE scim_active=true`. Same externalId «alice@acme.com» в Org A и Org B — два разных mappings. SCIM-handler авторизуется через bearer → resolves к Org X → любые операции верифицируют `target.user.account.organization_id == X` (DB query JOIN + service-layer assertion + integration test §6.3.7). Защита от: compromised Org A SCIM token не должен мочь видеть/менять Org B users даже если знает их id. |
| **P6-D6** | **SAML SP-init + IdP-init обе flow обязательны** | Enterprise customers ожидают оба: SP-init (user types email в UI Kachō); IdP-init (user clicks tile в Okta dashboard). Jackson supports обе нативно — Phase 6 wires UI + admin docs для обеих. |
| **P6-D7** | **JIT provisioning: first SAML signin без pre-SCIM → create User в default Account org'а** | Не все customers будут настраивать SCIM (extra cost in Okta etc.). SAML-only signin tier должен работать: user с verified-domain email → matches Organization → создаётся в `default_account_id` org'а + assigns `initial_role_id`. Default account и initial role — настраиваются Org admin'ом via UI. Если org-admin **не** настроил default_account_id — JIT fails fail-closed (`FAILED_PRECONDITION: organization has no default_account_id`); customer admin учится настроить или явно SCIM-provision users. |
| **P6-D8** | **Domain claim verification = DNS-TXT challenge** | Industry standard (Okta, Google Workspace, Slack, etc.). DNS-TXT доказывает контроль над DNS зоной — sufficient для tying email-domain к Org. Phase 6 supports только `dns-txt` метод; HTTP-meta verification — future. Challenge token — 32 hex chars; TXT record at `_kacho-verify.<domain>`; max 7 days to verify before token expires (re-Start). |
| **P6-D9** | **SCIM bearer token validation — внутри kacho-iam middleware, НЕ через api-gateway / Hydra OIDC** | SCIM bearer ≠ OAuth2 access token. RFC 7644 §2 allows opaque bearer. Если бы Phase 6 переиспользовал Hydra OAuth — пришлось бы issue refresh-token-rotation + JWT validate + DPoP — overkill для SCIM bearer (vendor clients не поддерживают DPoP). Phase 6: `/scim/v2/*` запросы — api-gateway пропускает без Hydra validation (bypass middleware); kacho-iam `scim_bearer_authn.go` middleware validates against `organizations.scim_token_hash`. Это design exception от standard принципала-flow — обосновано RFC 7644 § token semantics. |
| **P6-D10** | **SCIM `/Bulk` max 100 ops per request** | Safety limit; RFC 7644 §3.7.3 разрешает implementations to enforce. ServiceProviderConfig advertises `bulk.maxOperations=100, bulk.maxPayloadSize=1MiB`. >100 → `400 tooMany`. |
| **P6-D11** | **SCIM `/Bulk` атомарность — `failOnErrors=1` (default) — abort on first error; `failOnErrors=0` — continue** | RFC 7644 §3.7.3 поддерживает оба. Phase 6 implements оба: каждая bulk-op в своей TX (independent); `failOnErrors=1` — handler возвращает первую failure (response.Operations содержит только успешные + первую failure); `failOnErrors=0` — все обрабатываются; response содержит per-op status. |
| **P6-D12** | **SCIM nested groups — поддерживаются** | RFC 7644 §4.2 разрешает group members of type `Group`. Phase 6 хранит `group_members.member_user_id` (existing) + новая колонка `group_members.member_group_id` (mutual-exclusive CHECK). Resolve depth-1 + cycle detection в FGA model (через `group#member = [user, group#member]` — already есть в Phase 3 design). Max nesting depth — 5 (CHECK при INSERT через recursive CTE). |
| **P6-D13** | **SCIM-managed groups (`scim_managed=true`) — НЕ редактируемы через UI** | Groups созданные через SCIM (`POST /scim/v2/Groups`) — set `groups.scim_managed=true, groups.external_id=<scim_externalId>`. UI / iam-public-API запрещают `GroupService.Update` если `scim_managed=true` (returns `FAILED_PRECONDITION: group is SCIM-managed, modify via SCIM endpoint`). Customer-side modifications должны идти через Okta — это согласуется с industry expectation. |
| **P6-D14** | **`OrganizationService.Update` НЕ меняет `name` / `domain_claim`** | `name` — immutable после Create (как Account.name); `domain_claim` — меняется только через StartDomainVerification + VerifyDomain (явный flow). Любой Update запрос с `name` или `domain_claim` в `update_mask` → `INVALID_ARGUMENT: <field> is immutable, use dedicated RPC`. |
| **P6-D15** | **Multi-org user — один Kratos identity → N user-rows (one per Org)** | Существующая Phase 1/KAC-125 модель «User per-Account» расширяется: при SCIM POST для existing Kratos identity → ищется existing user-row WHERE `kratos_identity_id=$1 AND account_id=$2` (per-Account uniqueness Phase 1); если есть — reuse; если нет — create new user-row (NO Kratos identity duplication). Phase 6 GWT 6.9.4 covers. |
| **P6-D16** | **SAML cert rotation — re-upload metadata XML** | Customer IdP cert expires every ~1-3y. Customer admin re-uploads metadata-XML to kacho-ui; UploadSAMLMetadata replaces `saml_metadata_xml` + triggers Jackson Admin API `PATCH /api/v1/sso/connections/<id>` to update connection. Grace period: Jackson keeps both old+new public keys for 24h (Jackson-internal feature); after 24h только новый принимается. |
| **P6-D17** | **DELETE Organization — RESTRICT если есть accounts; cluster-admin может cascade-unbind** | `accounts.organization_id` FK `ON DELETE RESTRICT` (Phase 1). Cluster-admin вызывает `InternalOrganizationService.UnbindAccount` для каждого account → set `organization_id=NULL`; затем `DeleteOrganization`. Phase 6 не делает cascade unbind в одном RPC — explicit operator action required (safety). |
| **P6-D18** | **SCIM endpoint advertises ServiceProviderConfig** | RFC 7644 §5 mandates `/ServiceProviderConfig` endpoint. Phase 6 advertises: `patch.supported=true`, `bulk.supported=true, maxOperations=100, maxPayloadSize=1MiB`, `filter.supported=true, maxResults=200`, `changePassword.supported=false` (passwords — Kratos), `sort.supported=true`, `etag.supported=false` (Phase 6 — future improvement), `authenticationSchemes=[{type:"oauthbearertoken",name:"Bearer",description:"Per-org SCIM bearer token"}]`. |
| **P6-D19** | **SAML attribute mapping — fixed convention** | Jackson передаёт SAML assertion attrs через OIDC ID-token claims к Kratos. Phase 6 fixed mapping: `email`/`mail` → `traits.email`, `firstName`/`givenName` → `traits.name.first`, `lastName`/`familyName`/`sn` → `traits.name.last`. Per-Org custom mapping — future improvement. Если SAML assertion отсутствует `email` — Kratos OIDC fails (no identifier); kacho-iam логирует audit event «saml_assertion_missing_email». |
| **P6-D20** | **SCIM `/Schemas` + `/ResourceTypes` — RFC 7644 §7 mandatory** | Phase 6 hardcoded JSON responses: `/Schemas` lists Core User + Core Group + EnterpriseUser extension; `/ResourceTypes` lists User + Group with schema references. Read-only; не tied к Org. |
| **P6-D21** | **Per-Org SSO config UI — single page** | `OrgSSOConfigPage.tsx` объединяет: SAML metadata XML drag-drop + SP-init URL display + ACS URL display + SCIM token issue/revoke/show-once. Domain verification — отдельная страница (потому что multi-step DNS flow). |
| **P6-D22** | **SAML/SCIM availability — region-local, not multi-region active-active in Phase 6** | Jackson — single-region cluster (2 HA replicas в одном region); failover к secondary region — Phase 11. SCIM endpoint — kacho-iam-local (Phase 11 extends к active-active). Customer SLA: 99.9% (single region) → 99.99% (multi-region Phase 11). |
| **P6-D23** | **SCIM filter parser — handwritten, не библиотека** | На 2026-05 нет надёжной Go-библиотеки для SCIM 2.0 filter parser (есть `imulab/go-scim` — depricated; `elimity-com/scim` — partial). Phase 6 implements state-machine parser в corelib/scim (50+ unit-test cases against RFC §3.4.2.2 grammar). Decision tree сравнения: implement-self vs vendor; implement-self выигрывает в long-term maintainability (no external dep, full control over edge cases). |
| **P6-D24** | **JIT user — initial Account binding goes through standard AccessBinding flow** | JIT не bypass'ит access_bindings table. Handler создаёт row `access_bindings (subject_user_id=$1, role_id=org.initial_role_id, resource_account_id=org.default_account_id, status='ACTIVE', granted_by='system_jit_provision')`; FGA outbox emits tuple; ListObjects cache invalidates. Same audit trail и same revocation paths как regular grants. |
| **P6-D25** | **SCIM rate limiting — per-Org bucket 100 RPS** | Defense-in-depth против runaway provisioning loops (Okta misconfig может пушить 10k operations / minute). Phase 6: in-memory token-bucket per `organization_id`; 100 RPS sustained, burst 200. Exceeded → `429 Too Many Requests` (RFC 7644 supports). Future improvement: persistent rate-limit store (Redis) для cross-pod consistency. |

> **Backward compatibility note (user feedback round 2 2026-05-19 «no strict backward-compat»)**: Phase 1 schema для `organizations` создавался как skeleton (только id/name/...). Phase 6 свободно расширяет — ALTER TABLE без backfill (existing rows получают default values). API contract `OrganizationService` — новый в Phase 6 (Phase 1 не expose'ил RPC; только schema). Никаких deprecation cycles. SCIM/SAML — net new functionality. UI redesign — net new pages.

---

## 4. Архитектурные диаграммы

### 4.1 SAML SP-init flow (customer types email в Kachō UI)

```
┌──────────┐                ┌──────────┐         ┌──────────┐        ┌──────────┐
│  User    │                │ kacho-ui │         │ kacho-iam│        │  Kratos  │
│ (browser)│                │  (SPA)   │         │          │        │          │
└────┬─────┘                └────┬─────┘         └────┬─────┘        └────┬─────┘
     │                           │                    │                   │
     │ navigates                 │                    │                   │
     │ /iam/login                │                    │                   │
     │──────────────────────────►│                    │                   │
     │                           │                    │                   │
     │ types "alice@acme.com"    │                    │                   │
     │──────────────────────────►│                    │                   │
     │                           │                    │                   │
     │                           │ GET /v1/iam/orgs   │                   │
     │                           │ :lookupByDomain    │                   │
     │                           │ ?domain=acme.com   │                   │
     │                           │───────────────────►│                   │
     │                           │                    │                   │
     │                           │                    │ SELECT WHERE      │
     │                           │                    │ domain_claim=$1   │
     │                           │                    │ AND state=verified│
     │                           │                    │ AND saml_metadata_│
     │                           │                    │     xml IS NOT    │
     │                           │                    │     NULL          │
     │                           │                    │ ── DB ──          │
     │                           │                    │                   │
     │                           │ 200 {org_id:..,    │                   │
     │                           │      saml=true}    │                   │
     │                           │◄───────────────────│                   │
     │                           │                    │                   │
     │ redirect 302              │                    │                   │
     │ /oidc/auth?org=org_..     │                    │                   │
     │◄──────────────────────────│                    │                   │
     │                           │                    │                   │
     │ GET /oidc/auth            │                    │                   │
     │ ?org=org_..               │                    │                   │
     │─────────────────────────────────────────────────────────────────────►│
     │                                                                    │
     │                                                                    │ resolve OIDC
     │                                                                    │ connector
     │                                                                    │ kacho_jackson_<org>
     │                                                                    │
     │                                                                    │
     │   302 to Jackson:                                                  │
     │   /api/oauth/authorize?tenant=org_..&product=kacho                 │
     │◄────────────────────────────────────────────────────────────────────│
     │                                                                    │
     │                                                                    │
     │                       ┌──────────┐                ┌──────────┐
     │                       │ Jackson  │                │ Customer │
     │                       │  (SAML→  │                │  Okta    │
     │                       │   OIDC)  │                │  IdP     │
     │                       └────┬─────┘                └────┬─────┘
     │                            │                           │
     │ POST authorize             │                           │
     │───────────────────────────►│                           │
     │                            │                           │
     │                            │ generates                 │
     │                            │ SAMLRequest               │
     │                            │ (signed if configured)    │
     │                            │                           │
     │                            │ 302 to IdP SSO URL        │
     │                            │ POST SAMLRequest          │
     │                            │ (RelayState=org_id)       │
     │ 302/HTML auto-POST         │                           │
     │◄───────────────────────────│                           │
     │                            │                           │
     │ POST to Okta SSO URL       │                           │
     │ + SAMLRequest              │                           │
     │──────────────────────────────────────────────────────►│
     │                            │                           │
     │                            │                           │ user
     │                            │                           │ authenticates
     │                            │                           │ (Okta SSO+MFA)
     │                            │                           │
     │                            │                           │
     │ 200 HTML with auto-POST    │                           │
     │ SAMLResponse + RelayState  │                           │
     │ to ACS                     │                           │
     │◄──────────────────────────────────────────────────────│
     │                            │                           │
     │ POST /api/oauth/saml       │                           │
     │  (Jackson ACS)             │                           │
     │ + SAMLResponse             │                           │
     │ + RelayState=org_id        │                           │
     │───────────────────────────►│                           │
     │                            │                           │
     │                            │ validate                  │
     │                            │ signature                 │
     │                            │ (using saml_metadata_xml  │
     │                            │  cert от org's IdP);      │
     │                            │ extract attrs             │
     │                            │ (email, name);            │
     │                            │ create OIDC ID-token      │
     │                            │ для Kratos                │
     │                            │                           │
     │                            │ 302 back to Kratos        │
     │                            │ OIDC callback URL         │
     │                            │ + code=...                │
     │◄───────────────────────────│                           │
     │                                                        │
     │                                                        │
     │ GET /self-service/methods/oidc/callback?code=..&org=.. │
     │───────────────────────────────────────────────────────►│ (back to Kratos)
     │                                                        │
     │                                                        │ token-exchange:
     │                                                        │ Kratos → Jackson
     │                                                        │ POST /token
     │                                                        │ ←── ID-token
     │                                                        │
     │                                                        │ check Kratos identity:
     │                                                        │ ── if exists → reuse;
     │                                                        │ ── if new → call
     │                                                        │    post_oidc_registration
     │                                                        │    webhook:
     │                                                        │
     │                                                        │    POST kacho-iam:9091
     │                                                        │    InternalSAMLService
     │                                                        │    /JITProvision
     │                                                        │     {kratos_identity_id,
     │                                                        │      email,
     │                                                        │      saml_attrs_json}
     │                                                        │    ────────────────►
     │                                                        │
     │                                                        │       │ (kacho-iam)
     │                                                        │       │
     │                                                        │       │ resolve Org by
     │                                                        │       │ email domain
     │                                                        │       │ (domain_verified)
     │                                                        │       │
     │                                                        │       │ create User row
     │                                                        │       │ in default_account
     │                                                        │       │
     │                                                        │       │ INSERT access_binding
     │                                                        │       │ (role=initial_role,
     │                                                        │       │  resource=account,
     │                                                        │       │  status=ACTIVE)
     │                                                        │       │
     │                                                        │       │ outbox: FGA Write +
     │                                                        │       │ CAEP users.provisioned
     │                                                        │       │ + audit
     │                                                        │       │
     │                                                        │ ◄── 200 {user_id, acc_id,
     │                                                        │         org_id}
     │                                                        │
     │                                                        │ Kratos session created;
     │                                                        │ ID-token issued
     │                                                        │
     │ 302 to app + session-cookie set                        │
     │◄───────────────────────────────────────────────────────│
     │                                                        │
     │ User logged in to Kachō UI as JIT-provisioned User.    │
```

### 4.2 SAML IdP-init flow (customer clicks Okta tile)

```
┌──────────┐         ┌──────────┐                ┌──────────┐         ┌──────────┐
│  User    │         │ Customer │                │ Jackson  │         │  Kratos  │
│ (browser)│         │   Okta   │                │  ACS     │         │          │
└────┬─────┘         └────┬─────┘                └────┬─────┘         └────┬─────┘
     │                    │                           │                   │
     │ Okta dashboard:    │                           │                   │
     │ clicks "Kachō"     │                           │                   │
     │ tile               │                           │                   │
     │───────────────────►│                           │                   │
     │                    │                           │                   │
     │                    │ generates                 │                   │
     │                    │ SAMLResponse              │                   │
     │                    │ (no prior request)        │                   │
     │                    │ Destination = Jackson ACS │                   │
     │                    │ Assertion includes        │                   │
     │                    │ email, name, groups       │                   │
     │                    │ RelayState =              │                   │
     │                    │   "tenant=org_..&         │                   │
     │                    │    product=kacho"         │                   │
     │                    │                           │                   │
     │                    │ HTML form auto-POST       │                   │
     │ HTML page          │ to Jackson                │                   │
     │◄───────────────────│                           │                   │
     │                    │                           │                   │
     │ POST /api/oauth/   │                           │                   │
     │ saml               │                           │                   │
     │ + SAMLResponse     │                           │                   │
     │ + RelayState       │                           │                   │
     │───────────────────────────────────────────────►│                   │
     │                                                │                   │
     │                                                │ parse RelayState  │
     │                                                │ → tenant=org_..   │
     │                                                │                   │
     │                                                │ validate          │
     │                                                │ signature         │
     │                                                │                   │
     │                                                │ extract attrs     │
     │                                                │                   │
     │                                                │ skip OIDC         │
     │                                                │ authorize-code    │
     │                                                │ flow; issue       │
     │                                                │ ID-token direct   │
     │                                                │                   │
     │                                                │ POST к Kratos     │
     │                                                │ self-service init │
     │                                                │ for IdP-init      │
     │                                                │ session creation  │
     │                                                │──────────────────►│
     │                                                │                   │
     │                                                │                   │ same JIT
     │                                                │                   │ webhook flow
     │                                                │                   │ if new user
     │                                                │                   │ (see §4.1)
     │                                                │                   │
     │                                                │ 302 to            │
     │                                                │ app.kacho.cloud   │
     │                                                │ + session-cookie  │
     │◄───────────────────────────────────────────────│                   │
     │                                                                    │
     │ User logged in to Kachō UI (IdP-initiated).                        │
```

### 4.3 SCIM push from Okta (provisioning agent)

```
┌──────────┐                                ┌──────────┐         ┌──────────┐
│  Okta    │                                │ kacho-   │         │ kacho-iam│
│ provis.  │                                │ api-gw   │         │ (SCIM    │
│ agent    │                                │          │         │  handler)│
└────┬─────┘                                └────┬─────┘         └────┬─────┘
     │                                           │                    │
     │ Okta admin configures Provisioning to:    │                    │
     │   Base URL: https://api.kacho.cloud/scim/v2                    │
     │   API Token: <bearer issued by IssueSCIMToken>                 │
     │                                           │                    │
     │ POST /scim/v2/Users                       │                    │
     │ Authorization: Bearer abc123def..         │                    │
     │ Content-Type: application/scim+json       │                    │
     │ Body: {schemas:[..User], userName:        │                    │
     │   "alice@acme.com", externalId:"okta-123",│                    │
     │   active:true, name:{givenName:"Alice",   │                    │
     │   familyName:"Doe"}, emails:[...]}        │                    │
     │──────────────────────────────────────────►│                    │
     │                                           │                    │
     │                                           │ scim_bypass        │
     │                                           │ middleware:        │
     │                                           │ skip Hydra JWT;    │
     │                                           │ pass to backend    │
     │                                           │                    │
     │                                           │ proxy POST to      │
     │                                           │ kacho-iam:9080/    │
     │                                           │ scim/v2/Users      │
     │                                           │───────────────────►│
     │                                           │                    │
     │                                           │                    │ scim_bearer_authn
     │                                           │                    │ middleware:
     │                                           │                    │ SHA-256(bearer);
     │                                           │                    │ lookup
     │                                           │                    │ organizations
     │                                           │                    │ WHERE
     │                                           │                    │   scim_token_hash
     │                                           │                    │   AND NOT revoked
     │                                           │                    │ → org_acme..
     │                                           │                    │ → principal=
     │                                           │                    │   sva_scim_org_acme..
     │                                           │                    │
     │                                           │                    │ check rate limit
     │                                           │                    │ per-Org 100 RPS
     │                                           │                    │
     │                                           │                    │ parse SCIM body
     │                                           │                    │
     │                                           │                    │ check externalId
     │                                           │                    │ NOT already in
     │                                           │                    │ scim_user_mappings
     │                                           │                    │ (where active)
     │                                           │                    │
     │                                           │                    │ resolve Kratos
     │                                           │                    │ identity by email
     │                                           │                    │  ── if exists:
     │                                           │                    │     reuse identity
     │                                           │                    │  ── if new:
     │                                           │                    │     POST Kratos
     │                                           │                    │     admin
     │                                           │                    │     /identities
     │                                           │                    │
     │                                           │                    │ INSERT users
     │                                           │                    │ (per-Org-account
     │                                           │                    │  row)
     │                                           │                    │
     │                                           │                    │ INSERT mapping
     │                                           │                    │ (org_id,
     │                                           │                    │  scim_external_id,
     │                                           │                    │  user_id,
     │                                           │                    │  scim_active=true)
     │                                           │                    │
     │                                           │                    │ INSERT
     │                                           │                    │ access_binding
     │                                           │                    │ (initial_role,
     │                                           │                    │  account,
     │                                           │                    │  ACTIVE)
     │                                           │                    │
     │                                           │                    │ outbox: FGA Write
     │                                           │                    │ + CAEP
     │                                           │                    │ + audit
     │                                           │                    │
     │                                           │                    │ TX commit
     │                                           │                    │
     │                                           │ 201 Created        │
     │                                           │ + SCIMUser JSON    │
     │                                           │ (id, externalId,   │
     │                                           │  userName, meta..) │
     │◄──────────────────────────────────────────│◄───────────────────│
     │                                                                │
```

### 4.4 JIT provisioning без pre-SCIM

См. §4.1 — sequence from POST `/InternalSAMLService.JITProvision` onwards.

---

## 5. Декомпозиция Phase 6 по репо (см. также §1 «target repos / merge order»)

### 5.1 `kacho-proto`

**Файлы**:
- `proto/kacho/cloud/iam/v1/organization.proto` (public `OrganizationService` + messages — §2.2.2)
- `proto/kacho/cloud/iam/v1/internal_organization.proto` (internal admin RPC)
- `proto/kacho/cloud/iam/v1/internal_saml.proto` (`InternalSAMLService.JITProvision`)
- `proto/kacho/cloud/iam/v1/scim_v2.proto` (HTTP-only types — нет gRPC service definition)
- regen `gen/go/kacho/cloud/iam/v1/*.pb.go` (commit-ить)

**`buf lint` + `buf breaking`** обязаны быть зелёными.

### 5.2 `kacho-corelib`

**Файлы**:
- `scim/parser.go` + `scim/parser_test.go` (50+ test cases on RFC 7644 §3.4.2 grammar)
- `scim/pagination.go` + `scim/pagination_test.go`
- `scim/sort.go` + `scim/sort_test.go`
- `scim/errors.go` + `scim/errors_test.go`
- `scim/response.go`
- `scim/middleware.go` (HTTP middleware factory: parse SCIM filter, validate Content-Type, write SCIM errors)
- `dns/txt_resolver.go` (interface + default impl + mock-able)

### 5.3 `kacho-iam`

**Файлы**:
- `internal/migrations/0017_kac127_phase6_org_scim_saml.sql` (см. §2.2.1)
- `internal/migrations/0017_kac127_phase6_org_scim_saml.down.sql` (для CI / rollback testing — DROP COLUMN cascade; revert ALTER scim_user_mappings; DROP organization_domain_proofs)
- `internal/apps/kacho/api/organization/` (12 handlers)
- `internal/apps/kacho/api/organization/internal/` (4 handlers — `bind_account.go`, `unbind_account.go`, `list_accounts.go`, `list_pending_domains.go`, `list_scim_mappings.go`, `list_domain_proofs.go`)
- `internal/apps/kacho/api/scim/` — HTTP handlers (`users.go`, `groups.go`, `bulk.go`, `me.go`, `resource_types.go`, `schemas.go`, `service_provider_config.go`)
- `internal/apps/kacho/api/saml/jit_provision.go`
- `internal/apps/kacho/auth/scim_bearer_authn.go`
- `internal/apps/kacho/auth/scim_rate_limit.go` (in-memory per-Org token-bucket)
- `internal/repo/kacho/pg/organization_phase6_repo.go`
- `internal/repo/kacho/pg/scim_user_mappings_phase6_repo.go`
- `internal/repo/kacho/pg/organization_domain_proofs_repo.go`
- `internal/repo/kacho/pg/group_phase6_repo.go` (extends Phase 1 group_repo для SCIM-managed flag + nested members)
- `internal/service/saml_jit_service.go` (use-case логика; depends только на domain + ports)
- `internal/service/organization_service.go` (use-case; org CRUD)
- `internal/service/scim_user_service.go` (use-case; SCIM /Users handlers)
- `internal/service/scim_group_service.go` (use-case; SCIM /Groups handlers)
- `internal/service/scim_bulk_service.go` (use-case; bulk ops orchestration)
- `internal/service/domain_verification_service.go` (use-case; DNS-TXT challenge + verify)
- `internal/service/ports.go` (extends — `OrganizationRepo`, `SCIMUserMappingRepo`, `DomainProofRepo`, `TXTResolver`, `JacksonClient`, `KratosAdminClient`)
- `internal/clients/jackson_client.go` (HTTP client к Jackson Admin API — `PATCH /api/v1/sso/connections/<id>`)
- `internal/clients/kratos_admin_client.go` (Phase 2 wired; Phase 6 extends — `CreateIdentity`, `LookupIdentityByEmail`)
- integration tests (см. §8 DoD)

### 5.4 `kacho-deploy`

**Файлы**:
- `helm/umbrella/templates/jackson-deployment.yaml`
- `helm/umbrella/templates/jackson-service.yaml`
- `helm/umbrella/templates/jackson-ingress.yaml` (path `/api/oauth/saml`, `/api/oauth/saml-idp-init`, `/api/oauth/authorize`)
- `helm/umbrella/values.dev.yaml` + `values.prod.yaml` (jackson block; Kratos OIDC config)
- `helm/umbrella/templates/postgres-init-jackson.yaml` (creates `kacho_jackson` DB)
- `helm/umbrella/templates/sealed-secret-jackson-api-key.yaml`
- `helm/umbrella/templates/servicemonitor-jackson.yaml`
- Cloudflare WAF rule: allow `/scim/v2/*` from vendor IP ranges (Okta provisioning agent + Azure + Google known IPs)

### 5.5 `kacho-api-gateway`

**Файлы**:
- `internal/restmux/scim_v2_mount.go` (HTTP reverse-proxy для `/scim/v2/*` к kacho-iam:9080)
- `internal/restmux/organization_mount.go` (public OrganizationService — grpc-gateway transcoding; internal InternalOrganizationService на :9091)
- `internal/restmux/internal_saml_mount.go` (Kratos webhook target — `:9091` mount)
- `internal/auth/scim_bypass_middleware.go` (для path prefix `/scim/v2/*` — пропускает Hydra-JWT validation; SCIM bearer-auth — внутри kacho-iam)

### 5.6 `kacho-ui`

**Файлы**:
- `src/pages/iam/organizations/OrgListPage.tsx`
- `src/pages/iam/organizations/OrgDetailPage.tsx`
- `src/pages/iam/organizations/OrgSSOConfigPage.tsx`
- `src/pages/iam/organizations/DomainVerificationPage.tsx`
- `src/pages/iam/organizations/SCIMTokenPage.tsx`
- `src/hooks/useOrgSSO.ts`
- `src/api/iam/organization.ts` (regenerated from proto-gen)

### 5.7 `kacho-test`

**Файлы**:
- `tests/newman/cases/iam_organization_phase6.py` (~15 cases)
- `tests/newman/cases/iam_scim_phase6.py` (~25 cases)
- `tests/newman/cases/iam_saml_phase6.py` (~10 cases)
- `tests/newman/cases/iam_scim_cross_org_isolation_phase6.py` (~8 cases)
- `k6/scim_load_kac127_phase6.js`
- `tests/playwright/iam_org_admin_flows.spec.ts`
- `tests/integration/saml_okta_sandbox.spec.ts` (real Okta sandbox)
- `tests/integration/saml_azure_sandbox.spec.ts` (real Azure sandbox)
- `tests/integration/scim_google_workspace_sandbox.spec.ts`
- `k6/results/KAC-127-phase6-scim.md` + `KAC-127-phase6-saml.md` artifacts

### 5.8 `kacho-workspace`

**vault updates** (см. §1 step 8).

---

## 6. Given-When-Then сценарии (>60 GWT)

> **Notation**: «Given» — setup state; «When» — action under test; «Then» / «And» — assertions on output AND side-effects (DB rows, FGA tuples, outbox entries, audit, metrics, downstream side effects). Каждый сценарий — **stand-alone** (own setup); ID = `P6-<section>.<n>.<sub>`.

### 6.1 Organization CRUD (P6-6.1)

#### P6-6.1.1 — Create Organization happy-path

**Given** cluster-admin JWT (Hydra-issued, acr=aal2, FGA tuple `cluster:cluster_kacho_root#system_admin@user:usr_admin01`).
**And** `organizations` table содержит 0 rows.

**When** caller invokes `OrganizationService.Create` со spec:
```json
{
  "name": "acme-corp",
  "display_name": "ACME Corporation",
  "description": "B2B customer; primary contact alice@acme.com"
}
```

**Then** RPC returns `operation.Operation` (async).
**And** poll `OperationService.Get(op_id)` until `done=true` (≤2s in dev) — `result.response` is `Any{type:.Organization, value:{...}}`.
**And** returned `Organization` имеет:
  - `id = "org<17 hex chars>"` (auto-allocated)
  - `name = "acme-corp"`
  - `display_name = "ACME Corporation"`
  - `description = "..."`
  - `created_at`, `updated_at` set (timestamp truncated to seconds, YC-style)
  - `domain_verification_state = UNVERIFIED`
  - `saml_configured = false`, `scim_enabled = false`
**And** DB row exists in `kacho_iam.organizations` с теми же values.
**And** outbox row inserted в `audit_outbox`: `{event_type:"iam.organization.created", actor_id:"usr_admin01", target_id:"org_..."}`.
**And** FGA tuple `organization:<org_id>#owner@user:usr_admin01` written via outbox → corelib/authz cache invalidated.
**And** metric `kacho_iam_organization_created_total{status="success"}` incremented by 1.

#### P6-6.1.2 — Create Organization duplicate name → ALREADY_EXISTS

**Given** Organization `org_existing01` уже с `name="acme-corp"`.
**When** caller invokes `Create` со `name="acme-corp"`.
**Then** Operation done with error gRPC `ALREADY_EXISTS`, message `"Organization 'acme-corp' already exists"`.
**And** SQLSTATE `23505` caught from `organizations_name_unique`, mapped to gRPC code.
**And** no new row inserted; no audit row inserted (rollback).

#### P6-6.1.3 — Create Organization invalid name → INVALID_ARGUMENT

**Given** cluster-admin JWT.
**When** caller invokes `Create` со `name=""` (empty) OR `name="ACME-Corp"` (uppercase) OR `name="acme corp"` (space) OR `name` containing 64+ chars.
**Then** Operation done with error gRPC `INVALID_ARGUMENT`, message следует YC-style: `"Illegal argument 'name': must match ^[a-z][a-z0-9-]{2,62}$"`.
**And** validation в service-layer (before DB hit).

#### P6-6.1.4 — Get Organization

**Given** Org `org_acme01` existant.
**When** caller (cluster-admin OR `organization:org_acme01#viewer` user) invokes `OrganizationService.Get(id="org_acme01")`.
**Then** sync response `Organization{id:org_acme01, name:..., domain_claim:null, saml_configured:false, scim_enabled:false}`.
**And** `Get` НЕ возвращает sensitive: `scim_token_hash` (always omitted в proto serialization; proto field номера выше нет такого).

#### P6-6.1.5 — Get Organization NOT_FOUND

**When** caller invokes `Get(id="org_does_not_exist_xxx")`.
**Then** sync error gRPC `NOT_FOUND`, message `"Organization 'org_does_not_exist_xxx' not found"`.

#### P6-6.1.6 — Update Organization happy-path

**Given** Org `org_acme01` existant. Caller — `organization:org_acme01#admin` (через FGA tuple).
**When** caller invokes `Update` со spec:
```json
{
  "id": "org_acme01",
  "update_mask": ["display_name","description"],
  "display_name": "ACME Corporation Holdings",
  "description": "Updated description"
}
```
**Then** Operation done success; returned Organization показывает new values + `updated_at` ≠ created_at.
**And** outbox audit row `iam.organization.updated`.

#### P6-6.1.7 — Update Organization with immutable field в update_mask → INVALID_ARGUMENT

**Given** Org `org_acme01` existant.
**When** caller invokes `Update` со `update_mask=["name"]` AND `name="renamed"`.
**Then** Operation done error gRPC `INVALID_ARGUMENT`, message YC-style: `"'name' is immutable after Organization.Create"`.
**And** **NO** DB write occurs.

#### P6-6.1.8 — Update Organization unknown field in update_mask → INVALID_ARGUMENT

**Given** Org `org_acme01` existant.
**When** caller invokes `Update` со `update_mask=["unknown_field"]`.
**Then** Operation error gRPC `INVALID_ARGUMENT`, `"unknown field 'unknown_field' in update_mask"`.

#### P6-6.1.9 — Delete Organization with no accounts — success

**Given** Org `org_solo01` existant; нет `accounts WHERE organization_id='org_solo01'`.
**When** cluster-admin invokes `Delete(id="org_solo01")`.
**Then** Operation done success.
**And** DB row removed from `organizations`.
**And** cascade `organization_domain_proofs` removed (FK CASCADE).
**And** **NOT** cascade `users` / `accounts` — accounts уже NULL (нет binding).
**And** FGA tuple `organization:<org>#owner@user:...` removed via outbox.
**And** audit `iam.organization.deleted`.

#### P6-6.1.10 — Delete Organization with bound accounts → FAILED_PRECONDITION

**Given** Org `org_corp01` существует; есть `accounts WHERE organization_id='org_corp01'` (≥1 row).
**When** cluster-admin invokes `Delete(id="org_corp01")`.
**Then** Operation error gRPC `FAILED_PRECONDITION`, message `"organization 'org_corp01' has 3 bound accounts; unbind them first via InternalOrganizationService.UnbindAccount"`.
**And** SQLSTATE `23503` caught from `accounts_organization_fk`, mapped to `FAILED_PRECONDITION`.

#### P6-6.1.11 — List Organizations — cluster-admin sees all

**Given** Orgs `org_a01`, `org_b02`, `org_c03` existant. Caller = cluster-admin.
**When** caller invokes `List(page_size=10)`.
**Then** response содержит 3 Organizations (cluster-admin sees-all через FGA ListObjects).

#### P6-6.1.12 — List Organizations — non-admin user sees only own

**Given** Orgs `org_a01`, `org_b02`. User `usr_alice01` имеет FGA tuple `organization:org_a01#viewer@user:usr_alice01` (только в Org A).
**When** caller (Hydra JWT `sub=usr_alice01`) invokes `List`.
**Then** response содержит только `org_a01`; `org_b02` НЕ в результате.
**And** ListObjects FGA call возвращает `["organization:org_a01"]`; SQL filter `WHERE id = ANY($1)`.

#### P6-6.1.13 — List Organizations — anonymous → empty list

**Given** anonymous request (no JWT).
**When** caller invokes `List`.
**Then** sync error gRPC `UNAUTHENTICATED` (api-gateway rejects before reaching iam).

### 6.2 Domain claim DNS-TXT verification (P6-6.2)

#### P6-6.2.1 — StartDomainVerification happy-path

**Given** Org `org_acme01` existant. Caller — `organization:org_acme01#admin`.
**When** caller invokes `StartDomainVerification(org_id="org_acme01", domain_claim="acme.com")`.
**Then** Operation done success; returned `Organization` shows:
  - `domain_claim = "acme.com"`
  - `domain_verification_state = PENDING`
  - `domain_verification_challenge = "kacho-domain-verification=<32 hex chars>"`
**And** DB row updated: `domain_verification_token` set, `domain_verification_started_at` set.
**And** `organization_domain_proofs` row inserted: `{domain, challenge_token, requested_by_user_id, started_at}`.
**And** audit row `iam.organization.domain_verification_started`.
**And** UI shows hint: «Add TXT record at `_kacho-verify.acme.com` = `kacho-domain-verification=<hex>`».

#### P6-6.2.2 — StartDomainVerification — domain already claimed by another Org → ALREADY_EXISTS

**Given** Org `org_other` has `domain_claim="acme.com"` со state=VERIFIED.
**When** caller invokes `StartDomainVerification(org_id="org_mine", domain_claim="acme.com")`.
**Then** Operation error gRPC `ALREADY_EXISTS`, `"domain 'acme.com' is already claimed by another organization"`.
**And** SQLSTATE `23505` from partial UNIQUE `organizations_domain_claim_uniq`.

#### P6-6.2.3 — StartDomainVerification invalid domain syntax → INVALID_ARGUMENT

**Given** Org `org_acme01` existant.
**When** caller invokes `StartDomainVerification(domain_claim="ACME.com")` (uppercase) OR `"acme"` (no dot) OR `".acme.com"` (leading dot) OR 254+ chars.
**Then** Operation error gRPC `INVALID_ARGUMENT`, `"Illegal argument 'domain_claim': must be lowercase RFC 1035-compliant domain"`.

#### P6-6.2.4 — VerifyDomain happy-path

**Given** Org `org_acme01` имеет `domain_verification_state=PENDING`, `domain_verification_token="kacho-domain-verification=abc123"`.
**And** Test mock DNS resolver returns `["kacho-domain-verification=abc123"]` для query `_kacho-verify.acme.com`.
**When** caller invokes `VerifyDomain(org_id="org_acme01")`.
**Then** Operation done success; returned Organization shows:
  - `domain_verification_state = VERIFIED`
  - `domain_verified_at` set
**And** DB row updated.
**And** `organization_domain_proofs` row updated: `verified_at` set, `txt_record_observed` set.
**And** audit row `iam.organization.domain_verified`.
**And** subsequent SP-init lookup `lookupOrganizationByDomain(acme.com)` теперь returns this org.

#### P6-6.2.5 — VerifyDomain TXT record missing → FAILED_PRECONDITION

**Given** Org `org_acme01` имеет `domain_verification_state=PENDING`.
**And** Test mock DNS resolver returns `[]` (no TXT records).
**When** caller invokes `VerifyDomain(org_id="org_acme01")`.
**Then** Operation error gRPC `FAILED_PRECONDITION`, `"domain 'acme.com' TXT record not found at _kacho-verify.acme.com or does not match challenge"`.
**And** state stays PENDING (no transition).
**And** `organization_domain_proofs` row updated: `failed_at` set, `failure_reason="no_txt_records"`.

#### P6-6.2.6 — VerifyDomain TXT record mismatch → FAILED_PRECONDITION

**Given** Org `org_acme01` state=PENDING, token=`"kacho-domain-verification=abc123"`.
**And** Test mock DNS resolver returns `["kacho-domain-verification=WRONG"]`.
**When** caller invokes `VerifyDomain`.
**Then** Operation error gRPC `FAILED_PRECONDITION`, `"... does not match challenge"`.
**And** `organization_domain_proofs` row updated: `failure_reason="value_mismatch"`, `txt_record_observed="kacho-domain-verification=WRONG"`.

#### P6-6.2.7 — VerifyDomain when state=UNVERIFIED → FAILED_PRECONDITION

**Given** Org никогда не initiated verification (state=UNVERIFIED, no token).
**When** caller invokes `VerifyDomain`.
**Then** Operation error gRPC `FAILED_PRECONDITION`, `"no pending verification; call StartDomainVerification first"`.

#### P6-6.2.8 — VerifyDomain when challenge expired (>7 days) → FAILED_PRECONDITION

**Given** Org state=PENDING, `domain_verification_started_at` = now - 8 days.
**When** caller invokes `VerifyDomain`.
**Then** Operation error gRPC `FAILED_PRECONDITION`, `"verification challenge expired; restart via StartDomainVerification"`.
**And** state stays PENDING (admin может re-Start чтобы получить fresh token).

#### P6-6.2.9 — RevokeDomainVerification — admin manual reset

**Given** Org `org_acme01` state=VERIFIED, `domain_claim="acme.com"`.
**When** cluster-admin invokes `RevokeDomainVerification(org_id="org_acme01")`.
**Then** Operation done; state → REVOKED; `domain_claim` остаётся в row (для audit history), но partial UNIQUE index больше не matches (WHERE state IN pending,verified).
**And** subsequent SP-init `lookupOrganizationByDomain(acme.com)` returns NOT_FOUND.
**And** another Org может теперь claim `acme.com` через StartDomainVerification.

### 6.3 SCIM /Users endpoint (P6-6.3)

#### P6-6.3.1 — POST /scim/v2/Users — create user happy-path

**Given** Org `org_acme01` has:
  - `domain_verification_state=VERIFIED`, `domain_claim=acme.com`
  - `default_account_id=acc_acme_main`
  - `initial_role_id=rol_org_member`
  - `scim_token_hash` populated (issued earlier).
**And** caller — SCIM client with `Authorization: Bearer <plaintext that hashes to org's scim_token_hash>`.
**And** `users` имеет 0 rows для email "alice@acme.com".

**When** caller sends:
```http
POST /scim/v2/Users HTTP/1.1
Host: api.kacho.cloud
Authorization: Bearer abc123...
Content-Type: application/scim+json

{
  "schemas":["urn:ietf:params:scim:schemas:core:2.0:User"],
  "userName": "alice@acme.com",
  "externalId": "okta-abc123",
  "active": true,
  "name": { "givenName": "Alice", "familyName": "Doe" },
  "emails": [ { "value": "alice@acme.com", "type": "work", "primary": true } ]
}
```

**Then** response:
```http
HTTP/1.1 201 Created
Content-Type: application/scim+json
Location: https://api.kacho.cloud/scim/v2/Users/usr_...

{
  "schemas":["urn:ietf:params:scim:schemas:core:2.0:User"],
  "id": "usr_...",
  "externalId": "okta-abc123",
  "userName": "alice@acme.com",
  "active": true,
  "name": { "givenName": "Alice", "familyName": "Doe" },
  "emails": [{"value":"alice@acme.com","type":"work","primary":true}],
  "meta": {
    "resourceType": "User",
    "created": "2026-05-19T...",
    "lastModified": "2026-05-19T...",
    "location": "https://api.kacho.cloud/scim/v2/Users/usr_..."
  }
}
```
**And** new `users` row exists: `kratos_identity_id` populated (Kratos identity created), `account_id=acc_acme_main`, `status='ACTIVE'`.
**And** `scim_user_mappings` row inserted: `{organization_id:org_acme01, scim_external_id:"okta-abc123", user_id:usr_..., scim_active:true}`.
**And** `access_bindings` row inserted: `{subject_user_id:usr_..., role_id:rol_org_member, resource_account_id:acc_acme_main, status:ACTIVE, granted_by:'system_scim'}`.
**And** FGA outbox writes: `account:acc_acme_main#viewer@user:usr_...` (per role's permission scope).
**And** CAEP outbox: `{event_type:"users.provisioned", payload:{user_id, org_id, source:"scim", external_id}}`.
**And** audit outbox: `iam.scim.user_created`.

#### P6-6.3.2 — POST /scim/v2/Users — duplicate externalId → 409 Conflict

**Given** Org `org_acme01`; `scim_user_mappings` уже has row `{organization_id:org_acme01, scim_external_id:"okta-abc123", scim_active:true}`.
**When** caller POSTs `/scim/v2/Users` со same `externalId="okta-abc123"`.
**Then** response:
```http
HTTP/1.1 409 Conflict
Content-Type: application/scim+json

{
  "schemas":["urn:ietf:params:scim:api:messages:2.0:Error"],
  "status": "409",
  "scimType": "uniqueness",
  "detail": "externalId 'okta-abc123' already exists in organization"
}
```
**And** SQLSTATE `23505` from `scim_user_mappings_org_external_active_uniq`, mapped to 409 + scimType=uniqueness.

#### P6-6.3.3 — POST /scim/v2/Users — restore inactive mapping (resurrect)

**Given** Org `org_acme01`; `scim_user_mappings` has row `{organization_id:org_acme01, scim_external_id:"okta-abc123", scim_active:false}` (был DELETE'ed раньше).
**When** caller POSTs `/scim/v2/Users` со same `externalId="okta-abc123"`.
**Then** response 201 Created (NOT 409); handler:
  - UPDATEs `scim_user_mappings SET scim_active=true, last_scim_sync_at=now()` для inactive row;
  - UPDATEs `users SET status='ACTIVE' WHERE id=<mapped user_id>`;
  - re-INSERTs `access_binding` если был revoked; OR UPDATEs status='ACTIVE'.
**And** CAEP outbox: `users.provisioned` event (re-activation).

#### P6-6.3.4 — PATCH /scim/v2/Users/{id} — partial update

**Given** Org `org_acme01`; user `usr_alice01` existant; SCIM mapping active.
**When** caller PATCHes:
```http
PATCH /scim/v2/Users/usr_alice01
Content-Type: application/scim+json

{
  "schemas":["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
  "Operations":[
    { "op":"replace", "path":"name.givenName", "value":"Alicia" },
    { "op":"add", "path":"emails", "value":[{"value":"alicia.alt@acme.com","type":"work"}] }
  ]
}
```
**Then** response 200 OK; returned SCIMUser shows updated `name.givenName`, added email.
**And** DB row `users` updated; `kratos_identities` updated (через Kratos admin API).
**And** audit `iam.scim.user_updated`.

#### P6-6.3.5 — DELETE /scim/v2/Users/{id} — soft-delete + cascade

**Given** Org `org_acme01`; user `usr_alice01` имеет 3 active access_bindings + FGA tuples.
**When** caller invokes `DELETE /scim/v2/Users/usr_alice01`.
**Then** response 204 No Content.
**And** TX (per §2.8):
  - `users.status='BLOCKED'`;
  - `scim_user_mappings.scim_active=false`;
  - 3 × `access_bindings.status='REVOKED'`;
  - FGA outbox: 3 × delete-tuple-ops;
  - CAEP outbox: `users.deactivated`;
  - audit: `iam.scim.user_deleted`.
**And** subsequent `GET /scim/v2/Users/usr_alice01` returns 404 (mapping inactive).
**And** GUI lookup для user shows status=BLOCKED.
**And** within ~30s (LISTEN/NOTIFY + cache TTL), vpc-service / compute-service / lb-service Check для usr_alice01 returns deny (FGA tuples removed).

#### P6-6.3.6 — GET /scim/v2/Users — list with filter eq

**Given** Org `org_acme01` имеет 3 users: alice@acme.com, bob@acme.com, charlie@acme.com.
**When** caller GETs `/scim/v2/Users?filter=userName eq "alice@acme.com"`.
**Then** response 200; `Resources` contains только `alice@acme.com`; `totalResults=1`, `itemsPerPage=1`, `startIndex=1`.
**And** SCIM filter parsed по RFC 7644; SQL: `SELECT ... FROM users JOIN scim_user_mappings ... WHERE scim_user_mappings.organization_id=$1 AND users.email=$2 AND scim_active=true`.

#### P6-6.3.7 — Cross-org isolation: Org A cannot DELETE Org B user

**Given** Org A `org_acme01` with SCIM token hash `hash_a`; Org B `org_widget02` with token hash `hash_b`. User `usr_bob01` exists in Account `acc_widget_main` (Org B). SCIM mapping `{organization_id:org_widget02, scim_external_id:"okta-bob", user_id:usr_bob01}`.
**When** attacker with Org A bearer token (hashes to `hash_a`) sends `DELETE /scim/v2/Users/usr_bob01`.
**Then** response 404 Not Found (NOT 403; SCIM convention — pretend not exist для cross-tenant). Body:
```json
{"schemas":["...:Error"],"status":"404","detail":"User not found"}
```
**And** DB query: `SELECT ... FROM scim_user_mappings WHERE organization_id=$1 AND user_id=$2 AND scim_active=true` — но `$1=org_acme01`, `$2=usr_bob01` → no row → 404.
**And** **NO** mutation occurs on usr_bob01.
**And** audit row inserted: `iam.scim.cross_org_attempt_denied` (security event).
**And** integration test `scim_users_integration_test.go::TestCrossOrgIsolationDelete` — concurrent goroutines from Org A trying Org B users — verify zero successful mutations.

#### P6-6.3.8 — Cross-org isolation: same externalId in two Orgs — independent mappings

**Given** Orgs A and B; SCIM client of Org A POSTs externalId="alice"; SCIM client of Org B POSTs externalId="alice".
**When** both succeed concurrently.
**Then** Two distinct `scim_user_mappings` rows: `{A, "alice", usr_x}` и `{B, "alice", usr_y}`; both scim_active=true.
**And** UNIQUE `(organization_id, scim_external_id) WHERE scim_active=true` НЕ violated (different org_id).
**And** `usr_x` и `usr_y` — distinct users (potentially same Kratos identity if same email — but separate user-rows per Org's account, per D-15 multi-org).

#### P6-6.3.9 — GET /scim/v2/Users — pagination

**Given** Org `org_acme01` has 250 users.
**When** caller GETs `/scim/v2/Users?startIndex=1&count=100`.
**Then** response: `{totalResults:250, itemsPerPage:100, startIndex:1, Resources:[<100 users>]}`.
**When** caller GETs `/scim/v2/Users?startIndex=101&count=100`.
**Then** response shows next 100; `startIndex=101`.
**When** caller GETs `/scim/v2/Users?startIndex=201&count=100`.
**Then** response shows last 50; `itemsPerPage=50`.

#### P6-6.3.10 — GET /scim/v2/Users — sort

**Given** Org `org_acme01` has 5 users.
**When** caller GETs `/scim/v2/Users?sortBy=userName&sortOrder=descending&count=10`.
**Then** Resources содержит 5 users в reverse-alphabetical order по userName.

#### P6-6.3.11 — PUT /scim/v2/Users/{id} — replace (full PUT)

**Given** Org `org_acme01`; user `usr_alice01` existant.
**When** caller PUTs full SCIM User body (всё кроме `id`).
**Then** response 200 OK; user's all SCIM-managed fields replaced (including `active`, `name`, `emails`). Fields НЕ присутствующие в body → reset to default (e.g. emails=[] если PUT body не имеет emails).
**And** audit `iam.scim.user_replaced`.

#### P6-6.3.12 — GET /scim/v2/Users — filter with co (contains)

**Given** Org `org_acme01` users include alice@acme.com, bob.alpha@acme.com, charlie@acme.com.
**When** caller GETs `/scim/v2/Users?filter=userName co "alpha"`.
**Then** response Resources = [bob.alpha@acme.com]; totalResults=1.

#### P6-6.3.13 — GET /scim/v2/Users — invalid filter → 400 invalidFilter

**When** caller GETs `/scim/v2/Users?filter=userName % "alice"` (invalid operator).
**Then** response:
```http
HTTP/1.1 400 Bad Request

{"schemas":["...:Error"],"status":"400","scimType":"invalidFilter","detail":"unrecognized operator '%' in filter expression"}
```

### 6.4 SCIM /Groups endpoint (P6-6.4)

#### P6-6.4.1 — POST /scim/v2/Groups — create group

**Given** Org `org_acme01`; default_account_id=acc_acme_main.
**When** caller POSTs:
```json
{
  "schemas":["urn:ietf:params:scim:schemas:core:2.0:Group"],
  "displayName": "Engineering",
  "externalId": "okta-grp-eng",
  "members": [
    { "value": "usr_alice01", "type": "User" },
    { "value": "usr_bob01",   "type": "User" }
  ]
}
```
**Then** response 201; new `groups` row `{name:"Engineering", account_id:acc_acme_main, scim_managed:true, external_id:"okta-grp-eng"}`.
**And** 2 × `group_members` rows.
**And** FGA outbox writes `group:<id>#member@user:usr_alice01` + `...@user:usr_bob01`.

#### P6-6.4.2 — PATCH /scim/v2/Groups/{id} — add member

**Given** Group `grp_eng01` (SCIM-managed) с 2 members.
**When** caller PATCHes:
```json
{"Operations":[{"op":"add","path":"members","value":[{"value":"usr_charlie03","type":"User"}]}]}
```
**Then** response 200; new `group_members` row.
**And** FGA outbox: `group:grp_eng01#member@user:usr_charlie03`.

#### P6-6.4.3 — PATCH /scim/v2/Groups/{id} — remove member

**Given** Group `grp_eng01` с member usr_alice01.
**When** caller PATCHes:
```json
{"Operations":[{"op":"remove","path":"members[value eq \"usr_alice01\"]"}]}
```
**Then** response 200; `group_members` row deleted.
**And** FGA outbox delete-tuple.

#### P6-6.4.4 — Cross-org isolation Groups

**Given** Org A's SCIM bearer; Group `grp_widget01` of Org B.
**When** attacker GETs `/scim/v2/Groups/grp_widget01` с Org A bearer.
**Then** response 404 (cross-org isolation; same as P6-6.3.7).

#### P6-6.4.5 — Nested groups — group as member

**Given** Orgs A; SCIM-managed groups `grp_all_eng` and `grp_backend` (subgroup).
**When** caller PATCHes `grp_all_eng` adding member `{value:"grp_backend",type:"Group"}`.
**Then** response 200; `group_members` row с `member_group_id="grp_backend"` (mutual-exclusive CHECK passes).
**And** FGA outbox: `group:grp_all_eng#member@group:grp_backend#member` (relation-on-relation).
**And** subsequent FGA Check «is usr_bob (member of grp_backend) member of grp_all_eng?» → allow.

#### P6-6.4.6 — Group max nesting depth = 5

**Given** Group hierarchy 5-deep already exists.
**When** caller tries adding 6-th level group.
**Then** response 400; SCIM error `invalidValue` with detail `"max group nesting depth (5) exceeded"`.
**And** DB CHECK via recursive CTE rejects.

#### P6-6.4.7 — SCIM-managed group не редактируется через kacho-iam GroupService.Update

**Given** Group `grp_eng01` имеет `scim_managed=true`.
**When** caller invokes `GroupService.Update(id=grp_eng01, display_name="Renamed")` через regular gRPC (не SCIM).
**Then** Operation error `FAILED_PRECONDITION`, `"group is SCIM-managed; modify via /scim/v2/Groups/<id>"`.

### 6.5 SCIM /Bulk endpoint (P6-6.5)

#### P6-6.5.1 — Bulk happy-path 3 operations

**Given** Org `org_acme01`.
**When** caller POSTs `/scim/v2/Bulk`:
```json
{
  "schemas":["urn:ietf:params:scim:api:messages:2.0:BulkRequest"],
  "failOnErrors": 1,
  "Operations":[
    { "method":"POST", "path":"/Users", "bulkId":"a", "data":{...} },
    { "method":"POST", "path":"/Users", "bulkId":"b", "data":{...} },
    { "method":"POST", "path":"/Groups", "bulkId":"c", "data":{members:[{value:"bulkId:a",type:"User"},{value:"bulkId:b",type:"User"}]} }
  ]
}
```
**Then** response 200; BulkResponse with 3 per-op statuses (all 201).
**And** Resolved bulkId references: Group ссылается на real user_ids созданных в a и b.
**And** 2 users + 1 group + members + FGA tuples — all persisted.

#### P6-6.5.2 — Bulk failOnErrors=1 — abort on first failure

**Given** Org `org_acme01`. SCIM mapping `okta-existing` already exists.
**When** caller POSTs Bulk с 5 ops; 3-я op POSTs `/Users` с `externalId="okta-existing"` (will fail duplicate).
**Then** response BulkResponse:
  - Ops 1, 2 — status 201 (succeeded)
  - Op 3 — status 409 with scimType=uniqueness
  - Ops 4, 5 — **НЕ** outomeded (aborted)
**And** DB shows only 2 new users (ops 1, 2 committed; ops 3-5 not started or rolled back).

#### P6-6.5.3 — Bulk failOnErrors=0 — continue on errors

**Given** Org `org_acme01`. 1 existing externalId.
**When** caller POSTs Bulk failOnErrors=0 с 5 ops; 3-я op duplicate.
**Then** response BulkResponse with 5 op statuses; ops 1,2,4,5 — 201; op 3 — 409. All 4 successful ops persisted.

#### P6-6.5.4 — Bulk exceeds maxOperations (100)

**When** caller POSTs Bulk с 101 ops.
**Then** response 400 `tooMany`, detail `"max bulk operations (100) exceeded"`.

### 6.6 SCIM discovery endpoints (P6-6.6)

#### P6-6.6.1 — GET /scim/v2/Me

**Given** SCIM bearer authenticated; resolved к `service_account:sva_scim_org_acme01`.
**When** caller GETs `/scim/v2/Me`.
**Then** response 200 SCIM User schema-ish payload representing the **service-account principal** (not a User). Body:
```json
{
  "schemas":["urn:ietf:params:scim:schemas:core:2.0:User"],
  "id": "sva_scim_org_acme01",
  "userName": "scim-bot@org_acme01",
  "active": true,
  "meta": {"resourceType":"ServiceProvider","location":"https://api.kacho.cloud/scim/v2/Me"}
}
```

#### P6-6.6.2 — GET /scim/v2/ServiceProviderConfig

**When** anonymous caller (no bearer) GETs `/scim/v2/ServiceProviderConfig`.
**Then** response 200 with SCIM ServiceProviderConfig:
```json
{
  "schemas":["urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"],
  "documentationUri": "https://docs.kacho.cloud/iam/scim",
  "patch": {"supported": true},
  "bulk": {"supported": true, "maxOperations": 100, "maxPayloadSize": 1048576},
  "filter": {"supported": true, "maxResults": 200},
  "changePassword": {"supported": false},
  "sort": {"supported": true},
  "etag": {"supported": false},
  "authenticationSchemes": [{"type":"oauthbearertoken","name":"Bearer","description":"Per-org SCIM bearer token; obtain via OrganizationService.IssueSCIMToken"}]
}
```
**Note**: `/ServiceProviderConfig`, `/ResourceTypes`, `/Schemas` — public (no auth) per RFC 7644 §4.

#### P6-6.6.3 — GET /scim/v2/ResourceTypes

**When** caller GETs `/scim/v2/ResourceTypes`.
**Then** response 200; lists `[User, Group]` with schema references.

#### P6-6.6.4 — GET /scim/v2/Schemas

**When** caller GETs `/scim/v2/Schemas`.
**Then** response 200; lists Core User schema + Core Group schema + EnterpriseUser extension.

### 6.7 SAML SP-init flow (P6-6.7)

#### P6-6.7.1 — Org admin uploads SAML metadata XML

**Given** Org `org_acme01` имеет `domain_verification_state=VERIFIED`.
**When** Org admin uploads SAML metadata XML (containing IdP entity_id, SSO URL, X.509 signing cert):
```http
POST /v1/iam/organizations/org_acme01:uploadSAMLMetadata
Content-Type: application/json

{ "saml_metadata_xml": "<EntityDescriptor xmlns=\"urn:oasis:names:tc:SAML:2.0:metadata\">...</EntityDescriptor>" }
```
**Then** Operation done success; returned Organization shows `saml_configured=true`, `saml_acs_url="https://api.kacho.cloud/api/oauth/saml"`, `saml_entity_id="<extracted from XML>"`, `saml_metadata_uploaded_at` set.
**And** TX:
  - kacho-iam `UPDATE organizations SET saml_metadata_xml=$1, saml_acs_url=$2, saml_entity_id=$3, saml_metadata_uploaded_at=now()`.
  - kacho-iam calls Jackson Admin API `POST /api/v1/sso/connections` (or `PATCH` if connection already exists для этого tenant) с extracted metadata.
  - if Jackson API returns 4xx/5xx → Operation error `INTERNAL`, `"failed to register SAML connection with Jackson: <details>"`; kacho-iam rolls back saml_metadata_xml column update (TX-level).
**And** audit `iam.organization.saml_uploaded`.

#### P6-6.7.2 — SP-init redirects to IdP

**Given** Org `org_acme01` имеет `domain_verification_state=VERIFIED, saml_configured=true`.
**When** anonymous browser hits `GET /iam/login` → enters email `alice@acme.com` → UI calls `GET /v1/iam/organizations:lookupByDomain?domain=acme.com` → gets `{org_id:org_acme01, saml_configured:true}` → browser 302's to `/oidc/auth?org=org_acme01`.
**Then** Kratos serves OIDC selector page → resolves `kacho_jackson_org_acme01` connector → 302 to Jackson `/api/oauth/authorize?tenant=org_acme01&product=kacho&response_type=code&redirect_uri=<Kratos callback>`.
**And** Jackson generates SAMLRequest → 302's к customer IdP's SSO URL (extracted from metadata).
**And** integration test simulates Mock IdP returning signed SAMLResponse.

#### P6-6.7.3 — SAML response validated → Kratos session issued

**Given** browser получил SAMLResponse from Mock IdP (signed by configured cert; `nameId="alice@acme.com"`, `email="alice@acme.com"`, `firstName="Alice"`, `lastName="Doe"`).
**When** browser auto-POSTs SAMLResponse to Jackson ACS `/api/oauth/saml`.
**Then** Jackson validates signature → issues OIDC ID-token к Kratos callback.
**And** Kratos completes OIDC flow → creates/reuses Kratos identity → calls `post_oidc_registration` webhook → `InternalSAMLService.JITProvision` (см. §6.9).
**And** Kratos session cookie set; Hydra issues access token after final redirect.
**And** browser ends up at `https://app.kacho.cloud/` logged in as Alice.

#### P6-6.7.4 — SAML response with invalid signature → 401

**Given** Mock IdP signs SAMLResponse с wrong cert (not matching saml_metadata_xml).
**When** browser POSTs to Jackson ACS.
**Then** Jackson returns 401 → redirects к Kratos error page → user sees «authentication failed».
**And** audit row `iam.saml.signature_invalid` (Jackson logs propagated к kacho-iam via Jackson webhook — out-of-scope; Phase 6 settles for Jackson-local log).

### 6.8 SAML IdP-init flow (P6-6.8)

#### P6-6.8.1 — Okta dashboard tile click

**Given** Org `org_acme01` has SAML configured. Customer Okta admin set up «Kachō» app tile с target SAML SSO URL = `https://api.kacho.cloud/api/oauth/saml-idp-init?tenant=org_acme01`.
**When** Alice clicks tile в Okta dashboard.
**Then** Okta IdP generates unsolicited SAMLResponse → auto-POSTs to Jackson endpoint.
**And** Jackson handles IdP-init (no prior SAMLRequest); validates assertion; issues OIDC ID-token; completes via Kratos webhook path → Kachō session created.

#### P6-6.8.2 — IdP-init with RelayState

**Given** Okta tile has RelayState `"https://app.kacho.cloud/iam/users"`.
**When** Alice clicks tile → IdP-init flow → after Kratos session created, Kratos redirects к RelayState target.
**Then** browser lands at `/iam/users` (not default).

### 6.9 JIT provisioning без pre-SCIM (P6-6.9)

#### P6-6.9.1 — First SAML signin, no SCIM mapping — create User

**Given** Org `org_acme01` with VERIFIED domain `acme.com`, `default_account_id=acc_acme_main`, `initial_role_id=rol_org_member`. **No** SCIM mapping for "alice@acme.com". **No** existing Kratos identity for that email.
**When** Alice completes SAML SP-init signin (§6.7).
**Then** Kratos creates new identity (kratos_identity_id=`kti_xyz`) → `post_oidc_registration` webhook hits `InternalSAMLService.JITProvision`:
  - resolve org by email domain `acme.com` → `org_acme01`;
  - validate `default_account_id` is set → `acc_acme_main`;
  - validate `initial_role_id` is set → `rol_org_member`;
  - TX: INSERT `users (kratos_identity_id=kti_xyz, account_id=acc_acme_main, status='ACTIVE', email='alice@acme.com', name=...)`;
  - INSERT `access_bindings (subject_user_id=usr_..., role_id=rol_org_member, resource_account_id=acc_acme_main, status='ACTIVE', granted_by='system_jit_provision')`;
  - **DO NOT** insert `scim_user_mappings` (это не SCIM-provisioned);
  - FGA outbox: `account:acc_acme_main#viewer@user:usr_...`;
  - CAEP outbox: `users.provisioned, payload:{source:"jit_saml"}`;
  - audit: `iam.jit.user_provisioned`.
**And** webhook response `JITProvisionResponse{user_id:usr_..., account_id:acc_acme_main, org_id:org_acme01, created_now:true, assigned_role_ids:[rol_org_member]}`.
**And** Kratos completes session; Alice lands in Kachō UI как usual user.

#### P6-6.9.2 — Repeat SAML signin — reuse user

**Given** Alice уже provisioned (P6-6.9.1).
**When** Alice signs in again через SAML.
**Then** Kratos reuses existing identity (same `kratos_identity_id`); `post_oidc_registration` webhook **не** срабатывает (Kratos hook fires только on first registration); session created с existing user.
**And** **NO** new DB writes.

#### P6-6.9.3 — JIT fails when default_account_id is NULL

**Given** Org `org_acme01` имеет `default_account_id=NULL`.
**When** SAML signin triggers JIT.
**Then** `InternalSAMLService.JITProvision` returns gRPC `FAILED_PRECONDITION`, `"organization 'org_acme01' has no default_account_id configured; configure via OrganizationService.Update"`.
**And** Kratos webhook returns error → Kratos invalidates the half-created identity (or marks for cleanup); session NOT issued; user sees error page.
**And** audit `iam.jit.failed`, reason=`no_default_account`.

#### P6-6.9.4 — Multi-org user — same person signs in via Org A and Org B SAML

**Given** Org A `org_acme01` and Org B `org_widget02` both with verified domains acme.com and widget.io respectively. Existing user-row `usr_alice01` for alice@acme.com in `acc_acme_main` (Org A). **No** user-row for alice@widget.io (different email).
**When** Alice signs in via Org B SAML using email alice@widget.io.
**Then** Kratos creates **new** identity (`kti_alice_b`) — different email = different Kratos identity.
**And** JITProvision creates new user-row `usr_alice02` в `acc_widget_main` (Org B's default account); separate from `usr_alice01`.
**And** Alice now has 2 user-rows (one per Org) backed by 2 different Kratos identities. **Это normal** for B2B multi-org.
**And** **Alt scenario**: same email alice@acme.com used by Org A SCIM **AND** Org B SCIM (each posts the same userName) — same Kratos identity reused, **different** user-rows: P6-6.3.8 covers (different `scim_user_mappings`, different `account_id`).

### 6.10 SCIM bearer token rotation (P6-6.10)

#### P6-6.10.1 — Issue new token rotates old

**Given** Org `org_acme01` имеет `scim_token_hash=hash_v1` issued earlier; SCIM client uses token `bearer_v1`.
**When** Org admin calls `IssueSCIMToken(org_id="org_acme01")` again.
**Then** sync response `IssueSCIMTokenResponse{scim_bearer_token:"bearer_v2", issued_at:now()}`.
**And** DB row updated: `scim_token_hash=hash_v2, scim_token_issued_at=now()`.
**And** old hash `hash_v1` overwritten — **not** retained as previous.
**And** audit row `iam.scim_token_rotated, actor_id:<admin>, target_id:org_acme01`.
**And** CAEP outbox: `organization.scim_token_rotated` event.

#### P6-6.10.2 — Old token rejected after rotation

**Given** post-rotation state (P6-6.10.1).
**When** SCIM client sends request с old `bearer_v1`.
**Then** response 401:
```json
{"schemas":["...:Error"],"status":"401","detail":"invalid or revoked SCIM bearer token"}
```
**And** middleware: SHA-256(bearer_v1) does not match any active `scim_token_hash` → reject.

#### P6-6.10.3 — Revoke token

**Given** Org `org_acme01` имеет active SCIM token.
**When** admin invokes `RevokeSCIMToken(org_id="org_acme01")`.
**Then** Operation done success; DB `UPDATE organizations SET scim_token_revoked_at=now()`.
**And** subsequent SCIM requests возвращают 401.
**And** Issue новый — снова работает (rotation = revoke + issue в одной операции, semantic).

### 6.11 Lifecycle webhook cascade (P6-6.11)

#### P6-6.11.1 — SCIM DELETE user → access_bindings revoked + FGA tuples removed + CAEP emitted

См. P6-6.3.5 (already covered).

#### P6-6.11.2 — SCIM DELETE user → vpc/compute/lb checks deny within 30s

**Given** Alice имеет 3 access_bindings (vpc_network admin, compute_instance editor, lb_target_group viewer) + corresponding FGA tuples + cached entries в corelib/authz on vpc/compute/lb pods.
**When** SCIM DELETE /Users/usr_alice01.
**Then** access_bindings.status set REVOKED; FGA outbox emits 3 delete-ops; FGA writes apply → kacho_iam_subjects NOTIFY fires с `subject_id=usr_alice01`.
**And** within 100ms все corelib/authz subscriber pods (vpc, compute, lb) receive NOTIFY → invalidate cache entries for usr_alice01.
**And** subsequent Alice request к vpc service «list networks» → corelib/authz ListAllowedIDs → FGA returns empty → response empty.
**And** subsequent Alice request к compute «get instance» → corelib/authz Check → FGA returns no → gRPC `PERMISSION_DENIED`.

#### P6-6.11.3 — SCIM Group member remove → FGA tuple removed

**Given** Alice is member of group `grp_eng01`; group имеет FGA tuple `account#editor@group:grp_eng01#member`; effective Alice access through group.
**When** SCIM PATCH /Groups/grp_eng01 remove Alice.
**Then** `group_members` row deleted; FGA outbox emits delete-tuple `group:grp_eng01#member@user:usr_alice01`.
**And** within 100ms cache invalidates; subsequent Alice request denied.
**And** CAEP outbox: `groups.member_removed` event.

#### P6-6.11.4 — CAEP outbox-row persisted for Phase 8 drainer

**Given** Phase 6 ops emit `users.provisioned`, `users.deactivated`, `groups.member_added`, `groups.member_removed`, `organization.scim_token_rotated` rows в `caep_outbox`.
**When** Phase 6 Acceptance — observability check.
**Then** `SELECT count(*) FROM caep_outbox WHERE event_type LIKE 'users.%' OR event_type LIKE 'groups.%' OR event_type LIKE 'organization.%'` ≥ count of provisioning/deprovisioning operations.
**And** rows have `delivered_at IS NULL` (drainer Phase 8 will set this).
**And** Phase 6 unit test verifies row schema matches Phase 8 drainer expectations.

### 6.12 SAML cert rotation (P6-6.12)

#### P6-6.12.1 — Re-upload metadata XML refreshes Jackson connection

**Given** Org `org_acme01` имеет SAML configured (cert v1 в saml_metadata_xml). Jackson DB stores connection с cert v1.
**When** customer IdP updates cert (v2) → customer admin re-uploads new metadata XML containing cert v2 via `UploadSAMLMetadata`.
**Then** kacho-iam UPDATEs `saml_metadata_xml` + extracts new ACS/entity-id; calls Jackson Admin API `PATCH /api/v1/sso/connections/<id>` с new metadata.
**And** Jackson stores new cert; for ~24h **grace period** Jackson accepts assertions signed by either cert v1 OR cert v2 (this is Jackson-internal feature — Phase 6 relies on it; not own logic).
**And** audit `iam.organization.saml_uploaded`, with `saml_metadata_version=v2`.

#### P6-6.12.2 — Old cert assertions rejected after grace

**Given** SAML cert rotation occurred 25h ago.
**When** Mock IdP sends SAMLResponse signed by old cert v1.
**Then** Jackson returns 401 «signature does not match registered cert»; user sees auth error.

### 6.13 Per-Org SSO config UI (P6-6.13)

#### P6-6.13.1 — UI: SAML metadata XML upload via drag-drop

**Given** UI page `/iam/organizations/org_acme01/sso`.
**When** Org admin drags-drops `okta-metadata.xml` file → UI parses + previews extracted ACS / entity-id → user clicks «Save».
**Then** UI POSTs `/v1/iam/organizations/org_acme01:uploadSAMLMetadata` → Operation completes → UI page refreshes; shows `saml_configured=true`, ACS URL, entity-id.
**And** Playwright test verifies user-flow.

#### P6-6.13.2 — UI: SCIM token issue one-time-show

**Given** UI page `/iam/organizations/org_acme01/scim`. No active token.
**When** Org admin clicks «Issue SCIM Token» → modal opens с warning «This token shown only once; copy now».
**Then** UI calls `IssueSCIMToken` (sync) → receives `bearer_token` → renders в modal с copy-to-clipboard button → upon modal close, raw token cleared from JS memory.
**And** UI page shows `last_issued_at` + token fingerprint (last 4 chars of SHA-256 hash) but never plaintext.

#### P6-6.13.3 — UI: domain verification challenge UI

**Given** UI page `/iam/organizations/org_acme01/domain-verification`. No active claim.
**When** Org admin enters domain «acme.com» → clicks «Start Verification».
**Then** UI calls `StartDomainVerification` → Operation → returned challenge token displayed.
**And** UI shows step-by-step instructions: «Add TXT record at `_kacho-verify.acme.com` with value `kacho-domain-verification=<token>`. Then click Verify.».
**And** «Verify» button → calls `VerifyDomain` → on success, UI updates state badge from PENDING to VERIFIED.

---

## 7. Definition of Done (production-grade)

### 7.1 Functional

- [ ] OrganizationService 12 RPC implemented (P6-6.1.1 thru 6.1.13 happy/negative paths).
- [ ] SCIM /Users endpoints: POST/PUT/PATCH/DELETE/GET-list/GET-single + filter (eq/ne/co/sw/ew/gt/ge/lt/le/pr/and/or/not) + sort + pagination.
- [ ] SCIM /Groups endpoints: POST/PUT/PATCH/DELETE/GET-list/GET-single; nested groups support; SCIM-managed flag.
- [ ] SCIM /Bulk endpoint: failOnErrors=0/1; max 100 ops; bulkId resolution.
- [ ] SCIM /Me + /ResourceTypes + /Schemas + /ServiceProviderConfig discovery endpoints — RFC 7644 §5 compliant.
- [ ] SAML SP-init flow end-to-end (Mock IdP + Jackson + Kratos + JIT).
- [ ] SAML IdP-init flow end-to-end (Mock IdP unsolicited assertion).
- [ ] JIT provisioning без pre-SCIM (P6-6.9.1).
- [ ] Multi-org user (P6-6.9.4).
- [ ] Domain claim DNS-TXT verification (start + verify + revoke).
- [ ] SCIM token rotation + revocation.
- [ ] SCIM lifecycle cascade (DELETE user → access_bindings revoke + FGA tuples remove + CAEP emit + visible deny на vpc/compute/lb).
- [ ] Cross-org isolation (P6-6.3.7) under concurrent load.
- [ ] SAML cert rotation (re-upload XML; Jackson grace period).
- [ ] Per-Org SSO config UI: 5 pages (OrgList, OrgDetail, OrgSSOConfig, DomainVerification, SCIMToken).
- [ ] Cluster-admin can bind/unbind Accounts to Organizations via `InternalOrganizationService`.

### 7.2 Tests / CI

- [ ] integration tests ≥80% coverage on new code (kacho-iam + corelib/scim).
- [ ] `scim/parser_test.go` ≥50 test cases against RFC 7644 §3.4.2 grammar (eq/ne/co/sw/ew/gt/ge/lt/le/pr/and/or/not; nested parens; not-operator; complex expressions).
- [ ] `organization_phase6_integration_test.go` — full CRUD + concurrency races (concurrent Create duplicate name; concurrent StartDomainVerification same domain — ровно одна wins).
- [ ] `scim_users_integration_test.go` — POST/PUT/PATCH/DELETE/list + filter + pagination + sort + cross-org isolation (`TestCrossOrgIsolationDelete` — N concurrent goroutines from Org A trying Org B users — verify zero successful mutations).
- [ ] `scim_groups_integration_test.go` — including nested groups + SCIM-managed flag.
- [ ] `scim_bulk_integration_test.go` — failOnErrors=0 vs 1; bulkId resolution.
- [ ] `scim_filter_concurrency_integration_test.go` — concurrent POSTs same externalId — ровно одна 201, остальные 409.
- [ ] `domain_verification_integration_test.go` — mock DNS resolver; matched/unmatched/expired/revoked paths.
- [ ] `saml_jit_integration_test.go` — Kratos webhook → JITProvision; new user, existing user (idempotent), missing default_account, multi-org.
- [ ] `scim_bearer_authn_integration_test.go` — valid/invalid/revoked/rotated tokens.
- [ ] Newman ≥58 cases (15 organization + 25 SCIM + 10 SAML + 8 cross-org isolation).
- [ ] k6 SCIM load — `scim_load_kac127_phase6.js` — 100 RPS sustained 30min; p95 ≤200ms per RFC implementation note; success-rate ≥99.9%; artifact `k6/results/KAC-127-phase6-scim.md`.
- [ ] Playwright E2E `iam_org_admin_flows.spec.ts` — full happy path UI.
- [ ] Real Okta sandbox SAML SP-init test (real cert; real Okta IdP; real Jackson; CI runs against Okta dev tenant).
- [ ] Real Azure AD sandbox SCIM test (Azure AD provisioning client → kacho /scim/v2/Users → verified persisted).
- [ ] Real Google Workspace SCIM test (similar).
- [ ] golangci-lint passes strict config; gosec passes без waivers; trivy + grype zero High/Critical.
- [ ] SBOM + cosign + SLSA L3 attached.
- [ ] All CI workflows green (`buf-lint`, `buf-breaking`, `kacho-corelib-unit`, `kacho-iam-integration`, `kacho-test-e2e`, `playwright`, `k6-scim`).

### 7.3 Operational

- [ ] Boxyhq Jackson HA (2 replicas) deployed `kacho-deploy/helm/umbrella/templates/jackson-*`.
- [ ] Jackson Postgres DB `kacho_jackson_prod` provisioned.
- [ ] SealedSecret для Jackson API key + Kratos OIDC client_secret.
- [ ] Kratos OIDC connector wired to Jackson (per Org-tenant URL pattern).
- [ ] api-gateway routes `/scim/v2/*` → kacho-iam:9080.
- [ ] Cloudflare WAF rule: allow `/scim/v2/*` from Okta/Azure/Google IP ranges.
- [ ] SCIM rate-limit 100 RPS / Org enforced (in-memory token-bucket).
- [ ] Grafana dashboard «IAM Phase 6 — SSO» panels: SCIM RPS per Org, SCIM error-rate per type (uniqueness/invalidFilter/...), SAML signin rate, JIT-provision rate, domain verifications pending/verified counts.
- [ ] Prometheus metrics:
  - `kacho_iam_scim_request_total{org_id,endpoint,method,status}`
  - `kacho_iam_scim_request_duration_seconds`
  - `kacho_iam_saml_signin_total{org_id,outcome}` (outcome: success, sig_invalid, missing_email, jit_failed)
  - `kacho_iam_jit_provision_total{org_id,outcome}`
  - `kacho_iam_domain_verification_total{state}` (started/verified/failed/revoked)
  - `kacho_iam_organization_total{state}`
  - `kacho_iam_scim_token_rotation_total{org_id}`
  - `kacho_iam_scim_rate_limit_exceeded_total{org_id}`
- [ ] Alert rules:
  - SCIM error-rate >5% / 5min → P2
  - SAML signin failure-rate >10% per Org / 10min → P2
  - JIT provision failures >5% / 5min → P2
  - Jackson healthcheck failing — P1
  - Postgres `kacho_iam` connection pool exhausted — P1
- [ ] Runbooks:
  - `runbooks/scim-token-leaked.md` — incident response для leaked SCIM bearer.
  - `runbooks/saml-cert-rotation.md` — guide для customer admin.
  - `runbooks/jackson-failover.md` — manual failover steps Phase 6 single-region.
  - `runbooks/domain-claim-disputes.md` — operator process if two customers claim same domain.

### 7.4 Security / Compliance

- [ ] OWASP ASVS L3 sub-assessment для SCIM endpoint (V13.2 SAML / V14 OAuth / V8 Data Protection).
- [ ] SAML XML signature validation hardened (Boxyhq Jackson covers — verify via pentest).
- [ ] SCIM bearer token entropy = 256-bit (32 bytes); hashing = SHA-256 (NIST-approved).
- [ ] SCIM-bearer-storage — only hash в DB; plaintext **никогда** не persisted; audit log не contains plaintext.
- [ ] Cross-org isolation — fuzz-tested (Phase 12 will extend; Phase 6 baseline integration test).
- [ ] Domain TXT verification — protected against DNS rebinding (resolver uses fixed TTL; multiple queries within ≥60s window).
- [ ] Rate-limiting per-Org для prevent runaway provisioning (DoS pre-emption).

### 7.5 Documentation

- [ ] User-facing: `docs.kacho.cloud/iam/sso/` — customer admin guide для setting up SAML + SCIM.
- [ ] Admin: `docs.kacho.cloud/admin/iam/organizations.md` — cluster-admin operating procedures.
- [ ] Dev: `docs.kacho.cloud/dev/iam/scim.md` — SCIM endpoint reference.
- [ ] Vault entries: all 11 listed в §1 step 8.
- [ ] `KAC/KAC-127.md` updated: Phase 6 trail; status, PRs, acceptance chek-list items checked.

### 7.6 Code quality (zero tech debt)

- [ ] Zero `// TODO` / `// FIXME` / `// XXX` / `// HACK` (CI grep fails build).
- [ ] Zero «deferred» / «next epic» / «follow-up» в commit messages.
- [ ] Zero `t.Skip(...)` without referenced KAC issue.
- [ ] Zero `Out of scope: ... follow-up` в PR descriptions.

---

## 8. Cross-repo PR chain (рекомендуемый порядок mergeа)

Per workspace `CLAUDE.md` §«Кросс-репо зависимости и порядок выполнения», топологическая сортировка:

1. **`PRO-Robotech/kacho-proto#XX`** — `organization.proto` + `internal_organization.proto` + `internal_saml.proto` + `scim_v2.proto`; regenerated `gen/go/...`; `buf lint`/`breaking` зелёные.
2. **`PRO-Robotech/kacho-corelib#YY`** — `scim/` package + `dns/txt_resolver.go`; unit tests; depends on `replace ../kacho-proto`.
3. **`PRO-Robotech/kacho-iam#ZZ`** — migration `0017` + handlers + repo + integration tests; depends on previous two.
4. **`PRO-Robotech/kacho-deploy#AA`** — Jackson Helm + Kratos OIDC config + Postgres init + api-gateway routes (`/scim/v2`); depends on `kacho-iam`'s new image.
5. **`PRO-Robotech/kacho-api-gateway#BB`** — restmux mounts + scim_bypass middleware; depends on `kacho-iam` proto-gen.
6. **`PRO-Robotech/kacho-ui#CC`** — Org admin pages; depends on `kacho-iam` proto-gen (regenerated TS clients).
7. **`PRO-Robotech/kacho-test#DD`** — newman cases + k6 + Playwright + sandbox integration tests; depends on кластер с merged ms.
8. **`PRO-Robotech/kacho-workspace#EE`** — vault updates + `KAC/KAC-127.md` Phase 6 trail; depends on visibility into final code.

Каждый PR ссылается на YT `KAC-123` (`Closes` или `relates`); комменты в YT issue после каждого merge.

CI `ref:`-pinning: пока `kacho-corelib#YY` не в `main`, kacho-iam's `.github/workflows/ci.yaml` pins `kacho-corelib` ref к feature-branch `KAC-127`. После merge — revert к `main`. Закрывается graph снизу вверх.

---

## 9. Out of scope

Following items — explicitly **NOT** in Phase 6; address в future phases of same epic:

- **CAEP push pipeline** (drainer / SET signing / subscriber webhook delivery) — **Phase 8**. Phase 6 пишет `caep_outbox` rows; drainer consumes их Phase 8.
- **Audit Kafka + ClickHouse + S3 + HSM + Merkle pipeline** — **Phase 9**. Phase 6 пишет `audit_outbox` rows; drainer + consumers — Phase 9.
- **SPIFFE/SPIRE workload identity + Cilium mesh** — **Phase 10**.
- **Multi-region active-active for Jackson + SCIM endpoint** — **Phase 11**. Phase 6 — single-region.
- **OWASP ASVS L3 full audit + external pentest + bug bounty + FIDO/OIDC conformance certifications** — **Phase 12**.
- **Workload Identity Federation (RFC 8693 Token Exchange) для GitHub/AWS/GCP/etc.** — **Phase 5** (preceded Phase 6; assumed merged).
- **JIT/PIM activation + Break-glass 2-person approval + Access Reviews automation + GDPR erasure pipeline** — **Phase 7**.
- **SCIM ETag/If-Match для concurrent-modification protection** (RFC 7644 §3.14) — future improvement; Phase 6 — last-writer-wins PATCH/PUT semantics.
- **SCIM dual-token grace window** (current + previous active simultaneously) — future improvement; Phase 6 — immediate rotation (customer must update Okta config inline).
- **SAML per-Org custom attribute mapping** (configurable mapping per Org) — Phase 6 hardcoded mapping (email/firstName/lastName). Future improvement.
- **HTTP-meta domain verification method** (alternative к DNS-TXT) — Phase 6 supports only DNS-TXT.
- **Multi-method bulk in same /Bulk request** with cross-references — Phase 6 supports bulkId references for POST-Group → POST-User chains; advanced cross-ref scenarios (PATCH after POST) — future.
- **SCIM v2.1 / SCIM extensions like Enterprise User attributes (manager, department, costCenter)** — Phase 6 — Core User + Core Group schemas only.
- **per-Org SCIM provisioning analytics dashboard** (за прошлый месяц provisioned/deprovisioned counts, average lifetime, etc.) — Phase 6 metrics suffice; UI dashboards — future.

---

## 10. Open Questions resolved

Following questions were considered и settled during design:

**Q1**: SAML — native в kacho-iam или через bridge?
**A1**: Bridge (Boxyhq Jackson). See D-3 — Kratos OSS has no native SAML; gosaml2 self-implementation = security risk; Jackson — open-source, mature, isolates SAML complexity.

**Q2**: SCIM bearer — Hydra OAuth access token (with mTLS-bound) или opaque?
**A2**: Opaque per-Org token (D-9). RFC 7644 doesn't require OAuth; Okta/Azure SCIM clients overwhelmingly use opaque bearer; adding DPoP/mTLS to Okta side — vendor effort blocker.

**Q3**: SCIM endpoint — public on `api.kacho.cloud` или internal-only?
**A3**: Public — это требование RFC 7644 (vendor provisioning agents call from internet). Bearer authentication внутри (not Hydra/Internal-rule). Запрет #6 — про gRPC internal vs external endpoints; HTTP REST SCIM endpoint — отдельная категория (specifically allowed; protected by org-scoped bearer и Cloudflare WAF IP allowlist).

**Q4**: JIT provisioning — eager (first signin auto-creates) vs lazy (need explicit invite)?
**A4**: Eager если `default_account_id` configured (D-7). Customer admin opts in by setting default_account; absence → JIT fails fail-closed.

**Q5**: Domain claim — global UNIQUE или per-Org?
**A5**: Global UNIQUE через partial UNIQUE `WHERE state IN (pending, verified)`. Same domain can't be claimed by two Orgs simultaneously; revoked claims can be re-claimed.

**Q6**: SCIM externalId — global UNIQUE или per-Org?
**A6**: Per-Org UNIQUE `WHERE scim_active=true` (D-5). Different Orgs can independently SCIM «alice@acme.com» as separate user-rows.

**Q7**: Backward compatibility?
**A7**: Not required (user feedback round 2 2026-05-19). Phase 1 organization schema — skeleton; Phase 6 freely extends с ALTER TABLE.

**Q8**: SCIM `/Me` — return what?
**A8**: ServiceProvider-as-User payload (SCIM-bot service-account representation), per RFC 7644 §3.11. This is conventional для inbound provisioning clients that want to verify auth works.

**Q9**: Group nesting depth?
**A9**: Max 5 (D-12). Beyond → CHECK fails 400.

**Q10**: SAML attribute mapping custom per Org?
**A10**: No, fixed convention (D-19). Email + firstName + lastName. Future improvement.

**Q11**: SCIM rate limit?
**A11**: 100 RPS per Org (D-25), in-memory token-bucket. Defense against misconfigured Okta loops.

**Q12**: Cluster-admin or Org admin can issue SCIM token?
**A12**: Both. Cluster-admin для any Org; Org admin (`organization:<id>#admin`) для own Org. Enforced via corelib/authz Check.

**Q13**: Organization deletion safety?
**A13**: FK RESTRICT (D-17). Cluster-admin must unbind accounts first (explicit `InternalOrganizationService.UnbindAccount`).

**Q14**: Concurrent SCIM POSTs with same externalId — race-safe?
**A14**: Yes — partial UNIQUE `(organization_id, scim_external_id) WHERE scim_active=true` enforces; SQLSTATE 23505 → 409 Conflict. Integration test `scim_filter_concurrency_integration_test.go` verifies ровно одна wins.

**Q15**: SAML cert rotation — zero-downtime?
**A15**: Jackson grace period 24h (D-16). Both certs accepted during transition.

**Q16**: SCIM Bulk atomicity — one big TX или per-op TX?
**A16**: Per-op TX (D-11). failOnErrors=1 aborts on first failure (subsequent ops not executed); failOnErrors=0 continues. Implementations cannot guarantee atomic «all 100 ops succeed or all rollback» under partial backend failures без 2PC, which we don't have.

**Q17**: SCIM ETag concurrency?
**A17**: Not Phase 6 (future improvement). Last-writer-wins PATCH/PUT. ServiceProviderConfig advertises `etag.supported=false`.

**Q18**: How does kacho-ui obtain Org admin's view of pending SCIM mappings?
**A18**: `InternalOrganizationService.ListSCIMMappings` (admin-UI; cluster-admin only). Per-Org admin sees own via separate `OrganizationService.ListSCIMMappings(org_id)` public RPC — protected by FGA `organization:<id>#scim_admin`.

**Q19**: Logging plaintext SCIM bearer на one-time-show?
**A19**: No. UI receives plaintext from `IssueSCIMTokenResponse` and displays; audit log records ONLY hash-fingerprint (last 4 chars of SHA-256). Never plaintext в любой persistent layer.

**Q20**: Jackson — own Postgres или shares kacho_iam DB?
**A20**: Own DB `kacho_jackson` (same Postgres cluster, separate logical DB). Запрет #8 satisfied — no cross-DB FKs; Jackson schema independent.

---

## Document version

| Version | Date | Author | Changes |
|---|---|---|---|
| 0.1 | 2026-05-19 | acceptance-author | Initial DRAFT |
