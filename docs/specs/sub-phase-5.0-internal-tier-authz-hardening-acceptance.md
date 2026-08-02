# Sub-phase 5.0 — Internal-tier authz hardening (44 unguarded Internal.* methods) — Acceptance

> **Status**: ✅ **APPROVED** (acceptance-reviewer iteration 2, 2026-05-25; commit `7d69839` after M-02/M-04/M-05 fixes; original draft `4c26766`). Coding gate passed per `kacho-workspace/CLAUDE.md` §Запреты #1.
> **Date**: 2026-05-25
> **YouTrack epic**: KAC-201 (`[EPIC] Internal-tier authz hardening`). Subtasks materialised by the controller after this doc reaches APPROVED (see §13 «Decomposition map»). All issues + subtasks added to current sprint (`agiles/183-12`).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per Запрет #1).
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` — permission catalog enrichment (44 `Internal.*` entries get non-empty `permission` / `required_relation` / `scope_extractor`); FGA-model + seed for `system_admin` / `viewer` / `service_account` on `cluster:cluster_kacho_root`.
>   - **Primary**: `PRO-Robotech/kacho-api-gateway` — незаполненная запись каталога трактуется как **отказ**, а не как «требования нет» (§0, пункт 2); admin-mux-гейт, снимающий `Internal*`-пути с публичного TLS-листенера; различение вида принципала (`user` / `service_account`) в точке решения.
>   - **Primary**: `PRO-Robotech/kacho-corelib` — `auth/principal.go` extension: subject-type enum (`user|service_account|system`) + JWT claim parser (`kacho_principal_type`). Service-side authzguard refuses Cat-B FQN when `principal_type != service_account`.
>   - **Touched**: `PRO-Robotech/kacho-proto` — no new RPCs; only the catalog plugin (`protoc-gen-kacho-permissions`) emits the now-non-empty fields. Drift-test fixtures updated.
>   - **Touched**: `PRO-Robotech/kacho-vpc`, `PRO-Robotech/kacho-compute`, `PRO-Robotech/kacho-nlb` — Cat-B peer-clients (vpc → iam Check, compute → vpc InternalAddress, nlb → vpc/compute) acquire SA-token from k8s service-account / SPIRE SVID (already plumbed for some; verify and document).
>   - **Touched**: `PRO-Robotech/kacho-deploy` — bootstrap-job creates FGA tuple `cluster:cluster_kacho_root#system_admin@service_account:sva_kacho_cluster_admin` (idempotent); k8s ServiceAccount + token-mount per service deployment template; admin-tooling-script issues SA-token for `kacho-cluster-admin`.
>   - **NOT touched** (out of scope, explicit): `kacho-ui` (UI continues to use cluster-internal listener with viewer/admin user-token; no change to UX); per-resource authz (project/folder-scoped writes — already done in W1.6 + KAC-127); OPA bundles for backends (orthogonal — backends already do FGA-Check via authzguard).
> **Branch (all repos)**: `KAC-201` (per CLAUDE.md «git-флоу под задачу»).
> **Parent epic plan**: this doc is its own root (no master plan); related Wave-1 docs:
>   - `sub-phase-W1.3-gateway-authz-failclosed-acceptance.md` (APPROVED 2026-05-23) — fail-closed on IAM unreachable; **does NOT cover empty-permission catalog entries** (catalog-miss vs catalog-hit-with-empty-fields are different code paths).
>   - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md` — anti-anonymous authzguard for **public** mutating RPCs; orthogonal to Internal-tier (Internal* never traverses the public listener).
>   - `sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md` — adds the **drift-test** infra (proto reflection vs catalog); 5.0 reuses it to certify all 44 Internal entries are non-empty.
> **Predecessors**:
>   - W1.1 FGA outbox drainer (APPROVED + merged) — `bootstrap-admin` tuples land in OpenFGA; we extend the seed list rather than wiring a new mechanism.
>   - W1.3 gateway fail-closed (APPROVED + merged) — production overlay enforces `authz.enabled=true, failOpen=false`; 5.0 hardens the *empty-permission* sub-path on top.
>   - W2.A catalog-spec drift-test (APPROVED in flight) — gives us a CI gate that 5.0 wires into.

---

## 0. Преамбула — что эта sub-итерация (précis)

KAC-201 закрывает подтверждённый класс: **запись каталога прав, у которой требование не заполнено,
трактовалась как «требования нет»** — то есть отсутствие данных читалось как разрешение. На момент
обследования (§1.1) требование не было заполнено **ни у одной** из 264 записей каталога, 44 из них —
`Internal.*`-сервисы (admin / peer-RPC). Поэтому включённая и корректно настроенная authz-прослойка
шлюза (`authz.enabled=true`, `failOpen=false`) выносила «разрешено» **не отказав** — она честно
исполняла каталог, а каталог ничего не требовал.

Почему это стоит понять как класс, а не как один промах в данных:

- **Незаполненное поле — не «пусто», а значение.** У любого отсутствующего требования есть
  трактовка по умолчанию, и она либо «запретить», либо «разрешить». Здесь была вторая, и потому
  каждый пробел в данных автоматически становился дырой в контроле. Тот же класс, что «пустой
  список форвардеров значит не сужаем» и «отношение, выполнимое подстановкой, не сужает ничего»
  (`.claude/rules/security.md`): форма контроля присутствует, а сторона, в которую он ошибается, —
  открытая.
- **Проверка исполнялась и не отказывала ни разу за всё время жизни.** Провязанность прослойки,
  зелёный старт и отсутствие ошибок в логах — не свидетельства работы контроля. «Ноль отказов за
  всю жизнь» обязано быть заметно ровно так же, как «ноль доставленных строк за всю жизнь очереди»
  (`.claude/rules/data-integrity.md`).
- **Настройка выглядела правильной, и она была правильной.** Ручки стояли в безопасных положениях;
  пусто было в **данных**, которыми ручки распоряжаются. Аудит конфигурации такой дефект не
  находит — его находит вопрос «на скольких записях этот контроль хоть раз что-то потребовал».

> Пошаговое воспроизведение (какой запрос, от чьего имени, с каким наблюдаемым ответом) велось в
> рабочем каталоге задачи и **в git не идёт**: оба репозитория публичны, а связка «координата +
> условие + следствие» — восстановимый рецепт (`.claude/rules/security.md` §«Публичные артефакты»).
> Здесь достаточно того, что дефект был воспроизведён на стенде до правки и перестал
> воспроизводиться после — что и закрепляют сценарии §6.

KAC-201 закрывает три отдельных дыры одной hardening-pass:

1. **Permission-catalog content gap** — все 44 `Internal.*` записи получают корректные `permission` (`<domain>.<resource>.<verb>`-нотация) + `required_relation` (`system_admin` / `viewer` / `service_account`) + `scope_extractor` (`object_type=cluster, from_request_field='*'` для cluster-singleton, `object_type=project, from_request_field='project_id'` для project-scoped peer-RPC). Drift-test из W2.A гарантирует, что catalog не уйдёт обратно в empty-state.

2. **Gateway empty-entry fail-closed** — трактовка незаполненной записи меняется с «требования нет»
   на **отказ**, в паритет с уже существующим поведением для записи, которой в каталоге нет вовсе.
   Это ключевая часть правки, и она **не заменяется** пунктом 1: заполнить каталог — значит убрать
   сегодняшние пробелы, а развернуть умолчание — значит сделать так, что **завтрашний** пробел
   станет отказом, а не дырой. Первое чинит экземпляры, второе чинит класс; порядок обязателен
   именно такой, потому что развернуть умолчание **до** заполнения каталога значит закрыть доступ
   всем сразу. Ужесточение фиксируется doc-комментарием у самого места решения — комментарий обязан
   называть, что именно он запрещает, иначе следующий снимет его как непонятную проверку.

3. **Subject-type discrimination** — corelib уже различает вид принципала, но каталог этого не
   использовал, поэтому требование можно было выразить только как «какой уровень прав», но не как
   «кому этот путь вообще предназначен». Различие содержательное: межсервисные peer-RPC —
   поверхность **для машин**, и человек с достаточным уровнем прав всё равно не должен на неё
   попадать. Причина не в недоверии к человеку, а в том, что у пользовательского токена другой
   жизненный цикл, другой радиус при утечке и другой способ отзыва. Поэтому в запись каталога
   добавляется требование к **виду** субъекта (`any|user|service_account`, §4.5) — уровень прав и
   вид принципала становятся двумя независимыми осями, и повышение по одной не заменяет другую.

KAC-201 — это не «новая фича», а **гигиена**: catalog-content + gateway-config + corelib-helpers + tuple-seed. Реализация распадается ровно на 8 chain-of-dependency subtasks (см. §13).

### 0.1 KAC-201 НЕ включает

- **Per-resource ABAC / project-scoped writes на Internal.*** — единственный scope у Cat-A admin-RPC = singleton `cluster:cluster_kacho_root` (см. `resources/iam-cluster.md`). Cat-B peer-RPC оперируют project-scope, но это уже handled через project-id extractor + service_account relation; ABAC-conditions (rate-limit, ip-pin) — отдельный chunk вне 5.0.
- **JIT-eligibility / break-glass на `system_admin`** — PIM-flow для admin-доступа уже определён в `sub-phase-3.7-iam-jit-breakglass`-acceptance; 5.0 только проверяет, что effective `system_admin@cluster:cluster_kacho_root` (через JIT либо direct grant) даёт доступ.
- **CAEP push при revoke service_account-token** — covered в W3.2 observability chunk; orthogonal.
- **Internal listener mTLS-hardening** — workspace CLAUDE.md §«TLS-listener filter» и `sub-phase-3.10-iam-spiffe-spire-cilium-mesh`-acceptance уже описывают переход на SPIFFE SVID + Cilium mTLS. 5.0 принимает текущую schema (cluster-internal HTTP/2 cleartext + k8s-SA-token Bearer) и не вмешивается.
- **Backfilling missing `Internal*` methods** — например `InternalHypervisorService` уже выпилен (KAC-36); если будет добавлен новый `Internal*` сервис после 5.0 merge, drift-test (из W2.A) автоматически зафейлится с «catalog entry has empty permission».
- **Public RPC permission-catalog backfill (≈192 entries)** — это бóльший scope (отдельный эпик); 5.0 фокусируется ИСКЛЮЧИТЕЛЬНО на 44 `Internal.*`-методах + sandwich-of-defence для catalog-empty case.

### 0.2 Зависимости

- **W1.1 APPROVED + merged** — FGA-outbox drainer работает; добавление seed-tuple (`cluster:cluster_kacho_root#system_admin@service_account:sva_kacho_cluster_admin`) пройдёт через тот же drain-path.
- **W1.3 APPROVED + merged** — production overlay уже `authz.enabled=true, failOpen=false`. 5.0 НЕ переключает эти флаги; полагается на них.
- **W2.A drift-test landed** — proto-reflection scanner (`tests/drift/catalog_drift_test.go`) экспортирует map `(FQN → entry)`. 5.0 расширяет ассертику: каждый `*.Internal*` FQN обязан иметь `entry.Permission != ""` И `entry.RequiredRelation != ""` И `entry.ScopeExtractor.ObjectType != ""`.
- **OpenFGA HA-mini на target-стенде** — fail-closed enforcement требует FGA доступен. На dev — single-replica допустимо.
- **`kacho-cluster-admin` k8s ServiceAccount существует** или создаётся миграцией `kacho-deploy`. Token-mount per pod через `automountServiceAccountToken: true` + `audience: "kacho-internal"`.

