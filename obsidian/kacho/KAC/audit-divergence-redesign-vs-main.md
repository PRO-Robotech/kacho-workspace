---
title: Аудит расхождения redesign/integration vs main — раунд 1
category: kac
tags: [kacho-iam, kacho-nlb, kacho-storage, kacho-registry, kacho-api-gateway, kac, fix, architecture]
ticket_id: TBD
status: in-progress
type: fix
repos: [kacho (monorepo)]
opened: 2026-07-24
---

# Аудит расхождения `redesign/integration` vs `main` — раунд 1

Scope: **230 коммитов, 1024 файла, +127k/−55k** (весь 7-доменный редизайн). Harness —
skill `hardening-audit-loop`, адаптированный под монорепо: 8 per-area finder'ов × 6 дименсий
(security/leak/performance/concurrency/correctness/structure/readability/lean) → **adversarial
refute-verify** каждой находки (default `real=false`).

## Итог раунда 1

| | шт |
|---|---|
| Сырых находок | 35 |
| **Подтверждено HIGH** | **9** |
| **Подтверждено MEDIUM** | **14** |
| LOW | 5 |
| Отклонено верификацией (INVALID/refuted) | 7 |

Фикс-фаза: 4 агента по **непересекающимся** файловым зонам (nlb / storage / registry /
iam+gateway+proto), строгий TDD RED→GREEN, **без git-команд** (монорепо — параллельные
git-операции сцепляют агентов, см. [[parallel-agents-shared-worktree-collision]]).

## HIGH-находки

1. **credential-free выдача cluster-admin токена** (3 находки об одном):
   `MintBootstrapToken` объявлен `permission="<exempt>"`, зарегистрирован на internal REST-mux;
   gateway-фаза `phaseInternalOriginExempt` возвращает allow **до** извлечения принципала
   (значит и без 401), а iam-side `authzguard.CallerPolicy` проверяет лишь «вызвал ли api-gateway»,
   не «кто за ним»; в хендлере authz-проверок нет. ⇒ запрос **без Bearer** отдаёт подписанный
   RS256-токен bootstrap-admin, который принимает внешний prod-gateway. Комментарии в proto/mux/
   caller_policy прямо утверждают «mTLS-листенер и есть гейт» — запрещённая посылка «internal =
   trusted» (`security.md`) + doc-truthfulness (`architecture.md`).
2. **nlb**: Listener→TargetGroup через новое `targetGroupId` валидирует только регион — нет
   project-ownership ⇒ привязка ЧУЖОГО TargetGroup (BOLA).
3. **storage**: `Image.Create` не проверяет project-ownership `source_snapshot_id`/`source_volume_id`
   ⇒ содержимое чужого приватного тома утекает в свой Image. (+MEDIUM-близнец: `volumes.source_image_id`
   принимает чужой Image.)
4. **registry**: admin-гейт на `defaultRepositoryVisibility→PUBLIC` срабатывает только при наличии
   поля в `update_mask`; **пустой mask** (легальный full-object PATCH по `api-conventions.md`) его
   обходит ⇒ editor делает реестр публичным.
5. **registry**: миграция `0006 ADD COLUMN region_id TEXT NOT NULL` без DEFAULT/backfill ⇒ падает на
   любой непустой `registries` (апгрейд существующего стенда невозможен).
6. **gateway**: override authz-скоупа через `definition_tier` применяется без привязки к FQN и на
   HTTP-пути читается из **произвольного JSON-тела** ⇒ клиент влияет на выбор authz-скоупа.
7. **proto**: `UserService.Invite` понижен `required_acr_min` 2→1, хотя Invite **атомарно создаёт
   AccessBinding** (privilege-grant) ⇒ обход step-up (`[[step-up-acr-sensitive-only]]`).

## Решение по mint (владелец, 2026-07-24)

Владелец: «если в итоге сделали через рут-токен, встраиваемый секретом и пригодный для
аутентификации с root — то mint можно удалить». **Проверено — такого механизма НЕТ:**

- `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` — только выдаёт cluster-admin **существующему юзеру по email**
  (identity+grant в `bootstrap_admin.go`), это НЕ credential: юзеру всё равно нужен интерактивный
  Hydra-логин.
- `bootstrapToken:` в `values.dev-prod` — это **ES256-ключ подписи самого mint**
  (`kacho-iam-bootstrap-sa-key`), которым **iam сам** подписывает `client_assertion` в Hydra;
  вызывающий не предъявляет ничего.
