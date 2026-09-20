---
title: MembershipService
aliases:
  - MembershipService (iam)
proto_file: project/kaname/proto/kaname/cloud/iam/v1/membership_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-user]]"
methods_count: 3
async_methods: 1
status: test
related_tickets:
  - "[[issue-181-kaname]]"
  - "[[issue-1351]]"
tags:
  - rpc
  - kacho-iam
  - iam
verified_against: "kaname, ветка issue-181-membership-create от release/iam-lines@dfe2fefa: перечень методов сверен с контрактом в обе стороны; в стволе службы (4f6ab4be) глаголов два — Get и List"
---

# MembershipService (iam)

**Proto**: `project/kaname/proto/kaname/cloud/iam/v1/membership_service.proto` (дом — репозиторий службы `PRO-Robotech/kaname`; платформа берёт стабы пином).
**Backend**: `kaname:9090` (public gRPC); на внутреннем слушателе служба **не** регистрируется — единственный гейт чтений пообъектная проверка края.

Поверхность **трёхадресная**, и плоская коллекция несёт **только создание** (IAM-ID-2 §2.6, полоса C гейта IAM-ID-2-15):

| метод | адрес | sync/async | отношение | acr |
|---|---|---|---|---|
| `Create` | `POST /iam/v1/memberships` | async → `Operation` (metadata `CreateMembershipMetadata`, response `Membership`) | `editor` @ `account` по `account_id` | 2 |
| `Get` | `GET /iam/v1/accounts/{account_id}/memberships/{membership_id}` | sync | `viewer` @ `account` | 1 |
| `List` | `GET /iam/v1/accounts/{account_id}/memberships` | sync, курсор `(created_at, id)`, фильтр `userId=` | `viewer` @ `account` | 1 |

## Create — переезд приглашения (IAM-ID-1 S3.2, [[issue-181-kaname]])

Тот же поток, что `UserService.Invite` (`internal/apps/kaname/api/user/invite.go`): общие
синхронная приёмка и транзакция; до стадии S4 ([[issue-1351]]) оба глагола живут рядом и на
одну пару «человек × аккаунт» дают **одно** членство (`UNIQUE(user_id, account_id)`,
идентификатор вычислим из пары SQL-функцией и переиспользуется).

- почта неизвестна → строка `PENDING` + членство `PENDING`, письмо одно на пару;
- почта известна → строки не заводится, членство добавляется; у вошедшего — сразу `ACTIVE`.

Ответ собирается из строки, прочитанной **той же транзакцией** (`repouser.ReaderIface.Membership`),
проекция одна на всё (`internal/dto/toproto/membership.go`). Осиротевшая операция разрешается
по паре из метаданных (`operationresolver`): есть — `done`, нет — `interrupted`.

## Каталог прав — окно до подъёма пина

Запись `kaname.cloud.iam.v1.MembershipService/Create` лежит в копии службы, у копии края её
нет до перегенерации по новому пину; окно объявлено записью `check.CatalogPendingEntries`
(`internal/check/catalog_copy_parity.go`) с предикатом снятия «край несёт глагол». Появление
записи у края делает запись ведомости находкой — тогда её снимают и синхронизируют копию.

#rpc #kacho-iam #iam
