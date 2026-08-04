---
title: proto-api
category: packages
repo: kacho-proto
path: proto/kacho/cloud/api
layer: proto
status: stable
tags:
  - proto
  - api
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# proto/kacho/cloud/api — аннотация метода, а НЕ архив

**Каталог**: `proto/kacho/cloud/api/` (файл `operation.proto`)
**Пакет контракта**: `kacho.cloud.api`
**Go-импорт**: `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/api`
**Импортируют** (`go list` на `96b2879a`): сгенерённые пакеты **семи** доменов —
compute, geo, iam, loadbalancer, registry, storage, vpc.

> [!warning] Это не «старая версия конверта операции», и удалять его нельзя
> Прежняя редакция объявляла пакет legacy-алиасом конверта `Operation` «до выноса в
> отдельный домен» и предлагала снести при ближайшей уборке. По дереву — наоборот:
> `kacho.cloud.api.Operation` это **опция метода**, которой RPC объявляет, какими
> типами будут его `metadata` и `response`:
>
> ```protobuf
> import "kacho/cloud/api/operation.proto";
> rpc Create(...) returns (operation.Operation) {
>   option (kacho.cloud.api.operation) = { metadata: "...Metadata", response: "..." };
> }
> ```
>
> Оба поля — **строки с именами типов**, а не сам конверт. Пакет живой, его
> импортируют семь доменов, и снос по прежней записке сломал бы сборку контрактов
> всего дерева. Класс поучителен: совпадение имени сообщения (`Operation`) увело
> вывод в сторону, и запись «на удаление» прожила дольше, чем прожил бы её предмет.

Сам конверт длящейся операции живёт отдельно — [[proto-operation]].

#proto #api
