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
