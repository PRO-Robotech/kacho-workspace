# Sub-phase T3.3 (unify IAM label-scope — all iam-types label-selectable) — Acceptance

> **Статус:** DRAFT — ревизия rev2 (адресует ❌ CHANGES REQUESTED `acceptance-reviewer`; готов к re-review — НЕ кодить до APPROVED, ban #1)
> **Дата:** 2026-06-25
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — _на re-review (rev2)_
> **Изменения rev2:** BLOCKING — User write-path специфицирован через **новый публичный `UpdateUser` RPC** (D-1a; proto→handler→gateway в DoD). Точность: AB immutability (нет `ReplaceTargetSelector`); request-`labels` annotation parity (SA — gap); §0.1/§6 ground-truth (foundation+SA уже COMMITTED — retro-gate ban #1); Q1–Q5 зафиксированы как принятые; MAT-02 — assertion «admin/owner no visibility loss».
> **Эпик/тикет:** GitHub-issue / KAC-Subtask проставит исполнитель ДО `superpowers:writing-plans`. Продолжение эпика «Resource-scoped AccessBinding» под-фаза **T3** (`epic-resource-scoped-access-binding-selectors-acceptance.md`, D6/Q4 + O-4 reopening) и след за `sub-phase-T3.1-cross-service-label-revoke-acceptance.md` (label-change revoke).
> **Затронутые репо:** `kacho-proto` / `kacho-iam` / **`kacho-api-gateway`** (новая public-регистрация `UserService.Update` — D-1a, блокирующая) / `kacho-ui` (follow-up, **не-блокирующий** backend) / `kacho-deploy` (e2e) / `kacho-workspace` (docs/vault).

---

## Обзор

Владелец требует **единую модель видимости для ВСЕХ iam-типов** — `iam.user` / `iam.serviceAccount` / `iam.group` / `iam.role` / `iam.accessBinding` — такую же, как у эталона `iam.account` / `iam.project`: ресурс **label-selectable**, `List` фильтрует через `viewer ∪ v_list`, а reconciler материализует `v_list` по label-селектору из own-table `labels` напрямую (**iam-direct same-DB**, НЕ через `resource_mirror` — self-mirror запрещён ацикличностью). Эта под-фаза **переоткрывает** ранее принятый дефолт T3/Q4 («iam label-selectable = только project/account») и решение **O-4** (`feed_registry.go` — iam content-типы намеренно вынесены в `iamContentMaterializableTypes`, НЕ label-selectable) — по **прямому указанию владельца «для всех единая модель»**.

Документ описывает **только внешнее наблюдаемое поведение API/UI** (gRPC-коды, REST-формы, `viewer ∪ v_list`-видимость, eventual-consistency reconcile-семантику), не реализацию (SQL/Go — забота implementer/db-reviewer). Сценарии трассируются в имена integration-/newman-/UI-тестов через ID `T3.3-NN`. Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) нормативны и в тело не дублируются — только ссылками (§1).

> **Retro-gate (формальная фиксация ban #1-нарушения).** Часть работы УЖЕ начата ДО APPROVED: ветка `unify-iam-label-scope` несёт **закоммиченную** foundation + ServiceAccount end-to-end (`kacho-iam`@`unify-iam-label-scope` — 2 коммита впереди `main`: `feat(iam): unify label-scope foundation — feed-gate, reconciler, SA end-to-end` + CI-pin; в `kacho-proto` добавлены resource-message `labels` для всех 5 типов). Это формальное отклонение от ban #1 (код до APPROVED) — фиксируется здесь для трассировки. Этот acceptance **retro-gate'ит** уже-сделанное: foundation+SA подлежат тому же ревью, что и остальное. **ОСТАВШИЙСЯ код** (user / role / access_binding + **новый `UpdateUser` RPC** + request-`labels` proto-аннотации + api-gateway public-регистрация UpdateUser) пишется **ТОЛЬКО ПОСЛЕ** APPROVED этого документа.

---

## 0.1 Ground-truth (сверено против кода — что есть / чего нет)

| Слой | Состояние (verified 2026-06-25) | T3.3 действие |
|---|---|---|
| **proto resource-message labels** | `account`/`project`/`group` несут `map<string,string> labels`. **Ветка `unify-iam-label-scope` уже COMMITTED'ила** (`kacho-proto`@`unify-iam-label-scope`): `User.labels=9`, `ServiceAccount.labels=8`, `Role.labels=15` (ресурса, отдельно от `Rule.match_labels=5`), `AccessBinding.labels=21` (mutable). | Зафиксировать как контракт; ревью `proto-api-reviewer`. Tag-номера утвердить (Q3). |
| **proto Create/Update request-messages** | `Create*/Update*Request` для SA/role/accessBinding принимают `labels` лишь частично; **User write-path вовсе отсутствует** — `UserService` сегодня несёт только `Get`/`List`/`Invite`/`Delete`/`ListOperations` (единственный иной User-write — internal `InternalUserService.UpsertFromIdentity`). НЕТ публичного `Update`/`UpdateUser`. | Ввести **НОВЫЙ публичный `UpdateUser` RPC** (D-1a); добавить `labels` в Create/Update request остальных типов + `update_mask`-allowed (D-1). |
| **request labels annotations** | `account`/`project`/`group` Create/Update `labels` несут ПОЛНЫЙ annotation-set (`(kacho.cloud.size)="<=64"`, `(length)="<=63"`, `(pattern)="[-_0-9a-z]*"`, `(map_key).length="1-63"`, `(map_key).pattern="[a-z][-_0-9a-z]*"`). **SA request `labels` (`service_account_service.proto`) — голый `map<string,string>` БЕЗ аннотаций.** | Привести SA (и все новые) request-`labels` к паритету — полный annotation-set, чтобы sync-`INVALID_ARGUMENT` энфорсился на request-message layer (D-1). |
| **feed_registry.go** | `labelSelectableTypes` = compute.*/vpc.*/loadbalancer.*/`iam.project`/`iam.account`. `iamContentMaterializableTypes` = `iam.role`/`iam.group`/`iam.serviceAccount`/`iam.user`/`iam.accessBinding` (O-4 — НЕ label-selectable). | Перенести 5 iam content-типов в `labelSelectableTypes` (снять O-4 feed-gate), D-2. |
| **authzmap / .fga model** | Все 5 iam-типов (`iam_user`/`iam_service_account`/`iam_group`/`iam_role`/`iam_access_binding`) УЖЕ verb-bearing, УЖЕ несут полный `v_get/v_list/v_create/v_update/v_delete`. | **Изменений НЕ требуется** (T3.3-CONF-01 non-regression). |
| **role.List** | УЖЕ `viewer ∪ v_list` (эталон, `role/list.go` + `list_vlist_union_test.go`): fail-closed (FGA error → `Unavailable`), anonymous → empty, system-role floor, `Get==List` resolver. | **Изменений НЕ требуется** (эталон, D-5; T3.3-CONF-02 non-regression). |
| **DB own-tables labels** | `accounts`/`projects`/`groups` имеют `labels jsonb NOT NULL DEFAULT '{}'`. `users`/`service_accounts`/`roles`/`access_bindings` — **НЕ имеют**. GIN (`jsonb_path_ops`) на `projects`/`accounts` (mig 0023); на `groups.labels` GIN **НЕТ**. Helper `kacho_iam.kacho_labels_valid(jsonb)` существует. Последняя миграция — `0040`. | migration **0041** (D-3): добавить колонку+CHECK+GIN на 4 таблицы; GIN на `groups.labels`. |
| **List user/SA/group/accessBinding** | `user.List` / `service_account.List` — **membership-scoped** (любой член аккаунта видит ВСЕХ). `group.List` — голый repo-passthrough (без фильтрации). `accessBinding.List` — канонического catalog-List нет: `ListByScope` (owner/FGA-admin-gated), `ListBySubject` (self/granted), `ListByAccount`, `ListByRole`. | Перевести user/SA/group `List` на `viewer ∪ v_list`; accessBinding — см. D-6. |
| **reconciler iam-direct** | `MatchIAMDirect` (ARM_LABELS) обрабатывает только `iam.project`/`iam.account`. `IAMDirectSelectorBindingsMatchingObject` switch покрывает все 5 iam-типов + `hasLabels`-флаг (готов к расширению; для groups `hasLabels=true`, но gated O-4 — нет arm='labels'-кандидатов). `iamDirectScanSpecs` несёт per-type read-plan для всех iam-типов (containment по iam-hierarchy). | Расширить ARM_LABELS-ветку MatchIAMDirect на 5 типов; `hasLabels=true` (D-4). |

⇒ Большая часть инфраструктуры готова: FGA verb-bearing, role.List-эталон, reconciler-switch со всеми типами. T3.3 добавляет: **labels write-path (proto+DB+repo)**, **снятие O-4 feed-gate**, **ARM_LABELS-материализацию для 5 типов**, **`viewer ∪ v_list` для user/SA/group/accessBinding**.

---

## 0.2 Фиксированные дизайн-решения (предлагаются автором; approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **D-1 (proto labels-поля)** | Каждый из `User` / `ServiceAccount` / `Role` / `AccessBinding` несёт **own-resource** `map<string,string> labels` (tenant-facing метки самого ресурса; для `Role` — отдельно от `Rule.match_labels`, которое отбирает ОБЪЕКТЫ под грантом). `Group` уже есть. Поле **аддитивно** (свободные tag-номера: ветка предложила User=9/SA=8/Role=15/AB=21 — финал утверждает `proto-api-reviewer`). **Create/Update request-messages принимают `labels`** (`labels` ∈ `update_mask` allowed-set). **Каждое request-`labels`-поле несёт ПОЛНЫЙ `kacho.cloud`-annotation-set** идентично account/project/group: `(kacho.cloud.size)="<=64"`, value `(length)="<=63"` + `(pattern)="[-_0-9a-z]*"`, `(map_key).length="1-63"` + `(map_key).pattern="[a-z][-_0-9a-z]*"`. **SA request-`labels` сегодня БЕЗ аннотаций → привести к паритету** (иначе sync-валидация labels не энфорсится). | Единая форма ресурса (`api-conventions.md` flat-message). `buf breaking`-safe (новые поля, новые tag-номера, не меняют существующие). Role.labels ≠ Rule.match_labels — два разных концепта (ресурс vs объекты-под-грантом), оба нужны. Аннотации на request-layer → sync-`INVALID_ARGUMENT` (DB CHECK — лишь async backstop). |
| **D-1a (новый публичный `UpdateUser` RPC)** | Сегодня `UserService` = `Get`/`List`/`Invite`/`Delete`/`ListOperations` — **публичного User-write нет** (единственный иной — internal `InternalUserService.UpsertFromIdentity`). По указанию владельца «единая модель для всех типов» + parity конвенций Kachō (у каждого иного iam-ресурса есть стандартный `Update`) вводится **НОВЫЙ публичный** `rpc Update(UpdateUserRequest) returns (operation.Operation)` (async, как все мутации). `UpdateUserRequest { string user_id; google.protobuf.FieldMask update_mask; map<string,string> labels; }` — **flat-форма** (паритет с UpdateRole/ServiceAccount/AccessBinding/Account/Project/Group): `labels` лежит на верхнем уровне request'а — единственное mutable-поле; immutable IdP-mirror-поля User в request не переносятся (на `User.labels=9` это поле эхо-отражается в read-проекции). **Mutability:** `labels` — единственное mutable-поле через этот Update; **identity-поля hard-immutable** (`external_id` — IdP-`sub`; и любой IdP-projected immutable identity-ключ) → их наличие в `update_mask` → `INVALID_ARGUMENT "<field> is immutable after User.Create"` (§4.3-discipline остальных ресурсов). **AuthZ:** гейт `v_update` на user-объекте (verb-bearing) + cluster-admin short-circuit — постура остальных Update. REST: `POST /iam/v1/users/{id}` с `update_mask=labels`. | User обязан стать label-mutable как все 5 типов; единственный существующий User-write — internal upsert (не подходит для tenant-facing labels). Standard `Update` — parity конвенций (`api-conventions.md` стандартные методы). `external_id` = IdP `sub` (идентичность, не tenant-намерение) → hard-immutable, как `account_id`/`is_system` у других. **Это in-scope работа** (proto+handler+gateway), не «labels-поле в существующем request». |
| **D-2 (feed_registry — снять O-4)** | Перенести `iam.user` / `iam.serviceAccount` / `iam.group` / `iam.role` / `iam.accessBinding` из `iamContentMaterializableTypes` в `labelSelectableTypes`. Эффект: `Role.Create` с `Rule.match_labels` на эти 5 типов **валиден** (feed-gate больше не reject'ит). `IsLabelSelectableType` возвращает `true` для всех iam-типов. **`AllMaterializableTypes()` (union) не меняет состав** — те же типы, иной bucket. | Прямое указание владельца «для всех единая модель» — переоткрытие O-4/Q4. Типы УЖЕ verb-bearing в FGA и УЖЕ есть в reconciler-switch/scan-specs → перенос — минимальное изменение whitelist + ARM_LABELS-ветки, без новой инфраструктуры. |
| **D-3 (migration 0041)** | `ALTER TABLE … ADD COLUMN labels jsonb NOT NULL DEFAULT '{}'::jsonb` + `CHECK kacho_iam.kacho_labels_valid(labels)` на `users` / `service_accounts` / `roles` / `access_bindings`; `CREATE INDEX … USING gin (labels jsonb_path_ops)` на эти 4 таблицы **И** на `groups.labels` (колонка groups уже есть, GIN — нет). Новая миграция, применённые НЕ редактировать (ban #5). | Own-table labels — источник истины для iam-direct ARM_LABELS (`labels @> matchLabels` GIN-probe). `jsonb_path_ops` — operator-class под `@>` (как projects/accounts mig 0023). DEFAULT `'{}'` → backfill не нужен (существующие строки получают пустой labels). GIN на groups закрывает «селектор по группам без индекса». |
| **D-4 (reconciler ARM_LABELS iam-direct)** | `MatchIAMDirect` (ARM_LABELS-путь) расширяется на все 5 iam content-типов: SELECT `id,…,id FROM <own-table> WHERE labels @> $matchLabels` (как нынешние project/account-ветки), containment — по **iam-hierarchy** (`iamDirectScanSpecs` per-type: account/project-anchor через `projects.account_id` / `access_bindings.resource_type,resource_id`). `IAMDirectSelectorBindingsMatchingObject` — `hasLabels=true` для всех 5 (снимает O-4-комментарий «no arm='labels' candidates»). **НЕ через `resource_mirror`** (iam-direct same-DB, нет self-ребра, ацикличность). iam-direct типы **НЕ имеют `PENDING_VERIFICATION`** (объект всегда в own-table source — нет eventual-lag). | iam — владелец этих ресурсов (карта владельцев `data-integrity.md`); labels/hierarchy в own-DB. Гонять свой ресурс через Internal RegisterResource в собственное зеркало — self-ребро `iam→iam` (ацикличность, бессмысленный кругооборот). Switch+scan-specs уже несут все 5 типов — расширяется только labels-предикат. |
| **D-5 (List user/SA/group → `viewer ∪ v_list`)** | `user.List` / `service_account.List` / `group.List` приводятся к эталону `role.List` (D-6a parity): per-object filter = `ListObjects(subj,"viewer",<fga_type>) ∪ ListObjects(subj,"v_list",<fga_type>)`, push visible-id-set в repo `WHERE id = ANY(...)`. Инварианты эталона сохраняются: **anonymous → empty** (default-deny, до FGA-call); **FGA nil/error → `Unavailable`** (fail-closed, никогда unfiltered leak); **self-доступ** (user/SA видит сам себя — через self-tuple `iam_user:<U>#subject@user:<U>`, см. iam-user.md gotcha; в `viewer`-ветку резолвится); **cluster-admin / operator floor** — через FGA viewer-ветку (tier-cascade), без отдельной membership-логики; **`Get == List`** (тот же resolver). **Устранить membership-over-show** (member аккаунта больше НЕ видит всех user/SA автоматически — только тех, на кого есть viewer/v_list). | role.List — доказанный эталон (#193/#185, list_vlist_union_test). membership-over-show — текущий over-grant (любой член аккаунта видит всех users) — противоречит «единой модели видимости» (видеть ровно matching-набор). FGA-types уже verb-bearing → resolver переносится один-в-один. |
| **D-6 (accessBinding List → `viewer ∪ v_list`, self/granted сохранены)** | `accessBinding` приводится к vlist-union-совместимой модели: **catalog-видимость** binding'ов фильтруется через `viewer ∪ v_list` на `iam_access_binding` (label-селектор материализует `v_list` на matching-binding'и). **НО** существующие read-наборы сохраняются как ортогональные floor'ы: `ListBySubject` (self — субъект видит СВОИ binding'и) и owner/granted-видимость (`ListByScope` owner/FGA-admin-gated) **НЕ урезаются** — они дополняют (union), не заменяются. Анти-leak (`list_by_subject_anti_leak_test`) сохраняется. Канонический catalog-List (если вводится) — `viewer ∪ v_list ∪ self`. | Единообразие: accessBinding тоже label-selectable (метка на binding → видимость через грант). Но binding несёт особую семантику (self/granted — субъект и владелец scope обязаны видеть свои/выданные гранты независимо от label-селектора) → self/granted остаются как floor, label-селектор — дополнительный путь видимости. Склоняемся к «accessBinding List = viewer ∪ v_list», но self/granted-floor not-negotiable (иначе субъект потеряет видимость своих грантов). |
| **D-7 (write-path repo + reconcile-trigger)** | `Create`/`Update` 5 iam-типов пишут `labels` в новые колонки (D-3). `Update` с `labels` ∈ `update_mask` (или empty mask = full-PATCH) **триггерит reconcile-event на own-resource label-change** (iam-direct аналог `mirror.upsert`): co-commit reconcile-event в той же writer-tx, что и UPDATE ресурса (как T3.1 G-4, как rbac-contract-a-fix co-commit reconcile-event на iam-native Create). Расширить существующий co-commit на **Update-on-label-change**. `update_mask`-дисциплина: `labels` — **mutable** (НЕ в hard-immutable list). | Own-resource label-change должен ре-материализовать membership (label add → грант появляется; label remove/change → eager-revoke), симметрично T3.1 для cross-service. Co-commit в writer-tx (ban #10 / SEC-D, нет dual-write). iam-direct: триггер — own-resource Update (не RegisterResource), reconcile читает own-table актуальное состояние. |
| **D-8 (non-breaking + НЕ resource_mirror)** | T3.3 аддитивен: новые proto-поля (D-1), новая колонка (D-3 DEFAULT '{}'), перенос типов в whitelist (D-2 — раньше `Role.Create` с match_labels на эти типы → reject «not selectable», теперь → работает). Существующие binding'и/роли без iam-label-селекторов не затронуты. **iam-типы НЕ регистрируются в `resource_mirror`** (НЕТ self-ребра `iam→iam`, НЕТ нового cross-domain ребра) — ацикличность графа сохранена (`polyrepo.md`). | Заказчик: единая модель, без регресса. Снятие feed-gate ослабляет валидацию (раньше-reject → теперь-allow) — чистое расширение. iam-direct same-DB — никакого нового ребра, никакого зеркала собственного ресурса. |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — flat message + own-resource `labels`; read sync, мутации async `Operation`; Watch нет (poll Operation/List) | D-1, §A read-формы; `Create`/`Update` async (наследие) |
| `api-conventions.md` — JSON camelCase (`labels`, `matchLabels`, `verificationStatus`, `serviceAccountId`, `roleId`) | §A/§C read-формы |
| `api-conventions.md` — стандартные методы ресурса (`Update` async→Operation) — новый публичный `UpdateUser` RPC | D-1a, T3.3-UPD-01, T3.3-UPD-02; §4 S1/S2/S3 DoD |
| `api-conventions.md` — update_mask discipline (`labels` mutable; empty mask = full-PATCH; unknown/immutable → INVALID_ARGUMENT) | D-1, D-1a, D-7, T3.3-VAL-01, T3.3-UPD-01, T3.3-UPD-02 |
| `api-conventions.md` — error-format; malformed → sync `INVALID_ARGUMENT`; состояние → `FAILED_PRECONDITION`; peer/FGA недоступен → `UNAVAILABLE` (fail-closed) | T3.3-VAL-01, T3.3-AUTHZ-02 |
| `data-integrity.md` §within-service — own-table `labels` + GIN `@>` (D-3); reconcile-event co-commit в writer-tx (D-7); reconcile idempotent; concurrent → integration-тест ≥2 goroutine | D-3, D-7, T3.3-CONC-01 |
| `data-integrity.md` §cross-domain — iam-direct own-table (источник истины, НЕ mirror); containment same-DB (iam-hierarchy); **НЕ новые рёбра** (iam-типы same-DB — НЕТ self-ребра `iam→iam`); ацикличность сохранена | D-4, D-8, §3 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC per-RPC Check; List fail-closed (anonymous → empty; FGA error → Unavailable); НИКОГДА unfiltered catalog leak | D-5, D-6, T3.3-AUTHZ-01, T3.3-AUTHZ-02 |
| `security.md` §инфра-чувствительные — `labels` — tenant-facing метки; placement/underlay/числовой инфра-id в selector-membership НЕ светятся (iam-ресурсы инфра-полей не несут) | D-1 |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB / co-commit reconcile-event), #5 (новая миграция 0041, не редактировать применённые), #4/#8 (НЕ shared БД — iam-direct same-DB), #12/#13 (TDD), #1 (APPROVED перед кодом) | §0.2, §4 DoD RED→GREEN |
| `polyrepo.md` §порядок merge | §4: proto → iam → **api-gateway (новая public-регистрация `UserService.Update`, D-1a)** → ui (follow-up) → deploy → workspace(docs) |
| Эпик T3 (`…-selectors-acceptance.md`, D6/Q4 + O-4) — T3.3 **переоткрывает** дефолт «iam = только project/account» по указанию владельца; sub-phase γ selector-контракт (matchLabels, containment, verification_status) сохраняется; role.List-эталон (#193) сохраняется | D-2, D-5, T3.3-CONF-01, T3.3-CONF-02 |

---

## 2. Модель видимости (нормативно — наблюдаемые точки)

Видимость ARM_LABELS-гранта на iam-тип наблюдается через **три** независимые проекции (любая — assert в тесте):
- **`InternalIAMService.Check`** (или публичный authz-гейт) на `{subject, relation=v_list|v_get|viewer, object="<fga_type>:<id>"}` → `allowed: true|false`.
- **`ListObjects`** (FGA-обратный) на `{subject, relation, type}` → массив object-id; ресурс **включён** ⇔ грант активен.
- **`<Resource>.List`** через api-gateway под токеном приглашённого (`viewer ∪ v_list`-фильтр) → ресурс присутствует ⇔ грант активен.

**iam-direct (D-4):** материализация — same-DB, без `resource_mirror`-lag; нет `PENDING_VERIFICATION` (объект всегда в own-table). Тем не менее membership-пересчёт после Create/label-Update — async (reconcile-event drain ≤2s + sweep-backstop). Тесты поллят до сходимости с таймаутом (как Operation-полл), НЕ ассертят мгновенно.

**fga_type-маппинг (read-формы):** `iam.user`→`iam_user`, `iam.serviceAccount`→`iam_service_account`, `iam.group`→`iam_group`, `iam.role`→`iam_role`, `iam.accessBinding`→`iam_access_binding`.

---

## 3. Cross-repo граф (без изменений — подтверждение ацикличности)

- iam-типы (user/SA/group/role/accessBinding) материализуются **iam-direct same-DB** (own-table `labels` + iam-hierarchy containment). **НЕТ self-ребра `iam→iam`**, **НЕТ нового cross-domain ребра** — этот документ НЕ вводит RegisterResource для собственных iam-ресурсов.
- IAM **не** зовёт consumer'ов обратно. Циклов нет. **НЕ заводить** `edges/iam-to-iam` / `edges/iam-to-vpc|compute|nlb`.

---

## §A — Backend: proto labels-поля + write-path (вкл. новый `UpdateUser` RPC) + validation

### Сценарий T3.3-LBL-01: Happy — Create iam-ресурса с labels → persisted, отдан на read

**ID:** T3.3-LBL-01

Табличный прогон по типам, у которых есть публичный `Create` — `ServiceAccount`, `Role`, `Group`, `AccessBinding` (`User` создаётся только через OIDC/Invite — для User labels задаются через новый публичный `UpdateUser` RPC, D-1a, см. T3.3-UPD-01).

**Given** account `acc-A` с owner `usr-OWNER`; caller — `usr-OWNER`

**When** caller вызывает `Create` для ресурса с непустым `labels`, напр.:
  - `POST /iam/v1/serviceAccounts` payload `accountId=acc-A`, `name=sa-payments`, `labels={"team":"payments","env":"prod"}`
  - _(аналогично `POST /iam/v1/roles` с `labels`, `POST /iam/v1/groups` с `labels`, `POST /iam/v1/accessBindings` с `labels`)_

**Then** `Create` возвращает `Operation`; полл `OperationService.Get(id)` до `done=true && !error`
**And** последующий `Get(<id>)` отдаёт ресурс с `labels={"team":"payments","env":"prod"}` (round-trip через own-table колонку, D-3)
**And** `labels` появляется в read-проекции в camelCase (`labels`)

### Сценарий T3.3-UPD-01: Happy — Update labels (включая User через новый UpdateUser) через update_mask

**ID:** T3.3-UPD-01

Табличный прогон по ВСЕМ 5 типам (`User`, `ServiceAccount`, `Group`, `Role`, `AccessBinding`). **User-ветка драйвится через НОВЫЙ публичный `UpdateUser` RPC (D-1a)** — `PATCH /iam/v1/users/{user_id}` с `updateMask=labels`, `labels` flat на теле request'а.

**Given** существует ресурс `<id>` с `labels={}` (User — через Invite/OIDC bootstrap; остальные — через Create)

**When** caller вызывает `Update(<id>)` с `updateMask={paths:["labels"]}`, `labels={"tier":"gold"}`
  - User: `POST /iam/v1/users/{usr-X}` (новый `UpdateUser`), тело `{ user:{ labels:{"tier":"gold"} }, updateMask:{paths:["labels"]} }`
  - SA/Group/Role/AccessBinding: их существующие `Update` с `labels` ∈ `update_mask`

**Then** `Operation` done без error; `Get(<id>).labels = {"tier":"gold"}` (для User — `UpdateUser` материализует РОВНО заданный label-набор, round-trip через own-table `users.labels`, D-3)
**And** _случай B (full-PATCH):_ Update с **пустым** `updateMask` и телом `labels={"tier":"silver"}` → применяется (empty mask = full-PATCH; mutable `labels` применяются, immutable из тела silently игнорируются — `api-conventions.md` update_mask discipline); `labels={"tier":"silver"}`
**And** _случай C (immutable-сосед не задет):_ Update labels не трогает hard-immutable поля (Role `account_id`/`is_system`/`name`-system; SA `account_id`; **User `external_id` и иные IdP-projected identity-поля**; AccessBinding — всё immutable КРОМЕ `labels` и `deletion_protection`)

### Сценарий T3.3-UPD-02: Negative — UpdateUser с identity-полем в update_mask → INVALID_ARGUMENT (immutability)

**ID:** T3.3-UPD-02

Фиксирует hard-immutability identity-полей нового `UpdateUser` RPC (D-1a).

**Given** существует `usr-X` с заполненным `external_id` (IdP `sub`)

**When** caller вызывает `UpdateUser(usr-X)` с `updateMask={paths:["external_id"]}` (попытка сменить IdP-идентичность)

**Then** sync `INVALID_ARGUMENT` `"external_id is immutable after User.Create"` (первым стейтментом RPC, до writer-tx; паритет §4.3 hard-immutable других ресурсов); `usr-X` не изменён
**And** unknown-поле в `update_mask` (напр. `paths:["nonexistent"]`) → sync `INVALID_ARGUMENT` (`corevalidate.UpdateMask` known-set — `api-conventions.md` update_mask discipline)
**And** _контраст:_ тот же identity-поле в **теле** при **пустом** `updateMask` (full-PATCH) → silently игнорируется (не error), применяются лишь mutable `labels`

### Сценарий T3.3-IMM-01: Negative — AccessBinding labels mutable, остальные поля immutable

**ID:** T3.3-IMM-01

`AccessBinding` исторически **полностью immutable** (Delete+Create), единственное mutable-поле сегодня — `deletion_protection` (`update_mask=["deletion_protection"]`). T3.3 **ДОБАВЛЯЕТ `labels`** в mutable-набор. Итого AB mutable = `{deletion_protection, labels}`; `roleId` / subjects / scope / `resourceType` / `resourceId` остаются immutable. (Поля `target`/`selector` — RESERVED tombstone'ы, НЕ существуют как RPC/поле; никакого `ReplaceTargetSelector` RPC нет.)

**Given** существующий `acb-X`

**When** `Update(acb-X)` с `updateMask={paths:["labels"]}`, `labels={"k":"v"}`
**Then** `Operation` done без error; `labels` обновлён (новый mutable-путь)

**When** `Update(acb-X)` с `updateMask={paths:["roleId"]}` (попытка сменить role)
**Then** sync `INVALID_ARGUMENT` `"role_id is immutable after AccessBinding.Create"` (immutable-набор НЕ ослаблен — добавлен только `labels`)

### Сценарий T3.3-VAL-01: Negative — невалидные labels отклоняются

**ID:** T3.3-VAL-01

**Given** account `acc-A`, caller owner

**When** `Create`/`Update` с невалидным `labels`:
  - значение нарушает pattern (напр. `labels={"Team":"PROD!"}` — заглавные/спецсимволы вне `[-_0-9a-z]*`)
  - превышен лимит (>64 пар / key >63 / value >63)

**Then** **sync** `INVALID_ARGUMENT` (валидация labels-map энфорсится на **request-message layer** — полный `kacho.cloud`-annotation-set, паритет account/project/group request; SA request-`labels` должны быть доведены до этого паритета, D-1); ресурс не создан/не изменён
**And** табличный прогон по всем 5 типам (вкл. SA — проверяет, что аннотации добавлены; и User — через новый `UpdateUser` request)
**And** DB CHECK `kacho_iam.kacho_labels_valid(labels)` (D-3) — defense-in-depth **async backstop** (если request-валидация обойдена) → `Operation.error` `INVALID_ARGUMENT` (`23514`→InvalidArgument, без leak pgx). Backstop не заменяет sync request-валидацию.

---

## §B — Backend: feed-gate снят (Rule.match_labels на iam-типы валиден)

### Сценарий T3.3-FEED-01: Happy — Role.Create с Rule.match_labels на iam-тип теперь валиден

**ID:** T3.3-FEED-01

Табличный прогон по 5 типам (`iam.user`/`iam.serviceAccount`/`iam.group`/`iam.role`/`iam.accessBinding`).

**Given** account `acc-A`, owner

**When** caller вызывает `POST /iam/v1/roles` с `rules=[{module:iam, resources:["user"], verbs:["get","list"], matchLabels:{team:payments}}]` (account-scoped)

**Then** `Operation` done без error; роль создана (feed-gate СНЯТ — `IsLabelSelectableType("iam.user")` → true, D-2)
**And** `Get(role).rules[0].matchLabels = {team:payments}` сохранён
**And** _повторить для_ `resources:["serviceAccount"]` / `["group"]` / `["role"]` / `["accessBinding"]` — каждый отдельный кейс

### Сценарий T3.3-FEED-02: Negative — match_labels на НЕ-selectable тип всё ещё reject (граница whitelist)

**ID:** T3.3-FEED-02

**Given** account `acc-A`, owner

**When** `Role.Create` с `rules=[{module:iam, resources:["<тип-вне-whitelist>"], verbs:[...], matchLabels:{...}}]` (тип, которого нет ни в `labelSelectableTypes`, ни валидный iam-тип — напр. гипотетический не-fed)

**Then** sync `INVALID_ARGUMENT` (feed-gate границу энфорсит — T3.3 расширяет whitelist именно на 5 iam content-типов, но НЕ открывает его целиком)
**And** _Примечание:_ кейс защищает, что снятие O-4 — точечное (ровно 5 типов), а не «любой тип теперь label-selectable»

---

## §C — Backend: iam-direct ARM_LABELS-материализация + eager-revoke

### Сценарий T3.3-MAT-01: Happy — label-грант на iam.user → caller видит РОВНО matching-набор

**ID:** T3.3-MAT-01

Главный материализационный сценарий (повторяется табличным прогоном для serviceAccount/group/role/accessBinding).

**Given** account `acc-A` с owner `usr-OWNER`
**And** в `acc-A` есть `usr-1`{team:payments}, `usr-2`{team:billing} (labels на own-table `users`, D-3)
**And** custom-роль `rol-userviewer` с правилом `{module:iam, resources:["user"], verbs:["get","list"], matchLabels:{team:payments}}` (account-scoped, T3.3-FEED-01)
**And** caller `usr-MEMBER` — приглашённый субъект без иной видимости user'ов

**When** owner создаёт AccessBinding `subjectId=usr-MEMBER`, `roleId=rol-userviewer`, `resourceType=account`, `resourceId=acc-A` → полл Operation done

**Then** reconciler (feed-source=**iam-direct** own-table, containment=iam-hierarchy `users.account_id ⊑ acc-A`, D-4) материализует: `usr-1`(matches `team:payments`, под `acc-A`) → per-object tuple `iam_user:usr-1#v_list@user:usr-MEMBER`; `usr-2` НЕ matches
**And** в пределах reconcile-таймаута: `Check{usr-MEMBER, v_list, iam_user:usr-1}` сходится к `true`; на `usr-2` → `false`
**And** `ListObjects{usr-MEMBER, v_list, iam_user}` включает `usr-1`, исключает `usr-2`
**And** `GET /iam/v1/users?accountId=acc-A` под токеном `usr-MEMBER` содержит РОВНО `usr-1` (через `viewer ∪ v_list`-фильтр, D-5); `usr-2` отсутствует
**And** iam-direct тип НЕ проходит через `PENDING_VERIFICATION` (объект сразу в own-table source — D-4)
**And** _повторить табличным прогоном:_ `iam.serviceAccount` (`sa-1`{team:payments} visible), `iam.group`, `iam.role`, `iam.accessBinding` — каждый отдельный кейс `T3.3-MAT-01-<type>`

### Сценарий T3.3-MAT-02: membership-over-show устранён (negative — единая модель)

**ID:** T3.3-MAT-02

Фиксирует ключевое изменение D-5: член аккаунта больше НЕ видит всех user/SA автоматически.

**Given** account `acc-A` с `usr-1`{team:payments}, `usr-2`{team:billing}; `usr-MEMBER` — обычный член `acc-A` (есть membership), но БЕЗ label-гранта на user'ов и без admin/owner

**When** `GET /iam/v1/users?accountId=acc-A` под токеном `usr-MEMBER`

**Then** ответ **НЕ содержит** `usr-1`/`usr-2` (membership-over-show устранён — видимость теперь только через `viewer ∪ v_list`, D-5), КРОМЕ `usr-MEMBER` сам себя (self-floor)
**And** `usr-MEMBER` видит **себя** (`usr-MEMBER` в ответе — self-tuple `iam_user:usr-MEMBER#subject@user:usr-MEMBER` резолвит viewer-ветку, iam-user.md gotcha)
**And** _контраст с до-T3.3:_ ранее любой член `acc-A` видел всех — теперь нет (это намеренное усиление изоляции)
**And** _аналогично для_ `serviceAccount.List` (member больше не видит все SA аккаунта)
**And** _(Q4 — БЕЗ регресса admin/owner workflow):_ под токеном **owner/admin** аккаунта `acc-A` (`usr-OWNER`) `GET /iam/v1/users?accountId=acc-A` **по-прежнему содержит ВСЕХ** (`usr-1`/`usr-2`/`usr-MEMBER`) — видимость admin/owner идёт через FGA **viewer**-tier-cascade (`account.admin→editor→viewer` на `iam_user`-объектах), НЕ через упразднённую membership-логику. **Никакой admin visibility loss.** cluster-admin (short-circuit) и operator-floor видят всех тем же путём (FGA viewer-ветка). Единая модель сужает видимость только для обычного члена-без-гранта, не для admin/owner.

### Сценарий T3.3-REVOKE-01: label снят → eager-revoke (v_list исчезает)

**ID:** T3.3-REVOKE-01

**Given** грант из T3.3-MAT-01 материализован: `usr-1`{team:payments} ACTIVE, `Check{usr-MEMBER, v_list, iam_user:usr-1}=true`, `usr-1` виден в List под `usr-MEMBER`

**When** owner вызывает **новый `UpdateUser` RPC** (D-1a) `POST /iam/v1/users/{usr-1}` с `updateMask={paths:["labels"]}`, `labels={}` (метка `team` снята)

**Then** `Operation` done без error; `Get(usr-1).labels` пуст
**And** `UpdateUser` co-commit'ит reconcile-event на own-resource label-change в writer-tx (D-7) — наблюдаемо как ре-материализация membership (eager fall-out)
**And** в пределах reconcile-таймаута: `usr-1` выпал из matched-set → eager-revoke tuple; `Check{usr-MEMBER, v_list, iam_user:usr-1}` сходится к `false`
**And** `ListObjects{usr-MEMBER, v_list, iam_user}` исключает `usr-1`; `GET /iam/v1/users` под `usr-MEMBER` больше не содержит `usr-1`
**And** _симметрия (forward re-materialization при label add):_ `usr-2` получает `labels={"team":"payments"}` через тот же `UpdateUser` → reconcile → `usr-2` появляется в matched-set → `Check{…iam_user:usr-2}` сходится к `true` (грант материализуется)

### Сценарий T3.3-REVOKE-02: смена метки (payments → billing) — грант мигрирует

**ID:** T3.3-REVOKE-02

**Given** `rol-X`{team:payments} — роль-ресурс с меткой; ДВА label-гранта субъекту `usr-MEMBER`: роль-P `{module:iam, resources:[role], matchLabels:{team:payments}}` и роль-B `{…, matchLabels:{team:billing}}`, обе на `account:acc-A`; reconcile сошёлся (`Check{usr-MEMBER, v_list, iam_role:rol-X}=true` через роль-P)

**When** owner вызывает `UpdateRole(rol-X)` с `updateMask={paths:["labels"]}`, `labels={"team":"billing"}`

**Then** `Operation` done; членство под роль-P (`matchLabels:{team:payments}`) ревокается, под роль-B (`{team:billing}`) материализуется
**And** **итоговая** видимость остаётся `Check{usr-MEMBER, v_list, iam_role:rol-X}=true` (теперь через роль-B) — grant-источник сменился (наблюдаемо: удаление роль-B → видимость пропадёт; удаление роль-P → нет)

### Сценарий T3.3-CONT-01: containment iam-hierarchy — ресурс под чужим account → не виден

**ID:** T3.3-CONT-01

**Given** label-грант на `account:acc-A`, `{module:iam, resources:[user], matchLabels:{team:payments}}`, субъекту `usr-MEMBER`
**And** `usr-foreign`{team:payments} принадлежит `acc-OTHER` (`users.account_id=acc-OTHER`)

**When** reconciler материализует membership

**Then** `usr-foreign` matches по labels/type, но **НЕ под scope** (iam-hierarchy: `acc-OTHER ⋢ acc-A`, D-4) → tuple НЕ эмитится; `Check{usr-MEMBER, v_list, iam_user:usr-foreign}` → `false`
**And** `GET /iam/v1/users?accountId=acc-OTHER` под `usr-MEMBER` не содержит `usr-foreign` (нет видимости в чужой scope)

### Сценарий T3.3-AB-01: accessBinding label-видимость + self/granted floor сохранён

**ID:** T3.3-AB-01

Особый случай D-6 — accessBinding label-selectable, но self/granted-floor not-negotiable.

**Given** account `acc-A`, owner `usr-OWNER`; binding `acb-1`{stage:prod} (метка на самом binding), `acb-2`{stage:dev}
**And** label-грант `{module:iam, resources:[accessBinding], verbs:[get,list], matchLabels:{stage:prod}}` субъекту `usr-MEMBER` на `account:acc-A`
**And** `usr-SELF` — субъект binding'а `acb-2` (`acb-2.subject_id=usr-SELF`), без label-гранта

**When** reconcile сошёлся

**Then** `usr-MEMBER` видит `acb-1` (label-match через `viewer ∪ v_list`), НЕ видит `acb-2` (label не matches)
**And** `usr-SELF` видит `acb-2` (self-floor `ListBySubject` — субъект видит свои binding'и, D-6 — НЕ урезается label-селектором), независимо от label
**And** `usr-OWNER` видит ВСЕ binding'и на `acc-A` (owner/FGA-admin floor `ListByScope`, D-6 — НЕ урезается)
**And** анти-leak сохранён: посторонний `usr-X` (не subject, не owner, без label-гранта) не видит ни `acb-1`, ни `acb-2`

---

## §D — AuthZ / fail-closed / non-regression

### Сценарий T3.3-AUTHZ-01: anonymous → empty List (fail-closed)

**ID:** T3.3-AUTHZ-01

**Given** существуют user/SA/group/role/accessBinding в `acc-A`

**When** анонимный (не аутентифицированный) вызывает `List` любого из 5 типов

**Then** **empty result** (default-deny, как role.List — anonymous отсекается ДО FGA-call); НИКАКОГО leak существующих ресурсов
**And** табличный прогон по всем 5 типам

### Сценарий T3.3-AUTHZ-02: FGA недоступен на List → Unavailable (никогда unfiltered leak)

**ID:** T3.3-AUTHZ-02

**Given** аутентифицированный `usr-MEMBER`; FGA (ListObjects) временно недоступен

**When** `usr-MEMBER` вызывает `List` (user/SA/group/accessBinding — типы, переведённые на `viewer ∪ v_list`)

**Then** `UNAVAILABLE` (fail-closed — никогда unfiltered catalog leak, никогда owner-only fallback; паритет role.List D-47/security.md)
**And** **НЕ** возвращается полный список (отказ безопаснее over-show)

### Сценарий T3.3-CONC-01: Concurrency — конкурентный label-flip + reconcile идемпотентен

**ID:** T3.3-CONC-01

**Given** `usr-C`{team:payments} в `acc-A`; label-грант `matchLabels:{team:payments}` субъекту `usr-MEMBER`

**When** N≥2 goroutine конкурентно вызывают **новый `UpdateUser` RPC** (D-1a, `POST /iam/v1/users/{usr-C}`, `update_mask=labels`) с чередующимися `labels` (`{team:payments}` ↔ `{}`)

**Then** финальное состояние `usr-C.labels` детерминировано (last-writer под row-lock на `users`-row, не TOCTOU — `data-integrity.md`); reconcile idempotent (diff desired-vs-actual)
**And** итоговая видимость (`Check`/`ListObjects`) детерминированно соответствует финальной метке (matched ⇔ финал `={team:payments}`); нет «застрявшего» стейл-членства, нет дублей в membership/tuple-ledger
**And** (integration, testcontainers, ≥2 goroutine — **обязателен** `data-integrity.md` §5) ни одна гонка не оставляет membership рассинхронизированным с финальным состоянием ресурса

### Сценарий T3.3-CONF-01: Non-regression — FGA-модель + verb-bearing типы не тронуты

**ID:** T3.3-CONF-01

**Given** FGA-модель: 5 iam-типов уже verb-bearing (`v_get/v_list/v_create/v_update/v_delete`)

**When** проверяется FGA-модель / authzmap после T3.3

**Then** состав relation'ов 5 типов **не изменён** (T3.3 не трогает .fga/authzmap — D-2 меняет только `feed_registry.go` Go-whitelist + reconciler ARM_LABELS-ветку)
**And** существующие ARM_NAMES (resource_names pin-by-id) гранты на эти типы работают как прежде (ARM_NAMES не feed-gated)

### Сценарий T3.3-CONF-02: Non-regression — role.List эталон + project/account iam-direct не регрессируют

**ID:** T3.3-CONF-02

**Given** существующий `role.List` (`viewer ∪ v_list`, #193) + `iam.project`/`iam.account` ARM_LABELS-гранты (T3 D6, в проде)

**When** читаются/проверяются после T3.3

**Then** `role.List` membership/видимость без изменений (T3.3 НЕ трогает role.List — он эталон, D-5); `list_vlist_union_test` зелёный
**And** `iam.project`/`iam.account` label-гранты материализуются как прежде (T3.3 расширяет ARM_LABELS-ветку на 4 НОВЫХ типа, project/account-ветки не тронуты)
**And** `AllMaterializableTypes()` (wildcard-expansion union) возвращает тот же состав типов (перенос между bucket'ами не меняет union — D-2)

---

## §E — UI (follow-up, НЕ-блокирующий backend)

> UI — отдельная стадия, не блокирует backend-merge. Backend контракт (proto labels + `viewer ∪ v_list`) самодостаточен; UI догоняет.

### Сценарий T3.3-UI-01: labels-editor на формах iam-ресурсов + membership через единую модель

**ID:** T3.3-UI-01

**Given** оператор на форме создания/редактирования User/SA/Group/Role/AccessBinding

**When** форма рендерит секцию labels

**Then** labels-editor (key/value пары) доступен на Create/Update этих ресурсов (паритет с account/project формами)
**And** types-picker grant-формы «По меткам» (наследие T3) предлагает iam-типы `user`/`serviceAccount`/`group`/`role`/`accessBinding` как label-selectable (раньше — недоступны, O-4)
**And** список ресурсов (UserPage/RolesPage/…) отражает `viewer ∪ v_list`-видимость (показывает ровно то, что backend отдал — без отдельной membership-логики на фронте)

---

## 3.1 Что НЕ входит в scope (явно исключено)

| Область | Статус / почему вне scope |
|---|---|
| **FGA-модель / authzmap** | Без изменений: 5 iam-типов уже verb-bearing с полным `v_*` (T3.3-CONF-01). T3.3 меняет только Go-whitelist (`feed_registry.go`) + reconciler ARM_LABELS-ветку + List-resolver. |
| **role.List** | Уже `viewer ∪ v_list` (эталон) — НЕ трогаем, только non-regression (T3.3-CONF-02). Менять role.List запрещено. |
| **iam.project / iam.account ARM_LABELS** | Уже работают (T3 D6) — НЕ трогаем, только non-regression. T3.3 добавляет ровно 4 новых типа (user/SA/role/accessBinding) к ARM_LABELS-ветке + переносит group/role/SA/user/AB whitelist-bucket. |
| **resource_mirror для iam-типов** | **Запрещено** (D-8): iam-direct same-DB, нет self-ребра `iam→iam`, нет нового cross-domain ребра. iam-ресурсы НЕ регистрируются в собственное зеркало. |
| **cross-service типы (vpc/compute/nlb)** | Вне scope — это T3 / T3.1 (mirror-fed). T3.3 — только iam-собственные 5 типов (iam-direct). |
| **User.Create публичный** | User создаётся только через OIDC/Invite (нет публичного Create) — labels на User задаются через **новый публичный `UpdateUser` RPC** (D-1a, T3.3-UPD-01), не Create. `UpdateUser` — единственный новый RPC под-фазы (in-scope); никаких иных новых User-методов. |

---

## 4. Definition of Done (по стадиям; кросс-репо порядок `polyrepo.md`)

Кросс-репо порядок: **proto → iam → api-gateway (новая public-регистрация `UserService.Update`, D-1a) → ui (follow-up) → deploy (e2e) → workspace(docs/vault)**. Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего. Каждая Go-стадия: **RED-first** (падающий тест ДО кода, ban #12/#13), затем GREEN; в PR показать пару RED→GREEN.

**S1 — proto (`kacho-proto`) [D-1, D-1a]:**
- [ ] `User.labels` / `ServiceAccount.labels` / `Role.labels` / `AccessBinding.labels` — own-resource `map<string,string> labels` (свободные tag-номера; ветка предложила User=9/SA=8/Role=15/AB=21 — утверждает `proto-api-reviewer`). `Group.labels` уже есть.
- [ ] **НОВЫЙ публичный `rpc Update(UpdateUserRequest) returns (operation.Operation)`** в `UserService` (D-1a) + **flat `message UpdateUserRequest { string user_id; google.protobuf.FieldMask update_mask; map<string,string> labels; }`** (паритет с UpdateRole/ServiceAccount/AccessBinding — `labels` на верхнем уровне request'а, НЕ вложенный `User`; `UserService` сегодня `Update`-метода вовсе не имеет). Read-проекция `labels` эхо-отражается на `User.labels=9`.
- [ ] `Create*/Update*Request` для SA/Role/Group/AccessBinding принимают `labels` (`labels` ∈ `update_mask` allowed-set).
- [ ] **Request-`labels` annotation parity (D-1):** КАЖДОЕ Create/Update request-`labels`-поле всех типов несёт ПОЛНЫЙ `kacho.cloud`-annotation-set, идентичный account/project/group (`(kacho.cloud.size)="<=64"`, value `(length)="<=63"` + `(pattern)="[-_0-9a-z]*"`, `(map_key).length="1-63"` + `(map_key).pattern="[a-z][-_0-9a-z]*"`). **SA request-`labels` (`service_account_service.proto`) сегодня голые без аннотаций → привести к паритету** (иначе VAL-01 sync-`INVALID_ARGUMENT` не энфорсится на request-layer).
- [ ] `buf lint`/`breaking` зелёные (аддитивно — новые поля/tag-номера + новый RPC `Update` в существующем сервисе = non-breaking append). Ревью — `proto-api-reviewer` (flat-resource envelope, новый RPC sync/async форма `Update`→Operation, Internal-vs-public, tag-номера).

**S2 — iam (`kacho-iam`) [D-2..D-7 core]:**
- [ ] RED integration-тесты (testcontainers) по T3.3-LBL-01, T3.3-UPD-01, T3.3-UPD-02, T3.3-IMM-01, T3.3-VAL-01, T3.3-FEED-01/02, T3.3-MAT-01 (×5 типов), T3.3-MAT-02 (вкл. owner/admin no-loss assertion), T3.3-REVOKE-01/02, T3.3-CONT-01, T3.3-AB-01, T3.3-AUTHZ-01/02, T3.3-CONC-01, T3.3-CONF-01/02 первыми → подтверждён красный → GREEN.
- [ ] **migration 0041 (D-3):** `ADD COLUMN labels jsonb NOT NULL DEFAULT '{}'` + CHECK `kacho_labels_valid` + GIN `jsonb_path_ops` на `users`/`service_accounts`/`roles`/`access_bindings`; GIN на `groups.labels`. Новая миграция (не редактировать применённые, ban #5). Ревью — `db-architect-reviewer` (GIN op-class, CHECK, idempotent migration).
- [ ] **feed_registry (D-2):** перенести 5 iam content-типов в `labelSelectableTypes`; `IsLabelSelectableType` → true для всех iam-типов; `AllMaterializableTypes()` union-состав НЕ меняется (тест на стабильность union).
- [ ] **reconciler iam-direct (D-4):** `MatchIAMDirect` ARM_LABELS-ветка на 5 типов (own-table `labels @> matchLabels`, containment iam-hierarchy через `iamDirectScanSpecs`); `IAMDirectSelectorBindingsMatchingObject` `hasLabels=true` для 5 типов; БЕЗ self-register-mirror; iam-типы без PENDING_VERIFICATION.
- [ ] **List `viewer ∪ v_list` (D-5/D-6):** `user.List`/`service_account.List`/`group.List` → эталон role.List (anonymous→empty; FGA-error→Unavailable; self-floor; cluster-admin/operator floor через FGA viewer; membership-over-show устранён). accessBinding — `viewer ∪ v_list ∪ self/granted-floor` (D-6, анти-leak сохранён).
- [ ] **новый `UpdateUser` use-case + handler + repo (D-1a):** UpdateUser use-case (`internal/apps/kacho/api/user/`) + тонкий handler + repo `users.labels`-write (mutable); update_mask discipline (`labels` mutable; `external_id`/IdP-identity → `INVALID_ARGUMENT "<field> is immutable after User.Create"` первым стейтментом; unknown → `INVALID_ARGUMENT`; empty mask = full-PATCH над `labels`); AuthZ-гейт `v_update` на user-объекте + cluster-admin short-circuit; мутация → `Operation` (async). reconcile-event co-commit на User label-change (см. ниже).
- [ ] **write-path + reconcile-trigger (D-7):** Create/Update (вкл. `UpdateUser`) пишут labels; Update-on-label-change co-commit reconcile-event в writer-tx (ban #10 / SEC-D); `labels` mutable (не в hard-immutable list).
- [ ] **Concurrent integration-тест** T3.3-CONC-01 (label-flip + reconcile idempotent, ≥2 goroutine) ОБЯЗАТЕЛЕН (RED-first, `data-integrity.md` §5).
- [ ] Error-mapping (`INVALID_ARGUMENT`/`FAILED_PRECONDITION`/`UNAVAILABLE`), без leak pgx (`23514`→InvalidArgument).
- [ ] by-design D-2/D-4/D-5/D-6 — запись в `docs/architecture/` kacho-iam (iam content-типы стали label-selectable — снятие O-4; iam-direct same-DB same containment; viewer∪v_list for all iam-types; membership-over-show устранён; **НЕТ self-ребра `iam→iam`**).
- [ ] Ревью — `db-architect-reviewer` (0041 GIN/CHECK; iam-direct `@>` SQL), `go-style-reviewer`, `system-design-reviewer` (reconcile-event co-commit / iam-direct триггер / **подтвердить: НЕТ self-ребра `iam→iam`, НЕТ нового cross-domain ребра** — ацикличность сохранена).

**S3 — api-gateway (`kacho-api-gateway`) [затронут — НОВАЯ public-RPC регистрация]:**
- [ ] **НОВАЯ public-RPC регистрация `UserService.Update` (D-1a)** — `api-gateway-registrar`: добавить в public allowlist + gRPC-director + **public REST mux** (`POST /iam/v1/users/{id}`). `UpdateUser` — публичный tenant-facing метод (НЕ Internal.*), светится на external endpoint наравне с `UpdateRole`/`UpdateGroup`/`UpdateServiceAccount`. (Прежняя формулировка «новых RPC T3.3 не вводит» была неверна — `UpdateUser` это новый публичный RPC.)
- [ ] Остальные затронутые public RPC (`ServiceAccountService`/`GroupService`/`RoleService`/`AccessBindingService` Create/Update/List, `UserService` Get/List) уже зарегистрированы — для них `labels`-поля проходят через существующий public-mux (новых регистраций нет). Internal.* (напр. `InternalUserService.UpsertFromIdentity`) НЕ светить на external (`security.md` ban #6).

**S4 — deploy + e2e (`kacho-deploy`):**
- [ ] newman happy (T3.3-LBL-01, T3.3-UPD-01 вкл. `UpdateUser` happy, T3.3-FEED-01, T3.3-MAT-01 ×5, T3.3-AB-01) + negative (T3.3-UPD-02 `UpdateUser` external_id-immutable, T3.3-VAL-01, T3.3-IMM-01, T3.3-FEED-02, T3.3-MAT-02 membership-over-show + owner/admin no-loss, T3.3-AUTHZ-01 anon, T3.3-AUTHZ-02 FGA-down) + non-regression (T3.3-CONF-02 role.List) через api-gateway, ≥1 happy + ≥1 negative на тип, RED-first. Eventual-consistency: полл `Check`/`ListObjects` до сходимости с таймаутом.
- [ ] e2e-build-матрицы newman зелёные для iam.

**S5 — ui (`kacho-ui`) [follow-up, НЕ-блокирующий]:**
- [ ] labels-editor на формах User/SA/Group/Role/AccessBinding (T3.3-UI-01); grant-форма «По меткам» предлагает iam-типы; List отражает `viewer ∪ v_list`. UI-тесты (vitest/playwright). Отдельный KAC-Subtask, не блокирует backend-merge.

**S6 — workspace (docs/vault):**
- [ ] Этот acceptance-док → APPROVED.
- [ ] vault: `resources/iam-user.md` / `iam-service-account.md` / `iam-role.md` / `iam-group.md` / `iam-access-binding.md` (label-selectable + own-resource labels; `viewer ∪ v_list` List; iam-direct ARM_LABELS), `rpc/iam-user-service.md` (**новый публичный `UpdateUser` RPC** — sync/async форма, REST `POST /iam/v1/users/{id}`, mutable `labels` + immutable `external_id`; membership-over-show устранён в List) / `iam-service-account-service.md` / `iam-role-service.md` / `iam-group-service.md` / `iam-access-binding-service.md` (Create/Update labels-поле; List-семантика), KAC-trail. **НЕ заводить** `edges/iam-to-iam` (iam-direct same-DB).
- [ ] by-design: запись в `docs/architecture/` kacho-iam (O-4 reopening — обоснование, единая модель видимости по указанию владельца).
- [ ] **O-4 reopening зафиксирован**: T3 `feed_registry.go` комментарии O-4 («iam.role/serviceAccount/group/user/accessBinding are NOT label-selectable») — обновить под новое решение (это часть прод-кода S2, не S6 — отмечено для трассировки).

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.

---

## 5. Решённые вопросы (Q1–Q5 — дефолты приняты review; НЕ переоткрывать)

Ревьюер принял дефолты автора (a) по всем пяти. Зафиксированы как решения; реализация следует им.

| # | Вопрос | **Решение (принято)** |
|---|---|---|
| **Q1** | **accessBinding List-модель (D-6)** — `viewer ∪ v_list ∪ self/granted-floor`, ИЛИ owner/admin-only? | **ПРИНЯТО (a):** `viewer ∪ v_list` + self/granted-floor (единообразие; binding label-selectable; self/granted not-negotiable). Self = `ListBySubject`, granted = `ListByScope` owner/admin — остаются как union-floor'ы (T3.3-AB-01). |
| **Q2** | **Триггер reconcile на own-resource label-change (D-7)** — co-commit в writer-tx ИЛИ sweep? | **ПРИНЯТО (a):** co-commit reconcile-event в той же writer-tx, что Update labels (event-driven, атомарно) + sweep backstop — паритет T3.1. Деталь co-commit финализирует `system-design-reviewer` при реализации. |
| **Q3** | **proto tag-номера (D-1)** — принять ветку (User=9/SA=8/Role=15/AB=21) или переназначить? | **ПРИНЯТО:** ветка (свободные tag-номера); append-only-дисциплину финально подтверждает `proto-api-reviewer`. |
| **Q4** | **membership-over-show устранение (D-5/T3.3-MAT-02)** — сужение видимости user/SA. Усиление изоляции или floor «admin видит всех»? | **ПРИНЯТО (a):** устранить — единая модель (видеть ровно matching-набор). Admin/owner/cluster-admin видят всех через **FGA viewer tier-cascade** (НЕ membership) → **БЕЗ регресса admin-workflow** — явная assertion в T3.3-MAT-02 (owner/admin `List` по-прежнему содержит всех). |
| **Q5** | **Role.labels vs Rule.match_labels именование (D-1)** — риск путаницы. | **ПРИНЯТО:** чёткие proto-комментарии (ветка уже разводит: `Role.labels` = метки ресурса, `Rule.match_labels` = отбор объектов); UI — разные секции формы. Финал — `proto-api-reviewer`. |

> Решения влияют на план (`writing-plans`) и реализацию (List-floor accessBinding, reconcile-триггер), не на форму большинства сценариев. Q1/Q4 уже отражены в T3.3-AB-01 / T3.3-MAT-02. Новый `UpdateUser` RPC (D-1a) — НЕ открытый вопрос, а решение по указанию владельца (единая модель) + parity конвенций; зафиксирован в §0.2 D-1a и §4 S1/S2/S3.

---

## 6. Выход / запреты

- Единственный артефакт авторства — этот markdown. **Никакого кода** (`.go`/`.sql`/`.proto`). Ветка `unify-iam-label-scope` уже несёт **закоммиченную** foundation + ServiceAccount (см. §0.1 / Обзор retro-gate) — это формальное ban #1-отклонение, зафиксировано для трассировки; **ОСТАВШИЙСЯ** код (user/role/access_binding + **новый `UpdateUser` RPC** + request-`labels` proto-аннотации + api-gateway-регистрация UpdateUser) пишется ТОЛЬКО после APPROVED (ban #1).
- Описано только наблюдаемое поведение API/authz/UI; DB-уровень (0041 GIN/CHECK, iam-direct `@>` SQL, reconcile-event co-commit, role_rule_selectors) — забота `rpc-implementer`/`db-architect-reviewer`/`migration-writer`/`system-design-reviewer`.
- **Это осознанное расширение по прямому указанию владельца** «для всех iam-типов единая модель» — переоткрытие T3/Q4-дефолта и решения O-4 (`feed_registry.go`). Зафиксировано как D-2 + S6 by-design-запись.
- **НЕ resource_mirror для iam-типов** (D-8): iam-direct same-DB, **НЕТ self-ребра `iam→iam`**, **НЕТ нового cross-domain ребра**; ацикличность графа non-negotiable (`polyrepo.md`).
- **Non-breaking** (D-8): новые proto-поля + колонка DEFAULT '{}' + перенос whitelist-bucket (раньше match_labels на iam-тип → reject, теперь → allow); existing роли/binding'и не затронуты.
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- Координация после APPROVED: KAC-Subtask + `superpowers:writing-plans` → `integration-tester` (RED по T3.3-NN) → `rpc-implementer` (вкл. новый `UpdateUser` RPC end-to-end) → `api-gateway-registrar` (public-регистрация `UserService.Update`) → `proto-api-reviewer` (labels-поля/tag-номера + новый `Update`-RPC форма) / `db-architect-reviewer` (0041 / iam-direct `@>`) / `system-design-reviewer` (reconcile co-commit / ацикличность) → заказчик: финальный smoke (главный E2E — T3.3-MAT-01 + T3.3-REVOKE-01 через `UpdateUser`).
