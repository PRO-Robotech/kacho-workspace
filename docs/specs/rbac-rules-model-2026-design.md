Этот запрос — задача синтеза документа: у меня на руках синтезированный дизайн, подтверждённые ограничения и три набора adversarial-находок. Файловое исследование не требуется; результат — сам финальный документ. Произвожу его.

# Kachō IAM — Каноническая модель данных Role + AccessBinding (2026, финал)

> Финальный design-документ. Синтез четырёх линз сведён с adversarial-верификацией (3 независимых ревью против ground-truth). Все must-fix-находки применены. Артефакт под APPROVE (gate `acceptance-reviewer`, ban #1); из него `acceptance-author` строит Given-When-Then напрямую — каждый blocking-сценарий вынесен в §10.

---

## 0. Что изменено после верификации

Верификация (3 ревью против реального кода: `permissions_to_relations.go`, `fga_tuple_writer_v2.go`, `fga_model.fga`, applied-миграции `0001..0023`, live `role.proto`/`access_binding.proto`) выявила, что **центральный security-тезис синтеза был ложен для default-арма**, плюс три секции мигра-плана оказались phantom-работой (уже отгружено в `0005`/`0008`). Применены следующие must-fix:

1. **[CRITICAL — escalation-engine] all_in_scope больше НЕ эмитит whole-role tier на голый scope-anchor.** Ground-truth: `tuplesForBinding → PermissionsToRelations(role.Permissions)` type-blind — сворачивает ВСЮ роль в один сильнейший tier и пишет его на anchor (`account:X`/`project:X`), а FGA-модель каскадит anchor.admin на ВСЕ типы. Reference-JSON пользователя (`compute.instance verbs:[*]` all_in_scope @ ACCOUNT) дал бы account-wide admin над vpc/iam/всем. **Фикс:** all_in_scope эмитит **per-(module,resource) type-scoped** tuple через новый FGA-примитив `scope_grant` (§5), НЕ collapsed `PermissionsToRelations(role)` на raw anchor. Это требует **изменения FGA-модели** (раздел больше не «zero new FGA primitives»). См. §5, §8, GWT-1/GWT-2.
2. **[CRITICAL — verb-`*`] verb-`*` переклассифицирован: это admin-tier, НЕ «bounded».** `verbClass('*')=classAdmin` → наследует все derived-relations (ssh/console/manage, включая step-up-gated). Снято утверждение «безопасно/bounded». **Решение:** verb-`*` в custom-роли **запрещён** (parity с module/resource-`*`); admin-намерение выражается явным перечислением verbs или is_system. См. §4, §8, GWT-3.
3. **[CRITICAL — revocation] mutable `rules[]` ломал byte-symmetric revoke.** `delete.go` re-derive'ит tuple-set из ТЕКУЩЕЙ роли. **Фиксы:** (a) revoke удаляет **сохранённый при grant** tuple-set (`access_binding_emitted_tuples`), не re-derive; (b) `Role.Update(rules)` фан-аутит reconcile по ВСЕМ ACTIVE-биндингам роли (bounded, §6); (c) reconciler-membership ключуется **content-hash правила** (`rule_fp`), не позиционным `rule_index`. См. §5, §6, GWT-4/GWT-5.
4. **[CRITICAL — proto tags] исправлен renumber-конфликт.** Live `Role` занимает tag 1..10 (`account_id=2, created_at=7, cluster_id=8, organization_id=9, project_id=10`). Синтез ошибочно ставил `rules=10` (collision) и переставлял живые tag'и. **Фикс:** §2 теперь **бит-в-бит совпадает с live-tag'ами**; новое — append-only ≥11 (`rules=11`, …). `organization_id=9` — **tombstone (reserved), не удаляется** из proto (DB-колонка дропнута 0008, proto-tag живой). См. §2, §8.
5. **[CRITICAL — phantom migration] удалены ДВА несуществующих шага.** (a) «3→4-сегмент grammar-flip + re-emit seed» — **уже сделано миграцией `0005`**; live grammar 4-сегментная, `types.go:105` 4-сегментный. (b) «guarded org-drop колонки/индекса» — **уже сделано `0008`/KAC-223**; колонки нет. **Фикс:** оба шага вычеркнуты из §7; остаточный grammar-риск переформулирован как «squash-baseline `0001:119` 3-сегментный — отдельный pre-existing latent-bug, чинится своим forward-файлом ТОЛЬКО если squash не применён в прод» (§7, §8).
6. **[HIGH — cardinality cap] конфликт `4096` vs live `256`.** `iam_permissions_valid` + `types.go` + proto `(size)="1-256"` энфорсят ≤256. **Фикс:** либо bounds опускаются так, что worst-case compiled ≤256, либо отдельная lockstep cap-raise-миграция (DB CHECK + domain + proto annotation в одном tx, с RED-тестом). Выбрано: **cap-raise до 1024 lockstep-миграцией** (§6, §7); bounds dim'ов снижены чтобы worst-case ≤1024.
7. **[HIGH — reconciler rekey ≠ «bit-identical»] честно переописан как schema-migration.** Live `access_binding_selector` PK=`(binding_id)` (один арм/биндинг); `access_binding_target_members` PK=`(binding_id,object_type,object_id)` — не атрибутируют member к правилу. Per-rule селекция требует **PK-change + новые колонки + backfill**. **Фикс:** §5/§7 специфицируют новую `role_rule_selectors (role_id, rule_fp)` + members-ключ `(binding_id, role_id, rule_fp, object_type, object_id)`. Снято «reused дословно».
8. **[HIGH — matchLabels over-grant в emit] `m.r.*.v` для matchLabels неотличим от all_in_scope в `EmitForBinding`** → эмитил бы broad anchor-tuple (= всё-в-scope). **Фикс:** matchLabels-правила **НЕ компилируются в `permissions[]`**; они живут только как structured `rules`, потребляемые reconciler'ом; emit-вход получает per-grant arm-tag (`ARM_ANCHOR|ARM_LABELS|ARM_NAMES`). См. §5, GWT-6.
9. **[HIGH — feed-gate registry] `non-iam ⇒ mirror-fed` не верифицирует producer'а.** matchLabels на `vpc.addressPool`/`lb.listeners` прошёл бы gate, но producer'а нет → вечный PENDING. **Фикс:** gate сверяется с **закрытым code-registry CONFIRMED-fed типов** (= union того, что vpc/compute/nlb реально эмитят в `resource_mirror`), с self-test producer-coverage, не classifier-agreement. См. §6, GWT-7.
10. **[HIGH — dual-authority window] — SUPERSEDED O-9 (см. §7 врезку).** ~~backfill `rules` из `permissions` lossy для γ-биндингов; фикс — bit-identical-инвариант сужен до all_in_scope; legacy by_name/by_selector до re-author; inert-guard + no-double-emit тест.~~ Под clean-cut F legacy γ-путь удаляется целиком (продданных нет): dual-authority/backfill/inert-guard/no-double-emit сняты, единый источник истины `role.rules[]`. См. §7 врезку O-9, acceptance F-51.
11. **[MEDIUM — condition bypass] materialized-tuples грантят в FGA безусловно.** **Фикс:** condition эмитится как **FGA conditional-tuple** (`Condition`-ref + CEL-context) на time/IP/MFA-overlay — FGA сам энфорсит; ИЛИ доказывается, что КАЖДЫЙ Check-call-site (vpc/compute/geo/nlb) проходит condition-overlay до honor'а allow. Выбрано: **FGA conditional-tuple** (§4, §5, GWT-9).
12. **[MEDIUM — verb-tier lossy] раскрыт parity-gap:** authored verbs `get≠list` (оба viewer) различимы, но `create=update=delete=editor` НЕ энфорсятся раздельно (3-tier collapse). **Решение:** **раскрыто явно** — verb-гранулярность ниже tier-границ advisory/audit-only в v1; true per-verb FGA-relations — follow-up KAC (§8, Q#6). Не выдаём за faithful per-verb enforcement.
13. **[MEDIUM] прочее:** убран `Rule.label_feed_source` из authored-message (диагностического поля нет вовсе — `arm` выводится клиентом из формы правила, feed-проблемы — ошибка Create, §2); ~~RPC-rename `ListByResource→ListByScope` и retire target-мутаторов помечены breaking, только Phase 6 (live wire-name сохраняется до major)~~ **SUPERSEDED O-9: rename + retire target-мутаторов выполняются в под-фазе F (clean-cut), `buf breaking` намеренный в F — acceptance F-50/F-54**; `scope_tier/scope_id`-колонки **НЕ добавляются** (anchor = существующий `(scope, resource_type, resource_id)`, который `scope_ref` уже проецирует, §7); резерв полей `aggregationRule`/`matchExpressions` оставлен в комментариях (§9).
14. **[MEDIUM — backfill ordering] resourceNames-пины при неполном mirror → масса PENDING. — SUPERSEDED O-9.** ~~Фикс: mirror-sync gate перед flip'ом флага + bounded PENDING-TTL.~~ Flag-flip/mirror-sync gate сняты под clean-cut F (один путь, без переключателя); bounded PENDING-TTL для resourceNames сохраняется (acceptance C-24). См. §7 врезку O-9.

Сильные стороны синтеза, **подтверждённые** верификацией и сохранённые без изменений: containment (`IsContainedIn`) корректно применяется к обоим фидам с REJECTED+audit; **allow-only (no deny)** — верное монотонное решение; **отказ от FGA conditional-tuples для object-state labels** (materialization вместо `with`-CEL) технически корректен; **deprecate-and-add с сохранением tag'ов** — верный non-breaking путь (после фикса #4).

---

## 1. Модель в одном абзаце

**Role** — переиспользуемая **allow-only** политика, несущая `rules[]`; каждое правило (`Rule`) — однородный грант `{modules[], resources[], verbs[]}` над декартовым `modules×resources`, опц. суженный до инстансов через **`resourceNames[]` XOR `matchLabels{}`** (селекция **на уровне правила** — фикс старого «один matchLabels поверх разнотипных»). **AccessBinding** — тонкий: `{subjects[], roleId, scopeRef{tier,id}, condition}` — **без target/selector**. Каждое правило эмитится по **своему арму** (`ARM_ANCHOR`/`ARM_LABELS`/`ARM_NAMES`), и **tier материализуется ПОТИПНО**: all_in_scope-правило даёт `scope_grant`-tuple, привязанный к `(scopeAnchor, objectType, tier)` — **никогда** collapsed whole-role tier на голый anchor (закрытие escalation-engine). matchLabels/resourceNames — per-object type-correct tuples через reconciler/`resource_mirror`. Tier берётся из verbs **конкретного правила** (не из всей роли), объект — из membership; лейбл **никогда** не повышает tier и **никогда** не выходит за `scopeRef` (re-check `IsContainedIn` на каждом reconcile). `permissions[]` остаётся **internal** compiled-проекцией **только для anchor/names-армов** (matchLabels туда не компилируется; используется для FGA-эмиссии/Check-reuse, **не** в публичном Get/List-ответе для rules-ролей — публичный API роли = `rules[]`); revoke удаляет **сохранённый** tuple-set, не re-derive.

---

## 2. Proto — финальные messages

> **Tag-дисциплина (фикс #4).** Live `Role` занимает 1..10, live `AccessBinding` — до 18. Существующие tag'и **не двигаются**; новое — append-only. `organization_id=9` — **reserved tombstone** (DB-колонка дропнута 0008, proto-tag НЕ переиспользуется). `buf breaking` обязан быть зелёным (gate `proto-api-reviewer`).

### `role.proto` (`kacho.cloud.iam.v1`) — точное соответствие live-tag'ам + append

```protobuf
// Role = переиспользуемая allow-only политика. Flat-resource + Operation на мутациях.
// rules[] (tag 11) — authored-форма И публичный API (источник истины; UI/клиенты
// рендерят роль из rules[]). permissions[] (tag 5, live) — INTERNAL compiled-форма
// для FGA-эмиссии (anchor/resourceNames-армы, 4-сегмент module.resource.resourceName.verb);
// matchLabels-правила в permissions[] НЕ компилируются. permissions[] — live
// deprecated-поле (нельзя удалить, buf-breaking); в Get/List-ответах для rules-ролей
// НЕ заполняется (пустое); ИГНОРИРУЕТСЯ на входе Create/Update.
message Role {
  string id = 1;                              // live; prefix "rol"
  string account_id = 2;                      // live; custom account-scoped
  string name = 3;                            // live; ^[a-z][a-z0-9_]{0,40}$
  string description = 4;                     // live
  repeated string permissions = 5 [deprecated=true]; // live; INTERNAL compiled (anchor+names); НЕ в Get/List-ответе для rules-ролей
  bool is_system = 6;                          // live; immutable; seed-only
  google.protobuf.Timestamp created_at = 7;   // live
  string cluster_id = 8;                       // live; system-роли: cluster_kacho_root
  string organization_id = 9 [deprecated=true]; // TOMBSTONE: DB-колонка дропнута 0008; tag НЕ переиспользовать
  string project_id = 10;                      // live; custom project-scoped

  // --- APPEND-ONLY (новые tag'и ≥11) ---
  repeated Rule rules = 11;                     // authored-политика; 1..64 правил
  string resource_version = 12;                // OCC (xmin-backed) для Update под конкуренцией
  string created_by_user_id = 13;              // governance/audit
  google.protobuf.Timestamp updated_at = 14;
}

// Rule = один однородный грант: {verbs} над (modules × resources),
// опц. суженный resourceNames (pin-by-id) XOR matchLabels (наше расширение).
// arm (ARM_ANCHOR/ARM_LABELS/ARM_NAMES) выводится из формы правила клиентом;
// feed-доступность типа — жёсткий feed-gate на Create (matchLabels на не-fed
// тип → INVALID_ARGUMENT), отдельного диагностического поля нет.
message Rule {
  repeated string modules        = 1;   // 1..16; lowercase; "*" SYSTEM-ONLY
  repeated string resources      = 2;   // 1..16; lowercase; "*" SYSTEM-ONLY
  repeated string verbs          = 3;   // 1..16; lowercase; "*" SYSTEM-ONLY (фикс #2)

  // Селекция инстансов — взаимоисключающие; отсутствие обоих = ВСЕ инстансы
  // (modules×resources) в пределах scopeRef биндинга (ARM_ANCHOR).
  repeated string resource_names = 4;   // pin-by-id (K8s-native); "*" запрещён как элемент
  map<string,string> match_labels = 5;  // наше расширение; AND-equality; непусто если задано
}

message CreateRoleMetadata { string role_id = 1; }
message UpdateRoleMetadata { string role_id = 1; }
message DeleteRoleMetadata { string role_id = 1; }
```

> **`Role.Get` возвращает `Role`** напрямую (не response-обёртку) с `rules[]` как публичной API-поверхностью. `permissions[]` НЕ заполняется для rules-ролей (internal compiled, пустое в ответе). Feed-проблемы (matchLabels на не-fed тип) — ошибка `Role.Create` (`INVALID_ARGUMENT`), отдельного диагностического поля нет (у любой существующей роли все правила гарантированно прошли feed-gate).

### `role_service.proto`

```protobuf
service RoleService {
  rpc Get    (GetRoleRequest)    returns (Role);                  // sync; Role с rules[] (live)
  rpc List   (ListRolesRequest)  returns (ListRolesResponse);     // sync; scope-filtered
  rpc Create (CreateRoleRequest) returns (operation.Operation);   // iam.roles.create, editor @ account
  rpc Update (UpdateRoleRequest) returns (operation.Operation);   // iam.roles.update, admin @ iam_role; фан-аут reconcile (§6)
  rpc Delete (DeleteRoleRequest) returns (operation.Operation);   // iam.roles.delete, admin @ iam_role; FK RESTRICT при active-биндингах
  rpc ListOperations (ListRoleOperationsRequest) returns (ListRoleOperationsResponse);
}

message CreateRoleRequest {
  string account_id = 1;             // XOR project_id; cluster_id запрещён (system seed-only)
  string project_id = 2;
  string name = 3;                   // ^[a-z][a-z0-9_]{0,40}$
  string description = 4;
  repeated Rule rules = 5;           // 1..64. permissions[] на входе НЕ принимается.
}

message UpdateRoleRequest {
  string role_id = 1;
  Role role = 2;
  google.protobuf.FieldMask update_mask = 3;  // allow: name, description, rules
  // immutable: is_system, account_id, project_id, cluster_id, permissions(derived), organization_id
  // OCC: role.resource_version обязателен при mask содержит 'rules' (фикс #3)
}
```

### `access_binding.proto` (`kacho.cloud.iam.v1`) — live-tag'и сохранены, append-only

```protobuf
// AccessBinding = { subjects[], roleId, scopeRef, condition }. БЕЗ target/selector.
// Live proto уже несёт scope_ref=17, target_ref=18 (epic-100 δ) — НЕ пере-добавляем.
// subjects=19 — следующий свободный tag (verified против live).
message AccessBinding {
  string id = 1;                              // live; prefix "acb"
  string subject_type = 2  [deprecated=true]; // live; ← subjects[0] (read-projection)
  string subject_id   = 3  [deprecated=true]; // live
  string role_id = 4;                         // live; FK→roles RESTRICT
  string resource_type = 5 [deprecated=true]; // live; ← scope_ref projection
  string resource_id   = 6 [deprecated=true]; // live
  google.protobuf.Timestamp created_at = 7;   // live
  Status status = 8;                          // live; PENDING|ACTIVE|REVOKED
  string condition_id = 9;                    // live
  google.protobuf.Timestamp expires_at = 10;  // live; TTL
  string granted_by_user_id = 11;             // live
  google.protobuf.Timestamp revoked_at = 12;  // live
  string revoked_by_user_id = 13;             // live
  BuiltinCondition builtin_condition = 14;    // live
  Scope  scope = 15 [deprecated=true];        // live; ← scope_ref.tier
  AccessTarget    target     = 16 [deprecated=true]; // live; селекция ушла в role.rules
  ScopeRef        scope_ref  = 17;            // live (epic-100 δ) — каноническая ось scope
  AccessTargetRef target_ref = 18 [deprecated=true]; // live; селекция ушла в role.rules

  // --- APPEND-ONLY ---
  repeated Subject subjects = 19;             // 1..32; каждый → НЕЗАВИСИМЫЙ tuple-set + lineage
}

message Subject { SubjectType type = 1; string id = 2; }    // usr…|sva…|grp…
message ScopeRef { Scope tier = 1; string id = 2; }          // live

enum Status      { STATUS_UNSPECIFIED = 0; PENDING = 1; ACTIVE = 2; REVOKED = 3; }
enum Scope       { SCOPE_UNSPECIFIED = 0; CLUSTER = 1; ACCOUNT = 2; PROJECT = 3; }
enum SubjectType { SUBJECT_TYPE_UNSPECIFIED = 0; USER = 1; SERVICE_ACCOUNT = 2; GROUP = 3; }
```

### `access_binding_service.proto`

```protobuf
service AccessBindingService {
  rpc Get    (GetAccessBindingRequest)    returns (AccessBinding);              // sync, viewer @ iam_access_binding
  rpc Create (CreateAccessBindingRequest) returns (operation.Operation);       // requireGrantAuthority (§4)
  rpc Delete (DeleteAccessBindingRequest) returns (operation.Operation);       // editor; revoke по сохранённому tuple-set (фикс #3)
  rpc ListBySubject         (ListBySubjectRequest)         returns (ListBySubjectResponse);
  rpc ListByResource        (ListByResourceRequest)        returns (ListByResourceResponse);  // live wire-name СОХРАНЁН (фикс #13)
  rpc ListByRole            (ListByRoleRequest)            returns (ListByRoleResponse);       // audit "кто несёт роль R"
  rpc ListSubjectPrivileges (ListSubjectPrivilegesRequest) returns (ListSubjectPrivilegesResponse);
  rpc ListAssignableRoles   (ListAssignableRolesRequest)   returns (ListAssignableRolesResponse);  // lean AssignableRole (без rules/permissions)
  rpc ExpandAccess          (ExpandAccessRequest)          returns (ExpandAccessResponse);    // effective-principal audit (group-usersets, §9 Q#4)
  rpc ListByAccount         (ListByAccountRequest)         returns (ListByAccountResponse);
  rpc ListOperations        (ListAccessBindingOperationsRequest) returns (ListAccessBindingOperationsResponse);
}
// target-мутаторы (AddTargetResources/RemoveTargetResources/ReplaceTargetSelector/
// ListGrantableResources) и rename ListByResource→ListByScope — BREAKING, выполняются
// в ПОД-ФАЗЕ F (clean-cut, owner-decision O-9 2026-06-21): RPC и поля target/selector
// УДАЛЯЮТСЯ совсем (tags→reserved tombstone), `buf breaking` намеренный в F. Прежний план
// «ТОЛЬКО Phase 6; до Phase 6 зарегистрированы, на write → FAILED_PRECONDITION в окне» —
// SUPERSEDED O-9 (продданных нет, deprecation-окно/Phase-6 отменены; см. §7 врезку O-9).

message CreateAccessBindingRequest {
  repeated Subject subjects = 1;     // 1..32
  string role_id = 2;
  ScopeRef scope_ref = 3;
  string condition_id = 4;           // опц.
  BuiltinCondition builtin_condition = 5;
  google.protobuf.Timestamp expires_at = 6;
}
```

---

## 3. REST JSON (camelCase)

### Role — Create (`POST /iam/v1/roles` → Operation), смешанные правила

> Заметьте: reference-JSON пользователя `compute.instance verbs:["*"]` теперь **отвергается** (verb-`*` в custom-роли запрещён, фикс #2) — намерение «все CRUD» выражается явным `["get","list","create","update","delete"]`. Пример ниже скорректирован.

```json
{
  "accountId": "acc7h2k9...",
  "name": "network-ops",
  "description": "VPC + compute: read images, manage prod subnets and net-team instances",
  "rules": [
    { "modules": ["compute"], "resources": ["image"],    "verbs": ["get"] },
    { "modules": ["vpc"],     "resources": ["subnet"],   "verbs": ["create"], "matchLabels": { "env": "prod" } },
    { "modules": ["compute"], "resources": ["instance"], "verbs": ["get","list","create","update","delete"], "matchLabels": { "team": "net" } },
    { "modules": ["vpc"],     "resources": ["network"],  "verbs": ["list"] },
    { "modules": ["vpc"],     "resources": ["address"],  "verbs": ["get","update"], "resourceNames": ["addr5k...", "addr9m..."] }
  ]
}
```

### Role — Get (`GET /iam/v1/roles/{id}` → `Role`)

```json
{
  "id": "rol3x...",
  "accountId": "acc7h2k9...",
  "name": "network-ops",
  "isSystem": false,
  "createdByUserId": "usr2a...",
  "createdAt": "2026-06-20T10:00:00Z",
  "rules": [
    { "modules": ["compute"], "resources": ["image"],    "verbs": ["get"] },
    { "modules": ["vpc"],     "resources": ["subnet"],   "verbs": ["create"], "matchLabels": { "env": "prod" } },
    { "modules": ["compute"], "resources": ["instance"], "verbs": ["get","list","create","update","delete"], "matchLabels": { "team": "net" } },
    { "modules": ["vpc"],     "resources": ["network"],  "verbs": ["list"] },
    { "modules": ["vpc"],     "resources": ["address"],  "verbs": ["get","update"], "resourceNames": ["addr5k...", "addr9m..."] }
  ]
}
```

> `Role.Get` возвращает `Role` напрямую с `rules[]` как публичным API. `permissions[]` (internal compiled, anchor/names) **НЕ заполняется** в ответе для rules-ролей — это внутренняя проекция для FGA-эмиссии, не часть API-контракта. Диагностического поля (`ruleDiagnostics`) нет: `arm` выводится клиентом из формы правила, а feed-проблемы — ошибка `Create`. UI рендерит роль **из `rules[]`**.

### AccessBinding — Create (`POST /iam/v1/accessBindings` → Operation)

```json
{
  "subjects": [
    { "type": "USER",  "id": "usr2a..." },
    { "type": "GROUP", "id": "grp8c..." }
  ],
  "roleId": "rol3x...",
  "scopeRef": { "tier": "ACCOUNT", "id": "acc7h2k9..." },
  "builtinCondition": "NON_EXPIRED",
  "expiresAt": "2026-09-20T10:00:00Z"
}
```

---

## 4. Семантика полей

**`modules[]` / `resources[]` / `verbs[]`** — каждое непусто, lowercase `[a-z][a-zA-Z0-9_-]*` ИЛИ literal `*`. Правило грантит `{verbs}` над **декартовым** `modules×resources`. `*` — **исключительно как единственный элемент** своего списка (`["*"]`, никогда `["*","subnet"]` → INVALID_ARGUMENT).

**Wildcard `*` (пересмотрено после верификации, фикс #2):**
- `modules:["*"]` / `resources:["*"]` / `verbs:["*"]` — **все три запрещены в custom-ролях, только system** (seed). Обоснование: `verbClass('*')=classAdmin` → admin-tier → наследует ВСЕ derived-relations (включая step-up-gated ssh/console/manage). verb-`*` НЕ bounded — это максимальный tier. Admin-намерение в custom-роли выражается **явным перечислением verbs**. System-роли (`is_system`, seed-only) сохраняют `*` для bundles admin/edit/view.
- Любой `*` (в любой позиции) **+ matchLabels или + resourceNames** → INVALID_ARGUMENT.

**`resourceNames[]`** (pin-by-id, K8s-native) — opaque-id (1..64), literal `*` запрещён как элемент. Cross-DB soft-ref (без FK). На Create: in-mirror-но-out-of-scope id → FAILED_PRECONDITION; not-in-mirror id → принимается, материализуется `PENDING_VERIFICATION` (bounded TTL, §6). На материализации **обязателен** re-check `IsContainedIn(scopeRef)` **И** проверка, что mirrored `object_type` совпадает с типом правила (фикс edge-case: id позже создан другого типа) → mismatch → REJECTED+audit.

**`matchLabels{}`** (наше расширение; в K8s RBAC отсутствует) — AND-equality поверх labels mirror/own-table; если задан — **непуст** (`{}` при наличии ключа → INVALID_ARGUMENT; «все» = отсутствие обоих селекторов). Никогда не PENDING. **Trust-boundary (фикс HIGH #4):** для mirror-fed типов лейблы пишет owner-сервис; matchLabels-правило с **admin/editor**-tier требует, чтобы Create-биндинга прошёл `requireGrantAuthority` на `scopeRef` (низко-привилегированный актор не может авторить self-serving label-selector). Containment re-verify на каждом reconcile отсекает cross-scope-инъекцию через label-tampering. См. GWT-11.

**Пустое = всё (ARM_ANCHOR).** Отсутствие обоих селекторов = ВСЕ инстансы `modules×resources` под `scopeRef`. Пустой `rules[]` → INVALID_ARGUMENT. Пустой любой из `modules/resources/verbs` → INVALID_ARGUMENT.

**Mutual-exclusion.** `resourceNames` XOR `matchLabels` на правило (оба → INVALID_ARGUMENT).

**Precedence.** Правила **чисто аддитивны** (объединение грантов). **Нет deny, нет порядка, нет переопределения** (§8). Эффективное множество = `∪` по правилам `(verbs × instances × tier-per-type)`. Двойное покрытие (anchor-tier-правило + matchLabels-правило **одного tier**) → per-object tuple избыточен-но-безвреден → **validation WARNING**. **Важная коррекция (edge-case верификации):** если anchor-правило **viewer**, а matchLabels-правило **admin** на тот же тип — anchor НЕ subsumes label (tier'ы различны): субъект получает viewer-везде + admin-на-labeled-подмножестве; оба арма эмитятся, WARNING **не** выдаётся.

**`condition`** (`condition_id` XOR `builtin_condition`) — **эмитится как FGA conditional-tuple** (фикс #11): каждый материализованный tuple несёт `Condition`-ref + CEL-context (time/IP/MFA), FGA сам энфорсит на Check; ошибка/несовпадение → fail-**closed** (deny) + audit. `expires_at` — independent TTL, sweep CAS ACTIVE→REVOKED + eager-revoke. См. GWT-9.

**`scopeRef{tier,id}`** — якорь конфайнмента. `tier↔id`: CLUSTER⇒`cluster_kacho_root`, ACCOUNT⇒`acc…`, PROJECT⇒`prj…`. Каждый материализованный объект обязан `IsContainedIn(scopeRef)`, иначе REJECTED (без tuple). System(ClusterRole)-роль bind-абельна на любом tier; custom(namespaced)-роль на CLUSTER-tier → FAILED_PRECONDITION; **доп. cross-check**: `scopeRef` обязан быть в ancestry владельца роли (`role.account_id`/`role.project_id`) иначе FAILED_PRECONDITION (фикс edge-case).

---

## 5. FGA-компиляция (REUSE где возможно; type-scoped anchor — НОВОЕ)

> **Коррекция тезиса (фикс #1):** «zero new FGA primitives» больше неверно. all_in_scope-арм требует **type-scoped anchor-relation** в FGA-модели, иначе whole-role tier коллапсирует на anchor и каскадит на все типы (escalation-engine). Остальная машинерия (reconciler/mirror/containment/outbox) — реюзается.

**Три арма правила (per-rule, не per-binding):**

| Арм | Условие | Что эмитится | type-correct? |
|---|---|---|---|
| **ARM_NAMES** | `resourceNames` задан | per-id `fga(m,r):id#tier(rule.verbs)@subject` (1/объект) | да (per-object) |
| **ARM_LABELS** | `matchLabels` задан | reconciler → per-matched-and-contained-object `fga(m,r):obj#tier@subject` | да (per-object) |
| **ARM_ANCHOR** | ни одного | **`scope_grant:<anchor>/<objectType>#tier@subject`** (type-scoped!) | да (per-type) |

**Шаг 1 — `rules → permissions[]` (compiled, ТОЛЬКО ARM_ANCHOR + ARM_NAMES).** Чистая функция в `domain/` (новый код). Для каждого правила декартово `modules×resources×verbs`, затем per `(m,r,v)`:
- ARM_NAMES → `m.r.<id>.v` на каждый id.
- ARM_ANCHOR → `m.r.*.v`.
- **ARM_LABELS → НЕ компилируется в `permissions[]`** (фикс #8); хранится как structured rule + `role_rule_selectors`-строка для reconciler.

Dedupe + стабильная сортировка. Результат — `roles.permissions` jsonb (output-only, anchor+names). Tier-деривация: `SplitGrants` применяется **per-rule** (не per-role) — `Grant.Tier` из `verbClass` правила; **whole-role collapse запрещён**.

**Шаг 2 — emit с arm-tag (изменённый `EmitForBinding`-вход, фикс #1/#8).** Вход emit'а получает per-grant `arm` ∈ {ANCHOR, NAMES, LABELS}. Матрица:

| arm | scope | эмитится |
|---|---|---|
| ANCHOR `m.r.*.v` | any tier | `scope_grant:<anchor>/<m.r>#tier(v)@subject` (1 tuple/(type,tier)/anchor) — **НЕ raw-anchor relation** |
| ANCHOR `*.*.*.*` (system) | CLUSTER | `cluster:root#system_admin@subject` |
| NAMES `m.r.<id>.v` | any | `fga(m,r):id#tier(v)@subject` (1/объект) |
| LABELS | any | suppress anchor; reconciler эмитит per-object (Шаг 3) |

**Новый FGA-примитив `scope_grant`** (изменение `fga_model.fga`): тип `scope_grant` с relations `viewer/editor/admin`, привязан к `(anchor_object, object_type)`; целевые типы (`compute_instance`/`vpc_subnet`/…) получают `viewer = viewer from scope_grant:<self_type>@<anchor>` — каскад tier'а **только на свой тип**, не на все. Это закрывает escalation-engine: admin all_in_scope-правило над `compute.instance` даёт admin **только** над compute.instance в scope, не над vpc/iam. Деплой FGA-модели через bootstrap (re-write model id), миграция tuple'ов снапшотом.

**Шаг 3 — ARM_LABELS → reconciler (REUSE epic-103 γ, теперь driven by `role.rules`, rekeyed).** `reconcileBinding` грузит binding (`SELECT…FOR UPDATE`) + role (порядок: lock binding → read role-snapshot под тем же tx, чтобы concurrent Role.Update не давал torn read, фикс edge-case); на каждый `subject × ARM_LABELS-rule`: `partitionByFeed` → `MatchSelector`/`MatchIAMDirect` → `IsContainedIn(scopeRef)` per объект → ACTIVE (emit per-object tier-tuple **с Condition-ref если binding.condition**) / REJECTED (без tuple + audit). `applyDiff` → `fga_outbox` → drainer → OpenFGA (идемпотентно). Membership ключуется **`rule_fp` (content-hash правила), не rule_index** (фикс #3) — reorder/remove правила не десинхронит.

**Почему materialization, НЕ conditional-tuples для labels** (подтверждено верификацией как корректное): FGA `with`-CEL оценивает request-context, а labels — object-state; conditional-tuple для label вынудил бы per-candidate fan-out + сломал бы `ListObjects`/O(1)-Check. **Но для time/IP/MFA condition — conditional-tuple корректен и применяется** (фикс #11): это request-context, FGA энфорсит сам.

**Containment** — `domain.MirrorObject.IsContainedIn(scope)` для обоих фидов. `project:P ⊑ account:A ⊑ cluster:*`. Upward-type под downward-scope (label-selected ACCOUNT под PROJECT-scope) → структурно пусто → не silent: REJECTED с диагностикой (фикс edge-case).

**Revoke (фикс #3) — НЕ re-derive.** При grant сохраняется эмитированный tuple-set в `access_binding_emitted_tuples (binding_id, tuple_hash, tuple_json)`; `Delete`/expiry удаляет **ровно эти** tuple'ы, независимо от текущего состояния роли. Decouple revoke от current-role-state → нет orphan'ов после `Role.Update(rules)`.

**Что реюзается дословно:** `MatchSelector`/`MatchIAMDirect`, `IsContainedIn`, `membershipTuples`, `fga_outbox`+drainer, `resource_reconcile_outbox`+sweep dual-trigger, registry `selectableTypes`. **Новое:** Шаг 1 (per-rule develop, ARM_LABELS не в permissions), `scope_grant` FGA-примитив (Шаг 2), arm-tag во входе emit, `rule_fp`-rekey membership, `access_binding_emitted_tuples` для revoke, фан-аут reconcile на `Role.Update` (§6).

---

## 6. Инварианты / валидация

**Грамматика (4-сегмент, single source).** Live grammar **уже 4-сегментная** (`0005` + `types.go:105`) — grammar-flip НЕ нужен (фикс #5). Compiled-perm матчит `permissionElementRe` И DB `iam_permissions_valid`. matchLabels-правила в `permissions[]` отсутствуют → 4-сегмент-валидатор их не видит.

**Shape-валидация (`domain.Rule.Validate()` + DB CHECK `iam_rules_valid(jsonb)` — parity):**
- `modules`/`resources`/`verbs` непусты; `*` — единственный элемент И **only-if is_system** (включая verbs, фикс #2).
- `resourceNames` XOR `matchLabels` (оба → INVALID).
- `matchLabels` непуст если задан; ключи/значения — `kacho_labels_valid()`.
- `resourceNames`: каждый 1..64, `≠'' AND ≠'*'`, UNIQUE на правило.
- custom-wildcard-guard: `is_system OR (ни одно правило не имеет '*' в modules/resources/verbs)`.
- **feed-availability gate (фикс #9):** ARM_LABELS-правило, чей `(module,resource)` **не** в **закрытом code-registry CONFIRMED-fed типов** → INVALID_ARGUMENT "type <m>.<r> is not selectable (no resource feed)" на Role.Create/Update (sync, до Operation). Registry = **union того, что vpc/compute/nlb реально эмитят в `resource_mirror`** (code, не config), с self-test `TestSelectableTypes_ProducerCoverage` (не classifier-agreement). admin-only Internal-типы (`vpc.addressPool`) и non-producing (`lb.listeners`) → **reject**, не вечный PENDING. ARM_NAMES gate'у не подлежит.

**Cardinality-bounds (фикс #6 — worst-case compiled ≤ live-cap):** `rules[]` 1..64; `modules/resources/verbs` **1..16 каждый**; `resourceNames` ≤256/правило; `matchLabels` ≤16 ключей; **compiled `permissions[]` ≤1024** (cap-raise с live-256 lockstep-миграцией: DB CHECK + domain validator + proto `(size)` в одном forward-tx + RED-тест). `subjects[]` 1..32. Превышение compiled-cap → INVALID_ARGUMENT (не silent truncation, не INTERNAL). **Ordering-гарантия:** CHECK-relax (256→1024) применяется в **той же** tx, что и trigger-install — роль между 256 и 1024 не reject'ится mid-migration.

**Role-scope XOR (DB — уже без org, `0008`):** `(is_system AND cluster_id NOT NULL AND account_id IS NULL AND project_id IS NULL) OR (NOT is_system AND cluster_id IS NULL AND exactly-one-of(account_id, project_id))`. **org-drop НЕ повторяется** (сделано `0008`, фикс #5).

**Role-name uniqueness per scope (partial UNIQUE):** `roles_acc_unique`/`roles_prj_unique`/`roles_system_unique` (org-индекс отсутствует с `0008`).

**permissions-drift guard.** Пересчёт `permissions := compile(rules)` (anchor+names арм) выполняется **в Go composition-root в одной tx** с записью `rules` (НЕ в PL/pgSQL-триггере — фикс #13: второй cartesian-имплементации в PL/pgSQL быть не должно, drift-hazard). DB CHECK `iam_rules_valid` валидирует shape; **parity-fuzz-тест** `compile(rules)`-Go против хранимого `permissions` (round-trip для anchor/names). Client-sent `permissions` на input → INVALID_ARGUMENT.

**OCC Role.Update + фан-аут reconcile (фикс #3).** `UPDATE … WHERE xmin::text=$resource_version`; 0 rows → FailedPrecondition. При изменении `rules`: в той же логической операции **перечислить все ACTIVE-биндинги, несущие role_id, и reconcile каждый** (emit additions, eager-revoke removals по `access_binding_emitted_tuples`). Фан-аут **bounded**: `count(active bindings per role)` лимитируется (DB-guard, напр. ≤512; превышение → FAILED_PRECONDITION "role carried by too many bindings to update atomically; split role"). Реализация — через `resource_reconcile_outbox`-события (async drain), Operation завершается когда все per-binding reconcile задренены.

**AccessBinding strict-create UNIQUE (на существующем anchor-triple).** partial UNIQUE на `(subject_type, subject_id, role_id, resource_type, resource_id) WHERE revoked_at IS NULL` (уже поддерживается `0003`; **новых scope_tier/scope_id колонок НЕ добавляем** — фикс #13, anchor = `scope_ref`-проекция существующего triple). `subjects[]` нормализуются в `access_binding_subjects (binding_id, subject_type, subject_id)` UNIQUE.

**Reconciler fail-closed (наследуется):** ACTIVE-membership с 0 tuple → INTERNAL → rollback. `LoadBinding SELECT…FOR UPDATE` сериализует проходы; membership UPSERT идемпотентен на PK `(binding_id, role_id, rule_fp, object_type, object_id)`.

**buf:** append-only (новые `Rule`, `Role.rules=11`, `AccessBinding.subjects=19`); `RoleService.Get` остаётся `returns (Role)`; ZERO renumber/delete; `organization_id=9` tombstone, `permissions=5` deprecated. `buf breaking` зелёный.

**Integration (testcontainers, concurrent, ban #12):** см. §10 GWT (каждый — RED-тест до кода).

---

## 7. Миграция (non-breaking, против РЕАЛЬНОГО applied-chain 0001..0023)

> **Коррекция (фикс #5/#7/#10/#13):** удалены phantom-шаги (grammar-flip, org-drop). Учтено, что `scope_ref`/`target_ref`/`match_labels` **уже в live proto** (epic-100 δ) и `access_binding_selector`/`target_members`/`resource_reconcile_outbox` — **свежеотгружены** (`0018..0023`, не legacy). Топо-порядок `proto → corelib → iam → gateway → ui → deploy → docs`. Applied-миграции не редактируются (ban #5).

> **⚠ ВРЕЗКА O-9 — owner-decision 2026-06-21 (продданных нет → clean-cut SUPERSEDES Phase-5-flag / Phase-6-cleanup / deprecation-окно).**
> Поскольку live-данных и внешних клиентов нет — бэкфилить/инертизировать нечего, deprecation-окна не нужно. **Источник истины миграции под-фазы F — acceptance §5 (O-9) + acceptance под-фаза F (F-50..F-54), а НЕ описание Phase 5/6 ниже.** Конкретно SUPERSEDED данной резолюцией:
> - **Phase 5 flag-flip** (`KACHO_IAM_ROLE_RULES_SELECTION`, default off → flip после verify) — **снят**: переключателя нет, один путь.
> - **mirror-sync gate** (гарантия `RegisterResource`-backfill перед flip) — **снят** (нет flip).
> - **INERT-guard / dual-authority / no-double-emit инвариант** (фикс #10; legacy `by_name`/`by_selector` authority до re-author) — **снят**: legacy γ-путь удаляется целиком, единый источник истины — `role.rules[]`.
> - **Backfill `permissions→rules`** (фикс #10) — **отменён**: бэкфилить нечего, round-trip parity-требование снято.
> - **Phase 6 как отдельный major** (DROP legacy + retire target-мутаторов + rename `ListByResource→ListByScope`) — **свёрнут в под-фазу F** одним проходом.
> - **`buf breaking` теперь в F** (а не «разрешён только в Phase 6»): удаление RPC/полей target/selector/permissions-write + rename — **намеренный** документированный breaking на pre-prod (acceptance F-54).
> - **`ListByResource→ListByScope`** — rename выполняется в F (не Phase 6).
> Подробности Phase 5/6 ниже сохранены **только как историческая справка**; нормативен clean-cut (acceptance §5/O-9 + F).

**Инвариант (сужен, фикс #10) — SUPERSEDED O-9 (см. врезку выше):** ~~compiled `permissions[]` и FGA-tuple-set бит-идентичны до/после **только для all_in_scope-биндингов**; для legacy `by_name`/`by_selector`-биндингов legacy-путь остаётся authority **до явного re-author**; role-driven селекция **инертна** для pre-flag биндингов с тестом на отсутствие double-emit.~~ Под clean-cut F dual-authority/инертность/no-double-emit-инвариант сняты: единый источник истины — `role.rules[]`, legacy γ-путь удаляется целиком.

**Phase 0 — proto (additive, buf-breaking clean).** Add `message Rule`, `Role.rules=11`, `Role.resource_version=12`, `Role.created_by_user_id=13`, `Role.updated_at=14`, `AccessBinding.subjects=19`, RPC `ListByRole`/`ExpandAccess`. `RoleService.Get` остаётся `returns (Role)` (live — НЕ вводим `GetRoleResponse`-обёртку). Mark `organization_id=9` deprecated/tombstone; mark `Role.permissions=5` deprecated (internal compiled). `scope_ref=17`/`target_ref=18`/`match_labels` **НЕ пере-добавлять** (live). proto-api-reviewer gate; tag-allocation-таблица cross-checked против live `.proto`.

**Phase 1 — DB (новые forward-файлы; org-drop и grammar-flip НЕ повторяются).**
- ADD `roles.rules jsonb NOT NULL DEFAULT '[]'`; `iam_rules_valid(rules)` CHECK; cardinality/wildcard/XOR/label/feed CHECK.
- **cap-raise lockstep:** в одной tx — `CREATE OR REPLACE iam_permissions_valid` (256→1024 array-bound) + соответствующий domain-validator + proto `(size)` (фикс #6). RED-тест: роль на 300 compiled-perm проходит post-migration, рейзит pre-migration.
- **Backfill `rules` из `permissions` (anchor/names only, фикс #10):** `m.r.rn.v` → правило; `rn=='*'` → ARM_ANCHOR (без селектора); concrete → ARM_NAMES. **matchLabels НЕ recoverable** из permissions — для γ-биндингов селектор остаётся binding-resident. Backfill детерминированен для anchor/names.
- ADD `access_binding_subjects (binding_id FK CASCADE, subject_type, subject_id) UNIQUE`; backfill 1 строка/биндинг.
- ADD `access_binding_emitted_tuples (binding_id FK CASCADE, tuple_hash, tuple_json) PK(binding_id,tuple_hash)` (фикс #3 — revoke по сохранённому).
- **Reconciler rekey (фикс #7 — это РЕАЛЬНАЯ schema-migration, не rekey):** ADD `role_rule_selectors (role_id FK CASCADE, rule_fp, object_types text[], match_labels jsonb) PK(role_id, rule_fp)`; backfill из legacy single-arm `access_binding_selector`. ALTER `access_binding_target_members`: ADD `role_id`, `rule_fp`; миграция PK → `(binding_id, role_id, rule_fp, object_type, object_id)`; backfill synthesized rule-coordinates. Concurrent-reconcile integration-тест на новый ключ.
- **scope_tier/scope_id колонки НЕ добавляются** (фикс #13). strict-create UNIQUE остаётся на `(subject_type,subject_id,role_id,resource_type,resource_id) WHERE revoked_at IS NULL` (`0003`).

**Phase 2 — kacho-iam код.**
- `domain`: `Rule`-тип + `Role.Rules` + `Rule.Validate()` + чистый Go-компайлер (compile/lift, idempotent, **per-rule tier**, anchor/names-only в permissions). `Role.Permissions` derived. Dual-read (lift на read когда `rules` пуст).
- `RoleService.Create/Update`: принимают `rules` (предпочт.) ИЛИ legacy `permissions[]` (lift→rules в окне; оба заданы → set-equality `compile(rules)==permissions` для anchor/names, иначе INVALID). feed-gate на ARM_LABELS. `Update(rules)` → фан-аут reconcile всех ACTIVE-биндингов (§6), bounded. System-роли read-only публично.
- `AccessBinding.Create`: `subjects[]+scope_ref` (предпочт.) ~~ИЛИ legacy single (mapped); под флагом `KACHO_IAM_ROLE_RULES_SELECTION` входящие `target`/`target_ref` → FAILED_PRECONDITION (write)~~ **SUPERSEDED O-9: флага нет; `target`/`target_ref`/`selector` УДАЛЕНЫ из proto — поля просто отсутствуют (grpc-gateway игнорирует, acceptance F-51); селекция целиком role-driven**. requireGrantAuthority на admin/editor matchLabels (фикс HIGH #4).
- `emit`: arm-tagged вход; `scope_grant` для ANCHOR; per-object для NAMES/LABELS; Condition-ref для time/IP/MFA (фикс #11). revoke по `access_binding_emitted_tuples`.
- `reconciler`: `desiredMembers` из `role.rules` (per-rule `rule_fp`), lock-order binding→role-snapshot. δ read-projection: Get/List заполняют ОБА (new + legacy).
- ~~**Inert-guard (фикс #10):** биндинги, созданные до flip-флага, **не** получают role-driven селекцию; тест на отсутствие double-emit.~~ **SUPERSEDED O-9:** flip-флага нет, legacy γ удаляется целиком → inert-guard/double-emit неактуальны (единый источник истины `role.rules[]`).

**Phase 3 — kacho-api-gateway.** Публичная поверхность неизменна, кроме новых `ListByRole`/`ExpandAccess` (public mux). ~~**`ListByResource` wire-name СОХРАНЁН** (rename → Phase 6, фикс #13); target-мутаторы остаются зарегистрированы (write → FAILED_PRECONDITION).~~ **SUPERSEDED O-9:** rename `ListByResource→ListByScope` и снятие target-мутатор-роутов выполняются в под-фазе F (acceptance F-50/DoD F). Проверить camelCase `rules`/`matchLabels`/`resourceNames`/`scopeRef`. `RoleService.Get` отдаёт `Role` напрямую (без обёртки, `permissions` пустое). `ListAssignableRoles`→`AssignableRole` остаётся lean. Internal* не трогаем.

**Phase 4 — kacho-ui.** Рендер из `rules[]` (arm выводится клиентом из формы правила); автор правил per-rule; ~~verb-`*` в UI **disabled** для custom (фикс #2)~~ **SUPERSEDED O-2/R-3: verb-`*` в UI РАЗРЕШЁН для custom** (acceptance F-22); прекращение отправки `binding.target/selector`.

**Phase 5 — kacho-deploy / docs / vault.** **SUPERSEDED O-9 (clean-cut — flag-flip/mirror-sync сняты; см. врезку §7).** ~~Mirror-sync gate (фикс #10): перед flip'ом флага — гарантия, что vpc/compute/nlb `RegisterResource`-backfill завершён; env `KACHO_IAM_ROLE_RULES_SELECTION` (default off → flip после verify).~~ Сохраняется: FGA-модель re-bootstrap (новый `scope_grant`-примитив, фикс #1) + tuple-снапшот pre/post; re-seed system-ролей через `rules[]` (детерминированные id); docs-site Role-глава; vault-trail; APPROVED Given-When-Then **до кода** (ban #1). Раскатка fe3455 **без flag-flip** (один путь). Нормативно — acceptance DoD под-фазы F (`kacho-deploy`-пункт).

**Phase 6 — cleanup — SUPERSEDED O-9 (свёрнут в под-фазу F).** ~~Отдельный major: DROP legacy binding-side `access_binding_targets`/`access_binding_selector`, retire target-мутатор-RPC, rename `ListByResource→ListByScope`, DROP legacy колонки/proto-поля; `buf breaking` разрешён только здесь.~~ Всё это выполняется **в под-фазе F одним проходом** (`buf breaking` намеренный в F, acceptance F-54); `organization_id=9` остаётся reserved tombstone. Отдельной Phase 6 нет.

~~**Backfill legacy γ-биндингов — INERT до re-author** (фикс #10): legacy `by_name`/`by_selector` энфорсятся через legacy-путь; role-driven селекция не применяется; reconciler не double-эмитит.~~ **SUPERSEDED O-9:** INERT/backfill/no-double-emit сняты — legacy γ-путь удаляется целиком в под-фазе F, единый источник истины `role.rules[]` (бэкфилить нечего — продданных нет).

**Rollback:** `rules` аддитивна; permissions[] в одиночку драйвит anchor/names FGA (pre-rules путь); `scope_grant`-примитив аддитивен к FGA-модели (старые anchor-relations можно держать параллельно в окне); колонки дропаются без потери данных.

---

## 8. Принятые решения

| Решение | Выбор | Почему (и какую находку закрывает) |
|---|---|---|
| **all_in_scope tier-emit** | **type-scoped `scope_grant`-primitive (НЕ whole-role collapse на raw anchor)** | **CRITICAL #1**: `PermissionsToRelations(role)` type-blind → admin-anywhere-в-роли → account-wide admin над всеми типами (escalation-engine, reference-JSON юзера триггерил бы). Требует изменения FGA-модели. |
| **verb-`*` в custom-роли** | **РАЗРЕШЁН** (override O-2, заказчик) = «все verbs этого типа», bounded под per-verb-моделью | Пересмотрено: F2-верификация в основном ОПРОВЕРГЛА эскалацию (`manage` нет; ssh/console без live-RPC; admin-shortcut bounded scope-enforcement'ом). Под **per-verb enforcement** verb-`*` разворачивается в полный per-verb набор типа — bounded, не «максимальный tier». module/resource-`*` остаются system-only. Step-up-hardening (ssh/console) — issue #179. |
| **revoke completeness** | **удалять СОХРАНЁННЫЙ tuple-set (`access_binding_emitted_tuples`), НЕ re-derive; `rule_fp`-rekey; Role.Update→фан-аут reconcile** | **CRITICAL #3**: mutable `rules[]` + re-derive-revoke → orphan-tuples (standing privilege). |
| **proto field-numbering** | **бит-в-бит live-tag'и; append-only ≥11; `organization_id=9` tombstone** | **CRITICAL #4**: синтез ставил `rules=10` (collision с `project_id=10`) и двигал живые tag'и → buf-breaking. |
| **org-drop / grammar-flip** | **УДАЛЕНЫ из плана (phantom)** | **CRITICAL #5**: оба сделаны (`0008`/`0005`). Остаточный squash-`0001:119` 3-сегмент — отдельный pre-existing latent-bug, чинится своим forward-файлом ТОЛЬКО если squash не в проде. |
| **compiled-cap** | **≤1024 lockstep cap-raise (DB+domain+proto в одной tx); dims ≤16** | **HIGH #6**: `4096` конфликтовал с live `256` → CHECK-reject mid-migration. |
| **reconciler rekey** | **реальная schema-migration: `role_rule_selectors(role_id,rule_fp)` + members-PK `(binding_id,role_id,rule_fp,obj)`** | **HIGH #7**: live PK=`(binding_id)` физически не держит multi-rule селекцию; «bit-identical reuse» неверно. |
| **matchLabels в permissions[]** | **НЕ компилируется; arm-tag (ANCHOR/NAMES/LABELS) во входе emit** | **HIGH #8**: `m.r.*.v` неотличим от all_in_scope в `EmitForBinding` → over-grant (всё-в-scope). |
| **feed-gate registry** | **закрытый code-registry CONFIRMED-fed (= что producer'ы реально эмитят) + producer-coverage self-test** | **HIGH #9**: `non-iam ⇒ mirror-fed` пропускал `vpc.addressPool`/`lb.listeners` → вечный PENDING. |
| **dual-authority window** | ~~bit-invariant сужен до all_in_scope; γ-биндинги inert до re-author; no-double-emit тест~~ → **SUPERSEDED O-9: dual-authority снят, legacy γ удаляется целиком в F (clean-cut)** | **HIGH #10**: backfill `rules` из `permissions` lossy для binding-side γ — **неактуально (продданных нет)**. |
| **condition enforcement** | **FGA conditional-tuple (Condition-ref + CEL) для time/IP/MFA** | **MEDIUM #11**: plain materialized-tuples грантили в FGA безусловно → condition bypass. |
| **verb-granularity** | **TRUE per-verb enforcement** (override O-2, заказчик «no-MVP/best-2026») — `delete` энфорсится отдельно от `create`; FGA-модель получает per-verb relations | Пересмотрено: 3-tier collapse (`create=update=delete=editor`) — least-privilege-violation + вводит в заблуждение (authored verbs ≠ enforced). 2026-паритет (K8s/GCP/AWS — per-verb/per-action). **КРУПНЕЙШИЙ scope-пункт**: расширение `fga_model.fga` (per-verb relations) + `permission-catalog` (RPC→verb-relation) + `SplitGrants`, затрагивает Check во ВСЕХ сервисах. Реализуется в под-фазе B. |
| **deny-правила** | **НЕТ, allow-only** | Все ревью подтвердили: deny субтрактивен/немонотонен, нет tuple-представления, ломает «кто может X». (Сохранено.) |
| **Где живёт селекция** | **Целиком в `role.rules`; binding thin** | Подтверждённое направление; per-rule co-location убивает heterogeneous-type mismatch для NAMES/LABELS армов (ARM_ANCHOR закрыт через `scope_grant`). |
| **`subjects[]` (1..32) с per-subject lineage** | **list, независимый tuple-set/субъект** | reference-JSON требует; governance-изоляция (per-subject revoke/audit). admin/editor + GROUP → requireGrantAuthority (фикс #4/Q#4). |
| **`permissions[]`** | **KEEP как compiled (anchor+names), rules — authority** | reuse 4-сегмент/Check; matchLabels lossy через flat → структурная форма authority. |
| **matchLabels → tuples** | **materialization (per-object), НЕ conditional-tuple** | Подтверждено корректным: FGA `with` читает request-context, не object-state. |
| **Cardinality** | **hard DB-maxima (rules≤64, dims≤16, names≤256, compiled≤1024, subjects≤32)** | anti-DoS + tractable Check/audit. |
| **backfill legacy** | ~~INERT до re-author (не force, не lazy-undefined)~~ → **SUPERSEDED O-9: backfill отменён, legacy удаляется целиком в F (продданных нет)** | role-proliferation/scope-риск force-синтеза — **неактуально под clean-cut**. |

---

## 9. Открытые вопросы для заказчика

1. **aggregationRule (K8s ClusterRole-aggregation).** Включать opt-in controller-owned union? **Рекомендация: НЕ в этой фазе.** Зарезервировать поля в proto-комментарии, не реализовывать; follow-up KAC.
2. **strict-mode для anchor-vs-matchLabels double-coverage (одного tier).** **Рекомендация: WARNING (не reject)** в v1. **Коррекция:** при разных tier'ах (anchor viewer + label admin) — НЕ subsumes, оба арма эмитятся, WARNING не выдаётся.
3. **`matchExpressions` (In/NotIn/Exists).** **Рекомендация: только AND-equality в v1**; зарезервировать; добавляемо аддитивно.
4. **Group-subject amplification + effective-principal audit.** GROUP грантит всем членам; churn меняет blast-radius. **Рекомендация:** (a) admin/editor + GROUP → requireGrantAuthority на scope (фикс); (b) **новый `ExpandAccess` RPC** (FGA Expand userset→concrete principals) для «кто реально может DELETE X» — обязателен для 2026 audit-readiness (parity с effective-principal-анализом). Подтвердить достаточность `ExpandAccess` или нужен snapshot-membership.
5. **Окно deprecation для legacy binding-side target. — СНЯТО O-9 (owner 2026-06-21).** ~~Рекомендация: ≥1 минорный релиз accepted-as-FAILED_PRECONDITION, затем Phase 6 (DROP) major.~~ Deprecation-окна нет: продданных/внешних клиентов нет → legacy target/selector + мутаторы удаляются совсем в clean-cut F (acceptance F-50/F-54).
6. **[НОВЫЙ] verb-granularity parity.** v1 энфорсит 3 tier'а (`get≠list` viewer, но `create=update=delete=editor`); authored verbs ниже tier-границ — advisory/audit. **Рекомендация:** принять для v1 + завести follow-up KAC на true per-verb FGA-relations (расширение `fga_model.fga` + `SplitGrants`), если продукт требует раздельный enforce `delete` vs `create`. Решить ДО APPROVE: достаточно ли 3-tier для целевого use-case.

---

## 10. Blocking Given-When-Then сценарии (для `acceptance-author`)

Каждый — RED-тест ДО кода (ban #12). Integration (testcontainers + concurrent) + Newman где применимо.

- **GWT-1 (escalation, CRITICAL #1):** Given роль с правилом `{compute, instance, [get,list,create,update,delete]}` ARM_ANCHOR; When bind @ ACCOUNT; Then субъект получает admin **только** над `compute.instance` в scope, и **НЕ** имеет admin/editor/viewer над `vpc.*`/`iam.*`/другими типами (assert через FGA Check на чужой тип → deny).
- **GWT-2 (mixed-tier collapse):** Given роль: rule A `{compute,image,[get]}` (viewer ARM_ANCHOR) + rule B `{compute,instance,[...crud]}` (editor ARM_ANCHOR); When bind; Then `compute.image` tier == viewer (НЕ поднят до editor через whole-role collapse).
- **GWT-3 (verb-`*` ban):** Given Create custom-роли с `verbs:["*"]`; Then INVALID_ARGUMENT. Given is_system-роль с `verbs:["*"]`; Then принимается (admin-tier).
- **GWT-4 (revoke after rules-edit, CRITICAL #3):** Given grant binding B (role R = rules R1) → Update R → rules R2 → Delete B; Then FGA tuple-set пуст (нет residual из R1∖R2); assert zero orphans.
- **GWT-5 (Role.Update fan-out):** Given role R несёт N ACTIVE-биндингов, R удаляет matchLabels-правило; Then все N биндингов reconcile, per-object tuple'ы удалённого правила eager-revoked (по `rule_fp`); concurrent.
- **GWT-6 (matchLabels не over-grant, HIGH #8):** Given правило `{vpc,subnet,[create], matchLabels:{env:prod}}`; When bind; Then эмитится per-object tuple **только** на subnet с `env=prod`-в-scope, и **НЕ** anchor-tuple «все subnet в scope».
- **GWT-7 (feed-gate, HIGH #9):** Given Role.Create с matchLabels-правилом на `vpc.addressPool` (admin-only Internal) или `lb.listeners` (no producer); Then INVALID_ARGUMENT "not selectable", **не** вечный PENDING.
- **GWT-8 (dual-authority, HIGH #10):** Given legacy by_selector-биндинг, существующий до flip; When role обретает matchLabels-правила; Then reconciler **не** double-эмитит (legacy + role.rules) для одного `(binding,object)`; legacy-путь authority до re-author.
- **GWT-9 (condition не bypass, MEDIUM #11):** Given binding с `builtin_condition=NON_EXPIRED` после expiry; Then raw FGA tuple существует, но Check возвращает deny на каждом call-site (vpc/compute/geo) — condition энфорсится (conditional-tuple).
- **GWT-10 (resourceNames PENDING bounded):** Given pin not-in-mirror id; Then PENDING_VERIFICATION с TTL; later id создан **outside scopeRef** → REJECTED+audit (никогда auto-ACTIVE); later id создан **другого типа** → REJECTED (type-mismatch); later id создан in-scope нужного типа → ACTIVE.
- **GWT-11 (label-tampering, HIGH security #4):** Given tenant с editor на `vpc.subnet` ставит `env=prod`; foreign admin-биндинг селектит `matchLabels:{env:prod}`; Then создание admin/editor matchLabels-биндинга требовало requireGrantAuthority на scope (low-priv актор не мог авторить); containment re-verify отсекает cross-scope.
- **GWT-12 (cap & grammar):** Given роль, чьи rules cartesian-разворачиваются в 300 perm; Then принимается post cap-raise (≤1024), assert DB CHECK не reject'ит; роль на >1024 → INVALID_ARGUMENT (не truncation). Fresh DB: Create с 4-сегмент compiled perm принимается (grammar 4-сегмент).
- **GWT-13 (OCC + reconcile race):** Given concurrent Role.Update(rules) (xmin CAS) ⟂ binding Create читающий ту же роль; Then grant использует консистентный rule-snapshot (lock binding→read role в одной tx), без torn read; ровно один Update коммитит.
- **GWT-14 (scope/role ancestry):** Given custom (account-owned) роль, bind @ CLUSTER → FAILED_PRECONDITION; bind @ PROJECT вне ancestry `role.account_id` → FAILED_PRECONDITION.
- **GWT-15 (subjects[] independence):** Given binding с 32 subjects incl. (user, group-containing-that-user); Then нет double-grant аномалии; per-subject independent revoke; `ExpandAccess` разворачивает group→principals.

—

## 11. ТРЕБОВАНИЕ (заказчик, 2026): List — фильтрованный per-object, НЕ K8s all-or-nothing

**Ключевое отличие от Kubernetes RBAC.** В K8s `list` на тип в namespace = видишь ВСЕ объекты типа или ни одного (all-or-nothing, нет per-object фильтра). В Kachō — **`List<Resource>` обязан возвращать ровно те объекты, к которым у caller есть доступ**, по union армов гранта:
- `all_in_scope` → все объекты типа в scope;
- `matchLabels` → только совпавшие по меткам (в scope);
- `resourceNames` → только перечисленные id;
- нет доступа к объекту → объект **не виден** в выдаче (не leak'ается даже его existence).

**Механизм:** per-object фильтрация через **FGA `ListObjects`** (вернуть множество объектов типа T, на которых subject имеет relation `viewer`/`list`), а НЕ type-level «можно листать тип». Источник питания — те же **materialized per-object tuples** (из matchLabels/resourceNames-правил, эмитятся reconciler'ом) + `scope_grant` (для all_in_scope). Т.е. List и Check читают одну и ту же tuple-базу — single source of truth, паритет read==enforce.

**Интеграция:** существующий listauthz CI-гейт (`make audit-list-filter`, security.md «публичный List обязан фильтровать через listauthz») **расширяется до per-object**: каждый публичный `List` прогоняет id-set через `ListObjects`/batch-Check и отдаёт пересечение. Pagination применяется ПОСЛЕ фильтра (cursor по отфильтрованному набору). Cross-domain consumer'ы (vpc/compute/nlb List) фильтруют через `InternalIAMService` (ListObjects-аналог), fail-closed.

**Verification-гейт (после реализации — обязателен):**
- **LST-1 (labels):** subject с `matchLabels:{env:prod}` list-грантом → `List` отдаёт ТОЛЬКО `env=prod`-объекты в scope; объекты с `env=staging` НЕ в выдаче.
- **LST-2 (byName):** resourceNames-грант на [id1,id2] → List отдаёт ровно {id1,id2} (если существуют в scope), не больше.
- **LST-3 (global):** all_in_scope list-грант → все объекты типа в scope.
- **LST-4 (union):** несколько правил (labels ∪ names) → объединение видимых.
- **LST-5 (negative/no-leak):** объект вне всех грантов → отсутствует в List И в Get→NotFound (не FORBIDDEN, чтобы не подтверждать existence).
- **LST-6 (pagination):** page_size/page_token корректны ПОСЛЕ фильтра (не «дырявые» страницы).
- Newman + integration на каждый арм для всех доменов (compute/vpc/nlb/iam).

Это — обязательная часть rules-model редизайна (List-семантика), не follow-up.
**Файлы-артефакты (абсолютные):** proto — `/Users/dkot/workspace/github/PRO-Robotech/kacho/kacho-workspace/project/kacho-proto/proto/kacho/cloud/iam/v1/{role,role_service,access_binding,access_binding_service}.proto`; FGA-модель — `/Users/dkot/workspace/github/PRO-Robotech/kacho/kacho-workspace/project/kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga` (новый `scope_grant`-примитив); domain — `/Users/dkot/workspace/github/PRO-Robotech/kacho/kacho-workspace/project/kacho-iam/internal/domain/{role,rule,types,access_binding_target,access_binding_scope,selector_feed}.go`; authzmap — `/Users/dkot/workspace/github/PRO-Robotech/kacho/kacho-workspace/project/kacho-iam/internal/authzmap/permissions_to_relations.go` (per-rule tier, не whole-role collapse); emit — `/Users/dkot/workspace/github/PRO-Robotech/kacho/kacho-workspace/project/kacho-iam/internal/service/fga_tuple_writer_v2.go` (arm-tag вход); миграции — `/Users/dkot/workspace/github/PRO-Robotech/kacho/kacho-workspace/project/kacho-iam/internal/migrations/` (новые forward-файлы ≥0024; `0001..0023` и `0005`/`0008` НЕ редактировать; cap-raise lockstep + `role_rule_selectors` + `access_binding_emitted_tuples` + members-PK-migration).