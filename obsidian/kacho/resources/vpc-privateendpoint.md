---
title: PrivateEndpoint
aliases:
  - PrivateEndpoint (vpc)
  - vpc PrivateEndpoint
  - PE
category: resource
domain: vpc
id_prefix: "нет — ресурс отсутствует в дереве"
owner_table: "нет — таблицы private_endpoints не существует"
owner_db: kacho_vpc
project_level: true
status: deprecated
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/vpc-privateendpoint-service]]"
tags:
  - resource
  - kacho-vpc
  - privateendpoint
  - deprecated
---

> [!warning] Ресурса в дереве продукта НЕТ — записка оставлена как след
> Предикат переписи (сверено 2026-08-05, ствол `redesign/integration`):
> `grep -ril 'private_endpoint\|PrivateEndpoint\|privatelink'` по каталогам
> `proto/`, `services/`, `gateway/`, `pkg/` даёт **ноль** файлов. Ни контракта, ни
> таблицы, ни сервиса, ни миграции. Живых таблиц у vpc двадцать, `private_endpoints`
> среди них нет.
>
> Прежняя редакция объявляла `status: stable` и ссылалась на миграцию
> «0024 private_endpoint_fks» и на интеграционный тест внешних ключей — ни того, ни
> другого в дереве нет. Это ровно тот класс, ради которого записки и сверяют:
> **уверенное описание отсутствующего** хуже очевидного легаси, потому что читается как
> факт.

# PrivateEndpoint — снят (история)

Замысел: приватная точка входа тенанта к платформенным сервисам (объектное хранилище,
реестр образов) **внутри** его подсети, без выхода в публичную сеть. Ресурс должен был
занимать адрес из подсети и держать вид сервиса, к которому подключается.

## Что от замысла осталось верным

- **Адрес как отдельный ресурс** — приём прижился и живёт в [[vpc-address]]: любая привязка
  IP выражается ссылкой на Address, а не «сырым» полем.
- **Ссылка держит владельца** — `ON DELETE RESTRICT` на подсеть и адрес: нельзя удалить то,
  на чём висит потребитель. Этот контракт живёт у [[vpc-networkinterface]] и
  [[vpc-address]].

## Если ресурс когда-нибудь заведут заново

Он попадёт под общие правила, а не под эту записку: якорь размещения — подсеть
([[vpc-subnet]]), зона наследуется, `id` immutable и адресует ресурс во внешних ссылках,
мутации возвращают `Operation`, приёмка Given-When-Then до первой строки кода.

## См. также

[[vpc-address]] · [[vpc-subnet]] · [[../rpc/vpc-privateendpoint-service]]

#resource #vpc #privateendpoint #deprecated
