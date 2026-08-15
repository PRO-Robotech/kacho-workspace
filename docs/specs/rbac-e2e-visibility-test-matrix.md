# RBAC explicit-model (Design-B verb-bearing) — live-E2E visibility test matrix (UI / Playwright)

> Тип: **DOC (тест-матрица)**, НЕ исполнение. Источник истины модели —
> `docs/specs/rbac-explicit-model-2026-acceptance.md` (APPROVED 2026-06-24, D-1..D-18).
> Цель: исчерпывающе проверить authz-видимость explicit-RBAC на стенде **fe3455** через
> UI/Playwright — по каждому модулю → ресурсу → list/detail → дочернему ресурсу в detail.
> Ground-truth поверхности сверен с кодом 2026-06-25:
> `kacho-ui/src/lib/resource-registry.tsx` (REGISTRY), `…/src/components/ResourceShell.tsx`
> (related-табы), `…/src/components/resource-detail-extensions.tsx` (extraTabs / privileges /
> rules / routes / sg-rules / nic / ipam), `…/src/lib/service-modules.tsx` (sidebar),
> `kacho-iam/internal/authzguard/read_authz.go` + `…/authzguard/cluster_admin_shortcircuit.go`
> + `…/internal/authzmap/fga_types.go` (verb-bearing enforcement, short-circuit).

---

## 0. Модель энфорса (что именно проверяем) — норматив

| Понятие | Семантика на fe3455 (Design-B) |
|---|---|
| **AccessBinding** | `(subjects[], role, scope{CLUSTER(=GLOBAL)/ACCOUNT/PROJECT}+ref)`. Thin — селекция объектов целиком в `role.rules`, поля target/selector сняты с binding (F-51). |
| **Role** | `rules[] = [{module, resources[], verbs[], selector-arm}]`; arm = **all** (ARM_ANCHOR) \| **names[]** (ARM_NAMES) \| **labels{}** (ARM_LABELS). |
| **`v_list`** | Видимость объекта в **списке/селекторе** (list-view, related child-таблица, header-селектор Account/Project, ref-dropdown). |
| **`v_get`** | Доступ к **контенту**: detail-overview, дочерние табы внутри detail, JSON-таб, чтение полей. **`v_list` ≠ `v_get`** — развязаны. |
| **`v_create/v_update/v_delete`** | Мутации (кнопки «Создать»/«Редактировать»/«Удалить»/revoke). |
| **account/project — verb-bearing** | D-6: `account:<id># v_get/v_list/...`, грант `iam.account.list` даёт видимость account в шапке/списке без доступа к его контенту. tier admin/editor/viewer ОСТАЁТСЯ только как write-authz-якорь (D-7), доступа к контенту НЕ даёт. |
| **cluster-admin short-circuit** | D-9/КФ-2: `cluster:cluster_kacho_root # system_admin @ subj` → ALLOW на любом Check (read+write) без per-object tuple. Единственное легальное «GLOBAL+all». |
| **owner** | Системная роль (D-8) `*.*.* @ ACCOUNT:<A>`, auto-binding на `Account.Create`, `deletion_protection=true`. Per-object материализация на сам account + forward на содержимое. |
| **labels-селектор** | Грант материализуется ТОЛЬКО на ресурсы с матчащей меткой (напр. `foo=bar`); смена метки → fall-out → tuple снимается (≤2s reconcile). |
| **names-селектор** | Грант на конкретные id/имена. |
| **GLOBAL+all для НЕ-cluster-admin роли** | sync `INVALID_ARGUMENT` (A-05). UI-гард: `access-bindings-global-guard` (alert «GLOBAL допустим только для роли cluster-admin»). |

### Инварианты-баги (что НЕ должно происходить — каждый = провал теста)

- **INV-1** `v_list`-only грант → контент (detail/child) ДОЛЖЕН быть закрыт (403→UI 404/empty). Видимый контент без `v_get` = БАГ.
- **INV-2** ресурс без матчащей метки (`foo=bar` отсутствует) → НЕ виден в списке/селекторе/dropdown. Виден = БАГ.
- **INV-3** cross-account ресурс (вне scope гранта) → НЕ виден тест-юзеру (кроме cluster-admin). Виден = БАГ (cross-tenant leak).
- **INV-4** `v_get` на родителе (напр. network) НЕ даёт автоматического доступа к дочерним (subnet/SG/RT) без отдельного гранта на дочерний тип (D-2 — нет каскада).
- **INV-5** account/project tier admin (write-authz) сам по себе НЕ открывает контент аккаунта/проекта (D-7).
- **INV-6** смена метки, выводящая ресурс из-под labels-селектора → доступ снят ≤2s; ресурс исчезает из списка/detail.
- **INV-7** revoke binding ИЛИ role-rule изменение → все материализованные tuple сняты; ресурс пропадает у субъекта.
- **INV-8** GLOBAL+all для обычной роли → отклонено sync, binding/tuple не создаются.

### Конвенция чтения колонок ожиданий

- **HTTP** — код REST-ответа api-gateway за UI-действием (`200` allow / `403` denied-by-authz / `404` hide-existence для detail Get / `400` INVALID_ARGUMENT).
- **Список (v_list)** — виден ли ресурс строкой в list-view / related-child-таблице / селекторе.
- **Detail/контент (v_get)** — открывается ли detail-overview + дочерние табы.
- **Мутация (v_*)** — проходит ли create/update/delete/revoke.

> **Важно по UI-семантике 404 vs 403:** detail Get без `v_get` маппится в **NotFound (404)** (hide-existence,
> `read_authz.go` — «never PermissionDenied, no enumeration leak») → UI показывает ErrorResult/«не найдено»,
> а НЕ «доступ запрещён». List/related-таблицы фильтруются (объект просто отсутствует, без ошибки).

---

## 0.1 Subject-delivery dimension (3 канала) — норматив

Тот же грант `(role, scope, selector)` доставляется субъекту **тремя разными каналами**.
Результирующая видимость/доступ ОБЯЗАНЫ совпадать побайтово (visible-set + access-set) —
расхождение = БАГ. Различается только **принципал**, чей токен несёт запрос.

