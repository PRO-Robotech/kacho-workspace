# Sub-phase 5.1 (kacho-iam — per-RPC `system_viewer`-floor on cluster-internal READ RPCs) — Acceptance

> **Статус:** ✅ APPROVED (acceptance-reviewer, 2026-06-16; coding-gate пройден per workspace `CLAUDE.md` §Non-negotiables #1)
> **Дата:** 2026-06-16
> **Ревьюер:** `acceptance-reviewer` (единственный gate APPROVED per workspace `CLAUDE.md` §Non-negotiables #1)
> **Автор-агент:** `acceptance-author`
> **Эпик/тикет:** KAC-`<N>` (subtask; trail-anchor — GitHub issue `PRO-Robotech/kacho-iam#122`, prod-readiness backlog «internal-READ surface не имеет relation-tier Check»). Ветка `KAC-<N>` в `kacho-iam`.
> **Target repo:** `kacho-iam` (PRIMARY — interceptor + seed). `kacho-proto`/`kacho-api-gateway` **не затрагиваются** (контракт RPC не меняется; floor — внутренний для :9091 listener).
> **Конвенции (нормативно, не дублируются в теле — ссылки):**
> `.claude/rules/security.md` (§«AuthN+AuthZ ВЕЗДЕ» — закрываемый инвариант; Internal-vs-public ban #6),
> `.claude/rules/api-conventions.md` (error-format / gRPC-коды),
> `.claude/rules/data-integrity.md` (fail-closed cross-domain, seed через bootstrap-path не SQL-backdoor),
> `.claude/rules/testing.md` (TDD-red, ban #12/#13),
> `.claude/rules/polyrepo.md` (кросс-репо порядок — здесь single-repo).
> **Образцы стиля:** SEC-L (`sub-phase-SEC-L-operator-fga-system-viewer-acceptance.md` — тот же `system_viewer@cluster` примитив + fail-closed контракт + real-OpenFGA conformance), SEC-C (`sub-phase-SEC-C-iam-fga-proxy-sa-roles-acceptance.md` — least-priv module-SA seed, byte-for-byte template; `RelationWriteGate` fail-closed precedent), 5.0 (`sub-phase-5.0-internal-tier-authz-hardening-acceptance.md` — sibling, public-tier catalog hardening; этот документ — internal-tier read floor поверх).

---

## Обзор

`security.md` §«AuthN+AuthZ ВЕЗДЕ» предписывает, что **каждый** internal RPC (а не только public)
проходит per-RPC authz-Check сверх mTLS: «internal-листенер с одним mTLS (без authz-Check) —
нарушение инварианта, фиксится как баг. Read-RPC гейтить viewer-tier (`system_viewer`), мутации —
admin-tier.» Сегодня на :9091 энфорсятся: (1) coarse caller-policy floor (verified mTLS module SAN
+ gateway-only-restriction, `authzguard.CallerPolicy`), (2) `RelationWriteGate` (`fga_writer`) на
`RegisterResource`/`UnregisterResource`/`WriteCreatorTuple`, (3) `system_admin` на
`InternalClusterService` (через gateway-fronted-set + catalog). Но **internal-READ surface**
(`InternalIAMService.{LookupSubject,ListPermissions,GetJWKSStatus,PollSubjectChanges}`,
`InternalUserService.Get`, `InternalSessionRevocationsService.ListByUser`,
`InternalAuthorizeService.{ReadTuples,GetFGAStoreInfo}`) гейтится **только** mTLS-module-floor — без
relation-tier Check. Это и есть разрыв инварианта.

Эта под-фаза добавляет per-RPC **`system_viewer`-floor**: для набора READ-RPC требуется, чтобы
**модульная ServiceAccount вызывающего** (верифицированный mTLS-cert SAN → детерминированный
`sva`-id) держала **coarse cluster-level relation `system_viewer`** на singleton
`cluster:cluster_kacho_root` (ReBAC, через существующий `RelationChecker`-порт /
`InternalIAMService.Check`). Это **coarse** «легитимный ли это внутренний читатель» gate
(defense-in-depth против скомпрометированного модуля с валидным cert'ом, но не авторизованного
читать IAM), а **не** per-resource viewer-check. Floor — **default-OFF, per-edge enable** (зеркало
SEC-E/SEC-H mTLS default-off + production-mode gate): в dev/newman (без mTLS, FGA-on-internal
отключён per #71/#80) gate — **no-op**, стенд byte-identical. Легитимные module-SA читателей сидятся
`system_viewer@cluster` в том же изменении (через bootstrap-reconciler / seed-path, не SQL-backdoor —
прецедент Bug B / PR #76; SEC-C migration 0009 / SEC-L 0010).

---

## 1. Дизайн (нормативно — реализатор не редизайнит; сценарии пишутся вокруг этого)

### 1.1 Floor-интерсептор (новый, на internal-listener)

Новый `authzguard.SystemViewerFloor` (unary + stream) ставится в цепочку internal-listener'а
(`cmd/kacho-iam/serve.go`, `internalSrv` chain) **после** существующих
`UnaryCertIdentityExtract` → `UnaryTrustedPrincipalExtract` → `internalCallerPolicy.Unary()` и
**до** handler'а. Алгоритм `allow(ctx, fullMethod)`:

1. `fullMethod ∉ ReadFloorRPCs` (набор §1.3) → **pass** (не наша забота — caller-policy/in-handler
   gate уже отработал).
2. `!prodMode` (`cfg.AuthN.Mode.IsProduction() == false`) → **pass (no-op)** — dev/newman back-compat
   (зеркало `CallerPolicy`/`RelationWriteGate` dev-ветки).
3. prod-mode, нет verified module-cert SAN (`grpcsrv.CertIdentityFromContext` → `verified=false` ||
   SAN не парсится `ServiceNameFromSAN`) → `PermissionDenied "permission denied"` (fail-closed).
4. prod-mode, SAN валиден → derive `sva := ServiceAccountIDForService(svc)`
   (`'sva'||substr(md5("kacho-"+svc),1,17)`, та же функция, что SEC-C/SEC-L) →
   `RelationChecker.Check(ctx, "service_account:"+sva, "system_viewer", "cluster:cluster_kacho_root")`:
   - `err != nil` (FGA outage / 5xx / network / `ErrNotConfigured`) → `Unavailable "authz backend
     unavailable"` (retryable, fail-closed — **не** allow; парность с `RelationWriteGate`).
   - `allowed == false` → `PermissionDenied "permission denied"`.
   - `allowed == true` → **pass**.

Message-тексты — verbatim non-leaking (`"permission denied"` / `"authz backend unavailable"`),
парность с `RelationWriteGate.Authorize` (`fgaproxy.go`). `checker == nil` (не подключён в prod) →
fail-closed `PermissionDenied`. Floor **не** ReBAC'ит forwarded end-user principal (`x-kacho-principal-*`)
— субъект Check — это **caller module-SA**, не конечный пользователь.

### 1.2 Почему именно `system_viewer@cluster:cluster_kacho_root`

Тот же примитив, что узаконен SEC-L §2.1/INV-6: relation `system_viewer` в FGA-модели — direct-
assignment `[user, service_account]` **без wildcard `user:*`**. Coarse «это легитимный внутренний
читатель»-сигнал на singleton-объекте `cluster:cluster_kacho_root` (тот же root, что SEC-C
AccessBindings / SEC-L operator-tuple). Floor проверяет **только** наличие этого coarse relation —
**не** per-resource (`viewer@project:<id>` и т.п.); per-resource authz для конечного пользователя
делает api-gateway до проброса на :9091.

### 1.3 `ReadFloorRPCs` — набор READ-RPC под floor (нормативный список)

| FQN | Текущий catalog | Под floor? |
|---|---|---|
| `InternalIAMService/LookupSubject` | `<exempt>` | **ДА** |
| `InternalIAMService/ListPermissions` | `<exempt>` | **ДА** |
| `InternalIAMService/GetJWKSStatus` | `<exempt>` | **ДА** |
| `InternalIAMService/PollSubjectChanges` | `<exempt>` | **ДА** |
| `InternalUserService/Get` | `<exempt>` | **ДА** |
| `InternalSessionRevocationsService/ListByUser` | `<exempt>` (gateway-fronted) | **ДА** (floor И gateway-only — оба применяются) |
| `InternalAuthorizeService/ReadTuples` | `<exempt>` (gateway-fronted) | **ДА** |
| `InternalAuthorizeService/GetFGAStoreInfo` | `<exempt>` (gateway-fronted) | **ДА** |

**ВНЕ floor (см. §1.4 exemption-table с обоснованием):** `InternalIAMService.Check` (PDP — нельзя
гейтить), secret-authed webhooks (`InternalIamHooksService.*`, `InternalUserService.OnRecoveryCompleted`),
hot-path `InternalSessionRevocationsService.IsRevoked`, и все мутации (§1.5).

### 1.4 Exemption-таблица (явная, с обоснованием — нарушение = security-defect)

| FQN | Exempt от floor? | Обоснование |
|---|---|---|
| `InternalIAMService/Check` | **ДА — НИКОГДА не под resource-viewer-gate** | Check — **policy-decision-point**: caller (vpc/compute) зовёт его **от имени конечного пользователя**; SA caller'а — НЕ субъект решения. Гейтить Check на «caller has viewer на target-ресурс» семантически неверно и **сломает core authz-path** (каждый downstream-Check начнёт PermissionDenied'иться). Остаётся на mTLS-module-floor (`CallerPolicy`). Опционально допустимо обложить тем же **coarse** `system_viewer`-floor (caller module-SA, не per-resource) — но это **не** обязательно для этой волны и НИКОГДА не per-resource. **Default этой волны: Check НЕ в `ReadFloorRPCs`.** |
| `InternalIamHooksService/TokenHook` | **ДА — exempt by construction** | Hydra OAuth2 token-hook — **HTTP-handler на отдельном hooks-listener (:9092)**, НЕ gRPC-сервис на :9091 (`serve.go` hooks-mux; `InternalIamHooksService` не регистрируется в gRPC `grpc_register.go`). Floor — gRPC-interceptor :9091 — его **физически не перехватывает**. В `ReadFloorRPCs` не входит by construction; secret/transport-authed; Hydra — не kacho-seeded SA → relation-Check неприменим. |
| `InternalIamHooksService/RefreshTokenHook` | **ДА — exempt by construction** | То же (Hydra refresh-hook на HTTP hooks-listener :9092, вне gRPC-floor). |
| `InternalUserService/OnRecoveryCompleted` | **ДА** | Kratos recovery-hook. **Реальный gRPC-метод `InternalUserService` на :9091** (в отличие от Hydra-hooks выше) → должен быть **явно исключён из `ReadFloorRPCs`**. HMAC/secret-authed; Kratos — не kacho-seeded SA → relation-Check неприменим. |
| `InternalSessionRevocationsService/IsRevoked` | **ДА (floor-exempt)** | **Hot-path chicken-and-egg**: api-gateway зовёт его в refresh/token-hook пути **до** того, как per-user authz вообще может отработать (см. `caller_policy.go` doc-comment строки 76-78). Обкладывать его `system_viewer`-floor добавило бы FGA-Check на каждый token-refresh (hot-path latency + outage = массовый logout-fail). Остаётся на mTLS-module-floor. Gateway-SA уже верифицирован cert'ом; coarse legitimacy покрыт floor'ом caller-policy. |
| `InternalIAMService/RegisterResource` | **ДА (другой gate)** | Мутация (write owner-tuple). Уже гейтится in-handler `RelationWriteGate` (`fga_writer@iam_fgaproxy:system`). Не read. |
| `InternalIAMService/UnregisterResource` | **ДА (другой gate)** | То же (`RelationWriteGate`). |
| `InternalIAMService/WriteCreatorTuple` | **ДА (другой gate)** | То же (`RelationWriteGate`). |

### 1.5 Мутационная поверхность (этой волной НЕ меняется — regression-guard)

Primary scope — **READ floor**. Состояние мутаций фиксируется как контракт (сценарий 09):

| Мутационный RPC | Текущий gate | Статус в этой волне |
|---|---|---|
| `InternalIAMService.{RegisterResource,UnregisterResource,WriteCreatorTuple}` | in-handler `RelationWriteGate` (`fga_writer`) | **уже покрыто** — не трогаем |
| `InternalIAMService.ForceLogout` | gateway-only set + **in-handler** `system_admin`-checker (`.WithAdminChecker`, `wiring.go`; catalog-`permission` = `<exempt>`, НЕ `required_relation`) | **уже покрыто** — не трогаем |
| `InternalClusterService.{GrantAdmin,RevokeAdmin}` | gateway-only set + `system_admin` (catalog `required_relation` + in-handler checker) | **уже покрыто** — не трогаем |
| `InternalAuthorizeService.{WriteTuples,ReloadModel,RunRegoTest}` | gateway-only set | **deferred** (см. §«Scope boundaries» — admin-tier на эти write-RPC = отдельная residual-волна, отслеживается в #122) |
| `InternalSessionRevocationsService.Revoke` | gateway-only set | **уже покрыто** (gateway-only) |
| `InternalUserService.UpsertFromIdentity` | gateway-only set | **уже покрыто** (gateway-only) |

### 1.6 SEC-C seed-расширение (в ТОМ ЖЕ изменении — иначе legitimate-читатели упадут в prod)

Легитимные internal-reader module-SA должны держать `system_viewer@cluster:cluster_kacho_root`,
иначе в prod-mode упадут на floor'е. Сидятся **через seed-path / bootstrap-reconciler** (НЕ
SQL-backdoor — прецедент Bug B / PR #76), зеркало SEC-L migration 0010 (`fga_outbox` →
drainer применяет идемпотентно):

| Module-SA (`svc`) | `sva`-id | Уже сидирован? |
|---|---|---|
| `api-gateway` | `'sva'||substr(md5('kacho-api-gateway'),1,17)` | **НЕТ — сидируется здесь** |
| `vpc` | `'sva'||substr(md5('kacho-vpc'),1,17)` | **НЕТ — сидируется здесь** |
| `compute` | `'sva'||substr(md5('kacho-compute'),1,17)` | **НЕТ — сидируется здесь** (forward-looking least-priv, см. note) |
| `vpc-operator` | `'sva'||substr(md5('kacho-vpc-operator'),1,17)` | **ДА (SEC-L 0010)** — **исключается из 0014** (reviewer-decision Q2); сценарий 08 — regression-guard на no-conflict |

Новая миграция — **0014** (применены 0001..0013; ban #5 — 0010/0009 не редактировать). Только
read-relation `system_viewer`; никаких editor/admin/owner для этих SA (least-priv, INV-FLOOR-4).
**`vpc-operator` НЕ включается в 0014** (уже сидирован SEC-L 0010 — меньше дублей, проще down);
если реализатор всё же включит — обязан `ON CONFLICT DO NOTHING` (no-op, сценарий 08). Down-
миграция 0014 ревертит ровно свои intent'ы (api-gateway/vpc/compute).

**Note (compute — forward-looking seed):** на момент этой под-фазы зафиксированные runtime-edge
`kacho-compute → kacho-iam` (`polyrepo.md`) — `ProjectService.Get` + `InternalIAMService.Check`
(оба вне `ReadFloorRPCs`: Get — public, Check — PDP-exempt). Compute сидируется `system_viewer`
**preemptively** (least-priv read-only — безвреден; покрывает будущие internal-READ вызовы compute,
напр. `InternalUserService.Get`). Реализатор подтверждает в плане: либо compute уже зовёт RPC из
`ReadFloorRPCs`, либо seed помечен forward-looking. `system_viewer` без mutation-capability — leak-
риска нет.

---

## 2. Критические инварианты (нарушение = reject)

| # | Инвариант | Сценарий |
|---|---|---|
| **INV-FLOOR-1** | dev/newman (gate disabled / no mTLS) — floor **no-op**: каждое internal-read проходит byte-identical к сегодня. | 01 |
| **INV-FLOOR-2** | prod-mode, legitimate reader-SA (держит `system_viewer@cluster`) → READ-RPC **allowed**. | 02 |
| **INV-FLOOR-3** | prod-mode, module-SA **БЕЗ** `system_viewer` → READ-RPC **PermissionDenied**. | 03 |
| **INV-FLOOR-4** | seed даёт reader-SA **только** `system_viewer` (read-relation); никакого editor/admin/owner → нет mutation-capability. | 07, 08 |
| **INV-FLOOR-5** | `InternalIAMService.Check` **НИКОГДА** не гейтится resource-viewer-check; PDP не трактуется как субъект. Check проходит module-floor как раньше. | 04 |
| **INV-FLOOR-6** | secret-authed webhooks (`OnRecoveryCompleted`, `TokenHook`, `RefreshTokenHook`) и hot-path `IsRevoked` — **exempt** от ReBAC-floor. | 05, 06 |
| **INV-FLOOR-7** | prod-mode, FGA/checker недоступен → `Unavailable` (retryable, fail-closed) — **не** allow, **не** PermissionDenied. | 03b |
| **INV-FLOOR-8** | Мутационная поверхность не меняется (`RegisterResource` всё ещё `fga_writer`-gated; gateway-only set нетронут). | 09 |

---

## 3. Сценарии Given-When-Then

> REST-пути не приводятся: все RPC под floor — `Internal*` на cluster-internal :9091 (ban #6),
> не на external endpoint; вызовы service→service по mTLS-gRPC, не через external REST.
> Async/Operation-поллинг неприменим — все RPC под floor **sync read**.

### Сценарий 01: Dev-mode — floor no-op, internal-read byte-identical (INV-FLOOR-1)

**ID:** 5.1-01

**Given** `cfg.AuthN.Mode == ModeDev` (`IsProduction() == false`)
**And** internal-listener поднят без mTLS (insecure, текущий dev/newman)
**And** caller не предъявляет verified module-cert (SAN отсутствует)

**When** любой caller вызывает `kacho.cloud.iam.v1.InternalIAMService/LookupSubject` (resp.
`InternalUserService/Get`, `InternalAuthorizeService/ReadTuples`) с валидным payload

**Then** `SystemViewerFloor` интерсептор short-circuit'ит в **pass** (no-op ветка §1.1 шаг 2) —
`RelationChecker.Check` **не вызывается**
**And** RPC доходит до handler'а и отвечает ровно как до этой под-фазы (поведение byte-identical;
newman E2E suite не затронут — default-OFF)

### Сценарий 02: Prod-mode — legitimate reader-SA → allowed (INV-FLOOR-2)

**ID:** 5.1-02

**Given** `cfg.AuthN.Mode == ModeProduction` и internal-listener под mTLS RequireAndVerifyClientCert
**And** caller предъявляет verified cert с SAN `spiffe://kacho.cloud/ns/kacho-api-gateway/sa/kacho-api-gateway`
**And** в FGA существует tuple `service_account:<sva-api-gateway>#system_viewer@cluster:cluster_kacho_root`
(сидирован миграцией 0014, drained)

**When** caller вызывает `InternalIAMService/LookupSubject`

**Then** floor резолвит `svc = "api-gateway"` → `sva = 'sva'||substr(md5('kacho-api-gateway'),1,17)`
**And** `RelationChecker.Check("service_account:<sva>", "system_viewer", "cluster:cluster_kacho_root")`
возвращает `allowed=true`
**And** RPC проходит floor и доходит до handler'а (gRPC `OK`)
**And** субъект Check — **caller module-SA**, НЕ forwarded end-user principal (floor не читает
`x-kacho-principal-*`)

### Сценарий 03: Prod-mode — module-SA без `system_viewer` → PermissionDenied (INV-FLOOR-3)

**ID:** 5.1-03

**Given** prod-mode + mTLS
**And** caller предъявляет verified cert с SAN валидного, но НЕ сидированного module-SA
(напр. `.../sa/kacho-someother`), у которого **нет** tuple `system_viewer@cluster:cluster_kacho_root`

**When** caller вызывает `InternalUserService/Get`

**Then** floor резолвит `sva`, `RelationChecker.Check(...)` возвращает `allowed=false`
**And** RPC отклоняется с gRPC `PERMISSION_DENIED`, message `"permission denied"` (verbatim, без
leak'а backend-деталей)
**And** handler **не** вызывается

**And** (no-cert sub-case) если в prod-mode caller достигает :9091 **без** verified module-cert SAN
(insecure peer / mусорный/foreign-trust-domain SAN)
**Then** floor возвращает `PERMISSION_DENIED "permission denied"` (fail-closed; шаг 3 §1.1)

### Сценарий 03b: Prod-mode — FGA backend недоступен → Unavailable, fail-closed (INV-FLOOR-7)

**ID:** 5.1-03b

**Given** prod-mode + mTLS + legitimate reader-SA cert (`api-gateway`)
**And** FGA / `RelationChecker` backend недоступен (5xx / network drop / timeout / `ErrNotConfigured`)

**When** caller вызывает `InternalIAMService/ListPermissions` (любой READ-RPC под floor)

**Then** `RelationChecker.Check(...)` возвращает `err != nil`
**And** floor возвращает gRPC `UNAVAILABLE`, message `"authz backend unavailable"` (retryable)
**And** floor **НЕ** allow'ит (нет fail-open) и **НЕ** возвращает `PermissionDenied` (transient
outage ≠ authz-decision; парность с `RelationWriteGate.Authorize`)
**And** raw backend-ошибка логируется, не leak'ается в gRPC-message

### Сценарий 04: Prod-mode — InternalIAMService.Check от vpc от имени end-user НЕ сломан (INV-FLOOR-5)

**ID:** 5.1-04

**Given** prod-mode + mTLS
**And** `kacho-vpc` (verified cert `.../sa/kacho-vpc`) вызывает `InternalIAMService/Check` как
authz-gate **от имени конечного пользователя** (`x-kacho-principal-*` несёт end-user; subject в
`CheckRequest` — этот end-user, НЕ SA caller'а)

**When** vpc вызывает `InternalIAMService/Check(subject=user:<end-user>, relation=viewer, object=project:<id>)`

**Then** `InternalIAMService/Check ∉ ReadFloorRPCs` → `SystemViewerFloor` short-circuit'ит в **pass**
(шаг 1 §1.1) — никакого resource-viewer-gate на PDP
**And** Check проходит **module-floor** `CallerPolicy` как раньше (verified module-cert достаточно)
**And** PDP отрабатывает per-user authz-решение нормально (core authz-path не деградирует)
**And** явный assert: floor **не** трактует caller-SA `kacho-vpc` как субъект и **не** требует
`viewer@project:<id>` для caller-SA

> Регрессионный якорь INV-FLOOR-5: если Check случайно попадёт в `ReadFloorRPCs`, каждый downstream-
> Check начнёт `PermissionDenied`/`Unavailable`'иться → весь vpc/compute authz сломается. Сценарий
> это ловит.

### Сценарий 05: Prod-mode — exempt webhook OnRecoveryCompleted минует ReBAC-floor (INV-FLOOR-6)

**ID:** 5.1-05

**Given** prod-mode
**And** Kratos вызывает `InternalUserService/OnRecoveryCompleted` (HMAC/secret-authed; Kratos — НЕ
kacho-seeded SA, relation-Check к нему неприменим)

**When** запрос приходит на listener

**Then** `OnRecoveryCompleted ∉ ReadFloorRPCs` → floor short-circuit'ит в **pass** (шаг 1 §1.1) —
`RelationChecker.Check` не вызывается
**And** RPC обрабатывается своим существующим secret-auth путём (поведение неизменно)

### Сценарий 06: Prod-mode — hot-path IsRevoked floor-exempt (INV-FLOOR-6)

**ID:** 5.1-06

**Given** prod-mode + mTLS
**And** api-gateway вызывает `InternalSessionRevocationsService/IsRevoked` в refresh/token-hook
hot-path (chicken-and-egg: до того как per-user authz может отработать)

**When** вызов приходит

**Then** `IsRevoked ∉ ReadFloorRPCs` → floor short-circuit'ит в **pass** (шаг 1 §1.1) — без FGA-Check
на hot-path
**And** RPC доходит до handler'а; покрыт mTLS-module-floor `CallerPolicy` (verified cert достаточно)
**And** явный assert: латентность hot-path не несёт нового FGA round-trip; FGA-outage не блокирует
token-refresh

### Сценарий 07: Seed — bootstrap выдаёт system_viewer 4 reader-SA; идемпотентность (INV-FLOOR-4)

**ID:** 5.1-07

**Given** свежая БД, миграции применены до 0014
**And** 0014 enqueue'ит в `fga_outbox` tuple-write для `api-gateway`, `vpc`, `compute`
(`vpc-operator` уже из 0010)

**When** drainer применяет outbox

**Then** в FGA существуют tuples `service_account:<sva-<svc>>#system_viewer@cluster:cluster_kacho_root`
для `svc ∈ {api-gateway, vpc, compute, vpc-operator}`
**And** `<sva-<svc>>` совпадает с детерминированным `'sva'||substr(md5('kacho-<svc>'),1,17)`
(та же функция, что floor / SEC-C / SEC-L)
**And** для каждого SA выдан **только** `system_viewer` — никакого `editor`/`admin`/`owner`/`fga_writer`-
расширения (least-priv)

**And** (idempotent re-apply) повторный прогон миграции / drainer →
**Then** ровно по одной такой outbox-intent на SA (`ON CONFLICT DO NOTHING`), без дублей; down-
миграция удаляет ровно эти 3 intent'а (vpc-operator из 0010 не трогается)

### Сценарий 08: Seed — vpc-operator re-seed no-op (не конфликтует с SEC-L 0010) (INV-FLOOR-4)

**ID:** 5.1-08

**Given** миграция 0010 (SEC-L) уже сидировала `vpc-operator#system_viewer@cluster:cluster_kacho_root`

**When** применяется 0014 (если она включает `vpc-operator` в seed-набор)

**Then** результат — **no-op** для `vpc-operator` (`ON CONFLICT DO NOTHING` / тот же payload-shape),
ровно одна intent-row для vpc-operator
**And** 0010 не редактируется (ban #5)

> Реализатор может либо **исключить** vpc-operator из 0014 (уже сидирован 0010), либо включить с
> гарантией no-op. Сценарий фиксирует требование: **либо** no-op-re-seed, **либо** явное исключение —
> без дублирующей/конфликтующей intent-row.

### Сценарий 09: Мутационная поверхность не меняется — regression-guard (INV-FLOOR-8)

**ID:** 5.1-09

**Given** prod-mode + mTLS, изменение 5.1 развёрнуто
**And** `kacho-vpc` (verified cert, держит `fga_writer@iam_fgaproxy:system`, но НЕ обязательно
`system_viewer`) вызывает `InternalIAMService/RegisterResource`

**When** вызов приходит

**Then** `RegisterResource ∉ ReadFloorRPCs` → `SystemViewerFloor` short-circuit'ит в **pass**
(не накладывает `system_viewer`-требование на write-RPC)
**And** in-handler `RelationWriteGate` (`fga_writer`) отрабатывает как до 5.1 (gate неизменен)
**And** gateway-only set (`ForceLogout`, `GrantAdmin`, `WriteTuples`, …) — нетронут; те же gRPC-коды,
что до 5.1 (ассерт опирается на **фактический gate** каждого RPC — in-handler `system_admin`-checker
для `ForceLogout`/`GrantAdmin`/`RevokeAdmin`, gateway-only-restriction для `WriteTuples` — НЕ на
catalog-`required_relation`, см. §1.5)

**And** (negative) module-SA без `fga_writer`, но с `system_viewer`, вызывает `RegisterResource`
**Then** `RelationWriteGate` всё равно → `PERMISSION_DENIED` (наличие `system_viewer` не даёт write-
capability — relation-tier'ы независимы)

---

## 4. Scope boundaries (явно ВНЕ под-фазы — не tech-debt)

1. **acr-on-internal floor** — отдельный residual. `required_acr_min` на internal user-token путях
   (step-up для admin-tier) — **другая** проблема (см. #122 «cluster-admin без acr»); эта под-фаза
   гейтит **module-SA** coarse-read-legitimacy, не user-token ACR. service→service (mTLS-SA) путь
   `required_acr_min` не консультирует (как `RelationWriteGate`, `fgaproxy.go` строки 14-18).
2. **Admin-tier на internal write-RPC `InternalAuthorizeService.{WriteTuples,ReloadModel,RunRegoTest}`**
   — primary scope этой волны = READ floor. Эти write-RPC сегодня в gateway-only set (только
   api-gateway-SA). Полноценный `system_admin`-tier на них — **deferred residual** (отслеживается в
   #122), НЕ закрывается здесь. Зафиксировано в §1.5.
3. **`InternalIAMService.Check` под coarse-floor** — допустимо опционально (caller module-SA, НЕ
   per-resource), но **не** обязательно для этой волны; default — Check НЕ в `ReadFloorRPCs` (§1.4).
   Если reviewer захочет — отдельный явный line-item, но per-resource gate на Check **запрещён**
   (INV-FLOOR-5).
4. **Контракт RPC не меняется** — нет нового RPC/поля/oneof; proto/REST/pagination/request/response
   идентичны. Floor — внутренний interceptor :9091. `kacho-proto`/`kacho-api-gateway` не трогаются.
5. **mTLS-инфраструктура** (cert-manager PKI, SAN-проброс) — SEC-F/SEC-H, предсуществует. Эта
   под-фаза **потребляет** verified-SAN (`grpcsrv.CertIdentityFromContext`), не вводит mTLS.
6. **One-shot back-fill** не требуется — set читателей фиксирован (4 module-SA), все сидятся seed'ом.
7. **Per-resource viewer-check на internal-read** — НЕ вводится (coarse cluster-floor только); per-
   user authz делает api-gateway до проброса.

---

## 5. Тесты (TDD — RED до кода, ban #12; в том же PR)

### 5.1 Unit — floor-интерсептор (`internal/authzguard/system_viewer_floor_test.go`)

Драйв через mock `RelationChecker` (тот же паттерн, что `RelationWriteGate`-тесты) + поддельный
`grpcsrv.CertIdentityFromContext`-контекст:

- **01-unit** — `prodMode=false`, READ-FQN → pass, ассерт `checker.Check` **не вызывался**.
- **02-unit** — `prodMode=true`, verified SAN `api-gateway`, checker→`allowed=true` → pass; ассерт
  **точной** строки субъекта: `Check("service_account:<sva-api-gateway>", "system_viewer",
  "cluster:cluster_kacho_root")`.
- **03-unit** — `prodMode=true`, verified SAN, checker→`allowed=false` → `PermissionDenied`,
  handler не вызван. + no-cert sub-case (verified=false) → `PermissionDenied`.
- **03b-unit** — `prodMode=true`, checker→error → `Unavailable` (НЕ pass, НЕ PermissionDenied);
  ассерт message `"authz backend unavailable"`.
- **04-unit** — `InternalIAMService/Check` (НЕ-floor-FQN) → pass без обращения к checker, даже в
  prod-mode (PDP-exempt regression-guard).
- **05/06-unit** — `OnRecoveryCompleted`, `IsRevoked` (НЕ-floor-FQN) → pass без checker.
- **09-unit** — `RegisterResource` (НЕ-floor-FQN) → floor pass; ассерт floor не добавляет
  `system_viewer`-требование (write-gate независим).
- **set-membership-unit** — table-driven: каждый FQN из `ReadFloorRPCs` — gated; каждый exempt-FQN
  (Check / hooks / IsRevoked / мутации) — НЕ gated. Ловит дрейф набора.

### 5.2 Integration — seed-миграция (`internal/repo/.../*integration_test.go`, testcontainers)

- Применить до 0014; ассерт `fga_outbox`-rows с `payload->>'relation'='system_viewer'`,
  `payload->>'object'='cluster:cluster_kacho_root'`,
  `payload->>'user'='service_account:'||('sva'||substr(md5('kacho-<svc>'),1,17))` для
  `svc ∈ {api-gateway, vpc, compute}` (+ vpc-operator если включён).
- Re-apply (идемпотентность) → ровно одна intent-row на SA (`ON CONFLICT DO NOTHING`).
- vpc-operator (0010) не дублируется (сценарий 08).
- Down-миграция удаляет ровно intent'ы 0014; 0010/0009 нетронуты.

### 5.3 FGA-model conformance — реальный OpenFGA (INV-FLOOR-2/3/4, blocking)

Зеркало SEC-L §5.4 (stub не ловит relation-резолюцию):

```
Seed:  service_account:<sva-api-gateway>#system_viewer@cluster:cluster_kacho_root
Assert POSITIVE: Check(service_account:<sva-api-gateway>, "system_viewer", cluster:cluster_kacho_root) == true
Assert NEGATIVE: Check(service_account:<sva-someother>,   "system_viewer", cluster:cluster_kacho_root) == false
Assert least-priv: Check(service_account:<sva-api-gateway>, "editor", cluster:cluster_kacho_root) == false
                   Check(service_account:<sva-api-gateway>, "admin",  cluster:cluster_kacho_root) == false
Assert wildcard-guard: Check(user:rando, "system_viewer", cluster:cluster_kacho_root) == false
                       (system_viewer = [user, service_account] без user:* — INV-FLOOR-4 / SEC-L INV-6)
```

### 5.4 Newman — black-box через api-gateway (`tests/newman/cases/iam-*.py`)

- Floor — internal :9091 (service→service mTLS), НЕ external REST; основное покрытие — unit +
  model-conformance.
- Newman-кейс на **default-OFF инвариант** (INV-FLOOR-1): в dev/newman-стенде (production-mode
  выключен) все user-facing public-RPC и пробрасываемые-на-internal-REST admin-RPC ведут себя
  **byte-identical к pre-5.1** — suite зелёный без изменений (≥1 happy подтверждает no-op; явный
  negative не применим к dev no-op, поэтому ключевой negative — на unit/model-уровне).

---

## 6. Traceability — закрываемый инвариант → артефакт → сценарий/тест

| Требование (security.md §«AuthN+AuthZ ВЕЗДЕ») | Изменение | Сценарий / Тест |
|---|---|---|
| Каждый internal READ-RPC проходит relation-tier Check (`system_viewer`) сверх mTLS | `authzguard.SystemViewerFloor` + chain в `serve.go` (§1.1/§1.3) | 02, 03 / 5.1 |
| dev/newman no-op (default-OFF, production-mode gate) | `prodMode` short-circuit (§1.1 шаг 2) | 01 / 5.1, 5.4 |
| Fail-closed: backend down → Unavailable; no-cert → PermissionDenied | parity `RelationWriteGate` (§1.1) | 03, 03b / 5.1 |
| PDP `Check` не гейтится как субъект | `Check ∉ ReadFloorRPCs` (§1.4) | 04 / 5.1 |
| Secret-authed webhooks + hot-path IsRevoked exempt | exemption-table (§1.4) | 05, 06 / 5.1 |
| Legitimate reader-SA сидятся `system_viewer` (seed-path, не SQL-backdoor) | migration 0014 / `fga_outbox` (§1.6) | 07, 08 / 5.2, 5.3 |
| Read-only least-priv (нет editor/admin) | seed только `system_viewer` (§1.6, INV-FLOOR-4) | 07 / 5.3 |
| Мутационная поверхность неизменна | floor исключает write-RPC (§1.5) | 09 / 5.1 |
| Контракт RPC не меняется | нет proto/REST/catalog-правки набора (§4.4) | — / 5.4 |
| Не редактировать применённые миграции | новая 0014 (ban #5) | 5.2 |

**Файлы:**

| Слой | Артефакт | Изменение |
|---|---|---|
| interceptor | `kacho-iam/internal/authzguard/system_viewer_floor.go` | новый `SystemViewerFloor` (Unary/Stream) + `ReadFloorRPCs()` (§1.1/§1.3) |
| wiring | `kacho-iam/cmd/kacho-iam/serve.go` | вставить floor в `internalSrv` chain после `internalCallerPolicy`; передать `prodMode` + `RelationChecker` (openfgaClient) |
| migration | `kacho-iam/internal/migrations/0014_system_viewer_floor_reader_sa.sql` | seed `system_viewer@cluster-root` для api-gateway/vpc/compute (§1.6) |
| tests | `internal/authzguard/system_viewer_floor_test.go`, `internal/repo/.../*integration_test.go`, model-conformance harness | §5 |
| vault | `obsidian/kacho/edges/`, `rpc/kacho-iam-internal-*.md`, `KAC/KAC-<N>.md` | trail после merge |

**Vault-сущности (wikilinks для KAC-trail):** `[[kacho-iam-InternalIAMService]]`,
`[[kacho-iam-InternalUserService]]`, `[[kacho-iam-InternalAuthorizeService]]`,
`[[fga-authorization-model]]`, `[[iam-cluster]]`, соответствующие `edges/*-to-iam-*`.

---

## 7. Definition of Done

- [ ] APPROVED от `acceptance-reviewer` (этот док) — ДО любого кода (ban #1).
- [ ] KAC-тикет заведён; ветка `KAC-<N>` в `kacho-iam`; KAC-trail в vault; trail-link на GitHub
      issue `kacho-iam#122` (этот gap — пункт backlog'а).
- [ ] RED-тесты написаны и прогнаны ПЕРВЫМИ (§5), показаны RED→GREEN пары.
- [ ] **set-membership RED→GREEN** (table-driven `ReadFloorRPCs` vs exempt — §5.1) — явный line-item.
- [ ] **§5.3 model-conformance (реальный OpenFGA): reader-SA получает `system_viewer`, foreign-SA и
      `user:rando` — нет; reader-SA НЕ получает editor/admin** — blocking, GREEN.
- [ ] `SystemViewerFloor` энфорсит `system_viewer@cluster:cluster_kacho_root` для `ReadFloorRPCs` в
      prod-mode; no-op в dev; fail-closed (PermissionDenied / Unavailable) per §1.1.
- [ ] `InternalIAMService.Check`, secret-webhooks, `IsRevoked`, все мутации — exempt от floor (§1.4);
      core authz-path не деградирует (сценарий 04 GREEN).
- [ ] Миграция 0014 сидирует `system_viewer@cluster` для api-gateway/vpc/compute через seed-path
      (НЕ SQL-backdoor); идемпотентна; vpc-operator (0010) не дублируется; down ревертит; 0009/0010
      нетронуты (§1.6).
- [ ] Мутационная поверхность неизменна (`RegisterResource` всё ещё `fga_writer`-gated; gateway-only
      set нетронут) — сценарий 09 GREEN.
- [ ] newman E2E **не затронут** (default-OFF) — suite зелёный без изменений (INV-FLOOR-1).
- [ ] Финальная верификация: `go test ./... -race` + `golangci-lint run` + `gosec` + `govulncheck`
      + newman зелёные.
- [ ] Ревью ролями: `db-architect-reviewer` (миграция 0014 / outbox idempotency),
      `system-design-reviewer` (fail-closed / hot-path exemptions / seed-propagation),
      `go-style-reviewer` (interceptor / wiring).
- [ ] Vault-trail обновлён (edges/rpc/KAC); тикет Test → Done с артефактами; GitHub issue #122 —
      пункт «internal-READ relation-tier Check» отмечен closed.

---

## 8. Решения reviewer'а (closed — фиксируют дизайн)

Открытые вопросы закрыты на acceptance-review (2026-06-16):

1. **`InternalIAMService.Check` под coarse `system_viewer`-floor → НЕТ.** Check остаётся exempt от
   floor (default волны, §1.4). Per-resource gate на Check **запрещён** (INV-FLOOR-5); coarse-only
   line-item в этой волне не добавляется — лишний FGA round-trip на каждом downstream-authz
   (hot-path) без security-выигрыша (Check уже под `CallerPolicy`-floor). Будущая потребность —
   отдельный residual в #122.
2. **`vpc-operator` в 0014 → ИСКЛЮЧИТЬ.** Уже сидирован SEC-L 0010; меньше дублирующих intent-rows,
   проще down (0014 ревертит ровно api-gateway/vpc/compute). Сценарий 08 остаётся regression-guard
   на no-conflict; включение с `ON CONFLICT DO NOTHING` допустимо как fallback.
3. **Admin-tier на `InternalAuthorizeService.{WriteTuples,ReloadModel,RunRegoTest}` → ОТЛОЖЕНО
   (подтверждено).** Сейчас в gateway-only set (только api-gateway-SA); полноценный `system_admin`-
   tier — отдельная residual-волна (#122), НЕ блокер этой READ-floor под-фазы (§1.5/§4.2).
