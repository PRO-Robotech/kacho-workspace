---
title: Organization
aliases:
  - Organization (organizationmanager)
  - om Organization
category: resource
domain: organizationmanager
status: deprecated
related_rpc:
  - "[[rpc/rm-organization-service]]"
  - "[[rpc/om-organization-service]]"
related_packages:
  - "[[packages/proto-organizationmanager]]"
tags:
  - resource
  - kacho-rm
  - organization
  - deprecated
---

> [!warning] Ресурс снят вместе со своим доменом (KAC-124)
> Ни домена organizationmanager, ни обслуживавшего его сервиса в дереве продукта
> нет: каталога proto, объявления сервиса и схемы БД не существует. Преемник —
> Account в iam ([[iam-account]]). Ниже — след, а не описание действующего
> ресурса.

# Organization — снят (KAC-124)

Корень прежней иерархии арендатора, родитель облака. Жил в собственном
proto-домене, но обслуживался тем же снятым сервисом, что Cloud и Folder.

## Чем заменён

Organization / Cloud / Folder → Account / Project в iam (KAC-124). Организация и
облако свелись в один аккаунт ([[iam-account]]).

> [!note] Префикс идентификатора пережил ресурс
> Константа префикса этого ресурса в дереве продукта **жива** — осталась
> легаси-константой в пакете идентификаторов. Резолв имени доказывает
> существование **имени**, а не ресурса.

## Что снято из этой записки

Таблица полей, контракт внешних ключей, жизненный цикл и абзац про заготовки
доступа удалены: они называли таблицы, которых в дереве нет, и описывали
поведение сервиса, которого не существует. Заготовки доступа, о которых там шла
речь, к нынешней модели прав отношения не имеют — она живёт в iam
([[iam-access-binding]]).

## See also

[[iam-account]] [[iam-access-binding]] [[../rpc/rm-organization-service]]
[[../packages/proto-organizationmanager]] [[rm-cloud]] [[../KAC/KAC-124]]

#resource #kacho-rm #organization #deprecated
