# IAM AuthZ Review — Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans для исполнения чанков. Per-chunk bite-sized TDD-шаги формируются в начале исполнения чанка (после чтения impl-кода затронутых файлов) — этот документ фиксирует подтверждённые гипотезы и стратегию решения по чанкам.

**Goal:** Закрыть 44 подтверждённые находки code-review по `kacho-iam` (authz-корректность, DB/FGA-рассинхрон, gateway-wiring, spec-drift, identity-spoofing) пятью независимыми чанками — каждый с usecase-фиксами + newman-кейсами + integration-тестами.

**Architecture:** Корневая патология — OpenFGA не является надёжным источником истины для authz: grant-пути (Delete / JIT / break-glass) пишут в БД, но не в FGA, а единственный пишущий FGA путь (`AccessBinding.Create`) маппит по имени роли, игнорируя `role.permissions[]`. Лечение: унифицировать запись FGA-tuple'ов через `fga_outbox` (in-process, паттерн уже есть в `bootstrap_admin`), сделать relation-derivation из permissions, и убрать «слепое доверие gateway» в service-слое.

**Tech Stack:** Go (Clean Architecture: handler/service/repo), OpenFGA (ReBAC), ORY Hydra/Kratos, Postgres + goose + sqlc, gRPC + grpc-gateway, buf/protoc + `protoc-gen-kacho-permissions`, Newman (Postman) E2E, testcontainers-go.

**Источник верификации:** 5 параллельных агентов сверили каждую находку с реальным кодом 2026-05-21. Дрейф номеров строк учтён (фактические пути: `internal/service/` для phase7, `internal/apps/kacho/api/` для role/access_binding).

---

## Часть 1 — Подтверждение гипотез (assessment 55 находок)

**Итог: 44 CONFIRMED · 6 PARTIAL · 5 FALSE-POSITIVE.**

### 1.1 FALSE-POSITIVE (5) — в работу НЕ берём

| # | Гипотеза | Почему ложная |
|---|---|---|
| 2 | RoleService.Create privilege-escalation | gateway permission-catalog уже гейтит `RoleService/Create` через `editor@account` (`permission_catalog.json:1266`). `authz-deny.py:362 esc-custom-role` подтверждает DENY не-члену. Defense-in-depth в usecase тонкая, но bypass нет. |
| 17 | AuthorizeService graph-oracle | gateway fail-closed на catalog-miss (`authz.go:431-444`) → uncatalogued service denied, не оракул. |
| 18 | ConditionsService без authz | то же — catalog-miss → deny. |
| 22 | Federation Exchange не fail-closed по audit | by design: токен уже выпущен, `audit_outbox` — durable record; откатить выпущенный токен нельзя. |
| 24 | OPA fail-closed не соблюдается | by design: OPA — overlay-guardrail; FGA сам fail-closed (`s.fga==nil → authz unavailable`). Fail-closed для мутаций — на gateway-interceptor. **Action: верифицировать этот interceptor отдельно (см. Chunk 5, item OPA-VERIFY).** |

> **Caveat к #17/#18:** на прямом cluster-internal listener'е in-service authz действительно нет. Угроза — in-cluster workload, не external. Закрывается как hardening в Chunk 3 (catalog) + Chunk 5.

### 1.2 PARTIAL (6) — берём реальную часть