- Иных не-интерактивных путей нет: `SAKeyService.Issue` требует уже имеющегося admin-токена
  (chicken-and-egg).

⇒ **mint удалять нельзя** (единственный не-интерактивный вход в первый реальный токен; на него
опирается production-strict prodseed). **Фикс — сделать гейтом реальный credential вместо сетевой
позиции**: снять credential-free REST-роут с internal-mux + требовать проверенный клиентский
сертификат из явного SPIFFE allow-list (fail-closed в production boot-guard, core rule #16) и/или
proof-of-possession уже существующего секрета. Chicken-and-egg не возникает — секрет раздаётся
деплоем. Лживые комментарии «internal = trusted» — исправить.

## Полный список подтверждённых находок (персистировано — раньше жило только в счётчиках)


### HIGH — 9 (закрыты `4f2a93e`)

- **security** · `services/iam/internal/authzguard/caller_policy.go:98` — MintBootstrapToken (cluster-admin credential mint) is admitted with NO authN and NO authZ on the gateway internal listener — the caller-policy comment installs the forbidden «internal = trus
- **security** · `services/iam/internal/apps/kacho/seed/embedded/permission_catalog.json:2241` — Новый InternalBootstrapTokenService/MintBootstrapToken объявлен permission="<exempt>" без required_relation/scope_extractor — на cluster-internal листенере gateway пропускает его БЕЗ аутенти
- **security** · `services/nlb/internal/apps/kacho/api/listener/create.go:212` — Listener→TargetGroup wiring (new authoritative `targetGroupId`) validates only region — no project-ownership check and no object-scoped FGA Check on the caller-supplied TG id; the direct FK 
- **security** · `services/storage/internal/service/image/image.go:214` — Image.Create не проверяет, что source_snapshot_id / source_volume_id принадлежат тому же project — caller-supplied чужой id принимается (BOLA, cross-project disclosure).
- **security** · `services/registry/internal/handler/public.go:96` — Admin-gate на defaultRepositoryVisibility→PUBLIC срабатывает только при наличии поля в update_mask; пустой mask (full-object PATCH) применяет PUBLIC без admin-Check.
- **correctness** · `services/registry/internal/migrations/0006_registry_region_placement.sql:23` — ADD COLUMN region_id TEXT NOT NULL без DEFAULT и без backfill — миграция падает на любой непустой таблице registries; апгрейд существующего стенда невозможен.
- **security** · `gateway/internal/restmux/mux.go:638` — Новый RPC InternalBootstrapTokenService/MintBootstrapToken зарегистрирован на internal REST-листенере с permission="<exempt>" → минт bootstrap-токена (cluster-admin SA) проходит БЕЗ authN и 
- **security** · `gateway/internal/middleware/authz.go:883` — definition_tier-override authz-скоупа применяется без привязки к FQN и на HTTP-пути читается из ПРОИЗВОЛЬНОГО JSON-тела → клиент сам выбирает объект, против которого gateway делает FGA-Check
- **security** · `proto/kacho/cloud/iam/v1/user_service.proto:71` — UserService.Invite понижен с required_acr_min=2 до 1, но Invite атомарно создаёт AccessBinding (project_id+role_id) — step-up-гейт грант-поверхности обходится через /iam/v1/users:invite

### MEDIUM — 14 (закрыты фикс-фазой (коммит в работе))

- **security** · `services/iam/internal/apps/kacho/api/access_binding/create.go:162` — Новые F9 structural gates читают чужую Role и чужой Project ДО requireGrantAuthority на RPC, у которого gateway-authz отключён (`permission="<exempt>"`) → cross-tenant existence/metadata ora
- **concurrency** · `services/iam/internal/apps/kacho/api/access_binding/revoke.go:146` — doRevoke снимает snapshot emitted-tuple ledger БЕЗ advisory-lock/FOR UPDATE, а REVOKED-биндинг реконсайлером больше никогда не delete-stale'ится → tuple, дописанный конкурентным forward-прох
- **performance** · `services/iam/internal/apps/kacho/api/access_binding/delta_input.go:40` — target.resources принимается без ограничения кардинальности (ни в proto, ни в targetFromProto, ни в AccessTarget.Validate), а новый filterMatchedToTarget пересекает наборы линейным Contains 
- **correctness** · `services/iam/cmd/kacho-iam/wiring.go:275` — Унифицированный F11 `abList` собирается только с `.WithRelationQueries(...)` — без `.WithRelationStore(...)`, т.е. без grant-authority/cluster-admin ветки, которая есть у ВСЕХ siblings (Get,
- **correctness** · `services/iam/internal/repo/kacho/pg/access_binding_repo.go:112` — F11 `abReader.List` не имеет ни предиката по статусу, ни поля IncludeRevoked в ListFilter — вместе с новым F10 soft-revoke (RevokeGuarded оставляет строку со status='REVOKED') отозванные гра
- **concurrency** · `services/nlb/internal/repo/kacho/pg/target_group_repo.go:411` — После сноса pivot'а guard `MoveProject … WHERE NOT EXISTS(listeners referencing)` перестал быть атомарным: парный locking-read исчез вместе с `AttachedTargetGroups.Attach` (`FOR NO KEY UPDAT
- **performance** · `services/nlb/internal/apps/kacho/api/loadbalancer/sg_validate.go:39` — `validateSecurityGroups` делает по одному синхронному gRPC-вызову в vpc на КАЖДЫЙ элемент `security_group_ids`, без верхней границы количества, без дедупликации и без общего бюджета — proto-
- **concurrency** · `services/vpc/internal/apps/kacho/api/subnet/create.go:218` — F7-инвариант «subnet CIDR ⊆ declared-супернет сети» проверяется software check-then-act: Subnet.Create (и Subnet.AddCidrBlocks) читают родительскую networks-строку обычным SELECT без row-loc
- **correctness** · `services/compute/internal/migrations/0016_instance_redesign.sql:24` — instances.machine_type_id ссылается на новую таблицу machine_types в ТОЙ ЖЕ БД, но FK нет, а InternalMachineTypeService.Delete удаляет строку каталога без какой-либо проверки ссылок — единст
- **structure** · `services/vpc/internal/migrations/0015_network_supernet.sql:16` — Колонка networks.default_route_table_id и одноимённое публичное поле Network.defaultRouteTableId никогда не заполняются: ни один прод-путь их не пишет, а старый триггер «самая ранняя RT» (00
- **performance** · `services/vpc/internal/apps/kacho/api/network/helpers.go:58` — Declared-супернет сети (networks.ipv4_cidr_blocks/ipv6_cidr_blocks) растёт без какого-либо потолка: ни proto, ни use-case, ни DB не ограничивают число блоков, а NetworkService.AddCidrBlocks 
- **correctness** · `services/storage/internal/check/permission_map.go:128` — InternalImageService/GetInternal зарегистрирован на :9091, но отсутствует в backend PermissionMap → corelib authz fail-closed «rpc not mapped» на каждый вызов.
- **security** · `services/storage/internal/repo/pg/volume_repo.go:210` — Новое поле volumes.source_image_id принимает id образа из ЛЮБОГО проекта — boot-Volume можно засеять чужим приватным Image.
- **correctness** · `pkg/outbox/drainer/drainer.go:50` — ORDERING-контракт shared-drainer'а объявляет register-appliers (compute/vpc) безопасными при ApplyConcurrency>1 БЕЗ PartitionColumn, ссылаясь на source_version-LWW; но LWW защищает только UP

### LOW — 5 (не чинились: verify-фильтр по умолчанию отсекает LOW; список для раунда 2)

- geo: пустой update_mask в Internal Zone/Region Update молча затирает infra°-поля
- compute: редизайн MetadataOptions вносит имена чужих облаков обратно в отгружаемый дескриптор (ban #2)
- deploy: в production-оверлее iam→Hydra Admin API прописан plaintext http (обоснование в комментарии не покрывает риск)
- deploy: registry.iam.jwksUrl выставлен только чтобы удовлетворить boot-guard requireSecureJWKSURL
- fixtures: setup.sh пишет сырой FGA-tuple v_create@project для registry-editor'а вместо продуктового пути
## Затронутые сущности vault
- [[iam-internal-bootstrap-token-service]] (#58 — контракт меняется: не REST-exempt, а credential-gated)
- [[ci-red-triage-iam-storage-registry]] · [[step-up-acr-sensitive-only]] · [[parallel-agents-shared-worktree-collision]]

## Status
- [x] раунд 1: find → adversarial-verify (35 → 9 HIGH + 14 MEDIUM + 5 LOW)
- [x] решение по mint: удалять нельзя, гейтить реальным credential (проверено по коду)
- [ ] фикс-фаза HIGH (4 зоны, TDD) → review → commit
- [ ] фикс-фаза MEDIUM (14) + LOW (5)
- [ ] раунд 2 до сходимости (dry-раунд = 0 confirmed)

#kacho-iam #kacho-nlb #kacho-storage #kacho-registry #kacho-api-gateway #kac #fix #architecture
