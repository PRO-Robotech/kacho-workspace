# Sub-phase securitygroup-network-mandatory-and-same-network-rules — Acceptance

> Статус: APPROVED (правка 2026-06-01 — группа E переписана: self-healing backfill миграция вместо fail-fast, по требованию владельца; см. §«История правок» + D6)
> Дата: 2026-06-01
> Ревьюер: acceptance-reviewer (✅ APPROVED — 7 решений + 1 новый сценарий folded as FIXED defaults; правка группы E на backfill — owner-mandated, требует повторного APPROVE группы E + D6)
> Тикет: [KAC-243](https://prorobotech.youtrack.cloud/issue/KAC-243)
> Backend: `kacho-vpc` · Proto: `kacho-proto` (re-add `required` на `network_id`, см. §«Proto») · Frontend: `kacho-ui`
> Источники: `02-data-model-and-conventions.md` §14 (коды ошибок), workspace `CLAUDE.md`
> §«Запреты» #5/#6/#9/#10/#11/#12 + §«Within-service refs — DB-уровень обязателен» +
> §«Кросс-доменные ссылки на ресурсы», `kacho-vpc/CLAUDE.md` §4.4 (UpdateMask discipline) /
> §5 (validation layering) / §6 (error mapping) / §«Default SG», vault
> `[[resources/vpc-securitygroup]]` / `[[rpc/vpc-securitygroup-service]]`,
> proto `kacho/cloud/vpc/v1/security_group.proto` + `security_group_service.proto`,
> миграция `kacho-vpc/internal/migrations/0001_initial.sql` (SG table).

---

## История правок (changelog контракта)

> [!important] Направление фичи РАЗВЁРНУТО (KAC-243)
> Предыдущий драфт (`sub-phase-securitygroup-attach-to-network-acceptance.md`) описывал **attach-only**
> семантику: «бессетевую (network-less) SG можно один раз привязать к Network через `Update` с
> `update_mask=network_id`». **Этот контракт полностью отброшен.** Новое требование — ПРОТИВОПОЛОЖНОЕ:
>
> - **Было (отброшено):** `network_id` опционален на `Create`; `Update` принимает `network_id` в mask
>   (attach-only CAS); UI-кнопка «Привязать» бессетевые SG к сети; proto снял `required` с
>   `CreateSecurityGroupRequest.network_id`.
> - **Стало (этот документ):** `network_id` **обязателен** на `Create` и **неизменяем** после
>   (mandatory + immutable). Никакого attach/reassign/detach — все они rejected-by-design (не tech-debt).
>   SG→SG-правила разрешены **только в пределах одной Network**. UI: `network_id` обязателен в форме,
>   на табе сети — preset+locked; кнопка «Привязать» **удаляется**. proto: `required` на
>   `CreateSecurityGroupRequest.network_id` **возвращается**; `network_id` в `UpdateSecurityGroupRequest`
>   **НЕ добавляется**.
>
> Старый файл `sub-phase-securitygroup-attach-to-network-acceptance.md` подлежит удалению/архивации в
> том же PR, что и APPROVE этого документа (см. DoD п.8).

> [!important] Правка группы E (2026-06-01): миграция стала self-healing backfill (owner-mandated)
> Предыдущая версия группы E (сценарии 15/16) фиксировала **fail-fast + dev recreate**: миграция
> `ALTER … SET NOT NULL` падает при наличии NULL-строк, оператор пересоздаёт dev-стенд. **Это заменено.**
> Новое требование владельца («добавь везде дефолт нетворки для аккаунтов и создай связь несвязных СГ с
> созданной сетью, чтобы миграция не падала»):
>
> - Миграция **не падает**. Перед `SET NOT NULL` выполняется **backfill**: для каждого проекта
>   (`project_id`), у которого есть orphan-SG (с `network_id IS NULL` или пустым), миграция
>   **обеспечивает наличие default-Network** в этом проекте (переиспользует подходящую существующую сеть,
>   иначе создаёт новую) и проставляет orphan-SG этот `network_id`. После backfill `SET NOT NULL`
>   проходит чисто (ноль NULL).
> - **Scope = ОДНОРАЗОВЫЙ migration-backfill**, НЕ постоянная фича «авто-создание default-network на
>   проект» (см. флаг в конце §«Out of scope» + D6). Если владелец имел в виду постоянную фичу — это
>   отдельный эпик, не KAC-243.
> - Затронуты: группа E (сценарии 15/16 переписаны + добавлены 16b/16c/16d), D6, DoD п.5/6, §«Proto»
>   sequence. Группы A–D, F, G — **без изменений**.

---

## 0. Обзор

`SecurityGroup` в kacho-vpc — project-level ресурс, который **обязан** принадлежать ровно одной
`Network` своего проекта. Привязка к сети (`network_id`) задаётся **только при `Create`**, является
**обязательной** и **неизменяемой** на всём жизненном цикле SG — переместить SG в другую сеть, отвязать
её или создать SG «без сети» нельзя ни одним публичным RPC/полем.

Обоснование (продуктовое решение владельца): правило SG может ссылаться на **другую SecurityGroup**
(SG-target rule). SG на разных Network физически изолированы (никогда друг друга не «видят» в data-plane),
поэтому правило, таргетящее другую SG, имеет смысл **только** между SG одной и той же сети. Из этого
следует: SG должна принадлежать ровно одной сети с момента создания и не может её менять, а SG→SG-правила
ограничены пределами одной Network.

Это **реверт** недавнего изменения (`kacho-proto#8` + соответствующая правка kacho-vpc), сделавшего
`network_id` опциональным (registry/kacho-vpc сейчас допускают SG без сети; proto снял `required` с
`CreateSecurityGroupRequest.network_id`). Контракт «attach network-less SG» (предыдущий драфт)
**отменён** — фичи «привязать»/reassign/detach нет, они rejected-by-design.

Все мутации возвращают `operation.Operation` (async LRO, запрет #9; клиент поллит
`OperationService.Get`). Ссылочная безопасность `network_id` (existence) обеспечивается same-DB FK
`security_groups.network_id → networks(id)` + sync fast-fail precheck (запрет #10). Same-network-инвариант
SG-target-правил валидируется **на service-layer** — это осознанный дизайн-выбор, оправданный
immutability `network_id` (см. §«Design decisions», п. D3), а **не** отложенный tech-debt;
нормализация rule-target в отдельную таблицу с FK — отдельный редизайн-эпик.

### Терминология

- Идентификация ресурса — по `id`. `SecurityGroup.id` и `Network.id` имеют префикс `enp…`, regex
  `^enp[0-9a-hj-km-np-z]{17}$` (Network/RouteTable/SG/Gateway/PE делят `enp`, `kacho-vpc/CLAUDE.md` §«ID prefixes»).
- Проект — `project_id` (IAM-домен заменил Folder, KAC-124; в proto/REST поле — `projectId`,
  колонка БД — `project_id`).
- «SG-target rule» — правило, у которого в `oneof target` выбран `security_group_id` (ссылка на другую
  SG). Прочие виды target: `cidr_blocks` (CIDR-rule) и `predefined_target` — **не** SG-target.
- Все мутации возвращают `operation.Operation`; «Then … Operation done» = клиент опросил
  `GET /vpc/v1/operations/{id}` до `done=true`.

### Что НЕ меняется (boundary)

- Поведение `Update` по полям `name` / `description` / `labels` / `rule_specs` — **без изменений**
  (кроме добавления same-network-валидации SG-target-правил, §C).
- OCC через `xmin` на `Update` / `UpdateRules` / `UpdateRule` — **сохраняется**
  (`security_group_occ_integration_test.go`).
- Семантика CIDR-rule (`cidr_blocks`) и `predefined_target` — **без изменений** (сценарий 13).
- `Move` (cross-project) RPC — поведение для **не-привязанного** к сети случая не меняется, но в KAC-243
  Move получает **активный guard**: SG, привязанная к Network (а в новой модели — все SG), **не может**
  быть перемещена между проектами (сценарий 19, `FAILED_PRECONDITION`). Это не «Move вне scope / нетронут»,
  а целенаправленная защита инварианта (network привязана к проекту → cross-project Move сделал бы
  `network_id` dangling). Более широкий вопрос «должна ли SG вообще быть movable» — отдельный issue.

---

## Out of scope (явная граница, НЕ tech-debt)

Следующее **сознательно не реализуется** в KAC-243 и должно вести себя как «mandatory + immutable»
(запрещено), а не «недоделано»:

- **ATTACH / «Привязать»** — привязка существующей бессетевой SG к Network через `Update`. Отменено
  (это и был предыдущий, отброшенный драфт). Не реализуется; бессетевых SG в новой модели не существует.
- **REASSIGN / MOVE между сетями** — смена `network_id` с A на B через любой публичный путь. Запрещено
  (сценарии 04/05) — `network_id` неизменяем.
- **DETACH** — обнуление `network_id` (`""`/`null`). Запрещено: создать SG без сети нельзя (§A),
  отвязать нельзя (§B).
- **Создание SG без сети** (`network_id` пуст/отсутствует) — отвергается sync (сценарий 01).
- **Cross-project Move привязанной SG** — `Move` (cross-project) для SG, привязанной к Network,
  **активно отвергается** (`FAILED_PRECONDITION`, сценарий 19) — это guarded-by-design, не «нетронуто».
- **Нормализованная таблица rule-target + JSONB-триггер для same-network-инварианта** — **сознательно
  НЕ делается** в KAC-243. Same-network-проверка SG-target-правил выполняется **на service-layer**, и
  этого достаточно: `network_id` immutable (§B), поэтому проверка `target.network_id == self.network_id`
  **не** TOCTOU-prone (см. §«Design decisions» п. D3). Это осознанный дизайн-выбор, **не** tech-debt.
  Нормализация SG-target-ссылок в `security_group_rule_targets(rule_id, target_sg_id)` с FK +
  `network_id`-CHECK/триггером — это **редизайн-эпик** (`2026-05-30-vpc-network-sg-routetable-redesign.md`),
  не KAC-243. `db-architect-reviewer` сохраняет PR-time veto на миграцию (см. п. D3).
- **Постоянная фича «авто-создание default-Network на проект»** — KAC-243 **НЕ** вводит runtime-поведение
  «у каждого нового проекта автоматически появляется default-Network». Default-Network создаётся **только
  один раз, в миграции-backfill** (группа E), исключительно чтобы не оставить orphan-SG при `SET NOT NULL`.
  После миграции никакой автоматики «default-network per project» нет: новые SG требуют явный
  существующий `network_id` (§A, сценарий 01); новые проекты не получают сеть автоматически.
  > **Флаг для ревьюера/владельца:** формулировка владельца «добавь **везде** дефолт нетворки для
  > аккаунтов» допускает прочтение «постоянная фича». **Default-предположение этого документа —
  > migration-only backfill** (одноразово, по orphan-SG). Если требуется постоянная фича — это отдельный
  > эпик (новое runtime-поведение + acceptance), вне KAC-243; вынести в issue и подтвердить с владельцем.

---

## Группа A — `network_id` ОБЯЗАТЕЛЕН при Create

### Сценарий 01: Create SG без network_id → sync INVALID_ARGUMENT

**ID:** SG-NET-01-NEG-CREATE-NO-NETWORK

**Given** проект `P` (seed `projectId`) существует

**When** клиент вызывает `kacho.cloud.vpc.v1.SecurityGroupService/Create`
(REST `POST /vpc/v1/securityGroups`) с payload **без** `networkId` (поле отсутствует или пустая строка):
  - project_id = `<P>`
  - name = `"sg-1"`
  - (network_id отсутствует)

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` (Operation **НЕ** создаётся; `OperationService`
       не возвращает новую запись)
**And** текст ошибки — **`"network_id required"`** (lower-case, без «is» — в одном ряду с существующим
       `"project_id required"` в `create.go`, `status.Error(codes.InvalidArgument, "project_id required")`)
**And** в БД `kacho_vpc.security_groups` новая строка **не** появляется.

> Примечание: required-валидация `network_id` — sync, до создания Operation (в одном ряду с
> `project_id required` в `CreateSecurityGroupUseCase.Execute`; `kacho-vpc/CLAUDE.md` §5 «Validation
> layering» → Sync). Это reverts текущую ветку «network_id опционален» в `create.go`. Realism: сегодня
> `create.go:72` уже даёт `status.Error(codes.InvalidArgument, "project_id required")` — `network_id`
> required-check добавляется тем же стилем, новая ветка `if sg.NetworkID == "" { return …
> "network_id required" }` ставится **перед** Operation-созданием.

### Сценарий 02: Create SG с валидным существующим network_id → OK (happy path)

**ID:** SG-NET-02-CREATE-OK

**Given** проект `P`
**And** в `P` создана сеть `net-A` (`POST /vpc/v1/networks` → Operation done; `net-A.id` = `<netA>`)

**When** клиент вызывает `Create` с payload:
  - project_id = `<P>`
  - name = `"sg-2"`
  - network_id = `<netA>`

**Then** ответ синхронно содержит `operation.Operation` с непустым `id` (префикс `enp…`), `done=false`
**And** poll `GET /vpc/v1/operations/<opId>` сходится к `done=true` без `error`; `response` —
       созданная `SecurityGroup` с `networkId == "<netA>"`, `status = ACTIVE`
**And** `GET /vpc/v1/securityGroups/<sg2>` возвращает `networkId == "<netA>"`
**And** `GET /vpc/v1/networks/<netA>/security_groups` (`NetworkService.ListSecurityGroups`) содержит `sg-2`
**And** в `vpc_outbox` появилось событие `SecurityGroup … CREATED` для `<sg2>`.

### Сценарий 03: Create SG с несуществующим network_id → SYNC NOT_FOUND (+ async/FK backstop)

**ID:** SG-NET-03-NEG-NETWORK-NOTFOUND

**Given** проект `P`
**And** id `enp00000000000000000` (well-formed `enp…`) не соответствует никакой сети в `kacho_vpc`

**When** клиент вызывает `Create` с payload:
  - project_id = `<P>`
  - name = `"sg-3"`
  - network_id = `enp00000000000000000`

**Then** ответ — **синхронный** gRPC `NOT_FOUND` (Operation **НЕ** создаётся). Контракт — **sync fast-fail**:
       network-existence проверяется до Operation через `networkReader.Get` (sync-ветка уже есть в
       `create.go:107-108`, `if sg.NetworkID != "" && u.networkReader != nil { … networkReader.Get }`).
       Детерминированный наблюдаемый путь = sync `NOT_FOUND` (не async)
**And** текст ошибки — YC-стиля `"Network enp00000000000000000 not found"`
       (`status.Errorf(codes.NotFound, "Network %s not found", …)`)
**And** async-проверка в `doCreate` (`create.go:163-164`) + same-DB FK
       `security_groups.network_id → networks(id)` (`23503` → NOT_FOUND/FailedPrecondition через
       `mapRepoErr`) остаются как **defensive backstop** на случай TOCTOU-удаления сети между sync-precheck
       и записью — но happy-/negative-контракт для клиента детерминирован sync-путём
**And** в БД новая строка SG **не** появляется.

> Примечание: формат-/id-валидация (`corevalidate.ResourceID` на `network_id`) — однозначно sync, до
> network-existence-проверки. Размещение = **sync fast-fail + async backstop**: sync precheck даёт клиенту
> детерминированный `NOT_FOUND` без создания Operation; async-повтор в `doCreate` + FK ловят гонку
> «сеть удалена после precheck». Обе ветки уже существуют в `create.go` — контракт фиксирует sync как
> наблюдаемый путь, FK — как атомарный backstop (запрет #10).

---

## Группа B — `network_id` НЕИЗМЕНЯЕМ (no reassign / no attach / no detach)

### Сценарий 04: Update с network_id в update_mask → sync INVALID_ARGUMENT (unknown-field)

**ID:** SG-NET-04-NEG-UPDATE-MASK-NETWORK

**Given** SG `sg-2` существует, привязана к `net-A` (`networkId == "<netA>"`)
**And** существует другая сеть `net-B` (`<netB>`) того же проекта

**When** клиент вызывает `SecurityGroupService/Update`
(REST `PATCH /vpc/v1/securityGroups/<sg2>`) с payload:
  - security_group_id = `<sg2>`
  - update_mask = `["network_id"]`
  - (в теле произвольный `network_id=<netB>`, если поле вообще присутствует в request — см. §«Proto»)

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` (Operation **НЕ** создаётся)
**And** причина — `network_id` **не** входит в known-mask `Update` (`{name, description, labels,
       rule_specs}`); unknown-field в `update_mask` → `INVALID_ARGUMENT` через `corevalidate.UpdateMask`
       (это **уже** HEAD-поведение `validateSGUpdate`; фича **закрепляет** его как гарантию и
       запрещает добавлять `network_id` в known-set — в отличие от отброшенного драфта)
**And** `GET /vpc/v1/securityGroups/<sg2>` по-прежнему возвращает `networkId == "<netA>"` (не изменилось).

### Сценарий 05: full-PATCH (mask пустой) с network_id в теле → network_id НЕ меняется

**ID:** SG-NET-05-FULL-PATCH-IGNORES-NETWORK

**Given** SG `sg-2` привязана к `net-A` (`networkId == "<netA>"`)

**When** клиент вызывает `Update` (`PATCH /vpc/v1/securityGroups/<sg2>`) **без** `update_mask` (full PATCH):
  - security_group_id = `<sg2>`
  - name = `"sg-2-renamed"`
  - (в теле непустой `network_id=<netB>`, если поле присутствует в request)

**Then** Operation → `done=true` без `error`
**And** `name` обновлён (`"sg-2-renamed"`)
**And** `GET /vpc/v1/securityGroups/<sg2>` по-прежнему `networkId == "<netA>"` — full-PATCH **silently
       ignores** `network_id` в теле (`applySGMask` не присваивает `network_id` ни в no-mask, ни в
       per-field ветке — verbatim-YC silent-ignore immutable, `kacho-vpc/CLAUDE.md` §4.4). DETACH/MOVE
       «по умолчанию» не происходит.

### Сценарий 06: Нет публичного пути сменить network SG после Create (boundary)

**ID:** SG-NET-06-NO-REASSIGN-PATH

**Given** SG `sg-2` привязана к `net-A`

**When / Then** (граница — все попытки отвергаются by-design, не tech-debt):
  - **06a (attach/reassign через Update.mask):** покрыто сценарием 04 (sync `INVALID_ARGUMENT`).
  - **06b (detach через Update.mask, `network_id=""`):** покрыто сценарием 04 — `network_id` не в
    known-mask, поэтому любой `network_id` в mask (включая пустой) → `INVALID_ARGUMENT`. Отдельной
    «detach»-семантики нет.
  - **06c (full-PATCH):** покрыто сценарием 05 — silent-ignore, network не меняется.
  - **06d (отсутствие отдельного RPC):** в `SecurityGroupService` **нет** RPC `:attach` / `:detach` /
    `:reassign` / `:moveToNetwork` и т.п.; добавлять их **запрещено** этим контрактом. Единственный
    Move-RPC (`:move`) меняет `project_id`, не `network_id`, и для network-bound SG **активно запрещён**
    (`FAILED_PRECONDITION`, сценарий 19) — он **не** путь смены сети.

---

## Группа C — SG→SG-правила ограничены одной Network

### Сценарий 07: SG-target rule на SG из ДРУГОЙ сети → INVALID_ARGUMENT (at Create)

**ID:** SG-NET-07-NEG-RULE-CROSS-NETWORK-CREATE

**Given** проект `P`, сети `net-A` (`<netA>`) и `net-B` (`<netB>`)
**And** SG `sg-target-B` создана в `net-B` (`networkId == "<netB>"`, id `<sgB>`)

**When** клиент вызывает `Create` SG `sg-7` в `net-A` с `rule_specs[0]` = SG-target rule:
  - project_id = `<P>`
  - name = `"sg-7"`
  - network_id = `<netA>`
  - rule_specs[0].direction = INGRESS
  - rule_specs[0].security_group_id = `<sgB>`   (target SG в ДРУГОЙ сети `net-B`)

**Then** ответ — **синхронный** gRPC `INVALID_ARGUMENT` (sync fast-fail до Operation; async-повтор в
       worker'е = backstop). Cross-network SG-target — это невалидный rule-spec (target ссылается на
       объект, физически невидимый этой SG), **не** состояние ресурса → `INVALID_ARGUMENT`, **не**
       `FAILED_PRECONDITION`
**And** ошибка несёт `google.rpc.BadRequest` с `field_violations[0].field =
       "rule_specs[0].security_group_id"` (а **не** `wrapSGErr`/`NOT_FOUND`)
**And** текст ошибки —
       `"security group rule can only reference a security group in the same network"`
**And** SG `sg-7` **не** создаётся (вся транзакция Create отвергается).

### Сценарий 08: SG-target rule на SG из ТОЙ ЖЕ сети → OK

**ID:** SG-NET-08-RULE-SAME-NETWORK-OK

**Given** проект `P`, сеть `net-A` (`<netA>`)
**And** SG `sg-target-A` создана в `net-A` (`networkId == "<netA>"`, id `<sgA>`)

**When** клиент вызывает `Create` SG `sg-8` в `net-A` с `rule_specs[0]` = SG-target rule:
  - network_id = `<netA>`
  - rule_specs[0].direction = INGRESS
  - rule_specs[0].security_group_id = `<sgA>`   (target SG в ТОЙ ЖЕ сети `net-A`)

**Then** Operation → `done=true` без `error`
**And** `GET /vpc/v1/securityGroups/<sg8>` содержит правило с `securityGroupId == "<sgA>"`.

### Сценарий 09: SG-target rule cross-network через UpdateRules → INVALID_ARGUMENT

**ID:** SG-NET-09-NEG-RULE-CROSS-NETWORK-UPDATERULES

**Given** SG `sg-8` в `net-A`; SG `sg-target-B` (`<sgB>`) в `net-B`

**When** клиент вызывает `SecurityGroupService/UpdateRules`
(REST `PATCH /vpc/v1/securityGroups/<sg8>/rules`) с:
  - security_group_id = `<sg8>`
  - addition_rule_specs[0].direction = INGRESS
  - addition_rule_specs[0].security_group_id = `<sgB>`   (target в ДРУГОЙ сети)

**Then** **синхронный** gRPC `INVALID_ARGUMENT` (sync fast-fail до Operation; async-повтор = backstop)
       с текстом `"security group rule can only reference a security group in the same network"`
**And** ошибка несёт `google.rpc.BadRequest` с `field_violations[0].field` =
       `"addition_rule_specs[0].security_group_id"` (НЕ `wrapSGErr`/`NOT_FOUND`)
**And** набор правил `sg-8` **не** изменён (атомарная замена не применена).

> Impl-note (net-new wiring): `UpdateRulesUseCase` сегодня = `{repo, opsRepo}` (см.
> `update_rules.go:39-46`, `NewUpdateRulesUseCase(r Repo, opsRepo operations.Repo)`) — в него **НЕ**
> инжектирован ни SG-, ни Network-reader. Для same-network-проверки нужно добавить read-port,
> резолвящий: (a) `network_id` редактируемой SG и (b) `network_id` каждой target-SG. Это **net-new
> composition-root wiring** в `cmd/<svc>/main.go` (по аналогии с `networkReader` у
> `CreateSecurityGroupUseCase`). То же — для `UpdateRuleUseCase` (сценарий 10).

### Сценарий 10: SG-target rule cross-network через UpdateRule → INVALID_ARGUMENT

**ID:** SG-NET-10-NEG-RULE-CROSS-NETWORK-UPDATERULE

**Given** SG `sg-8` в `net-A` с существующим CIDR-rule `r1`; SG `sg-target-B` (`<sgB>`) в `net-B`

**When** клиент вызывает `SecurityGroupService/UpdateRule`
(REST `PATCH /vpc/v1/securityGroups/<sg8>/rules/<r1>`), меняя target правила `r1` на SG-target из
другой сети `security_group_id=<sgB>`

**Then** **синхронный** gRPC `INVALID_ARGUMENT` с текстом
       `"security group rule can only reference a security group in the same network"`
**And** ошибка несёт `google.rpc.BadRequest` с `field_violations[0].field` = `"security_group_id"`
       (поле target в `UpdateRuleRequest`; НЕ `wrapSGErr`/`NOT_FOUND`)
**And** правило `r1` остаётся неизменным.

> Impl-note: `UpdateRuleUseCase` сегодня = `{repo, opsRepo}` (`update_rule.go:39-46`) — read-port для
> network-резолюции редактируемой и target-SG нужно **доинжектировать** (net-new composition-root
> wiring), как и для `UpdateRulesUseCase` (сценарий 09).

> Примечание для покрытия: same-network SG-target rule через `UpdateRules` / `UpdateRule` (положительный
> путь) — зеркало сценария 08, должен проходить (`done=true`). Покрыть хотя бы один positive-путь
> per-endpoint в integration-тестах.

### Сценарий 11: SG-target rule на НЕсуществующую SG → INVALID_ARGUMENT

**ID:** SG-NET-11-NEG-RULE-TARGET-NOTFOUND

**Given** SG `sg-8` в `net-A`
**And** id `enp11111111111111111` (well-formed `enp…`) не соответствует никакой SG в `kacho_vpc`

**When** клиент вызывает `UpdateRules` для `sg-8` с `addition_rule_specs[0].security_group_id =
enp11111111111111111`

**Then** ответ — **`INVALID_ARGUMENT`** (один класс с cross-network: target-SG resolution — часть
       валидации rule-spec; несуществующая target-SG = невалидный rule-spec). **НЕ** `NOT_FOUND`, **НЕ**
       `wrapSGErr` — единый код для всех «плохой target-SG» (cross-network + non-existent) проще для клиента
**And** текст ошибки — `"security group rule references a non-existent security group"`
**And** ошибка несёт `google.rpc.BadRequest` с `field_violations[0].field` =
       `"addition_rule_specs[0].security_group_id"`
**And** lookup target-SG — в той же БД `kacho_vpc` (same-DB; SG — own-resource kacho-vpc).

> Замечание для импликации (impl note): `SG.network_id` неизменяем (§B), поэтому same-network-проверка
> по `network_id` **не** TOCTOU-prone — `network_id` ни у этой SG, ни у target-SG не может смениться между
> проверкой и записью. Единственная гонка — **удаление target-SG** между валидацией и применением →
> грациозный dangling-ref (target-SG могла быть удалена; правило хранит её id как строку, на чтении
> dangling-ref переживается без паники, `kacho-vpc/CLAUDE.md` §«Кросс-доменные ссылки» п.4 по аналогии —
> хотя здесь это within-DB ref). **Решение (D3):** service-layer-валидации **достаточно** для KAC-243;
> нормализованная rule-target-таблица + DB-backstop — отдельный редизайн-эпик (см. §«Design decisions» п. D3).

### Сценарий 12: Concurrency — удаление target-SG во время добавления SG-target rule

**ID:** SG-NET-12-CONCURRENT-TARGET-DELETE (integration / testcontainers)

**Given** SG `sg-8` в `net-A`; SG `sg-target-A` (`<sgA>`) в `net-A`

**When** одна goroutine выполняет `UpdateRules(sg-8, +rule{security_group_id=<sgA>})`, а параллельная
       goroutine выполняет `Delete(<sgA>)`

**Then** итог детерминирован по решению **D3 (service-layer)**: правило либо добавлено до удаления target-SG
       (тогда на чтении `GET <sg8>` правило присутствует с `securityGroupId=<sgA>`, а target-SG уже удалена →
       **грациозный dangling-ref**, не паника), либо `Delete(<sgA>)` прошёл первым (тогда `UpdateRules`
       видит target-SG отсутствующей → `INVALID_ARGUMENT` «references a non-existent security group»,
       сценарий 11). В новой модели **нет** нормализованного FK rules→sg, поэтому исход (b) «DB отклоняет
       одну операцию по FK» не применяется — это by-design (D3)
**And** **ни при каком исходе** сервис не падает и не возвращает `INTERNAL` с leak'ом pgx-текста
**And** integration-тест (testcontainers) фиксирует детерминированный исход D3: dangling-ref переживается
       на чтении ИЛИ negative `INVALID_ARGUMENT` — без inconsistent state и без паники.

### Сценарий 13: CIDR-rule и predefined_target — не затронуты

**ID:** SG-NET-13-CIDR-RULE-UNAFFECTED

**Given** SG `sg-2` в `net-A`

**When** клиент вызывает `UpdateRules(sg-2, +rule{cidr_blocks.v4_cidr_blocks=["10.0.0.0/24"]})` и
       (отдельно) `+rule{predefined_target="self_security_group"}`

**Then** оба правила принимаются (`done=true`) — same-network-проверка применяется **только** к
       SG-target-правилам (где выбран `security_group_id`), а не к `cidr_blocks` / `predefined_target`
**And** существующая CIDR-валидация (host-bits = 0, `validateSGRule`) — без изменений.

---

## Группа D — Default-SG (на Network.Create)

### Сценарий 14: Default-SG создаётся со своей сетью — не затронуто

**ID:** SG-NET-14-DEFAULT-SG-UNAFFECTED

**Given** `KACHO_VPC_DEFAULT_SG_INLINE=true` (default)

**When** клиент вызывает `NetworkService/Create` для `net-C` (`<netC>`) → Operation done

**Then** авто-создаётся default-SG `<sgDefault>` с `networkId == "<netC>"`, `default_for_network=true`,
       `status=ACTIVE`
**And** `net-C.default_security_group_id == <sgDefault>`
**And** default-SG уже имеет непустой `network_id` (создаётся inline через
       `domain.NewDefaultSecurityGroup`, `kacho-vpc/CLAUDE.md` §«Default SG») → mandatory-инвариант
       (§A) для неё выполняется естественно, отдельной правки пути default-SG не требуется
**And** попытка `Update(<sgDefault>, update_mask=["network_id"])` → sync `INVALID_ARGUMENT` (тот же
       инвариант immutable, что сценарий 04 — default-SG не исключение).

---

## Группа E — Self-healing миграция (backfill orphan-SG → default-Network + `SET NOT NULL`)

> **Контракт миграции (owner-mandated, заменяет fail-fast).** Перед `ALTER COLUMN network_id SET NOT
> NULL` миграция **backfill-ит** все orphan-SG (с `network_id IS NULL` или пустым), чтобы NULL-строк не
> осталось и `SET NOT NULL` прошёл чисто. Backfill — **одноразовый**, в одной миграции, идемпотентный,
> FK-упорядоченный (default-Network вставляются **до** `UPDATE` SG.network_id; `SET NOT NULL` —
> последним).
>
> **Реализация миграции = Go-миграция goose (решение D6, см. §«Design decisions»).** Причина: id сети
> = crockford-base32 `enp`+17 (`kacho-corelib/ids.NewID(ids.PrefixNetwork)`) — это **не** генерируется
> тривиально в чистом SQL/PLpgSQL (`kacho-vpc/CLAUDE.md` §2 прямо отмечает «id-generation crockford-base32
> не реализуется в PL/pgSQL без портирования `kacho-corelib/ids`»). Проверено по коду: migrator
> (`cmd/migrator` + `internal/apps/migrator`) использует **goose v3.27.1** через `goose.SetBaseFS(FS)` +
> `goose.UpContext`, а `cmd/migrator/main.go` и `internal/repo/integration_test.go` оба **импортируют**
> пакет `internal/migrations`. goose v3 поддерживает Go-миграции через `goose.AddMigrationContext(up,
> down)`: достаточно положить `.go`-файл в `package migrations` (рядом с `0001_initial.sql`), который в
> `init()` регистрирует up/down с версией `0004`; импорт пакета уже есть в обоих местах → миграция
> подхватится и в проде, и в integration-тестах, и сольётся с SQL-миграциями по номеру версии. Внутри
> `up(ctx, tx)` доступен полноценный Go: `ids.NewID(ids.PrefixNetwork)` + `tx.ExecContext` INSERT
> Network + `UPDATE security_groups`. Чистый-SQL вариант (PLpgSQL-энкодер crockford-base32 над
> `gen_random_uuid()`) **отвергнут** как уродливый и дублирующий `ids` (D6).

### Сценарий 15: Backfill — orphan-SG в проекте P → default-Network создаётся + SG привязаны + `SET NOT NULL` проходит

**ID:** SG-NET-15-MIGRATION-BACKFILL-OK (integration / testcontainers)

**Given** baseline `0001_initial.sql` объявляет `security_groups.network_id text REFERENCES
       kacho_vpc.networks(id) ON DELETE RESTRICT` (**nullable**, комментарий «unbound / folder-level SG,
       kacho-proto#8»)
**And** в проекте `P` (`project_id = "P"`) есть **orphan-SG** `sg-orphan-1` и `sg-orphan-2` с
       `network_id IS NULL` (или пустым), и **ни одной** сети
**And** (опционально для ветки reuse) в другом проекте `Q` уже есть подходящая существующая default-Network

**When** применяется **новая** миграция `0004` (goose Go-миграция, D6; запрет #5 — `0001_initial.sql`
       не редактируем) — в integration-тесте это `goose.Up(db, ".")` после seed orphan-SG

**Then** для проекта `P` миграция **обеспечивает default-Network**: переиспользует подходящую
       существующую сеть проекта (если такая есть — см. §«критерий reuse» ниже), иначе **создаёт** новую
       Network с `id = ids.NewID(ids.PrefixNetwork)` (валидный `enp…`), `project_id = "P"`,
       `name = "default"` (валидно по `networks_name_check`; уникально по `networks_project_id_name_key`
       — см. сценарий 16d про коллизию), `created_at = now()`, прочие колонки — defaults
       (`description=''`, `labels='{}'`, `default_security_group_id=''`, `route_distinguisher=''`)
**And** обе orphan-SG проекта `P` получают `network_id` = id этой default-Network
       (`UPDATE security_groups SET network_id = <netDefaultP> WHERE project_id='P' AND (network_id IS
       NULL OR network_id='')`)
**And** **порядок FK-безопасен**: INSERT Network выполняется **до** `UPDATE` SG.network_id (иначе FK
       `security_groups.network_id → networks(id)` отвергнет привязку); `ALTER COLUMN network_id SET NOT
       NULL` — **последним** стейтментом миграции, когда NULL-строк уже нет
**And** после миграции `SELECT count(*) FROM kacho_vpc.security_groups WHERE network_id IS NULL OR
       network_id = ''` = `0`
**And** FK `→ networks(id) ON DELETE RESTRICT` сохранён; колонка теперь `NOT NULL`
**And** комментарий-источник на колонке/в миграции обновлён: «network_id — mandatory + immutable
       (KAC-243); legacy orphan-SG backfilled to per-project default-Network».

> **Критерий reuse существующей сети (FIXED, D6):** «подходящая существующая default-Network проекта» =
> сеть проекта `P` с `name = 'default'` (если есть — взять её id, **не** создавать вторую). Если такой
> сети нет — создать новую `name='default'`. Это даёт идемпотентность (сценарий 16c) и избегает
> коллизии по `networks_project_id_name_key`. Если в проекте уже есть сеть с именем `default`, но НЕ
> создававшаяся backfill-ом — она всё равно валидный таргет привязки orphan-SG (сеть проекта; принадлежит
> тому же `project_id`), переиспользуется без вопросов.

> **No-recursive-default-SG (FIXED, D6):** backfill вставляет Network **напрямую SQL/Go в миграции, в
> обход service-layer** — поэтому inline default-SG creation (`network.go::doCreate`, §9 vpc-CLAUDE.md)
> **НЕ** триггерится (это путь сервиса, не миграции). default-Network, созданная backfill-ом, **остаётся
> с `default_security_group_id = ''`** и **без** собственной свежесозданной default-SG. Это намеренно:
> привязываемые к ней orphan-SG и становятся её security-group'ами; рекурсивно создавать ещё одну
> default-SG **запрещено** — это породило бы новую orphan-SG (которой ещё нет network_id на момент
> вставки) и/или лишнюю SG. Проверено по схеме: `networks.default_security_group_id text NOT NULL DEFAULT
> ''` — допускает пустую строку, FK на SG — `ON DELETE SET NULL` (см. §2 vpc-CLAUDE.md), поэтому пустой
> `default_security_group_id` валиден.

### Сценарий 16: Backfill-инварианты (scope / идемпотентность / коллизия имени)

**ID:** SG-NET-16-MIGRATION-BACKFILL-INVARIANTS (integration / testcontainers)

**16a — Проект без orphan-SG → НИ ОДНОЙ лишней сети не создаётся (negative):**
**Given** проект `R` со всеми SG, у которых `network_id` уже непустой (и/или вообще без SG)
**When** применяется миграция `0004`
**Then** для проекта `R` **никакая** default-Network не создаётся (backfill итерирует только по
       `DISTINCT project_id` среди orphan-SG — `WHERE network_id IS NULL OR network_id=''`); число сетей
       проекта `R` после миграции = до миграции
**And** существующие сети/привязки проекта `R` не изменены.

**16b — `SET NOT NULL` без orphan-SG вообще (чистый стенд) → миграция проходит, сетей не создано:**
**Given** стенд, где `security_groups` пуст или у всех SG `network_id` непустой (greenfield / уже
       мигрировано)
**When** применяется миграция `0004`
**Then** backfill — **no-op** (нет orphan-SG → цикл по проектам пуст → INSERT Network не выполняется),
       `SET NOT NULL` проходит, миграция зелёная; ни одной «спонтанной» default-Network не появилось.

**16c — Идемпотентность / повторный прогон (re-runnable-safe):**
**Given** миграция `0004` уже применена (goose записал версию в `goose_db_version` → повторно goose её
       не запустит) **И** гипотетический повторный прогон тела `up` (например, ручной replay в тесте)
**When** тело backfill выполняется второй раз на уже мигрированных данных
**Then** оно **идемпотентно**: для проекта `P` сеть `name='default'` уже существует → reuse (не вторая
       сеть; INSERT защищён через «найти `name='default'` → reuse, иначе INSERT», напр. `INSERT … ON
       CONFLICT (project_id, name) DO NOTHING` + повторный SELECT id, либо upsert-RETURNING); orphan-SG
       уже нет (все привязаны) → `UPDATE … WHERE network_id IS NULL` затрагивает 0 строк
**And** повторный прогон не падает и не плодит дубликаты сетей/привязок.

**16d — Коллизия имени default-Network:**
**Given** в проекте `P` с orphan-SG **уже существует** сеть `name='default'`, созданная пользователем
       (не backfill-ом)
**When** применяется миграция `0004`
**Then** backfill **переиспользует** существующую `default`-сеть проекта (по `networks_project_id_name_key`
       (project_id, name) — она одна) как таргет привязки orphan-SG; **второй** `default` не создаётся
       (иначе `23505` от UNIQUE-индекса). Имя `default` совпадает с `networks_name_check` regex →
       коллизий формата нет
**And** orphan-SG проекта `P` привязываются к этой существующей сети.

### Сценарий 16e: Созданная backfill-ом default-Network — валидный, listable Network

**ID:** SG-NET-16E-BACKFILL-NETWORK-LISTABLE (integration / e2e)

**Given** миграция `0004` отработала и создала default-Network `<netDefaultP>` в проекте `P` (ветка
       «не было подходящей сети»)
**And** сервис `kacho-vpc` поднят на этой БД

**When** клиент вызывает `GET /vpc/v1/networks/<netDefaultP>` и
       `GET /vpc/v1/networks?projectId=P` (`NetworkService.Get` / `List`)

**Then** `Get` возвращает корректную Network: `id == "<netDefaultP>"` (валидный `enp…`),
       `projectId == "P"`, `name == "default"`, `createdAt` непустой (truncated to seconds, §11)
**And** `List(projectId=P)` содержит эту сеть в результатах (она — обычный, полноценный Network-ресурс,
       не «битый» backfill-артефакт)
**And** `GET /vpc/v1/networks/<netDefaultP>/security_groups` (`NetworkService.ListSecurityGroups`)
       содержит привязанные backfill-ом orphan-SG (`sg-orphan-1` / `sg-orphan-2`) — теперь это нормальные
       SG этой сети
**And** default-Network не имеет «фантомной» свежесозданной default-SG помимо привязанных orphan-SG
       (`default_security_group_id == ''`, no-recursive-default-SG, сценарий 15).

### Сценарий 16f: Существующие бессетевые SG (dev) — раскатка KAC-243

**ID:** SG-NET-16F-DEV-ROLLOUT

**Given** в dev-стенде в окне «optional network_id» могли быть созданы SG с `network_id` пустым/NULL

**When** раскатывается KAC-243 (миграция `0004` применяется на существующей dev-БД **без** пересоздания)

**Then** миграция **не падает** (это и есть цель owner-правки): orphan-SG backfill-ятся к per-project
       default-Network (сценарий 15), `SET NOT NULL` проходит. Пересоздавать стенд **не требуется**
       (хотя greenfield-recreate тоже валиден — `emptyDir` Postgres, `03-deployment-and-operations.md` §5)
**And** **prod-раскатки нет** (no prod rollout yet); тот же self-healing backfill будет работать и на
       prod, когда он появится (миграция data-safe by design — не fail-fast). Отдельного prod-backfill
       issue **больше не требуется** (backfill встроен в миграцию, D6).

---

## Группа F — UI (`kacho-ui`)

### Сценарий 17: Форма Create SG — `network_id` ОБЯЗАТЕЛЕН

**ID:** SG-NET-17-UI-CREATE-NETWORK-REQUIRED

**Given** в `kacho-ui` открыта форма создания SecurityGroup

**When / Then** (два контекста):
  - **17a (с таба сети):** на детальной странице `Network` `net-A` → таб «Группы безопасности» →
    «Создать» — поле `network_id` **предзаполнено** значением `<netA>` и **заблокировано** (locked,
    нередактируемо); пользователь не может выбрать другую сеть
  - **17b (standalone create):** при создании SG вне контекста сети — поле выбора `network_id`
    **обязательно** (пользователь обязан выбрать сеть из списка сетей проекта); submit без выбранной
    сети блокируется клиентской валидацией (и backend всё равно отвергнет — сценарий 01)
**And** в форме **отсутствует** кнопка/действие «Привязать» (by design — это было заблуждение
       предыдущего драфта; SG↔network mandatory+immutable). Любой стаб «Привязать» в коде UI **удалён**.

### Сценарий 18: UI — редактор правил SG: SG-target picker фильтрует по той же сети

**ID:** SG-NET-18-UI-RULE-PICKER-SAME-NETWORK

**Given** в `kacho-ui` открыт редактор правил SG `sg-8` (которая в `net-A`), пользователь добавляет
       SG-target rule
**And** в проекте есть SG в `net-A` (`sg-target-A`) и SG в `net-B` (`sg-target-B`)

**When** пользователь открывает picker target-SecurityGroup

**Then** в списке кандидатов отображаются **только** SG из той же сети, что и редактируемая SG
       (`networkId == "<netA>"`) — `sg-target-A` показывается, `sg-target-B` (другая сеть) **не**
       selectable / не показывается
**And** источник списка — `SecurityGroupService.List` (`GET /vpc/v1/securityGroups?projectId=<P>`) с
       клиентской фильтрацией по `networkId == <редактируемой SG networkId>`
**And** на табе сети «Группы безопасности» **нет** действия «Привязать» (зеркало сценария 17 — кнопка
       удалена).

---

## Группа G — Move (cross-project) guarded под network-bound SG

### Сценарий 19: SecurityGroup.Move (cross-project) пока SG привязана к сети → FAILED_PRECONDITION

**ID:** SG-NET-19-NEG-MOVE-FORBIDDEN

**Given** проект `P` и проект `Q` (оба seed-`projectId`)
**And** сеть `net-A` (`<netA>`) создана в `P`
**And** SG `sg-19` создана в `P`, привязана к `net-A` (`networkId == "<netA>"`, id `<sg19>`)

**When** клиент вызывает `SecurityGroupService/Move`
(REST `POST /vpc/v1/securityGroups/<sg19>:move`) с payload:
  - security_group_id = `<sg19>`
  - destination_project_id = `<Q>`

**Then** ответ — gRPC `FAILED_PRECONDITION` (Move активно отвергается, **не** «нетронут»)
**And** текст ошибки —
       `"security group cannot be moved between projects while bound to a network"`
**And** `GET /vpc/v1/securityGroups/<sg19>` — **без изменений**: `projectId == "<P>"`,
       `networkId == "<netA>"`, тот же `id` (SG не перемещена)
**And** в `vpc_outbox` **нет** события Move для `<sg19>`.

> Обоснование: `network_id` mandatory+immutable, а Network привязана к своему проекту. Cross-project Move
> сделал бы `network_id` SG ссылкой на сеть **чужого** (исходного) проекта → cross-project dangling-ref.
> Поэтому Move guarded на network-bound SG. В новой модели **все** SG привязаны к сети, поэтому Move
> практически запрещён для любой SG — но guard формулируется через «bound to a network» (точная,
> проверяемая причина), а не «SG нельзя двигать».
>
> Impl-note (net-new guard): `MoveSecurityGroupUseCase` сегодня = `{repo, projectClient, opsRepo}`
> (`move.go:24-32`, `NewMoveSecurityGroupUseCase(r Repo, projectClient ProjectClient, opsRepo …)`) и
> валидирует только `destination_project_id` + `checkMoveDestination`. Добавляется **guard**: после
> `repo.Reader → Get(cur)` проверить `cur.NetworkID != ""` → `FAILED_PRECONDITION` с указанным текстом,
> **до** создания Operation (sync fast-fail). Reader для SG уже есть (`move.go:46` `repo.Reader(ctx)` →
> `Get`), дополнительного network-reader не требуется (`network_id` лежит на самой SG-строке).
>
> Тесты: integration (`move_*integration_test.go`) — network-bound SG → `FAILED_PRECONDITION`,
> SG неизменна; + 1 newman negative `SG-NET-19-NEG-MOVE-FORBIDDEN`.
>
> Более широкий вопрос «должна ли SG вообще быть movable между проектами» (раз все SG network-bound) —
> **отдельный issue/redesign**, не KAC-243.

---

## Proto (`kacho-proto`)

**Изменение** (минимальное, точечное):

- `CreateSecurityGroupRequest.network_id` (поле 5) — **вернуть** `(required) = true` (buf.validate),
  убранный в `kacho-proto#8`. (Сейчас: `string network_id = 5;` без `required` — см.
  `security_group_service.proto:211-215` + комментарий «Optional: a security group may be created
  without being bound to a network».) Комментарий переписать под mandatory.
- `UpdateSecurityGroupRequest` — **НЕ** добавлять `network_id` (противоположно отброшенному драфту).
  Поле остаётся отсутствующим в request → unknown-field в mask → `INVALID_ARGUMENT` (сценарий 04).
- `SecurityGroup.network_id` (поле 7 на ресурсном сообщении) — без изменений (output-поле, заполняется
  в Get/List/Operation.response).

**Sequence (по графу зависимостей, workspace `CLAUDE.md` §«Кросс-репо»):**
1. `kacho-proto` — вернуть `required` + regen `gen/` (commit), `buf lint` зелёный. `buf breaking`:
   `(required)` — кастомная field-option `#101501` (buf.validate), **не** часть proto-wire и **не**
   proto3-`optional`, поэтому `buf breaking` это **не** флагует — прогон будет **зелёным**. Зафиксировать
   зелёный вывод `buf breaking` в PR-описании как **осознанное validation-tightening**, реверсирующее
   `kacho-proto#8` (который снял `required`). **buf.yaml `except`-entry НЕ добавляется** (не нужно — не
   breaking). Поведенческое следствие: клиенты, славшие пустой `network_id`, теперь получат отказ
   (`network_id required`, сценарий 01) — это и есть цель фичи.
2. `kacho-vpc` — Create требует `network_id` + same-network rule-валидация (Create/UpdateRules/UpdateRule,
   service-layer D3, sync D4) + Move guard под network-bound SG (D5) + **новая self-healing
   backfill-миграция `0004` (Go-миграция goose: backfill orphan-SG → per-project default-Network, затем
   `SET NOT NULL`; D6)**; `network_id` остаётся вне Update-mask.
3. `kacho-ui` — форма-required + rule-picker фильтр + удаление «Привязать» стаба.

---

## Definition of Done (KAC-243)

Sub-фича считается завершённой, когда **все** пункты выполнены (test-first, RED→GREEN, без TODO/tech-debt;
запреты #11/#12/#13):

1. **Proto (`kacho-proto`):** `(required)=true` возвращён на `CreateSecurityGroupRequest.network_id`;
   `network_id` **не** добавлен в `UpdateSecurityGroupRequest`; `buf lint` зелёный; `buf breaking`
   прогнан и **зелён** (custom field-option `#101501`, не wire) — зелёный вывод задокументирован в
   PR-описании как validation-tightening (реверт `kacho-proto#8`); **buf.yaml `except`-entry не нужен**;
   regen `gen/` закоммичен.
2. **Backend (`kacho-vpc`) — Create:** `network_id` обязателен (sync `INVALID_ARGUMENT` «`network_id
   required`» при пустом/отсутствии, сценарий 01) — reverts «optional network_id» ветку в `create.go`;
   existence-проверка сети — **sync fast-fail** `NOT_FOUND "Network %s not found"` (+ async/same-DB FK
   backstop, сценарий 03).
3. **Backend — immutability + Move guard:** `network_id` **не** в known-mask `validateSGUpdate` (остаётся
   `{name, description, labels, rule_specs}`) — пин как гарантия (сценарий 04); `applySGMask` не трогает
   `network_id` (full-PATCH silent-ignore, сценарий 05); нет RPC attach/detach/reassign (сценарий 06d).
   **Move guard (D5):** `MoveSecurityGroupUseCase` отвергает Move network-bound SG → `FAILED_PRECONDITION`
   «`security group cannot be moved between projects while bound to a network`», SG неизменна (сценарий 19).
4. **Backend — same-network rule validation (service-layer, D3):** SG-target rule
   (`oneof target = security_group_id`) валидируется на совпадение `network_id` target-SG и редактируемой
   SG — на **Create** (`rule_specs`), **UpdateRules** (`addition_rule_specs`), **UpdateRule** (смена target);
   **sync fast-fail** (D4). Cross-network → `INVALID_ARGUMENT` «`security group rule can only reference a
   security group in the same network`» + `BadRequest.field_violations` (сценарии 07/09/10); несуществующая
   target-SG → `INVALID_ARGUMENT` «`security group rule references a non-existent security group`» +
   `field_violations` (11) — **НЕ** `NOT_FOUND`/`wrapSGErr`; same-network → OK (08); CIDR/predefined — не
   затронуты (13). **`UpdateRulesUseCase`/`UpdateRuleUseCase` сейчас БЕЗ reader'а** — доинжектировать
   read-port (network_id редактируемой + target-SG) = net-new composition-root wiring (сценарии 09/10).
   Same-network — **service-layer-валидация (D3)**, без нормализованной rule-target-таблицы (это редизайн-эпик).
5. **Backend — self-healing миграция backfill (D6):** **новый** файл миграции `0004` (запрет #5 —
   `0001_initial.sql` не редактируем) — **Go-миграция goose** (`package migrations`,
   `goose.AddMigrationContext`, D6.1): backfill orphan-SG → per-project default-Network
   (`ids.NewID(ids.PrefixNetwork)`, `name='default'`, reuse существующей `default`-сети проекта; D6.2/D6.4),
   FK-порядок INSERT Network → UPDATE SG.network_id → `ALTER … SET NOT NULL` последним (D6.5),
   идемпотентно/re-runnable-safe (16c/16d), no-recursive-default-SG (D6.3 — `default_security_group_id=''`),
   FK `→ networks(id) ON DELETE RESTRICT` сохранён, после миграции ноль NULL/empty `network_id`
   (сценарии 15/16/16e). Миграция **не падает** на существующих данных (dev — без recreate, 16f);
   prod-backfill встроен (отдельный issue **не нужен**). DB-level same-network backstop в KAC-243 **не**
   делается (D3 — service-layer достаточно); `db-architect-reviewer` сохраняет PR-time veto на миграцию
   (Go-vs-SQL, idempotency, FK-порядок, reuse-критерий).
6. **Integration-тесты (`internal/repo/*integration_test.go`, testcontainers):** create-without-network
   reject (01), create-OK (02), network-notfound sync (03), update-mask-network reject (04), full-patch-ignore
   (05), same-network rule OK (08) + **cross-network rule reject RED→GREEN** на Create/UpdateRules/UpdateRule
   (07/09/10), rule-target-notfound `INVALID_ARGUMENT` (11), **concurrent target-delete (12, RED→GREEN,
   D3 dangling-ref/negative-исход)**, default-SG (14), **миграция-backfill (15/16, RED→GREEN): seed
   orphan-SG (network_id NULL) в проекте → прогнать `goose.Up` (миграция `0004`) → assert (a) все
   orphan-SG привязаны к default-Network проекта, (b) `SET NOT NULL` прошёл (ноль NULL), (c) default-Network
   создана, valid и `default_security_group_id=''` (no-recursive-SG), (d) проект без orphan-SG → лишней
   сети нет (16a/16b negative), (e) повторный backfill идемпотентен (16c), (f) коллизия `name='default'`
   → reuse (16d); до миграции тест RED («`SET NOT NULL` падает на NULL-строках» / orphan не привязаны),
   после — GREEN)**, **backfill-Network listable/valid через сервис (16e)**, **Move guard под network-bound
   SG → `FAILED_PRECONDITION` (19, RED→GREEN)**. Все зелёные; пара RED→GREEN показана в PR (cross-network
   reject + create-without-network reject + **migration-backfill** + Move-forbidden).
7. **Newman-кейсы (`tests/newman/cases/security-group.py` → `gen.py`):** минимум
   `SG-NET-02-CREATE-OK` (happy), `SG-NET-01-NEG-CREATE-NO-NETWORK` (sync InvalidArgument `network_id
   required`), `SG-NET-03-NEG-NETWORK-NOTFOUND` (sync NotFound), `SG-NET-04-NEG-UPDATE-MASK-NETWORK`
   (InvalidArgument), `SG-NET-07-NEG-RULE-CROSS-NETWORK-CREATE` (InvalidArgument + field_violations),
   `SG-NET-08-RULE-SAME-NETWORK-OK` (happy), `SG-NET-19-NEG-MOVE-FORBIDDEN` (FailedPrecondition);
   зарегистрированы в `CASES-INDEX.md` (+`REQ-*` при необходимости), `TEST-PLAN.md`, `RESULTS.md`.
   Существующие SG newman/OCC-кейсы — зелёные (regression). **Удалить/переписать** любые newman-кейсы
   отброшенного attach-контракта (если успели появиться).
8. **UI (`kacho-ui`):** форма Create — `network_id` required (preset+locked на табе сети; обязателен
   standalone, сценарий 17); rule-editor SG-target picker фильтрует по той же сети (18); **удалён** любой
   «Привязать» стаб; vitest-тесты на required-валидацию и picker-фильтр. Старый attach-контракт
   acceptance-файл удалён/архивирован (changelog §«История правок»).
9. **Vault trail:** обновлены `[[resources/vpc-securitygroup]]`:
   - `network_id` mandatory+immutable; FK NOT NULL; убрать «network_id nullable / unbound / folder-level
     SG» формулировки;
   - **исправить Gotcha** «Cross-SG references … валидируется на Update в пределах same DB» — она **stale/неверна
     сегодня** (cross-SG ref никак не валидировался). Заменить на новый инвариант: «SG-target rule
     (`security_group_id`) разрешён **только** в пределах той же Network; cross-network / non-existent target →
     `INVALID_ARGUMENT` (service-layer, D3); target-SG может стать dangling при удалении — переживается грациозно»;
   - **исправить OCC-заметку** «0 rows → `Aborted "security group was modified concurrently"`» — код на самом
     деле маппит OCC-конфликт в **`FAILED_PRECONDITION`** (`helpers.ErrFailedPrecondition` → `codes.FailedPrecondition`,
     `pg/security_group.go:271`, текст «SecurityGroup %s was modified concurrently, please retry»;
     `security_group_occ_integration_test.go` ждёт `ErrFailedPrecondition`). Поправить там, где затронуто.

   `[[rpc/vpc-securitygroup-service]]` (Create `network_id` required; Update known-mask без `network_id`;
   same-network rule-валидация на Create/UpdateRules/UpdateRule; Move guarded под network-bound SG →
   `FAILED_PRECONDITION`), `KAC/KAC-243.md` (создать; PR-ссылки, acceptance чек-лист, changelog
   attach→mandatory + **migration backfill (orphan-SG → per-project default-Network, Go-миграция goose)**).
   Same-network-инвариант + Move-guard + **self-healing backfill-миграция (D6, no-recursive-default-SG)** —
   отметить в `kacho-vpc/docs/architecture/07-known-divergences.md` как осознанное ограничение.
   Обновить `[[resources/vpc-network]]` — упомянуть, что миграция `0004` может создать `name='default'`
   Network в проектах с legacy orphan-SG (одноразово, не runtime-фича).
10. **CI** затронутых репо зелёный; никаких TODO/FIXME/skip в diff; никакого tech-debt (запреты #11/#12/#13).

---

## Design decisions (FIXED — резолв acceptance-reviewer, не open questions)

> Все 7 пунктов ниже **зафиксированы** ревьюером и являются обязательными дефолтами контракта (не
> «к обсуждению»). Каждый сценарий выше уже утверждает конкретный код/текст/путь по этим решениям.

**D1. Код отказа для cross-network SG-target rule И для несуществующей target-SG = `INVALID_ARGUMENT`
(один класс).** Оба случая — невалидный rule-spec, не состояние ресурса. Ошибка несётся через
`google.rpc.BadRequest.field_violations` (`field`, напр. `rule_specs[0].security_group_id` /
`addition_rule_specs[0].security_group_id` / `security_group_id`), **НЕ** через `NOT_FOUND`/`wrapSGErr`.
Тексты: cross-network = `"security group rule can only reference a security group in the same network"`;
non-existent = `"security group rule references a non-existent security group"` (сценарии 07/09/10/11).

**D2. Required-текст `network_id` = `"network_id required"`** (lower-case, без «is» — в одном ряду с
существующим `"project_id required"` в `create.go`, не `"... is required"`) (сценарий 01).

**D3. Same-network-проверка = service-layer-валидация ДОСТАТОЧНА** для KAC-243. Нормализованная
rule-target-таблица (`security_group_rule_targets`) / JSONB-триггер / DB-CHECK на `network_id`
в KAC-243 **не** вводятся. Обоснование (осознанный дизайн-выбор, **не** отложенный tech-debt): `network_id`
immutable (§B) → проверка `target.network_id == self.network_id` **не** TOCTOU-prone; единственная гонка —
удаление target-SG — переживается грациозно (dangling-ref) или ловится negative `INVALID_ARGUMENT`
(сценарий 12). Нормализованная rule-target-таблица + FK + network-CHECK = отдельный **редизайн-эпик**
(`2026-05-30-vpc-network-sg-routetable-redesign.md`). `db-architect-reviewer` сохраняет **PR-time veto**
на миграцию (если при ревью PR сочтёт DB-backstop необходимым — может потребовать).

**D4. Размещение = SYNC fast-fail + ASYNC backstop** — и для network-existence (Create, сценарий 03), и
для same-network rule-проверки (Create/UpdateRules/UpdateRule, 07/09/10). Sync-путь даёт клиенту
детерминированный код (`NOT_FOUND` / `INVALID_ARGUMENT`) без создания Operation; async-повтор + FK =
backstop на гонки. Формат-/id-валидация (`corevalidate.ResourceID`) — всегда sync.
**Impl-note:** `UpdateRulesUseCase` (`{repo, opsRepo}`, `update_rules.go:39-46`) и `UpdateRuleUseCase`
(`{repo, opsRepo}`, `update_rule.go:39-46`) **сегодня БЕЗ** SG/network-reader'а — для резолюции `network_id`
редактируемой SG + каждой target-SG нужно **доинжектировать read-port** (net-new composition-root wiring
в `cmd/<svc>/main.go`, по аналогии с `networkReader` у `CreateSecurityGroupUseCase`).

**D5. `Move` (cross-project) для network-bound SG = АКТИВНО ЗАПРЕЩЁН** → `FAILED_PRECONDITION`
`"security group cannot be moved between projects while bound to a network"` (сценарий 19, новый).
Требует guard в `MoveSecurityGroupUseCase` (sync, до Operation; SG-reader уже есть в `move.go`) +
integration-тест + 1 newman negative. Более широкий «должна ли SG вообще быть movable» — **отдельный issue**.

**D6. Миграция = self-healing backfill + `ALTER … SET NOT NULL`** (owner-mandated, **заменяет** прежний
fail-fast). В **новом** файле миграции `0004` (НЕ редактирование `0001_initial.sql`, запрет #5). Перед
`SET NOT NULL` миграция backfill-ит orphan-SG, чтобы не упасть (сценарии 15/16).

- **D6.1 — id-gen: Go-миграция goose (а НЕ pure-SQL/PLpgSQL).** Проверено по коду: migrator
  (`cmd/migrator/main.go` → `internal/apps/migrator/{runner,postgres,dialect}.go`) гоняет **goose
  v3.27.1** через `goose.SetBaseFS(migrations.FS)` + `goose.UpContext(ctx, db, ".")`; `internal/
  repo/integration_test.go` — то же (`goose.SetBaseFS(migrations.FS)` + `goose.Up(db, ".")`). Оба
  **импортируют** пакет `internal/migrations`. goose v3 поддерживает Go-миграции через
  `goose.AddMigrationContext(up, down)`, регистрируемые из `.go`-файла в `package migrations` (версия
  выводится из имени файла, напр. `0004_backfill_sg_default_network.go`); регистрация сливается с
  FS-обнаруженными SQL-миграциями по номеру. `ids.NewID` — pure-Go (`crypto/rand` + `encoding/binary`),
  импортируется из миграции без проблем. **Выбор (a) Go-миграция** — чисто: `up(ctx, tx *sql.Tx)`
  использует `ids.NewID(ids.PrefixNetwork)` + `tx.ExecContext` (INSERT Network → UPDATE SG → ALTER SET
  NOT NULL в одной транзакции goose). Вариант (b) PLpgSQL-энкодер crockford-base32 над
  `gen_random_uuid()` — **отвергнут**: дублирует `kacho-corelib/ids`, уродлив, расходится с
  `kacho-vpc/CLAUDE.md` §2 («id-generation crockford-base32 не реализуется в PL/pgSQL без портирования
  ids»). **Подтвердить с `db-architect-reviewer`**, что Go-миграция в `package migrations` — приемлемый
  паттерн (прецедента Go-миграций в репо пока нет — все 3 файла `.sql`); если ревьюер настаивает на
  pure-SQL, fallback = (b), но это явный downgrade.
- **D6.2 — что нужно default-Network.** Обязательные колонки: `id` (`enp…` через `ids.NewID`),
  `project_id`, `name` (`'default'`). Остальные — DB-defaults (`created_at=now()`, `description=''`,
  `labels='{}'`, `default_security_group_id=''`, `route_distinguisher=''`). Проверено по
  `0001_initial.sql:183-199`: ни одной NOT-NULL-без-default колонки сверх этих трёх.
- **D6.3 — no-recursive-default-SG.** Backfill вставляет Network в обход service-layer → inline
  default-SG creation (`network.go::doCreate`) НЕ срабатывает. default-Network остаётся с
  `default_security_group_id=''` без свежей default-SG; её SG = привязываемые orphan-SG. Рекурсивно
  создавать ещё одну default-SG **запрещено** (породит новую orphan-SG). `networks.default_security_
  group_id NOT NULL DEFAULT ''` допускает пустую строку (схема подтверждает).
- **D6.4 — scope = ОДНОРАЗОВЫЙ migration-backfill, НЕ постоянная фича.** «для аккаунтов» = backfill
  итерирует `DISTINCT project_id` среди orphan-SG **в пределах `kacho_vpc`** (запрет #8 — kacho-vpc не
  перечисляет IAM-аккаунты cross-DB; `project_id` orphan-SG берётся из самой таблицы `security_groups`).
  НЕ авто-создание default-network на каждый новый проект (флаг в §«Out of scope»; если владелец хочет
  постоянную фичу — отдельный эпик).
- **D6.5 — FK-порядок + идемпотентность + транзакция.** INSERT Network до UPDATE SG.network_id; SET NOT
  NULL последним. Идемпотентно: reuse `name='default'`-сети проекта (`ON CONFLICT (project_id, name) DO
  NOTHING` + re-SELECT id, либо upsert-RETURNING), `UPDATE … WHERE network_id IS NULL` повторно
  затрагивает 0 строк (сценарии 16c/16d). goose выполняет up в одной транзакции (Postgres dialect).
- **D6.6 — dev/prod.** Dev: миграция применяется на существующей БД **без** recreate и не падает
  (сценарий 16f). Prod: тот же self-healing backfill сработает, когда появится prod — **отдельный
  prod-backfill issue больше НЕ нужен** (backfill встроен).
- `db-architect-reviewer` сохраняет **PR-time veto** на миграцию (Go-vs-SQL подход, idempotency,
  FK-порядок, reuse-критерий — на ревью).

**D7. `buf breaking` на возврат `(required)` = НЕ breaking → прогон зелёный.** `(required)` — кастомная
field-option `#101501` (buf.validate), не часть proto-wire и не proto3-`optional`. Зелёный вывод
`buf breaking` документируется в PR как осознанное validation-tightening, реверсирующее `kacho-proto#8`.
**buf.yaml `except`-entry не добавляется.**
