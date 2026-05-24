# Sub-phase W2.A — Stream A: Gateway permission-catalog unification (Chunk 3) + Spec-drift remediation (Chunk 4) — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: [KAC-170](https://prorobotech.youtrack.cloud/issue/KAC-170) W2.A (subtask of W2 in master epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) «kacho-iam → production-ready»).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos** (in dependency order per `kacho-workspace/CLAUDE.md` §«Кросс-репо зависимости»):
>   1. **`PRO-Robotech/kacho-proto`** — single-source-of-truth for permission catalog. Files:
>      - `proto/kacho/cloud/iam/v1/permissions_catalog.proto` — `PermissionsCatalogRoot` message (NEW; root that imports every iam service-proto whose RPCs must be catalogued; replaces «manual emit on plugin discovery»).
>      - `proto/kacho/cloud/iam/v1/authorize_service.proto` — fix `scope_extractor.object_type/from_request_field` for `Check`/`ListObjects`/`ListSubjects`/`CheckRelation` (#33).
>      - `proto/kacho/cloud/iam/v1/conditions_service.proto` — fix scope-extractor for `Get`/`Update`/`Delete`/`Evaluate` (#34); rename `folder_id`→`project_id` on Condition CRUD (#27, parity with KAC-124).
>      - `proto/kacho/cloud/iam/v1/compliance_report_service.proto` — fix scope-extractor `object_type` to track `scope_type` enum (#38).
>      - `proto/kacho/cloud/iam/v1/sa_key_service.proto` — fix mis-pluralised permission strings (`iam.issue_s_a_keies.issue` → `iam.serviceAccountKeys.issue` etc) (#44).
>      - `proto/kacho/cloud/iam/v1/service_account.proto` + `service_account_service.proto` — `project_id` required (drop legacy account-scope option), drop+recreate migration policy applies (#3, KAC-121 §1.1).
>      - `proto/kacho/cloud/iam/v1/jit_eligibility_service.proto` — declare `ActivateJIT` RPC + `ActivateJITRequest`/`ActivateJITResponse` (#32) — choice per OQ-W2.A-3 ⇒ live in `JITEligibilityService` (one fewer service).
>      - `cmd/protoc-gen-kacho-permissions/*` (generator plugin) — read `PermissionsCatalogRoot` imports, walk every `(google.api.http)` RPC, emit one `PermissionCatalogEntry` per (FQN, http-binding) pair. Drop ad-hoc per-RPC heuristics; fail-build on missing `(kacho.iam.authz.v1.permission)` option (no silent gaps).
>      - `gen/permission_catalog.json` — regenerated artefact; CI gate `make verify-catalog` ensures byte-for-byte determinism on regen.
>      - `Makefile` targets: `sync-permission-catalog`, `verify-permission-catalog` — publish catalog into `kacho-api-gateway` and `kacho-iam` embeds.
>   2. **`PRO-Robotech/kacho-api-gateway`** — consumer of the unified catalog. Files:
>      - `internal/middleware/embed/permission_catalog.json` — replaced by sync from kacho-proto (281 entries → catalog-derived; expected ≈310-330 entries post-Chunk 3, exact count determined by regenerated `kacho-proto/gen/permission_catalog.json`).
>      - `internal/middleware/permission_catalog.go` — `Lookup(fullMethod) (CatalogEntry, bool)` unchanged; `Validate()` (NEW, §4.5) tightened: catalog MUST contain every FQN of every registered gRPC handler at startup (cross-check against registered services); missing entry → process refuses to start (fail-closed on cold-path).
>      - `internal/middleware/rest_route_table_gen.go` — regenerated from same kacho-proto walk (334 routes → updated to match new catalog superset; AccessReview/JITEligibility/GdprErasure/InternalBreakGlass/ Conditions/FederationExchange entries added). One generator emits BOTH artefacts.
>      - `internal/middleware/authz.go` — `decide()` (current shape verified `:411-460`): no behavioural change; `Lookup` failure already → fail-closed deny (`outcomeDeny`/`outcomeUnauthenticated`). New: explicit `permission == "<exempt>"` short-circuit must remain idempotent under regen.
>      - `internal/restmux/mux.go` — add `RegisterAccessReviewServiceHandlerFromEndpoint`, `RegisterJITEligibilityServiceHandlerFromEndpoint`, `RegisterGdprErasureServiceHandlerFromEndpoint`, `RegisterConditionsServiceHandlerFromEndpoint`, `RegisterFederationExchangeServiceHandlerFromEndpoint` to the public `iam.v1` block (alongside existing AccessBinding/SAKey/JitPending/ComplianceReport/Authorize registered in KAC-132); `RegisterInternalBreakGlassServiceHandlerFromEndpoint` to internal block (kacho-only admin per §Запрет #6).
>   3. **`PRO-Robotech/kacho-iam`** — consumer of unified catalog + spec-drift fixes. Files:
>      - `internal/apps/kacho/seed/embedded/permission_catalog.json` — replaced by sync (was 236 entries — stale; becomes identical to gateway embed).
>      - `internal/apps/kacho/seed/permissions.go` — derives seed roles from synced catalog (no manual table); fail-fast on catalog parse error.
>      - `internal/apps/kacho/api/role/handler.go` (`:94-99`) — parse `is_system`/`account_id` from `ListRolesRequest.Filter` (#1). YC-style `filter=` mini-language: `"is_system=true"`, `"account_id=acc_xxx"`, `AND`-combine.
>      - `internal/apps/kacho/usecases/role/create.go` — `Validate()` cross-checks against unified catalog allowlist of supported permissions (#46).
>      - `internal/apps/kacho/domain/types.go` — sync `roleNameSystemRe` with migration `0008` CHECK (`^[a-z]+(\.[a-z_]+){0,2}$`) (#55).
>      - `internal/apps/kacho/api/account/list.go` (`:32-58`) — replace post-Go-filter on `OwnerUserID == principal.ID` with grant-aware list: enumerate accounts via FGA `ListObjects(user=principal, relation∈{admin,member}, object_type=account)` (#4). Old `OwnerUserID` post-filter dropped — TODO at `:50` retired (#11-rule: NO new TODO; existing TODO finally resolved).
>      - `internal/apps/kacho/usecases/user/list.go` + `internal/repo/.../user_repo.go` — replace single-`user.id==$1` membership with FGA-based identity (`ListSubjects(account/project, member)`) (#5).
>      - `internal/apps/kacho/usecases/group/{add_member,get,update,list}.go` (`:65` in add_member uses `RequireOwnerMatchesPrincipal`) — replace with `requireGrantAuthority(account_or_project, admin)` (parity with access_binding helper; same pattern shipped in W1.6 for delete) (#6/#14).
>      - `internal/apps/kacho/api/role/{update,delete}.go` — same owner→relation switch (#6 secondary).
>      - `internal/apps/kacho/api/project/list.go` — grant-aware listing + paging fix: filter applied in SQL `WHERE`, not post-Go (eliminates short-page bug; `next_page_token` consistent) (#15).
>      - `internal/apps/kacho/api/service_account/*` + `internal/repo/.../service_account_repo.go` + migration `0026_service_account_project_scoped.sql` — drop+recreate `service_accounts` table with `project_id NOT NULL` (no legacy account_id column, no dual-mode); reseed by env-flag `KACHO_IAM_GREENFIELD_SA=1` (default in dev; prod requires explicit opt-in) (#3).
>      - `internal/apps/kacho/api/conditions/handler.go` (`:51`,`:68`,`:85`,`:160`) — `FolderID`→`ProjectID` sweep (#27).
>      - `internal/apps/kacho/api/internal_iam/handler.go` (`:122` returns `Unimplemented` — verified) — implement `ListPermissions` returning catalog-aggregated set per (subject, scope) (#49). Powers gateway/admin-UI «what can this user do?» tooling.
>   - **NOT touched (verified)**: `kacho-corelib` (no new helper required — pure handler / generator / config work); other proto packages (compute/vpc/loadbalancer). Existing migrations 0001-0025 untouched.
> **Branches** (off `main` in each repo):
>   - `kacho-proto`: `KAC-170-proto-catalog-unify`
>   - `kacho-api-gateway`: `KAC-170-gateway-catalog-consumer`
>   - `kacho-iam`: `KAC-170-iam-spec-drift`
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 2 row («Поток A: Chunk 3 gateway wiring + permission-catalog unification + Chunk 4 spec-drift KAC-119/121»).
> **Source of finding-level requirements**: `docs/superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 3 (#19/#28/#29/#30/#31/#32/#33/#34/#38/#44/#45/#49) and §1.3 Chunk 4 (#1/#3/#4/#5/#6/#7/#14/#15/#27/#46/#55). Chunk 2 (#9/#11/#12/#13/#35/#36/#37/#39/#43/#53) is **already closed by W1.6 KAC-164** — out of scope here.
> **Predecessors (must be `main`-merged before W2.A impl starts)**:
> - **W1.4** — principal propagation cross-service ([[KAC-140]]) — **MERGED**. Required so api-gateway can trust principal-id from headers when populating ctx for downstream service calls (Chunk-4 group/role/account/project handlers depend on `authzguard.PrincipalFromCtx` returning real caller, not bootstrap-default).
> - **W1.6** — Remediation Chunk 2 ([[KAC-164]]) — **PR open / preparing merge**. Required because (a) the catalog-metadata-driven anti-anon allowlist (W1.6 §4.11 read-only suffixes) becomes authoritative once the catalog is unified — without W1.6's allowlist, any newly catalogued FQN added by W2.A would bypass anti-anon scrutiny on cold path; (b) W2.A asserts «every FQN in catalog has authoritative anti-anon coverage», which presupposes W1.6's table-test scaffold.
> - **W1.3** — gateway authz fail-closed enable ([[KAC-139]]) — **MERGED**. Without `decide()` actually denying on `Lookup`-miss, catalog-drift would degrade open (today's bug). W2.A trusts that path.
> - **W1.5** — Remediation Chunk 1 ([[KAC-163]]) — recommended-merged (not strict block). #4/#5/#6/#15 FGA-list scenarios assume grant→FGA atomicity from W1.5.
>
> **Why W2.A unlocks W3 and closes parity-against-spec gaps**: today **three** catalogs drift (236 iam-seed / 281 gateway-embed / >295 implied by proto sources verified 2026-05-24); newman suites assume per-RPC authz behaviour that depends on which catalog the runtime is reading. Chunk 3 makes ONE catalog source-of-truth; Chunk 4 forces handlers to match the acceptance docs KAC-119/121 promised. Without W2.A, W3 (federation/SSO internals) lands on top of an authoritative authz layer that doesn't agree with the spec it was written against.

---

## 0. Преамбула — что эта sub-итерация (précis)

W2.A — **первый из четырёх параллельных потоков W2** (поток A = catalog unification + spec-drift; потоки B/C/D — Enterprise / API-tokens / newman-добор). Объединяет два чанка из master plan W2 row, **потому что они разделяют одну и ту же primary surface**: proto-extension + catalog-emit pipeline. Один регенерационный шаг закрывает обе категории, поэтому split на две acceptance-доки создал бы синхронизационный риск.

**Chunk 3 (12 findings, gateway / proto / catalog)** — root cause: **три рассинхронизированных permission-каталога** существуют одновременно:

- `kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json` — **236 entries** (verified 2026-05-24 `python3 -c 'import json; len(...)' → 236`). Seed-derived viewer/editor/system-admin роли строятся ИЗ ЭТОГО файла. Stale: отсутствуют Phase 7/7b, AccessReview, ComplianceReport, JIT, GDPR.
- `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` — **281 entries** (verified 2026-05-24). Тот, что читает per-RPC authz middleware. Перекошен относительно iam-seed → роли «vpc.viewer» в iam-seed имеют permission'ы, которых нет в gateway-каталоге → authz check на gateway отдаёт fail-closed deny для тех permission'ов, которые валидно гранчены в FGA.
- `kacho-proto/proto/.../permission_catalog.json` (gen-output из proto-source) — нет канонического «root», плагин `protoc-gen-kacho-permissions` обходит whatever `.proto` ему передан per-вызов; реальное число каталогизированных FQN — суперсет (>295 implied; будем точно знать после regen с `PermissionsCatalogRoot`).

Триггерные findings #236/#273/#295 в master plan — три способа считать одну и ту же триаду drift'а. Chunk 3 ставит **ровно один** generator от **ровно одного** proto-root → **ровно один** JSON → **синхронизируется** во ВСЕ embed-локации одним `make sync-permission-catalog` (mirror паттерна `make sync-migrations` из corelib). Любая drift'а ловится `make verify-permission-catalog` в CI и валит build.

Вторичные Chunk-3 findings (#19/#28/#29/#30/#31/#32/#44/#49) — все следствия. После unification:
- #31 (catalog-root missing imports) — нет smysl'а, потому что root-message объявляет авторитетный список catalogued services.
- #19/#28 (Authorize/Conditions/FederationExchange/SAKey not in gateway-catalog) — закрыты тем, что generator обходит каждый `(google.api.http)`-аннотированный RPC и **fail'ит build при отсутствии** `(kacho.iam.authz.v1.permission)` option (был silent-skip).
- #29/#30 (restmux + route-table не регистрируют Phase 7/7b) — закрыты добавлением `Register*HandlerFromEndpoint` блоков (см. §4.2) и автоматической regen route-table из того же proto-walk.
- #32 (`ActivateJIT` realised but no proto RPC) — закрыт объявлением RPC в `JITEligibilityService` (OQ-W2.A-3).
- #44 (`iam.s_a_keyses` plurals typo) — закрыт runtime-rename `iam.serviceAccountKeys.*`; **breaking** для in-flight role-templates, но **не deployed в prod** (ack по master plan baseline: 4/44 findings closed, surface ещё не frozen).
- #49 (InternalIAM.ListPermissions stub) — закрыт реализацией поверх unified catalog как авторитативного источника «what permissions exist» (`internal/apps/kacho/api/internal_iam/handler.go:122`, verified).
- #33/#34/#38 (scope_extractor проблемные annotations) — закрыты proto-уровневыми правками (см. таблицу в шапке).
- #45 (три рассинхронизированных каталога) — root, описан выше.

**Chunk 4 (11 findings, spec-drift KAC-119/121)** — root cause: KAC-127 rewrite оставил owner-only authz и account-scoped SA вместо relation-based / project-scoped модели, заявленной в acceptance KAC-119/121. После W1.5/W1.6 FGA — источник истины для tuple'ов и handlers'ы enforce-ят principal-identity; W2.A довершает: handler'ы **читают** authz-state из FGA вместо post-filter'а в Go.

| # | Sev | File:line (verified 2026-05-24) | Симптом | Fix |
|---|---|---|---|---|
| **#19** | P1 | `cmd/kacho-iam/main.go` (gRPC registration); `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` (281 entries — verified) | gateway-catalog не содержит entries для `AuthorizeService`/`ConditionsService`/`FederationExchangeService`/`SAKeyService` → per-RPC middleware на FQN-miss → `outcomeDeny` (`authz.go:411-460`). Эффект: эти RPC недостижимы публично по REST. | Unified catalog (см. §4.1/§4.4) обходит все services с `(google.api.http)`. Generator fail'ит, если для catalogued RPC нет `(kacho.iam.authz.v1.permission)` option — silent-skip больше не возможен. |
| **#28** | P1 | `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` (281); `internal/middleware/rest_route_table_gen.go` (334 routes, verified `grep -E "^\s*\{" \| wc -l`) | Gateway-embed (281) vs implied-gen (>295) drift'аются → AccessReviewService/JITEligibilityService/GdprErasureService/InternalBreakGlassService — отсутствуют в gateway → blanket deny через `Lookup`-miss. | Regenerate from `PermissionsCatalogRoot`; expected post-unification ≈310-330 entries (exact = post-regen artifact). CI gate (`verify-permission-catalog`) валит build при drift. |
| **#29** | P1 | `kacho-api-gateway/internal/restmux/mux.go` (verified `:385-450` — iam-block регистрирует Account/Project/User/SA/Group/Role/AccessBinding/SAKey/JitPending/ComplianceReport/Authorize только) | НЕ зарегистрированы `AccessReviewService`/`JITEligibilityService`/`GdprErasureService`/`ConditionsService`/`FederationExchangeService` для REST → POST /iam/v1/accessReviewCampaigns:... → 404 (grpc-gateway не имеет роута). | Добавить `Register<X>ServiceHandlerFromEndpoint(ctx, mux, iamAddr, opts)` для каждой missing service в `iam.v1` блоке (§4.2). `InternalBreakGlassService` — в internal-block (внутренний admin, §Запрет #6). |
| **#30** | P1 | `kacho-api-gateway/internal/middleware/rest_route_table_gen.go` (334 routes) | Route-table — derived from proto `(google.api.http)`, но генератор не запускался после добавления Phase 7/7b → REST→FQN map не содержит jit/accessReview/complianceReport/jitPending/gdpr routes → per-RPC authz пропускает их через path-not-matched fallback (рискованный degrade). | Регенерация одним walk'ом с unified-catalog (одна regen-команда emit'ит и catalog, и route-table). |
| **#31** | P1 | `kacho-proto/proto/kacho/cloud/iam/v1/permissions_catalog.proto` (verified imports `descriptor.proto` + `validation.proto` only) | Нет `PermissionsCatalogRoot` message; plugin обходит whatever `.proto` ему передан → `compliance_report_service.proto` / `jit_pending_service.proto` могут не попасть в gen-каталог при невнимательном invoke'е. | **Add** `PermissionsCatalogRoot` message с `repeated string include_services = 1` (FQN-list) — declarative manifest, который plugin читает первым. Build fail'ит при попытке emit'ить RPC service'а, не объявленного в Root. Closure-style invariant. |
| **#32** | P1 | `kacho-iam/internal/service/phase7_jit_service.go` (impl exists); `kacho-proto/proto/kacho/cloud/iam/v1/jit_eligibility_service.proto` (no `ActivateJIT` RPC) | `ActivateJIT` метод реализован в service, но RPC отсутствует в proto → недостижим через wire. | Объявить `ActivateJIT` в `JITEligibilityService` (OQ-W2.A-3 recommendation: меньше новых сервисов). HTTP-binding: `POST /iam/v1/jitEligibilities/{eligibility_id}:activate`. |
| **#33** | P2 | `kacho-proto/proto/.../authorize_service.proto` (verified scope_extractor блоки: `Check`: `object_type:"project" from_request_field:"subject"`; `ListObjects`: `object_type:"project" from_request_field:"resource"` ×2) | `subject` строка-ARN трактуется gateway-extractor'ом как project-id → `Check` зовётся на `project:<subject-text>` — бессмыслица; deny ВСЕГДА. | `Check`: убрать `scope_extractor` целиком — Authorize.Check — meta-RPC, scope = `system` (admin-only по умолчанию, читается из `Check.scope`-параметра самим check'ом). `ListObjects`/`ListSubjects`/`CheckRelation`: `object_type` = `from_request_field("scope_type")` (dynamic) или резерв `"system"`. Поправка по результирующему scope_extractor design — RFC §4.6. |
| **#34** | P2 | `kacho-proto/proto/.../conditions_service.proto` (verified 6 блоков scope_extractor; 4 из 6 — `object_type:"project" from_request_field:"condition_id"`; 2 — `folder_id`) | `condition_id` (uid строка) трактуется как project-id → admin не может Update свою condition. `folder_id` пережиток до KAC-124 → не имеет такого поля. | Condition CRUD: scope_extractor через лёгкую косвенность — `from_db_lookup` (NEW в `kacho.iam.authz.v1.PermissionScopeExtractor`): plugin emit'ит hint, runtime extractor читает row `conditions.scope_id` по `condition_id` → Check на real scope. Альтернатива (если сложно — OQ-W2.A-7): сделать `scope_id` обязательным полем в `Update*Request`/`Delete*Request` (parity с CreateConditionRequest, где `scope_id` уже есть). |
| **#38** | P2 | `kacho-proto/proto/.../compliance_report_service.proto` (verified `GenerateAccessReport`: `object_type:"project" from_request_field:"scope_id"`; `Get`/`Download`: `object_type:"iam_compliance_report" from_request_field:"report_id"`) | `scope_id` может быть account/project/organization (`scope_type` enum), но `object_type` хардкодит `project` → admin'у account'а deny на свой же account-scoped report. | Generate/List: `object_type` = dynamic resolution `<scope_type>` (gateway extractor читает `scope_type` enum value из request и подставляет в FGA-call). Generic mechanism reused для #34. |
| **#44** | P3 | `kacho-proto/proto/.../sa_key_service.proto` (verified permission strings: `iam.issue_s_a_keies.issue`, `iam.s_a_keyses.list`, `iam.revoke_s_a_keies.revoke`) | Кривая protoc-плюрализация → permission'ы засоряют каталог; в RBAC-роле `iam.serviceAccountKeys.issue` (humanly expected) не существует → бессмысленные grant'ы. | Manual override: `iam.serviceAccountKeys.issue`, `iam.serviceAccountKeys.list`, `iam.serviceAccountKeys.revoke`. Breaking для in-flight (но не deployed) ролей. |
| **#45** | P1 | seed (236) / gateway-embed (281) / gen (implied >295) — все три verified 2026-05-24 | Три расходящихся каталога — root drift, описан выше. | Unified catalog (см. §4.1/§4.4/§4.5). |
| **#49** | P1 | `kacho-iam/internal/apps/kacho/api/internal_iam/handler.go:122` (verified: `return nil, status.Error(codes.Unimplemented, "ListPermissions is part of E3 (OpenFGA Check)")`) | `InternalIAMService.ListPermissions` — stub. Admin-UI не может «what can this user do?». | Реализация: aggregate from unified catalog filtered by FGA-subject-membership; см. §4.7. |
| **#1** | P1 | `kacho-iam/internal/apps/kacho/api/role/handler.go:94-99` (verified: `Filter: req.GetFilter()` only; comment `// На E0 не парсим is_system/account_id из YC filter (TODO follow-up)`) | `List` отдаёт system + custom-роли ВСЕХ аккаунтов. TOCTOU-leak. Existing TODO — нарушение §11 root rule. | Парсить `filter=` mini-language (`is_system=true`, `account_id="acc_xxx"`, `AND`); без accountId → system-only; с accountId → system + custom-этого-account. TODO retired. |
| **#3** | P1 | `kacho-proto/proto/.../service_account.proto` (verified: `string account_id = 2` + `string project_id = 6` dual); `kacho-iam/internal/repo/.../service_account_repo.go` | SA остался account-scoped, KAC-121 §1.1 требует project-scoped (drop dual-mode). | Drop+recreate migration `0026_service_account_project_scoped.sql` (OQ-W2.A-2: greenfield, не prod). `project_id NOT NULL`; old `account_id` column dropped. Handler/Repo/proto sweep. |
| **#4** | P1 | `kacho-iam/internal/apps/kacho/usecases/account/list.go:32-58` (verified: post-Go filter `string(a.OwnerUserID) == principal.ID`; existing TODO(KAC-126) at `:50`) | `AccountService.List` отдаёт ТОЛЬКО account'ы, owner которых — principal. Приглашённый admin (с FGA-binding admin@account) не видит account. TODO — нарушение §11. | FGA `ListObjects(user=principal, relation∈{admin,member}, type=account)`; result-set → SQL `WHERE id = ANY($ids)`. TODO retired. |
| **#5** | P2 | `kacho-iam/internal/apps/kacho/usecases/user/list.go` + `internal/repo/.../user_repo.go` | Membership считается single-`user.id=$1` row → не отражает identity / FGA. | Аналогично #4: `ListSubjects(account/project, member)`. |
| **#6** | P1 | `kacho-iam/internal/apps/kacho/usecases/group/add_member.go:65` (verified: `authzguard.RequireOwnerMatchesPrincipal(ctx, string(acct.OwnerUserID))`); same antipattern в `role/update.go`, `role/delete.go` | Owner-only authority — delegated admin не может добавить member / update / delete роль. | `requireGrantAuthority(ctx, repo, fga, "account", string(acct.ID))` (parity с access_binding helper — W1.6 §4.5 для delete). |
| **#7** | P1 | DECISION + (`kacho-api-gateway` authz exempt-handling) | Acceptance KAC-121 §5:103 требует `/iam/v1/roles` public-including-anonymous; код требует auth. | **OQ-W2.A-1 решён (см. §3)**: update acceptance (catalog-read требует auth). Anonymous → 401 PermissionDenied. Gateway не меняем; роль `iam.roles.list` уже non-exempt в catalog. Existing newman `authz-deny.py:41` остаётся source-of-truth. |
| **#14** | P2 | `kacho-iam/internal/apps/kacho/usecases/group/list.go` (real leak — no scope-filter) | `Group.List` без scope-filter возвращает все группы. | scope-filter: caller видит только группы account'ов, на которых имеет `member`/`admin` (FGA-derived). |
| **#15** | P2 | `kacho-iam/internal/apps/kacho/api/project/list.go` | Owner-only post-filter + сломанная пагинация (filter-after-page → короткие страницы с непустым `next`). | FGA-aware filter applied В SQL (`WHERE id = ANY($ids)`); paging consistent. |
| **#27** | P2 | `kacho-iam/internal/apps/kacho/api/conditions/handler.go:51,68,85,160` (verified 4 sites of `req.GetFolderId()` / `FolderID`); `kacho-proto/proto/.../conditions_service.proto` | API-drift после KAC-124 folder→project. | Sweep `FolderID`→`ProjectID` в proto + handler + domain + repo. |
| **#46** | P2 | `kacho-iam/internal/apps/kacho/usecases/role/create.go`; `internal/apps/kacho/domain/types.go` `Permissions.Validate()` | Проверяет regex+cardinality, но не supported-permission allow-list → можно создать роль с несуществующим permission. | `Validate(ctx, catalogProvider)` — cross-check каждый permission в supported set из unified catalog (Chunk 3.5). |
| **#55** | P2 | `kacho-iam/internal/apps/kacho/domain/types.go` `roleNameSystemRe = ^roles/[a-z]+\.[a-z]+$`; migration `0008` CHECK `^[a-z]+(\.[a-z_]+){0,2}$` | Domain validator stale — DB принимает, domain reject'ит при reload. | Sync regex с миграцией 0008; integration test (round-trip insert + domain.Parse). |

### 0.1 W2.A НЕ включает (явный scope-boundary)

| Что | Куда |
|---|---|
| W2.B — Enterprise (SAML/SCIM/JIT-activate UX / CAEP-fan-out / SPIRE-mTLS) | **отдельный acceptance-док W2.B** (parallel stream). W2.A не трогает SAML / SCIM / CAEP / SPIRE сурфейс. |
| W2.C — API tokens (proto + migration + usecase + gateway authn) | **отдельный acceptance-док W2.C** (parallel stream). |
| W2.D — Newman 100% coverage добор (13 новых сюит) | **отдельный план/доку W2.D** (parallel stream). W2.A добавляет ровно столько newman cases, сколько закрывает свои findings + регрессионные guards (см. §6). |
| W3 — Federation/SSO internals (SAML XML-DSig verify #40, CAEP-SET verify #42, MFA-fresh #23, model reload #25, RegoTest empty #26, OPA-VERIFY follow-up) | W3 acceptance-док. |
| Granular permission-relations в FGA model (model.fga DSL expansion) | W2 — после catalog unification; **может потребовать отдельный sub-stream** (acceptance-reviewer call). |
| Cross-service authz-cache invalidation на binding `Update` | W2 (отдельный chunk если acceptance-reviewer хочет split). |
| Observability metrics за catalog-load-fail / startup-validation | W3 observability. |
| ApiTokenService Internal.Resolve (Блок F internal) | W2.C. |
| Already-closed Chunk-2 findings (#9/#11/#12/#13/#35/#36/#37/#39/#43/#53) | W1.6 KAC-164. **НЕ пересматриваем.** |

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент / Запрет | Где соблюдаем |
|---|---|
| **§Запрет #1** | gate данного doc; impl стартует только после APPROVED от `acceptance-reviewer`. |
| **§Запрет #2** | в proto/handler/test'ах не упоминается; CI grep-guard в `kacho-proto` Makefile уже есть, остаётся в силе. |
| **§Запрет #3** | handwritten pgx — для `0026_service_account_project_scoped.sql` (#3) DDL handwritten goose-up + goose-down; ORM не вводим. |
| **§Запрет #4** | within-iam-DB only. Cross-service references (gateway → iam Authorize) — через peer-API, без cross-DB FK. |
| **§Запрет #5** | applied migrations не редактируем. `0008` (роль name CHECK) — НЕ трогаем; W2.A #55 fix — на domain-layer regex, в DB ничего не меняется. Новая миграция `0026` — добавляется как next-sequence. |
| **§Запрет #6** | **Critical**. `InternalBreakGlassService` остаётся internal-only (registered только в internal-mux block §4.2; `HasInternalSuffix` в proxy/director блокирует попадание на external TLS endpoint — verified existing pattern в `restmux/mux.go:551-559` для NLB). Любой новый Internal-RPC, добавляемый в catalog, помечается `permission_meta.scope = "internal_admin"` для отдельной фильтрации. |
| **§Запрет #7** | broker (Kafka/NATS) отсутствует. Catalog distribution — file-embed + Makefile sync, без broker. |
| **§Запрет #8** | DB-per-service. SA project-scope migration (#3) — внутри `kacho_iam`; FK `service_accounts.project_id → projects.id` — same-DB. |
| **§Запрет #9** | Мутации (`Create/Update/Delete` ролей/групп/SA/binding) остаются async via Operation — без изменений. |
| **§Запрет #10** (within-service refs DB-уровень обязателен) | Для `service_accounts` (#3): `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT` + `NOT NULL`; unique constraint `UNIQUE(project_id, name)` (parity с YC SA name-scope-per-project). Никакого software refcheck. |
| **§Запрет #11** (NO new TODO / NO tech debt) | **Critical для этого PR**. Существующие TODO которые retire'ются: `account/list.go:50` (`TODO(KAC-126): добавить OwnerUserID в repo ListFilter`); `role/handler.go:99` (`// На E0 не парсим is_system/account_id из YC filter (TODO follow-up)`). Ни одного нового TODO в diff. CI grep-guard уже в кодовой базе. |
| **§Запрет #12** (test-first strict, RED→GREEN per finding в same PR) | Каждый из 23 findings закрывается одной парой `RED (failing integration/newman) → GREEN (impl)` в том же PR (per-repo). См. §5/§6. Newman кейсы написаны ПЕРВЫМИ. |
| **§Запрет #13** (test-only PR ≠ product fix; никаких TODO в тестах) | Если W2.A в процессе обнаружит unrelated bug — отдельный KAC, не lumping в этот PR. В test-кейсах никаких `# TODO`. |
| **CLAUDE.md §«API contract — flat resources + Operations»** | Сохраняется. Все мутации `RoleService.Create`, `Group.AddMember`, `ServiceAccount.Create` — async Operation. ActivateJIT (#32) — тоже Operation (long-running при auto-grant). |
| **CLAUDE.md §«Инфра-чувствительные данные ТОЛЬКО во внутреннем API»** | `InternalBreakGlassService.Approve*` — internal-only (см. §Запрет #6 выше). Catalog enumeration НЕ leak'ает internal-FQN'ы публично — separate `permission_meta.scope` filter. |
| **CLAUDE.md §«Принцип переиспользования через kacho-corelib»** | Single-generator pattern остаётся в `kacho-proto/cmd/protoc-gen-kacho-permissions/`; не выносим в corelib (используется единственным репо для emit'а в polyrepo-wide). |
| **CLAUDE.md §«Within-service refs DB-уровень обязателен»** | `service_accounts.project_id` (#3) — FK + NOT NULL + UNIQUE composite. `Conditions.scope_id` (#34 db_lookup) — FK + NOT NULL. |
| **CLAUDE.md §«Vault discipline»** | KAC-170.md notes + edges/resources/packages updates обязательны (см. §8). |
| **CLAUDE.md §«Кросс-репо зависимости и порядок выполнения»** | W2.A фиксирует: kacho-proto → kacho-api-gateway → kacho-iam. CI зависимых репо временно пиннит sibling-`ref:` на feature-branch до merge'а proto. |

---

## 2. Глоссарий

- **`PermissionsCatalogRoot`** (NEW, kacho-proto §4.1) — top-level proto message в `permissions_catalog.proto`, который declarative-listed all iam services to be catalogued. Plugin reads it FIRST, fails build if a service-proto is referenced but file not importable, or if any RPC inside referenced service lacks `(kacho.iam.authz.v1.permission)` option.
- **Unified catalog** — single `permission_catalog.json` artifact, generated from `PermissionsCatalogRoot` walk, distributed via `make sync-permission-catalog` to (a) `kacho-api-gateway/internal/middleware/embed/`, (b) `kacho-iam/internal/apps/kacho/seed/embedded/`. Byte-for-byte identical; CI gate `make verify-permission-catalog` computes sha256 and fails on drift.
- **Catalog superset validation** (NEW, §4.5) — startup-time check в kacho-api-gateway: enumerate every gRPC FQN registered via `grpcSrv.GetServiceInfo()`; for each, `PermissionCatalog.Lookup(fqn)` MUST succeed; missing → `log.Fatalf` (process refuses to start, helm rollout fails). Closes Lookup-degrade-open path on cold start.
- **`requireGrantAuthority`** — existing helper в `kacho-iam/internal/apps/kacho/api/access_binding/helpers.go`; allow если caller — account-owner ИЛИ FGA-admin на resource. W2.A применяет ВЕЗДЕ, где сейчас `RequireOwnerMatchesPrincipal` (group/role/Account-admin context).
- **FGA `ListObjects`** — OpenFGA API: «return all objects of `type=T` where `user=U` has `relation=R`». Used #4/#5/#15 для grant-aware listing. Replaces post-Go-filter pattern.
- **`from_db_lookup`** (NEW scope_extractor mode, §4.6) — when extractor needs to indirect a request-ID through DB to obtain real scope (e.g. `condition_id → conditions.scope_id`). Plugin emits hint; runtime extractor in gateway middleware fetches the row.
- **Drop+recreate migration** (#3) — per CLAUDE.md «major rewrite» policy (memory `feedback-no-strict-backward-compat-on-major-rewrite.md`): no data preservation; greenfield restart; env-flag `KACHO_IAM_GREENFIELD_SA=1` (default dev / explicit prod opt-in) gates the destructive DDL.
- **Catalog scope** (`permission_meta.scope` extension, §4.1.3) — NEW per-RPC tag: `"public"` (REST-routable via grpc-gateway), `"internal_admin"` (kacho-only, internal-listener), `"system"` (no caller — system-bus). Used by `ListPermissions` (#49) to redact non-public entries.

---

## 3. Decisions / Open Questions

### 3.1 Decisions taken (binding without further review)

| ID | Decision |
|---|---|
| **D-W2.A-1** | Chunk 3 + Chunk 4 land в одной acceptance-доке (W2.A). Reason: shared proto/catalog surface; separate docs создают sync risk. |
| **D-W2.A-2** | Generator emits BOTH `permission_catalog.json` AND `rest_route_table_gen.go` в одном walk. Reason: avoid second-source-of-drift between catalog (FQN-keyed) и route-table (REST-keyed). |
| **D-W2.A-3** | `service_accounts` drop+recreate в migration `0026`. Reason: per CLAUDE.md major-rewrite + memory `feedback-no-strict-backward-compat-on-major-rewrite.md`; not deployed in prod (4/44 findings closed baseline). |
| **D-W2.A-4** | `InternalBreakGlassService` остаётся internal-only (Chunk 3 only adds catalog entry tagged `scope="internal_admin"` — НЕ public REST registration). External clients не должны догадываться, что это RPC существует. |

### 3.2 Open questions (DECISION-NEEDED перед стартом impl)

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W2.A-1** | #7: anonymous `/iam/v1/roles` — менять gateway (разрешить anon) или acceptance KAC-121 §5:103? | **Обновить acceptance KAC-121**: catalog-read требует auth (минимальная гигиена; anonymous role enumeration → information leak о authz-плане). Gateway не меняем; existing `authz-deny.py:41` (anon→401) остаётся source-of-truth. **Action**: open `KAC-iam-acceptance-update` follow-up KAC ссылается на W2.A. |
| **OQ-W2.A-2** | #3 SA drop+recreate — KACHO_IAM_GREENFIELD_SA flag default true (dev) или false (prod-safe)? | **Default = true в dev, false в prod**. Helm chart values exposes `iam.greenfieldSA: false`; explicit opt-in. Migrator (`cmd/kacho-iam-migrator`) prints big warning «GREENFIELD_SA=true — destructive; all service_account rows will be lost. Continue? (5s grace)» при apply, чтобы случайный prod-apply не сжёг данные. |
| **OQ-W2.A-3** | #32 `ActivateJIT` — в `JITEligibilityService` или отдельный `JITActivationService`? | **JITEligibilityService** (parity с remediation plan OQ-3). HTTP: `POST /iam/v1/jitEligibilities/{eligibility_id}:activate`. Меньше новых сервисов. |
| **OQ-W2.A-4** | #44 SAKey permission strings — break ли роли existing? | Не break: 4/44 findings closed в baseline; SA-key role bindings не в prod customer tenant'ах. **Migration script** в `cmd/kacho-iam-migrator/v0026/`: rewrite seed-роли с new strings; warn если custom-роли содержат `iam.s_a_*` строки (none expected per baseline). |
| **OQ-W2.A-5** | Catalog superset validation (§4.5) — fail-on-startup vs warn-and-degrade? | **Fail-on-startup** (`log.Fatalf`). Reason: degrade-open даже с warn — это #45-style drift. Fail-loud в pod startup → CI helm tests ловят перед production rollout. |
| **OQ-W2.A-6** | #34/#38 scope_extractor — `from_db_lookup` (gateway DB lookup) vs `scope_id`-в-request (require client to pass)? | **Hybrid**: где proto-request уже имеет `scope_id` (CreateCondition, GenerateAccessReport) — use `from_request_field:"scope_id"`. Где нет (Update/Delete/Get Condition с `condition_id` only) — `from_db_lookup` с описанием `table:conditions, key:condition_id, col:scope_id`. Gateway middleware фетчит row через peer-call `kacho-iam.InternalConditionsService.GetScope(condition_id)` (NEW lean internal RPC). |
| **OQ-W2.A-7** | #34 alternative: добавить `scope_id` обязательным в `Update/Delete/Get ConditionRequest` (avoid DB-lookup-on-authz) | **Defer; choose hybrid (OQ-W2.A-6)**. Avoids breaking changes к existing clients (KAC-127 frozen proto wire-compat); DB-lookup hop малое latency (peer-call same cluster, ms scale). Если acceptance-reviewer хочет cleaner — open separate KAC. |
| **OQ-W2.A-8** | #45 unified catalog — embed copy-on-build vs runtime fetch from ConfigMap mount | **embed по умолчанию + env override** (mirror existing pattern `KACHO_API_GATEWAY_PERMISSION_CATALOG_FILE` — verified в `permission_catalog_embed.go:18`). Build-time embed для airgapped deploy, runtime override для staged rollout. |
| **OQ-W2.A-9** | `ListPermissions` (#49) — return ALL catalogued permissions or only those visible-to-caller? | **Visible-to-caller** (per subject from auth ctx). Reason: prevents enumeration attack (anon should not discover privileged permission names). For admin tooling: separate `InternalIAM.AdminListPermissions` (no scope filter, internal-only). |
| **OQ-W2.A-10** | RoleService.List filter mini-language (#1) — full YC-compat parser vs subset? | **Subset**: only `=`/`AND`; only `is_system={true,false}` and `account_id="..."`. Other tokens → InvalidArgument («unsupported filter expression»). Full YC parser — out of scope. |

> **Ответы на OQ — за `acceptance-reviewer`.** OQ-W2.A-1/2/5/6/9 — critical для public-API/integration shape; impl не стартует без явных ответов. OQ-W2.A-3/4/7/8/10 — implementation-detail, acceptance-reviewer может accept рекомендацию.

---

## 4. Implementation steps (per-finding spec, в порядке зависимостей)

### 4.0 RED phase — write all failing tests FIRST (§Запрет #12 strict)

Per §5/§6. Каждая subsection ниже предполагает соответствующий RED тест уже committed and CI red.

### 4.1 `kacho-proto/proto/kacho/cloud/iam/v1/permissions_catalog.proto` — `PermissionsCatalogRoot` + `permission_meta.scope` (#31, #44, prereq для unification)

#### 4.1.1 Add `PermissionsCatalogRoot` message

```protobuf
// PermissionsCatalogRoot — authoritative manifest of all iam services
// whose RPCs are required to be catalogued. Plugin reads this FIRST.
// Adding a new iam service is a 1-line append here; forgetting →
// CI catalog-coverage gate failure, not silent omission.
message PermissionsCatalogRoot {
  // Each entry is the fully-qualified proto file path relative to
  // kacho-proto root (e.g. "kacho/cloud/iam/v1/access_review_service.proto").
  repeated string included_files = 1;
}

// Sentinel singleton — emitted into gen as static asset.
// Generator validates: every "string" here corresponds to an importable
// .proto, every RPC in those .protos has (kacho.iam.authz.v1.permission)
// or sentinel "<exempt>".
```

#### 4.1.2 Add `permission_meta.scope` extension

```protobuf
extend google.protobuf.MethodOptions {
  // permission_meta — per-RPC catalog metadata (in addition to
  // (kacho.iam.authz.v1.permission) on the same RPC). Optional.
  PermissionMeta permission_meta = 50104;
}

message PermissionMeta {
  // scope — controls catalog visibility / surface routing.
  // Values: "public" (REST-routable, public listener),
  //         "internal_admin" (kacho-only, internal-listener),
  //         "system" (system-bus, no human caller).
  // Default: "public" if (google.api.http) present, else "internal_admin".
  string scope = 1;
}
```

#### 4.1.3 Fix #44 — SAKey permission strings

`kacho-proto/proto/.../sa_key_service.proto`:

- `Issue` permission: `iam.serviceAccountKeys.issue` (was `iam.issue_s_a_keies.issue`)
- `List` permission: `iam.serviceAccountKeys.list` (was `iam.s_a_keyses.list`)
- `Revoke` permission: `iam.serviceAccountKeys.revoke` (was `iam.revoke_s_a_keies.revoke`)

### 4.2 `kacho-proto` scope_extractor fixes (#33, #34, #38)

- `authorize_service.proto::Check` — remove `scope_extractor` (meta-RPC, scope derived from request body explicitly).
- `authorize_service.proto::ListObjects/ListSubjects` — `object_type = from_request_field("object_type")` (dynamic from request).
- `authorize_service.proto::CheckRelation` — same dynamic resolution.
- `conditions_service.proto::CreateCondition` — keep `from_request_field("scope_id")` (already present).
- `conditions_service.proto::{Get,Update,Delete,Evaluate}Condition` — new `from_db_lookup{table:"conditions", key_field:"condition_id", scope_col:"scope_id"}` (extends `PermissionScopeExtractor` per §4.1.3 — see proto-api-reviewer).
- `conditions_service.proto::EvaluateCondition` — same lookup (also takes `condition_id`).
- `compliance_report_service.proto::GenerateAccessReport` — `object_type = from_request_field("scope_type")` (dynamic — closes #38).
- `compliance_report_service.proto::ListAccessReports` — same dynamic.

### 4.3 `kacho-proto` — declare `ActivateJIT` RPC (#32)

```protobuf
// jit_eligibility_service.proto
service JITEligibilityService {
  // ... existing RPCs ...

  // ActivateJIT — activate an existing JIT eligibility entry for the
  // calling principal. Creates a JitPending row for approval (or
  // immediately grants if auto_approve=true on eligibility). Returns
  // Operation containing JitPendingId in metadata.
  rpc ActivateJIT(ActivateJITRequest) returns (kacho.cloud.operation.v1.Operation) {
    option (google.api.http) = {
      post: "/iam/v1/jitEligibilities/{eligibility_id}:activate"
      body: "*"
    };
    option (kacho.iam.authz.v1.permission)        = "iam.jitEligibilities.activate";
    option (kacho.iam.authz.v1.required_relation) = "self";
    option (kacho.iam.authz.v1.scope_extractor)   = {
      object_type:        "iam_jit_eligibility"
      from_request_field: "eligibility_id"
    };
  }
}

message ActivateJITRequest {
  string eligibility_id = 1 [(required) = true];
  string justification  = 2 [(length) = "1-1024"];
  google.protobuf.Duration desired_ttl = 3;  // optional, capped by eligibility.max_ttl
}
```

### 4.4 `kacho-proto/cmd/protoc-gen-kacho-permissions/` — generator rewrite

- **Single entrypoint** that:
  1. Loads `PermissionsCatalogRoot.included_files`.
  2. For each file → walks every service → walks every RPC.
  3. For each RPC: extract `(kacho.iam.authz.v1.permission)` + `(required_relation)` + `(scope_extractor)` + `(permission_meta)` + `(google.api.http)`.
  4. **FAIL build** if RPC missing `permission` option (no silent skip). Sentinel value `"<exempt>"` explicitly allowed; «forgot to annotate» disallowed.
  5. Emit `gen/permission_catalog.json` (sorted by FQN, deterministic).
  6. **ALSO emit** `gen/rest_route_table.go` — same walk, output `[]restRoute` slice matching shape from `kacho-api-gateway/internal/middleware/rest_route_table_gen.go` (verified `:23-30`).
- **Makefile targets** (kacho-proto):
  - `make catalog`: regenerate both artefacts.
  - `make verify-catalog`: regen to temp dir, diff vs committed; non-zero exit on drift. CI invokes this.
- **Makefile targets** (kacho-api-gateway + kacho-iam):
  - `make sync-permission-catalog`: `cp ../kacho-proto/gen/permission_catalog.json internal/middleware/embed/` (or `internal/apps/kacho/seed/embedded/` for iam). `cp ../kacho-proto/gen/rest_route_table.go internal/middleware/rest_route_table_gen.go` (gateway only).
  - `make verify-permission-catalog`: sha256 of embedded copy vs sibling source; non-zero exit on drift.

### 4.5 `kacho-api-gateway/internal/middleware/permission_catalog.go` — catalog superset validation

Add to `PermissionCatalog` struct + new method:

```go
// ValidateAgainstRegisteredServices — fail-loud cold-path check.
// MUST be called from main() AFTER all gRPC handlers registered with grpcSrv.
// Iterates grpcSrv.GetServiceInfo(); for each service-method pair, asserts
// Lookup(<fqn>) returns (CatalogEntry, true). Missing → returns error.
//
// Callers (main.go) MUST log.Fatalf on error — process refuses to start.
// This closes the cold-start degrade-open hole when an RPC is added to proto
// but catalog forgot to sync.
func (c *PermissionCatalog) ValidateAgainstRegisteredServices(info map[string]grpc.ServiceInfo) error {
    var missing []string
    for svc, sInfo := range info {
        for _, m := range sInfo.Methods {
            fqn := svc + "/" + m.Name
            if _, ok := c.Lookup(fqn); !ok {
                missing = append(missing, fqn)
            }
        }
    }
    if len(missing) > 0 {
        sort.Strings(missing)
        return fmt.Errorf("permission catalog missing %d FQNs: %v", len(missing), missing)
    }
    return nil
}
```

Call site (kacho-api-gateway `cmd/kacho-api-gateway/main.go`):

```go
cat, err := middleware.LoadEmbeddedPermissionCatalog(catalogOverride)
if err != nil { log.Fatalf("permission catalog load: %v", err) }
if err := cat.ValidateAgainstRegisteredServices(grpcSrv.GetServiceInfo()); err != nil {
    log.Fatalf("permission catalog drift detected at startup: %v", err)
}
```

### 4.6 `kacho-api-gateway/internal/restmux/mux.go` — register missing iam services

In `iamAddr != ""` block (verified `:390-432`), append after existing registrations:

```go
// W2.A KAC-170 Chunk 3 — register Phase 7/7b services missing from KAC-132 batch.
if err := iampb.RegisterAccessReviewServiceHandlerFromEndpoint(ctx, mux, iamAddr, opts); err != nil {
    return nil, fmt.Errorf("register iam AccessReviewService: %w", err)
}
if err := iampb.RegisterJITEligibilityServiceHandlerFromEndpoint(ctx, mux, iamAddr, opts); err != nil {
    return nil, fmt.Errorf("register iam JITEligibilityService: %w", err)
}
if err := iampb.RegisterGdprErasureServiceHandlerFromEndpoint(ctx, mux, iamAddr, opts); err != nil {
    return nil, fmt.Errorf("register iam GdprErasureService: %w", err)
}
if err := iampb.RegisterConditionsServiceHandlerFromEndpoint(ctx, mux, iamAddr, opts); err != nil {
    return nil, fmt.Errorf("register iam ConditionsService: %w", err)
}
if err := iampb.RegisterFederationExchangeServiceHandlerFromEndpoint(ctx, mux, iamAddr, opts); err != nil {
    return nil, fmt.Errorf("register iam FederationExchangeService: %w", err)
}
```

In `iamInternalAddr != ""` block (verified `:443-447`), append:

```go
if err := iampb.RegisterInternalBreakGlassServiceHandlerFromEndpoint(ctx, mux, iamInternalAddr, opts); err != nil {
    return nil, fmt.Errorf("register iam InternalBreakGlassService: %w", err)
}
```

### 4.7 `kacho-iam/internal/apps/kacho/api/internal_iam/handler.go::ListPermissions` (#49)

Replace stub (verified line 122):

```go
func (h *Handler) ListPermissions(ctx context.Context, req *iamv1.ListPermissionsRequest) (*iamv1.ListPermissionsResponse, error) {
    if err := authzguard.RequireAuthenticated(ctx); err != nil {
        return nil, err
    }
    subjectID := req.GetSubjectId()
    if subjectID == "" {
        return nil, status.Error(codes.InvalidArgument, "subject_id required")
    }
    // Anti-enumeration: caller must be subject OR cluster-admin.
    if !authzguard.IsSelf(ctx, subjectID) && !h.isClusterAdminCaller(ctx) {
        return nil, status.Error(codes.NotFound, "subject not found")
    }
    // Aggregate permissions across access_bindings + group_memberships + roles.
    perms, err := h.permissionsAgg.PermissionsForSubject(ctx, subjectID)
    if err != nil {
        return nil, mapRepoErr(err)
    }
    // Filter against unified catalog (drop deprecated/typo'd permission strings).
    out := make([]*iamv1.Permission, 0, len(perms))
    for _, p := range perms {
        if entry, ok := h.catalog.LookupByPermission(p); ok && entry.Scope == "public" {
            out = append(out, &iamv1.Permission{
                Name:        p,
                Description: entry.Description,
                RiskLevel:   entry.RiskLevel,
            })
        }
    }
    return &iamv1.ListPermissionsResponse{Permissions: out}, nil
}
```

Reads catalog injected at construction (consumes unified catalog from §4.4).

### 4.8 `kacho-iam` Chunk 4 handler / usecase fixes (#1, #4, #5, #6, #14, #15, #46, #55, #27)

Per file:line specs in §0 preamble. Each fix has paired RED→GREEN test in §6.3.

- `internal/apps/kacho/api/role/handler.go:94-99` — parse `is_system=`/`account_id=` from `req.GetFilter()` (subset YC-compat per OQ-W2.A-10).
- `internal/apps/kacho/usecases/account/list.go` — replace post-Go OwnerUserID filter with `fga.ListObjects(principal, {admin,member}, account)` + `WHERE id = ANY($ids)`; retire `TODO(KAC-126)`.
- `internal/apps/kacho/usecases/user/list.go` + `internal/repo/.../user_repo.go` — FGA-based membership.
- `internal/apps/kacho/usecases/group/{add_member,get,update,list}.go` — `requireGrantAuthority` (parity with W1.6 §4.5 pattern); `list.go` adds scope-filter.
- `internal/apps/kacho/api/role/{update,delete}.go` — same owner→relation switch.
- `internal/apps/kacho/api/project/list.go` — grant-aware filter in SQL; paging consistent.
- `internal/apps/kacho/api/conditions/handler.go:51,68,85,160` — `FolderID`→`ProjectID` sweep (paired with proto rename).
- `internal/apps/kacho/usecases/role/create.go` — `Validate(ctx, catalog.SupportedPermissions())` rejects unsupported.
- `internal/apps/kacho/domain/types.go` — `roleNameSystemRe` synced with migration 0008.

### 4.9 `kacho-iam` migration `0026_service_account_project_scoped.sql` (#3)

```sql
-- 0026_service_account_project_scoped.sql
-- W2.A KAC-170 Chunk 4 #3 — drop legacy account_id scope, project_id required.
-- Greenfield: DROP TABLE + recreate. Gated by env flag KACHO_IAM_GREENFIELD_SA=1
-- (default true in dev; explicit opt-in in prod). Migrator binary prints warning.

-- +goose Up
-- DESTRUCTIVE: all existing service_account rows lost. Per CLAUDE.md major-rewrite
-- policy + memory feedback-no-strict-backward-compat-on-major-rewrite.md.
DROP TABLE IF EXISTS service_accounts CASCADE;

CREATE TABLE service_accounts (
    id                  TEXT PRIMARY KEY,
    project_id          TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    name                TEXT NOT NULL,
    description         TEXT NOT NULL DEFAULT '',
    enabled             BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- name unique within project (parity with vpc/compute naming rules).
    CONSTRAINT service_accounts_project_name_uniq UNIQUE (project_id, name)
);

CREATE INDEX service_accounts_project_idx ON service_accounts (project_id);

-- +goose Down
DROP TABLE IF EXISTS service_accounts CASCADE;
```

Migrator entrypoint (`cmd/kacho-iam-migrator/main.go`) — add safety gate:

```go
if migration == "0026" && os.Getenv("KACHO_IAM_GREENFIELD_SA") != "1" {
    log.Println("REFUSING to apply 0026: destructive SA-scope rewrite.")
    log.Println("Set KACHO_IAM_GREENFIELD_SA=1 to confirm. ALL service_account rows will be lost.")
    os.Exit(2)
}
if migration == "0026" {
    log.Println("APPLYING 0026 in 5s — destructive. Ctrl-C to abort.")
    time.Sleep(5 * time.Second)
}
```

### 4.10 `kacho-iam/internal/apps/kacho/api/service_account/*` + `internal/repo/.../service_account_repo.go` (#3 follow-up)

- `service_account_repo.go` — remove `account_id` column references; queries use `project_id`.
- `service_account/{create,update,list,get,delete}.go` — proto request now requires `project_id`; `account_id` removed.
- `service_account/list.go` — list by `projectId` (`ListServiceAccountsRequest.project_id` required).

### 4.11 `kacho-iam/cmd/kacho-iam/main.go` — wire unified catalog into seed & internal_iam handler

- Seed (`internal/apps/kacho/seed/permissions.go`) — load embedded catalog → derive system roles deterministically.
- `internal_iam.Handler` construction — inject `catalog *middleware.PermissionCatalog` for §4.7 `ListPermissions`.

---

## 5. Test discipline (§Запрет #12) — RED first, GREEN per finding, evidence in PR

PR (per repo) обязан содержать **в указанном порядке**:

1. **RED phase commit** (testing-only commit, one per repo): all §6 integration tests + §6.5 newman cases written and committed BEFORE any impl. CI red on this commit (compile-fail OR test-fail).
2. **GREEN phase commits**: per-finding impl driving each RED test → GREEN. One logical commit per finding (some Chunk-3 findings batch together because they share the regen step).
3. **Per-finding RED→GREEN evidence** в PR description: для каждой задачи table-row `# / RED-test-name / RED-output-before / GREEN-output-after`. PR без этой таблицы — отказ от `acceptance-reviewer`.
4. **Newman cases** added к `project/kacho-iam/tests/newman/cases/` (per-domain files + new `w2-a-nm-closeout.py`); regenerate via `gen.py`; verify `run.sh` picks up; verify CI matrix gate still green; verify total cases count grew by ≥ N (where N = §6.5 new-case count).
5. **Catalog drift gate** (`make verify-permission-catalog`): integral part of CI for ALL three repos. Если drift detected → PR red, нельзя merge.
6. **Catalog superset validation gate** (§4.5): integration test stands up real gateway against bufconn-registered all-iam-services, asserts no missing FQN.

---

## 6. Сценарии (Given-When-Then)

> All scenarios use Postgres testcontainer (kacho-iam migrations 0001-0026 applied) + fake/real OpenFGA + bufconn gRPC server with full iam service registration. Catalog test fixtures: `testdata/permission_catalog_baseline.json` (snapshot for drift detection in unit tests).

### 6.1 Positive scenarios (happy paths)

#### Сценарий W2.A-CAT-UNIFIED-01 — single regen produces byte-identical embeds across three repos

**ID**: W2.A-CAT-UNIFIED-01 (closes #45 happy path)

**Given** kacho-proto on branch `KAC-170-proto-catalog-unify`
**And** `PermissionsCatalogRoot.included_files` lists all iam service-proto files (verified §4.1)

**When** `make catalog` is invoked in kacho-proto
**And** `make sync-permission-catalog` is invoked in kacho-api-gateway (sibling)
**And** `make sync-permission-catalog` is invoked in kacho-iam (sibling)

**Then** `kacho-proto/gen/permission_catalog.json` byte-equals `kacho-api-gateway/internal/middleware/embed/permission_catalog.json`
**And** byte-equals `kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json`
**And** `make verify-permission-catalog` in all three repos exits 0
**And** catalog entry count is ≥ 295 (was 281 in gateway baseline; new entries — AccessReview/JITEligibility/Gdpr/InternalBreakGlass/Conditions/FederationExchange RPCs)

---

#### Сценарий W2.A-CAT-VALIDATE-02 — kacho-api-gateway startup validates catalog covers all registered FQNs

**ID**: W2.A-CAT-VALIDATE-02 (closes #28/#45 happy path)

**Given** kacho-api-gateway built with synced catalog
**And** all gRPC services registered via standard `RegisterXServer` in `main.go`

**When** `cat.ValidateAgainstRegisteredServices(grpcSrv.GetServiceInfo())` is called at startup

**Then** returns nil (no error)
**And** process continues to listener-bind

---

#### Сценарий W2.A-PHASE7-REST-REACHABLE-03 — Phase 7 RPCs now reachable via REST

**ID**: W2.A-PHASE7-REST-REACHABLE-03 (closes #29/#30 happy)

**Given** kacho-api-gateway built with §4.6 restmux additions
**And** authenticated principal `usr_admin` with admin@account binding

**When** `POST /iam/v1/accessReviewCampaigns/{id}/items/{item}:approve` with valid body
**And** `POST /iam/v1/jitEligibilities/{id}:activate` with valid body
**And** `POST /iam/v1/gdprErasureRequests` with valid body
**And** `GET /iam/v1/conditions/{id}`
**And** `POST /iam/v1/federationExchange:exchangeToken` with valid body

**Then** each call returns 200/202 (not 404); response has `Operation` envelope shape per §«API contract» (mutations) or resource (Get)
**And** per-RPC authz middleware logs `outcomeAllow` for each (verified via metrics scrape)

---

#### Сценарий W2.A-LIST-PERMISSIONS-04 — InternalIAM.ListPermissions returns catalog-derived perms

**ID**: W2.A-LIST-PERMISSIONS-04 (closes #49 happy)

**Given** subject `usr_alice` has FGA bindings: `admin@account:acc_a` (grants `iam.accounts.update`, `iam.users.invite`, ...); `viewer@project:prj_b` (grants `vpc.networks.get`, ...)

**When** `InternalIAMService.ListPermissions(subject_id=usr_alice)` called with ctx principal=usr_alice (self-call)

**Then** response.Permissions contains union of permission-names from both bindings
**And** every returned permission has matching catalog entry (description, risk_level populated)
**And** no `iam.s_a_keyses.*`-style deprecated strings appear (#44 closed)

---

#### Сценарий W2.A-ROLE-LIST-FILTER-05 — RoleService.List parses is_system/account_id

**ID**: W2.A-ROLE-LIST-FILTER-05 (closes #1 happy)

**Given** roles in DB: 3 system roles (`roles/iam.viewer`, `roles/iam.editor`, `roles/iam.admin`); 2 custom roles in `acc_a`; 1 custom in `acc_b`
**And** ctx principal `usr_admin` (admin on `acc_a`)

**When** `RoleService.List(filter="is_system=true")`

**Then** returns ONLY 3 system roles

**When** `RoleService.List(filter="account_id=\"acc_a\"")`

**Then** returns 3 system + 2 custom-from-acc_a = 5 roles (parity with #1 fix spec)
**And** does NOT return 1 custom-from-acc_b

**When** `RoleService.List(filter="")`

**Then** returns 3 system roles ONLY (no accountId → system-only per spec)

---

#### Сценарий W2.A-ACCOUNT-LIST-FGA-06 — invited admin sees account via FGA-derived list

**ID**: W2.A-ACCOUNT-LIST-FGA-06 (closes #4 happy)

**Given** account `acc_corp` (owner: `usr_owner`); FGA binding `admin@account:acc_corp` for `usr_inv` (invited admin)
**And** ctx principal `usr_inv`

**When** `AccountService.List()`

**Then** response contains `acc_corp` (was empty pre-W2.A — post-Go filter `OwnerUserID == principal.ID` was excluding invited admin)

---

### 6.2 Negative scenarios (spec-violation / drift detection)

#### Сценарий W2.A-CAT-DRIFT-DETECT-07 — catalog drift breaks CI

**ID**: W2.A-CAT-DRIFT-DETECT-07 (closes #45 negative)

**Given** kacho-proto on branch with intentional permission_catalog.json edit (1 entry deleted)

**When** CI runs `make verify-permission-catalog` in kacho-api-gateway

**Then** non-zero exit; CI fails; PR cannot merge
**And** error message identifies drift: `permission_catalog: sha256 mismatch (gateway-embed != kacho-proto/gen/...)`

---

#### Сценарий W2.A-CAT-MISSING-FQN-08 — gateway refuses to start on catalog-FQN-missing

**ID**: W2.A-CAT-MISSING-FQN-08 (closes #28/#45 negative; closes superset validation gap)

**Given** kacho-api-gateway with intentionally stale catalog (one registered service-FQN missing from catalog JSON, e.g. `kacho.cloud.iam.v1.AccessReviewService/ApproveItem` removed)

**When** `main()` calls `cat.ValidateAgainstRegisteredServices(...)`

**Then** returns error mentioning the missing FQN
**And** `main()` calls `log.Fatalf` (verified via test harness that intercepts os.Exit)
**And** process exit code != 0; pod CrashLoopBackOff in helm rollout

---

#### Сценарий W2.A-ANON-AFTER-FIX-09 — anonymous on newly catalogued RPC → deny

**ID**: W2.A-ANON-AFTER-FIX-09 (closes #19 negative; parity with W1.6 §6.1 anti-anon)

**Given** kacho-api-gateway with W2.A unified catalog
**And** anonymous ctx (no JWT)

**When** `POST /iam/v1/conditions:evaluate` with valid body (RPC previously inaccessible due to catalog-miss → fail-closed deny anyway; now catalogued)

**Then** returns 401 Unauthenticated (per W1.3 fail-closed for missing creds) — not 403, not 404, not 200
**And** authz-middleware metric `kacho_authz_decisions{outcome="unauthenticated"}` incremented

**When** same call with valid JWT for principal `usr_no_perms` (no FGA grant on condition scope)

**Then** returns 403 PermissionDenied with `reason` mentioning required relation

---

#### Сценарий W2.A-SPOOFED-CATALOG-REJECTED-10 — ConfigMap-override catalog must match shape

**ID**: W2.A-SPOOFED-CATALOG-REJECTED-10 (closes catalog tampering attack vector)

**Given** kacho-api-gateway started with `KACHO_API_GATEWAY_PERMISSION_CATALOG_FILE=/etc/kacho/spoofed.json`
**And** `/etc/kacho/spoofed.json` contains valid JSON but missing `fqn` field on every entry (corrupted shape)

**When** `LoadEmbeddedPermissionCatalog("/etc/kacho/spoofed.json")` is called

**Then** returns error «catalog entry missing required field `fqn`»
**And** caller (`main.go`) calls `log.Fatalf`; process refuses to start

> NOTE: This doesn't gate signing/integrity (out of scope; ConfigMap mount trusts the mount); it gates *shape* — spoofed catalogs with bad shape can't degrade behaviour.

---

#### Сценарий W2.A-SA-ACCOUNT-SCOPED-REJECTED-11 — old account_id SA Create → InvalidArgument

**ID**: W2.A-SA-ACCOUNT-SCOPED-REJECTED-11 (closes #3 negative)

**Given** kacho-iam with migration 0026 applied; proto has `project_id` required, no `account_id`
**And** client sends old-shape `CreateServiceAccountRequest{account_id="acc_x", name="sva_legacy"}` (no project_id)

**When** `ServiceAccountService.Create(...)`

**Then** returns `codes.InvalidArgument` with text `"Illegal argument project_id: required"` (proto-validation level)

---

#### Сценарий W2.A-GROUP-OWNER-ONLY-FIXED-12 — delegated admin can AddMember (was owner-only)

**ID**: W2.A-GROUP-OWNER-ONLY-FIXED-12 (closes #6 negative→positive)

**Given** group `grp_x` in `acc_corp` (owner=usr_owner)
**And** FGA binding `admin@account:acc_corp` for `usr_inv` (invited admin, NOT owner)
**And** ctx principal `usr_inv`

**When** `GroupService.AddMember(group_id=grp_x, member_type=user, member_id=usr_target)`

**Then** Operation completes successfully (was 403 pre-W2.A: `RequireOwnerMatchesPrincipal` returned PermissionDenied)
**And** `group_members` row exists for (grp_x, usr_target)

---

### 6.3 Edge / concurrency scenarios

#### Сценарий W2.A-REGEN-CONCURRENT-13 — concurrent `make catalog` produces deterministic output

**ID**: W2.A-REGEN-CONCURRENT-13 (closes regen-determinism edge)

**Given** kacho-proto repo on clean checkout

**When** `make catalog` invoked 5 times in parallel (5 goroutines / 5 shell invocations)

**Then** all 5 invocations produce byte-identical `gen/permission_catalog.json`
**And** all 5 produce byte-identical `gen/rest_route_table.go`
**And** sha256 stable across runs

> Mitigates risk: plugin uses `sort.Strings` on output keys; map iteration ordered.

---

#### Сценарий W2.A-STALE-EMBED-FAIL-START-14 — gateway with stale embed fails-startup-not-degrades-open

**ID**: W2.A-STALE-EMBED-FAIL-START-14 (closes cold-start degrade hole)

**Given** kacho-api-gateway built with embed from previous catalog version (missing 5 FQNs that current proto introduced)
**And** kacho-iam deployed with new proto-registered handlers (5 new FQNs registered with grpcSrv)

**When** kacho-api-gateway pod starts; `main()` runs `cat.ValidateAgainstRegisteredServices(...)`

**Then** returns error listing 5 missing FQNs
**And** `log.Fatalf` → exit code != 0 → pod CrashLoopBackOff → helm rollout fails
**And** alert `KachoCatalogStartupDriftDetected` fires (W3 observability — alert exists post-W3; W2.A only ensures the failure mode is fail-loud)

> Inverse of degrade-open: in W1.3 deployed shape, missing FQN → `Lookup`-miss → `outcomeDeny` → request denied; but with new RPCs added, denials would surface as «mysterious 403» rather than catalog problem. This scenario ensures the catalog-drift is detected at pod startup, not at first request.

---

#### Сценарий W2.A-SCOPE-DBLOOKUP-15 — Conditions Update authz scope resolved via DB-lookup

**ID**: W2.A-SCOPE-DBLOOKUP-15 (closes #34 edge)

**Given** condition `cnd_t15` exists in DB with `scope_type=project`, `scope_id=prj_a`
**And** principal `usr_admin_b` with FGA `admin@project:prj_b` (NOT prj_a)

**When** `UpdateCondition(condition_id=cnd_t15, ...)`
**And** gateway middleware extractor invokes `from_db_lookup` (peer call to `InternalConditionsService.GetScope(cnd_t15)`)
**And** lookup returns `(project, prj_a)`

**Then** FGA Check on `(usr_admin_b, editor, project:prj_a)` returns NotFound/deny
**And** middleware returns 403

---

### 6.4 Anti-spoof / authority-mismatch tests (Chunk 4 secondary)

#### Сценарий W2.A-PROJ-LIST-PAGING-16 — ProjectService.List paging consistent under filter

**ID**: W2.A-PROJ-LIST-PAGING-16 (closes #15 paging bug)

**Given** 100 projects in DB; principal has admin on 30 of them (mixed positions)
**And** request `page_size=10`

**When** repeatedly call `ListProjects(page_token=...)` until `next_page_token == ""`

**Then** 3 pages returned, each with exactly 10 items (was: short pages with non-empty next pre-W2.A — filter-after-page)
**And** total items returned across pages = 30
**And** no duplicates, no skips

---

#### Сценарий W2.A-CONDITIONS-PROJECT-SCOPED-17 — Conditions CRUD via project_id

**ID**: W2.A-CONDITIONS-PROJECT-SCOPED-17 (closes #27)

**Given** project `prj_x` with FGA admin@principal=`usr_p`

**When** `CreateCondition(scope_type=project, scope_id=prj_x, name="...", expression="...")`

**Then** Operation completes; condition row has `scope_id=prj_x` (not `folder_id`); GET returns it with `project_id` populated in proto response (`folder_id` field removed)

---

#### Сценарий W2.A-ROLE-UNSUPPORTED-PERM-REJECTED-18 — Create role with unknown permission → InvalidArgument

**ID**: W2.A-ROLE-UNSUPPORTED-PERM-REJECTED-18 (closes #46)

**Given** unified catalog supports permission `iam.users.invite`
**And** does NOT support `iam.users.absorb_minds` (non-existent permission)

**When** `RoleService.Create(name="roles/custom.evil", permissions=["iam.users.absorb_minds"])`

**Then** returns `codes.InvalidArgument` with text mentioning `iam.users.absorb_minds` and `not in supported permission catalog`

---

### 6.5 Newman E2E — closing strategy

> **Goal**: close the 23-finding surface with regression-proof newman coverage. New cases added to existing per-domain files + new `w2-a-nm-closeout.py` for cross-domain regression. All authoritative authz behaviour covered by **post-fix RED-first** newman.

| Existing file → expected outcome change | New cases needed |
|---|---|
| `authz-deny.py:41` (anon role list) | Behaviour stays (anon→401). OQ-W2.A-1 resolves contradiction in favour of code; acceptance KAC-121 §5:103 updated separately (follow-up KAC). |
| `iam-role.py` | NEW: `ROLE-LIST-NO-ACCOUNT-SYSTEM-ONLY`, `ROLE-LIST-WITH-ACCOUNT-SCOPED`, `ROLE-LIST-NO-FOREIGN-CUSTOM`, `ROLE-CREATE-UNSUPPORTED-PERM-DENY` |
| `iam-account.py` | NEW: `ACCOUNT-LIST-INVITED-ADMIN-SEES`, `ACCOUNT-LIST-OUTSIDER-EMPTY` |
| `iam-user.py` | NEW: `USER-LIST-FGA-MEMBERSHIP` (cross-account membership), `USER-LIST-NO-OWNER-ONLY` |
| `iam-group.py` | NEW: `GROUP-ADDMEMBER-DELEGATED-ADMIN-ALLOW`, `GROUP-LIST-SCOPED` |
| `iam-project.py` | NEW: `PROJECT-LIST-INVITED-ADMIN-SEES`, `PROJECT-LIST-PAGING-CONSISTENT` |
| `iam-service-account.py` | REWRITE: SA cases must use `projectId`; `SA-CREATE-NO-PROJECT-ID-INVALIDARG` |
| NEW: `iam-conditions.py` | `CONDITIONS-PROJECT-SCOPED-CRUD`, `CONDITIONS-UPDATE-DBLOOKUP-SCOPE` |
| NEW: `iam-jit-eligibility.py` (rename if exists) | `JIT-ACTIVATE-RPC-REACHABLE`, `JIT-ACTIVATE-ANON-DENY` |
| NEW: `iam-access-review.py` | `REVIEW-RPC-REACHABLE-POST-W2A` (covers #29 closure for AccessReview) |
| NEW: `iam-gdpr.py` | `GDPR-ERASURE-RPC-REACHABLE-POST-W2A` (covers #29 closure) |
| NEW: `iam-federation.py` | `FED-EXCHANGE-RPC-REACHABLE-POST-W2A` (covers #19 closure for Federation) |
| `iam-internal-only-check.py` | NEW: `INTERNAL-LISTPERMISSIONS-OK` (#49 closure); `INTERNAL-LISTPERMISSIONS-ANON-DENY` |
| NEW: `w2-a-nm-closeout.py` | Cross-cutting: `CATALOG-DRIFT-DETECTED-VIA-METRICS`, `SAKEY-NEW-PERM-STRINGS` (#44), `INTERNAL-BREAKGLASS-NOT-ON-PUBLIC-LISTENER` (§Запрет #6 regression) |

**Suite-level commitment**: post-W2.A merge:
- `iam-role`, `iam-account`, `iam-user`, `iam-group`, `iam-project`, `iam-service-account`, `iam-conditions` (NEW), `iam-jit-eligibility` (NEW/expanded), `iam-access-review` (NEW), `iam-gdpr` (NEW), `iam-federation` (NEW), `iam-internal-only-check`, `w2-a-nm-closeout` (NEW) — **all GREEN**.
- Total newman cases (1144 baseline post-W1.6 if W1.6 closes 87) grows by ≥ 25 (one-per-finding minimum + cross-cutting).
- `coverage.py --min 100` (W0.1 gate) still passes — every newly-catalogued RPC has ≥1 newman case.

### 6.6 Catalog enumeration table-test

#### Сценарий W2.A-CAT-COVERAGE-19 — coverage.py asserts every catalog FQN has ≥1 newman case

**ID**: W2.A-CAT-COVERAGE-19

**Given** unified catalog with N entries
**And** newman case suite enumerated via `gen.py`

**When** `tests/newman/coverage.py --min 100 --catalog .../permission_catalog.json` runs

**Then** every FQN in catalog with `scope=public` has ≥1 corresponding newman case (matched by FQN string in case metadata)
**And** every FQN with `scope=internal_admin` has either ≥1 case in `iam-internal-only-check.py` OR explicit `# wontfix-newman` annotation
**And** coverage report shows 100%

---

## 7. Definition of Done

### 7.1 Per-finding checklist

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc; OQ-W2.A-1/2/5/6/9 resolved (others recommendation-accepted)
- [ ] Branches created in each repo: `KAC-170-proto-catalog-unify` (kacho-proto), `KAC-170-gateway-catalog-consumer` (kacho-api-gateway), `KAC-170-iam-spec-drift` (kacho-iam)
- [ ] **RED phase commit** per repo: all §6 tests + §6.5 newman cases written, regenerated, CI red — RED evidence in PR description per finding
- [ ] **GREEN phase commits** (logical commit per finding, ordered by dependency):

  **Chunk 3 (kacho-proto → kacho-api-gateway):**
  - [ ] #31 — `PermissionsCatalogRoot` proto + plugin walk fail-on-missing-permission (RED W2.A-CAT-UNIFIED-01 → GREEN)
  - [ ] #44 — SAKey permission strings (RED `SAKEY-NEW-PERM-STRINGS` newman → GREEN)
  - [ ] #33 — authorize_service scope_extractor (RED integration `Test_AuthorizeService_Check_ScopeExtractor` → GREEN)
  - [ ] #34 — conditions_service scope_extractor + from_db_lookup (RED W2.A-SCOPE-DBLOOKUP-15 → GREEN)
  - [ ] #38 — compliance_report_service dynamic scope_extractor (RED integration → GREEN)
  - [ ] #32 — ActivateJIT proto RPC (RED `JIT-ACTIVATE-RPC-REACHABLE` newman → GREEN)
  - [ ] #19/#28/#45 — unified catalog distribution + drift gates (RED W2.A-CAT-UNIFIED-01, W2.A-CAT-DRIFT-DETECT-07 → GREEN)
  - [ ] #29/#30 — restmux + route-table regen for Phase 7/7b (RED W2.A-PHASE7-REST-REACHABLE-03 → GREEN)
  - [ ] catalog superset validation (RED W2.A-CAT-MISSING-FQN-08, W2.A-STALE-EMBED-FAIL-START-14 → GREEN)
  - [ ] #49 — InternalIAM.ListPermissions impl (RED W2.A-LIST-PERMISSIONS-04 → GREEN)

  **Chunk 4 (kacho-iam):**
  - [ ] #1 — RoleService.List filter parse (RED W2.A-ROLE-LIST-FILTER-05 → GREEN)
  - [ ] #46/#55 — role validation + regex sync (RED W2.A-ROLE-UNSUPPORTED-PERM-REJECTED-18 → GREEN)
  - [ ] #4/#5 — Account/User List via FGA (RED W2.A-ACCOUNT-LIST-FGA-06 → GREEN; existing TODO retired)
  - [ ] #6/#14 — Group authority via relation; Group.List scope-filter (RED W2.A-GROUP-OWNER-ONLY-FIXED-12 → GREEN)
  - [ ] #15 — ProjectService.List FGA + paging (RED W2.A-PROJ-LIST-PAGING-16 → GREEN)
  - [ ] #3 — SA project-scoped migration 0026 (RED W2.A-SA-ACCOUNT-SCOPED-REJECTED-11 → GREEN)
  - [ ] #27 — Conditions folder→project sweep (RED W2.A-CONDITIONS-PROJECT-SCOPED-17 → GREEN)
  - [ ] #7 — OQ-W2.A-1 follow-up KAC opened (acceptance KAC-121 §5:103 update) — referenced in PR description, NOT in this PR's diff
- [ ] Catalog coverage gate (`coverage.py --min 100`) GREEN (W2.A-CAT-COVERAGE-19)
- [ ] `make verify-permission-catalog` GREEN in all three repos (no drift)
- [ ] Catalog startup validation integration test (W2.A-CAT-MISSING-FQN-08) GREEN — also wired as CI gate in kacho-api-gateway smoke job
- [ ] Newman cases (§6.5 table) all GREEN; ≥25 new cases; existing failing-suite count unchanged or reduced
- [ ] `make e2e` smoke on dev-kind shows: Phase 7 RPCs reachable via REST; invited admin sees own account; system roles only when no account_id filter; SA Create rejects missing project_id; group AddMember works for delegated admin
- [ ] kacho-proto CI green (build/lint/buf-lint/buf-breaking/test/`verify-catalog`); kacho-api-gateway CI green (build/lint/gosec/trivy/govulncheck/integration/newman-e2e); kacho-iam CI green (same set + migration test)
- [ ] All three PRs merged in dependency order (kacho-proto → gateway → iam); CI on dependent repos pinned to feature-branch during the merge train, then unpinned
- [ ] Branches deleted post-merge in all three repos (`gh pr merge --delete-branch` per CLAUDE.md)

### 7.2 Global DoD

- [ ] **NO new TODO/FIXME/XXX in diff** (CLAUDE.md §Запрет #11 enforced); pre-existing TODOs at `account/list.go:50` and `role/handler.go:99` retired in same PR
- [ ] NO `yandex` references in handwritten code/tests/comments
- [ ] All RED→GREEN evidence pairs documented in PR descriptions (per CLAUDE.md §Запрет #12)
- [ ] Vault обновлён (§8 below)
- [ ] YouTrack KAC-170: In Progress on impl start; PR links commented per-repo; Done on merge + smoke + newman GREEN; W2 epic tracker updated
- [ ] Master plan `2026-05-23-iam-prod-ready-master.md` W2 row updated: «Поток A» → ✅ done + date; baseline metrics updated (catalog drift eliminated; spec-drift findings 11 closed)
- [ ] W3 unblock signal — explicit comment in master plan + KAC-134

---

## 8. Vault discipline

### 8.1 Notes to create/update (CLAUDE.md §«Vault discipline» обязательно)

| Path | Action | Content |
|---|---|---|
| `obsidian/kacho/KAC/KAC-170.md` | CREATE | Trail per CLAUDE.md template; status, type=epic, repos=kacho-proto+gateway+iam, PRs (filled on merge), acceptance checklist mirrored from §7, link to this doc, links to related KAC (134, 164) |
| `obsidian/kacho/packages/proto-iam-permissions-catalog.md` | CREATE | `PermissionsCatalogRoot` schema, generator workflow, `sync-permission-catalog` distribution flow, drift-gate semantics |
| `obsidian/kacho/packages/api-gateway-middleware-authz.md` | UPDATE | Note startup `ValidateAgainstRegisteredServices` (§4.5); fail-loud cold path; embed source-of-truth synced from kacho-proto |
| `obsidian/kacho/packages/iam-internal-iam-handler.md` | CREATE if missing / UPDATE | Note `ListPermissions` realised (#49); aggregates from unified catalog filtered by FGA membership |
| `obsidian/kacho/edges/api-gateway-to-iam-conditions.md` | CREATE | New runtime edge: gateway → `InternalConditionsService.GetScope` for `from_db_lookup` extractor (#34); peer-call same-cluster, ms latency |
| `obsidian/kacho/resources/iam-service-account.md` | UPDATE | Note `project_id` required (was account-scoped); migration 0026 drop+recreate; greenfield policy with env flag |
| `obsidian/kacho/resources/iam-role.md` | UPDATE | Note system vs custom (account-scoped) distinction enforced by `List` filter (#1); `Permissions.Validate` enforces supported-catalog allow-list (#46); regex sync with migration 0008 (#55) |
| `obsidian/kacho/resources/iam-account.md` | UPDATE | Note `List` is FGA-derived (admin/member relations), not owner-only (#4) |
| `obsidian/kacho/resources/iam-project.md` | UPDATE | Note `List` is FGA-derived + paging consistent (#15) |
| `obsidian/kacho/resources/iam-group.md` | UPDATE | Note AddMember/Get/Update/List use `requireGrantAuthority` (relation-based, not owner-only) (#6/#14) |
| `obsidian/kacho/resources/iam-condition.md` | CREATE if missing | Note `scope_id`/`scope_type` (was `folder_id`); CRUD via project_id (#27); authz extractor from_db_lookup (#34) |
| `obsidian/kacho/resources/iam-jit-eligibility.md` | UPDATE | Note `ActivateJIT` RPC declared and reachable (#32) |
| `obsidian/kacho/resources/iam-sa-key.md` | UPDATE | Note permission strings renamed `iam.serviceAccountKeys.*` (#44) |
| `obsidian/kacho/rpc/iam-access-review.md` | CREATE if missing | Phase 7 service now REST-reachable post W2.A; method table |
| `obsidian/kacho/rpc/iam-jit-eligibility.md` | UPDATE | Add `ActivateJIT` to method table |
| `obsidian/kacho/rpc/iam-conditions.md` | CREATE if missing | Method table; note scope_extractor uses from_db_lookup |
| `obsidian/kacho/rpc/iam-gdpr-erasure.md` | CREATE if missing | Phase 7b service now REST-reachable post W2.A |
| `obsidian/kacho/rpc/iam-federation-exchange.md` | CREATE if missing | Public via REST post W2.A; method table |
| `obsidian/kacho/rpc/iam-internal-iam.md` | UPDATE | Note `ListPermissions` realised (no longer Unimplemented) (#49) |
| `obsidian/kacho/architecture.md` | UPDATE | Note three-catalog drift eliminated; ONE generator-driven distribution (#45); cold-start fail-loud (§4.5) |

### 8.2 Cross-references

In KAC-170.md «Затронутые сущности vault» section, link all paths above + `[[../KAC/KAC-134]]` (parent epic) + `[[../KAC/KAC-164]]` (W1.6 prereq).

---

## 9. Traceability — finding-id ↔ scenario-id ↔ source-line ↔ test name

| Finding (rem. plan §1.3/§1.4) | GWT Scenarios | Code-сайт (verified 2026-05-24) | Тест-имя |
|---|---|---|---|
| **#19** (Chunk 3, P1) | W2.A-CAT-VALIDATE-02, W2.A-ANON-AFTER-FIX-09, W2.A-CAT-MISSING-FQN-08 | `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` (281 entries — verified) | `Test_PermissionCatalog_AllRegisteredFqnsCovered` |
| **#28** (Chunk 3, P1) | W2.A-PHASE7-REST-REACHABLE-03, W2.A-CAT-VALIDATE-02 | same as #19 + `internal/middleware/rest_route_table_gen.go` (334 routes) | `Test_PermissionCatalog_Phase7Coverage` |
| **#29** (Chunk 3, P1) | W2.A-PHASE7-REST-REACHABLE-03 | `kacho-api-gateway/internal/restmux/mux.go:390-432` (iam-block; verified missing Register* for AccessReview/JITEligibility/Gdpr/Conditions/Federation) | newman cases per service in §6.5 |
| **#30** (Chunk 3, P1) | W2.A-PHASE7-REST-REACHABLE-03 | `kacho-api-gateway/internal/middleware/rest_route_table_gen.go` (334 routes) | `Test_RestRouteTable_HasPhase7Routes` |
| **#31** (Chunk 3, P1) | W2.A-CAT-UNIFIED-01 | `kacho-proto/proto/kacho/cloud/iam/v1/permissions_catalog.proto` (no `PermissionsCatalogRoot`) | `Test_CatalogGenerator_FailsOnUnreferencedService` |
| **#32** (Chunk 3, P1) | W2.A-PHASE7-REST-REACHABLE-03 (ActivateJIT subset) | `kacho-iam/internal/service/phase7_jit_service.go` (impl) + `kacho-proto/proto/.../jit_eligibility_service.proto` (no RPC) | newman `JIT-ACTIVATE-RPC-REACHABLE` |
| **#33** (Chunk 3, P2) | (covered by integration test on AuthorizeService) | `kacho-proto/proto/.../authorize_service.proto::Check/ListObjects/ListSubjects/CheckRelation scope_extractor` (verified) | `Test_AuthorizeService_Check_ScopeExtractor_NotProject` |
| **#34** (Chunk 3, P2) | W2.A-SCOPE-DBLOOKUP-15 | `kacho-proto/proto/.../conditions_service.proto::Get/Update/Delete/Evaluate scope_extractor` (verified 6 sites) | `Test_ConditionsScopeExtractor_DbLookup` |
| **#38** (Chunk 3, P2) | (covered by integration on compliance_report) | `kacho-proto/proto/.../compliance_report_service.proto::GenerateAccessReport/List` (verified `object_type:"project"` hardcoded) | `Test_ComplianceReport_DynamicScopeType` |
| **#44** (Chunk 3, P3) | (newman) | `kacho-proto/proto/.../sa_key_service.proto` (verified `iam.issue_s_a_keies.issue`, `iam.s_a_keyses.list`, `iam.revoke_s_a_keies.revoke`) | newman `SAKEY-NEW-PERM-STRINGS` |
| **#45** (Chunk 3, P1) | W2.A-CAT-UNIFIED-01, W2.A-CAT-DRIFT-DETECT-07, W2.A-STALE-EMBED-FAIL-START-14 | seed (236), gateway-embed (281), implied gen (>295) — verified counts | `Test_PermissionCatalog_ByteIdenticalAcrossRepos`, `Test_PermissionCatalog_StartupSupersetValidation` |
| **#49** (Chunk 3, P1) | W2.A-LIST-PERMISSIONS-04 | `kacho-iam/internal/apps/kacho/api/internal_iam/handler.go:122` (verified Unimplemented stub) | `Test_InternalIAM_ListPermissions_AggregatedFromCatalog` |
| **#1** (Chunk 4, P1) | W2.A-ROLE-LIST-FILTER-05 | `kacho-iam/internal/apps/kacho/api/role/handler.go:94-99` (verified TODO + only Filter pass-through) | `Test_RoleService_List_FilterParsing` |
| **#3** (Chunk 4, P1) | W2.A-SA-ACCOUNT-SCOPED-REJECTED-11 | `kacho-proto/proto/.../service_account.proto` (verified `account_id=2` + `project_id=6` dual); `kacho-iam/internal/repo/.../service_account_repo.go` | `Test_ServiceAccount_RequiresProjectId`, `Test_ServiceAccount_MigrationDropRecreate` |
| **#4** (Chunk 4, P1) | W2.A-ACCOUNT-LIST-FGA-06 | `kacho-iam/internal/apps/kacho/usecases/account/list.go:32-58` (verified post-Go filter + TODO at :50) | `Test_AccountList_FgaAdminAndMember`, `Test_AccountList_TodoRetired` |
| **#5** (Chunk 4, P2) | (parity test similar to #4) | `kacho-iam/internal/apps/kacho/usecases/user/list.go` | `Test_UserList_FgaMembership` |
| **#6** (Chunk 4, P1) | W2.A-GROUP-OWNER-ONLY-FIXED-12 | `kacho-iam/internal/apps/kacho/usecases/group/add_member.go:65` (verified `RequireOwnerMatchesPrincipal`) | `Test_GroupAddMember_DelegatedAdminAllowed`, `Test_RoleUpdate_DelegatedAdminAllowed`, `Test_RoleDelete_DelegatedAdminAllowed` |
| **#7** (Chunk 4, P1) | (not in W2.A diff — opens follow-up KAC) | — | — (OQ-W2.A-1 follow-up KAC) |
| **#14** (Chunk 4, P2) | (covered by `Test_GroupList_ScopeFiltered`) | `kacho-iam/internal/apps/kacho/usecases/group/list.go` | `Test_GroupList_ScopeFiltered` |
| **#15** (Chunk 4, P2) | W2.A-PROJ-LIST-PAGING-16 | `kacho-iam/internal/apps/kacho/api/project/list.go` | `Test_ProjectList_FgaAware_PagingConsistent` |
| **#27** (Chunk 4, P2) | W2.A-CONDITIONS-PROJECT-SCOPED-17 | `kacho-iam/internal/apps/kacho/api/conditions/handler.go:51,68,85,160` (verified 4 sites) + `conditions_service.proto` | `Test_Conditions_ProjectIdSweep` |
| **#46** (Chunk 4, P2) | W2.A-ROLE-UNSUPPORTED-PERM-REJECTED-18 | `kacho-iam/internal/apps/kacho/usecases/role/create.go`; `internal/apps/kacho/domain/types.go` | `Test_RoleCreate_RejectsUnsupportedPermission` |
| **#55** (Chunk 4, P2) | (paired with #46) | `kacho-iam/internal/apps/kacho/domain/types.go` `roleNameSystemRe` | `Test_RoleName_RegexMatchesMigration0008` |

---

## 10. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#2/#5/#6/#10/#11/#12/#13; vault discipline; cross-repo dependency graph)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- API-gateway-specific: `../../project/kacho-api-gateway/CLAUDE.md`
- Proto-specific: `../../project/kacho-proto/CLAUDE.md`
- Source of findings: `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 3 + §1.4 Chunk 4
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` W2 row («Поток A»)
- Predecessor acceptance docs (must be `main`-merged):
  - `sub-phase-W1.3-gateway-authz-failclosed-acceptance.md` (fail-closed deny on Lookup-miss — required pre-W2.A so superset-validation has real teeth)
  - `sub-phase-W1.4-principal-propagation-acceptance.md` (gateway trusts principal-id; required so iam handlers see real caller)
  - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md` (read-only allowlist baseline; anti-anon table-test scaffold reused for §6.6)
- Related Phase 7/7b registrations history (KAC-132 added JitPending/ComplianceReport/Authorize/SAKey to gateway): see `kacho-api-gateway/internal/restmux/mux.go:419-432` comments
- Reference impl (parity for #6 authority check): `kacho-iam/internal/apps/kacho/api/access_binding/helpers.go::requireGrantAuthority` (existing pattern shipped in W1.5/W1.6)
- Reference impl (parity for #4 FGA-list): `kacho-iam/internal/apps/kacho/...` — FGA ListObjects integration appears in existing access_binding/list_by_resource.go (after KAC-131/133)
- Vault entries to update (DoD §8 above)
- Out-of-scope siblings:
  - W2.B Enterprise: `sub-phase-W2.B-enterprise-acceptance.md` (TBD, parallel)
  - W2.C API tokens: `sub-phase-W2.C-api-tokens-acceptance.md` (TBD, parallel)
  - W2.D Newman coverage: `sub-phase-W2.D-newman-coverage-plan.md` (TBD, parallel)
  - W3 Federation/SSO: TBD