---

## 0.5. Prerequisites & coordination with KAC-196 / KAC-178 (cross-epic dependency)

KAC-201 **зависит** от двух параллельно идущих эпиков. Без них Cat-A `required_relation: system_admin` нельзя ни замапить, ни валидировать в Newman. Эта секция фиксирует, **что приходит откуда** и **что не делает 5.0**.

### 0.5.1 KAC-178 §3 follow-up (proto#26 alias-relations) — Status: Test

Daёт FGA-аliases:
- `cluster:admin = system_admin + emergency_admin` (computed-from-relations)
- `cluster:editor = system_admin` (computed-from-relations)
- `cluster:viewer = editor + service_account` (transitive read-cascade)

KAC-201 **использует** эти aliases в catalog `required_relation` поле (Cat-A → `admin`; Cat-C → `viewer`). KAC-201 **НЕ дублирует** proto#26: его merge — pre-condition.

Если KAC-178 §3 ещё не merged к моменту начала KAC-201.5 (gateway authz-mw): можно временно использовать прямую relation `system_admin` без cascade — `viewer` cases в §3.5 будут падать на admin/SA, что считается RED-предсостоянием до KAC-178 fully merged.

### 0.5.2 KAC-196 — Cluster RBAC admin UI — Status: In Progress (backend merged 2026-05; UI WIP)

**Update (post-reviewer M-02)**: backend часть KAC-196 уже в `kacho-iam/main`:
- `008417a feat(KAC-196): InternalClusterService use-cases + handler + wiring (Task 3)`
- `7df68f1`, `371e8df` — repo + integration-tests
- `71f1941 chore(KAC-196): gofmt -w on Task 2+3 files (CI golangci-lint fix)`

То есть **server-side RPC `InternalClusterService.{Grant,Revoke,List}Admin` доступны уже сейчас**. UI часть (`/system/cluster`) — WIP. Для KAC-201.9 Newman это значит: setup-step может вызывать `POST /iam/v1/cluster/admins:grant` через api-gateway internal mux **сразу** (после регистрации route в `restmux/mux.go`), не дожидаясь UI.


