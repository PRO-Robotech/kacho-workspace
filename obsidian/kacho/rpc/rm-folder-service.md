---
title: FolderService
aliases:
  - FolderService (rm)
  - FolderService (resourcemanager)
category: rpc
backend: kacho-resource-manager
visibility: public
domain: resourcemanager
status: deprecated
related_resource: "[[resources/rm-folder]]"
tags:
  - rpc
  - kacho-rm
  - folder
  - deprecated
---

> [!warning] Сервис снят вместе со своим доменом (KAC-124)
> Ни этого сервиса, ни его домена в дереве продукта нет: объявления сервиса в
> proto не существует, каталога домена тоже. REST-префикс, который он занимал,
> шлюзом не обслуживается. Преемник — ProjectService в iam
> ([[iam-project-service]]).

# FolderService — снят (KAC-124)

Читающий сервис нижнего уровня прежней иерархии арендатора. Его звали доменные
сервисы (сеть, вычисления, балансировщик), чтобы проверить существование
владельца ресурса; сам он не звал никого — был листом графа обращений.

## Чем заменён

Проверка владельца ушла на проект в iam: тот же рисунок вызова (сверка
существования у владельца на пути запроса, отказ закрытым при недоступности),
другой домен. См. [[../edges/vpc-to-iam-project-exists]] и, как исторический
след прежнего ребра, [[../edges/vpc-to-rm-folder-exists]].

## Что снято из этой записки

Таблица методов и таблица соответствия REST удалены вместе с полями шапки,
называвшими файл proto и адрес бэкенда. Они описывали поверхность, которой в
дереве нет, и читались как утверждение о действующем API. Числа методов из шапки
убраны по той же причине: пересчитать их не по чему.

## See also

[[iam-project-service]] [[../resources/rm-folder]] [[../packages/rm-service]]
[[../edges/vpc-to-rm-folder-exists]] [[../edges/compute-to-rm-folder-check]]
[[../KAC/KAC-124]]

#rpc #kacho-rm #folder #deprecated
