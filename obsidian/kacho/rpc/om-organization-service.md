---
title: OrganizationService (om alias)
aliases:
  - OrganizationService (om)
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
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!warning] Сервиса в дереве продукта НЕТ — записка оставлена как история
> Домена organizationmanager в дереве нет; проверка края `TestResolver_RemovedResourceManagerBlocked` требует, чтобы `/kacho.cloud.organizationmanager.v1.OrganizationService/List` не резолвился. Преемник — `AccountService` ([[iam-account-service]]).
>
> Перечни методов и REST-маршрутов ниже **не являются контрактом**: по ним нельзя
> ни позвать, ни найти код. Читать как след прежнего замысла.
> Сверено по стволу `redesign/integration` 2026-08-05.

> [!warning] Снят вместе со своим доменом (KAC-124)
> Псевдоним записки о сервисе, которого в дереве продукта нет. Прежний статус
> этой записки был выдуман (не из перечня канонических) и потому не попадал ни в
> один фильтр — в том числе в тот, что собирает снятое.

# OrganizationService (om) — снят (KAC-124)

Псевдоним для [[rm-organization-service]]: один и тот же снятый бэкенд
обслуживал два proto-домена, и записка существовала, чтобы поиск по второму
имени приводил к первой.

## Что снято из этой записки

Имя gRPC-сервиса и REST-префикс удалены как координаты: ни того, ни другого в
дереве нет, а записанные в обратных кавычках они читаются как утверждение о
действующей поверхности.

## See also

[[rm-organization-service]] [[../packages/proto-organizationmanager]]
[[../resources/rm-organization]] [[../KAC/KAC-124]]

#rpc #kacho-rm #organization #deprecated
