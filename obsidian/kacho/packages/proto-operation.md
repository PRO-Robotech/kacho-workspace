---
title: proto-operation
category: package
repo: kacho-proto
path: proto/kacho/cloud/operation
layer: proto
status: stable
tags:
  - proto
  - operation
  - lro
---

# proto/kacho/cloud/operation — конверт длящейся операции

**Каталог**: `proto/kacho/cloud/operation/`
**Пакет контракта**: `kacho.cloud.operation.v1`
**Go-импорт**: `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/operation`
(алиас `operationv1`; каталог **без** сегмента `v1`, хотя пакет контракта его несёт —
частая причина промаха при написании импорта вручную).

Возвращается **каждой** мутацией платформы; чтение синхронно.

## Форма сообщения (по дереву, `96b2879a`)

```protobuf
string id = 1;  string description = 2;
google.protobuf.Timestamp created_at = 3;  string created_by = 4;
google.protobuf.Timestamp modified_at = 5;  bool done = 6;
google.protobuf.Any metadata = 7;
oneof result { google.rpc.Status error = 8; google.protobuf.Any response = 9; }
string principal_type = 10;  string principal_id = 11;  string principal_display_name = 12;
```

Три поля личности инициатора (10-12) прежней редакции известны не были. Они
структурированные и **не** заменяют `created_by` (поле 4), оставленное ради
совместимости. Отображаемое имя — снимок на момент операции и может разойтись с
текущим значением у пользователя.

## Служба: `Get` и `Cancel`, но НЕ `List`

`OperationService` объявляет два метода. Прежняя редакция называла `List` — его нет.
Перечисление операций живёт у своих доменов (например, счётный поток по аккаунту в
iam), а не в этом контракте.

## Идентификатор в `metadata` присваивается при ПРИЁМЕ, а не при успехе

Контракт проговаривает это прямо, и это самая дорогая ловушка узла: идентификатор
целевого ресурса попадает в метаданные **до** выполнения работы, поэтому он
присутствует и у **провалившейся** операции — указывая на ресурс, которого нет.

Правильный порядок чтения: дождаться `done` → проверить, что `error` не установлен →
и только затем брать идентификатор. Иначе получается ресурс-фантом: его
идентификатор проникает в окружение проб и в последующие привязки, а обращение к
нему отдаёт «не найдено» либо, хуже, резолвится в посторонний ресурс. Ровно этот
класс ловится в дисциплине фикстур (`testing.md`).

## `done` — durability предмета, а не видимость последствий

`done=true` означает «ресурс закоммичен» и только это. Гейтить его на видимость
eventually-consistent последствия запрещено (`api-conventions.md`): это
переопределяет контракт и на fail-closed рождает тот же фантом.

## Таблица операций — у каждого сервиса своя

Общей таблицы нет; шлюз проксирует службу операций за каждым доменом
([[corelib-operations]]).

## См. также

[[corelib-operations]] [[proto-api]] [[../resources/operation]]
[[../rpc/operation-service]]

#proto #operation #lro
