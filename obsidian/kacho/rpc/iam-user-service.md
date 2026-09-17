---
title: UserService
aliases:
  - UserService (iam)
proto_file: kaname/cloud/iam/v1/user_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-user]]"
methods_count: 11
async_methods: 8
status: done
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[issue-1281-kaname]]"
  - "[[sub-phase-1.2-iam-operations]]"
  - "[[sub-phase-1.3-subject-privileges]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - mirror
verified_against: "kaname main@af0ca8f3: перечень RPC сверен с `proto/kaname/cloud/iam/v1/user_service.proto` в ОБЕ стороны 2026-09-17 (9 глаголов), каталог use-case `internal/apps/kaname/api/user/` прочитан по именам файлов; release/iam-lines@6acf8f19 — десятый глагол `ResendInvite`; семантика authz в таблице методов построчно не пересматривалась с 2026-08-05"
---

# UserService (iam)

**Proto**: `proto/kaname/cloud/iam/v1/user_service.proto` (дом — репозиторий службы `PRO-Robotech/kaname`; платформа берёт стабы пином: контрактов iam под каталогом контрактов платформы на `main@972bdc34` — 0 файлов).
**Backend**: `kaname:9090` (public gRPC). Use-case — `internal/apps/kaname/api/user/` (по файлу на глагол: `get.go`, `list.go`, `invite.go`, `update.go`, `delete.go`, `remove_from_account.go`, `set_blocked.go` — `Block`/`Unblock` одним потоком; `handler.go` — транспорт, включая `ListOperations`; в линии `release/iam-lines` ещё `resend_invite.go`); зеркало внешней личности и завершение восстановления — `internal_upsert.go`, `internal_on_recovery.go` ([[iam-internal-user-service]]).
**Visibility**: public — read (`Get`/`List`) + label-write `Update` (DIVERGENCE-A); identity-mirror write — через [[iam-internal-user-service]].
**Status**: backend в [[KAC-112]]; `Update` (label-write) merged DIVERGENCE-A (proto#89 / iam#249 `b4164e0f` / api-gateway#102).


> [!note] Глагол исключения из аккаунта — В СТВОЛЕ службы (перемерено 2026-09-17)
> Прежняя редакция говорила «линия `release/identity-3` добавляет глагол, в стволе его ещё нет»
> и не писала имени координатой. Сегодня `RemoveFromAccount` стоит в `main` службы, предикат:
> ```sh
> git -C kaname grep -n 'rpc RemoveFromAccount' origin/main -- proto/kaname/cloud/iam/v1/user_service.proto   # → 1
> ```
> Заведён задачей [`kacho#1127`](https://github.com/PRO-Robotech/kacho/issues/1127). Глагол про
> **членство**, а не про личность: круг тех, кто вправе вывести, равен кругу тех, кто вправе
> ввести. Сужение круга чтения перечня токенов и истории сессий человека до «сам человек +
> надзор облака» — числа, предикаты и гейты в [[KAC/identity-stewardship-boundary-2026-08]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetUserRequest | User | sync | по id (`usr…`). **Authz (flat Design B): self OR `v_get` на `iam_user:<id>` OR cluster-admin (`authzguard.AllowsVGet` + self fast-path); non-authz → NotFound (hide).** См. [[rbac-explicit-model-2026]] read-authz trail. |
| List | ListUsersRequest | ListUsersResponse | sync | filter (email-prefix), page_token. **`viewer ∪ v_list`** (эталон role.List; DIVERGENCE-A): anonymous→empty, FGA error→`Unavailable`, self-floor, admin/owner/cluster-admin через viewer-tier; **membership-over-show устранён** (член аккаунта не видит всех — только себя + viewer/v_list). `Get == List` resolver. |
| Update | UpdateUserRequest | operation.Operation | **async** | **новый публичный label-write RPC** (DIVERGENCE-A, [[sub-phase-T3.3-unify-iam-label-scope-acceptance]]). **Flat request** `{user_id, update_mask, labels}` (паритет с UpdateRole/SA/AB — НЕ вложенный `User`). `labels` — единственное mutable; `external_id` (и иные IdP-mirror) в `update_mask` → `INVALID_ARGUMENT "externalId is immutable after User.Create"` (`internal/apps/kaname/api/user/update.go`); unknown mask-поле → `INVALID_ARGUMENT`; пустой mask = full-PATCH над `labels`. AuthZ — `v_update` на `iam_user:<id>` + cluster-admin short-circuit. label-change co-commit'ит reconcile-event в writer-tx (eager re-материализация). REST `PATCH /iam/v1/users/{user_id}`. |
| Delete | DeleteUserRequest | operation.Operation | **async** | admin-only на E0; E2 — self-delete тоже |
| RemoveFromAccount | RemoveUserFromAccountRequest | operation.Operation | **async** | исключение человека из аккаунта (`kacho#1127`); `POST /iam/v1/users/{user_id}:removeFromAccount`; use-case `remove_from_account.go` |
| ListOperations | ListUserOperationsRequest | ListUserOperationsResponse | sync | per-resource ops history (sub-phase 1.2; filter `resource_id`, viewer-tier на gateway). Был дырой → UI таб «Операции» бил в 404. |

> **НЕТ Create** — User создаётся только через OIDC callback ([[iam-internal-user-service]] `UpsertFromIdentity`).
> **Update — только `labels`** (см. таблицу). `email`/`displayName`/`external_id` остаются IdP-mirror'ом из Zitadel (immutable локально); editable — только tenant-facing `labels`.

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/users/{id}` | Get |
| `GET /iam/v1/users` | List |
| `PATCH /iam/v1/users/{user_id}` | Update (label-write) |
| `DELETE /iam/v1/users/{id}` | Delete |
| `GET /iam/v1/users/{user_id}/operations` | ListOperations |
| `POST /iam/v1/users:invite` | Invite |
| `POST /iam/v1/users/{user_id}:removeFromAccount` | RemoveFromAccount |
| `POST /iam/v1/users/{user_id}:block` · `:unblock` | Block · Unblock |
| `POST /iam/v1/users/{user_id}:resendInvite` | ResendInvite — **только в линии** `release/iam-lines` (kaname#186), в `main` службы нет |

## Notes

- Delete blocked → `FailedPrecondition "User <id> owns accounts and cannot be deleted"` (FK `accounts_owner_fk` RESTRICT).
- GroupMember и AccessBinding на user — soft-ref, не блокируют delete на DB-уровне; service-слой блокирует sentinel'ом (см. acceptance §7.5).
- **ListOperations (sub-phase 1.2, iam #160)** — `WithListOperations` mirror существующих 5 ресурсов; фильтрует `operations` по `resource_id`. Privacy: per-scope-viewer, не per-creator (см. `PRO-Robotech/kaname:docs/engineering/architecture/operations-visibility-privacy.md`). См. [[sub-phase-1.2-iam-operations]].
- **Привилегии-таб (sub-phase 1.3)** — детальная страница User в kacho-ui получила таб «Привилегии» через [[iam-access-binding-service]] `ListSubjectPrivileges` (subject=этот user) + кнопку «добавить привилегии» → AccessBindingCreatePage с locked subject. См. [[sub-phase-1.3-subject-privileges]].


## Сверка со стволом (2026-08-05)

В контракте **восемь** RPC. **Не были названы в записке** три глагола, и все три —
действия со своими метаданными, а не поля `Update`:

| Метод | Ответ | REST | Метаданные |
|---|---|---|---|
| `Invite` | `Operation` | `POST /iam/v1/users:invite` (в редакции 2026-08-05 стояло `POST /iam/v1/users`; перемерено 2026-09-17 по `main` службы) | `InviteUserMetadata` |
| `Block` | `Operation` | `POST /iam/v1/users/{user_id}:block` | `BlockUserMetadata` |
| `Unblock` | `Operation` | `POST /iam/v1/users/{user_id}:unblock` | `UnblockUserMetadata` |
| `ResetSecondFactor` | `Operation` | `POST /iam/v1/users/{user_id}:resetSecondFactor` | `ResetSecondFactorMetadata` |

`ResetSecondFactor` (Ф12 Р10, [[KAC/issue-1281-kaname]]) — третий читатель `identity_suspender`
с полом «2»: снимает у человека `totp` и `lookup_secret`, кроет все его сессии отсечкой
`second-factor-reset` актором-распорядителем, событие `iam.user.second_factor_reset` с обоими
акторами; без заведённого фактора (строки нет либо `pending`) — `FAILED_PRECONDITION` с токеном
`SECOND_FACTOR_NOT_ENROLLED`, `pending` не тронута. Провязан только посадкой `own`.

Пользователь **не создаётся** обычным `Create` — он приглашается (`Invite`) либо
заводится апсертом по внешней личности через `InternalUserService.UpsertFromIdentity`.

> [!note] Отказ на заблокированном — `FAILED_PRECONDITION`, и это **400**, а не 412
> Состояние ресурса не позволяет операцию ⇒ `FAILED_PRECONDITION` с текстом вида
> `"... is not active"`. Край не несёт своего отображения ошибок, поэтому HTTP выбирает
> `runtime.HTTPStatusFromCode`, а он даёт **400**. 412 не производится краем ни для одного
> кода. Таблица кодов — `api-conventions.md` §«gRPC-код → HTTP-статус».

## Сверка со стволом службы (2026-09-17)

Контракт переехал в репозиторий службы вместе с ней (`polyrepo.md` §Топология); прежние
координаты монорепо — каталог контрактов iam платформы и каталог службы под сервисами — в
дереве платформы **не резолвятся** и здесь сняты (мёртвый адрес в записке намеренно не
воспроизводится: проверка свежести читает его как живое утверждение). В `main` службы (`af0ca8f3`) глаголов **девять**: `Get`, `List`, `Invite`, `Update`,
`Delete`, `RemoveFromAccount`, `Block`, `Unblock`, `ListOperations`; асинхронных
(`corelib.operation.Operation`) — **шесть**. В линии `release/iam-lines` (`6acf8f19`) —
десятый, `ResendInvite` (kaname#186), с записью ведомости каталога прав, ждущей края
([[KAC/issue-184-kaname]] — та же форма).

Предикат в обе стороны:
```sh
git -C kaname show origin/main:proto/kaname/cloud/iam/v1/user_service.proto | grep -cE '^\s+rpc '   # → 9
git -C kaname ls-tree -r --name-only origin/main internal/apps/kaname/api/user/ | grep -vc _test   # → 14 файлов в main (в линии 16: + resend_invite.go, mirror_tx.go), по одному на глагол плюс транспорт, порт и зеркало
```

Текст отказа `Delete` на владельце аккаунтов производит `internal/repo/kaname/pg/pgmaperr.go`
(`iamerr.ErrReferenceInUse`), а не FK-сообщение базы.

## See also

[[../packages/iam-domain]] [[../resources/iam-user]] [[iam-internal-user-service]] [[../edges/iam-to-zitadel-oidc]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam #mirror
