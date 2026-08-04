---
title: CloudService
aliases:
  - CloudService (rm)
  - CloudService (resourcemanager)
category: rpc
backend: kacho-resource-manager
visibility: public
domain: resourcemanager
status: deprecated
related_resource: "[[resources/rm-cloud]]"
tags:
  - rpc
  - kacho-rm
  - cloud
  - deprecated
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!warning] Сервиса в дереве продукта НЕТ — записка оставлена как история
> Домена resource-manager в дереве нет. Снятие **закреплено проверкой**: `gateway/internal/proxy/resolver_test.go`, `TestResolver_RemovedResourceManagerBlocked` требует, чтобы `/kacho.cloud.resourcemanager.v1.CloudService/List` не резолвился.
>
> Перечни методов и REST-маршрутов ниже **не являются контрактом**: по ним нельзя
> ни позвать, ни найти код. Читать как след прежнего замысла.
> Сверено по стволу `redesign/integration` 2026-08-05.

> [!warning] Сервис снят вместе со своим доменом (KAC-124)
> Ни этого сервиса, ни его домена в дереве продукта нет: объявления сервиса в
> proto не существует, каталога домена тоже. REST-префикс, который он занимал,
> шлюзом не обслуживается. Преемник — AccountService в iam.

# CloudService — снят (KAC-124)

Сервис среднего уровня прежней иерархии арендатора. Промежуточного уровня в
преемнике нет: иерархия сократилась с трёх уровней до двух, поэтому отдельного
сервиса на его месте не появилось — его роль поглотил аккаунт.

## Чем заменён

Organization / Cloud / Folder → Account / Project в iam (KAC-124).

## Что снято из этой записки

Таблица методов и таблица соответствия REST удалены вместе с полями шапки,
называвшими файл proto и адрес бэкенда: они описывали поверхность, которой в
дереве нет. Числа методов убраны — пересчитать их не по чему.

## See also

[[../resources/rm-cloud]] [[../packages/rm-service]] [[../packages/proto-rm]]
[[rm-folder-service]] [[../KAC/KAC-124]]

#rpc #kacho-rm #cloud #deprecated
