---
title: iam-interactive-client
category: resource
domain: iam
id_prefix: ic
owner_table: kaname.interactive_clients
owner_db: kaname
project_level: false
status: test
related_rpc:
  - InternalInteractiveClientService
related_packages:
  - corelib-oauthceremony
tags:
  - resource
  - kacho-iam
  - migrations
verified_against: "PRO-Robotech/kaname@fc9f5aff19c (коммит слияния волны 358 в ветку эпика 357), 2026-09-26: таблица прочитана в internal/migrations/0001_initial.sql, поправки — в 20260920175118_interactive_client_carries_its_secret_verifier.sql и 20260923230023_interactive_client_declares_how_it_authenticates.sql (разделы Up); методы службы — proto/kaname/cloud/iam/v1/internal_interactive_client_service.proto. Двух поправок нет в origin/main службы cbbac984b7b. Поведение use-case не перезапускалось"
---

# interactive_clients — клиент, через которого человек проходит церемонию входа

**Где**: таблица `kaname.interactive_clients` службы доступа kaname; ключ `ic-<17 base32>`
(`PrefixInteractiveClientHyphen`, [[packages/corelib-ids]]). Управление — внутренняя служба
`InternalInteractiveClientService` (`Get`, `List`, синхронно; `Create`, `Update`, `Delete` —
через Operation), только на внутреннем слушателе.
**Состояние**: таблица есть и в `main` службы; две поправки волны
[[KAC/issue-358-kaname|kaname#358]] — только в ветке эпика `357`, отсюда `status: test`.

## Что это

OAuth 2.0 клиент интерактивной церемонии: через него человек проходит вход и получает
удостоверение, которое принимает край. Машинные клиенты сюда не относятся — у них своя выдача
(`client_credentials` вне церемонии). Строка несёт адреса возврата (от 1 до 16), адреса после
выхода (до 16), аудитории, виды гранта, способ аутентификации на токен-эндпоинте и состояние
`ACTIVE` / `DELETING`.

## Способ аутентификации выражен схемой (волна 358)

- **`token_endpoint_auth_method`** объявлен у каждого клиента, умолчания нет: `none`
  (публичный — владение доказывает PKCE), `client_secret_basic` либо `client_secret_post`.
  Держит `interactive_clients_auth_method_ck` ([[KAC/issue-317-kaname|kaname#317]]).
- **`secret_verifier`** — проверочное значение секрета, argon2id разметкой PHC с теми же
  параметрами, что у паролей; секрет в открытом виде не хранится. Лежит только у клиента со
  способом-секретом (`interactive_clients_secret_verifier_method_ck`), момент установки
  стоит ровно тогда, когда значение непусто.
- Признак публичности — `none`, а **не** пустота проверочного значения: пустая строка значит
  «в этой строке материала нет», о публичности клиента она не говорит.

Сверку секрета делает служба через порт церемонии `ClientSecretVerifier`
([[packages/corelib-oauthceremony]]); удаление клиента снимает его семейства выдачи каскадом —
[[resources/iam-token-family]].

## Чего ещё нет

Свой реестр заводит клиента публичным, а часть посадок ждёт конфиденциального — это вынесенная в
волну-3 задача kaname#405, стоящая на схеме #317.

## History

- 2026-09-23 — у своей посадки заведение и снятие клиента исполняет код службы, без внешнего
  поставщика ([[KAC/issue-322-kaname|kaname#322]], запрос #326); проверочное значение секрета —
  колонкой таблицы ([[KAC/issue-313-kaname|kaname#313]]).
- 2026-09-24 — способ аутентификации объявлен у каждого клиента и держится `CHECK`
  ([[KAC/issue-317-kaname|kaname#317]], сборка 1, PR #411).
- 2026-09-25 — волна #358 влита в ветку эпика `357` (PR #422, `fc9f5aff19c`).
- 2026-09-26 — записка заведена: ресурс не описывала ни одна записка хранилища.

#resource #kacho-iam #migrations