| Канал | `AccessBinding.subjects[]` | Принципал на проводе | FGA-subject в материализованном tuple |
|---|---|---|---|
| **user-direct** (baseline) | `[usr<T-USER>]` (`subject_type=user`) | `kacho_principal_type=user`, `sub=usr<T-USER>` | `user:usr<T-USER>` |
| **group-member** | `[grp<G>]` (`subject_type=group`), T-USER ∈ члены G | тот же user-JWT T-USER | userset `group:grp<G>#member` (binding-tuple) **+** member-tuple `group:grp<G>#member @ user:usr<T-USER>` (резолвит члена) |
| **SA-token** | `[sva<SA>]` (`subject_type=service_account`) | `kacho_principal_type=service_account`, `sub=sva<SA>` | `service_account:sva<SA>` |

Ground-truth (сверено 2026-06-25):
- Subject FGA-ref — `kacho-iam/internal/domain/subject.go::FGASubjectRef`: `user→user:<id>`,
  `service_account→service_account:<id>`, **`group→group:<id>#member`** (userset, generic-тип
  `group`, **НЕ** `iam_group`). FGA-модель `kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga`:
  `type group → define member: [user, service_account, …]`; каждый `v_*`/tier на ресурсных типах
  принимает `group#member` напрямую (`[user, service_account, group#member]`) → член группы
  наследует доступ через `group#member`-userset.
- Group membership зеркалится в FGA транзакционно: `group/add_member.go` / `remove_member.go`
  co-commit'ят `group:grp<G>#member @ <user|service_account>:<id>` в той же writer-tx, что
  `INSERT/DELETE group_members` (`resources/iam-group.md` §«FGA membership mirror»). **Тип объекта
  = `group`, не `iam_group`** (member-tuple на `iam_group` НЕ резолвит binding userset — verified).
