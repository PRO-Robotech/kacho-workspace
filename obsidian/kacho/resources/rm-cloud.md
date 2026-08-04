---
title: Cloud
aliases:
  - Cloud (rm)
  - rm Cloud
category: resource
domain: resourcemanager
status: deprecated
related_rpc:
  - "[[rpc/rm-cloud-service]]"
related_packages:
  - "[[packages/proto-rm]]"
tags:
  - resource
  - kacho-rm
  - cloud
  - deprecated
---

> [!warning] Ресурс снят вместе со своим доменом (KAC-124)
> Домена resource-manager в дереве продукта нет: ни каталога proto, ни объявления
> сервиса, ни схемы БД. Преемник — Account в iam ([[iam-account]]). Ниже — след,
> а не описание действующего ресурса.
>
> **Снятие закреплено проверкой, а не только отсутствием файлов** (сверено по стволу
> 2026-08-05): `gateway/internal/proxy/resolver_test.go`,
> `TestResolver_RemovedResourceManagerBlocked` требует, чтобы
> `/kacho.cloud.resourcemanager.v1.CloudService/List`,
> `…FolderService/Get` и `/kacho.cloud.organizationmanager.v1.OrganizationService/List`
> **не резолвились** на краю. То есть возвращение домена не «просто не сделано» —
> оно покраснеет.

# Cloud — снят (KAC-124)

Средний уровень прежней иерархии арендатора: принадлежал организации и держал
папки. Промежуточного уровня в преемнике нет вовсе — иерархия сократилась с трёх
уровней до двух, аккаунт и проект.

## Чем заменён

Organization / Cloud / Folder → Account / Project в iam (KAC-124). Организация и
облако свелись в один аккаунт ([[iam-account]]), папка — в проект
([[iam-project]]).

> [!note] Префикс идентификатора пережил ресурс
> Константа префикса этого ресурса в дереве продукта **жива** — осталась
> легаси-константой в пакете идентификаторов и делится с Folder. Резолв имени
> доказывает существование **имени**, а не ресурса.

## Что снято из этой записки

Таблица полей и контракт внешних ключей удалены: они называли таблицы, которых в
дереве нет, и читались как утверждение о нынешнем состоянии.

## See also

[[iam-account]] [[iam-project]] [[../rpc/rm-cloud-service]] [[../packages/proto-rm]]
[[rm-folder]] [[rm-organization]] [[../KAC/KAC-124]]

#resource #kacho-rm #cloud #deprecated
