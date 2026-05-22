---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.AuthorizeService/BatchCheck
  - rpc: kacho.cloud.iam.v1.AuthorizeService/Check
  - rpc: kacho.cloud.iam.v1.AuthorizeService/ExpandRelations
  - rpc: kacho.cloud.iam.v1.AuthorizeService/ListObjects
  - rpc: kacho.cloud.iam.v1.AuthorizeService/ListSubjects
  - rpc: kacho.cloud.iam.v1.InternalAuthorizeService/GetFGAStoreInfo
  - rpc: kacho.cloud.iam.v1.InternalAuthorizeService/ReadTuples
  - rpc: kacho.cloud.iam.v1.InternalAuthorizeService/ReloadModel
  - rpc: kacho.cloud.iam.v1.InternalAuthorizeService/RunRegoTest
  - rpc: kacho.cloud.iam.v1.InternalAuthorizeService/WriteTuples
  - rpc: kacho.cloud.iam.v1.InternalIAMService/Check
  - rpc: kacho.cloud.iam.v1.InternalIAMService/ForceLogout
  - rpc: kacho.cloud.iam.v1.InternalIAMService/GetJWKSStatus
  - rpc: kacho.cloud.iam.v1.InternalIAMService/ListPermissions
  - rpc: kacho.cloud.iam.v1.InternalIAMService/LookupSubject
  - rpc: kacho.cloud.iam.v1.InternalIAMService/PollSubjectChanges
  - rpc: kacho.cloud.iam.v1.InternalIAMService/WriteCreatorTuple
status: implemented
source_sha: ""
---

# Authorization

Read-модель авторизации — фактическая проверка «можно/нельзя». Три сервиса:
`AuthorizeService` (public REBAC Check), `InternalAuthorizeService` (write-path
FGA-tuple'ов + lifecycle модели/Rego), `InternalIAMService` (per-RPC authz-gate
для других kacho-сервисов + subject lookup).

## Зачем

`AccessBinding` — это намерение; здесь оно превращается в решение. Движок —
REBAC/Zanzibar (OpenFGA): доступ выводится из relation-tuple'ов с учётом
group-membership, project-иерархии и CEL-conditions-overlay, плюс OPA
cluster-deny gate (fail-closed override).

## Контракт

**`AuthorizeService`** (public, sync):
- `Check` — boolean `(user, relation, object) → allowed`.
- `BatchCheck` — до 100 tuple'ов за RPC.
- `ListObjects` — «к каким объектам типа T у user есть relation» (List-фильтрация).
- `ListSubjects` — «у каких subject'ов есть relation к object».
- `ExpandRelations` — Zanzibar-tree expand для debug/UI.

**`InternalAuthorizeService`** (internal 9091, sync): `WriteTuples` /
`ReadTuples` — bulk tuple-операции; `ReloadModel` — атомарный switch активной
authorization-model; `RunRegoTest` — dry-run Rego-policy против snapshot-кейсов;
`GetFGAStoreInfo` — метаданные FGA-store.

**`InternalIAMService`** (internal 9091): `Check` — per-RPC authz-gate, вызывают
`kacho-vpc` / `kacho-compute` перед мутацией ресурса; `LookupSubject` — резолв
JWT-идентичности в principal (oneof key: external_id / id / email);
`ListPermissions` — агрегированные permission'ы subject'а на ресурс;
`WriteCreatorTuple` — записать creator-tuple при создании ресурса;
`PollSubjectChanges` — поллинг изменений subject'а; `ForceLogout` —
инвалидация сессий; `GetJWKSStatus` — статус JWKS-ключей.

## Lifecycle

- Поток `Check`: извлечь identity из токена → разрешить conditions/JIT-overlay →
  OpenFGA `Check` → OPA cluster-deny gate → кэш результата с коротким TTL.
- Tuple-sync конкурирует с `AccessBinding` write-path, поэтому `WriteTuples`
  идемпотентен (повтор существующего tuple → ok).

## Gotchas

- `Check` возвращает boolean — `allowed=false` не есть ошибка; `PermissionDenied`
  отдаётся, только если сам caller не вправе вызывать `Check`.
- OpenFGA/OPA недоступны → fail-closed для мутаций.
- `Internal*` — только internal-listener; светить на external TLS запрещено
  (§Запрет #6).
- Model/Rego write/reload — только cluster-system-admin.