Даёт **mechanism**:
- `InternalClusterService.GrantAdmin` (subject=user → tuple `cluster:cluster_kacho_root#system_admin@user:usr_xxx`)
- `InternalClusterService.RevokeAdmin` (remove tuple)
- `InternalClusterService.ListAdmins` (admin-UI таблица)
- DB-таблица `cluster_admin_grant` + `fga_outbox` write — audit + idempotency.
- UI `/system/cluster` — admin user-list + grant button.
- Gate: `system_admin OR emergency_admin` (через alias `admin` от KAC-178 proto#26).

KAC-201 **использует** KAC-196 для grant'а человеческих админов перед запуском Newman §3.4 (Cat-A scenarios). KAC-201 **НЕ дублирует**:
- `InternalClusterService.*` RPC + handler + DB table — это KAC-196.
- UI `/system/cluster` — это KAC-196.

### 0.5.3 Scope split — explicit owner table

| Sphere | Owner |
|---|---|
| FGA proto changes (alias-relations `admin`/`editor`/`viewer` → `system_admin`) | **KAC-178 §3 proto#26** |
| `InternalClusterService.GrantAdmin/RevokeAdmin/ListAdmins` RPC | **KAC-196** |
| `InternalClusterService` handler в kacho-iam (incl. `cluster_admin_grant` DB-table + `fga_outbox` write) | **KAC-196** |
| UI `/system/cluster` (admin user list + grant button + email-lookup) | **KAC-196** |
| **Catalog migration** — 44 Internal.* entries get non-empty `permission`/`required_relation`/`scope_extractor` | **KAC-201** |
| **api-gateway authz-mw fail-closed** на empty entry для `.Internal*` paths | **KAC-201** |
| **Service-account distinct subject-type** в `kacho-corelib` auth-interceptor (Category B routing) | **KAC-201** |
| **`kacho-cluster-admin` SA seed** (FGA tuple `cluster:cluster_kacho_root#service_account@service_account:sva_kacho_cluster_admin`) — inter-service, **не human admin** | **KAC-201** |
| **TLS-listener filter** для admin paths (workspace CLAUDE.md §Запреты #6 — `Internal*` НЕ на external endpoint) | **KAC-201** |
| **Newman regression** — per-method × per-principal (admin tuples создаются через KAC-196 в setup-шаге, либо temporary FGA HTTP API до KAC-196 merge) | **KAC-201** |

### 0.5.4 Ordering — critical path с учётом prerequisites

```
0a. KAC-178 §3 proto#26 (Test → merged)    [out-of-KAC-201]
       │
       ▼
0b. KAC-196 (To do → merged)               [out-of-KAC-201]
       │
       ▼
1.  KAC-201.1 (proto SubjectType enum)     [параллельно с 4]
2.  KAC-201.2 (plugin extension)
3.  KAC-201.3 (annotations на 44 RPC)
4.  KAC-201.4 (FGA `service_account` relation + SA seed) [параллельно с 1]
5.  KAC-201.5 (gateway authz-mw fail-closed + subject-type)
6.  KAC-201.6 (corelib Principal.MatchesRequiredSubjectType + backend authzguards)
7.  KAC-201.7 (k8s SAs + token-mount + peer SA-clients)
8.  KAC-201.8 (drift-test tightening)
9.  KAC-201.9 (Newman 176-case matrix)     [depends on 0b для admin-setup]
10. KAC-201.10 (vault trail)
11. KAC-201.RT-1 (audit-schema)
12. KAC-201.RT-2 (Grafana dashboards)
```

Если KAC-196 задерживается, KAC-201.9 (Newman) использует **temporary FGA HTTP API** в setup-step (как сейчас делает stand-bootstrap) — это документировано как acceptable fallback в §9 Risks/mitigations, но `merge KAC-201` НЕ блокирует merge KAC-196.

### 0.5.5 GWT-сценарии под admin принципалом — формулировка

Все Cat-A сценарии в §3.4 формулируются как:

> **Given** user is `system_admin` (tuple `cluster:cluster_kacho_root#system_admin@user:usr_admin` exists — установлен через **KAC-196 `GrantAdmin` UI** или temporary FGA HTTP API в test-fixture setup),
> **When** ...
> **Then** ...

То есть **acceptance НЕ верифицирует механизм grant'а** (это KAC-196 acceptance). 5.0 верифицирует: «если tuple есть → 200; если tuple нет → 403».

---

## 1. Current state (discovered 2026-05-25)

Точные данные с `KAC-132` HEAD (current branch). Источники указаны inline для трассировки reviewer'ом.

### 1.1 Permission catalog — наблюдаемый dump

- `project/kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json` — **236 уникальных FQN-записей** (вычислено `grep -c '"fqn"'`). Все 236 имеют:
  - `"permission": ""`
  - `"required_relation": ""`
  - `"scope_extractor": {"object_type": "", "from_request_field": ""}`
- Из них **44 — `Internal.*`** (вычислено `grep -E 'Internal[A-Z]' ... | wc -l`). Полный список (точные FQN из catalog):
  - **Compute** (11): `InternalDiskTypeService.{Create,Update,Delete}`, `InternalRegionService.{Create,Update,Delete}`, `InternalZoneService.{Create,Update,Delete}`, `InternalResourceLifecycleService.Subscribe`, `InternalWatchService.Watch`.
  - **IAM** (6): `InternalIAMService.{Check,LookupSubject,WriteCreatorTuple,ListPermissions}`, `InternalUserService.{Get,UpsertFromIdentity}`.
  - **LoadBalancer** (1): `InternalResourceLifecycleService.Subscribe`.
  - **VPC** (26): `InternalAddressPoolService.{Create,Get,List,Update,Delete,BindAsNetworkDefault,UnbindNetworkDefault,BindAsAddressOverride,UnbindAddressOverride,Check,ExplainResolution,ListAddresses,GetUtilization}` (13), `InternalAddressService.{AllocateExternalIP,AllocateInternalIP,AllocateInternalIPv6,GetAddressReference,SetAddressReference,ClearAddressReference,MarkAddressEphemeralInUse}` (7), `InternalCloudService.{GetPoolSelector,SetPoolSelector,UnsetPoolSelector}` (3), `InternalNetworkService.SetDefaultSecurityGroupId` (1), `InternalResourceLifecycleService.Subscribe` (1), `InternalWatchService.Watch` (1).
- **Расхождение с запросом**: запрос упоминает `InternalNetworkService.GetNetwork` — этот FQN **отсутствует** в catalog. В реальном catalog присутствует `InternalNetworkService.SetDefaultSecurityGroupId`. (Прежняя internal-проекция Network с data-plane-идентификатором и её REST-path `/vpc/v1/networks/{id}/internal` — kube-ovn-эпохи — удалены в KAC-36/79/80.) KAC-201 покрывает существующие 44 FQN; добавление новых internal-методов — отдельный issue per repo (см. §13 RT-1).

### 1.2 Gateway catalog-loading behaviour

Разбор, важный **как класс** (пошаговая механика прохода велась в рабочем каталоге задачи и в git
не идёт — `.claude/rules/security.md` §«Публичные артефакты»):

- **«Записи нет» и «запись есть, но пустая» — разные состояния, и обрабатывались они по-разному.**
  Комментарий в загрузчике каталога описывает трактовку **отсутствующей** записи; ветка явного
  освобождения от проверки срабатывает **только** на специальном литерале-маркере. Незаполненная
  запись не попадает ни туда, ни туда: она не отсутствует, поэтому «не найдено» к ней не
  применяется, и она не помечена освобождённой, поэтому идёт дальше по конвейеру — в третье,
  никем не спроектированное состояние.

- **Класс: третье состояние, которого нет в модели автора.** Проектировались два случая («есть
  требование» / «требования нет по решению»), а реальность добавила третий («требование должно
  быть, но его не записали»), и он унаследовал поведение от того из двух, что оказался ближе по
  коду, — а не от того, что безопаснее. Это же объясняет, почему комментарий рядом **не лгал** и
  всё равно вводил в заблуждение: он верно описывал случай, о котором говорил, и молчал о случае,
  которого автор не предполагал. Проверять надо не согласие комментария с кодом, а **полноту
  разбора значений**.

- **Гипотеза о точном пути прохода не принимается на веру.** На момент написания дока
  окончательный механизм был предположением, и это фиксируется прямо: он **устанавливается
  прогоном** RED-теста G1 (§3.1) и проверкой §3.2, а не рассуждением по исходникам. Предположение,
  выглядящее как вывод, — отдельный способ ошибиться; правка не зависит от того, какая из версий
  верна, потому что закрывает **все** три состояния разом (§0, пункт 2).

### 1.3 Gateway mux split

- `internal/restmux/mux.go` — разделение на два mux'а задокументировано: публичный (tenant-facing) и
  внутренний (admin / data-plane), с маршрутизацией по пути.
- **Однако разделение проходит не там, где кажется.** Оба mux'а смонтированы на один корневой
  HTTP-обработчик, и authz-прослойка оборачивает именно его — то есть она **одна на оба**. Различие
  между «внутренним» и «публичным» здесь — это различие в **маршалинге JSON и в том, на каком
  листенере зарегистрирован маршрут**, но **не уровень авторизации**.

  Отсюда общий вывод, ради которого этот пункт и написан: **«внутренний» — свойство сетевой
  досягаемости, а не полномочий**. Оно ограничивает, **откуда** можно постучаться, и ничего не
  говорит о том, **кому** отвечать. Пока каждый RPC не несёт собственного требования (§0, пункт 1),
  всякий, кто оказался внутри периметра, для такой поверхности неотличим от администратора. Это
  ровно запрещённое допущение «internal = trusted» из `.claude/rules/security.md` §«AuthN+AuthZ
  ВЕЗДЕ»: внутренний периметр не доверенный, и правила для обоих листенеров одинаковые.

  Частичная защита при этом реально существует и её не надо путать с полной: внешний TLS-фронт не
  знает admin-маршрутов, поэтому снаружи они не видны. Именно эта частичность и продлевала жизнь
  дефекту — поверхность выглядела закрытой ровно с той стороны, с которой её обычно проверяют.

### 1.4 Service-account subject-type — current corelib state

- `project/kacho-corelib/auth/principal.go` (full file) — `Principal` struct:
  ```go
  type Principal struct {
      Type        string // "user" | "service_account" | "system"
      ID          string // "usr_*" | "sva_*" | "bootstrap"
      DisplayName string
  }
  ```
  Type-discrimination **уже есть** на уровне в struct, но catalog-driven enforcement отсутствует. Source of `Type`: JWT-claim `kacho_principal_type` (или fallback "user" если отсутствует — см. `kacho-api-gateway/internal/middleware/authz.go:835`).
- **Cat-B методы сейчас**: peer-clients (vpc→iam Check) уже посылают `Authorization: Bearer <sa-token>`, где SA-token — k8s SA JWT с `aud=kacho-internal`. authz-mw на gateway side **не различает** user vs service_account по полю Permission — это упущение KAC-127 (catalog не имел поля `required_subject_type`).

### 1.5 FGA model — cluster:cluster_kacho_root current relations

- `project/kacho-iam/internal/apps/kacho/seed/embedded/fga_model.fga` (assumed location; if elsewhere see `kacho-iam/internal/fga/model.go`) — current model file:
  ```
  model
    schema 1.1

  type user
  type service_account
  type cluster
    relations
      define system_admin: [user, service_account]
      define viewer: [user, user:*, service_account]
  ```
  (verify exact content in §3.1 G3-RED — may need extension)
- Missing relations (per `iam-cluster.md` line 13 «singleton root of hierarchy»):
  - `define service_account: [service_account]` — direct-match relation, чтобы catalog мог объявить `required_relation=service_account` и tuple-проверка свелась к «subject — это service_account, и он zarejestrowan на cluster».
- Bootstrap-seed tuple список (per W1.1 drainer): сейчас включает `cluster:cluster_kacho_root#system_admin@user:usr_kacho_bootstrap_admin`. **Добавляется** `cluster:cluster_kacho_root#system_admin@service_account:sva_kacho_cluster_admin`. И per service: `cluster:cluster_kacho_root#service_account@service_account:sva_kacho_vpc` / `sva_kacho_compute` / `sva_kacho_nlb` / `sva_kacho_api_gateway` (для каждого backend service deployment).

### 1.6 Drift-test infrastructure (from W2.A)

- `project/kacho-iam/tests/drift/catalog_drift_test.go` (assumed location, landed by W2.A) — scanner:
  ```go
  func TestCatalogCoversAllProtoMethods(t *testing.T) {
      // 1. Walk kacho-proto registry, collect all (service.FQN/Method) tuples.
      // 2. Load embedded catalog.
      // 3. Assert each proto-FQN has entry; assert entry.Permission != "".
  }
  ```
  Currently this test **passes** because the assertion is `entry exists`, not `entry.Permission != ""`. KAC-201 tightens the assertion (см. §3.1 G2-RED).

---

## 2. What ships (changes by file, dependency-ordered)

Каждый chunk ниже = один subtask из §13. Файлы и приблизительный diff-объём (точные строки уточняет implementer).

### 2.1 `kacho-iam` — FGA model + seed-tuples

- `internal/fga/model.fga` (или `internal/apps/kacho/seed/embedded/fga_model.fga`): добавить `define service_account: [service_account]` под `type cluster`. Bump `schema 1.1` → keep (FGA `schema 1.1` covers it). Re-emit authorization-model-id (write via `migrator` cmd on next deploy).
- `internal/apps/kacho/seed/bootstrap_tuples.go` (или соответствующий .go-builder, не JSON): добавить tuples:
  - `cluster:cluster_kacho_root#system_admin@service_account:sva_kacho_cluster_admin`
  - `cluster:cluster_kacho_root#service_account@service_account:sva_kacho_vpc`
  - `cluster:cluster_kacho_root#service_account@service_account:sva_kacho_compute`
  - `cluster:cluster_kacho_root#service_account@service_account:sva_kacho_nlb`
  - `cluster:cluster_kacho_root#service_account@service_account:sva_kacho_api_gateway`
  - `cluster:cluster_kacho_root#viewer@user:*` (если viewer-cascade для Cat-C public-read; opcjонально, см. §13 DR-1)
- Idempotency: drainer (`fga_outbox` table) уже дедуплицирует через `(object, relation, user, op)` UNIQUE. Replay-safe.

### 2.2 `kacho-iam` — Permission catalog source-of-truth + plugin emission

- `protoc-gen-kacho-permissions` plugin (location TBD — likely `kacho-iam/cmd/protoc-gen-kacho-permissions/`): расширить annotation-reader. Для каждой RPC method читает proto-options:
  ```proto
  rpc List (...) returns (...) {
    option (kacho.permission) = {
      permission: "vpc.address_pools.list"
      required_relation: "system_admin"
      required_subject_type: SUBJECT_USER
      scope_extractor: { object_type: "cluster", from_request_field: "*" }
    };
  }
  ```
  Если annotation отсутствует — plugin emit'ит entry с empty fields **и warning в build-log**; drift-test зафейлится. Это форсит per-RPC decisions ВО ВРЕМЯ proto-changes.
- `kacho-proto/proto/kacho/permission_options.proto` (новый): описание `kacho.permission` option + `SubjectType` enum (`SUBJECT_ANY=0`, `SUBJECT_USER=1`, `SUBJECT_SERVICE_ACCOUNT=2`).
- Per-proto annotations добавляются для всех 44 `Internal.*` методов. Categorization (см. §4 для policy-таблицы):

| Category | Required relation | Required subject_type | Object type | from_request_field |
|---|---|---|---|---|
| **A — admin** (AddressPool 13, Cloud.PoolSelector 3, Region/Zone/DiskType writes 9, InternalNetworkService.SetDefaultSecurityGroupId 1 = **26 methods**) | `system_admin` | `SUBJECT_USER` (admin-UI / admin-tooling) | `cluster` | `"*"` (cluster-singleton) |
| **B — inter-service / peer-RPC** (InternalIAMService 4, InternalUserService.UpsertFromIdentity 1, InternalAddressService 7, InternalResourceLifecycleService×3 backends, InternalWatchService×2 backends = **17 methods**) | `service_account` | `SUBJECT_SERVICE_ACCOUNT` | `cluster` | `"*"` |
| **C — public-read cluster-scoped** (InternalUserService.Get 1 — read own profile fallback) | `viewer` | `SUBJECT_ANY` | `cluster` | `"*"` |

  Sums: 26 + 17 + 1 = **44** ✓.

  *Note:* `InternalRegionService/InternalZoneService/InternalDiskTypeService.{Get,List}` НЕТ в catalog (только Create/Update/Delete есть). Read paths Geography (`Region/Zone/DiskType.Get/List`) — это **public** `compute.v1.RegionService` etc., НЕ Internal. Они получают свой permission в **другом** эпике (public-RPC backfill, out-of-scope KAC-201). Если они тоже хотим зафиксировать в 5.0 — это **scope-расширение**: см. §13 OQ-1.

- Output: `internal/apps/kacho/seed/embedded/permission_catalog.json` regenerated; commit'ится в git (mirror W2.A pattern). `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` синхронизируется через `make -C services/iam sync-permission-catalog`.

### 2.3 `kacho-corelib` — Subject-type discrimination в authzguard

- `auth/principal.go`: новые helpers `IsUser() bool`, `IsServiceAccount() bool`, `MatchesRequiredSubjectType(req string) bool`.
- `authzguard/interceptor.go` (если такой пакет существует; альтернативно — это per-service в `kacho-vpc/internal/authzguard`): метод проверяет `entry.RequiredSubjectType`, если не пусто и не совпадает с principal.Type → `PermissionDenied{reason="subject_type_mismatch: required=<x>, got=<y>"}`. **Backend-side enforcement**: даже если gateway пропустил (network compromise), backend authzguard отбьёт.

### 2.4 `kacho-api-gateway` — Empty-permission fail-closed

- `internal/middleware/permission_catalog.go`: doc-comment line 23-26 переписать на:

  > Method-not-found returns ok=false. Empty-permission (`""`) entry is **treated identically to not-found** — production must fail-closed unless the entry is `<exempt>`. The middleware refuses to forward such requests, returning `PermissionDenied{reason="catalog: entry has empty permission"}`.

- `internal/middleware/authz.go:504-568`: новый guard сразу после line 504 `entry, found := m.cfg.Catalog.Lookup(dr.FQN)`:
  ```go
  if found && !entry.IsExempt() && entry.Permission == "" {
      m.metrics.RecordDeny()
      m.cfg.Logger.Warn("authz catalog malformed: empty permission, denying",
          "fqn", dr.FQN)
      return decision{
          outcome: outcomeDeny,
          reasons: []string{"catalog: entry has empty permission"},
          descriptor: permissionDeniedDescriptor{FQN: dr.FQN},
      }
  }
  ```
- `CatalogEntry`: добавить поле `RequiredSubjectType string` (`json:"required_subject_type"`), значения `""` / `"user"` / `"service_account"`. Lookup-step проверяет совпадение с `subj.Type` (см. §2.5).

### 2.5 `kacho-api-gateway` — Subject-type matching в decision pipeline

- `authz.go:570-588`: после `subj, ok := m.cfg.Subjects.Extract(verified)` добавить:
  ```go
  if entry.RequiredSubjectType != "" && entry.RequiredSubjectType != subj.Type {
      m.metrics.RecordDeny()
      m.cfg.Logger.Info("authz subject_type mismatch",
          "fqn", dr.FQN,
          "required", entry.RequiredSubjectType,
          "got", subj.Type)
      return decision{
          outcome: outcomeDeny,
          reasons: []string{fmt.Sprintf("subject_type mismatch: required %q, got %q",
              entry.RequiredSubjectType, subj.Type)},
          descriptor: permissionDeniedDescriptor{FQN: dr.FQN},
      }
  }
  ```
- `internal/middleware/subject_extractor.go`: confirm `ResolvedSubject` carries `Type string` field (`"user"`/`"service_account"`/`"system"`). If missing — add (источник: JWT claim `kacho_principal_type`, fallback `"user"` for legacy tokens).

### 2.6 `kacho-deploy` — k8s ServiceAccounts + token-mount

- `helm/umbrella/values.yaml`: новая секция `serviceAccounts:` для backends:
  ```yaml
  serviceAccounts:
    kacho-vpc:        { audience: "kacho-internal" }
    kacho-compute:    { audience: "kacho-internal" }
    kacho-nlb:        { audience: "kacho-internal" }
    kacho-api-gateway:{ audience: "kacho-internal" }
    kacho-cluster-admin: { audience: "kacho-internal" }
  ```
- Per-subchart deployment template (`charts/vpc/templates/deployment.yaml` etc.): `automountServiceAccountToken: true`, `serviceAccountName: kacho-vpc`. Token injected into pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`, peer-clients читают и шлют в `Authorization: Bearer ...` header при peer-RPC.
- Bootstrap-job extension: `kacho-cluster-admin` SA создаётся идempotent (`kubectl apply` либо helm hook); token issued on first apply.

### 2.7 `kacho-vpc`, `kacho-compute`, `kacho-nlb` — Peer-clients SA-token wiring

- `internal/clients/iam_client.go` (vpc) и аналоги: загрузка JWT из `/var/run/secrets/.../token` (k8s projected SA-token), refresh on TTL expiry (rotated by kubelet каждые ~1h по умолчанию).
- Уже плумлено в большинстве сервисов (audit-trail из W1.x); KAC-201 проверяет полное покрытие через integration-tests (§3.4).

### 2.8 Drift-test tightening

- `tests/drift/catalog_drift_test.go` (или wherever W2.A landed): новые assertions:
  ```go
  for _, fqn := range allInternalFQNs {  // filter on contains "Internal"
      entry, ok := catalog.Lookup(fqn)
      require.True(t, ok, "Internal FQN missing in catalog: %s", fqn)
      require.NotEmpty(t, entry.Permission, "Internal FQN has empty permission: %s", fqn)
      require.NotEmpty(t, entry.RequiredRelation, "Internal FQN has empty required_relation: %s", fqn)
      require.NotEmpty(t, entry.ScopeExtractor.ObjectType, "Internal FQN has empty scope_extractor.object_type: %s", fqn)
      // RequiredSubjectType must be "user" or "service_account" (no "" or "any" for Internal).
      require.Contains(t, []string{"user", "service_account"}, entry.RequiredSubjectType,
          "Internal FQN has invalid required_subject_type: %s (got %q)", fqn, entry.RequiredSubjectType)
  }
  ```

---

## 3. Acceptance scenarios (Given-When-Then)

### 3.1 Catalog enrichment (proto annotations → JSON)

**Сценарий 01: All 44 Internal.* entries get non-empty permission/required_relation/scope_extractor**

**ID:** 5.0-01

**Given** `protoc-gen-kacho-permissions` plugin enhanced per §2.2 reads `(kacho.permission)` option
**And** все 44 Internal.*-метода в `kacho-proto/proto/kacho/cloud/<domain>/v1/internal_*.proto` имеют annotation согласно policy-таблицы §2.2 (cat-A/B/C)
**And** plugin regenerates `permission_catalog.json` + drift-mirror в `kacho-api-gateway/internal/middleware/embed/`

**When** запускается `cd services/iam && go test ./tests/drift/... -run TestCatalogCoversAllProtoMethods -v`

**Then** test passes (RED → GREEN compared to baseline §1.6 where assertion was `entry exists`)
**And** для каждого из 44 Internal.* FQN: `entry.Permission != ""`, `entry.RequiredRelation != ""`, `entry.ScopeExtractor.ObjectType != ""`, `entry.RequiredSubjectType ∈ {"user","service_account"}`
**And** для 26 Cat-A entries: `entry.RequiredRelation == "system_admin"` AND `entry.RequiredSubjectType == "user"`
**And** для 17 Cat-B entries: `entry.RequiredRelation == "service_account"` AND `entry.RequiredSubjectType == "service_account"`
**And** для 1 Cat-C entry (`InternalUserService.Get`): `entry.RequiredRelation == "viewer"` AND `entry.RequiredSubjectType == "user"` (read own profile)
**And** для всех 44: `entry.ScopeExtractor.ObjectType == "cluster"` AND `entry.ScopeExtractor.FromRequestField == "*"` (cluster-singleton scope, см. workspace CLAUDE.md §«Inra-чувствительные данные»)

**Сценарий 02: Drift-test catches regression (new Internal.* method without annotation)**

**ID:** 5.0-02

**Given** Сценарий 01 passes (catalog enriched)
**And** разработчик добавляет в proto новый RPC `InternalFooService.Bar` БЕЗ `(kacho.permission)` annotation

**When** запускается `make -C gateway permission-catalog-apply` + drift-test

**Then** plugin генерирует entry с `permission: ""`
**And** drift-test FAILS со строкой `Internal FQN has empty permission: kacho.cloud.foo.v1.InternalFooService/Bar`
**And** CI blocks merge до устранения

### 3.2 Gateway empty-entry fail-closed

**Сценарий 03: Gateway denies request with empty-permission catalog entry**

**ID:** 5.0-03

**Given** authz-middleware enabled (`KACHO_API_GATEWAY_AUTHZ_ENABLED=true, KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN=false`)
**And** in-memory catalog содержит entry `{fqn: "test.v1.FooService/Bar", permission: "", required_relation: "", ...}` (smoke-injected)
**And** клиент authenticated как regular user (valid Bearer `usr_test`)

**When** клиент вызывает `POST /test/v1/foos` (REST → resolves to FQN `test.v1.FooService/Bar`)

**Then** ответ HTTP 403 PermissionDenied
**And** body содержит `{"code":7,"message":"...","details":[{"reasons":["catalog: entry has empty permission"]}]}`
**And** structured-log emit'ит `level=WARN msg="authz catalog malformed: empty permission, denying" fqn="test.v1.FooService/Bar"`
**And** metric `kacho_authz_decisions_total{outcome="deny",reason="catalog_malformed"}` increments by 1

**Сценарий 04: Регрессия на исходный дефект — обычный тенант против admin-поверхности (RED → GREEN)**

**ID:** 5.0-04

> Сценарий описан **утверждением о требуемом свойстве**, а не готовой последовательностью вызовов:
> точная команда вместе с состоянием «до» — это воспроизведение, а репозитории публичны
> (`.claude/rules/security.md` §«Публичные артефакты»). Исполняемая форма живёт в самом newman-кейсе
> (§«Артефакты»), где ей и место: там она — проверка, а не инструкция.

**Given** базовое состояние до KAC-201 (каталог не заполнен, §1.1)
**And** поднят dev-стенд, в нём заведён **обычный** тенант — без каких-либо кластерных полномочий

**When** этот тенант обращается к admin-поверхности (`Internal.*`, ресурс уровня кластера) со своим
законным пользовательским токеном — то есть **аутентифицирован, но не авторизован**

**Then** **(до фикса, RED)** запрос **не отвергается** — ровно тот дефект, ради которого написан
KAC-201: аутентификация состоялась, авторизация не потребовала ничего. Значение теста в том, что он
**красный до правки**: проверка, не умеющая упасть, хуже отсутствующей.
**And** **(после фикса, GREEN)** — `403 PermissionDenied`; в теле ответа причина отказа в
`google.rpc.Status.details`, без раскрытия существования ресурса.
**And** в audit-log пишется событие отказа с `risk_level=HIGH` (обращение к `Internal.*` — высокий
риск **независимо** от исхода: важен сам факт попытки).

### 3.3 Subject-type discrimination (Cat-B service_account-only)

**Сценарий 05: User-token rejected on Cat-B method (InternalIAMService.Check)**

**ID:** 5.0-05

**Given** Сценарий 01 passes (catalog enriched)
**And** `InternalIAMService.Check` имеет `required_subject_type: SUBJECT_SERVICE_ACCOUNT`
**And** user `usr_admin_root` имеет `system_admin@cluster:cluster_kacho_root` direct grant

**When** клиент с user-Bearer `usr_admin_root` вызывает `InternalIAMService.Check{subject:user:usr_x, relation:viewer, object:project:prj_y}` через gRPC-direct на cluster-internal port

**Then** ответ gRPC PermissionDenied (code=7)
**And** error message `subject_type mismatch: required "service_account", got "user"`
**And** обоснование: даже supreme-admin user не должен иметь peer-RPC доступа (predicate prevention).

**Сценарий 06: Service-account-token passes on Cat-B method**

**ID:** 5.0-06

**Given** Сценарий 05 setup
**And** service-account `sva_kacho_vpc` имеет `service_account@cluster:cluster_kacho_root` grant (seed §2.1)
**And** kacho-vpc pod-token mount'ится в `/var/run/secrets/.../token`

**When** kacho-vpc peer-client (in-cluster) вызывает `InternalIAMService.Check` с SA-token в Bearer

**Then** ответ gRPC OK (Check возвращает `{allowed:true/false}` в зависимости от FGA-tuples)
**And** authz-mw decision-log: `outcome=allow, subject=service_account:sva_kacho_vpc, action=iam.authz.check, resource=cluster:cluster_kacho_root, model_id=<x>`

### 3.4 Cat-A admin-only positive/negative

**Сценарий 07: Admin user passes Cat-A method (InternalAddressPoolService.Create)**

**ID:** 5.0-07

**Given** Сценарий 01 passes
**And** user `usr_admin_root` имеет tuple `cluster:cluster_kacho_root#system_admin@user:usr_admin_root` (via direct grant или JIT-active)
**And** authz-middleware enabled, fail-closed

**When** admin вызывает (через admin-UI или admin-tooling) `POST /vpc/v1/addressPools` с body `{cidrBlocks:["10.0.0.0/16"]}`

**Then** HTTP 200 OK (либо 202 если async-operation)
**And** authz-mw decision-log: `outcome=allow, subject=user:usr_admin_root, action=vpc.address_pools.create, resource=cluster:cluster_kacho_root, risk=CRITICAL`
**And** audit-event `kacho.audit.admin_action` emitted to audit-pipeline.

**Сценарий 08: Regular user rejected on Cat-A method**

**ID:** 5.0-08

**Given** Сценарий 07 setup
**And** user `usr_tenant_alice` **НЕ** имеет `system_admin@cluster:cluster_kacho_root` (она viewer на project:prj_alice, не cluster-admin)

**When** alice вызывает `GET /vpc/v1/addressPools` через cookie-auth (`ory_kratos_session=...`)

**Then** HTTP 403 PermissionDenied
**And** reason `no path: subject user:usr_tenant_alice has no system_admin on cluster:cluster_kacho_root`
**And** audit-event `kacho.audit.access_denied` emitted with `risk_level=HIGH`.

**Сценарий 09: Anonymous request rejected on Cat-A method (no Bearer)**

**ID:** 5.0-09

**Given** Сценарий 07 setup

**When** клиент шлёт `GET /vpc/v1/addressPools` БЕЗ Authorization-header

**Then** HTTP 401 Unauthorized (per KAC-130 BUG-2 — distinct from 403 PermissionDenied)
**And** WWW-Authenticate header `Bearer realm="kacho", error="missing_token"`
**And** reason `subject: unauthenticated request`.

### 3.5 Cat-C public-read viewer cascade

**Сценарий 10: Authenticated user reads own profile via InternalUserService.Get**

**ID:** 5.0-10

**Given** user `usr_tenant_bob` registered + authenticated
**And** seed-tuple `cluster:cluster_kacho_root#viewer@user:*` exists (catch-all viewer cascade)
**And** `InternalUserService.Get` имеет `required_relation: viewer, required_subject_type: user`

**When** bob вызывает `GET /iam/v1/users/internal/usr_tenant_bob` (assumed REST mapping)

**Then** HTTP 200 OK + user profile
**And** decision-log: `outcome=allow, action=iam.users.read_internal, resource=cluster:cluster_kacho_root`.

**Сценарий 11: Anonymous rejected on Cat-C (must be authenticated)**

**ID:** 5.0-11

**Given** Сценарий 10 setup

**When** анонимный клиент вызывает `GET /iam/v1/users/internal/usr_x`

**Then** HTTP 401 Unauthorized (catalog entry not `<exempt>`, so subject extraction required).

### 3.6 FGA model + seed tuples

**Сценарий 12: Cluster relations declared + seeded**

**ID:** 5.0-12

**Given** post-deploy state on dev-стенд
**And** FGA model id поднят последней migration (per W1.1 drainer pattern)

**When** запустить:
```bash
fga model get --store-id $STORE_ID
fga tuple read --store-id $STORE_ID 'cluster:cluster_kacho_root#system_admin@*'
fga tuple read --store-id $STORE_ID 'cluster:cluster_kacho_root#service_account@*'
```

**Then** model contains relations `system_admin`, `viewer`, `service_account` on `type cluster`
**And** tuple `cluster:cluster_kacho_root#system_admin@service_account:sva_kacho_cluster_admin` present
**And** tuples `cluster:cluster_kacho_root#service_account@service_account:sva_kacho_{vpc,compute,nlb,api_gateway}` present (4 backend SAs)
**And** tuple `cluster:cluster_kacho_root#viewer@user:*` present (если включена Cat-C cascade — см. §13 OQ-2).

### 3.7 TLS-listener filter (defence-in-depth)

**Сценарий 13: Internal.* path returns 404 on external TLS-listener**

**ID:** 5.0-13

**Given** Production-like overlay (`values.prod.yaml`)
**And** TLS-listener bound on `api.kacho.cloud:443` обслуживает только **public** mux
**And** Internal-mux paths (`/vpc/v1/addressPools*`, `*/internal/*`) registered ТОЛЬКО на cluster-internal listener (port 9092)

**When** external attacker hits `https://api.kacho.cloud/vpc/v1/addressPools` с valid user-token

**Then** HTTP 404 Not Found (path not in public-mux routing-table) **либо** 403 PermissionDenied (если path всё же доходит до authz-mw, fail-closed deny на Cat-A relation)
**And** **никогда** 200 OK, даже под supreme-admin user-token (admin must use cluster-internal admin-tooling path, не public TLS).

### 3.8 Newman regression coverage

**Сценарий 14: Newman case per method — full 44 × 3 personae matrix**

**ID:** 5.0-14

**Given** Newman fixture (`tests/newman/cases/internal-tier-authz/`) генерируется через `gen.py`-pattern (parity с W2.D 100% coverage)
**And** 3 personae setup'ятся в fixture: `usr_tenant_alice` (regular user, no cluster-grants), `usr_admin_root` (cluster system_admin), `sva_kacho_test_peer` (service_account with `service_account@cluster:cluster_kacho_root`)

**When** запускается newman-набор `make -C deploy e2e-newman SVC=iam` (отдельной цели
`newman-internal-tier-authz` не существует)

**Then** для каждого из 44 FQN:
  - **Cat-A** (26 методов): `alice → 403` (PermissionDenied, reason "no path"), `admin → 200/202` (allow), `peer → 403` (subject_type mismatch: required user)
  - **Cat-B** (17 методов): `alice → 403`, `admin → 403` (subject_type mismatch: required service_account), `peer → 200` (allow)
  - **Cat-C** (1 метод): `alice → 200` (viewer-cascade), `admin → 200`, `peer → 403` (subject_type mismatch: required user)
**And** anonymous request (no Bearer) → 401 для всех 44
**And** suite reports `passed: 44*4 = 176, failed: 0`.

**Сценарий 15: Reproduction-curl Newman case (regression for current §0 vulnerability)**

**ID:** 5.0-15

**Given** Сценарий 14 suite landed
**And** dedicated case `regress_addresspool_list_tenant_blocked` exists

**When** suite runs (CI on every PR + nightly)

**Then** кейс утверждает **исход**, а не факт выполнения: обычный тенант против admin-поверхности
получает `403` — и **никогда** `200`. Отрицание здесь идёт в паре с положительным (кластерный
администратор на той же поверхности проходит, сценарии 05–13): одиночное «отвергнуто» зеленеет
сильнее всего именно тогда, когда сломано всё.
**And** кейс обязан быть **воспроизведённо красным** на состоянии до правки — иначе он проверяет не
дефект, а собственную формулировку.
**And** GitHub Issue (перекрёстная ссылка `# verifies <issue-url>`, CLAUDE.md §13) закрывается этим
зелёным тестом — закрытие issue обязано опираться на code-артефакт, а не на слово.

---

## 4. Permission/relation policy summary (canonical reference)

Источник для plugin-annotations + drift-test. Per-method таблица — в §2.2; здесь только декларация политики.

### 4.1 Cat-A — Admin-only (26 methods)

- Permission naming: `<domain>.<resource>.<verb>` где `<domain> ∈ {vpc, compute}` и `<verb> ∈ {create, read, list, update, delete, bind, unbind, set, unset, check, explain}`.
- Examples: `vpc.address_pools.create`, `vpc.address_pools.bind_as_network_default`, `compute.regions.create`, `vpc.networks.set_default_security_group_id`.
- Required relation: `system_admin@cluster:cluster_kacho_root`.
- Required subject_type: `user` (admin-UI/admin-tooling используют user-JWT, не SA-token).
- Risk level: `HIGH` (Region/Zone/DiskType, InternalCloudService.PoolSelector) or `CRITICAL` (InternalAddressPoolService.{Create,Delete,Update}, InternalNetworkService.SetDefaultSecurityGroupId — затрагивает default-SG cluster-wide).
- Requires MFA fresh: `true` (CRITICAL) / `false` (HIGH; per ACR=2 baseline).

### 4.2 Cat-B — Peer / inter-service (17 methods)

- Permission naming: `<domain>.<resource>.<verb_internal>` где `<verb_internal> ∈ {check, lookup, allocate, deallocate, reserve, get_ref, set_ref, clear_ref, subscribe, watch, upsert_identity, write_creator_tuple, list_permissions}`.
- Examples: `iam.authz.check`, `iam.subjects.lookup`, `vpc.addresses.allocate_internal`, `iam.users.upsert_from_identity`, `*.resources.subscribe_lifecycle`.
- Required relation: `service_account@cluster:cluster_kacho_root`.
- Required subject_type: `service_account` (только pod-mounted SA-token).
- Risk level: `MEDIUM` (most peer-RPC) / `HIGH` (`InternalUserService.UpsertFromIdentity` — может создать пользователя; api-gateway-only).
- Requires MFA fresh: `false` (SA-tokens не имеют ACR).

### 4.3 Cat-C — Public-read cluster-scoped (1 method)

- `InternalUserService.Get` — endpoint для admin-UI «list users + view profile». Tenant user читает свой профиль.
- Permission: `iam.users.read_internal`.
- Required relation: `viewer@cluster:cluster_kacho_root` (через cascade `viewer@user:*`).
- Required subject_type: `user` (SA peer-RPC не нужен — есть `InternalIAMService.LookupSubject` для peers).
- Risk level: `LOW`.

### 4.4 RequiredSubjectType — formal enum

В `kacho-proto/proto/kacho/permission_options.proto`:
```proto
enum SubjectType {
  SUBJECT_ANY              = 0;  // not set / catch-all (public RPCs)
  SUBJECT_USER             = 1;  // admin-UI / tenant-user
  SUBJECT_SERVICE_ACCOUNT  = 2;  // pod-mounted k8s SA-token
  SUBJECT_SYSTEM           = 3;  // bootstrap-only (migrations, seed-jobs)
}
```
В catalog JSON выводится как lower-case string `"user"` / `"service_account"` / etc., empty `""` = ANY (legacy public methods until backfill эпик).

### 4.5 Per-method matrix (canonical, sample top of 44)

**Post-reviewer M-05 (resolves OQ-4)**: column `RequiresMFAFresh` (bool) added — `true` для **4 CRITICAL** Cat-A methods (irreversible/destructive admin actions); `false` для остальных. Catalog plugin (`protoc-gen-kacho-permissions`) emits the field; api-gateway step-up gate (`stepup_gate.go`, KAC-127 Phase 2) уже консьюмит `RequiresMFAFresh` — zero-cost wiring.

| FQN | Cat | Permission | Required relation | Required subject_type | Object type | from_request_field | **RequiresMFAFresh** |
|---|---|---|---|---|---|---|---|
| `kacho.cloud.vpc.v1.InternalAddressPoolService/Create` | A | `vpc.address_pools.create` | `system_admin` | `user` | `cluster` | `*` | **true** (CRITICAL — creates infra pool) |
| `kacho.cloud.vpc.v1.InternalAddressPoolService/Delete` | A | `vpc.address_pools.delete` | `system_admin` | `user` | `cluster` | `*` | **true** (CRITICAL — destructive) |
| `kacho.cloud.vpc.v1.InternalAddressPoolService/Update` | A | `vpc.address_pools.update` | `system_admin` | `user` | `cluster` | `*` | **true** (CRITICAL — alters infra routing) |
| `kacho.cloud.vpc.v1.InternalNetworkService/SetDefaultSecurityGroupId` | A | `vpc.networks.set_default_sg` | `system_admin` | `user` | `cluster` | `*` | **true** (CRITICAL — alters tenant network defaults) |
| `kacho.cloud.vpc.v1.InternalAddressPoolService/List` | A | `vpc.address_pools.list` | `system_admin` | `user` | `cluster` | `*` | false |
| `kacho.cloud.vpc.v1.InternalAddressPoolService/BindAsNetworkDefault` | A | `vpc.address_pools.bind_as_network_default` | `system_admin` | `user` | `cluster` | `*` | false |
| `kacho.cloud.vpc.v1.InternalAddressService/AllocateExternalIP` | B | `vpc.addresses.allocate_external` | `service_account` | `service_account` | `cluster` | `*` | n/a (Cat-B — no human MFA) |
| `kacho.cloud.vpc.v1.InternalAddressService/AllocateInternalIP` | B | `vpc.addresses.allocate_internal` | `service_account` | `service_account` | `cluster` | `*` | n/a |
| `kacho.cloud.iam.v1.InternalIAMService/Check` | B | `iam.authz.check` | `service_account` | `service_account` | `cluster` | `*` | n/a |
| `kacho.cloud.iam.v1.InternalIAMService/LookupSubject` | B | `iam.subjects.lookup` | `service_account` | `service_account` | `cluster` | `*` | n/a |
| `kacho.cloud.iam.v1.InternalIAMService/WriteCreatorTuple` | B | `iam.tuples.write_creator` | `service_account` | `service_account` | `cluster` | `*` | n/a |
| `kacho.cloud.iam.v1.InternalUserService/UpsertFromIdentity` | B | `iam.users.upsert_from_identity` | `service_account` | `service_account` | `cluster` | `*` | n/a |
| `kacho.cloud.iam.v1.InternalUserService/Get` | C | `iam.users.read_internal` | `viewer` | `user` | `cluster` | `*` | false |
| `kacho.cloud.compute.v1.InternalZoneService/Create` | A | `compute.zones.create` | `system_admin` | `user` | `cluster` | `*` | false (zone-create reversible) |
| `kacho.cloud.compute.v1.InternalWatchService/Watch` | B | `compute.resources.watch` | `service_account` | `service_account` | `cluster` | `*` | n/a |
| `kacho.cloud.vpc.v1.InternalResourceLifecycleService/Subscribe` | B | `vpc.resources.subscribe_lifecycle` | `service_account` | `service_account` | `cluster` | `*` | n/a |
| ... (full 44 in `permission_options.proto` annotations; всего CRITICAL = 4) | | | | | | | |

---

## 5. Negative scenarios — completeness check

| # | Scenario | Expected gRPC code | Expected reason |
|---|---|---|---|
| N-01 | Regular user calls Cat-A | 7 PermissionDenied | `no path: subject ... has no system_admin on cluster:...` |
| N-02 | Regular user calls Cat-B | 7 PermissionDenied | `subject_type mismatch: required "service_account", got "user"` |
| N-03 | Anonymous calls Cat-A/B/C | 16 Unauthenticated | `subject: unauthenticated request` |
| N-04 | Service-account calls Cat-A | 7 PermissionDenied | `subject_type mismatch: required "user", got "service_account"` |
| N-05 | Service-account WITHOUT cluster-tuple calls Cat-B | 7 PermissionDenied | `no path: subject service_account:sva_x has no service_account on cluster:cluster_kacho_root` |
| N-06 | Expired SA-token (kubelet rotation lag) | 16 Unauthenticated | `token expired` (JWT-verify fail) |
| N-07 | Wrong audience SA-token (`aud=other`) | 16 Unauthenticated | `audience mismatch` |
| N-08 | FGA down (sim via scale-to-zero) | 14 Unavailable | `authz service unavailable: ...` (fail-closed per W1.3) |
| N-09 | Catalog entry malformed (empty permission re-introduced) | 7 PermissionDenied | `catalog: entry has empty permission` (KAC-201 added) |
| N-10 | TLS-listener external call to Internal.* path | 404 Not Found | (not routed to authz-mw at all) |
| N-11 | gRPC-direct call to backend internal-port from outside cluster | network-blocked (NetworkPolicy) или 14 Unavailable | `connection refused` |

---

## 6. Observability & audit

- **Metrics added** (Prometheus):
  - `kacho_authz_decisions_total{outcome="deny", reason="catalog_malformed"}` — RED-counter for §3.2 fail-closed.
  - `kacho_authz_decisions_total{outcome="deny", reason="subject_type_mismatch"}` — for Cat-B violations.
  - `kacho_authz_decisions_total{outcome="allow", risk_level="CRITICAL"}` — should remain low; spike = potential admin abuse.
- **Structured log fields added**:
  - `risk_level` (LOW/MEDIUM/HIGH/CRITICAL) on every authz allow/deny.
  - `subject_type` (user/service_account/system) on every authz decision.
  - `required_subject_type` on every deny with `subject_type_mismatch` reason.
- **Audit-events** (kacho-iam audit-pipeline):
  - `kacho.audit.admin_action` on every Cat-A allow (per workspace «admin-tooling actions are audit-mandatory»).
  - `kacho.audit.access_denied` on every Cat-A/B/C deny.

---

## 7. Definition of Done (Wave-level checklist)

- [ ] proto annotations добавлены для всех 44 Internal.* RPC (`(kacho.permission)` option).
- [ ] `kacho.permission_options.proto` создан, опубликован в kacho-proto.
- [ ] plugin `protoc-gen-kacho-permissions` emit'ит non-empty fields из annotations.
- [ ] `permission_catalog.json` regenerated; 44 Internal.* entries non-empty.
- [ ] Drift-test extended per §2.8; passes.
- [ ] FGA model updated (`define service_account`); migrator re-applied.
- [ ] Bootstrap-tuples extended (system_admin SA, per-service SAs, optional viewer-cascade).
- [ ] **`RequiresMFAFresh: true`** emitted в catalog для **4 CRITICAL Cat-A methods** (resolves OQ-4 per reviewer M-05):
      `InternalAddressPoolService.{Create,Delete,Update}` + `InternalNetworkService.SetDefaultSecurityGroupId`.
      Verified: api-gateway `stepup_gate.go` reads `RequiresMFAFresh` и emit'ит `step_up_required` 403 если `mfaFreshUntil` истёк.
- [ ] api-gateway authz-mw: empty-permission fail-closed (§2.4); subject-type check (§2.5).
- [ ] corelib `Principal.MatchesRequiredSubjectType` helper.
- [ ] backend authzguards (vpc/compute/nlb/iam) honor `required_subject_type` (defence-in-depth).
- [ ] k8s ServiceAccounts создаются helm + token-mount per pod.
- [ ] Integration-tests зелёные (per-category positive + negative).
- [ ] Newman suite `internal-tier-authz` зелёный (176 cases).
- [ ] Reproduction-curl case (5.0-15) GREEN: tenant alice → 403 на `/vpc/v1/addressPools`.
- [ ] Observability dashboards updated (RED-counter, deny-by-reason histogram).
- [ ] Audit-pipeline picks up `kacho.audit.admin_action` events for Cat-A allows.
- [ ] Vault entries updated: `resources/iam-cluster.md` (new relations), `rpc/<all-internal-services>.md` (permission/relation fields), `edges/<peer-calls>.md` (SA-token requirement), `KAC/KAC-201.md` (trail).

---

## 8. Open questions / decisions for reviewer

- **OQ-1**: Include or defer public-RPC permission backfill (~192 entries)? — **Recommendation: defer to separate epic.** KAC-201 scope = 44 Internal.* only; extending breaks ETA and risks scope-creep. Drift-test catches regression on remaining 192 (they stay `entry exists, permission ""` and drift-test reports «empty permission for public FQN» as warning, not error — to be tightened in follow-up).
- **OQ-2**: Cat-C viewer cascade — explicit tuple `cluster:...#viewer@user:*` vs implicit «authenticated user». — **Recommendation: explicit tuple.** FGA's `user:*` wildcard is canonical and self-documenting. Tradeoff: tenant logout still pre-authenticated for InternalUserService.Get — acceptable because the data returned is gated by per-resource ABAC at backend (`user.id == subject.id` only-read-own).
- **OQ-3**: Should `InternalRegionService.{Get,List}` (and Zone/DiskType) be **added** to catalog as part of 5.0 (currently catalog has only `Create/Update/Delete`)? — **Recommendation: NO.** Read paths Geography are public via `compute.v1.RegionService/Zone/DiskType` (already in catalog as public, currently empty — separate epic). Internal-tier *only* covers admin-mutations, which is the security delta.
- **OQ-4 [RESOLVED — M-05]**: Do we add `RequiresMFAFresh: true` for Cat-A CRITICAL via 5.0, or defer step-up gating to a follow-up? — **Decision: ADD NOW** (zafix'ено в §4.5 matrix + §7 DoD). 4 CRITICAL methods classified: `InternalAddressPoolService.{Create,Delete,Update}` + `InternalNetworkService.SetDefaultSecurityGroupId`. Catalog plugin emits `RequiresMFAFresh: true`; api-gateway `stepup_gate.go` (KAC-127 Phase 2) уже консьюмит. ROI high (prevents persistent-stolen-session admin abuse).
- **OQ-5**: Should `InternalWatchService.Watch` (streaming) be Cat-B (service_account-only) or Cat-A (admin-UI may use it)? — **Recommendation: Cat-B service_account.** Admin-UI uses regular polling Lists; Watch is for backend-to-backend lifecycle subscription (current consumers: vpc-implement, controllers). User-token Watch = abuse-vector (long-held streams). If admin-UI later needs streaming, mint dedicated `InternalAdminWatchService` for that with Cat-A.

---

## 9. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Per-service SA-token rollout incomplete → Cat-B peer-RPC start denying real backend calls → cascade outage | Medium | High | Stage rollout: enable subject-type-check **behind feature-flag** `KACHO_API_GATEWAY_AUTHZ_ENFORCE_SUBJECT_TYPE=true`, default false in 5.0 merge, flip to true after 1-week canary verifies all peer-clients authenticate. |
| FGA model migration breaks W1.1 drainer (schema 1.1 → new model_id) | Low | Medium | Tested via drainer-replay (W1.1 integration-test). Migration is additive (`define service_account` is new relation, doesn't break existing). |
| permission-catalog re-emission diff is huge (264 entries × 5 fields) → review-fatigue, missed bad-entry | High | Medium | Catalog stored sorted by FQN (already); diff per category (A/B/C); reviewer reviews per category, not per row. |
| Bootstrap-tuple seed duplicates (re-deploy creates same tuple twice) | High | Low | drainer `fga_outbox` dedupes via UNIQUE; idempotent. |
| User-side `Principal.Type` claim missing in legacy JWTs → empty `subject_type` → fails subject_type check on Cat-A admin who has valid `system_admin` grant | Medium | Medium | Default `subject_type = "user"` when claim missing (matches authz.go:835 today). Document explicit migration: re-issue tokens via Zitadel rotate, or backend always defaults to `user`. |
| **KAC-196 (admin-UI grant) merge задерживается → KAC-201.9 Newman не может создать admin-tuples** через UI-flow | Medium | Low | **Acceptable fallback**: KAC-201.9 Newman setup-step использует temporary direct FGA HTTP API (`POST /stores/<sid>/write` с tuple `cluster:cluster_kacho_root#system_admin@user:usr_test_admin`) — это уже делает stand-bootstrap для seed admin'а. Merge KAC-201 НЕ блокирует merge KAC-196, и наоборот. После того как KAC-196 в main → отдельный follow-up commit меняет Newman setup на `POST /iam/v1/cluster/admins:grant` для тестирования полноты flow. |
| **KAC-178 §3 (alias-relations admin/editor/viewer cascade) задерживается → catalog `required_relation: viewer` для Cat-C не работает каскадно** | Low | Low | Cat-C методов всего 1 (`InternalUserService.Get`). Если KAC-178 §3 не в main к моменту KAC-201.5: тогда **либо** ждём KAC-178 §3 merge (предпочтительно — small scope), **либо** временно ставим `required_relation: system_admin` в catalog v1 и одновременно открываем **explicit follow-up issue** `KAC-201.5-followup-cat-c-viewer-cascade` в `PRO-Robotech/kacho-iam` (метка `tech-debt` + ссылка на KAC-178 §3) — закрывается одним коммитом после KAC-178 §3 merged, который переводит entry обратно на `viewer`. Открытая GitHub Issue — source of truth, **не** TODO-в-PR-описании или TODO-в-коде (workspace CLAUDE.md §«Баги, задачи, tech-debt — GitHub Issues», Запрет #11). |

---

## 10. Verification matrix (Reviewer use)

| § | What | Where to look | Pass criterion |
|---|---|---|---|
| §0 | Reproduction curl | `tests/newman/cases/internal-tier-authz/regress_addresspool_list_tenant_blocked.py` | Test exists, GREEN post-fix, baseline-RED captured in PR |
| §1.1 | Catalog enumeration accurate | `permission_catalog.json` | 44 Internal.* lines × `grep` confirms |
| §2.2 | Per-method matrix complete | `permission_options.proto` annotations | 44 annotations present in proto changes |
| §3.1-3.8 | All 15 scenarios captured in integration + newman | Test files per §13 IT-1, NT-1 | All RED→GREEN pairs documented in PR-описании |
| §4.5 | Sample matrix matches catalog output | regenerated `permission_catalog.json` diff | First-12-rows-sample matches; full 44 in CI artifact |
| §6 | Metrics emitted | Grafana dashboard JSON change | Panels: deny-by-reason, allow-by-risk_level |
| §7 | DoD complete | PR-checklist | All 16 boxes ticked at merge time |

---

## 11. Traceability

| Workspace rule | Where honoured in this doc |
|---|---|
| Запрет #1 (acceptance gate) | This doc IS the gate; status DRAFT until reviewer APPROVED |
| Запрет #2 (no upstream-brand mention) | text-scan: 0 occurrences of forbidden brand-name |
| Запрет #6 (Internal.* not on external endpoint) | §3.7 scenario 13 |
| Запрет #10 (within-service refs via DB) | n/a (no schema-changes in 5.0) |
| Запрет #11 (no TODO/tech-debt) | §0.1 explicitly enumerates out-of-scope (boundary), not TODO |
| Запрет #12 (test-first) | RED→GREEN pairs in §3.1, §3.2 (G1-RED for `entry exists`-only baseline), §3.6 (FGA model-RED) |
| §«Инфра-чувствительные данные» | §3.7 + §4.5 (инфра-поля exposed только через `Internal*`, never public) |
| §«Кросс-доменные ссылки на ресурсы» | §2.7 (peer-clients via SA-token; no FK across services) |
| §«Obsidian vault trail» | §7 DoD checkbox + §13 RT-1 (vault entries) |
| Cross-epic coordination (KAC-178/KAC-196) | §0.5 Prerequisites — explicit scope-split table + ordering DAG |

---

## 12. Out-of-scope (boundary, not tech-debt)

Documented for clarity per Запрет #11 (out-of-scope ≠ TODO):

- **Public RPC permission-catalog backfill** (~192 remaining empty entries) — separate epic, drift-test in 5.0 surfaces as warning, not failure.
- **OPA bundles for backends** — backends already use FGA-Check via authzguard; OPA layer orthogonal.
- **Per-tenant rate-limiting on Cat-A** — abuse-prevention concern, separate observability epic.
- **CAEP push on SA-token revoke** — W3.2 chunk; 5.0 polls via JWT TTL.
- **Move TLS-listener routing to dedicated Ingress** — currently Istio Gateway-based, K8s-ingress + listener-split is a separate infra epic.
- **Per-resource ABAC for Cat-B** (e.g. `vpc.addresses.allocate_internal` could be scoped to network-of-caller's project) — adds ABAC-conditions; orthogonal to subject-type discrimination; future enhancement (KAC-TBD).

---

## 13. Decomposition map (subtasks for KAC-201 epic)

**Pre-condition rows (0a, 0b) — out-of-KAC-201 scope, owned by other epics:**

| # | ID | Title | Repo(s) | Owner | Status |
|---|---|---|---|---|---|
| **0a** | KAC-178.§3 | proto#26 alias-relations (`admin`/`editor`/`viewer` cascade) | `kacho-proto` (+ `kacho-iam` FGA model wiring) | KAC-178 epic | Test |
| **0b** | KAC-196 | `InternalClusterService.GrantAdmin/RevokeAdmin/ListAdmins` RPC + `cluster_admin_grant` DB-table + UI `/system/cluster` | `kacho-proto`, `kacho-iam`, `kacho-api-gateway`, `kacho-ui` | KAC-196 epic | **In Progress** — backend merged 2026-05 (commits 008417a / 7df68f1 / 371e8df / 71f1941 in `kacho-iam`); UI WIP |

KAC-201 subtasks **используют** результат 0a/0b как pre-condition. Если 0b ещё не merged к моменту KAC-201.9 (Newman), используется temporary FGA HTTP API в setup-step (см. §9 Risks/mitigations).

---

Dependency-ordered (top → bottom). Each subtask = separate YouTrack issue + one PR per affected repo. Branch naming: `KAC-201-<short>` per repo.

| # | ID (proposed) | Title | Repo(s) | Predecessor | Role (агент) | Artefacts |
|---|---|---|---|---|---|---|
| **1** | KAC-201.1 | Define `kacho.permission_options.proto` + `SubjectType` enum | `kacho-proto` | — | `proto-sync` | new .proto + buf-lint green |
| **2** | KAC-201.2 | Extend `protoc-gen-kacho-permissions` plugin to read `(kacho.permission)` option, emit `RequiredSubjectType` | `kacho-iam` (or wherever plugin lives) | KAC-201.1 | `rpc-implementer` | plugin code + unit-tests |
| **3** | KAC-201.3 | Add `(kacho.permission)` annotations to all 44 Internal.* RPC | `kacho-proto` | KAC-201.2 | `proto-sync` | 7 internal_*.proto files updated; gen/ regenerated |
| **4** | KAC-201.4 | FGA model `define service_account` + bootstrap-tuples for service-account-per-backend + admin-SA | `kacho-iam`, `kacho-deploy` | — (parallel with KAC-201.1) | `migration-writer` | model.fga + bootstrap_tuples builder + integration-test (drainer pickup) |
| **5** | KAC-201.5 | Gateway authz-mw: empty-permission fail-closed + subject-type discrimination | `kacho-api-gateway` | KAC-201.3 | `rpc-implementer` | authz.go + permission_catalog.go diff + unit-tests + RED-test for §3.2 |
| **6** | KAC-201.6 | corelib `Principal.MatchesRequiredSubjectType` + backend authzguards honor it | `kacho-corelib`, `kacho-vpc`, `kacho-compute`, `kacho-nlb`, `kacho-iam` | KAC-201.5 | `rpc-implementer` | helper + per-service authzguard wiring + integration-tests |
| **7** | KAC-201.7 | k8s ServiceAccounts + token-mount + peer-client SA-token wiring | `kacho-deploy`, `kacho-vpc`, `kacho-compute`, `kacho-nlb`, `kacho-api-gateway` | KAC-201.4, KAC-201.6 | `migration-writer` (helm) + `rpc-implementer` (clients) | helm values + deployment.yaml + iam_client.go (etc.) updates |
| **8** | KAC-201.8 | Drift-test tightening for Internal.* entries | `kacho-iam` | KAC-201.3 | `integration-tester` | drift_test.go extension |
| **9** | KAC-201.9 | Newman suite `internal-tier-authz` (44 × 3 personae × 4 outcomes = ~176 cases) + reproduction-curl regression | `kacho-iam` (tests/newman/cases) | KAC-201.5–7 | `integration-tester` | gen.py + cases/*.py + GREEN run |
| **10** | KAC-201.10 | Vault trail: update resources/iam-cluster.md, rpc/<internal-services>.md, edges/<peer-edges>.md, KAC/KAC-201.md | `kacho-workspace` (obsidian) | KAC-201.5–9 (after merge) | `acceptance-author` (этот агент) | 8-10 vault entries updated |
| **11** | KAC-201.RT-1 | Audit-event types `kacho.audit.admin_action` / `access_denied` extended with `risk_level` field | `kacho-iam`, `kacho-corelib/audit` | KAC-201.5 | `rpc-implementer` | audit-pipeline schema update |
| **12** | KAC-201.RT-2 | Grafana dashboards updated (deny-by-reason panel, allow-by-risk_level panel) | `kacho-deploy` (observability/grafana) | KAC-201.5 | `migration-writer` | dashboard JSON + screenshot in PR |

**Critical path**: KAC-201.1 → .2 → .3 → .5 → .7 → .9 → .10. Total: ~10-15 PRs across 6 repos. Estimated 2 weeks E2E (assuming 1-2 reviewers per PR + standard CI cycle).

**Merge order** (graph topological):
1. `kacho-proto` (KAC-201.1, .3)
2. `kacho-iam` (KAC-201.2, .4, .8, .9, .RT-1)
3. `kacho-corelib` (KAC-201.6 helper part)
4. `kacho-api-gateway` (KAC-201.5)
5. `kacho-vpc`, `kacho-compute`, `kacho-nlb` (KAC-201.6 authzguard + KAC-201.7 peer-clients) — parallel
6. `kacho-deploy` (KAC-201.4 seed + .7 helm + .RT-2 grafana)
7. `kacho-workspace` (KAC-201.10 vault — last, summarising trail)

Каждый PR ссылается на KAC-201 (parent) + свой subtask. CI cross-repo pinning per CLAUDE.md «Кросс-репо зависимости» — пока KAC-201.X не в main, KAC-201.Y временно `ref:` на feature-ветку.

---

#kac #epic #security #authz #iam #internal