- Принципал из контекста — `corelib operations.PrincipalFromContext`; FGA-subject строится
  `authzguard.SubjectFromPrincipal` (fail-closed на unknown type: НЕ default'ит в `user:`).
- Gateway маппинг принципала — `kacho-api-gateway/internal/middleware/subject_extractor.go`:
  `ext_claims.kacho_principal_type` (`user`/`service_account`) + `kacho_principal_id` → FGA-subject.
- SA-token acquisition — `SAKeyService.IssueSAKey` (Class-A static key) возвращает
  `{client_id, private_key_pem, public_key_pem, algorithm:"ES256", key_id}` (НЕ client_secret);
  caller подписывает `private_key_jwt`-assertion (RFC 7521/7523) → Hydra `/oauth2/token`
  `grant_type=client_credentials` → access_token; token_hook augment'ит JWT
  `kacho_principal_type=service_account`, `sub=sva<SA>` (`tests/newman/cases/authz-sa-apitoken.py`
  модель 5). Revoke ключа → последующий dozвon `401 UNAUTHENTICATED` (authn-fail раньше authz).

### INV-9 — subject-channel equivalence (новый инвариант)

- **INV-9** Для одного и того же `(role, scope, selector)` visible-set и access-set **идентичны**
  по всем трём каналам (user-direct ≡ group-member ≡ SA-token). Любое расхождение (член группы
  видит МЕНЬШЕ/БОЛЬШЕ, чем user-direct; SA видит иначе) = БАГ. Принципал отличается, эффективный
  доступ — нет.

### Как прогоняется каждый канал

- **newman** (kacho-iam/kacho-test e2e): на один и тот же набор фикстур выдаётся binding на
  `grp<G>` / `sva<SA>`; запрос выполняется под нужным принципалом (user-JWT vs SA-token из Hydra
  client_credentials); visible-set сверяется с user-direct baseline (тот же assert-набор, другой
  `Step.auth`). Channel-equivalence = diff(visible-set) пуст.
- **Playwright** (kacho-ui e2e):
  - **user-direct** и **group-member** прогоняются ОДНОЙ браузер-сессией T-USER. Членство в группе
    прозрачно для UI: тот же логин, доступ шире (через `group#member`-userset). Различие каналов —
    в том, КАК выдан binding (на usr vs на grp), не в том, как логинится UI.
  - **SA-token** прогоняется ВНУТРИ Playwright-теста через **authenticated API request-context** с
    SA-bearer-токеном (у SA нет браузер-логина — это non-human principal). Это НЕ второй
    браузер-вход, а request-context API-проверки (`request.newContext({ extraHTTPHeaders:
    { Authorization: 'Bearer <saToken>' }})`): тот же visible-set сверяется на уровне REST-ответов
    api-gateway, без DOM. (Документировано явно для автора UI-репо: SA-leg = API request-context,
    не UI-сессия.)

---

## 1. Полная карта поверхности (модуль → ресурс → list / detail / дочерние-в-detail)

Сверено с REGISTRY + `related[]` (RelatedTable-табы) + DETAIL_EXTENSIONS `extraTabs`/`childCreate`.
«Дочерние в detail» = вкладки внутри detail-страницы (related child-таблицы + доменные extra-табы).

### IAM (sidebar «Identity and Access Management», `/iam/*`)

| Ресурс | route / apiPath | scope | Дочерние ресурсы/табы в detail |
|---|---|---|---|
| **account** | `accounts` `/iam/v1/accounts` | global | related: **Проекты** (projects/account_id), **Сервисные аккаунты** (service-accounts/account_id), **Группы** (groups/account_id) |
| **project** | `projects` `/iam/v1/projects` | account | (overview-only; drill → VPC dashboard через headerAction; нет related-табов) |
| **service-account** | `service-accounts` `/iam/v1/serviceAccounts` | account | extraTab **Привилегии** (privileges → AccessBinding с subject=SA; childCreate) |
| **user** | `users` `/iam/v1/users` | global | extraTab **Привилегии** (privileges → AccessBinding subject=user) |
| **group** | `groups` `/iam/v1/groups` | account | extraTab **Привилегии** (privileges → AccessBinding subject=group); (членство — overview) |
| **role** | `roles` `/iam/v1/roles` | account | overview: tier system/custom + **Правила** (rulesView из role.rules); edit/delete скрыты для is_system |
| **access-binding** | `access-bindings` `/iam/v1/accessBindings` | account | overview: subjects[] + роль + ресурс + scope + защита; список — bespoke 3-view (byScope/bySubject/byAccount), нет flat-List |

### VPC (sidebar «Virtual Private Cloud», `/projects/:pid/vpc/*`)

| Ресурс | route / apiPath | scope | Дочерние ресурсы/табы в detail |
|---|---|---|---|
| **network** | `networks` `/vpc/v1/networks` | project | related: **Подсети** (subnets/network_id), **Таблицы маршрутов** (route-tables/network_id), **Группы безопасности** (security-groups/network_id); + JSON(internal) |
| **subnet** | `subnets` `/vpc/v1/subnets` | project | related: **IP-адреса** (addresses/internal_ipv4_address.subnet_id ∪ internal_ipv6_address.subnet_id) |
| **address** | `addresses` `/vpc/v1/addresses` | project | overview-only (потребители used_by) |
| **route-table** | `route-tables` `/vpc/v1/routeTables` | project | extraTab **Маршруты** (RoutesPanel из static_routes) |
| **security-group** | `security-groups` `/vpc/v1/securityGroups` | project | extraTab **Правила** (SgRulesPanel из rules) |
| **network-interface** | `network-interfaces` `/vpc/v1/networkInterfaces` | project | overview (subnet/MAC/v4/v6/SG/used_by); + JSON(internal) |
| **gateway** | `gateways` `/vpc/v1/gateways` | project | overview-only |

### Compute (sidebar «Compute Cloud», `/projects/:pid/compute/*`)

| Ресурс | route / apiPath | scope | Дочерние ресурсы/табы в detail |
|---|---|---|---|
| **instance** | `compute-instances` `/compute/v1/instances` | project | extraTabs: **NIC/сеть**, **power** (start/stop/restart), boot-disk/диски ref; overview NIC primary IP |
| **disk** | `compute-disks` `/compute/v1/disks` | project | overview (источник image/snapshot, привязка к ВМ instance_ids) |
| **image** | `compute-images` `/compute/v1/images` | project | overview (источник disk/snapshot/image/uri) |
| **snapshot** | `compute-snapshots` `/compute/v1/snapshots` | project | overview (source_disk_id) |
| **disk-type** | `disk-types` `/compute/v1/diskTypes` | global | read-only справочник (нет detail-мутаций) |

### NLB (sidebar «Network Load Balancer», `/projects/:pid/nlb/*`)

| Ресурс | route / apiPath | scope | Дочерние ресурсы/табы в detail |
|---|---|---|---|
| **load-balancer** | `load-balancers` `/nlb/v1/networkLoadBalancers` | project | extraTabs: listeners-ref, target-attachment; overview (region/status/VIP) |
| **listener** | `listeners` `/nlb/v1/listeners` | project | overview (load_balancer_id, protocol, port) |
| **target-group** | `target-groups` `/nlb/v1/targetGroups` | project | extraTab **Targets** (TargetGroup targets/attach); overview (health-check) |

### Geo / Admin (sidebar «Администрирование», `/system/*`; internal-only поверхность)

| Ресурс | route / apiPath | scope | Примечание |
|---|---|---|---|
| **region** | `regions` `/geo/v1/regions` | global | admin; read public, CRUD internal mux |
| **zone** | `zones` `/geo/v1/zones` | global | admin; read public, CRUD internal mux |
| **address-pool** | `address-pools` `/vpc/v1/addressPools` | global | admin Internal*; extraTabs: **Использование (IPAM)**, **Адреса** |

> **Объём поверхности:** **5 модулей** (IAM/VPC/Compute/NLB/Admin), **25 ресурсов**,
> **list-view × 25** + **detail-view × 23** (disk-type/region/zone — справочники без полноценного detail-мутирования) +
> **дочерних-в-detail ~28** (related child-таблицы + extra-табы privileges/rules/routes/sg-rules/nic/ipam/targets/members).

---

## 2. Подготовка стенда (Phase 0 — фикстуры владельца, выполнить ДО Playwright-прогона)

> Выполняется через UI/API под cluster-admin (или owner ws@dobry-kot.ru). Playwright Phase A/B/C
> работает уже из-под **тест-юзера**. Каждый шаг — конкретное действие + проверяемый результат.

| # | Действие (актор) | Ожидание |
|---|---|---|
| P0-1 | cluster-admin создаёт **тест-аккаунт** `T-ACC` (или используем `accpj09931vpw14js8zz` ws@dobry-kot.ru) | `Account.Create` → Operation done; owner-binding авто (deletion_protection=true) |
| P0-2 | создать **тест-юзера** `T-USER` (email) и **инвайтнуть** в аккаунт `accpj09931vpw14js8zz` (User → «Пригласить») | invite PENDING → ACTIVE после первого входа T-USER |
| P0-3 | В `accpj09931vpw14js8zz` создать **по 2 ресурса каждого типа**: один с меткой `foo=bar` (далее «**M+**»), один без меток (далее «**M−**»). Для дочерних — те же 2 варианта на каждый тип-ребёнок (subnet/SG/RT под network; address под subnet; SA/group/role под account; и т.д.) | Все ресурсы созданы; `RegisterResource` отправлен (видимы в `resource_mirror`) |
| P0-4 | Создать роль **`test-account`** (custom, account-scoped): rules = `[{module:iam, resources:[account,project,user,group,service-account,role,access-binding], verbs:[get,list], selector: labels{foo=bar}}]` | роль создана; rulesView показывает ARM_LABELS `foo=bar` |
| P0-5 | Создать роль **`test-project`** (custom): rules = по одному правилу на каждый модуль (vpc/compute/nlb) × все ресурсы, verbs:[get,list], selector: labels{foo=bar} | роль создана; видна в RulesEditor |
| P0-6 | Выдать T-USER **binding** `(T-USER, test-account, ACCOUNT:accpj09931vpw14js8zz)` и `(T-USER, test-project, PROJECT:<тест-проект M+>)` | оба Operation done; tuple материализованы (≤2s reconcile для labels) |
| P0-7 | Создать второй аккаунт `T-ACC2` с ресурсами (для cross-account INV-3) — T-USER в него НЕ инвайчен | ресурсы существуют, T-USER не член |
| P0-8 | Залогиниться Playwright-сессией под **T-USER** (отдельный browser-context, свой JWT) | header показывает T-USER; селектор Account показывает только доступные |

### Phase 0b — фикстуры subject-delivery (для INV-9, выполнить ДО channel-прогона)

> Те же роли `test-account`/`test-project` (и Phase B `r-label`/`r-name`) **переиспользуются** —
> различается ТОЛЬКО `binding.subjects[]` на канал. Ресурсы M+/M−/T+/T− те же.

| # | Действие (актор) | Ожидание |
|---|---|---|
| P0-9 | Создать **группу `T-GROUP`** в `accpj09931vpw14js8zz` (`Group.Create`) | Operation done; группа существует, FGA `iam_group:<G>#account@account:<acc>` |
| P0-10 | `Group.AddMember(T-GROUP, member_type=user, member_id=usr<T-USER>)` | Operation done; co-commit member-tuple `group:grp<G>#member @ user:usr<T-USER>` (та же writer-tx, что INSERT group_members) |
| P0-11 | Создать **service-account `T-SA`** в том же аккаунте (`ServiceAccount.Create`) | Operation done; `sva<SA>` существует |
| P0-12 | `SAKeyService.IssueSAKey(T-SA)` → получить `{client_id, private_key_pem, key_id, algorithm:ES256}`; подписать `private_key_jwt`-assertion → Hydra `/oauth2/token` `grant_type=client_credentials` → access_token (**T-SA-TOKEN**) | issue Operation done; обмен на Hydra access_token успешен; JWT несёт `kacho_principal_type=service_account`, `sub=sva<SA>` |
| P0-13 | (опц., group-of-SA sub-case) Создать вторую группу `T-GROUP-SA`, `AddMember(member_type=service_account, member_id=sva<SA>)` | Operation done; member-tuple `group:grp<G2>#member @ service_account:sva<SA>`. **Optional** — основной group-канал = group-of-user |

> Примечание по `verbs:[get,list]`: это даёт `v_get` **и** `v_list` → ресурс M+ виден в списке **и** контент открыт.
> Чтобы изолированно проверить INV-1 (`v_list`-only → контент закрыт), Phase A добавляет вариант роли `verbs:[list]`
> (см. A-кейсы с пометкой «v_list-only»).

### Channel-replication rule (INV-9) — как избежать триплицирования матрицы

> Каждый **grant-bearing** кейс Phase A/B/C прогоняется **трижды** — по одному разу на канал
> (user-direct / group-member / SA-token) — выдачей того же `(role, scope, selector)` соответственно
> на `usr<T-USER>` / `grp<T-GROUP>` / `sva<T-SA>`, и INV-9 утверждает идентичный исход (visible-set +
> access-set). Матрица не дублируется построчно: вместо ×3 строк — единый прогон фиксированного набора
> A/B/C под тремя `binding.subjects[]` + сверка diff'а. Negative/INV-кейсы (M−, cross-account, GLOBAL+all),
> не зависящие от субъекта, прогоняются один раз на baseline-канале.
> Ниже — **только канал-специфичные delta-кейсы**, которые имеют смысл лишь per-channel.

---

## Фаза A — `foo=bar` видимость (позитив + негатив по каждому ресурсу/уровню)

> Актор: **T-USER**. Грант: `test-account`/`test-project` с `verbs:[get,list], selector labels{foo=bar}`.
> Каждая строка = шаг Playwright: навигация → ожидание видимости.
> Колонки: **M+ list** (виден ли ресурс с foo=bar в списке) / **M+ detail** (открыт ли контент) /
> **M− list** (виден ли ресурс БЕЗ метки — должно быть **НЕТ**, negative) / **дочерние M+/M−**.

### A.1 IAM — account / project / дочерние account

| ID | Шаг (T-USER, Playwright) | Ожидание (HTTP · видимость) | INV |
|---|---|---|---|
| A-IAM-01 | GET `/iam/accounts` (list-view) | `accpj09931vpw14js8zz` (M+, foo=bar) **виден** строкой (`200`, v_list). Account без foo=bar — **НЕ виден** | INV-2 |
| A-IAM-02 | Клик в account M+ → detail overview | `200` (v_get) — overview раскрыт | — |
| A-IAM-03 | Открыть в account M+ таб **Проекты** | видны ТОЛЬКО проекты с foo=bar; M− проект отсутствует | INV-2/INV-4 |
| A-IAM-04 | Таб **Сервисные аккаунты** в account M+ | SA с foo=bar виден; SA без метки — нет | INV-2 |
| A-IAM-05 | Таб **Группы** в account M+ | группа foo=bar видна; без метки — нет | INV-2 |
| A-IAM-06 | GET detail account **M−** (прямой URL `/iam/accounts/<M−id>`) | `404` (hide-existence) — контент НЕ открыт | INV-1/INV-2 |
| A-IAM-07 | GET `/iam/projects` (list, выбран accpj09931vpw14js8zz в шапке) | project M+ виден; project M− — нет | INV-2 |
| A-IAM-08 | detail project M+ → overview | `200` v_get | — |
| A-IAM-09 | detail project **M−** (прямой URL) | `404` — закрыт | INV-1/INV-2 |
| A-IAM-10 | **v_list-only:** перевыдать роль `verbs:[list]` (без get) → list account M+ | M+ виден в списке (`200` v_list)… | — |
| A-IAM-11 | …клик в M+ detail при v_list-only | **`404`/закрыт** (нет v_get) — контент НЕ должен открыться | **INV-1** |

### A.2 IAM — user / service-account / group / role / access-binding (детали + privileges)

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| A-IAM-12 | list `/iam/users` | user с foo=bar виден; без — нет | INV-2 |
| A-IAM-13 | detail user M+ → таб **Привилегии** | privileges-таблица (его bindings) — `200` v_get | — |
| A-IAM-14 | detail user M− | `404` | INV-1 |
| A-IAM-15 | list `/iam/service-accounts` (acc выбран) | SA foo=bar виден; M− нет | INV-2 |
| A-IAM-16 | detail SA M+ → **Привилегии** | `200` v_get | — |
| A-IAM-17 | list `/iam/groups` | группа foo=bar видна; M− нет | INV-2 |
| A-IAM-18 | detail group M+ → **Привилегии** + членство (overview) | `200` v_get | — |
| A-IAM-19 | list `/iam/roles` | роль foo=bar видна; M− нет (custom-роли с/без метки) | INV-2 |
| A-IAM-20 | detail role M+ → **Правила** (rulesView) | `200` v_get; rules видны | — |
| A-IAM-21 | list access-bindings (byScope=accpj09931vpw14js8zz) | bindings на foo=bar-ресурсы видны; cross-account binding — нет | INV-2/INV-3 |
| A-IAM-22 | detail access-binding M+ | `200` v_get; subjects/role/scope раскрыты | — |

### A.3 VPC — network + дочерние (subnet/RT/SG) + остальные

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| A-VPC-01 | list `/projects/<P+>/vpc/networks` | network foo=bar виден; network M− — НЕ виден | INV-2 |
| A-VPC-02 | detail network M+ → overview | `200` v_get | — |
| A-VPC-03 | network M+ → таб **Подсети** | subnet foo=bar виден; subnet M− нет | INV-2/INV-4 |
| A-VPC-04 | network M+ → таб **Таблицы маршрутов** | RT foo=bar виден; M− нет | INV-2/INV-4 |
| A-VPC-05 | network M+ → таб **Группы безопасности** | SG foo=bar видна; M− нет | INV-2/INV-4 |
| A-VPC-06 | detail network **M−** (прямой URL) | `404` — закрыт | INV-1/INV-2 |
| A-VPC-07 | **INV-4 каскад:** дать только `vpc.network.get foo=bar` (НЕ subnet) → network M+ детали | network открыт, но таб **Подсети** ПУСТ (нет гранта на subnet) | **INV-4** |
| A-VPC-08 | list subnets (project) | subnet foo=bar виден; M− нет | INV-2 |
| A-VPC-09 | detail subnet M+ → таб **IP-адреса** | address foo=bar виден; M− нет | INV-2/INV-4 |
| A-VPC-10 | detail subnet M− | `404` | INV-1 |
| A-VPC-11 | list addresses; detail address M+ | M+ виден+открыт; M− не виден, detail `404` | INV-1/INV-2 |
| A-VPC-12 | list route-tables; detail RT M+ → таб **Маршруты** | M+ открыт, routes видны; M− `404` | INV-1/INV-2 |
| A-VPC-13 | list security-groups; detail SG M+ → таб **Правила** | M+ открыт, sg-rules видны; M− `404` | INV-1/INV-2 |
| A-VPC-14 | list network-interfaces; detail NIC M+ | M+ открыт (subnet/MAC/SG); M− `404` | INV-1/INV-2 |
| A-VPC-15 | list gateways; detail gateway M+ | M+ открыт; M− `404` | INV-1/INV-2 |
| A-VPC-16 | **v_list-only NIC:** роль `vpc.network-interface.list foo=bar` → list виден, detail клик | detail **`404`** (нет v_get) | **INV-1** |
| A-VPC-17 | JSON(internal) таб network M+ | при v_get открыт; инфра-поля только в internal-проекции | — |

### A.4 Compute — instance + дочерние (disks/nic/power) + остальные

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| A-CMP-01 | list `/projects/<P+>/compute/instances` | instance foo=bar виден; M− нет | INV-2 |
| A-CMP-02 | detail instance M+ → overview | `200` v_get | — |
| A-CMP-03 | instance M+ → таб **NIC/сеть** | NIC info виден; (boot-disk ref) | INV-4 (диск виден только при гранте на disk) |
| A-CMP-04 | instance M+ → power-таб (start/stop/restart) — только просмотр | кнопки видны (v_get); мутация — Phase B | — |
| A-CMP-05 | detail instance M− | `404` | INV-1/INV-2 |
| A-CMP-06 | list disks; detail disk M+ | M+ открыт (источник, привязка к ВМ); M− `404` | INV-1/INV-2 |
| A-CMP-07 | **INV-4:** instance foo=bar открыт, но его boot-disk БЕЗ foo=bar | ссылка на disk есть, но клик → disk detail `404` (нет гранта на этот disk) | **INV-4** |
| A-CMP-08 | list images; detail image M+ | M+ открыт; M− `404` | INV-1/INV-2 |
| A-CMP-09 | list snapshots; detail snapshot M+ | M+ открыт; M− `404` | INV-1/INV-2 |
| A-CMP-10 | list disk-types (справочник) | виден всем с floor-грантом (read-only ref) — задокументировать фактическое поведение | — |

### A.5 NLB — load-balancer + listeners/target-groups/targets

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| A-NLB-01 | list `/projects/<P+>/nlb/load-balancers` | LB foo=bar виден; M− нет | INV-2 |
| A-NLB-02 | detail LB M+ → overview + listeners-ref / target-attach табы | `200` v_get | — |
| A-NLB-03 | detail LB M− | `404` | INV-1/INV-2 |
| A-NLB-04 | list listeners; detail listener M+ | M+ открыт; M− `404` | INV-1/INV-2 |
| A-NLB-05 | list target-groups; detail TG M+ → таб **Targets** | M+ открыт, targets видны; M− `404` | INV-1/INV-2 |
| A-NLB-06 | **INV-4:** LB foo=bar открыт, listener БЕЗ foo=bar | listener в табе НЕ виден / detail `404` | **INV-4** |

### A.6 Admin/Geo — region / zone / address-pool

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| A-ADM-01 | T-USER открывает `/system/regions` | admin-поверхность: без admin-гранта → пусто/403; задокументировать (T-USER не admin) | INV-3/INV-5 |
| A-ADM-02 | `/system/zones` | то же — region/zone admin-CRUD скрыт от обычного субъекта | INV-3 |
| A-ADM-03 | `/system/address-pools` (Internal*) | НЕ доступно T-USER (internal-only, admin); виден = БАГ (ban #6 на UI-поверхности) | INV-3 |

### A.7 Cross-account (INV-3 — глобальный negative)

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| A-XACC-01 | T-USER переключает header-Account-селектор | `T-ACC2` (где T-USER не член) **НЕ** в списке селектора | **INV-3** |
| A-XACC-02 | Прямой URL на ресурс из `T-ACC2` (любой тип, даже с foo=bar) | `404` — cross-account невидим (foo=bar в чужом аккаунте не материализует tuple для T-USER) | **INV-3** |
| A-XACC-03 | list любого типа с выбранным своим аккаунтом | в результате нет ни одной строки из `T-ACC2` | **INV-3** |

---

## Фаза B — `test=treska` точечные гранты × scope-тип × CRUD (Role И Binding)

> Цель: проверить **3 операции (create/modify/delete)** для **роли И биндинга** при разных типах
> селектора/scope с меткой `test=treska`. Актор мутаций-настройки — cluster-admin/owner; проверка
> результата гранта — из-под T-USER. Перед B: пометить отдельный набор ресурсов `test=treska` (**T+**),
> остальные без неё (**T−**).

### B.1 Матрица Role CRUD × selector/scope (ожидание материализации и видимости у субъекта)

> Для каждого модуля/ресурса × scope-тип создаём роль с правилом на `test=treska` (by-label),
> by-name (конкретный T+ id), global. После Role-операции — re-check видимости у T-USER (через его binding).

| ID | Role-операция | selector / scope | Ожидание | INV |
|---|---|---|---|---|
| B-ROLE-01 | **Role.Create** `r-label` rules=`[{<mod>.<res>, get,list, labels{test=treska}}]` @ account/project binding | by-label / PROJECT | `200` Operation done; reconcile ≤2s → T+ виден у T-USER, T− нет | INV-2 |
| B-ROLE-02 | **Role.Create** `r-name` rules=`[{<mod>.<res>, get,list, names:[<T+id>]}]` | by-name / PROJECT | `200`; ровно `<T+id>` виден; другой T+ (вне names) — нет | INV-2 |
| B-ROLE-03 | **Role.Create** `r-global-name` rules=`names:[...]` или `labels{test=treska}` @ GLOBAL | global+names/labels | `200` (A-05b легально); материализация cluster-wide по матч-объектам | — |
| B-ROLE-04 | **Role.Create** `r-global-all` rules=`selector all` @ GLOBAL, роль НЕ cluster-admin | global+all | **`400` INVALID_ARGUMENT**; UI-гард `access-bindings-global-guard`; tuple/binding не создаются | **INV-8** |
| B-ROLE-05 | **Role.Modify** `r-label`: убрать ресурс из rules ИЛИ сменить arm на names | — | `200`; diff → tuple на убранные ресурсы сняты; видимость у T-USER пересчитана | INV-7 |
| B-ROLE-06 | **Role.Modify** `r-name`: расширить names ещё одним T+ | — | `200`; новый T+ становится виден; идемпотентно (повтор → 0 изменений) | — |
| B-ROLE-07 | **Role.Delete** custom-роли (отвязанной) | — | `200`; если есть активные bindings → `FAILED_PRECONDITION` (RESTRICT) | — |
| B-ROLE-08 | **Role.Modify/Delete** на is_system роль (owner/cluster-admin/каталог) | — | edit/delete недоступны (UI hideEdit/hideDelete), API → отказ | — |

> Повторить B-ROLE-01..03 для каждого модуля×ресурса (см. карту §1) — by-label/by-name/global вариант на тип.

### B.2 Матрица Binding CRUD × scope-тип (create/modify/delete = create/—/revoke)

> У AccessBinding нет generic Update (immutable; modify = Delete+Create). «modify» трактуем как
> revoke+recreate с другим scope/role. Колонки: ожидаемый код + видимость после.

| ID | Binding-операция | scope-тип | Ожидание | INV |
|---|---|---|---|---|
| B-BIND-01 | **Create** `(T-USER, r-label, PROJECT:<P+>)` | PROJECT by-label | `200` Operation done; T+ виден у T-USER ≤2s | INV-2 |
| B-BIND-02 | **Create** `(T-USER, r-label, ACCOUNT:accpj09931vpw14js8zz)` | ACCOUNT by-label | `200`; материализация cross-project в пределах аккаунта (T+ в P1 и P2 видны) | — |
| B-BIND-03 | **Create** `(T-USER, r-name, PROJECT:<P+>)` | PROJECT by-name | `200`; ровно named T+ виден | INV-2 |
| B-BIND-04 | **Create** `(T-USER, r-global-name, GLOBAL)` | GLOBAL names/labels | `200`; cluster-wide матч | — |
| B-BIND-05 | **Create** `(T-USER, r-global-all, GLOBAL)` обычная роль | GLOBAL all | **`400`** sync; binding не создан | **INV-8** |
| B-BIND-06 | **Modify** = revoke B-BIND-01 → recreate с PROJECT:<другой P> | — | revoke `200` (tuple сняты, T+ исчез у T-USER) → новый create `200` | INV-7 |
| B-BIND-07 | **Delete (revoke)** активного binding | — | `200`; все материализованные tuple сняты; T-USER теряет видимость T+ | **INV-7** |
| B-BIND-08 | **Delete** owner-binding (deletion_protection=true) | — | **`FAILED_PRECONDITION`** "...has deletion_protection enabled; clear it via Update before Delete"; binding жив | — |
| B-BIND-09 | снять protection (Update deletion_protection=false) → Delete | — | Update `200` → Delete `200`; owner-tuple сняты | — |
| B-BIND-10 | **Create** не-cluster-admin'ом binding на чужой ACCOUNT (T-USER без admin-tier на чужом) | — | **`PERMISSION_DENIED`** (requireGrantAuthority) | INV-5 |

### B.3 label-mutation revoke (INV-6 — реконсиляция по смене метки)

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| B-LBL-01 | T+ ресурс виден у T-USER (binding `r-label test=treska`) → владелец меняет метку на `test=other` (Update + RegisterResource) | reconcile ≤2s → ресурс fell-out → tuple снят → ресурс исчезает из списка/detail у T-USER | **INV-6** |
| B-LBL-02 | вернуть метку `test=treska` обратно | reconcile ≤2s → ресурс снова виден (forward-materialization) | INV-6 |
| B-LBL-03 | удалить T+ ресурс (UnregisterResource) | tuple снят; T-USER не видит; dangling-ref переживается грациозно (IAM не падает) | INV-6/INV-7 |

---

## Фаза C — селектор шапки (header Account/Project) — видимость без контента

> Проверяет: грант `v_list` на account/project (D-6 verb-bearing) → объект появляется в **header-селекторе**
> (Account/Project switcher), но БЕЗ доступа к контенту (если нет `v_get`/гранта на содержимое).
> Используем `accpj09931vpw14js8zz` + второй проект.

| ID | Грант (cluster-admin выдаёт T-USER) | Шаг (T-USER) | Ожидание | INV |
|---|---|---|---|---|
| C-01 | `iam.account.list` @ ACCOUNT:accpj09931vpw14js8zz (только v_list) | открыть header Account-селектор | account **появляется** в селекторе (`200` v_list) | — |
| C-02 | (тот же, v_list-only) | выбрать account → попытка открыть его detail/контент | контент закрыт: detail account `404`, ресурсы внутри не видны (нет v_get/каскада) | **INV-1** |
| C-03 | `iam.project.list` @ PROJECT:<P+> (v_list) | header Project-селектор (после выбора account) | project **появляется** в селекторе | — |
| C-04 | (project v_list-only) | в выбранном project открыть VPC/Compute списки | списки ПУСТЫ (нет грантов на vpc/compute ресурсы — D-2 нет каскада от project) | **INV-4** |
| C-05 | `iam.account.get` добавлен к v_list | account detail | теперь `200` v_get — overview открыт (но содержимое всё ещё по отдельным грантам) | INV-1 (разграничение list/get) |
| C-06 | tier admin на account (write-authz, без v_*) | header-селектор + detail | account виден если есть v_list; **detail контента нет** только от tier admin (D-7) | **INV-5** |
| C-07 | AccessBindingCreateForm: scope=PROJECT без выбранного account в шапке | открыть форму создания binding | `access-bindings-scope-ref` показывает «Сначала выберите Account в шапке секции» (зависимость селектора от header-account) | — |
| C-08 | GLOBAL в форме binding с обычной ролью | выбрать scope=GLOBAL + не-cluster-admin роль | alert `access-bindings-global-guard` («GLOBAL допустим только для роли cluster-admin») | INV-8 |

---

## Фаза D — subject-channel delta-кейсы (INV-9) — канал-специфичный негатив/реконсиляция

> Это НЕ повтор A/B/C под другим субъектом (то — channel-replication rule), а кейсы, осмысленные
> ТОЛЬКО для конкретного канала: членство группы, принципал-изоляция SA, authN SA-токена.
> Baseline-сверка (равенство visible-set трёх каналов) — implicit-предусловие каждого delta-кейса.

### D.1 group-member канал (subjects[]=[grp<T-GROUP>])

| ID | Шаг (актор → проверка) | Ожидание | INV |
|---|---|---|---|
| A-GRP-01 | Дан binding `(grp<T-GROUP>, test-account, ACCOUNT)`; T-USER ∈ T-GROUP → T-USER открывает list/detail M+ | visible-set/access-set **идентичны** user-direct baseline | **INV-9** |
| A-GRP-02 | `AddMember` нового user `U2` в T-GROUP → U2 (своя сессия) открывает M+ | доступ **появляется** для U2 (member-tuple co-commit) — без отдельного binding на U2 | INV-9 |
| A-GRP-03 | `RemoveMember(T-USER)` из T-GROUP → T-USER пере-запрашивает M+ | доступ **исчезает** у T-USER (member-tuple снят в той же tx); list M+ пуст, detail `404` | INV-7/INV-9 |
| A-GRP-04 | **non-member negative:** user `U3` НЕ член T-GROUP, binding только на группу → U3 открывает M+ | U3 **НЕ** видит M+ (list пуст, detail `404`) — групповой грант не течёт на не-членов | INV-3/INV-9 |
| A-GRP-05 | **revoke group binding:** revoke `(grp<T-GROUP>, test-account, …)` → все члены (T-USER, U2) | доступ снят у **всех** членов одновременно (binding-tuple userset убран) | **INV-7** |
| A-GRP-06 | (опц.) group-of-SA: binding на `grp<T-GROUP-SA>`, T-SA член → дозвон под T-SA-TOKEN | T-SA видит M+ как член группы (member-tuple `service_account:sva<SA>`) | INV-9 |

### D.2 SA-token канал (subjects[]=[sva<T-SA>], дозвон под T-SA-TOKEN)

| ID | Шаг | Ожидание | INV |
|---|---|---|---|
| A-SA-01 | Дан binding `(sva<T-SA>, test-account, ACCOUNT)`; дозвон под **T-SA-TOKEN** → list/detail M+ | visible-set/access-set **идентичны** user-direct baseline; принципал = `service_account:sva<SA>` | **INV-9** |
| A-SA-02 | **principal-isolation (SA→owner):** owner-user, выпустивший T-SA-key, дозванивается под СВОИМ user-JWT (без личного binding) → M+ | owner user **НЕ** наследует грант T-SA автоматически (list пуст, detail `404`) | INV-3/INV-9 |
| A-SA-03 | **principal-isolation (owner→SA):** T-USER имеет личный binding, T-SA — нет; дозвон под T-SA-TOKEN → M+ | T-SA **НЕ** наследует грант своего владельца-user; доступа нет | INV-3/INV-9 |
| A-SA-04 | **revoke SA key:** `SAKeyService` revoke ключа T-SA → повторный дозвон под (теперь отозванным) T-SA-TOKEN | `401 UNAUTHENTICATED` (authn-fail раньше authz — не `404`/`403`); доступ невозможен | INV-7 |
| A-SA-05 | **revoke SA binding (не ключа):** binding `(sva<T-SA>, …)` revoke, ключ жив → дозвон под валидным T-SA-TOKEN → M+ | токен аутентифицируется (`200`-auth), но visible-set ПУСТ / detail `404` (грант снят) | **INV-7** |

---

## 3. cluster-admin контрольная группа (позитив short-circuit — фон для контраста)

> Отдельная Playwright-сессия под cluster-admin (owner ws@dobry-kot.ru / root). Подтверждает,
> что short-circuit (D-9) даёт сквозной доступ — контраст к ограниченному T-USER.

| ID | Шаг (cluster-admin) | Ожидание |
|---|---|---|
| CA-01 | list любого ресурса в любом модуле/аккаунте | ВСЕ ресурсы видны (M+, M−, T+, T−, cross-account) — short-circuit |
| CA-02 | detail любого ресурса БЕЗ per-object tuple | `200` v_get (short-circuit Check) |
| CA-03 | выдать/ревокнуть binding на чужой ACCOUNT (где не owner) | `200` (requireGrantAuthority через short-circuit, КФ-2) |
| CA-04 | List/Get/Delete access-binding в чужом аккаунте | `200` (D-07 — не осиротевает после contract) |
| CA-05 | `/system/regions|zones|address-pools` | доступны (admin) |

---

## 4. Сводная трассировка кейсов → инварианты / D-решения

| Инвариант | Покрывающие кейсы |
|---|---|
| INV-1 (v_list-only → контент закрыт) | A-IAM-06/09/10/11/14, A-VPC-06/10..16, A-CMP-05/06/08/09, A-NLB-03/04/05, C-02/C-05 |
| INV-2 (non-matching label → невидим) | A-IAM-01/03/04/05/07/12/15/17/19/21, A-VPC-01/03/04/05/08, A-CMP-01/06/08/09, A-NLB-01/04/05, B-ROLE-01/02, B-BIND-01/03 |
| INV-3 (cross-account невидим) | A-IAM-21, A-ADM-01/02/03, A-XACC-01/02/03, CA-01 (контраст), A-GRP-04, A-SA-02/03 |
| INV-4 (нет каскада родитель→дети) | A-VPC-03/04/05/07, A-CMP-03/07, A-NLB-06, C-04 |
| INV-5 (tier admin не открывает контент) | B-BIND-10, C-06 |
| INV-6 (label-change снимает доступ) | B-LBL-01/02/03 |
| INV-7 (revoke/role-modify снимает tuple) | B-ROLE-05, B-BIND-06/07, B-LBL-03, A-GRP-03/05, A-SA-04/05 |
| INV-8 (GLOBAL+all обычной роли → отклонён) | A-05 (acceptance), B-ROLE-04, B-BIND-05, C-08 |
| **INV-9 (subject-channel equivalence)** | весь Phase A/B/C ×3 канала (channel-replication rule); delta A-GRP-01/02/06, A-SA-01; isolation A-GRP-04, A-SA-02/03 |
| D-6 verb-bearing account/project | A-IAM-01..09, C-01..C-06 |
| D-9 short-circuit | CA-01..05 |
| D-10 deletion_protection | B-BIND-08/09 |
| group#member userset (FGASubjectRef) | A-GRP-01..06 |
| SA принципал-изоляция (SAKey → Hydra cc) | A-SA-01..05 |

---

## 5. Заметки исполнения Playwright

- **Сессии:** отдельные browser-context на T-USER и cluster-admin (изолированные JWT/cookie).
- **Селекторы UI:** detail-табы — path-based (`/<detailBase>/<tabId>`, напр. `.../subnets` related-таб, `.../rules` SG, `.../privileges` SA/user/group). Формы: `data-testid` есть на access-bindings (`access-bindings-scope`, `-scope-ref`, `-global-guard`, `-role-select`) и role rules (`role-rule-*-arm-{anchor,names,labels}`).
- **404 vs 403:** detail Get без `v_get` → backend `404` (hide-existence). Playwright проверяет ErrorResult / отсутствие overview-Descriptions, НЕ «PermissionDenied»-текст.
- **Async/reconcile:** мутации binding/role — Operation (поллить done). labels-материализация reconcile ≤2s — добавлять `wait_for` на исчезновение/появление строки, не fixed sleep.
- **Список access-bindings** — bespoke 3-view (byScope/bySubject/byAccount), нет flat-List: проверять видимость через нужный view (byScope=account для A-IAM-21).
- **Verify per-tuple (опц.):** при доступе к internal API можно подтверждать материализацию через `ExpandAccess`/`Check` (acceptance §F-04) параллельно UI-проверке.
- **SA-token (Playwright SA-leg):** SA не логинится в браузер — SA-кейсы выполняются через
  `request.newContext({ extraHTTPHeaders: { Authorization: 'Bearer <T-SA-TOKEN>' }})` и сверяют
  visible-set на REST-ответах api-gateway (НЕ через DOM/вторую браузер-сессию). T-SA-TOKEN получают
  в `beforeAll`: `IssueSAKey` → подпись `private_key_jwt`-assertion (ES256, `kid=<key_id>`) → Hydra
  `/oauth2/token` `grant_type=client_credentials`. ES256-подпись JWT нативно ни newman, ни Playwright
  не умеют — нужен helper в setup-harness (jsrsasign / отдельный CLI). `revoke SAKey` (A-SA-04) →
  ожидать `401`; не путать с `404` грант-снятия (A-SA-05: ключ жив, снят binding).
- **group membership reconcile timing:** AddMember/RemoveMember co-commit'ят member-tuple в той же
  writer-tx → доступ появляется/исчезает синхронно с завершением Operation (НЕ отдельный async-цикл
  reconcile). Playwright: дожидаться `Operation.done` AddMember/RemoveMember, затем `wait_for` строки
  list — этого достаточно; labels-материализация (≤2s) — отдельная история, не путать.
- **principal-isolation:** для A-SA-02/03 и A-GRP-04 нужны ДВА independent request-context/сессии
  (owner-user-JWT и T-SA-TOKEN; member и non-member). Доступ одного принципала НЕ должен наблюдаться
  под другим — проверять обе стороны (SA→owner и owner→SA; member→non-member).
- **channel baseline-diff:** INV-9 проверяется как равенство множеств id в visible-set между каналами
  на идентичном наборе фикстур — снимать список видимых id (list-view / селектор) под каждым каналом
  и assert'ить `setEquals(direct, group)` && `setEquals(direct, sa)`, а не построчно дублировать кейсы.
```

---

## Открытые точки для уточнения на стенде (не блокируют матрицу)

- A-CMP-10 disk-types / A-ADM-* — фактический floor-доступ к справочникам и admin-поверхности: задокументировать наблюдаемое поведение fe3455 (что показывает UI обычному субъекту).
- Точный список модулей в `r-project` — сверить с backend-driven permission catalog (sub-phase G), чтобы rules покрывали все live-ресурсы.
- **ASSUMPTION (verify on stand):** обмен `private_key_jwt`-assertion на Hydra access_token и augment
  JWT через token_hook (`kacho_principal_type=service_account`) описаны кодом/кейсом
  `authz-sa-apitoken.py`, но на fe3455 SA-key newman/Playwright harness был known-RED до миграции
  ES256-подписи (FOLLOW-UP). Перед прогоном A-SA-* подтвердить, что setup-harness реально минтит
  рабочий T-SA-TOKEN на стенде; иначе A-SA-* остаются заблокированы harness'ом, а не продуктом.
- **ASSUMPTION (verify on stand):** A-SA-05 (ключ жив, binding revoke → `200`-auth + пустой
  visible-set) предполагает, что revoke binding'а снимает FGA-tuple, не затрагивая SA-key authN —
  подтвердить на стенде, что эти два слоя независимы (ожидание: токен валиден, доступ снят).
