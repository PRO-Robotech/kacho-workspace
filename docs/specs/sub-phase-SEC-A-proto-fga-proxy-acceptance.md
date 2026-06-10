# Sub-phase SEC-A — Proto: Internal IAM FGA-proxy RPC (RegisterResource / UnregisterResource) — Acceptance

> Статус: DRAFT
> Дата: 2026-06-11
> Ревьюер: acceptance-reviewer
> Эпик/тикет: KAC-SEC (эпик `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`), подфаза **SEC-A**
> Версия: v2 (закрывает acceptance-review v1 — критические п.1-2; опирается на эпик §4.1 ground-truth)

## Обзор

Подфаза SEC-A добавляет в `kacho-proto` два **Internal-only** RPC в существующий
`InternalIAMService` (`proto/kacho/cloud/iam/v1/internal_iam_service.proto`,
package `kacho.cloud.iam.v1`): `RegisterResource` и `UnregisterResource`. Это контракт
**FGA-proxy** — через него vpc/compute/nlb перестанут писать owner-hierarchy-tuple
напрямую в OpenFGA (требование эпика #6: «модули не ходят в FGA напрямую, только через
IAM») и начнут декларировать намерение «зарегистрировать/снять owner-tuple» через IAM
(реализация — SEC-C/SEC-D, Вариант A transactional-outbox §3.1 эпика). Подфаза —
**proto + buf только**, без Go-реализации.

