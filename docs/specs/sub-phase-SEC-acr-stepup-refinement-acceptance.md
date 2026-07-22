# Sub-phase SEC-acr-stepup-refinement (сузить `required_acr_min="2"` step-up-floor с blanket-372-RPC до полной **grant-поверхности** = 41 posture-changing операций, per RFC 9470 + NIST 800-63B) — Acceptance

> **Статус:** ✅ APPROVED (2026-07-22, R3) — оба gate'а APPROVED: `acceptance-reviewer` (41-set ground-truthed против каталога, арифметика 41+332+65=438 holds) + `system-design-reviewer` (round-2: все 4 code-verified блокера B-1..B-4 закрыты — fail-safe scoped на non-exempt, `GroupService/Delete` под-включён, третий godoc `pkg/grpcsrv/acr.go`, verdict-parity lock-тест). Кодинг разблокирован (ban #1 снят).
> **Дата:** 2026-07-22
> **Ревизия:** R3 — учтён CHANGES REQUESTED round-2 от `system-design-reviewer` (4 code-verified блокера) + non-blocking-заметки `acceptance-reviewer`. Правки R3: (B-2, material) `GroupService/Delete` — **revoke-по-всем** (cascade `group_members` + cleanup group-targeted `AccessBinding.subject_id`, verified `api/group/delete.go`) → **под-включён в sensitive** (категория D), set **40 → 41**, routine **333 → 332** (iam-routine 50 → 49); (B-1) fail-safe layer (a) generator-default `"2"` scoped на **non-exempt** RPC — exempt un-annotated получает пустой acr (early-return ДО default-injection), НЕ покрыт ни step-up-, ни authz-completeness-backstop'ом → полагается на deliberate FGA-exempt posture + authN + in-handler ReBAC (новый exempt-RPC = high-scrutiny); (B-3) третий misleading godoc `pkg/grpcsrv/acr.go` («SHARED … used by BOTH … never drift» — ложно, gateway держит свой `acrRank`) добавлен в doc-truthfulness-fix-set; (B-4) O1 lock-тест усилен: ассертит **идентичность enforcement-вердикта** двух реальных entrypoint'ов (`StepUpGate.Check` ↔ `grpcsrv.ACRSatisfies`) над `{presented}×{required}` incl. `""`, не только совпадение rank-функций. R2 (база): core-принцип domain-agnostic grant-поверхность (sensitive 11 → 40, compute-grant опроверг «no non-iam acr=2»); `AccessBindingService/Create` net-strengthening (exempt+acr2); B6 author-inert; V3/O1. Все FQN/counts ground-truthed против worktree-каталога (2026-07-22).
> **Ревьюер:** `acceptance-reviewer` (единственный gate APPROVED per workspace `CLAUDE.md` §Non-negotiables #1 — заказчик к approve контракта не подключается)
> **Автор-агент:** `acceptance-author`
> **Тип:** security-model refinement (изменение **значений** permission-каталога + proto-аннотаций + regen обеих embedded-копий + lock-тесты). **НЕ** новый ресурс / RPC / proto-message / схема БД. FGA relation-authz, SA-exemption и ACR-minting/IdP **не трогаются**.
> **Repo / ветка (монорепо-редизайн):** `github.com/PRO-Robotech/kacho`, ветка `redesign/integration`. Working dir реализации — `/home/dk/.claude/jobs/2cf6b0b4/tmp/wt-integration`. Затрагиваются intra-repo модули: `proto/kacho/cloud/**` (аннотации) → `gateway/internal/middleware/embed/permission_catalog.json` (regen) → `services/iam/internal/apps/kacho/seed/embedded/permission_catalog.json` (byte-identical sync) + lock-тесты в `gateway/` и `services/iam/`.
> **Связанные GitHub issues:** `#59` (Phase C production-newman — эта фаза — финальный блокер, разблокирующий production-mode newman для user-subject потоков), `#60` (iam SA cannot issue user tokens — смежный SA-путь; не регрессирует).
> **Конвенции (нормативно, не дублируются в теле — ссылки):**
> `.claude/rules/security.md` (§«AuthN+AuthZ ВЕЗДЕ» — authN остаётся обязательным на каждом листенере; SA-exemption O-1; permission-catalog полон и byte-identical, CI-гейт; hardening-инвариант #5 doc-truthfulness),
> `.claude/rules/api-conventions.md` (error-format / gRPC-коды / стабильные non-leaking тексты / permission-catalog регенерируется из proto, обе копии byte-identical),
> `.claude/rules/testing.md` (строгий TDD-red ДО кода, ban #12/#13; regression на уровне обсёрвабла),
> `.claude/rules/00-kacho-core.md` (#14 production-grade, никогда MVP; сужение scope допустимо только как production-complete под-фаза).
> **Образцы стиля / прямой прецедент:**
> `sub-phase-5.4-iam-acr-on-internal-acceptance.md` (**прямой прецедент** — ввёл acr-floor-механизм: per-RPC `required_acr_min`-enforcement на gateway StepUpGate + iam :9091 acr_floor; этот документ **сужает набор RPC**, к которым он применяется, не меняя механизм),
> `sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md` (§2.1/§2.2 — семантика ACR-уровней / RFC 9470 step-up matrix),
> `sub-phase-5.1-iam-internal-reads-system-viewer-floor-acceptance.md` (default-off prod-mode floor, fail-closed),
> `sub-phase-registry-iam-jwks-unify-acceptance.md` (формат security-config-рефайнмента: инварианты-таблица + traceability).

---

## Обзор

`required_acr_min` — per-RPC step-up / MFA-freshness floor из permission-каталога (single
source of truth для per-RPC authz, **генерируется** из proto-аннотаций
`(kacho.iam.authz.v1.required_acr_min)`). Его энфорсят **два** рантайм-читателя одного и
того же каталожного значения: gateway `StepUpGate`
(`gateway/internal/middleware/stepup_gate.go` + `dpop_http_middleware.go`) на public/edge-пути
и iam internal acr-floor (`services/iam/internal/authzguard/acr_floor.go`) на cluster-internal
:9091 для gateway-fronted privileged RPC (введён в 5.4). ACR-ранжирование (нормативно, 3.2 §2.1):
`"0"` anonymous < `"1"` password / AAL1 < `"2"` MFA / AAL2 < `"3"` hardware-bound / AAL3.

Сегодня каталог штампует `required_acr_min="2"` на **372 из 438** RPC (66 — `permission="<exempt>"`
без acr-ключа). То есть step-up MFA требуется **на каждом** `acr>=2`-RPC — на любом ресурсном
`Get`/`List`/`Create`/`Update`/`Delete` и `:verb`-action всех доменов, а не только на операциях,
меняющих security-posture. Эта под-фаза сужает floor до **полной grant-поверхности** — операций,
непосредственно меняющих чью-то действующую привилегию (**независимо от домена**), оставляя `"2"`
на **41** RPC и понижая все прочие non-exempt (332) до `"1"` (нормальная аутентификация, AAL1).

**End-state каталога:** 41 × `"2"` · 332 × `"1"` · 65 × acr=`""` (нет step-up-требования). 41+332+65=438.

### PROBLEM (live-diagnosed — определяет мотивацию, читать ДО сценариев)

- **Наблюдаемый дефект.** User-токен несёт `acr<=1` (password / AAL1) в штатном non-interactive
  потоке. При blanket-`acr>=2` он получает **`401` step-up-required на КАЖДОМ** ресурсном
  `Get`/`List`/CRUD — то есть на любой рутинной операции.
- **Почему это анти-паттерн.** Форсировать интерактивную MFA-переаутентификацию на каждом рутинном
  `List` ломает (а) non-interactive automation (CI/SDK/service-tooling с user-токеном), (б) **все
  production-newman user-subject потоки** (`#59`, Phase C). Step-up по RFC 9470 — carved-out
  исключение для чувствительных операций, а **не** дефолт для всего трафика.
- **SA-принципалы уже освобождены** (O-1, `kacho_principal_type=="service_account"`; см.
  `stepup_gate.go` `isServiceAccountPrincipal`, `acr_floor.go`) — SA структурно не может предъявить
  MFA-acr. User-принципалы **не** освобождены (и не должны быть) → проблема бьёт по user-subject-потокам.
- **Это финальный блокер `#59`.** После сужения floor'а user-токен с AAL1 проходит рутинный
  жизненный цикл ресурсов, а step-up сохраняется **точечно** на 41 grant/posture-changing RPC.
- **FGA relation-authz — НЕ проблема и НЕ трогается.** Понижается **только** acr-floor
  (assurance-level), не relation-check. Понижение acr не даёт ни одной новой привилегии: downstream
  FGA `Check` (relation `editor`/`v_update`/`system_admin`/…) остаётся тем же.

**Наблюдаемая цель:** user-токен с `acr="1"` проходит любой рутинный/read/lifecycle-RPC (и далее
подчиняется неизменному FGA-authz); step-up-`401` сохраняется дословно на 41 названном grant/posture
RPC; SA-принципалы проходят и то и другое (exemption не сломан); ровно 41 FQN несёт `"2"`, обе
embedded-копии каталога byte-identical.

---

## Принцип решения (нормативно — RFC 9470 §1 + NIST 800-63B AAL) — переформулирован (R2)

> **`required_acr_min="2"` (step-up MFA / AAL2) требуется ТОГДА И ТОЛЬКО ТОГДА, когда операция:**
> **(1)** **чеканит / уничтожает credential** (bearer-токен, SA-ключ); **или**
> **(2)** **создаёт / изменяет / снимает privilege-grant ЛИБО живой authorization-policy-артефакт,
> через который grant резолвится** (binding, group-membership, role-policy, condition) — т.е.
> **немедленно меняет действующую привилегию какого-то существующего субъекта, НЕЗАВИСИМО ОТ ДОМЕНА**;
> **или** **(3)** **необратимо уничтожает tenancy-root** (account/project — cascade + deletion-protection).
> Всё остальное non-exempt — routine `required_acr_min="1"` (нормальная аутентификация, AAL1).

Это по-прежнему модель **RFC 9470 (OAuth 2.0 Step-Up Authentication Challenge) §1** (step-up —
carved-out исключение для sensitive operations, вызываемое сервером через challenge) и **NIST SP
800-63B (Authenticator Assurance Levels)** (AAL повышают для операций повышенного риска — изменение
аутентификаторов/привилегий, — а не для рутинного доступа). **R2-исправление root-дефекта:** принцип
применяется к **ПОЛНОЙ grant-поверхности**, а не только к iam. Privilege-grant существует и в
compute-домене (`*Service/SetAccessBindings` / `UpdateAccessBindings` привязывают subject→role на
compute-ресурсе — эффект идентичен iam-binding'у) → прежний инвариант «no non-iam RPC несёт `"2"`»
был **неверен** и заменён.

**Дискриминатор границы (author-inert vs mutate-live):** *создание* authz-артефакта, который сам по
себе **никому ничего не даёт** (роль без держателей, condition без ссылающихся binding'ов, пустая
группа) — **routine**; *создание живого grant'а* (AccessBinding/Create), *изменение/снятие живого
артефакта* (Role/Update·Delete, Condition/Update·Delete), либо *привязка/членство* (Set/UpdateAccessBindings,
Group/AddMember·RemoveMember) — **sensitive**. Понижение до AAL1 **не** ослабляет authz: routine-RPC
по-прежнему проходит authN + FGA relation-`Check` (не трогается) + scope_extractor; снимается **только**
требование assurance-level `>=2` на posture-neutral операциях.

---

## Реальность каталога (ground-truth, сверено с кодом 2026-07-22 — определяет scope)

Сверено с обеими embedded-копиями: `gateway/internal/middleware/embed/permission_catalog.json` и
`services/iam/internal/apps/kacho/seed/embedded/permission_catalog.json`.

| Величина | Сейчас | End-state (после рефайнмента) |
|---|---|---|
| Всего RPC-записей | **438** | **438** |
| `required_acr_min = "2"` | **372** | **41** (см. SENSITIVE-SET) |
| `required_acr_min = "1"` | 0 (не используется явно) | **332** (283 non-iam + 49 iam понижаются) |
| `required_acr_min = ""` (нет требования) | **66** | **65** (`AccessBindingService/Create` уходит из `""` в `"2"`) |
| `permission = "<exempt>"` (orthogonal) | 66 | **66** (не меняется; Create остаётся exempt-by-permission, но теперь acr=`"2"`) |
| Обе embedded-копии byte-identical | да | да (CI-гейт `permission-catalog-check`) |

Проверка: 41 + 332 + 65 = 438. Из 372 текущих `"2"`: 40 остаются `"2"`, 332 понижаются до `"1"`.
`AccessBindingService/Create` GAINS `"2"` (переходит из 66-набора `""`), поэтому `""`-набор 66→65.
(`GroupService/Delete` был `"2"` и **остаётся** `"2"` — под-включён R3/B-2, поэтому «остаются `"2"`» 39→40.)
`permission`-поле и `required_acr_min`-поле **ортогональны** (verified в generator `extractEntry`:
exempt-RPC сохраняет явный `required_acr_min`, а step-up-gate ключуется на FQN+acr, не на scope) —
поэтому «exempt-permission + acr=2» — валидная комбинация (см. B1).

> **Важно для ревьюера:** каталог включает крупную redesigned-поверхность compute (`DiskPlacementGroup`/
> `GpuCluster`/`HostGroup`/`Filesystem`/`ReservedInstancePool`/`instancegroup`/`MachineType`/`HostType`/
> `Maintenance`/`SnapshotSchedule`) и кросс-доменные `Internal*`-admin-сервисы. Из них **22 compute
> grant-verb'а** (`Set/UpdateAccessBindings`) **остаются sensitive** (они и есть non-iam grant-поверхность,
> опровергающая старый инвариант); **42 non-iam `Internal*`-admin** RPC понижаются до `"1"` (B5).

---

## SENSITIVE-SET — держим `acr>=2` (ровно 41 RPC; grant-поверхность + credential + tenancy-root)

Матрица по категориям. Все verified в каталоге; все currently-`"2"` **кроме**
`AccessBindingService/Create` (currently exempt/`""` → GAINS `"2"`).

### A — CREDENTIAL mint/destroy (4; классический step-up, RFC 9470 §1)

| RPC | Обоснование |
|---|---|
| `kacho.cloud.iam.v1.UserTokenService/Issue` | чеканит долгоживущий user-credential (bearer-токен) |
| `kacho.cloud.iam.v1.UserTokenService/Revoke` | уничтожает credential (lockout/anti-forensics-риск) |
| `kacho.cloud.iam.v1.SAKeyService/Issue` | чеканит SA-key (long-lived machine-credential) |
| `kacho.cloud.iam.v1.SAKeyService/Revoke` | уничтожает SA-key |

### B — IAM BINDING grant (4; privilege-write)

| RPC | Обоснование |
|---|---|
| `kacho.cloud.iam.v1.AccessBindingService/Create` | **создаёт живой grant** subject→role (см. B1: acr=2 ADDED, permission остаётся `<exempt>`, **net-strengthening**) |
| `kacho.cloud.iam.v1.AccessBindingService/Update` | изменяет привязку привилегии |
| `kacho.cloud.iam.v1.AccessBindingService/Delete` | снимает привязку привилегии |
| `kacho.cloud.iam.v1.AccessBindingService/Revoke` | отзывает привязку привилегии |

### C — COMPUTE per-resource grant (22; per-resource IAM policy, эффект = iam-binding, non-iam!)

`{Disk, DiskPlacementGroup, Filesystem, GpuCluster, HostGroup, Image, Instance, PlacementGroup,
SnapshotSchedule, Snapshot}Service/{SetAccessBindings, UpdateAccessBindings}` (20) +
`instancegroup.InstanceGroupService/{SetAccessBindings, UpdateAccessBindings}` (2) = **22**.
Все `kacho.cloud.compute.v1.*`. Обоснование: привязывают `subject→role` на compute-ресурсе
(request `access.SetAccessBindingsRequest{AccessBinding{role_id, subject}, AccessBindingDelta{ADD/REMOVE}}`)
— per-resource IAM policy grant, эффект **идентичен** iam-binding'у. Verified: все 22 currently-`"2"`,
никаких `Set/UpdateAccessBindings` вне compute нет (только эти 22 + iam AccessBindingService).

### D — GROUP membership grant + group destroy (3)

| RPC | Обоснование |
|---|---|
| `kacho.cloud.iam.v1.GroupService/AddMember` | добавляет субъекта в группу → материализует привилегии всех binding'ов группы для нового члена |
| `kacho.cloud.iam.v1.GroupService/RemoveMember` | снимает членство → отзыв действующей привилегии |
| `kacho.cloud.iam.v1.GroupService/Delete` | **revoke-по-всем** (R3/B-2): delete НЕ гейтится на пустоту группы — cascade `group_members` (снимает всех членов) + cleanup group-targeted `AccessBinding.subject_id` (verified `api/group/delete.go`) → одномоментно снимает материализованную привилегию у **каждого** члена связанной группы. Строго impactful-нее `RemoveMember`; та же revoke-по-всем destructive-семантика, что `RoleService/Delete` (E) |

### E — ROLE policy mutation (2)

| RPC | Обоснование |
|---|---|
| `kacho.cloud.iam.v1.RoleService/Update` | меняет набор permission'ов роли → немедленно меняет привилегию **всех держателей** |
| `kacho.cloud.iam.v1.RoleService/Delete` | снимает policy роли у **всех держателей** (revoke-по-всем — **destructive**, см. B3) |

### F — CONDITION policy mutation (2)

| RPC | Обоснование |
|---|---|
| `kacho.cloud.iam.v1.ConditionsService/Update` | меняет живое ABAC-условие, через которое резолвятся binding'и → меняет effective-доступ |
| `kacho.cloud.iam.v1.ConditionsService/Delete` | снимает живое условие → меняет effective-доступ ссылающихся binding'ов |

### G — CLUSTER-ADMIN grant (2)

| RPC | Обоснование |
|---|---|
| `kacho.cloud.iam.v1.InternalClusterService/GrantAdmin` | **эскалация до cluster-admin — высшая привилегия платформы** |
| `kacho.cloud.iam.v1.InternalClusterService/RevokeAdmin` | снятие cluster-admin |

### H — TENANCY-ROOT destroy (2; необратимо, cascade, deletion-protected)

| RPC | Обоснование |
|---|---|
| `kacho.cloud.iam.v1.AccountService/Delete` | необратимое уничтожение tenancy-root (account) с каскадом |
| `kacho.cloud.iam.v1.ProjectService/Delete` | необратимое уничтожение tenancy-root (project) с каскадом |

**Итого 4+4+22+3+2+2+2+2 = 41.** Из них 40 несут реальный `permission` (22 compute grant + 18 iam);
41-я — `AccessBindingService/Create` (permission=`<exempt>`, acr=`"2"`). **Инвариант allowlist'а:**
ровно этот набор из 41 FQN несёт `"2"`; всё остальное non-exempt — `"1"`.

---

## ROUTINE-SET — понижаем до `acr="1"` (332 RPC = 283 non-iam + 49 iam)

Определяется как **дополнение**: `{все non-exempt RPC} \ {41 sensitive}`. Представительные категории:

1. **ВСЕ vpc / compute / storage / nlb / registry / geo resource-RPC, НЕ являющиеся grant-verb'ами** —
   `Get`/`List`/`Create`/`Update`/`Delete` + `:verb`-actions (`attach`/`detach`/`start`/`stop`/
   `addCidrBlocks`/`addRoutes`/`relocate`/`move`/`updateRules`/…) + **per-resource `ListAccessBindings`
   (read!)** — 241 public + 42 кросс-доменных `Internal*`-admin (B5) = 283 non-iam. *(compute
   `Set/UpdateAccessBindings` — НЕ здесь: они sensitive, категория C.)*
2. **iam READS / authz-primitives:** `UserTokenService/List`, `SAKeyService/List`, все
   `AccessBindingService` reads (`Get`/`List`/`ListByScope`/`ListBySubject`/`ListSubjectPrivileges`/
   `ListAssignableRoles`/`ListByRole`/`ExpandAccess`/`ListByAccount`/`ListOperations`),
   `AccountService/{Get,ListOperations,ListAllOperations}`, `ProjectService/{Get,ListOperations}`,
   `AuthorizeService/*` (`Check`/`BatchCheck`/`ListObjects`/`ListSubjects`/`ExpandRelations` —
   service decision-primitives), `InternalClusterService/{Get,ListAdmins}`,
   `InternalOperationsService/ListIamOperations` **(iam-домен, read — routine)**.
3. **iam NON-DESTRUCTIVE / author-inert lifecycle:** `AccountService/Update`,
   `ProjectService/{Create,Update}`, `RoleService/{Create,ListOperations}` **(Create — author-inert, B6;
   Update/Delete — sensitive, E)**, `GroupService/{Create,ListMembers,ListOperations}` **(Create —
   author-inert, B6; AddMember/RemoveMember/Delete — sensitive, D; Delete под-включён R3/B-2)**, `ServiceAccountService/{Create,Update,
   Delete,Get,ListOperations}` **(Delete — routine, B3)**, `UserService/{Get,Update,Delete,Invite,
   ListOperations}` **(Delete — routine, B3)**, `ConditionsService/{Create,Get,List,Evaluate}`
   **(Create — author-inert, B6; Update/Delete — sensitive, F)**.

Из 332: 283 non-iam + 49 iam (verified; iam-routine 50 → 49 — `GroupService/Delete` ушёл в sensitive R3/B-2).
**Наблюдаемый эффект:** user-токен с `acr="1"` проходит
step-up-gate на этих RPC и далее подчиняется **неизменному** FGA relation-`Check` + scope_extractor.

---

## Boundary-решения (ратифицировать явно — ревьюеры этого требовали)

**B1 — `AccessBindingService/Create`: exempt-permission + acr=`"2"` (ортогональные поля) → NET-STRENGTHENING.**
Currently: `permission="<exempt>"`, **нет** `required_acr_min`-ключа. `permission` и `required_acr_min` —
**ортогональные** поля каталога (verified в generator `extractEntry`; step-up-gate ключуется на FQN+acr,
не на scope). Рефайнмент **ДОБАВЛЯЕТ** `option (kacho.iam.authz.v1.required_acr_min)="2"`, оставляя
`permission="<exempt>"` → **StepUpGate энфорсит acr=2**, FGA project-scope-`Check` остаётся **skipped**
(in-handler ReBAC не тронут). Это **чистое усиление**: create-binding — primary grant-primitive — был
**un-gated по acr** (bypass «create a new binding вместо Update/Delete/Revoke» обходил их step-up).
Совпадает с исходным intent'ом задачи (Create числился sensitive). FGA-authz **не трогается** — только
acr-floor. *(Инверсия прежней R1-формулировки «Create остаётся exempt без step-up» — reviewer C2.)*

**B2 — `GroupService/AddMember`, `RemoveMember` & `Delete` → SENSITIVE (категория D).** Currently `"2"` → **остаются**
`"2"`. R2-исправление R1-ошибки: членство в группе, у которой есть binding'и, немедленно материализует/
снимает действующую привилегию члена — это privilege-grant, а не posture-neutral lifecycle. *(Прежняя
R1-логика «membership даёт nothing без binding» неверна для непустой группы — reviewer V1.)* **R3/B-2
(system-design round-2):** `GroupService/Delete` — **под-включён в sensitive** (тот же bucket D). Delete НЕ
гейтится на пустоту группы: cascade `group_members` (снимает **всех** членов) + cleanup group-targeted
`AccessBinding.subject_id` (`DELETE … WHERE NOT EXISTS`) — verified `services/iam/internal/apps/kacho/api/group/delete.go`.
Значит delete связанной непустой группы = **одномоментный revoke-по-всем** материализованных привилегий её
членов — строго impactful-нее `RemoveMember` и та же destructive-семантика, что держит sensitive
`RoleService/Delete` (E) и `ConditionsService/Delete` (F). AAL1-only/phished user НЕ должен уметь стереть
доступ целой группы без step-up. Прежняя (R2) complement-логика молча понижала его до `"1"` — исправлено.

**B3 — `ServiceAccountService/Delete` + `UserService/Delete` → ROUTINE.** Currently `"2"` → понижаются `"1"`.
Обоснование: удаление субъекта — не grant (не выдаёт/не изменяет привилегию) и не tenancy-root-cascade
(в отличие от account/project). *Caveat (ратифицировать): lockout-симметрия — `UserTokenService/Revoke`
(credential-destroy) остаётся sensitive (A); удаление самого субъекта — routine. Если ревью сочтёт
subject-delete эквивалентным credential-destroy по lockout-риску — перенести две RPC в sensitive (набор
станет 42). Текущее решение: subject-delete ≠ credential/grant/tenancy-root → routine.* **`RoleService/Delete`
здесь НЕТ** — она **sensitive** (E): снимает policy роли у **всех держателей** = revoke-по-всем.

**B4 — cluster-admin: Grant/Revoke = sensitive (G); Get/ListAdmins = routine.** Currently все четыре `"2"`.
`GrantAdmin`/`RevokeAdmin` — эскалация/деэскалация высшей привилегии (остаются `"2"`). `Get`/`ListAdmins` —
чтения → `"1"`. Регрессия #7 (SEC-ACR-14) фиксирует, что iam :9091 acr_floor сохраняет `"2"` на `GrantAdmin`
и понижает `Get`.

**B5 — кросс-доменные non-iam `Internal*`-admin (42) → ROUTINE.** Currently `"2"` → понижаются `"1"`. Полный
список (verified, 42): `compute.InternalDiskTypeService/*` (3), `compute.InternalMachineTypeService/*` (3),
`geo.InternalRegionService/*` (4), `geo.InternalZoneService/*` (4), `loadbalancer.InternalLoadBalancerAnnounceService/*`
(2), `registry.InternalRegistryService/*` (2), `storage.InternalDiskTypeService/*` (3),
`storage.InternalImageService/GetInternal` (1), `storage.InternalVolumeService/*` (4),
`vpc.InternalAddressPoolService/*` (11), `vpc.InternalNetworkInterfaceService/*` (3),
`vpc.InternalNetworkService/*` (2). Обоснование: admin-curated platform-catalog / data-plane-wiring мутации —
**не** credential/privilege-grant/tenancy-root, posture-neutral; остаются под `system_admin`/`system_viewer`
ReBAC + mTLS + (для module-SA caller'ов) O-1 acr-exemption. **Оба ревьюера ратифицировали.** *(NB:
`iam.InternalOperationsService/ListIamOperations` — iam-домен, **read** → в iam-reads routine bucket, не здесь.)*
*(NB2 (acceptance-reviewer): прочие **13** non-iam `Internal*` RPC — `vpc.InternalAddressService/*` (8),
`*.InternalResourceLifecycle*` (3), `*.InternalWatch*` (2) — уже `permission="<exempt>"`/acr=`""`, остаются в
65-`""`-bucket и **не** понижаются; поэтому 42 ≠ 55 non-iam Internal*. I1 complement-based → инвариант робастен независимо.)*

**B6 (НОВОЕ) — `RoleService/Create`, `ConditionsService/Create`, `GroupService/Create` → ROUTINE.** Currently
`"2"` → понижаются `"1"`. Обоснование (дискриминатор author-inert): создание authz-артефакта **инертно** —
роль без держателей, condition без ссылающихся binding'ов, пустая группа **никому ничего не дают**. Любой
путь, делающий такой артефакт действующим, проходит через **теперь-sensitive** grant-verb
(`AccessBinding/Create·Update`, `GroupService/AddMember`, compute `Set/UpdateAccessBindings`, `RoleService/Update`).
Контраст: `AccessBinding/Create` — **немедленно живой** grant → sensitive (B1). **Линия: author-inert-артефакт =
routine; mutate/remove-живой-артефакт или create-живого-grant'а = step-up.**

---

## Как энфорсится (mechanism — документируем точку, не реализацию)

Док описывает **наблюдаемое поведение** (HTTP-статус / gRPC-код + `WWW-Authenticate` + reach-backend на
public и :9091 путях). Фактическая цепочка (источник истины — код):

- **Аннотация (intent).** 332 routine-RPC получают **явный** `option (kacho.iam.authz.v1.required_acr_min)="1"`
  на методе; 40 sensitive-с-permission — явный `="2"` (17+1 iam с `GroupService/Delete` = 18 iam + 22 compute);
  `AccessBindingService/Create` — `="2"` **ADDED** при сохранённом `permission="<exempt>"` (B1). Greppable review-visible intent.
- **Fail-safe — уточнено (R2 V3, scope-исправлен R3/B-1).** Fail-closed-свойство даёт **НЕ** runtime-дефолт step-up-gate'а,
  а **два** слоя: **(a) generator default `"2"` — только для NON-EXEMPT RPC** — генератор выставляет **явную**
  запись `"2"` каждому **non-exempt** un-annotated RPC на gen-time, поэтому miss'ов в каталоге на практике нет;
  **(b) authz-completeness** — un-cataloged метод → `"no entry for method"` → `AUTHZ_DENIED` (security.md инвариант #4).
  **Сам step-up-слой fail-OPEN на genuine-miss:** `catalogPermissionLookup.Lookup` возвращает пустой
  `PermissionRequirement`, а `StepUpGate.Check` при `RequiredACRMin==""` **пропускает** (`if req.RequiredACRMin != ""`-guard).
  **R3/B-1 — граница exempt (verified `main.go` L296-299 early-return ДО default-injection L326-328):** для
  **exempt** un-annotated RPC генератор эмитит запись с **пустым** acr (НЕ `"2"`) → ни step-up-backstop (fail-open
  на пустом), ни authz-completeness (запись **есть**, FGA project-scope-`Check` для `<exempt>` намеренно skipped)
  **НЕ** срабатывают. Такой RPC защищён **только** authN + in-handler ReBAC + deliberate FGA-exempt-posture →
  **добавление нового exempt-RPC = high-scrutiny action**, требующий явного `required_acr_min` (как сделано для
  `AccessBindingService/Create`). V3-claim «net fail-closed двумя слоями» верен **для non-exempt**; для exempt —
  явно оговорён этот третий контур. Реализация **исправит вводящий-в-заблуждение godoc** `PermissionRequirement`
  (`stepup_gate.go`, «a missing entry implies the default requirement (ACR=2)» — противоречит коду; security.md #5).
  Понижение делается явным `"1"`, не удалением записи.
- **Ranking — уточнено (R2 O1, дополнено R3/B-3+B-4).** Gateway `StepUpGate` использует **локальный** `acrRank`
  (`stepup_gate.go`); iam `acr_floor` использует `grpcsrv.ACRSatisfies`/`ACRRank` (`pkg/grpcsrv/acr.go`) —
  **два раздельных** ranking-table'а, **functionally identical сегодня** (оба: `"3">"2">"1">"0"/""`, unknown→0).
  Не «shared». **R3/B-3 — три godoc-фикса (не два):** (1) `stepup_gate.go` `PermissionRequirement` (см. выше);
  (2) `acr_floor.go` (ошибочно называет ranking «SAME»); (3) **`pkg/grpcsrv/acr.go` — root-ложь** («the SHARED
  ACR ranking used by BOTH … so the two never drift» — неверно: gateway `StepUpGate` НЕ зовёт `grpcsrv.ACRRank`,
  держит свой `acrRank`; grpcsrv — source-of-truth **только** iam-стороны). **R3/B-4 — lock-тест усилен:**
  ассертит **не** совпадение rank-функций (недостаточно — не ловит дрейф wrapper'а `<`→`<=` или `!=""`-guard'а),
  а **идентичность enforcement-вердикта двух реальных entrypoint'ов** — gateway `StepUpGate.Check(token, req)` ↔
  iam `grpcsrv.ACRSatisfies(presented, required)` — над **полной матрицей** `{presented}×{required}` из
  `{"","0","1","2","3",<unknown>}` (incl. пустой `required`). Это запирает фактический pass/deny, а не только rank-таблицу.
- **Регенерация каталога.** `cd gateway && make permission-catalog-apply` перегенерирует
  `gateway/internal/middleware/embed/permission_catalog.json`; iam-копия
  `services/iam/internal/apps/kacho/seed/embedded/permission_catalog.json` синхронизируется **byte-identical**.
  CI-гейт `make permission-catalog-check` роняет сборку при staleness/дрейфе (security.md инвариант #4).
- **Рантайм-читатели (одно каталожное значение, два места):** gateway `StepUpGate.Check` +
  `dpop_http_middleware.go` (public/edge; недостаток → RFC 9470 `401` + `WWW-Authenticate: Bearer
  error="insufficient_user_authentication", acr_values="<min>"`; SA → exempt O-1); iam `authzguard` acr-floor
  (:9091, gateway-fronted; тот же исход, `PERMISSION_DENIED` + step-up-сигнал). Понижение каталожного
  значения понижает **оба** floor'а консистентно.
- **`mfa_max_age` — не трогается** (freshness-window остаётся как есть на sensitive-RPC).

---

## ACR-ранжирование (нормативно — для всех сценариев)

`"" / "0"` (anonymous) < `"1"` (password-only / AAL1) < `"2"` (MFA / AAL2) < `"3"` (hardware-bound / AAL3).
Неизвестное/отсутствующее значение → ранг 0 (fail-closed). Sensitive floor = `>=2`; routine floor = `>=1`.
Два раздельных, functionally-identical ranking-table'а (gateway `acrRank` / iam `grpcsrv.ACRRank`), с
lock-тестом на их совпадение (O1). SA-принципал (`kacho_principal_type=="service_account"`) — **exempt от
acr-floor целиком** (O-1), но по-прежнему подчиняется FGA-authz.

---

## Сценарии (Given-When-Then)

ID трассируются в имена lock-тестов (см. §Traceability). Prod-mode сценарии предполагают `production`
AuthN-mode + валидированный JWT (user) либо mTLS-verified peer (SA). Public/edge-путь — через api-gateway;
:9091-путь — internal-mux / прямой. «Проходит gate» = проходит step-up-floor и **далее** подчиняется
неизменному FGA relation-`Check` (не «получает доступ безусловно»).

---

### Группа 1 — Sensitive step-up ПРЕДОХРАНЁН / РАСШИРЕН (41-set)

#### SEC-ACR-01 — sensitive credential RPC + acr=1 → 401 step-up (регрессия #1, LOCK)

**ID:** SEC-ACR-01

**Given** prod-mode; `kacho.cloud.iam.v1.UserTokenService/Issue` несёт `required_acr_min="2"`
**And** user-JWT с `acr="1"` (password / AAL1); FGA-привилегия на issue присутствует (relation-Check прошёл бы)

**When** клиент вызывает `UserTokenService/Issue` (public-путь через gateway `StepUpGate`)

**Then** step-up-gate отклоняет **до backend**: HTTP `401`
  `WWW-Authenticate: Bearer error="insufficient_user_authentication", acr_values="2"` (RFC 9470)
**And** backend не вызван (token не выпущен; no side-effect)
**And** step-up на sensitive-RPC сохранён.

#### SEC-ACR-02 — sensitive RPC + acr=2 → проходит gate (регрессия #2, LOCK)

**ID:** SEC-ACR-02

**Given** prod-mode; `UserTokenService/Issue` = `"2"`; user-JWT `acr="2"` (MFA / AAL2)

**When** клиент вызывает `UserTokenService/Issue`

**Then** step-up-gate пропускает (`2>=2`) → доходит до backend → подчиняется неизменному FGA-`Check`
**And** edge: `acr="3"` тоже проходит (`3>=2`).

#### SEC-ACR-03 — полная 41-set матрица (A–H) + acr=1 → 401 (extension)

**ID:** SEC-ACR-03

**Given** prod-mode; user-JWT `acr="1"`

**When** клиент по очереди вызывает представителей каждой категории:
  - **A credential:** `UserTokenService/{Issue,Revoke}`, `SAKeyService/{Issue,Revoke}`
  - **B iam-binding:** `AccessBindingService/{Create,Update,Delete,Revoke}`
  - **C compute-grant:** `InstanceService/SetAccessBindings`, `DiskService/UpdateAccessBindings`, `instancegroup.InstanceGroupService/SetAccessBindings` (репрезентативно из 22)
  - **D group-membership + group-destroy:** `GroupService/{AddMember,RemoveMember,Delete}` (Delete — revoke-по-всем, R3/B-2)
  - **E role-policy:** `RoleService/{Update,Delete}`
  - **F condition-policy:** `ConditionsService/{Update,Delete}`
  - **G cluster-admin:** `InternalClusterService/{GrantAdmin,RevokeAdmin}`
  - **H tenancy-root:** `AccountService/Delete`, `ProjectService/Delete`

**Then** **каждый** → step-up-`401` `insufficient_user_authentication` + `acr_values="2"`, backend не вызван
**And** каждый c `acr="2"` (или `"3"`) → проходит gate.

#### SEC-ACR-04 — cross-domain COMPUTE grant + acr=1 → 401 (C1 LOCK — grant-поверхность non-iam)

**ID:** SEC-ACR-04

**Given** prod-mode; `kacho.cloud.compute.v1.InstanceService/SetAccessBindings` несёт `required_acr_min="2"`
**And** user-JWT `acr="1"`; caller имеет право на set-bindings (relation-Check прошёл бы)

**When** клиент вызывает `InstanceService/SetAccessBindings` (`POST /compute/v1/instances/{id}:setAccessBindings`)
  с payload `access.SetAccessBindingsRequest{AccessBinding{role_id, subject}, AccessBindingDelta{ADD}}`

**Then** step-up-gate отклоняет: HTTP `401` `insufficient_user_authentication` + `acr_values="2"`, backend не вызван
**And** это доказывает: privilege-grant в **compute**-домене — sensitive (принцип domain-agnostic);
  прежний инвариант «no non-iam RPC несёт `"2"`» опровергнут.

#### SEC-ACR-05 — GROUP membership grant + acr=1 → 401 (V1 LOCK)

**ID:** SEC-ACR-05

**Given** prod-mode; `GroupService/AddMember` = `"2"`; user-JWT `acr="1"`; группа имеет ≥1 binding

**When** клиент вызывает `GroupService/AddMember` (`POST /iam/v1/groups/{id}:addMember`)

**Then** step-up-`401` `acr_values="2"`, backend не вызван
**And** членство — privilege-grant (материализует привилегии binding'ов группы новому члену), не
  posture-neutral lifecycle (B2). То же для `RemoveMember`.
**And** `GroupService/Delete` (R3/B-2) — тоже `"2"`: delete связанной непустой группы = revoke-по-всем
  (cascade `group_members` + cleanup group-targeted `AccessBinding.subject_id`) → `acr=1` → `401`, backend не вызван;
  строго impactful-нее `RemoveMember`. `acr=2` → проходит gate.

#### SEC-ACR-06 — AccessBindingService/Create + acr=1 → 401, permission остаётся exempt (C2 LOCK — net-strengthening)

**ID:** SEC-ACR-06

**Given** prod-mode; после рефайнмента `AccessBindingService/Create` несёт `required_acr_min="2"` при
  `permission="<exempt>"` (acr ADDED, permission не тронут — B1); user-JWT `acr="1"`

**When** клиент вызывает `AccessBindingService/Create`

**Then** **StepUpGate отклоняет** (`1<2`): HTTP `401` `insufficient_user_authentication` + `acr_values="2"`,
  backend не вызван
**And** FGA project-scope-`Check` остаётся **skipped** (`permission="<exempt>"` не изменён) — in-handler
  ReBAC не тронут
**And** это **net-strengthening**: primary grant-primitive был un-gated по acr → закрыт «create-instead-of-Update»
  bypass. Никакая FGA-логика не менялась.

#### SEC-ACR-07 — ROLE/CONDITION policy-mutation + acr=1 → 401 (E/F LOCK)

**ID:** SEC-ACR-07

**Given** prod-mode; user-JWT `acr="1"`; `RoleService/Delete`, `ConditionsService/Delete` = `"2"`

**When** клиент вызывает `RoleService/Delete` (роль с держателями) и `ConditionsService/Delete`
  (condition, на который ссылаются binding'и)

**Then** каждый → step-up-`401`, backend не вызван
**And** обоснование: `Role/Delete` снимает policy у **всех держателей** (revoke-по-всем); `Condition/Delete`
  меняет effective-доступ ссылающихся binding'ов — оба меняют действующую привилегию (E/F).

---

### Группа 2 — Routine РАЗБЛОКИРОВАН (позитив — суть фикса)

#### SEC-ACR-08 — routine resource-create + acr=1 → 200 (регрессия #3, LOCK — UNBLOCK)

**ID:** SEC-ACR-08

**Given** prod-mode; после рефайнмента `kacho.cloud.vpc.v1.NetworkService/Create` несёт `required_acr_min="1"`
  (было `"2"`); user-JWT `acr="1"`; caller имеет FGA `editor` на project-scope

**When** клиент вызывает `NetworkService/Create` (`POST /vpc/v1/networks`)

**Then** step-up-gate **пропускает** (`1>=1`) — **ранее `401`**, теперь UNBLOCKED
**And** запрос проходит FGA relation-`Check` (не тронут) → мутация возвращает `Operation` (async) → `200`
**And** resource-create — **НЕ** grant (создание сети никому не выдаёт привилегию) → routine; разблокирует
  production-newman user-subject потоки (`#59`).

#### SEC-ACR-09 — routine reads / lifecycle / authz-primitives / author-inert + acr=1 → проходят (extension)

**ID:** SEC-ACR-09

**Given** prod-mode; user-JWT `acr="1"`

**When** клиент вызывает представителей routine-set:
  - **read:** `UserTokenService/List`, `AccessBindingService/ListBySubject`, `AuthorizeService/Check`,
    `AccountService/Get`, `ProjectService/Get`, `InstanceService/ListAccessBindings` (per-resource **read**),
    `InternalOperationsService/ListIamOperations`
  - **lifecycle:** `ProjectService/Create`, `AccountService/Update`, `ServiceAccountService/Create`, `UserService/Update`
  - **author-inert (B6):** `RoleService/Create`, `ConditionsService/Create`, `GroupService/Create`
  - **resource `:verb`:** `InstanceService/Start`, `InstanceService/AttachDisk`, `SubnetService/AddCidrBlocks`

**Then** **каждый** проходит step-up-gate (`1>=1`) и подчиняется своему обычному FGA-`Check`
**And** author-inert-артефакт (роль без держателей / condition без ссылок / пустая группа) — routine (B6):
  доступ конферится только через sensitive grant-verb; per-resource `ListAccessBindings` — read → routine.

---

### Группа 3 — AAL1-floor держится (routine ≠ anonymous)

#### SEC-ACR-10 — routine RPC + acr=0 → 401 (регрессия #4, LOCK)

**ID:** SEC-ACR-10

**Given** prod-mode; `NetworkService/Create` = `"1"`; принципал с `acr="0"` (нет интерактивной auth)

**When** клиент вызывает `NetworkService/Create`

**Then** step-up-gate отклоняет (`0<1`): HTTP `401` `insufficient_user_authentication` + `acr_values="1"`
**And** routine ≠ anonymous: понижение до `"1"` не открывает anonymous-доступ (security.md fail-closed).

#### SEC-ACR-11 — отсутствующий/неизвестный acr → ранг 0 → 401 (edge, fail-closed)

**ID:** SEC-ACR-11

**Given** prod-mode; токен без `acr`-claim (или с неизвестным значением)

**When** клиент вызывает routine RPC (`"1"`) и sensitive RPC (`"2"`)

**Then** acr → ранг 0 → routine `0<1` → `401`; sensitive `0<2` → `401` (fail-closed на обоих floor'ах).

---

### Группа 4 — SA-exemption НЕ сломан

#### SEC-ACR-12 — SA-принципал (acr-exempt O-1) проходит sensitive и routine (регрессия #5, LOCK)

**ID:** SEC-ACR-12

**Given** prod-mode; principal — service-account (`kacho_principal_type=="service_account"`), без acr/MFA

**When** SA вызывает (а) sensitive `UserTokenService/Issue` (напр. bootstrap-admin SA, `#58`/`#60`) и
  (б) routine `NetworkService/Create`

**Then** **оба** проходят step-up-gate **независимо** от acr — SA acr-EXEMPT (O-1, `isServiceAccountPrincipal`
  → pass; parity gateway `StepUpGate` ↔ iam `acr_floor`)
**And** exemption **узкий**: `user`-принципал НИКОГДА не exempt (mechanism-lock)
**And** exemption снимает **только** assurance-floor — downstream FGA-`Check` исполняется (SA без привязки → FGA-deny).

---

### Группа 5 — инвариант каталога + floor-паритет + fail-safe + ranking

#### SEC-ACR-13 — catalog invariant: ровно 41 named FQN несут "2", комплемент !="2" (регрессия #6, LOCK)

**ID:** SEC-ACR-13

**Given** регенерированный каталог (обе embedded-копии)

**When** тест перечисляет все записи

**Then** **ровно** множество {41 названных FQN} несёт `required_acr_min="2"` — не больше, не меньше (enumerate)
**And** **комплемент несёт `!="2"`**, в частности (явные regression-точки): `RoleService/Create`,
  `ConditionsService/Create`, `GroupService/Create` (B6 → `"1"`); все per-resource `*/ListAccessBindings`
  (reads → `"1"`); `ServiceAccountService/Delete`, `UserService/Delete` (B3 → `"1"`); 42 non-iam
  `Internal*`-admin (B5 → `"1"`); `NetworkService/Create` (`"1"`)
**And** `GroupService/Delete` **несёт `"2"`** (R3/B-2 — sensitive, категория D), а `GroupService/{Create,ListMembers,ListOperations}` — `!="2"`
**And** `AccessBindingService/Create` несёт `"2"` при `permission="<exempt>"` (B1)
**And** обе embedded-копии **byte-identical**; `permission`-поле не изменено ни у одной записи (только acr).

#### SEC-ACR-14 — iam :9091 acr_floor паритет (регрессия #7, LOCK)

**ID:** SEC-ACR-14

**Given** prod-mode iam с mTLS-verified gateway→iam ребром; gateway-fronted acr-floor (5.4)

**When** api-gateway вызывает на :9091: `InternalClusterService/GrantAdmin` (остаётся `"2"`) c `x-kacho-acr="1"`;
  `InternalClusterService/Get` (понижен до `"1"`) c `x-kacho-acr="1"`

**Then** `GrantAdmin` → acr_floor **отклоняет** (`1<2`) `PERMISSION_DENIED` + step-up-сигнал, handler не вызван
**And** `Get` → acr_floor **пропускает** (`1>=1`) → доходит до handler
**And** floor читает то же каталожное значение, что gateway.

#### SEC-ACR-15 — fail-safe: generator default "2" (non-exempt) + authz-completeness (НЕ runtime step-up-default) (V3 LOCK, R3/B-1)

**ID:** SEC-ACR-15

**Given** гипотетический будущий **non-exempt** RPC **без** явной `required_acr_min`-аннотации

**When** каталог регенерируется, затем этот RPC вызывается

**Then** **генератор** выставляет ему явную запись `"2"` (fail-safe на gen-time → miss'ов в каталоге нет) —
  **только для non-exempt** (R3/B-1)
**And** если запись всё же отсутствует в рантайме — **step-up-слой fail-OPEN** (`StepUpGate.Check` при
  `RequiredACRMin==""` пропускает), но **authz-completeness** слой отвергает un-cataloged метод
  (`"no entry for method"` → `AUTHZ_DENIED`) — **net fail-closed** держится этими двумя слоями, не
  step-up-дефолтом
**And** **exempt-граница (R3/B-1):** гипотетический будущий **exempt** un-annotated RPC получает от генератора
  запись с **пустым** acr (early-return ДО default-injection, verified `main.go` L296-299) → step-up fail-open
  (пустой) **и** authz-completeness не срабатывает (запись есть, FGA scope-Check для `<exempt>` skipped) →
  защищён **только** authN + in-handler ReBAC + deliberate FGA-exempt-posture. Тест ассертит: exempt-un-annotated
  → acr пуст (не `"2"`); non-exempt-un-annotated → acr `"2"`. Добавление нового exempt-RPC = high-scrutiny.
**And** реализация исправляет вводящий-в-заблуждение godoc `PermissionRequirement` (security.md #5,
  doc-truthfulness) — комментарий утверждал «missing → ACR=2», код пропускает на пустом.

#### SEC-ACR-16 — verdict agreement: реальные entrypoint'ы StepUpGate.Check ≡ grpcsrv.ACRSatisfies (O1 LOCK, R3/B-4)

**ID:** SEC-ACR-16

**Given** gateway `StepUpGate.Check` инлайнит `if req.RequiredACRMin != ""`-guard + строгий `<` (`stepup_gate.go`);
  iam-floor зовёт `grpcsrv.ACRSatisfies` (guard `ACRRank(required)==0` покрывает `""` и `"0"`, + `>=`)

**When** lock-тест прогоняет **полную матрицу** `{presented}×{required}` из `{"","0","1","2","3",<unknown-value>}`
  через **оба реальных enforcement-entrypoint'а** (не только rank-функции)

**Then** оба дают **идентичный pass/deny-вердикт** на каждой клетке матрицы (включая `required=""` → обе пропускают;
  `required="2"`,`presented="1"` → обе deny) — гарантия отсутствия дрейфа **enforcement-логики**, а не только
  rank-таблиц (R3/B-4: rank-only тест не ловит дрейф wrapper'а `<`→`<=` или `!=""`-guard'а)
**And** реализация исправляет **три** godoc (R3/B-3): `stepup_gate.go` `PermissionRequirement`, `acr_floor.go`
  («SAME»), и `pkg/grpcsrv/acr.go` (root-ложь «SHARED … used by BOTH … never drift» — grpcsrv это
  source-of-truth **только** iam-стороны; gateway держит свой `acrRank`) — doc-truthfulness (security.md #5).

---

### Группа 6 — boundary-ратификация (B3/B5/B6)

#### SEC-ACR-17 — B3: SA/User Delete → routine, acr=1 проходит (lockout-caveat)

**ID:** SEC-ACR-17

**Given** prod-mode; user-JWT `acr="1"`; после рефайнмента `ServiceAccountService/Delete`, `UserService/Delete` = `"1"`

**When** клиент вызывает каждый (при наличии FGA-права)

**Then** каждый проходит step-up-gate (`1>=1`) → подчиняется FGA-`Check`
**And** subject-delete — не grant/credential/tenancy-root-cascade → routine; credential-destroy для субъекта —
  `UserTokenService/Revoke`/`SAKeyService/Revoke` (sensitive, A) — lockout-симметрия сохранена там.

#### SEC-ACR-18 — B5: кросс-доменная non-iam Internal*-admin → routine, ReBAC держит

**ID:** SEC-ACR-18

**Given** prod-mode; после рефайнмента `InternalRegionService/Create`, `InternalAddressPoolService/AddCidrBlocks`,
  `InternalMachineTypeService/Create` = `"1"` (было `"2"`)

**When** (а) user-admin c `acr="1"` вызывает через internal-mux; (б) module-SA вызывает peer-RPC

**Then** (а) проходит step-up-gate (`1>=1`), но по-прежнему требует `system_admin` FGA relation (не тронут) →
  без admin-привязки FGA-deny
**And** (б) module-SA acr-exempt (O-1), проходит штатный mTLS + relation-gate
**And** step-up MFA к platform-catalog-мутации не предъявляется (posture-neutral, B5); authz не ослаблен.

#### SEC-ACR-19 — B6: author-inert create → routine; контраст с AccessBinding/Create sensitive

**ID:** SEC-ACR-19

**Given** prod-mode; user-JWT `acr="1"`; `RoleService/Create`, `ConditionsService/Create`, `GroupService/Create` = `"1"`

**When** клиент вызывает каждый

**Then** каждый проходит step-up-gate (`1>=1`) — создание инертного артефакта (роль без держателей / condition
  без ссылок / пустая группа) никому не конферит доступ
**And** контраст: `AccessBinding/Create` (немедленно живой grant) → **401** при `acr=1` (SEC-ACR-06) — линия
  «author-inert = routine; create-живого-grant = step-up» заперта.

---

### Группа 7 — сквозной e2e (prod-mode стенд)

#### SEC-ACR-20 — e2e happy: production-newman user-subject поток разблокирован

**ID:** SEC-ACR-20

**Given** развёрнутый prod-mode стек; user получает JWT c `acr="1"` (штатный non-MFA login)

**When** user прогоняет полный resource-lifecycle: `NetworkService/Create` → `SubnetService/Create` →
  `InstanceService/Create` → `Start`/`AttachDisk` → `List`/`Get` → `Delete` (+ iam reads/lifecycle:
  `ProjectService/Create`, `AccessBindingService/ListBySubject`, `RoleService/Create`)

**Then** **все** проходят step-up-gate (routine `"1"`) и подчиняются FGA-authz → поток зелёный
**And** `#59` Phase C production-newman разблокирован для user-subject.

#### SEC-ACR-21 — e2e negative: sensitive step-up сохранён (iam + compute grant)

**ID:** SEC-ACR-21

**Given** тот же стек; тот же user-JWT `acr="1"`

**When** user вызывает (а) `UserTokenService/Issue` (iam credential) и (б) `InstanceService/SetAccessBindings`
  (compute grant, `POST /compute/v1/instances/{id}:setAccessBindings`)

**Then** оба → HTTP `401` `insufficient_user_authentication` + `acr_values="2"` (RFC 9470 → UI инициирует MFA-ceremony)
**And** после step-up до `acr="2"` оба проходят — step-up точечно живой на **полной grant-поверхности**
  (iam **и** compute), не blanket.

---

## Инварианты (MUST hold — для ревьюера)

| # | Инвариант | Сценарии |
|---|---|---|
| I1 | Ровно 41 named FQN несут `required_acr_min="2"` (grant-поверхность + credential + tenancy-root, domain-agnostic, incl. `GroupService/Delete` revoke-по-всем R3/B-2); комплемент несёт `!="2"`. | SEC-ACR-13 |
| I2 | Обе embedded-копии каталога byte-identical; `permission`-поле не изменено (только acr); CI-гейт `permission-catalog-check` зелёный. | SEC-ACR-13 |
| I3 | Step-up ПРЕДОХРАНЁН на всех 41 sensitive (iam **и** compute grant): `acr<2` → `401` + `acr_values="2"`, backend не вызван. | SEC-ACR-01, -03, -04, -05, -07, -21 |
| I4 | `AccessBindingService/Create` — net-strengthening: acr=`"2"` ADDED, `permission="<exempt>"` не тронут, FGA scope-Check skipped. | SEC-ACR-06 |
| I5 | Routine RPC разблокирован для `acr="1"` (проходит gate; ранее `401`); author-inert create — routine (B6). | SEC-ACR-08, -09, -19, -20 |
| I6 | AAL1-floor держится: `acr="0"`/отсутствует → `401` на routine (routine ≠ anonymous, fail-closed). | SEC-ACR-10, -11 |
| I7 | SA-exemption (O-1) не сломан: SA проходит sensitive и routine независимо от acr; user НИКОГДА не exempt. | SEC-ACR-12 |
| I8 | iam :9091 acr_floor паритет: sensitive floored на `"2"`, routine понижен на `"1"`; два реальных enforcement-entrypoint'а дают идентичный вердикт над полной матрицей (verdict-lock, R3/B-4). | SEC-ACR-14, -16 |
| I9 | Fail-closed даёт generator-default `"2"` (**non-exempt**) + authz-completeness (**НЕ** runtime step-up-default; тот fail-open на пустом); exempt-un-annotated → пустой acr, защищён authN+ReBAC+FGA-exempt-posture (R3/B-1); три misleading godoc исправлены (R3/B-3). | SEC-ACR-15, -16 |
| I10 | FGA relation-authz НЕ тронут: понижение acr не даёт ни одной привилегии (downstream `Check` тот же). | SEC-ACR-06, -08, -09, -18 |
| I11 | Boundary B1–B6 ратифицированы и заперты (Create-strengthen, membership+group-delete-sensitive, SA/User-Delete-routine, cluster-reads-routine, Internal*-admin-routine, author-inert-routine). | SEC-ACR-06, -05, -17, -14, -18, -19 |

---

## Out-of-scope (явно вне scope)

- **FGA relation-authz — НЕ трогается.** Ни один `required_relation` / scope_extractor / FGA-модель /
  `permission="<exempt>"`-статус не меняется. Меняются **только** `required_acr_min`-значения.
- **SA-exemption (O-1) — НЕ трогается.** `isServiceAccountPrincipal` / `kacho_principal_type` в обоих gate'ах
  остаётся as-is (запирается SEC-ACR-12, не переписывается).
- **ACR-minting / IdP-config — Phase C, вне scope.** Как IdP чеканит `acr="2"` (passkey/UV, DPoP,
  hardware-bound), issuer-config, step-up-ceremony UI — отдельная работа. Здесь — только **потребление**
  `acr`-claim floor'ом.
- **`mfa_max_age` — не меняется.** Freshness-window на sensitive-RPC остаётся как в текущем каталоге.
- **Механизм acr-floor (5.4) — не меняется.** gateway `StepUpGate` / iam `acr_floor` / metadata-plumbing
  `x-kacho-acr` / caller-policy — as-is; меняется только **набор RPC** (через каталожные значения) + правки
  godoc (doc-truthfulness) + новый ranking-agreement lock-тест.
- **Никакого нового proto-message / RPC / схемы БД.** Меняются только method-level option-аннотации + regen.

---

## Тест-план (строгий TDD — RED до GREEN, ban #12; regression на уровне обсёрвабла)

Lock-тесты авторятся и прогоняются **RED до** правки каталога; пара RED→GREEN в PR. Security-refinement
запирается на **наблюдаемом поведении** (HTTP-статус + `WWW-Authenticate`-заголовок + reach-backend / gRPC-код +
byte-identity), не только на значении (testing.md §regression-lock).

### Уровень 1 — gateway `StepUpGate` unit (table-driven, CI-validatable)
- **SEC-ACR-01/02/03** (41-set × acr): для каждого из 41 FQN — `acr∈{0,1}` → `ErrStepUpRequired` → `401` +
  `acr_values="2"`; `acr∈{2,3}` → pass. Проверяется **сообщение/заголовок**, не только код.
- **SEC-ACR-04** (C1 compute-grant), **SEC-ACR-05** (V1 membership + R3/B-2 `GroupService/Delete`), **SEC-ACR-06**
  (C2 Create: acr=2 deny + permission-exempt/scope-skip), **SEC-ACR-07** (E/F policy-mutation).
- **SEC-ACR-08/09** (routine + author-inert × acr=1 → pass); **SEC-ACR-10/11** (acr∈{0,absent} → `401`).
- **SEC-ACR-12** (SA-exempt на sensitive и routine; user НЕ exempt — mechanism-lock).

### Уровень 2 — catalog invariant unit (CI-validatable)
- **SEC-ACR-13:** множество `"2"`-FQN **равно** {41 named} (enumerate); комплемент `!="2"` (явные точки:
  Role/Condition/Group Create, `*/ListAccessBindings`, SA/User Delete, 42 Internal*-admin); `GroupService/Delete`
  несёт `"2"` (R3/B-2); Create несёт `"2"` при `permission="<exempt>"`; byte-identity двух копий; `permission`-поле не менялось.
- **SEC-ACR-15 (V3, R3/B-1):** generator-default = `"2"` **только для non-exempt** (non-exempt-un-annotated → `"2"`;
  **exempt-un-annotated → пустой acr**, не `"2"`); тест поведения step-up-слоя на пустом `RequiredACRMin`
  (fail-open) + authz-completeness net-closed (non-exempt) + exempt-third-contour оговорён; godoc-truthfulness assert.

### Уровень 3 — iam `acr_floor` + verdict-parity (bufconn/unit, CI-validatable)
- **SEC-ACR-14:** gateway-fronted `GrantAdmin` (`"2"`)×`acr=1` → `PERMISSION_DENIED`; `Get` (`"1"`)×`acr=1` → pass;
  dev-mode no-op сохранён (5.4-паттерн).
- **SEC-ACR-16 (O1, R3/B-4):** verdict-agreement — **реальные entrypoint'ы** `StepUpGate.Check` ≡ `grpcsrv.ACRSatisfies`
  над **полной матрицей** `{presented}×{required}` из `{"","0","1","2","3",<unknown>}` (не только rank-функции);
  три godoc-фикса (`stepup_gate.go`, `acr_floor.go`, `pkg/grpcsrv/acr.go`) — R3/B-3.

### Уровень 4 — e2e / newman (prod-mode стенд, требует live-gateway)
- **SEC-ACR-20 (happy):** user-JWT `acr="1"` прогоняет полный vpc/compute lifecycle + iam reads + author-inert
  create → всё зелёное (unblock `#59`). ≥1 happy.
- **SEC-ACR-21 (negative):** user-JWT `acr="1"` × `UserTokenService/Issue` **и** `InstanceService/SetAccessBindings`
  → `401` + `acr_values="2"`; после step-up до `acr="2"` → pass. ≥1 negative.

> Финальный гейт (ai-tooling §7): `go test ./... -race` + `golangci-lint run` + `govulncheck` +
> `make permission-catalog-check` (byte-identity) + newman зелёные (prod-mode e2e-конфиг для acr-кейсов).

---

## Traceability (scenario ID → lock-test; для ревьюера)

| Пункт дизайна (R2/R3) | Сценарий / Инвариант | Lock-тест (RED→GREEN) |
|---|---|---|
| Core-принцип: `"2"` ⟺ credential/grant/tenancy-root, **domain-agnostic** (RFC 9470 §1 + NIST 800-63B) | Sensitive-41, Routine-332 | SEC-ACR-01..09, -13 |
| A credential mint/destroy | SEC-ACR-01, -02, -03/A, -21 | `stepup_gate_test` credential-A |
| B iam-binding grant (incl. Create net-strengthen) | SEC-ACR-03/B, -06 | `stepup_gate_test` binding + create-exempt-acr2 |
| C compute per-resource grant (non-iam!) | SEC-ACR-04, -03/C, -21 | `stepup_gate_test` compute-grant (C1) |
| D group-membership grant + group-destroy (R3/B-2) | SEC-ACR-05, -03/D | `stepup_gate_test` membership (V1) + group-delete |
| E/F role/condition policy-mutation | SEC-ACR-07, -03/E,F | `stepup_gate_test` policy-mutation |
| G cluster-admin grant | SEC-ACR-03/G, -14 | `acr_floor_test` GrantAdmin |
| H tenancy-root destroy | SEC-ACR-03/H | `stepup_gate_test` tenancy-C |
| Routine unblock (регрессия #3) + author-inert (B6) | SEC-ACR-08, -09, -19, -20 | `stepup_gate_test` routine-pass + newman |
| AAL1-floor держится (регрессия #4) | SEC-ACR-10, -11 | `stepup_gate_test` acr0/absent |
| SA-exemption (регрессия #5) | SEC-ACR-12 | `stepup_gate_test`/`acr_floor_test` SA-exempt + user-not-exempt |
| Catalog invariant 41-set (регрессия #6) | SEC-ACR-13 | `permission_catalog_invariant_test` (41-set + complement + group-delete-2 + byte-identity + permission-unchanged) |
| iam acr_floor паритет (регрессия #7) | SEC-ACR-14 | `acr_floor_test` GrantAdmin-2 / Get-1 |
| Fail-safe уточнён (V3, R3/B-1): generator-default non-exempt + authz-completeness, exempt-third-contour | SEC-ACR-15, I9 | catalog-gen default (non-exempt→2, exempt→empty) + stepup empty-passes + godoc-truthfulness |
| Verdict-parity двух реальных entrypoint'ов (O1, R3/B-4) + три godoc-фикса (R3/B-3) | SEC-ACR-16, I8 | verdict-agreement lock-test (full matrix) + `pkg/grpcsrv/acr.go` godoc |
| FGA untouched | I10, SEC-ACR-06/08/09/18 | diff-guard: FGA-модель/`required_relation`/`permission` без изменений |
| B3 SA/User-Delete routine | SEC-ACR-17 | catalog + `stepup_gate_test` routine |
| B5 Internal*-admin routine (42), ReBAC держит | SEC-ACR-18 | catalog + FGA-relation assert |

---

## DoD (Definition of Done)

- [ ] **APPROVED `acceptance-reviewer`** (этот док, R3) до любого кода (ban #1); статус дока → APPROVED.
- [ ] **KAC-тикет + ветка** (или под-таск Phase-C эпика; `#59`/`#60` связаны); KAC-trail в vault.
- [ ] **TDD-red ДО кода** (ban #12): сперва RED lock-тесты SEC-ACR-01..21, затем правка каталога → GREEN;
      пара RED→GREEN в PR. Regression запирает **обсёрвабл** (`401`/`WWW-Authenticate`/reach-backend/gRPC-код +
      byte-identity + permission-unchanged).
- [ ] **proto:** явный `="1"` на 332 routine; явный `="2"` на 40 sensitive-с-permission (incl. `GroupService/Delete`);
      `="2"` **ADDED** на `AccessBindingService/Create` при сохранённом `permission="<exempt>"`; generator-default остаётся `"2"` (non-exempt).
- [ ] **regen каталога:** `cd gateway && make permission-catalog-apply`; iam-копия синхронизирована byte-identical;
      `make permission-catalog-check` зелёный.
- [ ] **инвариант I1/I2:** ровно 41 FQN несут `"2"` (enumerate; incl. `GroupService/Delete` R3/B-2); комплемент `!="2"`; обе копии byte-identical;
      `permission`-поле не менялось (SEC-ACR-13).
- [ ] **предохранён step-up** на 41 sensitive iam+compute (I3); Create net-strengthen (I4); **разблокирован**
      routine + author-inert (I5); **держится** AAL1-floor (I6).
- [ ] **не сломаны:** SA-exemption O-1 (I7, SEC-ACR-12), FGA relation-authz + `permission`-поле (I10), iam
      acr_floor паритет (I8, SEC-ACR-14).
- [ ] **fail-safe (V3, R3/B-1) уточнён:** generator-default non-exempt + authz-completeness net-closed; exempt-un-annotated →
      пустой acr (third-contour authN+ReBAC+FGA-exempt); **три godoc-фикса (R3/B-3):** `PermissionRequirement`
      (`stepup_gate.go`), `acr_floor.go` («SAME»), `pkg/grpcsrv/acr.go` («SHARED»); **verdict-parity (O1, R3/B-4)
      lock-тест** двух реальных entrypoint'ов над полной матрицей (security.md #5 doc-truthfulness).
- [ ] **boundary B1–B6 ратифицированы** и заперты (I11).
- [ ] **Newman:** ≥1 happy (SEC-ACR-20 — user `acr=1` full lifecycle) + ≥1 negative (SEC-ACR-21 — iam+compute
      step-up) на prod-mode e2e-конфиге; `#59` Phase C production-newman разблокирован.
- [ ] **Ревью ролями:** `system-design-reviewer` (assurance-model / no-drift между двумя floor'ами / fail-safe
      слоистость), `go-style-reviewer` (godoc-правки, thin). proto-message/RPC не добавлены → `proto-api-reviewer`
      только sanity (option-аннотации); схема БД не менялась → `db-architect-reviewer` N/A.
- [ ] **Финальная верификация:** `go test ./... -race` + `golangci-lint run` + `govulncheck` +
      `make permission-catalog-check` + newman зелёные.
- [ ] **Trail:** vault KAC-trail + затронутые сущности (rpc/edges); `#59`/`#60` обновлены; тикет → Test → Done с
      артефактами (PR-URL, лог RED→GREEN, newman-отчёт).

---

## Координация (после APPROVED)

1. `acceptance-reviewer` → `✅ APPROVED` (статус дока → APPROVED). Итерации по замечаниям (R2 учитывает
   round-1 CHANGES REQUESTED обоих gate'ов); ≥3 раунда без сходимости → эскалация неоднозначности заказчику.
2. `superpowers:writing-plans` → `integration-tester` (RED lock-тесты SEC-ACR-01..21) → реализация
   (точечная правка каталога-аннотаций + godoc-truthfulness + ranking-lock-тест; это не новый RPC —
   implementer действует в режиме config/annotation-change с TDD).
3. **Ревью:** `system-design-reviewer` (assurance-model / fail-safe слоистость / two-floor no-drift).
   `proto-api-reviewer` — sanity (option-аннотации, без нового контракта). `db-architect-reviewer` — N/A.
4. Заказчик — только финальный smoke / e2e (SEC-ACR-20/21: user `acr=1` full lifecycle + iam+compute step-up),
   шаг 7.

Сценарий оказался неоднозначным **после** старта кодирования → вернуть сюда для уточнения; НЕ менять
поведение реализации (в т.ч. границу sensitive/routine) без правки этого дока и повторного APPROVED.
