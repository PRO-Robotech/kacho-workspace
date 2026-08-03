---
title: proto-rm
category: package
repo: kacho-proto
layer: proto
status: deprecated
tags:
  - packages
  - proto
  - kacho-rm
  - deprecated
---

> [!warning] Домен proto снят (KAC-124)
> Каталога этого домена в дереве продукта нет, объявлений его сервисов в proto
> тоже. Ниже — след, а не описание действующего домена.

# proto-rm — снят (KAC-124)

Домен proto прежней иерархии арендатора: сообщения и сервисы облака и папки.
Организация жила в соседнем домене — [[proto-organizationmanager]].

## Чем заменён

Домен iam: аккаунт и проект вместо организации, облака и папки (KAC-124).

## Что снято из этой записки

Путь каталога, имя пакета proto и путь импорта Go удалены как координаты: ни
одна в дереве не резолвится. Перечень файлов proto снят по той же причине — он
числился расхождением у проверки свежести. Абзац про положение домена в графе
обращений снят как утверждение о действующем рантайме; исторические рёбра
сохранены ссылками ниже.

## See also

[[proto-organizationmanager]] [[../resources/rm-cloud]] [[../resources/rm-folder]]
[[../rpc/rm-cloud-service]] [[../rpc/rm-folder-service]]
[[../edges/vpc-to-rm-folder-exists]] [[../edges/compute-to-rm-folder-check]]
[[../KAC/KAC-124]]

#packages #proto #kacho-rm #deprecated
