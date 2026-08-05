---
title: rm-domain
category: packages
repo: kacho-resource-manager
layer: domain
status: deprecated
tags:
  - packages
  - kacho-rm
  - domain
  - deprecated
---

> [!warning] Пакет снят вместе со своим репозиторием (KAC-124)
> Репозитория resource-manager не существует; в монорепо продукта каталога этого
> сервиса нет. Ниже — след, а не описание действующего пакета.

# rm-domain — снят (KAC-124)

Слой сущностей снятого сервиса: чистые типы организации, облака и папки, без
импорта proto и хранилища.

## Что снято из этой записки

Перечень файлов удалён — он называл исходники, которых в дереве нет. Соглашение,
на которое записка ссылалась (самопроверяющиеся конструкторы, сравнение для
диффа, отсутствие импортов транспорта), остаётся общим для платформы и описано
на действующих доменных пакетах, например [[vpc-domain]].

## See also

[[vpc-domain]] [[rm-service]] [[../resources/rm-organization]]
[[../resources/rm-cloud]] [[../resources/rm-folder]] [[../KAC/KAC-124]]

#packages #kacho-rm #domain #deprecated