| # | Реальная часть (берём) | Отброшенная часть |
|---|---|---|
| 7 | Код требует auth на `/iam/v1/roles`, acceptance KAC-121 §5:103 требует public-including-anonymous → spec-vs-code расхождение | Тест `authz-deny.py:41` не «устаревший» — он кодирует текущую реализацию |
| 10 | В usecase `SAKey.Issue` нет `RequireAuthenticated` / SA-ownership-check (defense-in-depth) | «нет в permission_catalog» — НЕВЕРНО: `SAKeyService` есть в каталоге, FGA-enforced на gateway |
| 14 | `Group.List` без scope-filter (реальная утечка) | Get/Update/AddMember owner-only — это намеренный KAC-122 hardening, не «старый код» (но всё равно ужесточаем до relation-based, см. #6) |
| 20 | helm `service.yaml` публикует `grpc` и `grpc-internal` на одном k8s Service — сегрегация зависит от NetworkPolicy (не в репо) | «без auth внутри» — internal-port trust это документированная модель (Запрет #6) |
| 26 | `RunRegoTest` для empty bundle возвращает `Allowed:true` (вводит в заблуждение admin-диагностику) | не authz-decision-path, prod-код его не зовёт → P3 |
| 40 | `sp_handler.go:180` берёт `subject`/`email` из raw form values без проверки SAML-assertion signature — latent P0 при wiring | сейчас bypass нет: `OnSAMLAssertion: nil` → ACS не минтит сессию |

### 1.3 CONFIRMED (44) — полная таблица

Severity: **P0** = auth bypass / priv-esc / secret-or-data leak; **P1** = functional break или spec-violation, который ловит пользователь; **P2** = более узкая correctness; **P3** = косметика.

| # | Sev | Fix surface | Суть (evidence) |
|---|---|---|---|
| 8 | P0 | usecase | `access_binding/delete.go` `doDelete` зовёт только `AccessBindingsW().Delete` — FGA-tuple не удаляется. `create.go` пишет 2 tuple'а, инверсии нет. Revoke косметический. |
| 47 | P0 | usecase | `access_binding/create.go` строит FGA-relation из ИМЕНИ роли (`roleNameToRelation`), схлопывая всё в admin/editor/viewer; `role.permissions[]` не читается. |
| 50 | P0 | usecase + repo | JIT auto-grant (`phase7_jit_service.go`) вставляет `AccessBinding{Status:ACTIVE}` через `InsertTx` (чистый SQL INSERT, `phase7_repos.go`) — FGA-tuple не пишется. |
| 51 | P0 | usecase + repo | JIT approve/expiry зовёт `EmitSubjectErasure` (`jit_pending_service.go`, `phase7_workers.go`) — это CAEP `iam.subject.erased` (удаление), а не grant/revoke. |
| 52 | P0 | usecase | Break-glass `ApproveB` (`phase7_break_glass_service.go`) флипает grant→ACTIVE + audit/CAEP, но не пишет `cluster_admin_grants` / FGA / `fga_outbox` (ср. `bootstrap_admin.go`). |
| 35 | P0 | handler + usecase | `AccessReview.Decide` берёт `reviewer_user_id` из тела запроса (`access_review/handler.go`), service проверяет только non-empty → impersonation + подделка audit; `RevokeTx` пишет поддельного актора. |
| 37 | P0 | wiring + usecase | `ComplianceReport` Get/Download/List без service-side authz; `phase7b_wiring.go` создаёт handler без `VisibleScopeProvider` → `scopes==nil` → unrestricted list + presigned-URL leak cross-tenant. |
| 11 | P0 | handler | Plaintext `client_secret` в `Operation.response` (`sa_keys/usecases.go`); вместе с #9 anonymous с opId вытащит secret. |
| 9 | P1 | handler | `operation_handler.go` проверяет ownership только `if !IsAnonymous(ctx)` → anonymous пропускается. Логическая инверсия: anonymous должен быть строжайшим случаем. |
| 43 | P1 | interceptor | `authzguard/interceptor.go` `mutatingSuffixes` не содержит Issue/Revoke/Approve*/Deny*/Generate*/Cancel → эти RPC минуют anti-anonymous gate. |
| 16 | P2 | usecase | `access_binding/create.go`: `w.Commit()` до FGA `WriteTuples`; FGA-ошибка только `logger.Warn` (non-fatal). Binding в БД есть, tuple'а может не быть → authz `no path`. |
| 48 | P2 | usecase | `authzmap/role_expand.go` — более чистый mapper, но `access_binding/create.go` его не импортирует, дублирует свой. (Оба игнорируют permissions — #47.) |
| 12 | P1 | usecase | `AccessBinding.ListBySubject/ListByResource` (`list_by_subject.go`, `list_by_resource.go`) — прямой `repo`-passthrough без `RequireAuthenticated` и scope-filter → enumeration «кто-что-имеет». |
| 13 | P1 | usecase | `access_binding/delete.go` требует `subject_id == principal.ID` (self-only) → account-owner / delegated admin не может отозвать чужой grant. Должно зеркалить `requireGrantAuthority` из `create.go`. |
| 36 | P2 | usecase | `JitPending` Get/List (`jit_pending_service.go`) — repo-passthrough без caller-scoping. |
| 39 | P2 | handler | `JITEligibility.Create` handler не заполняет `CreatedBy`; service пишет `string(req.CreatedBy)` → eligibility-row + audit с пустым создателем. |
| 53 | P1 | handler + usecase | `SAKey` handler берёт `CreatedByUserID` из тела запроса; usecase проверяет только non-empty → spoofable audit-attribution. |
| 54 | P1 | usecase | `sa_keys/usecases.go` `Revoke` коммитит DB-delete, потом Hydra `DeleteOAuthClient`; non-404 ошибки проглатываются → orphaned Hydra-client = отозванный ключ продолжает аутентифицироваться. |
| 28 | P1 | catalog-gen + gateway-restmux + route-table | gateway embed-catalog 273 vs gen 295; нет AccessReviewService/JITEligibilityService/GdprErasureService/InternalBreakGlassService → catalog-miss → blanket deny публично зарегистрированных RPC. |
| 29 | P1 | gateway-restmux | `restmux/mux.go` IAM-блок не регистрирует Phase 7/7b handler'ы (JIT/AccessReview/ComplianceReport/JitPending/Gdpr) → REST 404. |
| 30 | P1 | gateway-route-table | `rest_route_table_gen.go` — нет jitEligibility/accessReview/complianceReport/jitPending/gdpr/breakGlass routes. |
| 31 | P1 | catalog-gen (proto root) | `permissions_catalog_root.proto` не импортирует `compliance_report_service.proto` / `jit_pending_service.proto` → их RPC не в gen-каталоге. |
| 32 | P1 | proto | `JITService.ActivateJIT` реализован (`phase7_jit_service.go`), но RPC нет ни в одном proto-сервисе → недостижим по wire. |
| 19 | P1 | catalog-gen | `main.go` публично регистрирует AuthorizeService/ConditionsService/FederationExchangeService/SAKeyService — в каталоге их нет (эффект: fail-closed deny, RPC недостижимы). |
| 33 | P2 | proto (scope_extractor) | `authorize_service.proto` Check/ListObjects: `object_type:"project", from_request_field:"subject"` → gateway чекает caller'а как `viewer` на `project:<subject-string>` — бессмыслица. |
| 34 | P2 | proto (scope_extractor) | `conditions_service.proto` Get/Update/Delete/Evaluate: `object_type:"project" from_request_field:"condition_id"` — condition-id трактуется как project-id. |
| 38 | P2 | proto (scope_extractor) | `compliance_report_service.proto` GenerateAccessReport/List хардкодят `object_type:"project"` хотя `scope_type` = account\|project\|organization. |
| 44 | P3 | proto + catalog-gen | `sa_key_service.proto` permission-строки `iam.issue_s_a_keies.issue` / `iam.s_a_keyses.list` / `iam.revoke_s_a_keies.revoke` — кривая protoc-плюрализация; засоряет каталог. |
| 45 | P1 | catalog-gen | seed-catalog `permission_catalog.json` = 236, gateway = 273, proto-gen = 295 — три рассинхронизированных каталога; `seed/permissions.go` embed-ит stale 236, deriving viewer/system roles от него. |
| 49 | P1 | handler | `internal_iam/handler.go` `ListPermissions` возвращает `codes.Unimplemented` — stub. |
| 1 | P1 | handler | `RoleService.List` (`role/handler.go`) строит `ListFilter` только с `Filter`; `account_id`/`is_system` не парсятся → List отдаёт system + custom-роли ВСЕХ аккаунтов. |
| 3 | P1 | proto + migration + handler + usecase | `ServiceAccount` остался account-scoped (`service_account.proto`, `service_account_repo.go`); KAC-121 §1.1 требует project-scoped (drop+recreate). |
| 4 | P1 | usecase | `AccountService.List` (`account/list.go`) post-фильтрует `OwnerUserID==principal.ID`; KAC-119 §3 требует List через FGA `admin`/`member` — приглашённый admin не видит account. |
| 5 | P2 | usecase + migration | `User/SA List` membership (`user/list.go`, `user_repo.go`) считается по одной user-row (`WHERE id=$1 AND invite_status=ACTIVE`), не identity/FGA. |
| 6 | P1 | usecase | `Group.AddMember` (`add_member.go`) — `RequireOwnerMatchesPrincipal` (owner-only); KAC-119/127 — relation-based. Тот же anti-pattern в `role/update.go`, `role/delete.go`. |
| 15 | P2 | usecase | `ProjectService.List` (`project/list.go`) post-фильтрует owner-only + сломанная пагинация (filter-after-page → короткие страницы с непустым `next`). |
| 46 | P2 | usecase + domain | `role/create.go` зовёт только `r.Validate()`; `domain/types.go` `Permissions.Validate()` чекает regex+cardinality, но не supported-permission allow-list. |
| 55 | P2 | domain | `domain/types.go` `roleNameSystemRe = ^roles/[a-z]+\.[a-z]+$`, миграция `0008` ослабила DB CHECK до `^[a-z]+(\.[a-z_]+){0,2}$` — domain-валидатор stale. |
| 27 | P2 | proto + handler | `conditions/handler.go` использует `GetFolderId()` / `FolderID` — API-drift после KAC-124 folder→project. |
| 21 | P1 | proto + migration + usecase | Federation Exchange (`exchange.go`) передаёт `RequestedScope` в `minter.Mint` verbatim; на `domain.FederationTrustPolicy` нет scope-allowlist поля → scope minted без intersection. |
| 23 | P2 | usecase | `CheckRelation` (`authorize_service.go`) кладёт в FGA condition-context только `current_time` — без MFA/source_ip/device/principal → conditional bindings всегда deny на internal-gate. |
| 25 | P2 | handler | `InternalAuthorize.ReloadModel` (`internal_authorize/handler.go`) меняет только `h.currentModelID`, не трогает `AuthorizeService.modelID` / OpenFGA-client → no-op для реальной авторизации. |
| 42 | P1 | handler | `caep_ingress_handler.go` `parseSETBody` base64-декодит JWT без проверки подписи; единственная граница — shared `X-Kacho-Hook-Token` → обладатель секрета подделывает session-revocation для любого user. |
| 41 | P3 | wiring | `phase6_listeners.go` `BasicAuthOrgID:""` → `scim/auth.go` всегда reject — SCIM Basic-auth выключен (bearer работает → dead config). |

---

## Часть 2 — Решение по чанкам

5 чанков. Каждый чанк = независимый PR-набор; внутри — задачи на уровне находки.

> **МЕТОДОЛОГИЯ — строгий test-first (CLAUDE.md §Запреты #11, обязательно).**
> Порядок исполнения **каждого чанка**:
> 1. **RED**: написать ВСЕ падающие тесты чанка ПЕРВЫМИ — newman-кейсы (`cases/*.py` → `gen.py`) + integration/unit-тесты — на КАЖДУЮ находку чанка. Прогнать (локально go test + в CI newman-e2e), убедиться, что **все падают** по нужной причине (находка ещё не починена).
> 2. **GREEN**: затем чинить находки по одной, переводя соответствующий тест RED→GREEN.
> 3. В отчёте/PR показывать пару «RED (до) → GREEN (после)» на каждую находку.
>
> Newman-кейс/тест, написанный ПОСЛЕ кода фикса, — нарушение, даже если зелёный.
> Per-finding fix ниже даёт целевые файлы + стратегию; bite-sized шаги формируются в начале чанка, но тест всегда первым.

### Chunk 1 — DB/FGA grant-write desync (P0-ядро)

**Findings:** 8, 16, 47, 48, 50, 51, 52
**Repos:** kacho-iam (миграция + usecase + repo)
**Root cause:** OpenFGA не источник истины — три grant-пути из четырёх не пишут tuple, единственный пишущий маппит по имени роли.

**Стратегия (общая):** унифицировать ВСЕ FGA-мутации (grant/revoke) через `fga_outbox` — emit в той же DB-транзакции, что и сама строка (binding / jit-grant / break-glass-grant); drainer применяет к OpenFGA. Паттерн уже есть: `bootstrap_admin.go` пишет `cluster_admin_grants` + `fga_outbox` атомарно. Это закрывает #8/#16/#50/#51/#52 одним механизмом и убирает «non-fatal Warn после commit».

| Задача | Файлы | Фикс | Тест |
|---|---|---|---|
| 1.1 #47/#48 — permission-based relation mapping | `internal/authzmap/role_expand.go`, `internal/apps/kacho/api/access_binding/create.go`, `helpers.go` | Расширить `authzmap` функцией `PermissionsToRelations(role.Permissions) []Relation` (а не name→relation). Удалить дублирующий `roleNameToRelation` из `create.go`, переключить на `authzmap`. Custom-роль с гранулярными permissions → набор корректных FGA-relation, не схлопывание в viewer. | integration: роль с permissions={`vpc.networks.get`} → binding → FGA Check на `vpc_network` allow, на `vpc_network` write — deny. newman: `BIND-CUSTOM-ROLE-GRANULAR`. |
| 1.2 #16 — FGA-write через outbox | `internal/apps/kacho/api/access_binding/create.go`, repo `fga_outbox` writer | `Create` пишет binding-row + `fga_outbox`-запись (grant) в ОДНОЙ tx до `Commit()`. Убрать post-commit `WriteTuples` + non-fatal Warn. | integration: FGA-write падает → tx rollback, binding-row отсутствует (атомарность). newman: `BIND-CREATE-THEN-CHECK-ALLOW`. |
| 1.3 #8 — Delete пишет revoke в outbox | `internal/apps/kacho/api/access_binding/delete.go` | `doDelete` в той же tx: DELETE binding-row + emit `fga_outbox` revoke-запись (инверсия 2 tuple'ов из Create — relation + hierarchy). | integration: create→check allow→delete→check deny. newman: `BIND-REVOKE-ENFORCED` (grant→allow, revoke→deny). |
| 1.4 #50 — JIT auto-grant пишет FGA | `internal/service/phase7_jit_service.go`, repo `phase7_repos.go` `InsertTx` | Auto-approve путь: в tx `InsertTx` binding + emit `fga_outbox` grant. | integration: JIT auto-activate → FGA Check allow. newman: `JIT-AUTO-ACTIVATE-ENFORCED`. |
| 1.5 #51 — JIT approve/expiry: grant/revoke вместо erasure | `internal/service/jit_pending_service.go`, `phase7_workers.go` | Approve: заменить `EmitSubjectErasure` на emit `fga_outbox` **grant**. Expiry: emit `fga_outbox` **revoke** (не erasure). `EmitSubjectErasure` оставить только для GDPR-пути. | integration: pending-approve → Check allow; expiry-tick → Check deny. newman: `JIT-PENDING-APPROVE-ENFORCED`, `JIT-EXPIRY-REVOKES`. |
| 1.6 #52 — Break-glass approve пишет grant | `internal/service/phase7_break_glass_service.go` | `ApproveB` в tx: flip grant→ACTIVE + INSERT `cluster_admin_grants` + emit `fga_outbox` (parity с `bootstrap_admin.go`). | integration: 2-person approve → `cluster_admin_grants`-row + Check cluster-admin allow. newman: `BREAKGLASS-2APPROVE-ENFORCED`. |

**Открытый вопрос Chunk 1:** drainer `fga_outbox`→OpenFGA — существует ли уже (его использует `bootstrap_admin`)? Если да — переиспользуем. Если drainer только для CAEP — нужен FGA-drainer (corelib `outbox` pattern). Проверить в начале исполнения.

### Chunk 2 — In-service authz holes + identity spoofing (P0/P1)

**Findings:** 9, 11, 12, 13, 35, 36, 37, 39, 43, 53
**Repos:** kacho-iam (handler + usecase + interceptor + wiring)
**Root cause:** service-слой слепо доверяет gateway; на прямом listener'е authz нет; ряд handler'ов берёт identity из тела запроса.

| Задача | Файлы | Фикс | Тест |
|---|---|---|---|
| 2.1 #9/#11 — Operation anonymous bypass | `internal/handler/operation_handler.go` | Инвертировать: `IsAnonymous(ctx)` → сразу `PermissionDenied`/`NotFound`. Ownership-check выполнять ВСЕГДА. Закрывает и secret-leak #11. | newman: `OP-GET-ANON-DENY`, `OP-CANCEL-ANON-DENY`, `SAKEY-SECRET-NOT-LEAKED-VIA-OP`. |
| 2.2 #43 — anti-anonymous covers all mutations | `internal/authzguard/interceptor.go` | Заменить suffix-matching на explicit read-only allowlist (default-deny anonymous для всего, что не в allowlist Get/List/Watch/...). Покрывает Issue/Revoke/Approve*/Deny*/Generate*/Cancel. | integration: table-test по FullMethod. newman: `JIT-ACTIVATE-ANON-DENY`, `REVIEW-APPROVE-ANON-DENY`. |
| 2.3 #12 — ListBySubject/ListByResource scope-filter | `internal/apps/kacho/api/access_binding/list_by_subject.go`, `list_by_resource.go` | Добавить `RequireAuthenticated` + scope-filter (caller видит только bindings в своём authority-scope: self-subject ИЛИ FGA-admin на resource). | newman: `BIND-LIST-BY-SUBJECT-FOREIGN-DENY`, `BIND-LIST-BY-RESOURCE-SCOPED`. |
| 2.4 #13 — Delete authority | `internal/apps/kacho/api/access_binding/delete.go` | Заменить self-only на `requireGrantAuthority` (owner ИЛИ FGA-admin на resource) — зеркало `create.go`. | newman: `BIND-DELETE-BY-ADMIN-ALLOW`, `BIND-DELETE-BY-STRANGER-DENY`. |
| 2.5 #35 — AccessReview reviewer от principal | `internal/apps/kacho/api/access_review/handler.go`, `internal/service/phase7_access_review_service.go` | `Decide` берёт reviewer из authenticated principal (ctx), игнорирует `reviewer_user_id` из тела (или валидирует ==principal). | newman: `REVIEW-DECIDE-REVIEWER-IS-PRINCIPAL`, `REVIEW-DECIDE-SPOOF-DENY`. |
| 2.6 #36 — JitPending caller-scoping | `internal/service/jit_pending_service.go` | `GetPending/ListPending` фильтруют по caller (requester ИЛИ approver). | newman: `JITPENDING-LIST-SCOPED`, `JITPENDING-GET-FOREIGN-DENY`. |
| 2.7 #37 — ComplianceReport authz | `cmd/kacho-iam/phase7b_wiring.go`, `internal/service/compliance_report_service.go` | Wiring: `NewHandler(cmrSvc).WithVisibleScopeProvider(...)`. `GetReport/GetReportDownloadURL` — добавить scope-check (caller имеет admin на scope отчёта). | newman: `COMPLIANCE-GET-FOREIGN-DENY`, `COMPLIANCE-LIST-SCOPED`. |
| 2.8 #39 — JITEligibility CreatedBy | `internal/apps/kacho/api/jit_eligibility/handler.go` | Handler заполняет `CreatedBy` из authenticated principal. | integration: Create → row.created_by == principal. newman: `JITELIG-CREATEDBY-AUDIT`. |
| 2.9 #53 — SAKey CreatedByUserID | `internal/apps/kacho/api/sa_keys/handler.go`, `usecases.go` | `CreatedByUserID` из principal, не из тела. | newman: `SAKEY-CREATEDBY-NOT-SPOOFABLE`. |

### Chunk 3 — Gateway wiring + permission catalog unification (P1)

**Findings:** 19, 28, 29, 30, 31, 32, 33, 34, 38, 44, 45, 49
**Repos:** kacho-proto → kacho-api-gateway → kacho-iam (порядок по графу зависимостей, CLAUDE.md)
**Root cause:** три рассинхронизированных permission-каталога (236/273/295); Phase 7/7b не зарегистрированы в gateway; кривые scope_extractor-аннотации; недостающие proto-импорты и RPC.

| Задача | Файлы | Фикс | Тест |
|---|---|---|---|
| 3.1 #31 — catalog-root импорты | `kacho-proto/proto/kacho/cloud/iam/v1/permissions_catalog_root.proto` | Добавить `import` `compliance_report_service.proto` + `jit_pending_service.proto`. Регенерация gen-каталога. | CI: `buf lint`/`buf breaking` зелёные; catalog-count растёт. |
| 3.2 #44 — SAKey permission-строки | `kacho-proto/.../sa_key_service.proto` | Исправить `iam.issue_s_a_keies.issue` → корректные строки (`iam.serviceAccountKeys.issue` и т.п.); решить с `protoc-gen-kacho-permissions` плюрализацию. | proto-api-reviewer; catalog grep clean. |
| 3.3 #33/#34/#38 — scope_extractor аннотации | `authorize_service.proto`, `conditions_service.proto`, `compliance_report_service.proto` | `object_type` подбирать по реальному ресурсу (condition / report-scope), не хардкодить `project`. `compliance` — выбирать по `scope_type`. | proto-api-reviewer; integration на resource_extractor. |
| 3.4 #32 — ActivateJIT RPC | `kacho-proto/.../` (решить сервис: `JITEligibilityService` или новый `JITActivationService`) | Объявить `ActivateJIT` RPC + request/response. Регенерация stubs. | proto-api-reviewer; newman: `JIT-ACTIVATE-RPC-REACHABLE`. |
| 3.5 #19/#28/#45 — единый каталог | catalog-gen, `kacho-api-gateway/internal/middleware/` embed, `kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json` | Один сгенерированный каталог = source of truth. Классифицировать RPC AuthorizeService/ConditionsService/FederationExchangeService/SAKeyService + Phase 7/7b. `make`-таргет, синхронизирующий embed в gateway И seed. Убрать ручные расхождения 236/273/295. | CI-guard: тест «catalog в gateway == iam-seed == gen». |
| 3.6 #29/#30 — restmux + route-table | `kacho-api-gateway/internal/restmux/mux.go`, `internal/middleware/rest_route_table_gen.go` | Зарегистрировать REST-handler'ы JIT/AccessReview/ComplianceReport/JitPending/Gdpr/BreakGlass; регенерировать route-table. | newman: REST-доступность каждого Phase 7/7b endpoint (не 404). |
| 3.7 #49 — InternalIAM.ListPermissions | `kacho-iam/internal/apps/kacho/api/internal_iam/handler.go` | Реализовать: aggregate permissions из единого каталога (Chunk 3.5). | integration: ListPermissions возвращает non-empty, count == каталог. newman: `INTERNAL-LISTPERMISSIONS-OK`. |

### Chunk 4 — Spec-drift KAC-119/121 (P1/P2)

**Findings:** 1, 3, 4, 5, 6, 7, 14, 15, 27, 46, 55
**Repos:** kacho-iam (+ kacho-proto для #3/#27)
**Root cause:** rewrite KAC-127 оставил owner-only authz и account-scoped SA вместо relation-based / project-scoped модели, заявленной в acceptance KAC-119/121.

| Задача | Файлы | Фикс | Тест |
|---|---|---|---|
| 4.1 #1 — RoleService.List фильтрация | `internal/apps/kacho/api/role/handler.go` | Парсить `account_id`/`is_system`; без accountId → system-only; с accountId → system + custom этого аккаунта. | newman: `ROLE-LIST-NO-ACCOUNT-SYSTEM-ONLY`, `ROLE-LIST-NO-FOREIGN-CUSTOM`. |
| 4.2 #46/#55 — role validation | `internal/apps/kacho/usecases/role/create.go`, `internal/apps/kacho/domain/types.go` | `Permissions.Validate()` — сверять с supported-каталогом (Chunk 3.5). `roleNameSystemRe` синхронизировать с миграцией `0008` CHECK. | integration: unsupported permission → reject; role-name по 0008-формату → accept. |
| 4.3 #4/#5 — Account/User/SA List через FGA | `account/list.go`, `user/list.go`, `user_repo.go` | List через FGA `ListObjects`/`ListSubjects` (admin/member relation), не owner-only / single user-row. | newman: `ACCOUNT-LIST-INVITED-ADMIN-SEES`, `USER-LIST-FGA-MEMBERSHIP`. |
| 4.4 #6/#14 — relation-based authority | `group/add_member.go`, `group/get.go`, `group/update.go`, `group/list.go`, `role/update.go`, `role/delete.go` | Заменить `RequireOwnerMatchesPrincipal` на `requireGrantAuthority` (owner ИЛИ FGA-admin). `Group.List` — добавить scope-filter + auth-check. | newman: `GROUP-ADDMEMBER-DELEGATED-ADMIN-ALLOW`, `GROUP-LIST-SCOPED`. |
| 4.5 #15 — ProjectService.List | `internal/apps/kacho/api/project/list.go` | Grant-aware list (FGA) + починить пагинацию: фильтровать ДО paging, `next`-token консистентен. | integration: paged list с filter → корректные страницы. newman: `PROJECT-LIST-INVITED-ADMIN-SEES`. |
| 4.6 #3 — ServiceAccount project-scoped | `kacho-proto/.../service_account*.proto`, миграция, `service_account/handler.go`, `service_account_repo.go` | `project_id` — required (drop optional account_id-scope, greenfield drop+recreate миграция — допустимо per CLAUDE.md major-rewrite). List по `projectId`. | integration: SA.Create под project; List по projectId. newman: `SA-PROJECT-SCOPED-CRUD`. |
| 4.7 #27 — Conditions folder→project | `kacho-proto/.../conditions_service.proto`, `conditions/handler.go`, `conditions_crud_service.go`, `domain.Condition` | Переименовать `folder_id`→`project_id` сквозь proto/handler/domain/repo. | integration: Conditions CRUD по project_id. newman: `CONDITIONS-PROJECT-SCOPED`. |
| 4.8 #7 — anonymous role-catalog контракт | DECISION + (`kacho-api-gateway` authz exempt-handling ИЛИ `docs/specs/...KAC-121...`) | **Открытый вопрос — нужно решение пользователя:** acceptance KAC-121 §5:103 требует `/iam/v1/roles` public-including-anonymous; код требует auth. Либо (a) gateway пропускает anonymous на `RoleService/List`, либо (b) обновить acceptance-док. | После решения: newman `ROLE-LIST-ANON-*` приводится в соответствие. |

### Chunk 5 — Federation / SSO / AuthZ internals (P1/P2/P3)

**Findings:** 20, 21, 23, 25, 26, 40, 41, 42 (+ OPA-VERIFY из #24)
**Repos:** kacho-iam (+ kacho-proto/migration для #21), kacho-deploy (#20)

| Задача | Файлы | Фикс | Тест |
|---|---|---|---|
| 5.1 #21 — federation scope-allowlist | `kacho-proto` (trust-policy proto: `allowed_scopes[]`), миграция, `internal/service/federation/exchange.go`, `token_minter.go` | На `FederationTrustPolicy` — поле `allowed_scopes[]`. Exchange делает intersection `RequestedScope ∩ policy.allowed_scopes`; запрос вне allowlist → reject. | integration: scope вне allowlist → reject; subset → minted subset. newman: `FED-EXCHANGE-SCOPE-INTERSECTION`. |
| 5.2 #42 — CAEP SET signature verify | `internal/handler/iamhooks/caep_ingress_handler.go` | `parseSETBody` — проверять подпись SET-JWT по JWKS доверенного IdP (не только `X-Kacho-Hook-Token`). | integration: невалидная подпись → reject. newman: `CAEP-SET-BADSIG-REJECT`. |
| 5.3 #23 — CheckRelation context | `internal/service/authorize_service.go` | `CheckRelation` пробрасывает MFA/source_ip/device/principal в FGA condition-context (parity с `Check`). | integration: conditional binding (mfa_fresh) + валидный context → allow. |
| 5.4 #25 — ReloadModel | `internal/apps/kacho/api/internal_authorize/handler.go`, `authorize_service.go` | `ReloadModel` реально обновляет `AuthorizeService.modelID` / re-point OpenFGA-client (модель thread-safe атомарным swap). | integration: ReloadModel(newID) → последующий Check использует новую модель. |
| 5.5 #40 — SAML ACS hardening | `internal/apps/kacho/api/saml/sp_handler.go`, `cmd/kacho-iam/phase6_listeners.go` | **DECISION:** (a) реализовать проверку подписи SAML-assertion перед извлечением subject/email и затем wire `OnSAMLAssertion`; либо (b) явно guard'ить ACS пока verification нет (убрать JSON-echo fallback, возвращать 501). Не оставлять latent-P0. | integration: assertion без валидной подписи → reject. |
| 5.6 #41 — SCIM Basic-auth | `cmd/kacho-iam/phase6_listeners.go`, `internal/apps/kacho/api/scim/auth.go` | Либо wire `BasicAuthOrgID` из конфига, либо удалить мёртвый Basic-auth путь (оставить bearer). P3. | — |
| 5.7 #20 — port segregation | `kacho-iam/deploy/templates/` | Добавить NetworkPolicy, ограничивающую `grpc-internal` (9091) cluster-internal источниками; либо разнести на отдельный Service. | deploy-lint. |
| 5.8 #26 — RunRegoTest | `internal/apps/kacho/api/internal_authorize/handler.go` | Empty bundle → `Allowed:false` + явный Trace «no bundle», не false-allow. P3. | integration. |
| 5.9 OPA-VERIFY (#24 follow-up) | `kacho-api-gateway` interceptor | Верифицировать, что fail-closed-для-мутаций при недоступном OPA реально enforced на gateway-interceptor (агент видел только комментарий). Если нет — завести как баг. | — |

---

## Часть 3 — Последовательность и кросс-репо порядок

**Порядок чанков:**
1. **Chunk 1** — первым: без него authz фундаментально сломан (grant'ы не грантят, revoke не отзывает). Всё остальное предполагает FGA = источник истины.
2. **Chunk 2** — закрывает прямые bypass-дыры (anonymous, spoofing). Независим от Chunk 1.
3. **Chunk 3** — gateway/каталог; делает Phase 7/7b RPC достижимыми. Кросс-репо.
4. **Chunk 4** — spec-drift; крупнее (SA project-scope миграция), много handler'ов.
5. **Chunk 5** — federation/SSO internals; наиболее изолирован.

Chunk 1 и 2 можно вести параллельно (разные файлы). Chunk 3 — после, т.к. часть newman-кейсов Chunk 1/2 идёт через gateway и выиграет от исправленного каталога.

**Кросс-репо порядок внутри Chunk 3/4/5 (CLAUDE.md граф зависимостей):**
`kacho-proto` (новые RPC/поля/scope-аннотации + регенерация `gen/`, `buf lint/breaking` зелёные) → `kacho-api-gateway` (catalog embed, restmux, route-table) → `kacho-iam` (handler/usecase/seed-catalog) → `kacho-deploy` (#20 NetworkPolicy).
Пока proto-изменения не в `main` — CI зависимых репо временно пиннит sibling-`ref:` на feature-ветку.

**Тестовая дисциплина (CLAUDE.md §Запреты #11):** каждая задача = integration-тест (testcontainers Postgres + при необходимости concurrent-race) + newman-кейс (≥1 happy + ≥1 negative) В ТОМ ЖЕ PR. Особый акцент: newman access-matrix должна проверять не «Check возвращает allow на seed», а **grant→allow / revoke→deny / JIT-activate→allow / expiry→deny** — именно эти переходы пропустила «854/854 GREEN» матрица KAC-127.

---

## Часть 4 — Открытые вопросы (нужны решения до старта чанка)

| # | Вопрос | Чанк | Рекомендация |
|---|---|---|---|
| OQ-1 | `fga_outbox`-drainer уже существует и применяет к OpenFGA, или только CAEP-drainer? | 1 | Проверить в начале Chunk 1; если нет — добавить FGA-drainer на corelib `outbox`-паттерне. |
| OQ-2 | #7: anonymous `/iam/v1/roles` — менять gateway (разрешить anon) или acceptance-док (требовать auth)? | 4 | Решение пользователя. Рекомендую обновить acceptance: catalog-read требует auth (минимальная гигиена), anonymous не нужен. |
| OQ-3 | #32: `ActivateJIT` — в `JITEligibilityService` или отдельный `JITActivationService`? | 3 | В `JITEligibilityService` (меньше новых сервисов). |
| OQ-4 | #3: SA project-scope — greenfield drop+recreate миграция приемлема (данных нет в prod)? | 4 | Да per CLAUDE.md major-rewrite + memory (no strict backward-compat). |
| OQ-5 | #40: SAML — реализовать assertion-verification сейчас или заглушить ACS до отдельного тикета? | 5 | Заглушить (501) сейчас, verification — отдельный объём; не оставлять latent-P0. |
| OQ-6 | KAC-тикет: пользователь сказал «без тикета пока». Завести эпик ретроспективно перед первым PR? | — | Рекомендую завести перед PR (CLAUDE.md: PR ссылается на тикет); решение пользователя. |

---

## Часть 5 — Прогресс исполнения

### Раунд 1 (2026-05-21) — Chunk 1, задача 1.3 (#8) + 1.3-bis (#13)

**Сделано** (TDD red→green, kacho-iam):
- `internal/apps/kacho/api/access_binding/delete.go` — `DeleteAccessBindingUseCase` получил `WithOpenFGA`; `Execute` авторизуется через общий `requireGrantAuthority` (не self-only — **#13**); `doDelete` после DB-commit удаляет FGA grant-tuple'ы (relation + project-hierarchy) — **#8**.
- `helpers.go` / `create.go` — `requireGrantAuthority` и `resolveBindingRelation` извлечены в пакетные функции (переиспользуются Create и Delete).
- `cmd/kacho-iam/main.go` — `abDelete.WithOpenFGA(...)` wired.
- `internal/apps/kacho/api/access_binding/delete_test.go` — 3 теста (revoke удаляет FGA-tuple; owner отзывает чужой binding; посторонний → PermissionDenied). Все GREEN, `go build ./...` чистый.

**Открытия раунда 1:**
- **OQ-1 РЕШЁН**: таблица `fga_outbox` (migration 0002) существует и имеет NOTIFY-триггер, но **drainer'а, который её читает, НЕТ** — только `bootstrap_admin` пишет туда, никто не дренит. Значит bootstrap-grant FGA-tuple **никогда не применяется**. Следствие: план «route everything через fga_outbox» нереализуем без drainer'а. Chunk 1 использует sync `WriteTuples`/`DeleteTuples` (как уже делает `AccessBinding.Create`). **Новая задача: построить `fga_outbox`-drainer** (corelib `outbox`-паттерн + LISTEN `kacho_iam_fga_outbox`) — добавить в Chunk 1 как 1.0, либо отдельным тикетом. До неё `#16` (надёжность FGA-write) частично решается тем, что write/delete sync в worker'е.
- **NEWMAN-находка (новая)**: case-файлы `tests/newman/cases/iam-*.py` (iam-account, iam-access-binding, iam-group, iam-project, iam-role, iam-service-account, ...) написаны в формате `dict(...)`, а `gen.py` генерирует **только** `Case(...)`/`Step(...)`-формат → `gen.py` **SKIP'ает весь файл** («non-Case items in CASES»). Т.е. **вся iam CRUD newman-сюита — declarative-spec-only, никогда не гонялась в CI**. Реально работают только `authz-deny.py` / `authz-sa-apitoken.py` (их `run.sh` гоняет). → Новая задача в Chunk 3 test-discipline: конвертировать `iam-*.py` в `Case`/`Step` + добавить в `run.sh`.
  - **Раунд-1 решение**: runnable newman-кейс для #8 размещён в `authz-deny.py` как `AUTHZ-REVOKE-ENFORCED-A-INV` (stateful flow Case: AAA grant admin→INV на account-A → INV GET account-A ALLOW → AAA revoke → INV GET account-A DENY 403). Использует фикстуру `authz-fixtures/setup.sh` (env `accountAId`/`userINVId`/`jwtAccountAdminA`/`jwtInvitee`), генерируется `gen.py` (288→289 cases), гоняется в CI. Это закрывает blind spot матрицы — она проверяла только static state, не grant→revoke переход.

**Дальше:** Chunk 1 задачи 1.1 (#47/#48 permission-mapping), 1.2 (#16), 1.4–1.6 (JIT/break-glass FGA-grant). 1.0 (fga_outbox drainer) — предусловие для «надёжного» варианта 1.2/1.4–1.6.

---

## Self-review

- **Покрытие:** все 44 CONFIRMED + 6 PARTIAL (реальная часть) распределены по 5 чанкам; 5 FALSE-POSITIVE явно исключены с обоснованием. #24 даёт follow-up OPA-VERIFY (5.9).
- **Placeholder-scan:** открытые вопросы вынесены в Часть 4 как явные DECISION-пункты, не «TBD» внутри задач.
- **Type-consistency:** `fga_outbox` / `authzmap.PermissionsToRelations` / `requireGrantAuthority` используются согласованно между задачами 1.1–1.6 и 2.3/2.4/4.4.
- **Scope:** 5 чанков — независимые PR-наборы; bite-sized TDD-шаги формируются per-chunk при исполнении (impl-код затронутых файлов на момент написания плана не прочитан — поэтому план фиксирует стратегию + файлы + тесты, а не построчный код).
