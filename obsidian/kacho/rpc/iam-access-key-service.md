---
title: AccessKeyService (kaname)
aliases:
  - iam-access-key-service
  - AccessKeyService
category: rpc
backend: kaname
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/kaname-access-key]]"
methods_count: 6
async_methods: 2
status: test
related_tickets:
  - "[[KAC/issue-1273]]"
tags:
  - rpc
  - kacho-iam
  - iam
verified_against: "kaname release/iam-lines@4b674bf5 — project/kaname/proto/kaname/cloud/iam/v1/access_key_service.proto; каталог прав службы: 6 записей, порождены генератором края"
---

# `AccessKeyService` — шесть глаголов ключа доступа (Ф7 Р11)

Регистрируется на публичном REST и gRPC **только под `own`** (под `external` ключами владеет
поставщик). Две пары «церемония → результат», перечень и снятие.

| RPC | REST | право · отношение · пол | ответ |
|---|---|---|---|
| `BeginRegistration` | `POST /iam/v1/users/{user_id}/accessKeys:beginRegistration` | `iam.access_keys.begin_registration` · `token_issuer` на `iam_user` · acr 1 | `AccessKeyRegistrationChallenge` (sync) |
| `FinishRegistration` | `POST /iam/v1/users/{user_id}/accessKeys` | `iam.access_keys.register` · `token_issuer` · acr 1 | `Operation` → `AccessKey` |
| `List` | `GET /iam/v1/users/{user_id}/accessKeys` | `iam.access_keys.list` · `token_reader` · acr 1 | `ListAccessKeysResponse` (sync) |
| `Revoke` | `DELETE /iam/v1/users/{user_id}/accessKeys/{access_key_id}` | `iam.access_keys.revoke` · `token_issuer` · acr 1 | `Operation` |
| `BeginAssertion` | `POST /iam/v1/accessKeys:beginAssertion` | `<exempt>` (SELF_SERVICE — вход ещё не состоялся) | `AccessKeyAssertionChallenge` |
| `FinishAssertion` | `POST /iam/v1/accessKeys:finishAssertion` | `<exempt>` | `FinishAccessKeyAssertionResponse` — единый отказ без подробностей |

**Что судит сервер сам** (`internal/webauthnverify`): клиентские данные (тип, испытание,
происхождение из перечня), хэш `rp_id`, флаги присутствия/проверки, подпись COSE-ключом;
`sign_count` только растёт. Аттестация не читается.

**Три величины контракта** — `authn.access-keys.rp-id` (доменное имя), `.origins` (перечень;
пустой — «никого»), `.algorithms` (из словаря) — страж старта под `own`.

**Осиротевшая операция**: резолвер `operationresolver` разрешает `Register`/`Revoke` по строке
ключа (есть — `done`, нет — `interrupted`).

**Край платформы**: шесть записей каталога и маршрутов приедут подъёмом пина после посадки
среза 3 линии (`CatalogPendingEntry` ×6 у службы до тех пор).

#rpc #kacho-iam #iam
