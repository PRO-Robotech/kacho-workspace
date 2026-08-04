---
title: UserAccountService (om)
aliases:
  - UserAccountService (organizationmanager)
category: rpc
visibility: public
domain: organizationmanager
status: deprecated
tags:
  - rpc
  - kacho-rm
  - organization
  - deprecated
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!warning] Сервиса в дереве продукта НЕТ — записка оставлена как история
> Домена organizationmanager в дереве нет. Роль «учётная запись пользователя» несут `UserService` ([[iam-user-service]]) и `AccountService` ([[iam-account-service]]).
>
> Перечни методов и REST-маршрутов ниже **не являются контрактом**: по ним нельзя
> ни позвать, ни найти код. Читать как след прежнего замысла.
> Сверено по стволу `redesign/integration` 2026-08-05.

> [!warning] Запланированное в снятом домене — не «ждёт», а отменено (KAC-124)
> Записка числилась запланированной. Домена, в котором её предмет должен был
> появиться, больше нет, поэтому «запланировано» тут читается как ожидание
> работы, которой не будет: ожидающий статус на снятом домене неотличим от живой
> очереди. Учётные записи и привязки прав уехали в iam и там уже есть
> ([[../resources/iam-access-binding]]).

# UserAccountService (om) — отменён вместе с доменом (KAC-124)

Задел под учётные записи и привязки прав в домене organizationmanager. В proto
не появился никогда — сначала ждал разблокировки, потом домен сняли целиком
вместе с организацией, облаком и папкой.

## Чем закрыт

Домен iam: пользователи, служебные учётные записи, группы, роли и привязки
доступа — действующая поверхность, а не задел. См.
[[../resources/iam-access-binding]] и [[../packages/proto-organizationmanager]]
как след снятого домена.

## Что снято из этой записки

Числа методов убраны: они были нулями-заглушками и в срезе по количеству
читались как «сервис есть, методов ноль». Тег принадлежности к iam снят — записка
описывает снятый домен, а не iam, и в срезе по iam ей не место.

## See also

[[../packages/proto-organizationmanager]] [[../packages/proto-access]]
[[../resources/iam-access-binding]] [[../KAC/KAC-124]]

#rpc #kacho-rm #organization #deprecated
