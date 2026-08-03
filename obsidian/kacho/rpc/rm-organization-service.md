---
title: OrganizationService
aliases:
  - OrganizationService (rm)
  - OrganizationService (organizationmanager)
category: rpc
backend: kacho-resource-manager
visibility: public
domain: organizationmanager
status: deprecated
related_resource: "[[resources/rm-organization]]"
tags:
  - rpc
  - kacho-rm
  - organization
  - deprecated
---

> [!warning] Сервис снят вместе со своим доменом (KAC-124)
> Ни этого сервиса, ни домена organizationmanager в дереве продукта нет:
> объявления сервиса в proto не существует, каталога домена тоже. REST-префикс,
> который он занимал, шлюзом не обслуживается. Преемник — AccountService в iam.

# OrganizationService — снят (KAC-124)

Сервис корня прежней иерархии арендатора. Жил в собственном proto-домене, но
обслуживался тем же снятым бэкендом, что Cloud и Folder — отсюда парная записка
[[om-organization-service]].

## Чем заменён

Organization / Cloud / Folder → Account / Project в iam (KAC-124); организация и
облако свелись в один аккаунт.

## Что снято из этой записки

Таблица методов и таблица соответствия REST удалены вместе с полями шапки,
называвшими файл proto и адрес бэкенда. Отдельно снята часть про заготовки
привязок доступа: она описывала нереализованные заглушки снятого сервиса и к
нынешней модели прав отношения не имеет — та живёт в iam
([[../resources/iam-access-binding]]).

## See also

[[om-organization-service]] [[../resources/rm-organization]]
[[../packages/proto-organizationmanager]] [[../resources/iam-access-binding]]
[[../KAC/KAC-124]]

#rpc #kacho-rm #organization #deprecated
