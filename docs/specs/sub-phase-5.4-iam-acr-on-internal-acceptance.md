# Sub-phase 5.4 (kacho-iam — enforce `required_acr_min` step-up on the cluster-internal :9091 path for gateway-fronted privileged RPCs) — Acceptance

> **Статус:** ✅ APPROVED (ревью `acceptance-reviewer`, 2026-06-16 — все code-grounding-claims подтверждены против `kacho-proto`/`kacho-iam`/`kacho-corelib`/`kacho-api-gateway`)
> **Дата:** 2026-06-16
> **Ревьюер:** `acceptance-reviewer` (единственный gate APPROVED per workspace `CLAUDE.md` §Non-negotiables #1)
> **Автор-агент:** `acceptance-author`
> **Эпик/тикет:** KAC-`<N>` (subtask; trail-anchor — GitHub issue `PRO-Robotech/kacho-iam#122`, prod-readiness backlog «P2 acr-on-internal (acr-metadata plumbing gateway→corelib)»; Round-5 residual). Ветки `KAC-<N>` в `kacho-corelib`, `kacho-iam`, `kacho-api-gateway`.
> **Target repos (кросс-репо, порядок по build-графу):** `kacho-corelib` (PRIMARY — acr-carrying trusted-principal extract) → `kacho-iam` (PRIMARY — per-RPC acr-floor interceptor на :9091) → `kacho-api-gateway` (forward acr-metadata на internal mux re-dial). `kacho-proto` **не затрагивается** (контракт RPC не меняется; acr — transport-metadata, не proto-поле). `permission_catalog.json` правится только в части тест-фикстуры (см. §«Реальность каталога»).
> **Конвенции (нормативно, не дублируются в теле — ссылки):**
> `.claude/rules/security.md` (§«AuthN+AuthZ ВЕЗДЕ» — закрываемый инвариант; «Internal = trusted, mTLS достаточно» — запрещённое допущение; Internal-vs-public ban #6),
> `.claude/rules/api-conventions.md` (error-format / gRPC-коды / стабильность текстов),
> `.claude/rules/data-integrity.md` (fail-closed cross-domain; trust-boundary metadata),
> `.claude/rules/testing.md` (строгий TDD-red ДО кода, ban #12/#13),
> `.claude/rules/polyrepo.md` (кросс-репо порядок proto→corelib→service→gateway).
> **Образцы стиля:** 5.1 (`sub-phase-5.1-iam-internal-reads-system-viewer-floor-acceptance.md` — тот же паттерн: per-RPC floor-интерсептор на :9091, default-off prod-mode, fail-closed, real-OpenFGA/прод-only; этот документ — acr-floor поверх того же chain), 5.0 (`sub-phase-5.0-internal-tier-authz-hardening-acceptance.md` — public-tier catalog hardening), SEC-B (`sub-phase-SEC-B-corelib-mtls-acceptance.md` — trust-boundary `UnaryTrustedPrincipalExtract` / FD-4 invariant, в который встраивается acr-plumbing), 3.2 (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md` — ACR/step-up matrix §2.1/§2.2, источник семантики acr-уровней).

---

## Обзор

`required_acr_min` (step-up / MFA-freshness floor из permission-каталога) сейчас энфорсится
**только на публичном пути**: api-gateway валидирует JWT, сверяет `acr`-claim с
`required_acr_min` и на недостаточном уровне возвращает RFC 9470 step-up challenge
(`StepUpGate.Check`, `dpop_http_middleware.go`). Но привилегированные admin-RPC
(`InternalClusterService.GrantAdmin`/`RevokeAdmin`/`ListAdmins`/`Get` и пр.) — **Internal-only**
(:9091, ban #6) и достигаются через api-gateway **internal mux**, который переноправляет
forwarded end-user principal. На этом internal-пути `required_acr_min` **не проверяется**:
forwarded principal-metadata несёт только `type`/`id`/`display-name` (corelib
`principalFromIncomingMetadata`), а `acr` **не пробрасывается** в gRPC-metadata на re-dial
(`restmux/mux.go` `principalMetadata` callback собирает только `x-kacho-principal-*`). Поэтому
пользователь со stale/низким `acr` в JWT может провести привилегированную admin-операцию через
internal-маршрут, минуя step-up.

Эта под-фаза **закрывает плечо**: (1) gateway пробрасывает `acr` валидированного JWT как
доверенную metadata `x-kacho-acr` на :9091-вызов (только на mTLS-verified gateway→iam ребре);
(2) corelib `UnaryTrustedPrincipalExtract` вносит `acr` в neutral-принципал/ctx под тем же FD-4
trust-инвариантом; (3) iam internal-authz слой энфорсит `acr >= required_acr_min` для
gateway-fronted RPC с `required_acr_min > 0` → иначе `PermissionDenied` со step-up-сигналом.
Service-caller (vpc/compute/nlb fgaproxy — не user-principal, без MFA) от acr-floor **освобождён**.

**Это не новый RPC и не новое proto-поле** — это transport-metadata plumbing + enforcement-точка
во внутренней interceptor-цепочке. Контракт RPC (методы, request/response) не меняется.

---

## Реальность каталога (ground-truth, читать ДО сценариев — определяет scope)

Сверено с `kacho-proto/gen/permission_catalog.json` + iam-копией
`internal/apps/kacho/api/internal_iam/embedded/permission_catalog.json` (2026-06-16). ACR-уровни —
из 3.2 §2.1: `0` anonymous · `1` password-only (AAL1) · `2` phishing-resistant/MFA (AAL2) · `3`
hardware-bound UV passkey (AAL3).

**Gateway-fronted internal RPC-набор** = `authzguard.GatewayFrontedInternalRPCs()`
(`caller_policy.go`) — единственные internal-RPC, у которых caller-context = api-gateway,
действующий за end-user'а. Их текущий `required_acr_min`:

| Gateway-fronted internal RPC | `required_acr_min` сегодня | acr-floor применится? |
|---|---|---|
| `InternalClusterService/Get` | **2** | **ДА** |
| `InternalClusterService/GrantAdmin` | **2** | **ДА** |
| `InternalClusterService/RevokeAdmin` | **2** | **ДА** |
| `InternalClusterService/ListAdmins` | **2** | **ДА** |
| `InternalIAMService/ForceLogout` | 0 / none | нет (latent) |
| `InternalAuthorizeService/WriteTuples` | 0 / none | нет (latent) |
| `InternalAuthorizeService/{ReadTuples,ReloadModel,RunRegoTest,GetFGAStoreInfo}` | 0 / none | нет (latent) |
| `InternalSessionRevocationsService/{Revoke,ListByUser}` | 0 / none | нет (latent) |
| `InternalUserService/{UpsertFromIdentity,OnRecoveryCompleted}` | 0 / none | нет (latent) |

**Вывод по scope (важно для ревьюера):** механизм **не полностью латентный** — `InternalClusterService.*`
(cluster-admin RBAC из admin-UI) **уже** несут `required_acr_min=2`, значит acr-floor для них даёт
**немедленный наблюдаемый эффект** в prod-mode. Прочие gateway-fronted admin-RPC сегодня имеют
`required_acr_min=0` → для них floor **latent-until-policy** (включится, когда политика поднимет
их acr_min). Поэтому под-фаза = **«wire the enforcement mechanism end-to-end» + немедленный
эффект на `InternalClusterService.*` + тест-фикстура, поднимающая `required_acr_min>0` на
ForceLogout** (доказывает, что floor сработает для любого RPC, как только политика так скажет).
Любое изменение `required_acr_min` для прочих RPC — отдельное policy-решение (вне scope; не
менять реальный prod-каталог в этой под-фазе, кроме тест-фикстуры).

**Не-gateway-fronted internal RPC** (`InternalIAMService/Check`, `…/RegisterResource`,
`InternalAddressService/Allocate*`, `InternalWatchService/Watch`, …) — вызываются МОДУЛЬНЫМИ SA
(vpc/compute/nlb), не пользователем; acr к ним **неприменим** (у SA нет MFA / нет acr-claim).
Они остаются на своих gate'ах (mTLS-floor + `RelationWriteGate`/`system_viewer`-floor), acr-floor
их **не трогает**. Это согласуется с уже зафиксированным освобождением SA от `required_acr_min`
(см. `edges/vpc-operator-to-vpc-mtls.md`: «SA освобождён от `required_acr_min`, service→service»).

---

## Точка энфорса (ground-truth — где именно встраивается, наблюдаемо снаружи косвенно)

Док описывает **наблюдаемое поведение** (gRPC-коды на :9091 + сквозной REST через gateway), не
внутреннюю реализацию. Для трассируемости ревьюером фиксируем фактическую цепочку (источник
истины — код, не этот док):

- **corelib** `grpcsrv.UnaryTrustedPrincipalExtract` (`cert_identity.go`) — читает forwarded
  principal-metadata под FD-4 trust-инвариантом (доверяем ⟺ peer mTLS-verified). Расширяется:
  дополнительно читает `x-kacho-acr` и кладёт его в neutral-принципал/ctx **только когда principal
  trusted** (на untrusted TLS-peer — drop вместе с principal, anti-spoof).
- **iam** новый interceptor `authzguard` acr-floor — в internal-цепочке (`cmd/kacho-iam/serve.go`)
  **после** `UnaryTrustedPrincipalExtract` и `internalCallerPolicy`, рядом с
  `internalSystemViewerFloor` (тот же default-off prod-mode паттерн). Для каждого RPC из
  gateway-fronted-набора с `required_acr_min > 0` (lookup по FQN из embedded-каталога) проверяет
  `acrRank(acr) >= acrRank(required_acr_min)`.
- **gateway** `restmux/mux.go` `principalMetadata` callback — добавляет `x-kacho-acr` (из
  `X-Kacho-Token-Acr`, который public DPoP-middleware уже выставляет) в outgoing gRPC-metadata
  на internal-mux re-dial (рядом с уже пробрасываемыми `x-kacho-principal-*`).

---

## Сценарии

ACR-ранжирование (нормативно, 3.2 §2.1): `"" / "0" < "1" < "2" < "3"`; неизвестное значение → ранг 0
(fail-closed). Все prod-mode сценарии предполагают `KACHO_IAM_AUTHN_MODE=production` + mTLS-verified
gateway→iam ребро (как 5.1 floor). REST-сценарии идут через api-gateway **internal mux**
(`*InternalAddr`-блок; ban #6 — на external endpoint этих путей нет).

### Сценарий 5.4-01: gateway-fronted privileged RPC, acr ≥ required_acr_min → allowed

**ID:** 5.4-01

**Given** prod-mode iam с mTLS-verified gateway→iam ребром
**And** RPC `InternalClusterService/GrantAdmin` имеет `required_acr_min = "2"` в каталоге
**And** end-user держит `system_admin@cluster:cluster_kacho_root` в ReBAC (in-handler gate проходит)

**When** api-gateway вызывает `/kacho.cloud.iam.v1.InternalClusterService/GrantAdmin` на :9091
с trusted metadata:
  - `x-kacho-principal-type` = `user`
  - `x-kacho-principal-id` = `usr<…>`
  - `x-kacho-acr` = `2`

**Then** acr-floor пропускает (`2 >= 2`)
**And** запрос доходит до handler, in-handler `requireSystemAdmin` (system_admin@cluster) проходит
**And** RPC возвращает успешный ответ (grant создан) — поведение идентично сегодняшнему prod-pre-floor для валидного acr.

### Сценарий 5.4-02: acr < required_acr_min → denied (step-up), без side-effect

**ID:** 5.4-02

**Given** prod-mode iam с mTLS-verified gateway→iam ребром
**And** RPC `InternalClusterService/GrantAdmin` имеет `required_acr_min = "2"`

**When** api-gateway вызывает `InternalClusterService/GrantAdmin` на :9091 с metadata:
  - `x-kacho-principal-type` = `user`, `x-kacho-principal-id` = `usr<…>`
  - `x-kacho-acr` = `1`  (password-only)

**Then** acr-floor отклоняет ДО handler'а: gRPC `PERMISSION_DENIED`, message `"permission denied"`
  (стабильный non-leaking текст — `api-conventions.md`)
**And** ответ несёт step-up-сигнал в деталях статуса (`PreconditionFailure`-violation типа
  step-up / `acr_values`), консистентно с public-path `buildGRPCDenyStatus`
  (`permission_denied_response.go`) — так gateway может перевести в RFC 9470 challenge
  (`Bearer error="insufficient_user_authentication", acr_values="2"`)
**And** handler НЕ вызван → grant НЕ создан (no side-effect; проверяется отсутствием новой записи
  через последующий `InternalClusterService/ListAdmins` с достаточным acr).

### Сценарий 5.4-03: acr metadata отсутствует на acr-требующем RPC → fail-closed (treated as acr=0)

**ID:** 5.4-03

**Given** prod-mode iam с mTLS-verified gateway→iam ребром
**And** RPC `InternalClusterService/GrantAdmin` имеет `required_acr_min = "2"`

**When** api-gateway вызывает `InternalClusterService/GrantAdmin` на :9091 с principal-metadata, но
**без** `x-kacho-acr` (метаданные acr отсутствуют)

**Then** acr-floor трактует отсутствующий acr как ранг 0 → `0 < 2` → gRPC `PERMISSION_DENIED`
  со step-up-сигналом
**And** handler НЕ вызван (no side-effect). Default-safe: отсутствие acr на RPC, который его
  требует, в prod-mode = denied (`security.md` fail-closed).

### Сценарий 5.4-04: gateway-fronted RPC с required_acr_min = 0 → acr не проверяется

**ID:** 5.4-04

**Given** prod-mode iam с mTLS-verified gateway→iam ребром
**And** RPC из gateway-fronted-набора с `required_acr_min` = 0 / none (напр.
  `InternalSessionRevocationsService/Revoke` в текущем каталоге)

**When** api-gateway вызывает этот RPC на :9091 с `x-kacho-acr` = `0` (или вовсе без acr-metadata)

**Then** acr-floor **пропускает** (для acr_min=0 floor — no-op; `RequiredACRMin == ""` ⇒ нет требования,
  как `StepUpGate.Check`)
**And** запрос доходит до своего обычного gate (gateway-only caller-policy + in-handler authz) и
  обрабатывается как сегодня (acr на это поведение не влияет).

### Сценарий 5.4-05: non-gateway service-caller на internal RPC → acr-exempt

**ID:** 5.4-05

**Given** prod-mode iam с mTLS-verified ребром
**And** caller — модульный SA (напр. kacho-vpc, SAN `…/sa/kacho-vpc`), вызывает НЕ-gateway-fronted
  internal RPC (напр. `InternalIAMService/RegisterResource`)

**When** kacho-vpc вызывает `InternalIAMService/RegisterResource` на :9091 без `x-kacho-acr`
  (у модульного SA нет user-acr)

**Then** acr-floor **не применяется** (RPC не входит в gateway-fronted acr-набор; caller — не
  gateway) → проходит без acr-проверки
**And** запрос проходит свой штатный gate (`RelationWriteGate` fga_writer) как сегодня. Service→service
  путь acr-нейтрален (SA освобождён от `required_acr_min`).

### Сценарий 5.4-06: спуфинг acr не-gateway caller'ом → отклонён (acr доверяем только на verified gateway-ребре)

**ID:** 5.4-06

**Given** prod-mode iam с mTLS-listener
**And** скомпрометированный модульный caller (НЕ api-gateway SAN) вызывает gateway-fronted RPC
  `InternalClusterService/GrantAdmin`, подделав metadata `x-kacho-acr` = `3` и
  `x-kacho-principal-*` = чужого user'а

**When** этот не-gateway caller делает вызов на :9091

**Then** запрос отклоняется на `internalCallerPolicy` (gateway-only RPC от не-gateway модуля →
  `PERMISSION_DENIED`) **до** acr-floor — caller-policy уже срабатывает первым
**And** дополнительно: forwarded principal+acr приходят с НЕ-gateway peer'а → даже если caller-policy
  гипотетически прошёл бы, acr/principal trusted ⟺ FD-4 (peer mTLS-verified gateway). На
  unverified/foreign-SAN peer forwarded acr **dropped** (как principal в SEC-B) → трактуется как
  acr=0 → denied. Спуфнутый `x-kacho-acr` не повышает уровень (не spoofable вне verified gateway-ребра).

### Сценарий 5.4-07: dev-mode no-op consistency

**ID:** 5.4-07

**Given** dev/newman-стенд: `KACHO_IAM_AUTHN_MODE` НЕ production (insecure listener, без mTLS,
  acr-metadata может отсутствовать)

**When** любой gateway-fronted RPC (включая `InternalClusterService/GrantAdmin` с `required_acr_min=2`)
  вызывается с любым/отсутствующим `x-kacho-acr`

**Then** acr-floor — **NO-OP pass-through** (как `internalCallerPolicy` / `internalSystemViewerFloor`
  в dev): поведение байт-в-байт идентично сегодняшнему newman-стенду
**And** newman E2E остаётся зелёным без изменения кейсов (default-off prod-mode паттерн — единый
  сигнал prod-mode, что и у 5.0/5.1 floor'ов).

### Сценарий 5.4-08: тест-фикстура поднимает required_acr_min>0 на ранее-0 RPC → floor срабатывает

**ID:** 5.4-08

**Given** prod-mode iam с тест-фикстурным каталогом, где `InternalIAMService/ForceLogout` имеет
  `required_acr_min = "2"` (фикстура; реальный prod-каталог в этой под-фазе не меняется для ForceLogout)

**When** api-gateway вызывает `ForceLogout` на :9091 с `x-kacho-acr` = `1`

**Then** acr-floor отклоняет (`1 < 2`) → gRPC `PERMISSION_DENIED` со step-up-сигналом, handler не вызван
**And** тот же `ForceLogout` с `x-kacho-acr` = `2` проходит floor → доходит до handler.
  (Доказывает: enforcement-механизм generic по FQN→acr_min, сработает для любого gateway-fronted
  RPC, как только политика поднимет его `required_acr_min` — latent-until-policy замкнут.)

---

## CI-validatable vs требует live-gateway (явно — по запросу)

| Слой | Что проверяется | Как (TDD) | CI-validatable? |
|---|---|---|---|
| corelib acr-extract | `x-kacho-acr` вносится в принципал/ctx ⟺ trusted (FD-4); drop на untrusted peer (anti-spoof 5.4-06 plumbing-часть) | unit-тест `grpcsrv` с синтетическим ctx/peer (как существующие `cert_identity` unit-тесты) | **ДА** |
| iam acr-floor interceptor | 5.4-01..05, 5.4-07, 5.4-08: allow/deny по acr vs catalog acr_min, gateway-fronted-набор, exempt service-caller, dev no-op, fixture-acr_min>0 | unit-тест интерсептора (table-driven: acr × required_acr_min × prod-mode × RPC-в-наборе), fake catalog + ctx | **ДА** |
| iam acr-floor + caller-policy ordering | 5.4-06: caller-policy срабатывает первым; acr drop на не-gateway peer | unit/integration interceptor-chain тест (bufconn, как 5.1 floor integration) | **ДА** |
| gateway forward acr-metadata | `restmux` `principalMetadata` добавляет `x-kacho-acr` в outgoing md из `X-Kacho-Token-Acr` | unit-тест callback'а (как существующие principal-metadata тесты) | **ДА** (на стороне gateway) |
| Сквозной REST→internal-mux→iam :9091 | полный путь: JWT acr → gateway public DPoP-mw → internal re-dial → iam floor → deny/allow | newman/e2e через **живой** gateway + iam с mTLS + prod-mode | **требует live-gateway** (e2e-стенд; `make e2e-test` / smoke заказчика) |

Newman happy+negative обязателен (`testing.md`): ≥1 happy (acr достаточен → allowed) + ≥1 negative
(acr недостаточен → PERMISSION_DENIED) на сквозном пути. На default newman-стенде (dev-mode) floor —
no-op (5.4-07), поэтому prod-mode acr-кейсы — отдельная e2e-конфигурация (prod-mode stand), как и
для 5.0/5.1 floor'ов.

---

## DoD (Definition of Done)

**Кросс-репо порядок (build-граф):** `kacho-corelib` → `kacho-iam` → `kacho-api-gateway`. Пока
вышестоящее не в `main` — нижестоящий CI пиннит sibling к feature-ветке `KAC-<N>` (`polyrepo.md`).
proto не затрагивается.

- [ ] **TDD-red ДО кода** (ban #12): сперва падающие тесты по сценариям 5.4-01..08 (RED), затем код → GREEN; в PR показана пара RED→GREEN.
- [ ] **corelib:** `UnaryTrustedPrincipalExtract` (+ stream-аналог) carries `x-kacho-acr` в neutral-принципал/ctx под FD-4 trust-инвариантом (drop на untrusted peer); exported helper для чтения acr из ctx. Unit-тесты (5.4-06 plumbing). vault: `packages/<corelib-grpcsrv>.md` обновлён.
- [ ] **iam:** новый `authzguard` acr-floor interceptor — gateway-fronted-набор × `required_acr_min>0` × prod-mode; default-off dev no-op; fail-closed (absent acr → deny). Встроен в internal-цепочку `serve.go` после `UnaryTrustedPrincipalExtract` + `internalCallerPolicy`. FQN→acr_min lookup из embedded permission-каталога (`seed.PermissionRegistry.LookupFQN`). Unit + integration (bufconn) тесты 5.4-01..05/07/08. Удалены/обновлены follow-up-комментарии в `cluster/admin_authz.go` и `internal_iam/force_logout.go` (acr теперь энфорсится floor'ом). vault: `rpc/iam-internal-*.md` / новый `edges/api-gateway-to-iam-acr-floor.md`.
- [ ] **api-gateway:** `restmux/mux.go` `principalMetadata` пробрасывает `x-kacho-acr` (из `X-Kacho-Token-Acr`) в outgoing gRPC-metadata internal-mux re-dial. Unit-тест callback'а. vault: `edges/api-gateway-to-iam-*.md` History-запись с KAC-номером.
- [ ] **Тест-фикстура** (5.4-08): catalog-фикстура с `required_acr_min>0` на ForceLogout — только в тестах, реальный prod-каталог для ForceLogout НЕ меняется (latent-until-policy остаётся явным).
- [ ] **Newman**: ≥1 happy + ≥1 negative на сквозном acr-пути (prod-mode e2e-конфиг); dev-стенд no-op подтверждён (5.4-07, newman зелёный без изменений кейсов).
- [ ] **Ревью ролями:** `system-design-reviewer` (trust-boundary / metadata propagation / fail-closed), `go-style-reviewer` (interceptor, thin, no panic). proto не менялся → `proto-api-reviewer` N/A. Схема БД не менялась → `db-architect-reviewer` N/A.
- [ ] **Финальная верификация:** `go test ./... -race` + `golangci-lint run` + `govulncheck` (corelib, iam, gateway) + newman зелёные.
- [ ] **Trail (#122):** vault KAC-trail обновлён; GitHub issue `kacho-iam#122` пункт «P2 acr-on-internal» закрыт; `PROD-READINESS-iam-2026-06.md` DoD-чекбокс «acr-on-internal» отмечен. Тикет YouTrack → Test→Done с артефактами (PR-URL × 3 репо, лог тестов).

---

## Заметки для ревьюера (трассировка ground-truth)

1. **Plumbing-gap подтверждён в коде:** `restmux/mux.go` `principalMetadata` собирает только
   `x-kacho-principal-{type,id,display-name}` (НЕ acr); corelib `principalFromIncomingMetadata`
   читает только type/id/display; два in-code follow-up-комментария явно фиксируют дыру
   (`cluster/admin_authz.go` L23-28, `internal_iam/force_logout.go` L93-95: «acr step-up NOT enforced
   here … Plumbing acr … tracked as follow-up»). `X-Kacho-Token-Acr` уже выставляется public
   DPoP-middleware («Bonus: … for downstream audit») — то есть acr доходит до gateway-HTTP-слоя,
   но обрывается на internal re-dial.
2. **Код возврата = `PermissionDenied`** (не `FailedPrecondition`): соответствует public-path
   `buildGRPCDenyStatus` (`permission_denied_response.go` → `codes.PermissionDenied` + step-up
   `PreconditionFailure`/`acr_values` в деталях) и precedent'у `CallerPolicy`/`SystemViewerFloor`
   (оба `PermissionDenied`, verbatim non-leaking). Step-up-намерение несётся в деталях статуса, не
   отдельным кодом — чтобы gateway транслировал в RFC 9470 challenge.
3. **Немедленный эффект vs latent:** только `InternalClusterService.*` сегодня имеют `acr_min=2` →
   immediate. Прочие gateway-fronted admin-RPC = `acr_min=0` → floor latent до policy-изменения
   (вне scope). Поэтому фикстура 5.4-08 — обязательное доказательство, что механизм generic.
4. **Освобождение SA от acr** — by-design и уже зафиксировано (`edges/vpc-operator-to-vpc-mtls.md`:
   «SA освобождён от `required_acr_min`, service→service»); acr-floor применяется только к
   gateway-fronted RPC, где caller = gateway-за-user'а.