Ключевые контрактные свойства, фиксируемые здесь:
- форма сообщений (`subject_id` / `relation` / `object` / `trace_id`), симметрично существующим `CheckRequest` / `WriteCreatorTupleRequest`;
- **идемпотентность как контракт**: повтор register того же owner-tuple → gRPC `OK` (не `ALREADY_EXISTS`); unregister отсутствующего → gRPC `OK` (не `NOT_FOUND`) — от этого зависит outbox-retry-цепочка SEC-D (требование #6 / §3.1 / §6.1 эпика, fail-closed §6.7);
- **per-RPC authz-опция `permission = "<exempt>"`** — как у всех 7 текущих `InternalIAMService` RPC. Least-privilege энфорсится НЕ через permission-каталог, а через **ReBAC в IAM-handler** (SEC-C): mTLS client-cert → ServiceAccount (SEC-B), затем проверка relation `fga_writer` на системном объекте `iam_fgaproxy:system`. Это канон эпика §4.1 п.1 (закрывает критику v1);
- регистрация **только** на internal mux :9091 — не на external endpoint (ban #6 / security.md «Internal admin-RPC только на :9091»);
- **public breaking-diff = 0**: публичные ресурсные контракты не тронуты (требование #8); добавление RPC в Internal-сервис — additive (FILE breaking-rule зелёный).

Трассировка: каждый сценарий помечен требованием эпика (#1–#8) и/или решением §3 / §4.1 / §6.

---

## Канон §4.1 эпика, применённый к SEC-A (закрывает acceptance-review v1)

acceptance-review v1 заблокировал прежний вариант, где RPC несли
`permission = "iam.fgaproxy.write"` без обязательных для non-exempt записей
`required_relation` + `scope_extractor`. Это противоречит контракту опции authz и
ведёт к красному CI (warnings-файл → `verify-catalog` / strict `verify-permissions-coverage`).
Эпик §4.1 п.1-3 даёт канонические решения, принятые ниже:

1. **authz-механизм fgaproxy = `<exempt>` + ReBAC (§4.1 п.1).** Оба RPC несут
   `option (kacho.iam.authz.v1.permission) = "<exempt>"`. Это совпадает с обработкой
   плагина `protoc-gen-kacho-permissions`: для `<exempt>` обязательные поля
   `required_relation` / `scope_extractor` **не проверяются** (extractEntry short-circuit),
   warnings не пишутся. Least-priv энфорсится в IAM-handler (SEC-C): mTLS client-cert →
   SA → ReBAC-проверка relation `fga_writer` на объекте `iam_fgaproxy:system`. Tuple
   `service_account:<sva> # fga_writer @ iam_fgaproxy:system` выдаётся модульным SA в seed
   (SEC-C). Нет relation → `PERMISSION_DENIED`. Это ReBAC, НЕ flat-capability и НЕ каталог-scope.
2. **permission-строка `iam.fgaproxy.write` НЕ вводится (§4.1 п.3).** Механизм — exempt+ReBAC,
   отдельная permission-строка не нужна и не добавляется в `gen/permission_catalog.json`.
   Прежняя формулировка SEC-A-03 «НЕ `<exempt>`» отозвана.
3. **service→service вызовы освобождены от `required_acr_min` (§4.1 п.2).** ACR-floor
   применяется только к user-token-флоу; у SA нет MFA, его аутентификация — mTLS client-cert.
   Для `<exempt>` RPC `required_acr_min` в каталог не попадает по контракту (см. SEC-A-03).
4. **SPIFFE SAN — существующий SPIRE-формат (§4.1 п.4):** `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>`
   (umbrella уже несёт spire-server/agent/csi subchart'ы + `spiffe.trustDomain`). cert-manager
   выдаёт string-SAN в этом же формате. SEC-A прямо НЕ кодирует SAN в proto (это SEC-B/SEC-F),
   но фиксирует канон, чтобы proto-комментарии не вводили устаревший `spiffe://kacho/<sva-id>`.
5. **Реальные имена ресурсов берутся ЭМПИРИЧЕСКИ из `kacho-proto/gen/permission_catalog.json`
   (§4.1 п.3).** В SEC-A это влияет только на пример FGA-object в proto-комментарии (он
   описывает FGA authorization-model object-type, а не permission-каталог) — см. примечание к форме.

---

## Точные proto-локации и форма (нормативно для SEC-A)

- **Файл**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto`, сервис `InternalIAMService`.
- **Новые RPC** (добавляются в конец списка методов сервиса, gRPC-only — REST-аннотация
  `google.api.http` НЕ добавляется, чтобы они физически не попали в grpc-gateway external-mux;
  вызов — только напрямую service→service по mTLS и через api-gateway internal mux, SEC-E):

  ```protobuf
  // RegisterResource — Internal FGA-proxy: применить owner-hierarchy tuple
  // (subject имеет relation на object'е) от имени модуля-владельца ресурса.
  // Вызывается outbox-drainer'ом vpc/compute/nlb (SEC-D) по mTLS.
  // ИДЕМПОТЕНТНО (контракт): повтор того же (subject,relation,object) → OK,
  // НЕ AlreadyExists. От этого зависит at-least-once outbox-retry (§3.1 эпика).
  //
  // authz: <exempt> на уровне permission-каталога. Least-priv энфорсится в
  // handler (SEC-C) через ReBAC: mTLS client-cert → ServiceAccount → relation
  // `fga_writer` на объекте `iam_fgaproxy:system`. Нет relation → PermissionDenied.
  rpc RegisterResource (RegisterResourceRequest) returns (RegisterResourceResponse) {
    option (kacho.iam.authz.v1.permission) = "<exempt>";
  }

  // UnregisterResource — Internal FGA-proxy: снять owner-hierarchy tuple.
  // ИДЕМПОТЕНТНО (контракт): удаление отсутствующего tuple → OK, НЕ NotFound.
  // authz: <exempt> + ReBAC fga_writer @ iam_fgaproxy:system (см. RegisterResource).
  rpc UnregisterResource (UnregisterResourceRequest) returns (UnregisterResourceResponse) {
    option (kacho.iam.authz.v1.permission) = "<exempt>";
  }
  ```

- **Сообщения** (форма симметрична `CheckRequest` / `WriteCreatorTupleRequest` —
  `subject_id` / `relation` / `object` строки FGA-формата; `trace_id` как в `CheckRequest`):

  ```protobuf
  message RegisterResourceRequest {
    // FGA-subject: "user:<usr_xxx>" | "service_account:<sva_xxx>" | "<owner-type>:<id>".
    string subject_id = 1 [(required) = true, (length) = "<=128"];
    // FGA-relation owner-tuple (как правило "admin" / "parent").
    string relation   = 2 [(required) = true, (length) = "<=32"];
    // FGA-object: "<type>:<id>" из authorization-model, напр.
    // "vpc_network:<enp>", "compute_instance:<...>".
    string object     = 3 [(required) = true, (length) = "<=128"];
    // Correlation trace-id (optional) — для сшивки логов модуль↔IAM↔FGA.
    string trace_id   = 4 [(length) = "<=64"];
  }
  message RegisterResourceResponse {}      // пусто — success implicit (gRPC OK)

  message UnregisterResourceRequest {
    string subject_id = 1 [(required) = true, (length) = "<=128"];
    string relation   = 2 [(required) = true, (length) = "<=32"];
    string object     = 3 [(required) = true, (length) = "<=128"];
    string trace_id   = 4 [(length) = "<=64"];
  }
  message UnregisterResourceResponse {}    // пусто — success implicit (gRPC OK)
  ```

  > FGA-object в `object`-поле — это object-type **authorization-model OpenFGA** (`vpc_network`,
  > `compute_instance`, …), НЕ permission-каталог `<module>.<resource>.<verb>`. Это разные
  > пространства имён; SEC-A фиксирует только форму строки. Конкретные object-type — модель FGA
  > (SEC-C), а не `permission_catalog.json`.

- **Authz-опция**: `permission = "<exempt>"` на обоих RPC (как 7 текущих `InternalIAMService`
  RPC). Запись в каталоге будет иметь форму exempt-прецедента (пустые `required_relation` /
  `scope_extractor` / без `required_acr_min`) — см. SEC-A-03. **`iam.fgaproxy.write` как
  permission-строка НЕ вводится** (механизм — exempt+ReBAC, §4.1 п.1/п.3).
- **Идемпотентность** — свойство **контракта**, не реализации. SEC-A фиксирует его в
  proto-комментарии и в acceptance; верифицируется conformance-/integration-тестами в SEC-C
  (репо kacho-iam). Здесь — только сценарии-ожидания + proto-форма.

Стандартные конвенции (`Operation` для мутаций, error-format, ID-формат) — нормативны по
`.claude/rules/api-conventions.md`; **исключение по дизайну**: эти два RPC — sync
unary (как `Check` / `WriteCreatorTuple`), НЕ async через `Operation`, т.к. они вызываются
из outbox-drainer'а, который сам обеспечивает retry/at-least-once (§3.1 эпика). Это
осознанное решение, симметричное уже существующему `WriteCreatorTuple`.

---

## Сценарий SEC-A-01: Форма сообщений RegisterResource (proto-контракт)

**ID:** SEC-A-01   (трассировка: эпик #6, §3.1; форма симметрична `WriteCreatorTuple`)

**Given** ветка `kacho-proto` SEC-A с правкой `internal_iam_service.proto`
**And** `make generate` (buf generate + plugin) выполнен

**When** инспектируется сгенерированный дескриптор `InternalIAMService` и Go-stubs

**Then** существует RPC `RegisterResource(RegisterResourceRequest) returns (RegisterResourceResponse)` в сервисе `kacho.cloud.iam.v1.InternalIAMService`
**And** `RegisterResourceRequest` имеет ровно поля: `subject_id` (1, string, `required`, `length<=128`), `relation` (2, string, `required`, `length<=32`), `object` (3, string, `required`, `length<=128`), `trace_id` (4, string, `length<=64`)
**And** `RegisterResourceResponse` — пустой message (0 полей), как существующий `WriteCreatorTupleResponse`
**And** RPC НЕ имеет `option (google.api.http)` (gRPC-only, не маршрутизируется grpc-gateway external-mux)
**And** RPC НЕ имеет `option (kacho.cloud.api.operation)` (sync unary, не Operation)
**And** RPC имеет `option (kacho.iam.authz.v1.permission) = "<exempt>"` и НЕ имеет `required_relation` / `scope_extractor` / `required_acr_min`

## Сценарий SEC-A-02: Форма сообщений UnregisterResource (proto-контракт)

**ID:** SEC-A-02   (трассировка: эпик #6, §3.1)

**Given** та же ветка SEC-A с регенерацией

**When** инспектируется дескриптор `InternalIAMService`

**Then** существует RPC `UnregisterResource(UnregisterResourceRequest) returns (UnregisterResourceResponse)`
**And** `UnregisterResourceRequest` имеет поля идентично register (`subject_id` / `relation` / `object` / `trace_id` с теми же типами / номерами / аннотациями)
**And** `UnregisterResourceResponse` — пустой message
**And** RPC НЕ имеет `option (google.api.http)` и НЕ имеет `option (kacho.cloud.api.operation)`
**And** RPC имеет `option (kacho.iam.authz.v1.permission) = "<exempt>"` (как register)

## Сценарий SEC-A-03: authz-опция <exempt> — запись каталога как у прецедента, без warnings

**ID:** SEC-A-03   (трассировка: эпик §4.1 п.1/п.3 ground-truth; security.md Internal admin-RPC; закрывает критику v1 п.1-2)

**Given** оба RPC несут `option (kacho.iam.authz.v1.permission) = "<exempt>"` (без `required_relation` / `scope_extractor`)
**And** `make generate` выполнен (плагин `protoc-gen-kacho-permissions` отрабатывает)

**When** читается `gen/permission_catalog.json` и `gen/permission_catalog_warnings.txt`

**Then** есть запись `{"fqn":"kacho.cloud.iam.v1.InternalIAMService/RegisterResource","permission":"<exempt>","required_relation":"","scope_extractor":{"object_type":"","from_request_field":""}}` — форма идентична существующим exempt-записям (`Check`, `WriteCreatorTuple`, `LookupSubject` …)
**And** есть аналогичная запись для `.../UnregisterResource`
**And** **`permission_catalog_warnings.txt` НЕ содержит** offending-FQN для register/unregister (плагин для `<exempt>` short-circuit'ит required-fields-проверку → warnings не пишутся) — warnings-файл либо отсутствует, либо его прежнее содержимое не меняется этими RPC
**And** `make verify-catalog` зелёный: `git diff --exit-code gen/permission_catalog.json gen/permission_catalog_warnings.txt` = 0 (каталог + warnings закоммичены консистентно с регенерацией)
**And** `make verify-permissions-coverage` (strict `KACHO_PERMISSIONS_STRICT=1`) зелёный — exempt-RPC не дают warnings, strict-mode не фейлит
**And** `iam.fgaproxy.write` отсутствует в `permission_catalog.json` (permission-строка не вводится, §4.1 п.3)

## Сценарий SEC-A-04: least-priv fgaproxy = ReBAC fga_writer @ iam_fgaproxy:system (нормативное ожидание для SEC-C)

**ID:** SEC-A-04   (трассировка: эпик #4 least-privilege, §3.3, §4.1 п.1/п.2; security.md)

**Given** RPC `RegisterResource` / `UnregisterResource` — `<exempt>` (SEC-A-03), т.е. permission-каталог их не гейтит
**And** канон §4.1 п.1: least-priv энфорсится ReBAC в IAM-handler (SEC-C)

**When** (нормативное ожидание, реализуется/тестируется в SEC-C) IAM-handler получает вызов register/unregister

**Then** контракт обязывает: handler резолвит caller через mTLS client-cert → ServiceAccount (SEC-B identity-extractor), затем проверяет relation `fga_writer` на объекте `iam_fgaproxy:system`
**And** SA имеет relation (выдан seed-tuple `service_account:<sva> # fga_writer @ iam_fgaproxy:system` в SEC-C) → вызов допускается
**And** SA НЕ имеет relation → `PERMISSION_DENIED` (least-priv: чужой/непривилегированный SA не может писать owner-tuple)
**And** service→service вызов SA освобождён от `required_acr_min` (§4.1 п.2 — у SA нет MFA; аутентификация = mTLS client-cert)
**And** SEC-A не реализует это (proto+buf only) — фиксирует как нормативное требование к SEC-C (conformance-кейс там); SEC-A гарантирует, что proto/контракт не противоречит ReBAC-энфорсу (нет permission-строки, опция `<exempt>`)

## Сценарий SEC-A-05: Идемпотентность register — контракт (ожидание, фиксируется для SEC-C)

**ID:** SEC-A-05   (трассировка: эпик #6, §3.1 «повтор owner-tuple → OK не AlreadyExists», §6.1)

**Given** контракт `RegisterResource` (proto-комментарий явно фиксирует идемпотентность)

**When** клиент дважды вызывает `InternalIAMService.RegisterResource` с одинаковым payload:
  - subject_id = `user:usr-abc`
  - relation = `admin`
  - object = `vpc_network:enp-xyz`

**Then** контракт обязывает: первый вызов → gRPC `OK`; повторный (тот же tuple) → gRPC `OK` (НЕ `ALREADY_EXISTS`)
**And** это зафиксировано как нормативное требование к реализации SEC-C (conformance-кейс там); SEC-A гарантирует, что proto/контракт не противоречит идемпотентности (нет Operation, нет уникального ответа-id, ответ пустой)

## Сценарий SEC-A-06: Идемпотентность unregister — контракт (ожидание, фиксируется для SEC-C)

**ID:** SEC-A-06   (трассировка: эпик #6, §3.1 «delete отсутствующего → OK», §6.1)

**Given** контракт `UnregisterResource`

**When** клиент вызывает `UnregisterResource` с tuple, которого нет (или уже снят):
  - subject_id = `user:usr-abc`
  - relation = `admin`
  - object = `vpc_network:enp-nonexistent`

**Then** контракт обязывает: gRPC `OK` (НЕ `NOT_FOUND`)
**And** повторный unregister того же tuple → снова `OK` (идемпотентно)
**And** зафиксировано как нормативное требование к SEC-C; SEC-A proto-форма не противоречит (пустой response, нет error-нагруженного результата)

## Сценарий SEC-A-07: Negative — invalid input (контракт валидации)

**ID:** SEC-A-07   (трассировка: api-conventions.md error-format; validation-аннотации `(required)` / `(length)`)

**Given** поля `subject_id` / `relation` / `object` помечены `(required) = true` с `length`-ограничениями (как `CheckRequest`)

**When** реализация (SEC-C) получает запрос с пустым `object` (или `subject_id` длиннее 128, или `relation` длиннее 32)

**Then** контракт обязывает sync `INVALID_ARGUMENT` (валидация по `(required)` / `(length)`, как у `CheckRequest`)
**And** SEC-A гарантирует наличие этих аннотаций в proto (верифицируется инспекцией дескриптора в SEC-A-01/02); фактический возврат кода — conformance-кейс SEC-C

## Сценарий SEC-A-08: buf lint зелёный

**ID:** SEC-A-08   (трассировка: polyrepo.md «единый buf lint — гейт»; DoD эпика)

**Given** ветка SEC-A с новыми RPC и сообщениями

**When** выполняется `make buf-lint` (`buf lint`)

**Then** выход 0, нарушений нет
**And** имена сообщений (`RegisterResourceRequest` / `Response`, `UnregisterResourceRequest` / `Response`) соответствуют STANDARD-набору с действующими `except` из `buf.yaml`
**And** новых `except` / `ignore` в `buf.yaml` под эти RPC НЕ добавлено (форма уже lint-чистая, как `WriteCreatorTuple`)

## Сценарий SEC-A-09: buf breaking зелёный (additive к Internal-сервису)

**ID:** SEC-A-09   (трассировка: эпик #8 «контракты не меняются», DoD «proto breaking-diff»)

**Given** ветка SEC-A
**And** `buf.yaml` breaking-конфиг — `use: FILE`

**When** выполняется `make buf-breaking` (`buf breaking --against ".git#branch=main"`)

**Then** выход 0
**And** изменение — чисто additive: добавлены RPC + новые message'ы, ни один существующий RPC / поле / номер не удалён и не переименован, существующие field-номера не переиспользованы

## Сценарий SEC-A-10: public breaking-diff = 0 (публичные сервисы не тронуты)

**ID:** SEC-A-10   (трассировка: эпик #8, требование «public breaking-diff = 0», DoD)

**Given** ветка SEC-A
**And** изменён ТОЛЬКО `internal_iam_service.proto` (Internal-сервис)

**When** сравнивается diff публичных ресурсных `.proto` (vpc / compute / iam public services, api/operation, validation, authz_options) против `main`

**Then** ни один публичный (не-`Internal*`) сервис / message не изменён (`git diff main -- proto/ ':!**/internal_*'` по сервис-контрактам = 0 семантических изменений)
**And** breaking-проверка на множестве публичных сервисов даёт 0 breaking-изменений
**And** добавление новых RPC в `InternalIAMService` не влияет на форму публичных ресурсов (требование #8 соблюдено)

## Сценарий SEC-A-11: Internal-only — не на external endpoint (ban #6)

**ID:** SEC-A-11   (трассировка: эпик #5, ban #6, security.md «Internal admin-RPC только на :9091»)

**Given** новые RPC добавлены в `InternalIAMService` (visibility: internal, backend :9091)
**And** у RPC нет `google.api.http`-аннотации (не попадают в external grpc-gateway REST-mux)

**When** оценивается поверхность экспозиции

**Then** контракт фиксирует: `RegisterResource` / `UnregisterResource` маршрутизируются ТОЛЬКО на cluster-internal listener :9091 и (если нужно UI/tooling REST) через api-gateway **internal** mux — НИКОГДА на external TLS `api.kacho.local:443`
**And** ответственность за фактическую internal-mux-регистрацию — `api-gateway-registrar` в SEC-E (этот сценарий — нормативный инвариант, который SEC-E обязан соблюсти: external-allowlist НЕ содержит fgaproxy-путей)
**And** SEC-A гарантирует proto-предусловие (нет http-аннотации) — верифицируется в SEC-A-01/02

## Сценарий SEC-A-12: ацикличность — fgaproxy-рёбра не вводят цикл

**ID:** SEC-A-12   (трассировка: эпик §6.6 «ацикличность подтверждена», polyrepo.md «циклы запрещены»)

**Given** новые RPC потребляются vpc→iam / compute→iam / nlb→iam (drainer→IAM.RegisterResource, SEC-D)
**And** `kacho-iam` НЕ импортирует и НЕ зовёт vpc / compute / nlb

**When** фиксируются runtime-edges в `polyrepo.md`

**Then** fgaproxy-рёбра (vpc→iam, compute→iam, nlb→iam) — усиление уже существующего направления `*→iam` (Check / ProjectService.Get), цикл не вводится
**And** новые edges документируются в `polyrepo.md` (runtime-edge) и vault `edges/vpc-to-iam-fgaproxy.md` / `compute-to-iam-fgaproxy.md` / `nlb-to-iam-fgaproxy.md` (создаются в SEC-A trail; реальное поведение — SEC-D). NLB-сервис — канонически `kacho-nlb` (§4.1 п.6; legacy `kacho-loadbalancer` не использовать)

## Сценарий SEC-A-13: verify-no-yandex и no-cloud-naming

**ID:** SEC-A-13   (трассировка: ban #2)

**Given** новые proto-комментарии и имена

**When** выполняется `make verify-no-yandex` (`! grep -ri 'yandex' proto/ gen/`)

**Then** выход 0 — ни в RPC-комментариях, ни в каталоге нет упоминаний чужих облаков
**And** контракт сформулирован в терминах Kachō (FGA-proxy / owner-tuple / IAM), без «как у X»

---

## DoD подфазы SEC-A

- [ ] `internal_iam_service.proto`: добавлены `RegisterResource` / `UnregisterResource` RPC + 4 message'а (`Register/UnregisterResourceRequest/Response`) по форме выше; **authz-опция `permission = "<exempt>"` на обоих** (без `required_relation` / `scope_extractor` / `required_acr_min`); без `google.api.http`, без `operation`-опции; proto-комментарий явно фиксирует идемпотентность + ReBAC-энфорс fga_writer @ iam_fgaproxy:system (SEC-A-01/02/03/04/05/06).
- [ ] `make generate` — Go-stubs + `gen/permission_catalog.json` + `gen/permission_catalog_warnings.txt` регенерированы и закоммичены; register/unregister попали в каталог как exempt-записи; warnings-файл НЕ получил offending-FQN для этих RPC (SEC-A-03).
- [ ] `make verify-catalog` зелёный — `git diff --exit-code gen/permission_catalog.json gen/permission_catalog_warnings.txt` = 0 (SEC-A-03).
- [ ] `make verify-permissions-coverage` (strict) зелёный — exempt-RPC не дают warnings (SEC-A-03).
- [ ] `make buf-lint` зелёный без новых `except` (SEC-A-08).
- [ ] `make buf-breaking` зелёный — additive (SEC-A-09).
- [ ] public breaking-diff = 0 — изменён только Internal-сервис, публичные контракты нетронуты (SEC-A-10); ban #6 proto-предусловие (нет http-аннотации) соблюдено (SEC-A-11).
- [ ] `make verify-no-yandex` зелёный (SEC-A-13).
- [ ] `polyrepo.md` обновлён fgaproxy-рёбрами (vpc/compute/nlb→iam) + не-цикл-инвариантом (SEC-A-12; §6.6 эпика); NLB упомянут как `kacho-nlb`.
- [ ] Тесты для контракта (этот PR / kacho-proto): см. ниже «proto-conformance / buf тесты». Идемпотентность / коды / ReBAC-энфорс (SEC-A-04/05/06/07) — нормативные ожидания, RED-тесты под них пишутся как conformance в SEC-C (kacho-iam) и newman в сервисных репо (SEC-D/SEC-E); зафиксированы здесь для трассировки 1:1.
- [ ] vault-trail: `rpc/iam-internal-iam-service.md` (+2 метода; **methods_count 7→9** — реальный proto уже содержит 7 RPC: `LookupSubject` / `ListPermissions` / `Check` / `WriteCreatorTuple` / `GetJWKSStatus` / `ForceLogout` / `PollSubjectChanges`; vault-запись `methods_count: 3` stale — актуализировать как часть trail), новые `edges/*-to-iam-fgaproxy.md` (planned), `KAC/KAC-<SEC-A>.md`.

## Тесты, подтверждающие сценарии (TDD-red), 1:1 к ID

SEC-A — proto+buf-only, поэтому «тесты» подфазы — это CI-гейты на proto-контракт +
descriptor-assert; полные integration / newman-кейсы на поведение (идемпотентность,
коды, ReBAC-энфорс) пишутся RED в зависимых подфазах (SEC-C / SEC-D / SEC-E) и
трассируются к ID отсюда. Newman-харнесс живёт в **сервисных репо** (`kacho-<svc>/tests/newman`),
не в kacho-deploy (§4.1 п.5); `make e2e-test` в kacho-deploy = bash-смоук `e2e/0.1/*.sh`.

**В этом PR (kacho-proto) — RED → GREEN proto-гейты:**
- `make buf-lint` (SEC-A-08) — RED до правки невозможен (RPC ещё нет); GREEN после.
- `make buf-breaking` против `main` (SEC-A-09) — должен остаться зелёным (additive).
- `make verify-catalog` (SEC-A-03) — RED, если каталог/warnings не регенерированы / не закоммичены; GREEN после `make generate` + commit. **Проверить именно отсутствие warnings-FQN** для register/unregister (контракт exempt).
- `make verify-permissions-coverage` strict (SEC-A-03) — GREEN: exempt не фейлит strict-mode.
- `make verify-no-yandex` (SEC-A-13).
- Descriptor-assert (Go-тест в `kacho-proto`, reflect-проверка дескриптора или CI-скрипт): сервис `InternalIAMService` содержит `RegisterResource` / `UnregisterResource`; request-сообщения имеют ровно ожидаемые поля / номера / аннотации; ни у одного из RPC нет `google.api.http` / `operation`-опции; `permission = "<exempt>"`, нет `required_relation` / `scope_extractor` (SEC-A-01/02/03/11). RED до правки proto, GREEN после.
- public-no-change-assert (CI-скрипт): `git diff --stat main -- proto/ ':(exclude)**/internal_*'` по сервис-контрактам = 0 (SEC-A-10).

**Нормативные ожидания для зависимых подфаз (зафиксированы здесь, RED пишется там):**
- SEC-C kacho-iam integration / conformance: `RegisterResource` повтор → `OK` не `AlreadyExists` (SEC-A-05); `UnregisterResource` отсутствующего → `OK` не `NotFound` (SEC-A-06); пустой / превышающий `object` / `subject_id` / `relation` → `INVALID_ARGUMENT` (SEC-A-07); **caller-SA без relation `fga_writer` на `iam_fgaproxy:system` → `PERMISSION_DENIED`** (SEC-A-04 ReBAC least-priv); IAM↔FGA недоступен → `UNAVAILABLE` (§6.7 fail-closed). Эти тесты — testcontainers-integration + (где применимо) bufconn-conformance в kacho-iam.
- SEC-D / SEC-E newman (через api-gateway, харнесс `kacho-vpc/tests/newman` etc.): fgaproxy-путь отвечает на internal mux и НЕ отвечает на external TLS listener (SEC-A-11, аналог существующего `iam-internal-only-check` кейса); happy «register после Create ресурса» + negative «register чужим SA → PermissionDenied».
