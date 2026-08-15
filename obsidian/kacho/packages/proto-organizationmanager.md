---
title: proto-organizationmanager
category: packages
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
> Каталога этого домена в дереве продукта нет, объявления его сервиса в proto
> тоже. Ниже — след, а не описание действующего домена.

# proto-organizationmanager — снят (KAC-124)

Домен proto корня прежней иерархии арендатора: сообщение и сервис организации.
Отдельный домен, но обслуживался тем же снятым бэкендом, что облако и папка из
[[proto-rm]].

## Чем заменён

Домен iam: аккаунт вместо организации и облака (KAC-124).

## Что снято из этой записки

Путь каталога, имя пакета proto и путь импорта Go удалены как координаты: ни
одна в дереве не резолвится. Перечень файлов proto снят по той же причине — он
числился расхождением у проверки свежести. Снята и схема иерархии из трёх
уровней: она изображала действующую структуру платформы, которой нет — уровней
теперь два, аккаунт и проект.

## See also

[[proto-rm]] [[../resources/rm-organization]] [[../rpc/rm-organization-service]]
[[../rpc/om-organization-service]] [[../rpc/om-user-account-service]]
[[../resources/iam-account]] [[../KAC/KAC-124]]

#packages #proto #kacho-rm #deprecated
